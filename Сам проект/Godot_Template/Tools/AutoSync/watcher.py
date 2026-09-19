"""
AutoSync — основной процесс демона.

Логика на файл-событие (п.5 списка действий, БЕЗ debounce — так решили: сохранил → сразу пуш):
    1. Есть материал для пуша (сработало файловое событие, отфильтрованное от мусора).
    2. Обращаемся к серверу (git fetch) + сверка git vs local (ahead/behind) — п.3 из уточнения:
       «перед этим проверка на совпадения git и local».
    3. Если behind > 0 (в remote есть то, чего нет локально) — это расхождение, не пушим
       вслепую, идём в notifier.ask_sync_choice (вопрос пользователю, п.3 списка действий).
    4. Если расхождений нет — передаём синхронизацию (commit+push), ставим тег версии, печатаем
       результат.

Периодическая проверка (п.6) — тот же путь, но без события сохранения — просто по таймеру.
При старте программы делается одна такая же проверка сразу (чтобы статус-борд с первого кадра
показывал реальное состояние, а не заглушки).

В консоль постоянно выводится живой статус по каждому репозиторию + обратный отсчёт до
следующей плановой проверки. Строки статуса обновляются НА МЕСТЕ (через ANSI-коды), а не
печатаются заново — это динамический борд, не растущий список одинаковых блоков. Если между
кадрами борда произошло что-то важное (лог с деталями синхронизации), это печатается обычной
строкой в прокрутку, а борд на следующем кадре просто перерисовывается заново ниже.
"""

import fnmatch
import json
import os
import threading
import time
from datetime import datetime
from pathlib import Path

from watchdog.events import FileSystemEventHandler
from watchdog.observers import Observer

import git_ops
import notifier
from version import Version, VALID_STATUSES, parse

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

