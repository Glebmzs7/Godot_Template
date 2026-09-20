"""
Обёртка над git-командами для AutoSync.

Важно: здесь НЕТ своей логики трёхстороннего слияния — конфликты решает сам git
(`git merge` / `git mergetool`), это уже готовый, проверенный инструмент (ответ на вопрос
«есть ли готовые шаблоны для решения этих вопросов» — да, не изобретаем велосипед).
Наша обвязка только читает состояние (fetch/ahead-behind/diff) и, если git может разрешить
конфликт сам, — вызывает его: `git mergetool` откроет тот diff/merge-инструмент, который уже
настроен у пользователя (по умолчанию Windows предложит выбрать при первом вызове — VS Code,
Beyond Compare, kdiff3, meld и т.п. — либо оставит текстовые маркеры <<<<<<< для ручного
разрешения прямо в редакторе).
"""

import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional


class GitError(RuntimeError):
    pass


# На Windows каждый subprocess.run(["git", ...]) без этого флага открывает своё маленькое
# консольное окно (мелькает и сразу закрывается) — при частых проверках нескольких репозиториев
# это и даёт "очень много окон" при запуске. CREATE_NO_WINDOW убирает именно консоль команды,
# не трогая работу самой команды. На других ОС такого флага нет — там просто 0 (по умолчанию).
_NO_WINDOW_FLAGS = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0


def _run(repo_path: Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo_path), *args],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        creationflags=_NO_WINDOW_FLAGS,
    )
    if result.returncode != 0:
        raise GitError(f"git {' '.join(args)} failed in {repo_path}:\n{result.stderr}")
    return result.stdout.strip()


def fetch(repo_path: Path, remote: str = "origin") -> None:
    _run(repo_path, "fetch", "--prune", remote)


def current_branch(repo_path: Path) -> str:
    return _run(repo_path, "rev-parse", "--abbrev-ref", "HEAD")


def remote_url(repo_path: Path, remote: str = "origin") -> Optional[str]:
    """Для ссылки на git в окне (пункт 2 списка строки) — берём как есть, что настроено у git,
    без своих догадок."""
    try:
        return _run(repo_path, "remote", "get-url", remote)
    except GitError:
        return None


@dataclass
class AheadBehind:
    ahead: int   # локальных коммитов, которых нет в remote
    behind: int  # коммитов в remote, которых нет локально


def ahead_behind(repo_path: Path, branch: Optional[str] = None, remote: str = "origin") -> AheadBehind:
    branch = branch or current_branch(repo_path)
    out = _run(repo_path, "rev-list", "--left-right", "--count", f"{branch}...{remote}/{branch}")
    ahead_s, behind_s = out.split()
    return AheadBehind(ahead=int(ahead_s), behind=int(behind_s))


def diff_name_status(repo_path: Path, ref_a: str, ref_b: str) -> List[str]:
    out = _run(repo_path, "diff", "--name-status", ref_a, ref_b)
    return out.splitlines() if out else []


def has_local_changes(repo_path: Path) -> bool:
    return bool(_run(repo_path, "status", "--porcelain"))


def add_commit(repo_path: Path, paths: List[str], message: str) -> None:
    _run(repo_path, "add", *paths)
    _run(repo_path, "commit", "-m", message)


def push(repo_path: Path, branch: Optional[str] = None, remote: str = "origin") -> None:
    branch = branch or current_branch(repo_path)
    _run(repo_path, "push", remote, branch)


def tag_exists(repo_path: Path, tag: str) -> bool:
    out = _run(repo_path, "tag", "--list", tag)
    return bool(out)


def create_and_push_tag(repo_path: Path, tag: str, message: str, remote: str = "origin") -> None:
    if tag_exists(repo_path, tag):
        # Коллизия версии (см. п.1.2.2 обсуждения) — git сам отказывает на дубликат тега,
        # отдельную логику сравнения писать не нужно, просто ловим и поднимаем понятную ошибку.
        raise GitError(f"Тег {tag!r} уже существует — коллизия версии, нужно решение пользователя")
    _run(repo_path, "tag", "-a", tag, "-m", message)
    _run(repo_path, "push", remote, tag)


def create_tag(repo_path: Path, tag: str, message: str) -> None:
    """Только локально — создать тег, БЕЗ пуша (используется вместе с push_atomic, чтобы ветка и
    тег уходили на сервер одной командой)."""
    if tag_exists(repo_path, tag):
        raise GitError(f"Тег {tag!r} уже существует — коллизия версии, нужно решение пользователя")
    _run(repo_path, "tag", "-a", tag, "-m", message)


def delete_local_tag(repo_path: Path, tag: str) -> None:
    """Убрать локальный тег, который не удалось (атомарно) запушить — чтобы следующая попытка
    со следующим номером пуша не спотыкалась о него как о 'уже существующий'."""
    try:
        _run(repo_path, "tag", "-d", tag)
    except GitError:
        pass  # тега и так нет — ничего страшного


def push_atomic(repo_path: Path, branch: str, tag: str, remote: str = "origin", force: bool = False) -> None:
    """Пушим ветку и тег ОДНОЙ атомарной командой (git push --atomic): git либо принимает ОБА
    ref-а, либо (при отклонении любого из них — коллизия на сервере, разрыв связи, отставшая
    ветка и т.п.) НЕ принимает НИ ОДНОГО. Так код никогда не окажется на GitHub без версии,
    и наоборот — тег никогда не появится без соответствующего ему кода."""
    args = ["push", "--atomic"]
    if force:
        args.append("--force-with-lease")
    args += [remote, branch, tag]
    _run(repo_path, *args)


def latest_tag_on_branch(repo_path: Path, branch: Optional[str] = None) -> Optional[str]:
    branch = branch or current_branch(repo_path)
    try:
        return _run(repo_path, "describe", "--tags", "--abbrev=0", branch)
    except GitError:
        return None  # тегов ещё нет


def open_mergetool(repo_path: Path) -> None:
    """Открыть настроенный у пользователя инструмент слияния конфликтов.

    Ничего не решает сам — просто передаёт управление git/внешнему diff-инструменту.
    """
    subprocess.run(["git", "-C", str(repo_path), "mergetool"])


def reset_hard(repo_path: Path, ref: str) -> None:
    """ДЕЙСТВИЕ_ОБНОВИТЬ_ЛОКАЛЬНО: отбросить локальные файлы и встать на ref (обычно
    origin/<branch>). Вызывается только после явного подтверждения пользователя."""
    _run(repo_path, "reset", "--hard", ref)


def push_force_with_lease(repo_path: Path, branch: Optional[str] = None, remote: str = "origin") -> None:
    """Для варианта 'оставить локальную версию' в ПРОЦЕСС_СЛИЯНИЯ_РАСХОЖДЕНИЙ. force-with-lease
    (не голый --force) — откажет, если на remote появилось что-то новое уже ПОСЛЕ того, как мы
    в последний раз его видели, вместо того чтобы затереть это молча."""
    branch = branch or current_branch(repo_path)
    _run(repo_path, "push", "--force-with-lease", remote, branch)
