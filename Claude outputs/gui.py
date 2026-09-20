"""
Окно AutoSync (tkinter). Один прокручиваемый список, одна строка на репозиторий:

    [путь слежения — клик открывает проводник] [ссылка git — клик открывает ветку на GitHub]
    [версия, последнее число выделено цветом — его одного двигает автопуш]
    [время последнего сохранения] [обратный отсчёт до принудительной проверки]

Правая кнопка мыши на пути/git-ссылке — контекстное меню (Открыть/Копировать/Изменить).
Правая кнопка мыши на обратном отсчёте — задать свой интервал проверки для этого репозитория.

Если репозиторию нужно решение пользователя — строка красная, наверху появляется значок "!"
(фильтр: показать только красные строки). Диалог с вопросом МОЖНО закрыть крестиком, не отвечая —
это НЕ считается ответом "нет", репозиторий просто остаётся "красным", а вопрос — открытым;
кликом по красной строке диалог открывается заново. Это отличие от обычного модального окна
сделано специально: пользователь не обязан отвечать сразу, если сейчас не до этого.

Про потоки: watcher.py делает git-операции в ФОНОВЫХ потоках, а tkinter обязан жить в главном.
Поэтому обновление виджетов из фона идёт через self.root.after(0, ...), а блокирующий вопрос —
через threading.Event: фоновый поток вызывает ask_yes_no/ask_choice и стоит на event.wait(),
пока по этому вопросу не нажмут кнопку (хоть сразу, хоть после переоткрытия по клику на строку).
"""

import re
import subprocess
import sys
import threading
import time
import tkinter as tk
import webbrowser
from dataclasses import dataclass, field
from pathlib import Path
from tkinter import simpledialog, ttk
from typing import Callable, List, Optional

from notifier import SyncChoice

_MAX_LOG_LINES = 300

# Журнал теперь не только в окне (которое каждый раз при перезапуске начинается с чистого листа),
# но и в файле рядом с программой — жалоба "вывод в консоль не сохраняется из сессии в сессию".
_LOG_FILE_PATH = Path(__file__).resolve().parent / "autosync.log"


def _last_n_path_parts(path: Path, n: int = 3) -> str:
    parts = path.parts[-n:] if len(path.parts) >= n else path.parts
    return str(Path(*parts))


def remote_to_github_web_url(remote_url: str, branch: str) -> Optional[str]:
    """git@github.com:owner/repo.git или https://github.com/owner/repo.git -> страница ветки."""
    if not remote_url:
        return None
    url = remote_url.strip()
    if url.startswith("git@"):
        try:
            host_and_path = url.split("git@", 1)[1]
            host, path = host_and_path.split(":", 1)
        except ValueError:
            return None
    else:
        without_scheme = re.sub(r"^https?://", "", url)
        host, _, path = without_scheme.partition("/")
        if not path:
            return None
    path = path[:-4] if path.endswith(".git") else path
    return f"https://{host}/{path}/tree/{branch}"


@dataclass
class PendingQuestion:
    kind: str  # "yes_no" | "choice"
    message: str = ""
    branch: str = ""
    diff_lines: List[str] = field(default_factory=list)
    event: threading.Event = field(default_factory=threading.Event)
    result: object = None


