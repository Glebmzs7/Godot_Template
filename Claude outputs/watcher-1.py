"""
AutoSync — основной процесс демона.

Вся логика собрана вокруг ОДНОЙ функции — СВЕРКА_ВЕРСИЙ (в коде: RepoWatcher.sverka_versiy) —
её вызывает и живое сохранение файла, и периодическая проверка (у каждого репозитория свой
интервал — можно задать по правому клику на обратный отсчёт в окне), и старт программы. Разница
только в параметре "причина": "Пуш" (файл только что живьём сохранён — пушим сразу, без
вопросов) или "Запуск" (обычный повод — если тут находятся незарегистрированные изменения,
сначала спрашиваем пользователя).

СВЕРКА_ВЕРСИЙ:
    1. Смотрим версию, которую мы сами в прошлый раз подтвердили (known_version, state.py).
    2. git fetch. Не получилось — ДЕЙСТВИЕ_ОШИБКА_СВЯЗИ.
    3. Смотрим, какая версия сейчас реально на git (current_tag — для строки в окне).
    4. Сравниваем known_version с git-версией:
       - Совпало (в т.ч. когда обеих нет вообще):
           - есть локальные изменения:
               - причина "Пуш" -> ДЕЙСТВИЕ_ПУШ сразу
               - причина "Запуск" -> ДЕЙСТВИЯ_ОЖИДАНИЯ_РЕШЕНИЯ_ПО_ПРЕДЛОЖЕНИЮ -> (да) ДЕЙСТВИЕ_ПУШ
           - нет изменений -> ДЕЙСТВИЕ_ПРОДОЛЖИТЬ_СЛЕЖЕНИЕ
       - Не совпало:
           - known_version, который мы помним, уже не существует как тег на git -> ПРОЦЕСС_СЛИЯНИЯ_РАСХОЖДЕНИЙ
           - иначе (git реально ушёл вперёд):
               - нет локальных изменений -> ДЕЙСТВИЯ_ОЖИДАНИЯ_РЕШЕНИЯ_ПО_ПРЕДЛОЖЕНИЮ -> (да) ДЕЙСТВИЕ_ОБНОВИТЬ_ЛОКАЛЬНО
               - есть локальные изменения -> ПРОЦЕСС_СЛИЯНИЯ_РАСХОЖДЕНИЙ

ДЕЙСТВИЯ_ОЖИДАНИЯ_РЕШЕНИЯ_ПО_ПРЕДЛОЖЕНИЮ (gui.ask_yes_no) и ПРОЦЕСС_СЛИЯНИЯ_РАСХОЖДЕНИЙ
(gui.ask_choice) — блокирующие вопросы: поток стоит на месте, пока не будет ответа. Но теперь
диалог можно закрыть крестиком, не отвечая, — это НЕ "нет", репозиторий просто помечается
красным (см. gui.py — watcher.pending_question), и клик по красной строке в окне открывает
диалог заново.

ДЕЙСТВИЕ_ПУШ включает и саму отправку, и проверку результата: коммит + пуш + тег -> заново
спрашиваем git, что там теперь -> если совпало и рабочее дерево чистое — принимаем версию и
запускаем СВЕРКА_ВЕРСИЙ("Запуск") заново; если не совпало — ПРОЦЕСС_СЛИЯНИЯ_РАСХОЖДЕНИЙ.
"""

import json
import fnmatch
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

import git_ops
import notifier
import repo_data
import self_update
import state
import version
from gui import AutoSyncGUI, remote_to_github_web_url

REASON_START = "Запуск"
REASON_PUSH = "Пуш"

# Служебные/временные файлы, которые НЕ должны триггерить коммит (см. IGNORE_PATTERNS ниже).
IGNORE_PATTERNS = [
    "*.tmp",
    ".*.tmp",
    "~$*",       # временные файлы Office и похожих программ
    "*.godot.import",
]

# Папка самой программы AutoSync (там, где лежит этот watcher.py). Если она физически оказалась
# ВНУТРИ отслеживаемого пути (как сейчас — Tools/AutoSync лежит внутри "Сам проект\Godot_Template",
# которую и стережём) — свои же служебные файлы (autosync.log, state.json, __pycache__/*.pyc,
# autosync_crash.log) были бы триггером собственного пуша программы саму на себя: лог пишется на
# КАЖДОЕ сообщение, из-за чего запись в лог сама вызывала новую проверку/пуш, которая снова что-то
# логировала, и т.д. — отсюда и подозрительные версии/теги. Файлы самой программы из слежения
# полностью исключаем, независимо от имени.
_AUTOSYNC_DIR = Path(__file__).resolve().parent

app: Optional[AutoSyncGUI] = None       # выставляется в main() — единственный экземпляр окна
observer: Optional[Observer] = None     # общий на всю программу — нужен для до/пере-регистрации слежения
cfg: dict = {}                          # текущая конфигурация — держим в памяти, чтобы дописывать/сохранять
config_path: str = "config.json"


