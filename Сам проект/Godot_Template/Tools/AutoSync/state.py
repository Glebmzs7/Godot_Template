"""
Локально известная (последняя подтверждённая) версия каждого репозитория.

Храним рядом с самим AutoSync (в этой же папке), НЕ внутри репозиториев — по двум причинам:
  1. Чтобы не путать со содержимым проектов и не требовать добавлять файл в .gitignore каждого
     репозитория.
  2. Чтобы файл состояния сам не попадал в watch_paths и не триггерил собственную же проверку.

Это именно "версия, которую мы сами в прошлый раз подтвердили" — то, с чем сравнивается версия,
пришедшая с git, в SVERKA_VERSIY (см. watcher.py). Это НЕ то же самое, что self.current_tag —
current_tag просто показывает, что сейчас реально стоит на git (для строки статуса), а
known_version — это то, что мы "приняли" как своё последнее согласованное состояние.
"""

import json
from pathlib import Path
from typing import Optional

_STATE_FILE = Path(__file__).parent / "state.json"


def _load_all() -> dict:
    if not _STATE_FILE.exists():
        return {}
    return json.loads(_STATE_FILE.read_text(encoding="utf-8"))


def load_known_version(repo_name: str) -> Optional[str]:
    return _load_all().get(repo_name)


def save_known_version(repo_name: str, version_tag: str) -> None:
    data = _load_all()
    data[repo_name] = version_tag
    _STATE_FILE.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