def _finalize_toplevel(win: tk.Toplevel) -> None:
    """Известная особенность Tk на Windows: свежесозданный Toplevel иногда повисает БЕЗ рамки
    вообще (ни свернуть, ни развернуть, ни крестика) в углу экрана — оконный менеджер просто не
    перерисовывает рамку, пока не получит сигнал об изменении геометрии. Вручную это лечится
    попыткой изменить размер окна мышью — здесь делаем то же самое программно: пересчитываем
    размер под содержимое и переустанавливаем геометрию (заодно и по центру — раньше окно
    оставалось там, где Windows его изначально поставило, обычно в верхнем левом/правом углу),
    что форсирует Windows нарисовать нормальную рамку сразу, без участия пользователя."""
    win.update_idletasks()
    width = win.winfo_reqwidth()
    height = win.winfo_reqheight()

    # Центрируем относительно главного окна программы (а не относительно всего экрана — так
    # диалог появляется рядом с тем окном, из которого его открыли, даже на нескольких мониторах).
    owner = win.master.winfo_toplevel()
    x = owner.winfo_rootx() + (owner.winfo_width() - width) // 2
    y = owner.winfo_rooty() + (owner.winfo_height() - height) // 2
    # На случай, если главное окно свёрнуто/за пределами экрана — не даём диалогу уйти в минус.
    x, y = max(0, x), max(0, y)

    win.geometry(f"{width}x{height}+{x}+{y}")
    win.lift()
    win.focus_force()


def _open_in_explorer(path: Path) -> None:
    if sys.platform == "win32":
        try:
            import os
            os.startfile(str(path))  # type: ignore[attr-defined]
        except Exception:
            pass
    else:
        subprocess.run(["xdg-open", str(path)])


