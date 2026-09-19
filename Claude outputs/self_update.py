"""
Самообновление самого AutoSync — отдельно от СВЕРКА_ВЕРСИЙ (та работает с игровыми репозиториями
и их тегами). Здесь всего один повод — ЗАПУСК_САМОЙ_ПРОГРАММЫ — и он не привязан ни к одному
RepoWatcher/строке в окне: обновляем не версию проекта, а сам код AutoSync в его собственной
папке (она и так уже git-репозиторий — https://github.com/Glebmzs7/GIT_automation).

ЗАПУСК_САМОЙ_ПРОГРАММЫ:
    1. Смотрим, с какой веткой сверяться — файл update_branch.txt рядом с программой, НЕ в git
       (у каждой копии/машины свой: у рабочей — "Stable", у копии для разработки — "alpha/Mzs7").
       Файла нет — по умолчанию "Stable": это безопасный выбор для обычного использования.
    2. git fetch этой ветки в СВОЁМ репозитории (там, где лежит сам AutoSync).
       Не получилось (нет связи) -> тихо пропускаем проверку, обычный запуск, ничего не спрашиваем.
    3. Сравниваем свой текущий коммит (HEAD) с origin/<ветка>:
        - Совпадают -> обновлять нечего, обычный запуск.
        - origin впереди, а наш HEAD — предок origin (мы просто отстали) -> есть новая версия,
          спрашиваем пользователя (Да/Нет):
            - Да -> git pull --ff-only -> сообщаем "обновлено, перезапустите программу" и
              завершаем процесс (программа уже загружена в память со старым кодом — чтобы не
              работать в перепутанном состоянии "файлы новые, код в памяти старый", проще
              попросить перезапустить, чем пытаться подменить код на лету).
            - Нет -> просто продолжаем обычный запуск на текущей версии.
        - НЕ являемся предком origin (либо у нас есть свои коммиты, которых там нет, либо ветки
          разошлись) -> НИЧЕГО не делаем автоматически, только предупреждение в лог. По задумке
          рабочую копию никто не редактирует руками (для разработки — отдельная копия), так что
          это нештатная ситуация, где безопаснее не трогать код молча.
"""

import subprocess
import sys
from pathlib import Path
from typing import Callable, Optional

_SELF_DIR = Path(__file__).resolve().parent
_UPDATE_BRANCH_FILE = _SELF_DIR / "update_branch.txt"
_DEFAULT_BRANCH = "Stable"


class _GitError(RuntimeError):
    pass


def _run(*args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(_SELF_DIR), *args],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if result.returncode != 0:
        raise _GitError(result.stderr.strip())
    return result.stdout.strip()


def get_update_branch() -> str:
    if _UPDATE_BRANCH_FILE.exists():
        value = _UPDATE_BRANCH_FILE.read_text(encoding="utf-8").strip()
        if value:
            return value
    return _DEFAULT_BRANCH


def check_and_apply(ask_yes_no: Callable[[str], bool], notify_and_exit: Callable[[str], None],
                     log: Callable[[str], None]) -> None:
    """Вызывается один раз при старте, ДО открытия основного окна.

    ask_yes_no(message) -> bool — обычный вопрос Да/Нет (отдельный простой диалог, не через
    таблицу репозиториев — у самообновления нет своей строки).
    notify_and_exit(message) -> None — показать сообщение и завершить процесс (после успешного
    обновления).
    log(message) -> None — запись в лог для нештатных ситуаций (расхождение, ошибка pull).
    """
    branch = get_update_branch()

    try:
        _run("fetch", "origin", branch)
        local_head = _run("rev-parse", "HEAD")
        remote_head = _run("rev-parse", f"origin/{branch}")
    except _GitError:
        return  # нет связи с git или ветки не существует — не мешаем обычному запуску

    if local_head == remote_head:
        return  # уже актуальная версия

    is_behind = subprocess.run(
        ["git", "-C", str(_SELF_DIR), "merge-base", "--is-ancestor", local_head, remote_head],
        capture_output=True,
    ).returncode == 0

    if not is_behind:
        log(
            f"Самообновление: локальная копия AutoSync разошлась с веткой {branch!r} "
            f"(есть свои коммиты, которых нет в источнике) — обновление пропущено, ничего не трогаем."
        )
        return

    if not ask_yes_no(f"Доступна новая версия AutoSync (ветка {branch!r}). Обновить сейчас?"):
        return

    try:
        _run("pull", "--ff-only", "origin", branch)
    except _GitError as e:
        log(f"Самообновление: git pull не удался — {e}")
        return

    notify_and_exit("AutoSync обновлён. Перезапустите программу, чтобы применились изменения.")
    sys.exit(0)
