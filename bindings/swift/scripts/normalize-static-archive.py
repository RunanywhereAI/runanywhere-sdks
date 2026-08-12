#!/usr/bin/env python3
"""Canonicalize path-derived cctools archive member names in place."""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile


ARCHIVE_MAGIC = b"!<arch>\n"
HEADER_SIZE = 60
HEADER_TRAILER = b"`\n"
HASHED_OBJECT_NAME = re.compile(rb"^(?P<stem>.+)-[0-9a-f]{32}(?P<suffix>\.o)$")


def _parse_decimal(field: bytes, label: str, archive: Path) -> int:
    value = field.strip()
    if not value or not value.isdigit():
        raise ValueError(f"{archive}: invalid {label} field {field!r}")
    return int(value)


def _members(archive: Path) -> list[tuple[int, int, bytes, int, int]]:
    """Return index, name offset/name, and payload offset/size for each member."""
    result: list[tuple[int, int, bytes, int, int]] = []
    archive_size = archive.stat().st_size

    with archive.open("rb") as stream:
        if stream.read(len(ARCHIVE_MAGIC)) != ARCHIVE_MAGIC:
            raise ValueError(f"{archive}: invalid static archive magic")

        offset = len(ARCHIVE_MAGIC)
        index = 0
        while offset < archive_size:
            stream.seek(offset)
            header = stream.read(HEADER_SIZE)
            if len(header) != HEADER_SIZE or header[-2:] != HEADER_TRAILER:
                raise ValueError(f"{archive}: invalid member header at byte {offset}")

            member_size = _parse_decimal(header[48:58], "member size", archive)
            member_start = offset + HEADER_SIZE
            member_end = member_start + member_size
            if member_end > archive_size:
                raise ValueError(f"{archive}: truncated member at byte {offset}")

            raw_name = header[:16].rstrip(b" ")
            name_offset = offset
            name = raw_name.rstrip(b"/")
            payload_offset = member_start
            payload_size = member_size

            if raw_name.startswith(b"#1/"):
                name_size = _parse_decimal(raw_name[3:], "extended name size", archive)
                if name_size == 0 or name_size > member_size:
                    raise ValueError(f"{archive}: invalid extended member name at byte {offset}")
                stream.seek(member_start)
                encoded_name = stream.read(name_size)
                name = encoded_name.split(b"\0", 1)[0]
                name_offset = member_start
                payload_offset += name_size
                payload_size -= name_size

            result.append((index, name_offset, name, payload_offset, payload_size))
            if member_size % 2:
                stream.seek(member_end)
                if stream.read(1) != b"\n":
                    raise ValueError(f"{archive}: invalid member padding at byte {member_end}")
            offset = member_end + (member_size % 2)
            index += 1

        if offset != archive_size:
            raise ValueError(f"{archive}: invalid trailing archive bytes")

    return result


def normalize(archive: Path, expected: dict[bytes, int]) -> int:
    if archive.is_symlink() or not archive.is_file():
        raise ValueError(f"{archive}: expected a regular static archive")

    members = _members(archive)
    targets = [member for member in members if HASHED_OBJECT_NAME.fullmatch(member[2])]
    actual = Counter(
        match.group("stem")
        for member in targets
        if (match := HASHED_OBJECT_NAME.fullmatch(member[2])) is not None
    )
    if actual != expected:
        render = lambda values: ", ".join(  # noqa: E731 - compact diagnostic helper
            f"{stem.decode(errors='replace')}={count}"
            for stem, count in sorted(values.items())
        ) or "none"
        raise ValueError(
            f"{archive}: hashed member inventory changed "
            f"(expected {render(expected)}; found {render(actual)})"
        )

    reserved_names = {member[2] for member in members if member not in targets}
    replacements: list[tuple[int, bytes]] = []

    with archive.open("rb") as stream:
        for index, name_offset, name, payload_offset, payload_size in targets:
            match = HASHED_OBJECT_NAME.fullmatch(name)
            if match is None:  # Kept explicit for type narrowing and fail-closed behavior.
                raise ValueError(f"{archive}: invalid generated member name {name!r}")

            stream.seek(payload_offset)
            digest = hashlib.sha256()
            remaining = payload_size
            while remaining:
                chunk = stream.read(min(remaining, 1024 * 1024))
                if not chunk:
                    raise ValueError(f"{archive}: truncated payload for {name!r}")
                digest.update(chunk)
                remaining -= len(chunk)
            digest.update(index.to_bytes(8, byteorder="big"))

            counter = 0
            while True:
                candidate_digest = digest.copy()
                candidate_digest.update(counter.to_bytes(4, byteorder="big"))
                candidate = (
                    match.group("stem")
                    + b"-"
                    + candidate_digest.hexdigest()[:32].encode("ascii")
                    + match.group("suffix")
                )
                if candidate not in reserved_names:
                    break
                counter += 1

            if len(candidate) != len(name):
                raise ValueError(f"{archive}: normalized member name changed length")
            reserved_names.add(candidate)
            if candidate != name:
                replacements.append((name_offset, candidate))

    if not replacements:
        return 0

    mode = stat.S_IMODE(archive.stat().st_mode)
    descriptor, temporary_path = tempfile.mkstemp(prefix=f".{archive.name}.", dir=archive.parent)
    os.close(descriptor)
    try:
        shutil.copyfile(archive, temporary_path)
        with open(temporary_path, "r+b") as stream:
            for name_offset, candidate in replacements:
                stream.seek(name_offset)
                stream.write(candidate)
        os.chmod(temporary_path, mode)
        os.replace(temporary_path, archive)
    finally:
        if os.path.exists(temporary_path):
            os.unlink(temporary_path)

    return len(replacements)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("expected", nargs="*", metavar="STEM=COUNT")
    arguments = parser.parse_args()

    try:
        expected: dict[bytes, int] = {}
        for specification in arguments.expected:
            stem, separator, count_text = specification.rpartition("=")
            if not separator or not stem or not count_text.isdecimal() or int(count_text) <= 0:
                raise ValueError(f"invalid expected member specification {specification!r}")
            encoded_stem = stem.encode("ascii")
            if encoded_stem in expected:
                raise ValueError(f"duplicate expected member stem {stem!r}")
            expected[encoded_stem] = int(count_text)
        count = normalize(arguments.archive, expected)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    if count:
        print(f"  normalized {count} path-derived member name(s): {arguments.archive}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