class RepoRow(tk.Frame):
    """Одна строка списка — один репозиторий."""

    def __init__(self, parent, watcher, app: "AutoSyncGUI"):
        super().__init__(parent, bd=1, relief="solid", padx=6, pady=4)
        self.watcher = watcher
        self.app = app

        # Колонки растягиваются РАВНОМЕРНО (uniform) вместе с окном — раньше ширина была
        # фиксированной в символах, и при узком окне текст последних колонок просто уезжал за
        # пределы видимой области (не было ни переноса, ни горизонтальной прокрутки).
        # Колонка 5 — кнопка работает/ожидает/остановлена.
        for col in range(6):
            self.grid_columnconfigure(col, weight=1, uniform="repo_row_cols")

        self.path_label = tk.Label(self, cursor="hand2", anchor="w")
        self.path_label.grid(row=0, column=0, sticky="ew", padx=(0, 8))
        self.path_label.bind("<Button-1>", lambda e: _open_in_explorer(self.watcher.full_watch_path))
        self.path_label.bind("<Button-3>", self._path_menu)

        self.git_label = tk.Label(self, cursor="hand2", anchor="w", fg="#1a5fb4")
        self.git_label.grid(row=0, column=1, sticky="ew", padx=(0, 8))
        self.git_label.bind("<Button-1>", self._open_git)
        self.git_label.bind("<Button-3>", self._git_menu)

        self.version_frame = tk.Frame(self)
        self.version_frame.grid(row=0, column=2, sticky="ew", padx=(0, 8))
        self.version_prefix_label = tk.Label(self.version_frame, anchor="w")
        self.version_prefix_label.pack(side="left")
        self.version_push_label = tk.Label(self.version_frame, anchor="w", fg="#1a5fb4", font=("TkDefaultFont", 9, "bold"))
        self.version_push_label.pack(side="left")
        for widget in (self.version_frame, self.version_prefix_label, self.version_push_label):
            widget.bind("<Button-3>", self._version_menu)

        # Последние две колонки (время/отсчёт) — текст прижат вправо, к краю строки, а не влево.
        self.saved_label = tk.Label(self, anchor="e")
        self.saved_label.grid(row=0, column=3, sticky="ew", padx=(0, 8))

        self.countdown_label = tk.Label(self, anchor="e", cursor="hand2")
        self.countdown_label.grid(row=0, column=4, sticky="ew", padx=(0, 8))
        self.countdown_label.bind("<Button-3>", self._interval_menu)

        # Работает (зелёная) / Ожидает (жёлтая — есть вопрос, требующий ответа, клик открывает
        # тот же диалог, что и клик по красной строке) / Остановлена (красная — слежение и
        # проверки для этого репозитория выключены пользователем, до повторного включения).
        self.run_button = tk.Button(self, width=12, command=self._on_run_button_click)
        self.run_button.grid(row=0, column=5, sticky="ew")

        self.status_label = tk.Label(self, anchor="w")
        self.status_label.grid(row=1, column=0, columnspan=6, sticky="ew", pady=(2, 0))

        for widget in (self, self.status_label, self.saved_label):
            widget.bind("<Button-1>", self._row_click, add="+")
            widget.bind("<Button-3>", self._row_menu, add="+")

        self.pack(fill="x", padx=6, pady=3)

    # --- контекстные меню --------------------------------------------------------

    def _path_menu(self, event):
        menu = tk.Menu(self, tearoff=0)
        menu.add_command(label="Открыть", command=lambda: _open_in_explorer(self.watcher.full_watch_path))
        menu.add_command(label="Копировать", command=lambda: self._copy(str(self.watcher.full_watch_path)))
        menu.add_command(label="Изменить путь...", command=self._edit_path)
        menu.tk_popup(event.x_root, event.y_root)

    def _git_menu(self, event):
        menu = tk.Menu(self, tearoff=0)
        url = self.watcher.git_web_url()
        menu.add_command(label="Открыть", command=self._open_git_now)
        menu.add_command(label="Копировать", command=lambda: self._copy(url or self.watcher.branch))
        menu.add_command(label="Изменить ветку...", command=self._edit_branch)
        menu.tk_popup(event.x_root, event.y_root)

    def _version_menu(self, event):
        menu = tk.Menu(self, tearoff=0)
        menu.add_command(label="Изменить версию...", command=self._edit_version)
        menu.tk_popup(event.x_root, event.y_root)

    def _edit_version(self) -> None:
        from version import split_prefix_and_push

        base = self.watcher.known_version or self.watcher.current_tag
        if base and base != "тегов ещё нет":
            default_prefix, _ = split_prefix_and_push(base)
        else:
            default_prefix = str(self.watcher.dev_id)

        win = tk.Toplevel(self)
        win.title(f"Изменить версию — {self.watcher.name}")
        tk.Label(
            win,
            text="Версия — любой текст, никакого формата не требуется. Номер пуша в конце вы не\n"
                 "задаёте — он обнулится и дальше снова будет расти сам с каждым пушем.\n"
                 "Применяется сразу: коммит + пуш поверх того, что сейчас на git.",
            justify="left",
        ).pack(padx=12, pady=(12, 6), anchor="w")

        entry = tk.Entry(win, width=48)
        entry.insert(0, default_prefix)
        entry.pack(padx=12, pady=(0, 12), fill="x")
        entry.select_range(0, "end")
        entry.focus_set()

        def submit():
            new_prefix = entry.get().strip()
            if not new_prefix:
                return
            self.app.manual_version_change(self.watcher, new_prefix)
            win.destroy()

        entry.bind("<Return>", lambda e: submit())
        tk.Button(win, text="Применить (коммит + пуш сразу)", command=submit).pack(pady=(0, 12))
        _finalize_toplevel(win)

    def _interval_menu(self, event):
        menu = tk.Menu(self, tearoff=0)
        menu.add_command(label="Задать интервал проверки...", command=self._set_interval)
        menu.tk_popup(event.x_root, event.y_root)

    def _copy(self, text: str) -> None:
        self.clipboard_clear()
        self.clipboard_append(text)

    def _open_git(self, _event=None) -> None:
        self._open_git_now()

    def _open_git_now(self) -> None:
        url = self.watcher.git_web_url()
        if url:
            webbrowser.open(url)

    def _edit_path(self) -> None:
        new_value = simpledialog.askstring(
            "Изменить путь", "Относительный путь слежения (watch_paths[0]):",
            initialvalue=self.watcher.watch_paths[0], parent=self,
        )
        if new_value:
            self.app.on_edit_repo(self.watcher, watch_path=new_value)

    def _edit_branch(self) -> None:
        new_value = simpledialog.askstring(
            "Изменить ветку", "Ветка git:", initialvalue=self.watcher.branch, parent=self,
        )
        if new_value:
            self.app.on_edit_repo(self.watcher, branch=new_value)

    def _set_interval(self) -> None:
        # В секундах и обязательно целым числом — проще, чем возиться с разделителем дробной
        # части (запятая/точка путаются в разных региональных настройках Windows).
        seconds = simpledialog.askinteger(
            "Интервал проверки", f"Через сколько секунд проверять «{self.watcher.name}»?",
            initialvalue=self.watcher.check_interval_seconds, minvalue=1, parent=self,
        )
        if seconds:
            self.watcher.check_interval_seconds = seconds
            self.watcher.next_check_at = time.time() + self.watcher.check_interval_seconds

    def _on_run_button_click(self) -> None:
        w = self.watcher
        if w.pending_question is not None:
            # Жёлтое состояние — это не переключатель, а напоминание об открытом вопросе: клик
            # открывает тот же диалог заново, ровно как клик по красной строке.
            self.app.reopen_pending(w)
        elif w.running:
            self.app.on_toggle_run(w, False)
        else:
            self.app.on_toggle_run(w, True)

    def _row_click(self, _event=None) -> None:
        if self.watcher.pending_question is not None:
            self.app.reopen_pending(self.watcher)

    def _row_menu(self, event) -> None:
        menu = tk.Menu(self, tearoff=0)
        menu.add_command(label="Изменить репозиторий...", command=self._edit_repo_full)
        menu.tk_popup(event.x_root, event.y_root)

    def _edit_repo_full(self) -> None:
        """Правая кнопка мыши на строке (не на конкретной ссылке/версии/интервале — там свои
        отдельные меню) — открывает окно, аналогичное добавлению репозитория, но с уже
        подставленными данными этой строки, включая имя (раньше имя было неизменяемым)."""
        w = self.watcher
        win = tk.Toplevel(self)
        win.title(f"Изменить репозиторий — {w.name}")

        rows = [
            ("path", "Папка хранения (где лежит .git)", str(w.repo_path)),
            ("branch", "Ветка для push", w.branch),
            ("interval", "Через сколько секунд проверять git", str(w.check_interval_seconds)),
            ("name", "Имя", w.name),
            ("watch_path", "Папка слежения внутри репозитория (пусто — вся папка)", w.watch_paths[0]),
        ]
        fields = {}
        for i, (key, label, current) in enumerate(rows):
            tk.Label(win, text=label, wraplength=260, justify="left").grid(
                row=i, column=0, sticky="w", padx=8, pady=4
            )
            entry = tk.Entry(win, width=40)
            entry.insert(0, current)
            entry.grid(row=i, column=1, padx=8, pady=4)
            fields[key] = entry

        def submit():
            path = fields["path"].get().strip()
            branch = fields["branch"].get().strip()
            name = fields["name"].get().strip()
            watch_path = fields["watch_path"].get().strip()
            if not (path and branch and name):
                return
            try:
                interval_seconds = int(fields["interval"].get().strip())
            except ValueError:
                interval_seconds = w.check_interval_seconds
            self.app.on_edit_repo(
                w, name=name, path=path, branch=branch,
                watch_path=watch_path, interval_seconds=interval_seconds,
            )
            win.destroy()

        tk.Button(win, text="Сохранить", command=submit).grid(
            row=len(rows), column=0, columnspan=2, pady=10
        )
        _finalize_toplevel(win)

    # --- обновление вида -----------------------------------------------------------

    def refresh(self) -> None:
        w = self.watcher
        self.path_label.configure(text=_last_n_path_parts(w.full_watch_path, 3))
        self.git_label.configure(text=_last_n_path_parts(Path(w.name) / w.branch, 3))

        tag = w.current_tag
        if tag and tag != "тегов ещё нет" and "," in tag:
            prefix, last = tag.rsplit(",", 1)
            self.version_prefix_label.configure(text=prefix + ",")
            self.version_push_label.configure(text=last)
        else:
            self.version_prefix_label.configure(text=tag or "—")
            self.version_push_label.configure(text="")

        self.saved_label.configure(text=w.last_saved_at)
        remaining = max(0, int(w.next_check_at - time.time()))
        mm, ss = divmod(remaining, 60)
        self.countdown_label.configure(text=f"{mm:02d}:{ss:02d}" if w.running else "—:—")
        self.status_label.configure(text=f"{w.last_action} ({w.last_check_time})")

        needs_attention = w.pending_question is not None
        if needs_attention:
            self.run_button.configure(text="Ожидает", bg="#f6c343", activebackground="#f6c343")
        elif w.running:
            self.run_button.configure(text="Работает", bg="#4caf50", activebackground="#4caf50")
        else:
            self.run_button.configure(text="Остановлена", bg="#e05252", activebackground="#e05252")
        bg = "#f8d7da" if needs_attention else self.app.default_bg
        for widget in (self, self.status_label, self.saved_label, self.countdown_label,
                       self.version_frame, self.version_prefix_label, self.version_push_label,
                       self.path_label, self.git_label):
            widget.configure(bg=bg)


