"""
Простое уведомление пользователя + блокирующие вопросы ("что делать при расхождении",
"повторить попытку?", "обновить локально?").

На Windows пробуем системный toast (win10toast-reborn); если библиотеки нет — просто ничего не
делаем (уведомление необязательно, суть уходит в консоль через log() в watcher.py). Вопросы с
выбором решены как консольный ввод — этого достаточно для первой рабочей версии; позже можно
заменить на нормальное окно (tkinter, ничего доустанавливать не нужно — есть в стандартной
поставке Python на Windows).

Все консольные print/input здесь используют общую блокировку из console_lock.py — ту же самую,
что и watcher.py для log()/StatusBoard — чтобы вопрос пользователю не наехал на перерисовку
столбика статуса и не испортил вывод.
"""

from enum import Enum

from console_lock import LOCK as _console_lock


def notify(title: str, message: str) -> None:
    """Системное всплывающее уведомление (если библиотека доступна). Раньше здесь был ещё и
    запасной print() в консоль — убрали: он печатал БЕЗ общей блокировки консоли, из-за чего мог
    влезать посреди перерисовки статус-борда и портить вывод. То же самое сообщение и так уходит
    в консоль через log() в watcher.py — дублировать не нужно, а неаккуратный дубль был
    источником бага."""
    try:
        from win10toast_reborn import ToastNotifier  # type: ignore
        ToastNotifier().show_toast(title, message, duration=8, threaded=True)
    except Exception:
        pass


class SyncChoice(Enum):
    TAKE_LOCAL = "local"
    TAKE_GIT = "git"
    OPEN_MERGETOOL = "mergetool"


def ask_sync_choice(branch: str, diff_lines: list[str]) -> SyncChoice:
    """Блокирующий вопрос пользователю — используется в ПРОЦЕСС_СЛИЯНИЯ_РАСХОЖДЕНИЙ.

    Черновик через консоль — заменить на tkinter-окно перед реальным использованием,
    консольный ввод не подходит для фонового процесса без открытой консоли.
    """
    with _console_lock:
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


def ask_yes_no(message: str) -> bool:
    """Блокирующий вопрос да/нет — используется ДЕЙСТВИЯ_ОЖИДАНИЯ_РЕШЕНИЯ_ПО_ПРЕДЛОЖЕНИЮ.

    Программа именно ЖДЁТ ответа по этому конкретному репозиторию (не уходит дальше по своим
    делам до ответа) — так и было явно оговорено: "программа для проблемного файла стоит и ждёт
    ответа", а не пропускает вопрос до следующего повода.
    """
    with _console_lock:
        print(f"\n[AutoSync] {message}")
        answer = input("Продолжить? [y/n]: ").strip().lower()
    return answer in ("y", "yes", "д", "да")