def _is_ignored(filename: str) -> bool:
    return any(fnmatch.fnmatch(filename, pattern) for pattern in IGNORE_PATTERNS)


# Папки, которые НИКОГДА не должны триггерить пуш, независимо от того, что именно в них
# изменилось — не маски имён файлов (это IGNORE_PATTERNS выше), а целые папки, узнаваемые по
# имени на любом уровне пути (см. on_modified). ".git" и папка данных repo_data.py —
# обязательные, их нельзя убрать даже правкой config.json (см. комментарий в on_modified).
_MANDATORY_IGNORED_FOLDERS = {".git", repo_data.DATA_DIRNAME}


def _ignored_folders() -> set:
    """Объединяет обязательный список с необязательным config["ignored_folders"] — пользователь
    может дописывать туда свои папки сам, правкой config.json, без изменения кода программы."""
    return _MANDATORY_IGNORED_FOLDERS | set(cfg.get("ignored_folders", []))


def _now_str() -> str:
    return datetime.now().strftime("%H:%M:%S %d/%m/%Y")


def log(repo_name: str, message: str) -> None:
    app.log(repo_name, message)


def _log_git_command(repo_path: Path, command: str) -> None:
    """Прокидывается в git_ops.py (см. set_command_logger) — программа запускается без консоли
    (AutoSync.pyw), поэтому это единственный способ показать пользователю в журнале, какие именно
    git-команды выполняются, не только итоговый результат."""
    log(Path(repo_path).name, f"git {command}")


git_ops.set_command_logger(_log_git_command)


def _save_config() -> None:
    Path(config_path).write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


