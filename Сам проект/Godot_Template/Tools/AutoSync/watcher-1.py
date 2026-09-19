"""
AutoSync — основной процесс демона.

Вся логика собрана вокруг ОДНОЙ функции — СВЕРКА_ВЕРСИЙ (в коде: RepoWatcher.sverka_versiy) —
её вызывает и живое сохранение файла, и периодическая проверка, и старт программы. Разница
только в параметре "причина": "Пуш" (файл только что живьём сохранён — пушим сразу, без
вопросов) или "Запуск" (обычный повод — старт/таймер/возврат из другого действия — если тут
находятся незарегистрированные изменения, сначала спрашиваем пользователя).

СВЕРКА_ВЕРСИЙ:
    1. Смотрим версию, которую мы сами в прошлый раз подтвердили (known_version, state.py).
    2. git fetch. Не получилось — ДЕЙСТВИЕ_ОШИБКА_СВЯЗИ.
    3. Смотрим, какая версия сейчас реально на git (current_tag — для строки статуса; None,
       если тегов ещё нет).
    4. Сравниваем known_version с git-версией:
       - Совпало (в т.ч. когда обеих нет вообще):
           - есть локальные изменения:
               - причина "Пуш" -> ДЕЙСТВИЕ_ПУШ сразу
               - причина "Запуск" -> ДЕЙСТВИЯ_ОЖИДАНИЯ_РЕШЕНИЯ_ПО_ПРЕДЛОЖЕНИЮ -> (да) ДЕЙСТВИЕ_ПУШ
           - нет изменений -> ДЕЙСТВИЕ_ПРОДОЛЖИТЬ_СЛЕЖЕНИЕ
       - Не совпало:
           - known_version, который мы помним, уже не существует как тег на git (пропуск/сбой,
             локально мы "уехали вперёд" несуществующего) -> ПРОЦЕСС_СЛИЯНИЯ_РАСХОЖДЕНИЙ
           - иначе (git реально ушёл вперёд по сравнению с тем, что мы знали):
               - нет локальных изменений -> ДЕЙСТВИЯ_ОЖИДАНИЯ_РЕШЕНИЯ_ПО_ПРЕДЛОЖЕНИЮ ->
                 (да) ДЕЙСТВИЕ_ОБНОВИТЬ_ЛОКАЛЬНО
               - есть локальные изменения -> ПРОЦЕСС_СЛИЯНИЯ_РАСХОЖДЕНИЙ

ДЕЙСТВИЯ_ОЖИДАНИЯ_РЕШЕНИЯ_ПО_ПРЕДЛОЖЕНИЮ — блокирующий вопрос (notifier.ask_yes_no): программа
именно ЖДЁТ ответа по этому репозиторию, а не откладывает до следующего повода. Отказ — просто
ничего не делаем в этот раз (следующий повод — файл/таймер — запустит проверку заново).

ДЕЙСТВИЕ_ПУШ включает в себя и саму отправку, и проверку результата одним действием: коммит +
пуш + тег -> заново спрашиваем git, что там теперь -> если совпало с ожидаемым и рабочее дерево
чистое — принимаем новую версию как известную и запускаем СВЕРКА_ВЕРСИЙ("Запуск") заново с чистого
листа; если не совпало — что-то пошло не так и это уже ПРОЦЕСС_СЛИЯНИЯ_РАСХОЖДЕНИЙ.

ПРОЦЕСС_СЛИЯНИЯ_РАСХОЖДЕНИЙ — показываем разницу и спрашиваем пользователя (notifier.ask_sync_choice,
готовый инструмент git, велосипед не изобретаем): оставить локальное (force-push + ДЕЙСТВИЕ_ПУШ),
взять git (ровно то же самое, что ДЕЙСТВИЕ_ОБНОВИТЬ_ЛОКАЛЬНО — не дублируем логику) или открыть
mergetool (после ручного слияния — СВЕРКА_ВЕРСИЙ("Запуск") заново).

В консоль выводится живой статус СТОЛБИКОМ (по строке на репозиторий), обновляется на месте через
ANSI-коды курсора. Весь консольный вывод (log/StatusBoard и вопросы пользователю в notifier.py)
идёт через одну общую блокировку (console_lock.py), чтобы ничего не портило другое.
"""

import fnmatch
import json
import os
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
from console_lock import LOCK as _console_lock
from version import Version, parse

REASON_START = "Запуск"
REASON_PUSH = "Пуш"

# Служебные/временные файлы, которые НЕ должны триггерить коммит.
# Пример из практики: Yandex Disk пишет файлы атомарно — сначала во временный
# ".<имя>.<pid>.<hash>.tmp", потом переименовывает в целевой файл. Событие на сам
# переименованный файл всё равно придёт отдельно и обработается как обычно.
IGNORE_PATTERNS = [
    "*.tmp",
    ".*.tmp",
    "~$*",       # временные файлы Office и похожих программ
    "*.godot.import",
]

