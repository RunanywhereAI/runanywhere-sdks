#!/usr/bin/env python3
"""Require every non-signature-metadata AAB entry to be JAR-manifest signed."""

from __future__ import annotations

import json
import re
import sys
import zipfile
from pathlib import Path


SIGNATURE_METADATA = re.compile(
    r"^META-INF/(?:MANIFEST\.MF|[^/]+\.(?:SF|RSA|DSA|EC))$",
    re.IGNORECASE,
)
SIGNATURE_FILE = re.compile(r"^META-INF/([^/]+)\.SF$", re.IGNORECASE)
SIGNATURE_BLOCK = re.compile(r"^META-INF/([^/]+)\.(?:RSA|DSA|EC)$", re.IGNORECASE)


def manifest_sections(raw: bytes) -> list[dict[str, str]]:
    lines: list[str] = []
    for line in raw.decode("utf-8", errors="strict").splitlines():
        if line.startswith(" "):
            if not lines:
                raise ValueError("invalid continuation in JAR manifest")
            lines[-1] += line[1:]
        else:
            lines.append(line)

    sections: list[dict[str, str]] = []
    current: dict[str, str] = {}
    for line in [*lines, ""]:
        if not line:
            if current:
                sections.append(current)
                current = {}
            continue
        if ": " not in line:
            raise ValueError("invalid attribute in JAR manifest")
        name, value = line.split(": ", 1)
        if name in current:
            raise ValueError("duplicate attribute in JAR manifest section")
        current[name] = value
    return sections


def verify(path: Path) -> int:
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if len(names) != len(set(names)):
            raise ValueError("AAB contains a duplicate ZIP entry")
        signature_files = [match for name in names if (match := SIGNATURE_FILE.fullmatch(name))]
        signature_blocks = [match for name in names if (match := SIGNATURE_BLOCK.fullmatch(name))]
        if len(signature_files) != 1 or len(signature_blocks) != 1:
            raise ValueError("AAB must contain exactly one JAR signature-file/block pair")
        if signature_files[0].group(1).lower() != signature_blocks[0].group(1).lower():
            raise ValueError("AAB JAR signature-file/block names do not match")
        try:
            manifest = archive.read("META-INF/MANIFEST.MF")
        except KeyError as exc:
            raise ValueError("AAB has no JAR signature manifest") from exc

        signed: dict[str, dict[str, str]] = {}
        for section in manifest_sections(manifest)[1:]:
            entry = section.get("Name")
            if not entry:
                raise ValueError("JAR manifest payload section has no Name")
            if entry in signed:
                raise ValueError("duplicate payload entry in JAR manifest")
            if "sha-256-digest" not in {key.lower() for key in section}:
                raise ValueError("JAR manifest payload section has no SHA-256 digest")
            signed[entry] = section

        actual_payload: set[str] = set()
        for info in infos:
            if info.is_dir() or SIGNATURE_METADATA.fullmatch(info.filename):
                continue
            actual_payload.add(info.filename)
            if info.filename not in signed:
                raise ValueError("AAB contains an unsigned payload entry")

        if not actual_payload:
            raise ValueError("AAB contains no signed payload entries")
        if signed.keys() != actual_payload:
            raise ValueError("AAB is missing a payload entry declared by its signed manifest")
        return len(actual_payload)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"Usage: {Path(sys.argv[0]).name} AAB", file=sys.stderr)
        return 2
    try:
        payload_entries = verify(Path(sys.argv[1]))
    except (OSError, UnicodeError, ValueError, zipfile.BadZipFile) as exc:
        print(f"ERROR: signature coverage check failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps({"signedPayloadEntryCount": payload_entries}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
