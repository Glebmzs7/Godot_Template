"""
Формат и разбор версии AutoSync.

Версия — это ТОЛЬКО то, что реально стоит тегом на git. Букв-статусов (L/G/OG/C/M) больше нет —
решили, что это лишнее усложнение (см. чат «Автоматизация»): вся история "откуда мы знаем, что
происходит с версией" теперь живёт не в самой версии, а в логике сверки (см. watcher.py —
SVERKA_VERSIY и связанные действия).

Пример без промежуточного этапа наследования:
    2,1.5,3.7,4,9
Пример с промежуточным этапом (наследование правок между проектами):
    2,1.5,3.1,2.7,4,9

Структура:
    <Stable>,<StablePatch>.<Beta>,<BetaPush>[.<ProjectSync>,<ProjectSyncPush>].<DevId>,<TaskLabel>,<PushCount>
"""

from dataclasses import dataclass
from typing import Optional, Tuple
import re


@dataclass
class Version:
    stable: int
    stable_patch: int
    beta: int
    beta_push: int
    dev_id: int
    task_label: int
    push_count: int
    project_sync: Optional[Tuple[int, int]] = None  # (checkpoint, push) — только для наследования между проектами

    def format(self) -> str:
        parts = [f"{self.stable},{self.stable_patch}", f"{self.beta},{self.beta_push}"]
        if self.project_sync is not None:
            ps_checkpoint, ps_push = self.project_sync
            parts.append(f"{ps_checkpoint},{ps_push}")
        parts.append(f"{self.dev_id},{self.task_label},{self.push_count}")
        return ".".join(parts)

    def __str__(self) -> str:
        return self.format()


_VERSION_RE = re.compile(
    r"^(?P<stable>\d+),(?P<stable_patch>\d+)\."
    r"(?P<beta>\d+),(?P<beta_push>\d+)"
    r"(?:\.(?P<ps_checkpoint>\d+),(?P<ps_push>\d+))?"
    r"\.(?P<dev_id>\d+),(?P<task_label>\d+),(?P<push_count>\d+)$"
)


def parse(text: str) -> Version:
    """Разобрать строку версии вида '2,1.5,3.7,4,9' обратно в Version.

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
        project_sync=project_sync,
    )


if __name__ == "__main__":
    # Быстрая самопроверка формата — запустить: python version.py
    v = Version(stable=2, stable_patch=1, beta=5, beta_push=3, dev_id=7, task_label=4, push_count=9)
    s = v.format()
    assert s == "2,1.5,3.7,4,9", s
    assert parse(s) == v, parse(s)

    v2 = Version(stable=2, stable_patch=1, beta=5, beta_push=3, dev_id=7, task_label=4, push_count=9,
                 project_sync=(1, 2))
    s2 = v2.format()
    assert s2 == "2,1.5,3.1,2.7,4,9", s2
    assert parse(s2) == v2, parse(s2)

    print("version.py: самопроверка пройдена")
