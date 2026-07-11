#!/usr/bin/env python3
"""Generate archive-level notice evidence for the release SBOM components."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sys
import zipfile


NOTICE_PATH = re.compile(
    r"(^|/)(license|notice|copying|copyright)([._/-].*|$)",
    re.IGNORECASE,
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def notice_entries(path: Path) -> list[str]:
    if not zipfile.is_zipfile(path):
        return []
    with zipfile.ZipFile(path) as archive:
        entries = [
            info.filename
            for info in archive.infolist()
            if not info.is_dir() and NOTICE_PATH.search(info.filename)
        ]
        try:
            classes_jar = archive.read("classes.jar")
        except KeyError:
            classes_jar = None
        if classes_jar is not None:
            with zipfile.ZipFile(io.BytesIO(classes_jar)) as nested:
                entries.extend(
                    f"classes.jar!/{info.filename}"
                    for info in nested.infolist()
                    if not info.is_dir() and NOTICE_PATH.search(info.filename)
                )
    return sorted(set(entries))


def artifact_filename(component: dict[str, object]) -> str:
    for prop in component.get("properties", []):
        if prop.get("name") == "artifact.file":
            return str(prop["value"])
    raise ValueError(
        f"SBOM component has no artifact.file property: "
        f"{component.get('group')}:{component.get('name')}:{component.get('version')}"
    )


def locate_artifact(
    component: dict[str, object],
    expected_hash: str,
    local_aars: Path,
    gradle_cache: Path,
    hash_cache: dict[Path, str],
) -> Path:
    group = str(component.get("group", ""))
    name = str(component.get("name", ""))
    version = str(component.get("version", ""))
    filename = artifact_filename(component)
    if group == "com.runanywhere.local":
        candidates = [local_aars / filename]
    else:
        coordinate_dir = gradle_cache / group / name / version
        candidates = [
            path
            for path in coordinate_dir.rglob("*")
            if path.is_file() and path.suffix.lower() in {".aar", ".jar", ".zip"}
        ]

    for candidate in candidates:
        if not candidate.is_file():
            continue
        actual_hash = hash_cache.setdefault(candidate, sha256(candidate))
        if actual_hash == expected_hash:
            return candidate
    coordinate = f"{group}:{name}:{version}"
    raise FileNotFoundError(
        f"could not locate exact SBOM artifact {coordinate} ({filename}, {expected_hash})"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sbom", type=Path, required=True)
    parser.add_argument("--local-aars", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    sbom = json.loads(args.sbom.read_text(encoding="utf-8"))
    components = sbom.get("components")
    if sbom.get("bomFormat") != "CycloneDX" or not isinstance(components, list):
        raise ValueError("input is not the expected CycloneDX SBOM")

    gradle_home = Path(os.environ.get("GRADLE_USER_HOME", Path.home() / ".gradle"))
    gradle_cache = gradle_home / "caches" / "modules-2" / "files-2.1"
    hash_cache: dict[Path, str] = {}
    inventory_components: list[dict[str, object]] = []
    for component in components:
        hashes = component.get("hashes", [])
        expected_hashes = [
            str(entry["content"])
            for entry in hashes
            if entry.get("alg") == "SHA-256"
        ]
        if len(expected_hashes) != 1:
            raise ValueError(
                "each SBOM component must have exactly one SHA-256 hash: "
                f"{component.get('group')}:{component.get('name')}:{component.get('version')}"
            )
        expected_hash = expected_hashes[0]
        artifact = locate_artifact(
            component,
            expected_hash,
            args.local_aars,
            gradle_cache,
            hash_cache,
        )
        inventory_components.append(
            {
                "group": component.get("group", ""),
                "name": component.get("name", ""),
                "version": component.get("version", ""),
                "artifact": artifact_filename(component),
                "sha256": expected_hash,
                "noticeEntries": notice_entries(artifact),
            }
        )

    inventory_components.sort(
        key=lambda item: (
            str(item["group"]),
            str(item["name"]),
            str(item["version"]),
            str(item["artifact"]),
        )
    )
    with_evidence = sum(
        bool(component["noticeEntries"]) for component in inventory_components
    )
    output = {
        "schemaVersion": 1,
        "generatedAt": dt.datetime.now(dt.timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
        "applicationVersion": sbom.get("metadata", {})
        .get("component", {})
        .get("version", ""),
        "componentCount": len(inventory_components),
        "componentsWithNoticeEntries": with_evidence,
        "componentsWithoutNoticeEntries": len(inventory_components) - with_evidence,
        "components": inventory_components,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1)