class RepoWatcher(FileSystemEventHandler):
    def __init__(self, repo_cfg: dict, dev_id: int, check_interval_seconds: int):
        self.repo_path = Path(repo_cfg["path"])
        self.branch = repo_cfg["branch"]
        self.name = repo_cfg["name"]
        self.watch_paths = list(repo_cfg["watch_paths"]) or [""]
        self.dev_id = dev_id
        self._lock = threading.Lock()
        self._observed_watches: list = []  # для пере-регистрации слежения при смене пути

        self.check_interval_seconds = check_interval_seconds
        self.next_check_at = time.time() + self.check_interval_seconds

        # Работает/остановлена — ручной переключатель (кнопка в строке окна), сохраняется в
        # config.json как "enabled", чтобы состояние переживало перезапуск программы. Старых
        # config.json без этого поля это не касается — по умолчанию считаем, что репозиторий
        # запущен (как было всегда).
        self.running: bool = repo_cfg.get("enabled", True)

        # known_version — версия, которую мы сами приняли/подтвердили в прошлый раз (state.py).
        # current_tag — что реально сейчас стоит на git, только для отображения в окне.
        self.known_version: Optional[str] = state.load_known_version(self.name)
        self.current_tag: str = self.known_version or "тегов ещё нет"

        self.last_check_time: str = "ещё не было"
        self.last_saved_at: str = "ещё не было"
        self.last_action: str = "ожидание"

        self.pending_question = None  # выставляется/снимается в gui.py (AutoSyncGUI)
        self._remote_url_cache: Optional[str] = None

        # Данные репозитория (ветка/интервал/версия) дублируются ВНУТРИ самого репозитория —
        # см. repo_data.py — чтобы "путешествовать" вместе с проектом на другую машину.
        # Расхождение с центральным config.json/state.json не разрешаем сами — спрашиваем
        # пользователя (см. _reconcile_repo_data_on_start/resolve_repo_data_conflict,
        # gui.py — ask_repo_data_conflict; сам вопрос задаётся из _background_start, а не
        # отсюда — на этом шаге окно AutoSyncGUI ещё не создано).
        self._repo_data_conflict: Optional[dict] = None  # {"central": {...}, "folder": {...}}
        self._reconcile_repo_data_on_start()

    @property
    def full_watch_path(self) -> Path:
        return self.repo_path / self.watch_paths[0]

    def git_web_url(self) -> Optional[str]:
        if self._remote_url_cache is None:
            self._remote_url_cache = git_ops.remote_url(self.repo_path) or ""
        if not self._remote_url_cache:
            return None
        return remote_to_github_web_url(self._remote_url_cache, self.branch)

    def _accept_version(self, tag: str) -> None:
        self.known_version = tag
        state.save_known_version(self.name, tag)
        self.current_tag = tag
        self.last_saved_at = _now_str()
        self._save_repo_data()

    # --- дублирование данных репозитория в .autosync_data (repo_data.py) --------------------

    def _central_repo_data(self) -> dict:
        return {
            "name": self.name,
            "branch": self.branch,
            "check_interval_minutes": round(self.check_interval_seconds / 60),
            "known_version": self.known_version,
        }

    def _save_repo_data(self) -> None:
        try:
            repo_data.save(self.repo_path, saved_at=_now_str(), **self._central_repo_data())
        except OSError as e:
            log(self.name, f"Не удалось записать данные в папку проекта (.autosync_data): {e}")

    def _reconcile_repo_data_on_start(self) -> None:
        """Вызывается один раз при создании RepoWatcher (запуск программы или добавление нового
        репозитория). Если .autosync_data ещё нет — создаём из текущих данных (для нового
        репозитория это и есть "перенос данных" — делается автоматически, без ручных команд).
        Если есть, но расходится — ничего не решаем сами, только запоминаем расхождение;
        сам вопрос пользователю задаётся позже, из _background_start (см. там)."""
        # Автоматически поддерживаем исключение .autosync_data/ в .gitignore репозитория — не
        # коммитим этот файл в git (у каждого пользователя своя ветка), и делаем это без ручной
        # правки .gitignore при каждом новом репозитории (см. repo_data.ensure_gitignore_entry).
        repo_data.ensure_gitignore_entry(self.repo_path)

        central = self._central_repo_data()
        try:
            folder = repo_data.load(self.repo_path)
        except OSError:
            folder = None

        if folder is None:
            self._save_repo_data()
            return

        if repo_data.matches(folder, central):
            return

        log(self.name, "Данные в .autosync_data (в папке проекта) расходятся с config.json — нужен выбор")
        self._repo_data_conflict = {"central": central, "folder": folder}

    def resolve_repo_data_conflict(self, take: str) -> None:
        """take == 'central' (общий config.json) или 'folder' (.autosync_data в папке проекта).
        Вызывается из watcher._ask_repo_data_conflict после ответа пользователя в окне."""
        conflict = self._repo_data_conflict
        self._repo_data_conflict = None
        if conflict is None:
            return

        if take == "folder":
            folder = conflict["folder"]
            new_branch = folder.get("branch") or self.branch
            self.branch = new_branch
            self._remote_url_cache = None

            interval_min = folder.get("check_interval_minutes")
            if interval_min:
                self.check_interval_seconds = interval_min * 60
                self.next_check_at = time.time() + self.check_interval_seconds

            known = folder.get("known_version")
            if known:
                self.known_version = known
                state.save_known_version(self.name, known)
                self.current_tag = known

            for repo_cfg in cfg.get("repos", []):
                if repo_cfg["name"] == self.name:
                    repo_cfg["branch"] = self.branch
                    break
            _save_config()
            log(self.name, "Выбор пользователя: взять данные из папки проекта (.autosync_data)")
        else:
            log(self.name, "Выбор пользователя: оставить данные из общего config.json")

        self._save_repo_data()
        _run_check(self, REASON_START, "Первичная проверка синхронизации с GitHub...")

    # --- события файловой системы ------------------------------------------------

    def on_modified(self, event):
        if not self.running:
            return  # на всякий случай — по идее watch уже снят, событие сюда не должно прийти
        if event.is_directory:
            return

        src_path = Path(event.src_path)
        try:
            src_path.resolve().relative_to(_AUTOSYNC_DIR)
            return  # это собственный служебный файл AutoSync (лог/состояние/кэш) — не код проекта
        except ValueError:
            pass  # путь не внутри папки AutoSync — обычное событие, обрабатываем как раньше

        # Целые служебные папки, которые не должны триггерить пуш ни при каких обстоятельствах —
        # не по имени файла (см. IGNORE_PATTERNS/_is_ignored ниже), а по имени папки на ЛЮБОМ
        # уровне пути. ".git" и ".autosync_data" — обязательные (нельзя убрать даже правкой
        # config.json): ".git" сам постоянно меняет свои файлы (FETCH_HEAD, logs/HEAD) при каждом
        # нашем же git fetch — без исключения это давало бесконечный цикл проверок при слежении за
        # ВСЕЙ папкой репозитория (найдено 21.09 на Life_Operator — по несколько циклов в секунду);
        # ".autosync_data" — наша же папка с данными репозитория (repo_data.py), по той же причине.
        # Остальное — необязательный список из config.json ("ignored_folders"), пользователь может
        # дописывать туда свои папки сам, без правки кода (например ".godot", "__pycache__" и т.п.).
        if any(part in _ignored_folders() for part in src_path.parts):
            return

        filename = src_path.name
        if _is_ignored(filename):
            return
        log(self.name, f"Есть материал для пуша: {event.src_path}")
        self.sverka_versiy(REASON_PUSH)

    # --- СВЕРКА_ВЕРСИЙ и действия ---------------------------------------------------

    def sverka_versiy(self, reason: str) -> None:
        with self._lock:  # чтобы два быстрых сохранения подряд не гонялись за git одновременно
            self.last_action = "обращаемся к серверу..."
            log(self.name, "Обращаемся к серверу (git fetch)...")

            try:
                git_ops.fetch(self.repo_path)
                # Смотрим тег именно на origin/<branch> (реально то, что на git ПОСЛЕ fetch), а
                # не на локальной ветке — fetch сам по себе локальную ветку не двигает, поэтому
                # раньше здесь можно было увидеть устаревший тег и решить, что "версии совпали",
                # хотя реально git уже ушёл вперёд (или наоборот).
                git_version = git_ops.latest_tag_on_branch(self.repo_path, f"origin/{self.branch}")
            except git_ops.GitError as e:
                self._action_error_connection(reason, e)
                return

            self.current_tag = git_version or "тегов ещё нет"

            if git_version == self.known_version:
                self._branch_matched(reason)
                return

            if self.known_version is not None and not git_ops.tag_exists(self.repo_path, self.known_version):
                log(self.name, "Известная нам версия не найдена на git — расхождение, нужен выбор")
                self._process_slияniya_raskhozhdeniy(reason)
                return

            self._branch_git_ahead(reason, git_version)

    def _branch_matched(self, reason: str) -> None:
        if not git_ops.has_local_changes(self.repo_path):
            self.last_check_time = _now_str()
            self.last_action = "актуально, изменений нет"
            log(self.name, "Результат: локальных изменений не найдено, пуш не нужен")
            return

        if reason == REASON_PUSH:
            self._action_push(reason)
            return

        self.last_action = "есть незафиксированные изменения — нужен ответ"
        log(self.name, "Найдены незафиксированные локальные изменения")
        if app.ask_yes_no(self, f"[{self.name}] Есть незафиксированные изменения. Запушить их?"):
            self._action_push(reason)
        else:
            self.last_check_time = _now_str()
            self.last_action = "изменения найдены, пуш отложен пользователем"
            log(self.name, "Пользователь отложил пуш")

    def _branch_git_ahead(self, reason: str, git_version: Optional[str]) -> None:
        if not git_ops.has_local_changes(self.repo_path):
            self.last_action = "на git есть более новая версия — нужен ответ"
            log(self.name, f"На git версия {git_version}, у нас {self.known_version} — нужен ответ")
            if app.ask_yes_no(self, f"[{self.name}] На git есть более новая версия {git_version}. Обновить локально?"):
                self._action_update_local(git_version)
            else:
                self.last_check_time = _now_str()
                self.last_action = "есть новая версия на git, обновление отложено"
                log(self.name, "Пользователь отложил обновление")
        else:
            log(self.name, "На git есть новая версия, и локально тоже есть изменения — нужен выбор")
            self._process_slияniya_raskhozhdeniy(reason)

    def _action_error_connection(self, reason: str, error: Exception) -> None:
        self.last_check_time = _now_str()
        self.last_action = "нет связи с git"
        log(self.name, f"Результат: нет связи с git — {error}")
        if app.ask_yes_no(self, f"[{self.name}] Нет связи с git. Повторить попытку?"):
            self.sverka_versiy(reason)

    def _action_update_local(self, git_version: str) -> None:
        git_ops.reset_hard(self.repo_path, f"origin/{self.branch}")
        self._accept_version(git_version)
        self.last_check_time = _now_str()
        self.last_action = "обновлено с git"
        log(self.name, f"Результат: обновлено с git до {git_version}")

    def manual_set_version(self, new_prefix: str) -> None:
        """Ручное изменение версии — разработчик просто вписывает любой текст (никакого формата
        не требуется, хоть 'HJDF3123Hj0'), push_count при этом обнуляется и дальше снова растёт
        сам по +1 на каждый пуш.

        Это осознанно принудительное действие (force-with-lease) — сделано так, а не с отказом
        при расхождении: если разработчик явно вписал версию и нажал "Применить", значит его
        решение и есть новая истина, независимо от того, что раньше застряло на git (в том числе
        если там повис старый некорректный тег, который иначе было не поправить из программы)."""
        with self._lock:
            log(self.name, f"Ручное изменение версии на {new_prefix!r}...")
            try:
                git_ops.fetch(self.repo_path)
            except git_ops.GitError as e:
                self.last_action = "нет связи с git — версия не изменена"
                log(self.name, f"Ручное изменение версии отменено: нет связи с git — {e}")
                return
            self._action_push(
                reason=f"Ручное обновление версии: {new_prefix}",
                force=True,
                explicit_prefix=new_prefix,
            )

    def _action_push(self, reason: str, force: bool = False, explicit_prefix: Optional[str] = None) -> None:
        self.last_action = "передаём синхронизацию..."
        log(self.name, "Передаём синхронизацию (commit + push)...")

        try:
            if git_ops.has_local_changes(self.repo_path):
                git_ops.add_commit(self.repo_path, ["."], message=reason)
        except git_ops.GitError as e:
            self.last_check_time = _now_str()
            self.last_action = "ошибка коммита"
            log(self.name, f"Результат: ошибка при коммите — {e}")
            return

        # Версия — это просто префикс (любой текст) + свой номер пуша (version.py). При ручном
        # изменении префикс задан явно и push_count начинается с 0; иначе берём то, что уже
        # знаем, и увеличиваем номер пуша на 1. Если конкретный тег вдруг уже занят на git — не
        # сдаёмся (см. цикл ниже), просто едем по номеру пуша дальше.
        if explicit_prefix is not None:
            prefix, push_count = explicit_prefix, 0
        else:
            base = self.known_version or self.current_tag
            if not base or base == "тегов ещё нет":
                prefix, push_count = str(self.dev_id), 0
            else:
                prefix, prev_push = version.split_prefix_and_push(base)
                push_count = prev_push + 1

        # ВАЖНО: ветка и тег пушатся ОДНОЙ атомарной командой (git_ops.push_atomic — git push
        # --atomic). Либо GitHub принимает и код, и тег сразу вместе, либо (коллизия тега на
        # сервере, разрыв связи, отклонение сервером и т.п.) — НИ ОДИН из них. Раньше это были
        # два отдельных push подряд: код мог уйти на сервер, а вот тег — не успеть (например,
        # кончились 50 попыток на свободный номер), и тогда коммит оставался на GitHub БЕЗ
        # версии. Это прямо запрещено: код без тега на сервере появиться не должен ни при каких
        # обстоятельствах.
        tag = None
        for _ in range(50):
            candidate = version.build_tag(prefix, push_count)
            try:
                git_ops.create_tag(self.repo_path, candidate, message=reason)
            except git_ops.GitError:
                push_count += 1  # локальная коллизия имени тега — пробуем следующий номер
                continue
            try:
                git_ops.push_atomic(self.repo_path, self.branch, candidate, force=force)
                tag = candidate
                break
            except git_ops.GitError:
                # Атомарный пуш отклонён целиком — локальный тег убираем (иначе он будет мешать
                # следующей попытке) и пробуем следующий номер.
                git_ops.delete_local_tag(self.repo_path, candidate)
                push_count += 1
        if tag is None:
            self.last_check_time = _now_str()
            self.last_action = "ошибка коммита/пуша"
            log(
                self.name,
                "Результат: атомарный пуш (код+тег) не удался за 50 попыток — на сервер НЕ "
                "ушло ничего, код остался только локально до следующей попытки",
            )
            return

        # Проверяем ПО КОММИТУ (rev-parse), а не по "последнему тегу веткиHEAD" (git describe) —
        # раньше здесь сравнивали confirmed_tag == tag через git_ops.latest_tag_on_branch
        # (git describe --tags --abbrev=0). Это ломалось всякий раз, когда пуш не создавал новый
        # коммит (например ручное изменение версии без реальных файловых изменений, force-push
        # без нового содержимого) — тег вешался на УЖЕ существующий коммит, у которого мог быть и
        # старый тег, и describe был не обязан вернуть именно наш новый тег (какой из нескольких
        # тегов на одном коммите он выберет — не гарантировано). Из-за этого проверка постоянно
        # решала "версия не совпала" и уходила в слияние по кругу, даже после force-push
        # ("оставить локальную версию") — именно это и было зацикливание у Life_Operator.
        # Раз push_atomic() уже не бросил ошибку — и ветка, и тег гарантированно приняты сервером
        # ОДНОЙ операцией; остаётся проверить только то, что реально может быть не так: что HEAD
        # действительно совпадает с origin/<ветка> и что за время пуша не появилось новых
        # локальных изменений (гонка с сохранением файла).
        try:
            git_ops.fetch(self.repo_path)
            local_head = git_ops.rev_parse(self.repo_path, "HEAD")
            remote_head = git_ops.rev_parse(self.repo_path, f"origin/{self.branch}")
        except git_ops.GitError as e:
            self.last_action = "ошибка проверки после пуша"
            log(self.name, f"Результат: пуш прошёл, но проверка после пуша не удалась — {e}")
            return

        if local_head == remote_head and not git_ops.has_local_changes(self.repo_path):
            self._accept_version(tag)
            self.last_check_time = _now_str()
            self.last_action = "синхронизировано"
            log(self.name, f"Результат: синхронизировано, {tag}")
            self.sverka_versiy(REASON_START)
        else:
            log(self.name, "После пуша версия/файлы не совпали с ожиданием — уходим в слияние")
            self._process_slияniya_raskhozhdeniy(reason)

    def _process_slияniya_raskhozhdeniy(self, reason: str) -> None:
        self.last_action = "расхождение — нужен выбор"
        diff = git_ops.diff_name_status(self.repo_path, self.branch, f"origin/{self.branch}")
        choice = app.ask_choice(self, self.branch, diff)

        if choice == notifier.SyncChoice.TAKE_LOCAL:
            log(self.name, "Выбор пользователя: оставить локальную версию (force-push)")
            self._action_push(reason, force=True)
            return
        elif choice == notifier.SyncChoice.TAKE_GIT:
            log(self.name, "Выбор пользователя: взять версию с git")
            git_version = git_ops.latest_tag_on_branch(self.repo_path, f"origin/{self.branch}")
            if git_version:
                self._action_update_local(git_version)
        else:
            log(self.name, "Выбор пользователя: открыть mergetool")
            unmerged = git_ops.unmerged_files(self.repo_path)
            if not unmerged:
                log(
                    self.name,
                    "Внимание: git не видит файлов в состоянии реального конфликта — mergetool, "
                    "скорее всего, откроется и сразу закроется сам (показывать нечего). Это не "
                    "ошибка mergetool — открываем его всё равно, на случай если git считает иначе.",
                )
            git_ops.open_mergetool(self.repo_path)
            log(self.name, "Mergetool закрыт — перепроверяем состояние")

        self.sverka_versiy(REASON_START)


