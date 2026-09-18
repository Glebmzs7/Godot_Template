"""
Простое уведомление пользователя + вопрос "что делать при расхождении".

На Windows пробуем системный toast (win10toast-reborn); если библиотеки нет — просто печатаем
в консоль. Вопрос с выбором сейчас решён как консольный ввод (1/2/3) — этого достаточно для
первой рабочей версии; позже можно заменить на нормальное окно (tkinter, у него не нужно
ничего доустанавливать — есть в стандартной поставке Python на Windows).
"""

from enum import Enum


def notify(title: str, message: str) -> None:
    try:
        from win10toast_reborn import ToastNotifier  # type: ignore
        ToastNotifier().show_toast(title, message, duration=8, threaded=True)
    except Exception:
        print(f"[AutoSync] {title}: {message}")


class SyncChoice(Enum):
    TAKE_LOCAL = "local"
    TAKE_GIT = "git"
    OPEN_MERGETOOL = "mergetool"


def ask_sync_choice(branch: str, diff_lines: list[str]) -> SyncChoice:
    """Блокирующий вопрос пользователю при расхождении (п.3 списка действий демона).

    Черновик через консоль — заменить на tkinter-окно перед реальным использованием,
    консольный ввод не подходит для фонового процесса без открытой консоли.
    """
    print(f"\n[AutoSync] Расхождение в ветке {branch!r}:")
    for line in diff_lines:
        print("   ", line)
    print("Что делать?")
    print("  1 — оставить локальную версию (перезаписать git)")
    print("  2 — взять версию из git (перезаписать локальные файлы)")
    print("  3 — открыть mergetool и разрешить вручную")
    choice = input("Выбор [1/2/3]: ").strip()
    return {
        "1": SyncChoice.TAKE_LOCAL,
        "2": SyncChoice.TAKE_GIT,
        "3": SyncChoice.OPEN_MERGETOOL,
    }.get(choice, SyncChoice.OPEN_MERGETOOL)
