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
import state
from gui import AutoSyncGUI, remote_to_github_web_url
from version import Version, parse

REASON_START = "Запуск"
REASON_PUSH = "Пуш"

# Служебные/временные файлы, которые НЕ должны триггерить коммит (см. IGNORE_PATTERNS ниже).
IGNORE_PATTERNS = [
    "*.tmp",
    ".*.tmp",
    "~$*",       # временные файлы Office и похожих программ
    "*.godot.import",
]

app: Optional[AutoSyncGUI] = None       # выставляется в main() — единственный экземпляр окна
observer: Optional[Observer] = None     # общий на всю программу — нужен для до/пере-регистрации слежения
cfg: dict = {}                          # текущая конфигурация — держим в памяти, чтобы дописывать/сохранять
config_path: str = "config.json"


def _is_ignored(filename: str) -> bool:
    return any(fnmatch.fnmatch(filename, pattern) for pattern in IGNORE_PATTERNS)


def _now_str() -> str:
    return datetime.now().strftime("%H:%M:%S %d/%m/%Y")


def log(repo_name: str, message: str) -> None:
    app.log(repo_name, message)


def _save_config() -> None:
    Path(config_path).write_text(json.dumps(cfg, ensure_ascii=False, indent=2), encoding="utf-8")


class RepoWatcher(FileSystemEventHandler):
    def __init__(self, repo_cfg: dict, dev_id: int, check_interval_minutes: int):
        self.repo_path = Path(repo_cfg["path"])
        self.branch = repo_cfg["branch"]
        self.name = repo_cfg["name"]
        self.watch_paths = list(repo_cfg["watch_paths"])
        self.dev_id = dev_id
        self._lock = threading.Lock()
        self._observed_watches: list = []  # для пере-регистрации слежения при смене пути

        self.check_interval_seconds = check_interval_minutes * 60
        self.next_check_at = time.time() + self.check_interval_seconds

        # known_version — версия, которую мы сами приняли/подтвердили в прошлый раз (state.py).
        # current_tag — что реально сейчас стоит на git, только для отображения в окне.
        self.known_version: Optional[str] = state.load_known_version(self.name)
        self.current_tag: str = self.known_version or "тегов ещё нет"

        self.last_check_time: str = "ещё не было"
        self.last_saved_at: str = "ещё не было"
        self.last_action: str = "ожидание"

        self.pending_question = None  # выставляется/снимается в gui.py (AutoSyncGUI)
        self._remote_url_cache: Optional[str] = None

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

    # --- события файловой системы ------------------------------------------------

    def on_modified(self, event):
        if event.is_directory:
            return
        filename = Path(event.src_path).name
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
                git_version = git_ops.latest_tag_on_branch(self.repo_path, self.branch)
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

    def _next_version(self) -> Version:
        base = self.known_version or self.current_tag
        if not base or base == "тегов ещё нет":
            return Version(
                stable=0, stable_patch=0, beta=0, beta_push=0,
                dev_id=self.dev_id, task_label=0, push_count=0,
            )
        prev = parse(base)
        return Version(
            stable=prev.stable, stable_patch=prev.stable_patch,
            beta=prev.beta, beta_push=prev.beta_push,
            dev_id=self.dev_id, task_label=prev.task_label, push_count=prev.push_count + 1,
            project_sync=prev.project_sync,
        )

    def manual_set_version(self, new_version: Version) -> None:
        """Ручное изменение версии (разработчик сам двигает Stable/Beta/task_label и т.п.) —
        push_count при этом всегда обнуляется: это начало нового отрезка версий, дальше он снова
        растёт автоматически по +1 на каждый пуш, как обычно.

        Разрешено ТОЛЬКО когда нет расхождения с git (известная нам версия и то, что реально на
        git, совпадают) — единственное, что должно меняться в этом действии, это обозначение
        версии, а не заодно ещё и разрешение какого-то незакрытого расхождения. Если расхождение
        есть — просим сначала разрешить его обычным путём (СВЕРКА_ВЕРСИЙ/ПРОЦЕСС_СЛИЯНИЯ_РАСХОЖДЕНИЙ),
        а не протаскиваем его через ручное изменение версии."""
        with self._lock:
            self.last_action = "проверяем расхождения перед ручным изменением версии..."
            log(self.name, "Проверка перед ручным изменением версии...")
            try:
                git_ops.fetch(self.repo_path)
                git_version = git_ops.latest_tag_on_branch(self.repo_path, self.branch)
            except git_ops.GitError as e:
                self.last_action = "нет связи с git — версия не изменена"
                log(self.name, f"Ручное изменение версии отменено: нет связи с git — {e}")
                return

            self.current_tag = git_version or "тегов ещё нет"
            if git_version != self.known_version:
                self.last_action = "есть расхождение с git — сначала разрешите его"
                log(self.name, "Ручное изменение версии отменено: есть расхождение с git, "
                                "сначала нужно его разрешить обычной проверкой")
                return

            new_version.push_count = 0
            self._action_push(
                reason=f"Ручное обновление версии: {new_version.format()}",
                explicit_version=new_version,
            )

    def _action_push(self, reason: str, force: bool = False, explicit_version: Optional[Version] = None) -> None:
        self.last_action = "передаём синхронизацию..."
        log(self.name, "Передаём синхронизацию (commit + push)...")

        try:
            if git_ops.has_local_changes(self.repo_path):
                git_ops.add_commit(self.repo_path, ["."], message=reason)
            if force:
                git_ops.push_force_with_lease(self.repo_path, self.branch)
            else:
                git_ops.push(self.repo_path, self.branch)
        except git_ops.GitError as e:
            self.last_check_time = _now_str()
            self.last_action = "ошибка коммита/пуша"
            log(self.name, f"Результат: ошибка при коммите/пуше — {e}")
            return

        # При ручном изменении версии используем версию, которую задал разработчик, а не
        # автоматически посчитанную следующую — но если её тег вдруг уже занят, всё равно не
        # сдаёмся (см. цикл ниже), просто едем по push_count дальше от неё.
        version = explicit_version if explicit_version is not None else self._next_version()
        tag = None
        for _ in range(50):
            tag = version.format()
            try:
                git_ops.create_and_push_tag(self.repo_path, tag, message=reason)
                break
            except git_ops.GitError:
                version.push_count += 1
                tag = None
        if tag is None:
            self.last_check_time = _now_str()
            self.last_action = "пуш прошёл, тег не поставлен"
            log(self.name, "Результат: код запушен, но свободный тег не найден за 50 попыток")
            return

        try:
            git_ops.fetch(self.repo_path)
            confirmed = git_ops.latest_tag_on_branch(self.repo_path, self.branch)
        except git_ops.GitError as e:
            self.last_action = "ошибка проверки после пуша"
            log(self.name, f"Результат: пуш прошёл, но проверка после пуша не удалась — {e}")
            return

        if confirmed == tag and not git_ops.has_local_changes(self.repo_path):
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
            git_version = git_ops.latest_tag_on_branch(self.repo_path, self.branch)
            if git_version:
                self._action_update_local(git_version)
        else:
            log(self.name, "Выбор пользователя: открыть mergetool")
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