def _register_watch(watcher: RepoWatcher) -> None:
    for rel_path in watcher.watch_paths:
        full_path = watcher.repo_path / rel_path
        watch = observer.schedule(watcher, str(full_path), recursive=True)
        watcher._observed_watches.append(watch)


def _unregister_watch(watcher: RepoWatcher) -> None:
    for watch in watcher._observed_watches:
        try:
            observer.unschedule(watch)
        except KeyError:
            pass
    watcher._observed_watches.clear()


def add_repo_runtime(repo_cfg: dict, interval_seconds: int):
    """Вызывается из окна (кнопка '+'): создать репозиторий, сохранить в config.json, начать
    следить. Версию не спрашиваем — она сама подтянется с git при первой проверке."""
    cfg.setdefault("repos", []).append(repo_cfg)
    _save_config()

    watcher = RepoWatcher(repo_cfg, cfg["dev_id"], interval_seconds)
    _register_watch(watcher)
    log(watcher.name, "Репозиторий добавлен — первичная проверка...")
    threading.Thread(target=watcher.sverka_versiy, args=(REASON_START,), daemon=True).start()
    return watcher


def edit_repo_runtime(watcher: RepoWatcher, name: Optional[str] = None, path: Optional[str] = None,
                       branch: Optional[str] = None, watch_path: Optional[str] = None,
                       interval_seconds: Optional[int] = None) -> None:
    """Вызывается из окна (отдельные пункты 'Изменить...' в контекстных меню, и полное окно
    'Изменить репозиторий...' по правому клику на строке — оно может прислать сразу все поля)."""
    old_name = watcher.name
    for repo_cfg in cfg.get("repos", []):
        if repo_cfg["name"] != old_name:
            continue

        needs_rewatch = bool(path) or (watch_path is not None)
        if needs_rewatch:
            _unregister_watch(watcher)

        if name and name != old_name:
            watcher.name = name
            repo_cfg["name"] = name
            # известная версия хранится в state.json по имени — переносим на новое, чтобы
            # переименование не выглядело как "версия сбросилась"
            known = state.load_known_version(old_name)
            if known is not None:
                state.save_known_version(name, known)
        if path:
            watcher.repo_path = Path(path)
            repo_cfg["path"] = path
            watcher._remote_url_cache = None
        if branch:
            watcher.branch = branch
            repo_cfg["branch"] = branch
            watcher._remote_url_cache = None
        if watch_path is not None:  # пустая строка — осознанный выбор "следить за всей папкой"
            watcher.watch_paths = [watch_path]
            repo_cfg["watch_paths"] = [watch_path]
        if interval_seconds:
            watcher.check_interval_seconds = interval_seconds
            watcher.next_check_at = time.time() + interval_seconds

        if needs_rewatch:
            _register_watch(watcher)
        break
    _save_config()
    watcher._save_repo_data()
    log(watcher.name, "Настройки репозитория изменены")


