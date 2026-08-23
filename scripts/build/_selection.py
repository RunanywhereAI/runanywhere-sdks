#!/usr/bin/env python3
"""The `current` selection pointer for a content-addressed prebuilt payload.

`current` names exactly one immutable `versions/<64-hex-receipt>` directory.
Readers resolve it, so the swap must never be delete-then-create on POSIX: a
reader landing in the gap would see no engine at all.

Windows cannot use the POSIX mechanism. Creating a symlink needs
SeCreateSymbolicLinkPrivilege, which the GitHub Actions runner service does NOT
hold -- it runs as NT AUTHORITY\\NETWORK SERVICE, and enabling Developer Mode
does not grant it either (verified on the runner by launching as that account
through a scheduled task, since an interactive SSH session runs as a different,
privileged user and cannot reproduce it). A JUNCTION needs no privilege and is
the same kind of reparse point to a directory, so Windows selects with one of
those instead.

Two consequences of that substitution, both handled here:
  * A junction stores an ABSOLUTE target, so the raw link text is not portable
    the way the POSIX relative form is. `read_target` normalizes both back to
    "versions/<receipt>" so callers compare one shape.
  * `stat.S_ISLNK` is true only for IO_REPARSE_TAG_SYMLINK, so a junction is not
    a symlink to Python: `Path.is_symlink()` returns False for one. Use
    `is_selection` rather than testing is_symlink() directly.
"""

from __future__ import annotations

import os
from pathlib import Path, PurePath, PurePosixPath
import re
import shutil
import stat
import subprocess

IS_WINDOWS = os.name == "nt"
SHA256 = re.compile(r"[0-9a-f]{64}\Z")


def _is_junction(path: Path) -> bool:
    if not IS_WINDOWS:
        return False
    # Python 3.12+ has Path.is_junction; older interpreters need the attribute.
    checker = getattr(path, "is_junction", None)
    if checker is not None:
        try:
            return bool(checker())
        except OSError:
            return False
    try:
        st = path.lstat()
    except (OSError, ValueError):
        return False
    reparse = getattr(st, "st_reparse_tag", None)
    if reparse is not None:
        return reparse == getattr(stat, "IO_REPARSE_TAG_MOUNT_POINT", 0xA0000003)
    return bool(st.st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT)


def is_selection(current: Path) -> bool:
    """True when `current` is a selection pointer rather than real content."""
    return current.is_symlink() or _is_junction(current)


def describe_kind() -> str:
    return "junction (or symlink)" if IS_WINDOWS else "symlink"


def read_target(prebuilt: Path, current: Path) -> str:
    """The selection target as a POSIX "versions/<receipt>" string.

    Raises OSError if `current` is not a selection pointer.
    """
    raw = os.readlink(current)
    # A junction's target is absolute and may carry the \\?\ device prefix.
    if IS_WINDOWS:
        for prefix in ("\\\\?\\", "\\??\\"):
            if raw.startswith(prefix):
                raw = raw[len(prefix):]
        if PurePath(raw).is_absolute():
            raw = os.path.relpath(raw, os.path.abspath(prebuilt))
    return PurePosixPath(*PurePath(raw).parts).as_posix()


def create(prebuilt: Path, receipt: str) -> None:
    """Point `prebuilt/current` at `versions/<receipt>`.

    POSIX swaps atomically via os.replace on the link itself. `mv tmp current`
    would instead FOLLOW an existing symlink-to-directory and move the temp link
    INSIDE the old target, leaving `current` untouched while reporting success --
    that silently kept the previously selected ABI.
    """
    prebuilt = Path(prebuilt)
    target = os.path.join("versions", receipt)
    current = prebuilt / "current"
    tmp = prebuilt / f".current.{os.getpid()}"

    if tmp.is_dir() and not is_selection(tmp):
        shutil.rmtree(tmp)
    elif os.path.lexists(tmp):
        _unlink_selection(tmp)

    if not IS_WINDOWS:
        os.symlink(target, tmp, target_is_directory=True)
        os.replace(tmp, current)
        return

    # A junction needs an absolute target, and cannot be swapped over an
    # existing directory entry: MoveFileEx's REPLACE_EXISTING and ReplaceFile
    # both refuse directories. So the old pointer is removed first. The gap is
    # real but safe here: selection only happens on a single-writer staging
    # host, with no concurrent reader of the same tree.
    _create_junction(tmp, (prebuilt / target).resolve())
    if os.path.lexists(current):
        _unlink_selection(current)
    os.rename(tmp, current)


def _unlink_selection(path: Path) -> None:
    """Remove a selection pointer without touching what it points at."""
    if _is_junction(path) or (IS_WINDOWS and path.is_dir()):
        # rmdir removes the reparse point itself, never the target's contents.
        os.rmdir(path)
    else:
        os.unlink(path)


def _create_junction(link: Path, target: Path) -> None:
    try:
        import _winapi

        _winapi.CreateJunction(str(target), str(link))
        return
    except (ImportError, AttributeError, OSError):
        pass
    # mklink is a cmd builtin, so it needs a shell; /J is the junction form and
    # is the one link type that does not require a privilege.
    subprocess.run(
        ["cmd", "/c", "mklink", "/J", str(link), str(target)],
        check=True, capture_output=True, text=True,
    )
