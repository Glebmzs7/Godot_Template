"""
Запуск AutoSync БЕЗ окна консоли: двойной клик по этому файлу (или ярлык на него) на Windows
открывает только окно программы — pythonw.exe, который стоит за .pyw-файлами, консоль не создаёт.

Раньше это было главной причиной, почему без консоли было бы неудобно: если что-то падает ДО того,
как открылось окно программы (например, битый config.json), консоли нет — и ошибку было бы вообще
не увидеть, программа просто "не запустилась" молча. Поэтому здесь любая ошибка на старте:
  1) записывается в файл autosync_crash.log рядом с программой (можно скопировать и показать),
  2) сразу же показывается всплывающим окном (messagebox) — его видно, даже если консоли нет.
"""

import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))


def _show_fatal_error(exc: BaseException) -> None:
    error_text = "".join(traceback.format_exception(type(exc), exc, exc.__traceback__))

    try:
        crash_log = Path(__file__).resolve().parent / "autosync_crash.log"
        crash_log.write_text(error_text, encoding="utf-8")
    except OSError:
        pass

    try:
        import tkinter as tk
        from tkinter import messagebox

        root = tk.Tk()
        root.withdraw()
        # Полный текст — в autosync_crash.log, в окне показываем достаточно, чтобы понять суть.
        messagebox.showerror(
            "AutoSync — ошибка запуска",
            "Программа не смогла запуститься.\n\n"
            f"Подробности сохранены в:\n{Path(__file__).resolve().parent / 'autosync_crash.log'}\n\n"
            + error_text[-1200:],
        )
    except Exception:
        pass  # если даже messagebox не поднялся — хотя бы файл уже записан


if __name__ == "__main__":
    try:
        import watcher

        watcher.main()
    except BaseException as exc:  # ловим всё, включая ошибки конфигурации/импорта при старте
        _show_fatal_error(exc)