def set_repo_running_runtime(watcher: RepoWatcher, running: bool) -> None:
    """Кнопка в строке окна (зелёная 'Работает' / красная 'Остановлена'). При остановке снимаем
    слежение watchdog и репозиторий просто пропускается в периодических проверках — не трогаем
    известную версию и ничего не пушим. При включении — сразу перерегистрируем слежение и
    запускаем проверку, как при старте программы. Состояние сохраняется в config.json, чтобы
    пережить перезапуск.

    ВАЖНО: _register_watch/_unregister_watch (watchdog observer.schedule/unschedule) уходят в
    отдельный поток, а не выполняются прямо здесь. Раньше unschedule вызывался прямо в обработчике
    кнопки (главный поток GUI) — а unschedule останавливает и ДОЖИДАЕТСЯ (join) поток-эмиттер
    этого репозитория. Если у репозитория в этот момент шла git-операция (fetch/push) или был
    открыт диалог с вопросом пользователю (эмиттер стоит внутри on_modified -> sverka_versiy,
    ожидая git или ответа), join() не мог завершиться — а поскольку это происходило в главном
    потоке, зависало ВСЁ окно целиком (не только эта строка), пока операция/диалог не завершится
    сама по себе. Именно это и было 'нажал кнопку — программа зависла'. Теперь это ожидание идёт
    в фоне и не блокирует GUI; watcher.running выставляется СРАЗУ (см. on_modified и
    periodic_check_loop — они и так проверяют этот флаг первым делом), так что новые события по
    остановленному репозиторию перестают обрабатываться немедленно, даже пока сам unschedule ещё
    доигрывает в фоне."""
    for repo_cfg in cfg.get("repos", []):
        if repo_cfg["name"] == watcher.name:
            repo_cfg["enabled"] = running
            break
    _save_config()

    watcher.running = running
    if running:
        log(watcher.name, "Репозиторий включён — слежение возобновлено")
        threading.Thread(target=_start_watch_and_check, args=(watcher,), daemon=True).start()
    else:
        log(watcher.name, "Репозиторий остановлен пользователем — слежение и проверки приостановлены")
        threading.Thread(target=_unregister_watch, args=(watcher,), daemon=True).start()


