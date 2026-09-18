"""
Формат и разбор версии AutoSync.

Полная строка (пример без промежуточного этапа наследования):
    G2,1.5,3.7,4,9
Пример с промежуточным этапом (наследование правок между проектами):
    G2,1.5,3.1,2.7,4,9

Структура (без буквы статуса в начале):
    <Stable>,<StablePatch>.<Beta>,<BetaPush>[.<ProjectSync>,<ProjectSyncPush>].<DevId>,<TaskLabel>,<PushCount>

Буква(ы) статуса приписываются ПЕРЕД всей строкой целиком (не по группам — решили не усложнять
на первом этапе, см. чат «Автоматизация»).
"""

from dataclasses import dataclass
from typing import Optional, Tuple
import re

# --- Статусы -----------------------------------------------------------------

STATUS_CODES = {
    "L":  "Local — изменено локально, ещё не отправлено в git",
    "G":  "Git — подтверждено, отправлено и совпадает с remote",
    "OG": "Old-vs-Git — локальная версия отстала, в git есть более новое обновление",
    "C":  "Conflict — локальная и удалённая версии разошлись по-разному (нужно решение пользователя)",
    "M":  "Missing — ожидаемый тег не найден в истории (пропуск из-за сбоя), восстановлено по факту git",
}

VALID_STATUSES = tuple(STATUS_CODES.keys())

# --- Модель версии -------------------------------------------------------------

@dataclass
class Version:
    stable: int
    stable_patch: int
    beta: int
    beta_push: int
    dev_id: int
    task_label: int
    push_count: int
    status: str = "L"
    project_sync: Optional[Tuple[int, int]] = None  # (checkpoint, push) — только для наследования между проектами

    def format(self) -> str:
        if self.status not in VALID_STATUSES:
            raise ValueError(f"Неизвестный статус: {self.status!r}, ожидался один из {VALID_STATUSES}")
        parts = [f"{self.stable},{self.stable_patch}", f"{self.beta},{self.beta_push}"]
        if self.project_sync is not None:
            ps_checkpoint, ps_push = self.project_sync
            parts.append(f"{ps_checkpoint},{ps_push}")
        parts.append(f"{self.dev_id},{self.task_label},{self.push_count}")
        return self.status + ".".join(parts)

    def __str__(self) -> str:
        return self.format()


_STATUS_RE = "|".join(sorted(VALID_STATUSES, key=len, reverse=True))  # OG раньше G, чтобы не откусило по одной букве
_VERSION_RE = re.compile(
    rf"^(?P<status>{_STATUS_RE})"
    r"(?P<stable>\d+),(?P<stable_patch>\d+)\."
    r"(?P<beta>\d+),(?P<beta_push>\d+)"
    r"(?:\.(?P<ps_checkpoint>\d+),(?P<ps_push>\d+))?"
    r"\.(?P<dev_id>\d+),(?P<task_label>\d+),(?P<push_count>\d+)$"
)


def parse(text: str) -> Version:
    """Разобрать строку версии вида 'G2,1.5,3.7,4,9' обратно в Version.

    Бросает ValueError, если строка не соответствует формату — это ожидаемое поведение:
    лучше упасть сразу и явно, чем молча продолжить с неправильно понятой версией.
    """
    m = _VERSION_RE.match(text.strip())
    if not m:
        raise ValueError(f"Не удалось разобрать версию: {text!r}")
    g = m.groupdict()
    project_sync = None
    if g["ps_checkpoint"] is not None:
        project_sync = (int(g["ps_checkpoint"]), int(g["ps_push"]))
    return Version(
        stable=int(g["stable"]),
        stable_patch=int(g["stable_patch"]),
        beta=int(g["beta"]),
        beta_push=int(g["beta_push"]),
        dev_id=int(g["dev_id"]),
        task_label=int(g["task_label"]),
        push_count=int(g["push_count"]),
        status=g["status"],
        project_sync=project_sync,
    )


if __name__ == "__main__":
    # Быстрая самопроверка формата — запустить: python version.py
    v = Version(stable=2, stable_patch=1, beta=5, beta_push=3, dev_id=7, task_label=4, push_count=9, status="G")
    s = v.format()
    assert s == "G2,1.5,3.7,4,9", s
    assert parse(s) == v, parse(s)

    v2 = Version(stable=2, stable_patch=1, beta=5, beta_push=3, dev_id=7, task_label=4, push_count=9,
                 status="OG", project_sync=(1, 2))
    s2 = v2.format()
    assert s2 == "OG2,1.5,3.1,2.7,4,9", s2
    assert parse(s2) == v2, parse(s2)

    print("version.py: самопроверка пройдена")
