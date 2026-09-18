"""
AutoSync — основной процесс демона.

Логика на файл-событие (п.5 списка действий, БЕЗ debounce — так решили: сохранил → сразу пуш):
    1. Сначала сверка git vs local (fetch + ahead/behind) — п.3 из последнего уточнения:
       «перед этим проверка на совпадения git и local».
    2. Если behind > 0 (в remote есть то, чего нет локально) — это расхождение, не пушим
       вслепую, идём в notifier.ask_sync_choice (вопрос пользователю, п.3 списка действий).
    3. Если расхождений нет — коммитим и пушим сразу, ставим новый тег версии со статусом G.

Периодическая проверка (п.6) — тот же путь п.1-2, но без события сохранения — просто по таймеру.

Это ПЕРВЫЙ рабочий черновик для запуска и обкатки на одном репозитории — до "Применяй" в чат
не кладётся ни в один реальный репозиторий, только в /mnt/user-data/outputs для ревью.
"""

import fnmatch
import json
import threading
import time
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


def _is_ignored(filename: str) -> bool:
    return any(fnmatch.fnmatch(filename, pattern) for pattern in IGNORE_PATTERNS)


class RepoWatcher(FileSystemEventHandler):
    def __init__(self, repo_cfg: dict, dev_id: int):
        self.repo_path = Path(repo_cfg["path"])
        self.branch = repo_cfg["branch"]
        self.name = repo_cfg["name"]
        self.dev_id = dev_id
        self._lock = threading.Lock()

    # --- события файловой системы ------------------------------------------------

    def on_modified(self, event):
        if event.is_directory:
            return
        filename = Path(event.src_path).name
        if _is_ignored(filename):
            return
        self._sync(reason=f"изменён файл: {event.src_path}")

    # --- основная логика -----------------------------------------------------------

    def _sync(self, reason: str) -> None:
        with self._lock:  # чтобы два быстрых сохранения подряд не гонялись за git одновременно
            try:
                git_ops.fetch(self.repo_path)
                state = git_ops.ahead_behind(self.repo_path, self.branch)
            except git_ops.GitError as e:
                notifier.notify(f"AutoSync [{self.name}]", f"Ошибка git при проверке: {e}")
                return

            if state.behind > 0:
                # Расхождение: в git есть то, чего нет локально — это п.3, вопрос пользователю,
                # НЕ пушим вслепую поверх.
                diff = git_ops.diff_name_status(
                    self.repo_path, self.branch, f"origin/{self.branch}"
                )
                notifier.notify(
                    f"AutoSync [{self.name}]",
                    f"Расхождение с git на ветке {self.branch} ({state.behind} коммитов позади) — нужен выбор",
                )
                choice = notifier.ask_sync_choice(self.branch, diff)
                self._resolve(choice)
                return

            if not git_ops.has_local_changes(self.repo_path):
                return  # событие было, но по факту нечего коммитить (например, файл пересохранён без изменений)

            self._commit_and_push(reason)

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

    def _commit_and_push(self, reason: str) -> None:
        try:
            git_ops.add_commit(self.repo_path, ["."], message=reason)
            git_ops.push(self.repo_path, self.branch)
            version = self._next_version()
            tag = version.format()
            git_ops.create_and_push_tag(self.repo_path, tag, message=reason)
            notifier.notify(f"AutoSync [{self.name}]", f"Синхронизировано: {reason} ({tag})")
        except git_ops.GitError as e:
            notifier.notify(f"AutoSync [{self.name}]", f"Ошибка при коммите/пуше: {e}")


def periodic_check(watchers: list[RepoWatcher], interval_minutes: int) -> None:
    while True:
        time.sleep(interval_minutes * 60)
        for w in watchers:
            w._sync(reason="периодическая проверка")


def main(config_path: str = "config.json") -> None:
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
    threading.Thread(
        target=periodic_check, args=(watchers, cfg["check_interval_minutes"]), daemon=True
    ).start()

    print("AutoSync запущен. Ctrl+C для остановки.")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()


if __name__ == "__main__":
    main()