def _start_watch_and_check(watcher: RepoWatcher) -> None:
    _register_watch(watcher)
    watcher.next_check_at = time.time() + watcher.check_interval_seconds
    _run_check(watcher, REASON_START, "Проверка после включения...")


def delete_repo_runtime(watcher: RepoWatcher) -> None:
    """Кнопка 'Удалить репозиторий...' в окне 'Изменить репозиторий...' (после двойного
    подтверждения). Ничего на диске не трогаем — только снимаем слежение, убираем запись из
    config.json и из окна. Снятие слежения — в фоне, по той же причине, что и у
    set_repo_running_runtime (unschedule может ждать текущую git-операцию/диалог)."""
    watcher.running = False
    for i, repo_cfg in enumerate(cfg.get("repos", [])):
        if repo_cfg["name"] == watcher.name:
            del cfg["repos"][i]
            break
    _save_config()
    log(watcher.name, "Репозиторий удалён из слежения пользователем")

    def _unwatch_and_remove() -> None:
        _unregister_watch(watcher)
        app.remove_row_for(watcher)

    threading.Thread(target=_unwatch_and_remove, daemon=True).start()


def manual_version_change_runtime(watcher: RepoWatcher, new_prefix: str) -> None:
    """Вызывается из окна ('Изменить версию...') — сама git-операция идёт в фоновом потоке,
    чтобы не подвешивать окно на время commit+push."""
    threading.Thread(target=watcher.manual_set_version, args=(new_prefix,), daemon=True).start()