class AutoSyncGUI:
    def __init__(self, watchers: list, on_add_repo: Callable[[dict], object],
                 on_edit_repo: Callable[..., None],
                 on_manual_version_change: Callable[..., None],
                 on_toggle_run: Callable[..., None]):
        self.watchers = watchers
        self._on_add_repo_cb = on_add_repo
        self._on_edit_repo_cb = on_edit_repo
        self._on_manual_version_change_cb = on_manual_version_change
        self._on_toggle_run_cb = on_toggle_run

        self.root = tk.Tk()
        self.root.title("AutoSync")
        self.root.geometry("900x520")
        self.default_bg = self.root.cget("bg")

        top_bar = tk.Frame(self.root)
        top_bar.pack(fill="x", padx=6, pady=(6, 0))
        tk.Button(top_bar, text="+", width=3, command=self._open_add_dialog).pack(side="left")
        # Пока нет отдельной иконки — просто текстовая кнопка "ПРОБЛЕМЫ (n)", хорошо видна и без
        # значка. Нажатие — фильтр: показать только строки, где нужен ответ.
        self.alert_button = tk.Button(top_bar, text="", command=self._toggle_filter, fg="#a4000f")
        self.alert_button.pack(side="left", padx=8)

        # Список репозиториев и лог — в PanedWindow, чтобы можно было перетащить границу между
        # ними мышью и увеличить лог, если строк репозиториев мало, а лога нужно много видно
        # (жалоба "только 5 строчек лога и не видно больше").
        paned = ttk.PanedWindow(self.root, orient="vertical")
        paned.pack(fill="both", expand=True, padx=6, pady=6)

        list_container = tk.Frame(paned)
        canvas = tk.Canvas(list_container, highlightthickness=0)
        scrollbar = ttk.Scrollbar(list_container, orient="vertical", command=canvas.yview)
        self.rows_frame = tk.Frame(canvas)
        self.rows_frame.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        rows_window = canvas.create_window((0, 0), window=self.rows_frame, anchor="nw")
        # Ширина содержимого канваса всегда равна ширине окна — иначе при изменении размера окна
        # строки не растягивались вслед за ним, и правые колонки "уезжали" за пределы видимой
        # области без возможности прокрутить (только вертикальная прокрутка и была нужна).
        canvas.bind("<Configure>", lambda e: canvas.itemconfig(rows_window, width=e.width))
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.pack(side="left", fill="both", expand=True)
        scrollbar.pack(side="right", fill="y")
        paned.add(list_container, weight=3)

        log_container = tk.Frame(paned)
        log_bar = tk.Frame(log_container)
        log_bar.pack(fill="x")
        tk.Label(log_bar, text="Журнал событий").pack(side="left", padx=(2, 0))
        tk.Button(log_bar, text="Копировать весь лог", command=self._copy_log).pack(side="right")
        log_body = tk.Frame(log_container)
        log_body.pack(fill="both", expand=True)
        # state="disabled" в некоторых сборках Tk на Windows заодно ломает и обычное выделение
        # мышью (работала только кнопка "Копировать весь лог") — вместо этого держим текст
        # "normal" всегда, а от ручного редактирования защищаемся отдельно, блокируя клавиши
        # (см. _block_log_editing ниже); выделение и Ctrl+C/Ctrl+A при этом работают как обычно.
        self.log_text = tk.Text(log_body, wrap="word")
        self.log_text.bind("<Key>", self._block_log_editing)
        log_scrollbar = ttk.Scrollbar(log_body, orient="vertical", command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=log_scrollbar.set)
        self.log_text.pack(side="left", fill="both", expand=True)
        log_scrollbar.pack(side="right", fill="y")
        paned.add(log_container, weight=2)

        self.filter_mode = False
        self._rows: dict = {}
        self._log_lock = threading.Lock()
        for w in watchers:
            self._add_row(w)

        self._load_log_history()
        self._tick()

    _LOG_NAV_KEYSYMS = {
        "Left", "Right", "Up", "Down", "Home", "End", "Prior", "Next",
        "Shift_L", "Shift_R", "Control_L", "Control_R",
    }

    def _block_log_editing(self, event) -> Optional[str]:
        """Лог должен оставаться читаемым мышью (выделение/Ctrl+C/Ctrl+A), но не редактируемым
        с клавиатуры. Пропускаем клавиши навигации/выделения и Ctrl+C/Ctrl+A как есть, всё
        остальное (обычный ввод, Delete/Backspace и т.п.) блокируем."""
        if event.keysym in self._LOG_NAV_KEYSYMS:
            return None
        ctrl_pressed = bool(event.state & 0x4)
        if ctrl_pressed and event.keysym.lower() in ("c", "a"):
            return None
        return "break"

    # --- вызывается из фоновых потоков (watcher.py) -----------------------------

    def log(self, repo_name: str, message: str) -> None:
        line = f"[{time.strftime('%H:%M:%S')}] [{repo_name}] {message}"
        self._append_log_file(line)
        self.root.after(0, self._append_log, line)

    def _append_log_file(self, line: str) -> None:
        with self._log_lock:
            try:
                with open(_LOG_FILE_PATH, "a", encoding="utf-8") as f:
                    f.write(line + "\n")
            except OSError:
                pass  # запись в файл — не критично, окно всё равно должно работать дальше

    def _load_log_history(self) -> None:
        """При старте подтягиваем хвост лога с прошлых сессий, чтобы окно не начиналось с
        пустоты — раньше весь журнал терялся при каждом перезапуске программы."""
        try:
            lines = _LOG_FILE_PATH.read_text(encoding="utf-8").splitlines()
        except OSError:
            return
        if not lines:
            return
        tail = lines[-_MAX_LOG_LINES:]
        self.log_text.insert("end", "\n".join(tail) + "\n")
        self.log_text.insert("end", "── новый запуск программы ──\n")
        self.log_text.see("end")

    def ask_yes_no(self, watcher, message: str) -> bool:
        pq = PendingQuestion(kind="yes_no", message=message)
        watcher.pending_question = pq
        self.root.after(0, self._show_pending_dialog, watcher, pq)
        pq.event.wait()
        watcher.pending_question = None
        return bool(pq.result)

    def ask_choice(self, watcher, branch: str, diff_lines: List[str]) -> "SyncChoice":
        pq = PendingQuestion(kind="choice", branch=branch, diff_lines=diff_lines)
        watcher.pending_question = pq
        self.root.after(0, self._show_pending_dialog, watcher, pq)
        pq.event.wait()
        watcher.pending_question = None
        return pq.result  # type: ignore[return-value]

    def reopen_pending(self, watcher) -> None:
        pq = watcher.pending_question
        if pq is not None:
            self._show_pending_dialog(watcher, pq)

    def add_row_for(self, watcher) -> None:
        self.root.after(0, self._add_row, watcher)

    # --- внутреннее (главный поток) ---------------------------------------------

    def _force_focus(self) -> None:
        self.root.deiconify()
        self.root.lift()
        self.root.focus_force()

    def _show_pending_dialog(self, watcher, pq: PendingQuestion) -> None:
        self._force_focus()
        win = tk.Toplevel(self.root)
        win.title(f"AutoSync — {watcher.name}")
        win.transient(self.root)

        def close_without_answer():
            win.destroy()  # НЕ трогаем pq.event — вопрос остаётся открытым, строка красная

        win.protocol("WM_DELETE_WINDOW", close_without_answer)

        if pq.kind == "yes_no":
            tk.Label(win, text=pq.message, wraplength=420, justify="left").pack(padx=16, pady=16)
            buttons = tk.Frame(win)
            buttons.pack(pady=(0, 12))

            def answer(value: bool):
                pq.result = value
                pq.event.set()
                win.destroy()

            tk.Button(buttons, text="Да", width=10, command=lambda: answer(True)).pack(side="left", padx=8)
            tk.Button(buttons, text="Нет", width=10, command=lambda: answer(False)).pack(side="left", padx=8)
        else:
            tk.Label(win, text=f"Расхождение в ветке {pq.branch!r}:", justify="left").pack(
                padx=16, pady=(16, 4), anchor="w"
            )
            diff_box = tk.Text(win, height=min(10, max(3, len(pq.diff_lines))), width=60)
            diff_box.insert("1.0", "\n".join(pq.diff_lines) if pq.diff_lines else "(нет данных о разнице)")
            diff_box.configure(state="disabled")
            diff_box.pack(padx=16, pady=4)

            buttons = tk.Frame(win)
            buttons.pack(pady=(4, 16))

            def answer(value: "SyncChoice"):
                pq.result = value
                pq.event.set()
                win.destroy()

            tk.Button(buttons, text="Оставить локальное", width=20,
                      command=lambda: answer(SyncChoice.TAKE_LOCAL)).pack(side="left", padx=6)
            tk.Button(buttons, text="Взять с git", width=16,
                      command=lambda: answer(SyncChoice.TAKE_GIT)).pack(side="left", padx=6)
            tk.Button(buttons, text="Mergetool", width=14,
                      command=lambda: answer(SyncChoice.OPEN_MERGETOOL)).pack(side="left", padx=6)

        _finalize_toplevel(win)

    def _append_log(self, line: str) -> None:
        self.log_text.insert("end", line + "\n")
        line_count = int(self.log_text.index("end-1c").split(".")[0])
        if line_count > _MAX_LOG_LINES:
            self.log_text.delete("1.0", f"{line_count - _MAX_LOG_LINES}.0")
        self.log_text.see("end")

    def _copy_log(self) -> None:
        # Отдельная кнопка "скопировать весь лог целиком" — быстрее, чем выделять мышью весь
        # текст. Выделение конкретного куска мышью + Ctrl+C теперь тоже работает (см.
        # _block_log_editing выше — раньше state="disabled" на некоторых сборках Tk блокировало
        # и это тоже, оставляя рабочей только эту кнопку).
        self.root.clipboard_clear()
        self.root.clipboard_append(self.log_text.get("1.0", "end-1c"))

    def _add_row(self, watcher) -> None:
        row = RepoRow(self.rows_frame, watcher, self)
        # Ключ — сам объект watcher (id), а не watcher.name: имя теперь можно менять через
        # "Изменить репозиторий...", и по строковому имени строка была бы потеряна после смены.
        self._rows[id(watcher)] = row

    def _toggle_filter(self) -> None:
        self.filter_mode = not self.filter_mode
        self._apply_filter()

    def _apply_filter(self) -> None:
        for w in self.watchers:
            row = self._rows.get(id(w))
            if row is None:
                continue
            show = (not self.filter_mode) or (w.pending_question is not None)
            if show:
                row.pack(fill="x", padx=6, pady=3)
            else:
                row.pack_forget()

    def _open_add_dialog(self) -> None:
        win = tk.Toplevel(self.root)
        win.title("Добавить репозиторий")

        # Порядок и подписи — по вашему списку (папка хранения / ветка для push / интервал),
        # плюс два необязательных поля с понятным объяснением, что это и зачем — заполнять их
        # нужно не всегда:
        #   "Имя" — просто подпись репозитория в списке и в файле состояния (state.json). Если
        #       оставить пустым — возьмём имя папки автоматически, ничего вводить не обязательно.
        #   "Папка слежения внутри репозитория" — НЕ путь к самому репозиторию (это отдельное
        #       поле выше), а конкретная подпапка ВНУТРИ него, изменения в которой должны сразу
        #       пушиться (например у вас — "Godot_Template_Life_Operator", а не весь проект
        #       целиком, где много не относящихся к делу файлов). Если оставить пустым — будет
        #       следить за всей папкой репозитория.
        # Git-адрес (origin) отдельно не спрашиваем — берём как уже настроено в самой папке
        # (git remote), спрашиваем только ветку, потому что именно её вы выбираете сами.
        fields = {}
        rows = [
            ("path", "Папка хранения (где лежит .git)", True),
            ("branch", "Ветка для push", True),
            ("interval", "Через сколько секунд проверять git", True),
            ("name", "Имя (необязательно — по умолчанию из папки)", False),
            ("watch_path", "Папка слежения внутри репозитория (необязательно — по умолчанию вся папка)", False),
        ]
        for i, (key, label, _required) in enumerate(rows):
            tk.Label(win, text=label, wraplength=260, justify="left").grid(
                row=i, column=0, sticky="w", padx=8, pady=4
            )
            entry = tk.Entry(win, width=40)
            entry.grid(row=i, column=1, padx=8, pady=4)
            fields[key] = entry
        fields["interval"].insert(0, "1800")

        def submit():
            path = fields["path"].get().strip()
            branch = fields["branch"].get().strip()
            if not (path and branch):
                return
            name = fields["name"].get().strip() or Path(path).name
            watch_path = fields["watch_path"].get().strip()  # пусто — следим за всей папкой репозитория
            repo_cfg = {
                "name": name,
                "path": path,
                "branch": branch,
                "watch_paths": [watch_path],
            }
            try:
                interval_seconds = int(fields["interval"].get().strip() or "1800")
            except ValueError:
                interval_seconds = 1800
            watcher = self._on_add_repo_cb(repo_cfg, interval_seconds)
            self.watchers.append(watcher)
            self._add_row(watcher)
            win.destroy()

        tk.Button(win, text="Добавить", command=submit).grid(row=len(rows), column=0, columnspan=2, pady=10)
        _finalize_toplevel(win)

    def on_edit_repo(self, watcher, **changes) -> None:
        self._on_edit_repo_cb(watcher, **changes)

    def manual_version_change(self, watcher, new_version) -> None:
        self._on_manual_version_change_cb(watcher, new_version)

    def on_toggle_run(self, watcher, running: bool) -> None:
        self._on_toggle_run_cb(watcher, running)

    def _tick(self) -> None:
        pending_count = sum(1 for w in self.watchers if w.pending_question is not None)
        # Раньше при 0 проблем кнопка вообще исчезала ("ПРОБЛЕМЫ (0)" не было видно совсем) —
        # теперь кнопка всегда на месте, просто со счётчиком.
        self.alert_button.configure(text=f"ПРОБЛЕМЫ ({pending_count})")
        if self.filter_mode and pending_count == 0:
            self.filter_mode = False
        self._apply_filter()
        for w in self.watchers:
            row = self._rows.get(id(w))
            if row is not None:
                row.refresh()
        self.root.after(500, self._tick)

    def run(self) -> None:
        """Блокирует до закрытия окна — должно вызываться из ГЛАВНОГО потока программы."""
        self.root.mainloop()