def add_repo_runtime(repo_cfg: dict, interval_minutes: int):
    """Вызывается из окна (кнопка '+'): создать репозиторий, сохранить в config.json, начать
    следить. Версию не спрашиваем — она сама подтянется с git при первой проверке."""
    cfg.setdefault("repos", []).append(repo_cfg)
    _save_config()

    watcher = RepoWatcher(repo_cfg, cfg["dev_id"], interval_minutes)
    _register_watch(watcher)
    log(watcher.name, "Репозиторий добавлен — первичная проверка...")
    threading.Thread(target=watcher.sverka_versiy, args=(REASON_START,), daemon=True).start()
    return watcher


def edit_repo_runtime(watcher: RepoWatcher, branch: Optional[str] = None,
                       watch_path: Optional[str] = None) -> None:
    """Вызывается из окна (пункты 'Изменить...' в контекстных меню)."""
    for repo_cfg in cfg.get("repos", []):
        if repo_cfg["name"] != watcher.name:
            continue
        if branch:
            watcher.branch = branch
            repo_cfg["branch"] = branch
            watcher._remote_url_cache = None
        if watch_path:
            _unregister_watch(watcher)
            watcher.watch_paths = [watch_path]
            repo_cfg["watch_paths"] = [watch_path]
            _register_watch(watcher)
        break
    _save_config()
    log(watcher.name, "Настройки репозитория изменены")


def manual_version_change_runtime(watcher: RepoWatcher, new_version: Version) -> None:
    """Вызывается из окна ('Изменить версию...') — сама git-операция идёт в фоновом потоке,
    чтобы не подвешивать окно на время commit+push."""
    threading.Thread(target=watcher.manual_set_version, args=(new_version,), daemon=True).start()


def periodic_check_loop(watchers: list) -> None:
    while True:
        time.sleep(1)
        now = time.time()
        for w in watchers:
            if now >= w.next_check_at:
                w.next_check_at = now + w.check_interval_seconds
                log(w.name, "Плановая (периодическая) проверка...")
                w.sverka_versiy(REASON_START)


def _background_start(watchers: list) -> None:
    for w in watchers:
        _register_watch(w)
    observer.start()

    for w in watchers:
        log(w.name, "Первичная проверка синхронизации с GitHub...")
        w.sverka_versiy(REASON_START)

    threading.Thread(target=periodic_check_loop, args=(watchers,), daemon=True).start()


def main(config_path_: str = "config.json") -> None:
    global app, observer, cfg, config_path
    config_path = config_path_
    cfg = json.loads(Path(config_path).read_text(encoding="utf-8"))
    dev_id = cfg["dev_id"]
    default_interval = cfg["check_interval_minutes"]

    observer = Observer()
    watchers = [RepoWatcher(repo_cfg, dev_id, default_interval) for repo_cfg in cfg["repos"]]

    app = AutoSyncGUI(
        watchers,
        on_add_repo=add_repo_runtime,
        on_edit_repo=edit_repo_runtime,
        on_manual_version_change=manual_version_change_runtime,
    )

    # Слежение и проверки идут в фоне, окно — на главном потоке (обязательное требование tkinter).
    threading.Thread(target=_background_start, args=(watchers,), daemon=True).start()

    app.run()  # блокирует до закрытия окна


if __name__ == "__main__":
    main()