def _run_check(w: "RepoWatcher", reason: str, start_message: str) -> None:
    log(w.name, start_message)
    w.sverka_versiy(reason)


def periodic_check_loop(watchers: list) -> None:
    # Раньше проверка каждого репозитория шла здесь же, синхронно, одна за другой. Если у
    # какого-то репозитория sverka_versiy зависала на вопросе пользователю (ask_yes_no/ask_choice
    # блокируют поток до ответа), весь цикл вставал — остальные репозитории тоже переставали
    # проверяться по расписанию, и обратный отсчёт у них визуально "замирал". Теперь каждая
    # сработавшая проверка уходит в свой отдельный поток, и ожидание ответа по одному репозиторию
    # не мешает ни таймерам, ни проверкам остальных.
    while True:
        time.sleep(1)
        now = time.time()
        for w in watchers:
            if not w.running:
                continue  # остановлен пользователем — пропускаем, таймер не двигаем
            if now >= w.next_check_at:
                w.next_check_at = now + w.check_interval_seconds
                threading.Thread(
                    target=_run_check, args=(w, REASON_START, "Плановая (периодическая) проверка..."),
                    daemon=True,
                ).start()


def _background_start(watchers: list) -> None:
    for w in watchers:
        if w.running:
            _register_watch(w)
    observer.start()

    # Первичная проверка каждого репозитория — тоже в своём потоке (см. периодический цикл выше):
    # раньше эти проверки шли последовательно ЗДЕСЬ, и если первый же репозиторий на старте
    # упирался в вопрос пользователю, поток periodic_check_loop вообще не запускался, пока на
    # этот вопрос кто-то не ответит — снаружи это выглядело как "программа зависла, отсчёт не
    # идёт". Теперь periodic_check_loop стартует сразу, независимо от того, ждут ли ответа
    # какие-то репозитории.
    #
    # Если для репозитория ещё на старте (в __init__ -> _reconcile_repo_data_on_start) нашлось
    # расхождение между config.json и .autosync_data в папке проекта — сперва спрашиваем
    # пользователя (окно AutoSyncGUI к этому моменту уже создано), обычная первичная проверка
    # для него запустится сама, уже после ответа (см. resolve_repo_data_conflict).
    for w in watchers:
        if not w.running:
            continue
        if w._repo_data_conflict is not None:
            threading.Thread(target=_ask_repo_data_conflict, args=(w,), daemon=True).start()
        else:
            threading.Thread(
                target=_run_check, args=(w, REASON_START, "Первичная проверка синхронизации с GitHub..."),
                daemon=True,
            ).start()

    threading.Thread(target=periodic_check_loop, args=(watchers,), daemon=True).start()