_console_lock = threading.Lock()  # чтобы строки из разных потоков не перемешивались посимвольно
_activity_version = [0]           # счётчик: любой log() увеличивает — StatusBoard видит "было новое"


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

        # Состояние для строки статуса (StatusBoard читает эти поля). Обновляется на КАЖДОЙ
        # проверке (а не только когда реально что-то запушили) — п. задачи "добавить данные о
        # первичной проверке синхронизации вместо заглушек".
        self.last_check_time: str = "ещё не было"
        self.last_mode: str = "—"
        self.current_tag: str = "—"
        self.last_action: str = "—"

    def status_line(self) -> str:
        return (
            f"{self.repo_path} - {self.last_check_time} - {self.last_mode} - "
            f"{self.current_tag} ({self.last_action})"
        )

    def _refresh_known_tag(self) -> None:
        """Подтягивает актуальный тег ветки из git — вызывается на каждой проверке, независимо
        от того, пушили мы что-то в этот раз или нет, чтобы борд не показывал заглушки."""
        latest = git_ops.latest_tag_on_branch(self.repo_path, self.branch)
        self.current_tag = latest or "тегов ещё нет"

    # --- события файловой системы ------------------------------------------------

    def on_modified(self, event):
        if event.is_directory:
            return
        filename = Path(event.src_path).name
        if _is_ignored(filename):
            return
        log(self.name, f"Есть материал для пуша: {event.src_path}")
        self._sync(reason=f"изменён файл: {event.src_path}", mode="Автоматически")

    # --- основная логика -----------------------------------------------------------

    def _sync(self, reason: str, mode: str) -> None:
        with self._lock:  # чтобы два быстрых сохранения подряд не гонялись за git одновременно
            self.last_check_time = _now_str()
            self.last_mode = mode

            log(self.name, "Обращаемся к серверу (git fetch)...")
            try:
                git_ops.fetch(self.repo_path)
                state = git_ops.ahead_behind(self.repo_path, self.branch)
            except git_ops.GitError as e:
                self.last_action = "ошибка проверки"
                log(self.name, f"Результат: ошибка git при проверке — {e}")
                notifier.notify(f"AutoSync [{self.name}]", f"Ошибка git при проверке: {e}")
                return

            self._refresh_known_tag()

            if state.behind > 0:
                # Расхождение: в git есть то, чего нет локально — это п.3, вопрос пользователю,
                # НЕ пушим вслепую поверх.
                diff = git_ops.diff_name_status(
                    self.repo_path, self.branch, f"origin/{self.branch}"
                )
                self.last_action = f"расхождение ({state.behind} позади)"
                log(self.name, f"Результат: расхождение с git ({state.behind} коммитов позади) — нужен выбор")
                notifier.notify(
                    f"AutoSync [{self.name}]",
                    f"Расхождение с git на ветке {self.branch} ({state.behind} коммитов позади) — нужен выбор",
                )
                choice = notifier.ask_sync_choice(self.branch, diff)
                self._resolve(choice)
                return

            if not git_ops.has_local_changes(self.repo_path):
                self.last_action = "актуально, изменений нет"
                log(self.name, "Результат: локальных изменений не найдено, пуш не нужен")
                return

            log(self.name, "Передаём синхронизацию (commit + push)...")
            self._commit_and_push(reason, mode)

    def _resolve(self, choice: notifier.SyncChoice) -> None:
        if choice == notifier.SyncChoice.TAKE_GIT:
            git_ops._run(self.repo_path, "reset", "--hard", f"origin/{self.branch}")
        elif choice == notifier.SyncChoice.TAKE_LOCAL:
            git_ops._run(self.repo_path, "push", "--force-with-lease", "origin", self.branch)
        else:
            git_ops.open_mergetool(self.repo_path)

    def _next_version(self) -> Version:
        """push_count растёт автоматически на +1 от последнего тега ветки (решение пользователя:
        "версии с альфа пушатся автоматически просто по порядку 0,1,2 и т.д."). Stable/Beta и
        task_label демон САМ не меняет — их вручную двигает разработчик, когда решает
        зафиксировать более старшую версию или подать заявку на слияние в Beta/Stable."""
        latest = git_ops.latest_tag_on_branch(self.repo_path, self.branch)
        if latest is None:
            return Version(
                stable=0, stable_patch=0, beta=0, beta_push=0,
                dev_id=self.dev_id, task_label=0, push_count=0, status="G",
            )
        prev = parse(latest)
        return Version(
            stable=prev.stable, stable_patch=prev.stable_patch,
            beta=prev.beta, beta_push=prev.beta_push,
            dev_id=self.dev_id, task_label=prev.task_label, push_count=prev.push_count + 1,
            status="G", project_sync=prev.project_sync,
        )

    def _commit_and_push(self, reason: str, mode: str) -> None:
        try:
            git_ops.add_commit(self.repo_path, ["."], message=reason)
            git_ops.push(self.repo_path, self.branch)
        except git_ops.GitError as e:
            self.last_action = "ошибка коммита/пуша"
            log(self.name, f"Результат: ошибка при коммите/пуше — {e}")
            notifier.notify(f"AutoSync [{self.name}]", f"Ошибка при коммите/пуше: {e}")
            return

        # Коммит и пуш уже прошли успешно к этому моменту — дальше только тег. Если имя тега
        # почему-то занято (latest_tag_on_branch не увидел уже существующий тег — например,
        # git ещё не успел обновить локальные refs, или тег был создан отдельно), не сдаёмся
        # сразу с ошибкой (тогда правки уедут в git БЕЗ версии) — пробуем следующий push_count,
        # пока не найдём свободный.
        version = self._next_version()
        for _ in range(50):
            tag = version.format()
            try:
                git_ops.create_and_push_tag(self.repo_path, tag, message=reason)
                self.current_tag = tag
                self.last_action = "синхронизировано"
                log(self.name, f"Результат: синхронизировано, {tag}")
                notifier.notify(f"AutoSync [{self.name}]", f"Синхронизировано: {reason} ({tag})")
                return
            except git_ops.GitError:
                version.push_count += 1
        self.last_action = "пуш прошёл, тег не поставлен"
        log(self.name, f"Результат: код запушен, но свободный тег не найден за 50 попыток (последний: {tag})")
        notifier.notify(
            f"AutoSync [{self.name}]",
            f"Код запушен, но не удалось подобрать свободный тег версии за 50 попыток "
            f"(последний: {tag}) — коммит в {self.branch} есть, версия не проставлена",
        )


class StatusBoard:
    """Живая шапка в консоли: по строке на репозиторий + обратный отсчёт до плановой проверки.

    Перерисовывается НА МЕСТЕ поверх своего предыдущего кадра (ANSI cursor-up + очистка строки),
    пока между кадрами не было ничего интересного (см. _activity_version). Как только где-то
    вызвался log() — это уходит в обычную прокрутку консоли, а борд на следующем кадре просто
    печатается заново ниже этой записи (не пытаемся откатывать курсор через чужой лог — так
    надёжнее, чем городить сложную многооконную консоль ради черновика)."""

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
        lines = ["=== AutoSync: статус ==="]
        lines.extend(w.status_line() for w in self.watchers)
        lines.append(f"Время до проверки на GitHub — {mm:02d}:{ss:02d}")

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
            time.sleep(1)  # раз в секунду — с ANSI-перерисовкой это не мусорит в прокрутку


def periodic_check(watchers: list[RepoWatcher], board: StatusBoard) -> None:
    while True:
        time.sleep(board.interval_seconds)
        board.mark_checked_now()
        for w in watchers:
            log(w.name, "Плановая (периодическая) проверка...")
            w._sync(reason="периодическая проверка", mode="Периодическая проверка")


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

    # Первичная проверка сразу при старте — чтобы борд с первого кадра показывал реальные
    # данные из git, а не заглушки "ещё не было".
    for w in watchers:
        log(w.name, "Первичная проверка синхронизации с GitHub...")
        w._sync(reason="первичная проверка при запуске", mode="Первичная проверка")

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
