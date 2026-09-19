"""
Единственное, что здесь осталось — тип выбора при расхождении. Системные toast-уведомления
(win10toast) убрали: вместо "показать тост, если окно свёрнуто" теперь просто принудительно
поднимаем само окно программы поверх остальных при появлении вопроса (см. gui.py —
AutoSyncGUI._force_focus, вызывается из ask_yes_no/ask_choice).
"""

from enum import Enum


class SyncChoice(Enum):
    TAKE_LOCAL = "local"
    TAKE_GIT = "git"
    OPEN_MERGETOOL = "mergetool"