def _ask_repo_data_conflict(watcher: "RepoWatcher") -> None:
    conflict = watcher._repo_data_conflict
    if conflict is None:
        return
    choice = app.ask_repo_data_conflict(watcher, conflict["central"], conflict["folder"])
    watcher.resolve_repo_data_conflict(choice)


def _run_self_update_check() -> None:
    """Простые самостоятельные диалоги для ЗАПУСК_САМОЙ_ПРОГРАММЫ — отдельный tk.Tk() на время
    вопроса/сообщения (основное окно AutoSyncGUI ещё не создано на этом шаге)."""
    import tkinter as tk
    from tkinter import messagebox

    def ask_yes_no(message: str) -> bool:
        root = tk.Tk()
        root.withdraw()
        result = messagebox.askyesno("AutoSync — обновление", message)
        root.destroy()
        return result

    def notify_and_exit(message: str) -> None:
        root = tk.Tk()
        root.withdraw()
        messagebox.showinfo("AutoSync — обновление", message)
        root.destroy()

    # На этом шаге окна AutoSyncGUI ещё нет (app.log недоступен), поэтому пишем СРАЗУ в тот же
    # файл autosync.log, который окно читает при старте (gui.py: _load_log_history) — так шаги
    # самообновления видно и в самой программе, а не только в консоли (которой в .pyw-запуске и
    # вовсе нет). Пишем ДО создания окна, поэтому эти строки попадут в подгруженную "историю"
    # прямо перед меткой "── новый запуск программы ──", хоть и относятся к текущему запуску.
    log_path = Path(__file__).resolve().parent / "autosync.log"

    def log_update_step(message: str) -> None:
        line = f"[{datetime.now().strftime('%H:%M:%S')}] [AutoSync] {message}"
        print(line)
        try:
            with open(log_path, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError:
            pass  # запись в файл не критична — сама проверка обновления при этом не прерывается

    self_update.check_and_apply(ask_yes_no, notify_and_exit, log_update_step)


def main(config_path_: Optional[str] = None) -> None:
    global app, observer, cfg, config_path
    if config_path_ is None:
        # По умолчанию config.json ищем РЯДОМ С САМИМ watcher.py, а не в текущей рабочей папке —
        # раньше относительный путь "config.json" резолвился от того, откуда был запущен процесс,
        # и при запуске программы не из её собственной папки (например ярлыком, или если файлы
        # случайно оказались скопированы в другое место) она не находила свой config.json и
        # падала с FileNotFoundError, хотя реально файл лежал рядом с watcher.py/AutoSync.pyw.
        config_path_ = str(Path(__file__).resolve().parent / "config.json")
    config_path = config_path_
    cfg = json.loads(Path(config_path).read_text(encoding="utf-8"))
    dev_id = cfg["dev_id"]
    # config.json по-прежнему хранит интервал в минутах (не переписываем формат файла) — окно и
    # все интерактивные диалоги дальше работают в секундах, переводим только один раз здесь.
    default_interval = cfg["check_interval_minutes"] * 60

    # ЗАПУСК_САМОЙ_ПРОГРАММЫ (self_update.py) — проверяем обновление самого AutoSync ДО открытия
    # основного окна. Диалоги здесь простые, отдельные от таблицы репозиториев (у самообновления
    # нет своей строки) — временный tk.Tk() только на время вопроса/сообщения, сразу закрывается.
    _run_self_update_check()

    observer = Observer()
    watchers = [RepoWatcher(repo_cfg, dev_id, default_interval) for repo_cfg in cfg["repos"]]

    app = AutoSyncGUI(
        watchers,
        on_add_repo=add_repo_runtime,
        on_edit_repo=edit_repo_runtime,
        on_manual_version_change=manual_version_change_runtime,
        on_toggle_run=set_repo_running_runtime,
        on_delete_repo=delete_repo_runtime,
    )

    # Слежение и проверки идут в фоне, окно — на главном потоке (обязательное требование tkinter).
    threading.Thread(target=_background_start, args=(watchers,), daemon=True).start()

    app.run()  # блокирует до закрытия окна


if __name__ == "__main__":
    main()