_activity_version = [0]  # счётчик: любой log() увеличивает — StatusBoard видит "было новое"


def _enable_ansi_on_windows() -> None:
    """cmd.exe на Windows 10+ понимает ANSI-коды курсора, но их обработку нужно один раз
    включить — простой и широко известный трюк: пустой os.system("") инициализирует консоль
    в режиме, где VT100-последовательности начинают работать."""
    if os.name == "nt":
        os.system("")


def _is_ignored(filename: str) -> bool:
    return any(fnmatch.fnmatch(filename, pattern) for pattern in IGNORE_PATTERNS)


def _now_str() -> str:
    return datetime.now().strftime("%H:%M:%S %d/%m/%Y")


def log(repo_name: str, message: str) -> None:
    with _console_lock:
        print(f"[{_now_str()}] [{repo_name}] {message}")
        _activity_version[0] += 1


class RepoWatcher(FileSystemEventHandler):
    def __init__(self, repo_cfg: dict, dev_id: int):
        self.repo_path = Path(repo_cfg["path"])
        self.branch = repo_cfg["branch"]
        self.name = repo_cfg["name"]
        self.dev_id = dev_id
        self._lock = threading.Lock()

        # known_version — версия, которую мы сами приняли/подтвердили в прошлый раз (state.py).
        # current_tag — что реально сейчас стоит на git, только для отображения в столбике.
        self.known_version: Optional[str] = state.load_known_version(self.name)
        self.current_tag: str = self.known_version or "тегов ещё нет"

        self.last_check_time: str = "ещё не было"
        self.last_action: str = "ожидание"

    def status_line(self) -> str:
        return f"{self.name}: {self.current_tag} — {self.last_action} ({self.last_check_time})"

    def _accept_version(self, tag: str) -> None:
        self.known_version = tag
        state.save_known_version(self.name, tag)
        self.current_tag = tag

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

            # Версии не совпали. Если то, что мы сами помним, уже не существует как тег на
            # git — это не "git ушёл вперёд", а разрыв/сбой (или локально "уехали" без пуша) —
            # сразу в процесс слияния, сравнивать тут больше нечего.
            if self.known_version is not None and not git_ops.tag_exists(self.repo_path, self.known_version):
                log(self.name, "Известная нам версия не найдена на git — расхождение, нужен выбор")
                self._process_slияniya_raskhozhdeniy(reason)
                return

            # Иначе — git реально ушёл вперёд по сравнению с тем, что мы знали.
            self._branch_git_ahead(reason, git_version)

    def _branch_matched(self, reason: str) -> None:
        if not git_ops.has_local_changes(self.repo_path):
            self.last_check_time = _now_str()
            self.last_action = "актуально, изменений нет"
            log(self.name, "Результат: локальных изменений не найдено, пуш не нужен")
            return  # ДЕЙСТВИЕ_ПРОДОЛЖИТЬ_СЛЕЖЕНИЕ — просто ждём следующего файлового события

        if reason == REASON_PUSH:
            self._action_push(reason)
            return

        # reason == REASON_START: расхождение, которое мы сами только что не создавали (не
        # живое сохранение) — сначала спрашиваем пользователя.
        self.last_action = "есть незафиксированные изменения — нужен ответ"
        log(self.name, "Найдены незафиксированные локальные изменения")
        if notifier.ask_yes_no(f"[{self.name}] Есть незафиксированные изменения. Запушить их?"):
            self._action_push(reason)
        else:
            self.last_check_time = _now_str()
            self.last_action = "изменения найдены, пуш отложен пользователем"
            log(self.name, "Пользователь отложил пуш")

    def _branch_git_ahead(self, reason: str, git_version: Optional[str]) -> None:
        if not git_ops.has_local_changes(self.repo_path):
            self.last_action = "на git есть более новая версия — нужен ответ"
            log(self.name, f"На git версия {git_version}, у нас {self.known_version} — нужен ответ")
            if notifier.ask_yes_no(f"[{self.name}] На git есть более новая версия {git_version}. Обновить локально?"):
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
        if notifier.ask_yes_no(f"[{self.name}] Нет связи с git. Повторить попытку?"):
            self.sverka_versiy(reason)
        # иначе просто ничего не делаем сейчас — следующий повод (файл/таймер) проверит заново

    def _action_update_local(self, git_version: str) -> None:
        git_ops.reset_hard(self.repo_path, f"origin/{self.branch}")
        self._accept_version(git_version)
        self.last_check_time = _now_str()
        self.last_action = "обновлено с git"
        log(self.name, f"Результат: обновлено с git до {git_version}")

    def _next_version(self) -> Version:
        """push_count растёт автоматически на +1 от последней известной версии (решение
        пользователя: "версии с альфа пушатся автоматически просто по порядку 0,1,2 и т.д.").
        Stable/Beta и task_label демон САМ не меняет — их вручную двигает разработчик."""
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

    def _action_push(self, reason: str, force: bool = False) -> None:
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
            notifier.notify(f"AutoSync [{self.name}]", f"Ошибка при коммите/пуше: {e}")
            return

        # Коммит и пуш уже прошли успешно к этому моменту — дальше только тег. Если имя тега
        # почему-то занято, не сдаёмся сразу (правки бы уехали в git БЕЗ версии) — пробуем
        # следующий push_count, пока не найдём свободный.
        version = self._next_version()
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
            notifier.notify(
                f"AutoSync [{self.name}]",
                "Код запушен, но не удалось подобрать свободный тег версии за 50 попыток",
            )
            return

        # ДЕЙСТВИЕ_ПУШ включает проверку результата: заново спрашиваем git и сверяем, что
        # появилось именно то, что мы ждём, и рабочее дерево чистое.
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
            notifier.notify(f"AutoSync [{self.name}]", f"Синхронизировано: {reason} ({tag})")
            # Перезапускаем цикл с чистого листа — по сути "программа как будто только что
            # заново проверила состояние".
            self.sverka_versiy(REASON_START)
        else:
            log(self.name, "После пуша версия/файлы не совпали с ожиданием — уходим в слияние")
            self._process_slияniya_raskhozhdeniy(reason)

    def _process_slияniya_raskhozhdeniy(self, reason: str) -> None:
        self.last_action = "расхождение — нужен выбор"
        diff = git_ops.diff_name_status(self.repo_path, self.branch, f"origin/{self.branch}")
        choice = notifier.ask_sync_choice(self.branch, diff)

        if choice == notifier.SyncChoice.TAKE_LOCAL:
            log(self.name, "Выбор пользователя: оставить локальную версию (force-push)")
            self._action_push(reason, force=True)
            return  # _action_push сам решит, что делать дальше (или перезапустит цикл)
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


class StatusBoard:
    """Живой столбик в консоли: по строке на репозиторий + обратный отсчёт до плановой
    проверки. Перерисовывается НА МЕСТЕ поверх своего предыдущего кадра (ANSI cursor-up +
    очистка строки), пока между кадрами не было ничего интересного (см. _activity_version).
    Как только где-то вызвался log() — на следующем кадре борд просто печатается заново ниже
    этой записи, не пытаясь откатывать курсор через чужую строку."""

    def __init__(self, watchers: list[RepoWatcher], interval_minutes: int):
        self.watchers = watchers
        self.interval_seconds = interval_minutes * 60
        self.next_check_at = time.time() + self.interval_seconds
        self._printed_lines = 0
        self._last_seen_activity = _activity_version[0]

    def mark_checked_now(self) -> None:
        self.next_check_at = time.time() + self.interval_seconds

    def _render_once(self) -> None:
        remaining = max(0, int(self.next_check_at - time.time()))
        mm, ss = divmod(remaining, 60)
        lines = [w.status_line() for w in self.watchers]
        lines.append(f"До проверки на GitHub: {mm:02d}:{ss:02d}")

        with _console_lock:
            current_activity = _activity_version[0]
            redraw_in_place = self._printed_lines > 0 and current_activity == self._last_seen_activity
            if redraw_in_place:
                print(f"\033[{self._printed_lines}A", end="")  # курсор вверх на кол-во строк борда
            for line in lines:
                print("\033[2K" + line)  # очистить всю строку, затем напечатать новую
            self._printed_lines = len(lines)
            self._last_seen_activity = current_activity

    def loop(self) -> None:
        while True:
            self._render_once()
            time.sleep(1)


def periodic_check(watchers: list[RepoWatcher], board: StatusBoard) -> None:
    while True:
        time.sleep(board.interval_seconds)
        board.mark_checked_now()
        for w in watchers:
            log(w.name, "Плановая (периодическая) проверка...")
            w.sverka_versiy(REASON_START)


def main(config_path: str = "config.json") -> None:
    _enable_ansi_on_windows()
    cfg = json.loads(Path(config_path).read_text(encoding="utf-8"))
    dev_id = cfg["dev_id"]

    observer = Observer()
    watchers: list[RepoWatcher] = []

    for repo_cfg in cfg["repos"]:
        watcher = RepoWatcher(repo_cfg, dev_id)
        watchers.append(watcher)
        for rel_path in repo_cfg["watch_paths"]:
            full_path = Path(repo_cfg["path"]) / rel_path
            observer.schedule(watcher, str(full_path), recursive=True)

    observer.start()

    print("AutoSync запущен. Ctrl+C для остановки.")

    # Первичная проверка сразу при старте — чтобы столбик с первого кадра показывал реальные
    # данные из git, а не заглушки "ещё не было".
    for w in watchers:
        log(w.name, "Первичная проверка синхронизации с GitHub...")
        w.sverka_versiy(REASON_START)

    board = StatusBoard(watchers, cfg["check_interval_minutes"])
    threading.Thread(target=periodic_check, args=(watchers, board), daemon=True).start()
    threading.Thread(target=board.loop, daemon=True).start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()


if __name__ == "__main__":
    main()
