#!/usr/bin/env python3
"""Make an npm package archive publishable and optionally bundle dependencies.

Workspace manifests stay optimized for local development. This helper rewrites
only the archived package manifest, vendors explicitly requested package
archives beneath ``node_modules``, and emits normalized tar/gzip metadata so
the resulting release artifact is independent of the build machine.
"""

from __future__ import annotations

import argparse
import copy
import gzip
import io
import json
import os
import tarfile
import tempfile
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


DEPENDENCY_FIELDS = (
    "dependencies",
    "devDependencies",
    "optionalDependencies",
    "peerDependencies",
    "overrides",
    "resolutions",
)
PACKAGE_JSON = "package/package.json"


class ManifestRewriteError(RuntimeError):
    """Raised when a package archive cannot be safely rewritten."""


@dataclass(frozen=True)
class ArchiveEntry:
    """A normalized tar member and its optional file payload."""

    member: tarfile.TarInfo
    payload: bytes | None


def _rewrite_workspace_specs(value: object, exact_version: str) -> int:
    rewritten = 0
    if isinstance(value, dict):
        for key, nested in value.items():
            if isinstance(nested, str) and nested.startswith("workspace:"):
                value[key] = exact_version
                rewritten += 1
            else:
                rewritten += _rewrite_workspace_specs(nested, exact_version)
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            if isinstance(nested, str) and nested.startswith("workspace:"):
                value[index] = exact_version
                rewritten += 1
            else:
                rewritten += _rewrite_workspace_specs(nested, exact_version)
    return rewritten


def _safe_member_name(name: str, archive: Path) -> str:
    normalized = name.removeprefix("./").rstrip("/")
    path = PurePosixPath(normalized)
    if not normalized or path.is_absolute() or ".." in path.parts:
        raise ManifestRewriteError(
            f"{archive.name}: unsafe archive member path {name!r}"
        )
    return normalized


def _normalized_member(member: tarfile.TarInfo, name: str) -> tarfile.TarInfo:
    normalized = copy.copy(member)
    normalized.name = name
    normalized.uid = 0
    normalized.gid = 0
    normalized.uname = ""
    normalized.gname = ""
    normalized.mtime = 0
    normalized.pax_headers = {}
    if normalized.isdir():
        normalized.mode = 0o755
    elif normalized.isfile():
        normalized.mode = 0o755 if member.mode & 0o111 else 0o644
    return normalized


def _read_archive(archive: Path) -> dict[str, ArchiveEntry]:
    if not archive.is_file():
        raise ManifestRewriteError(f"package archive is missing: {archive}")

    entries: dict[str, ArchiveEntry] = {}
    with tarfile.open(archive, "r:gz") as bundle:
        for member in bundle.getmembers():
            name = _safe_member_name(member.name, archive)
            if name in entries:
                raise ManifestRewriteError(
                    f"{archive.name}: duplicate archive member {name}"
                )
            payload: bytes | None = None
            if member.isfile():
                source = bundle.extractfile(member)
                if source is None:
                    raise ManifestRewriteError(
                        f"{archive.name}: cannot read {member.name}"
                    )
                payload = source.read()
            entries[name] = ArchiveEntry(
                _normalized_member(member, name), payload
            )
    return entries


def _read_manifest(entries: dict[str, ArchiveEntry], archive: Path) -> dict[str, object]:
    entry = entries.get(PACKAGE_JSON)
    if entry is None or entry.payload is None:
        raise ManifestRewriteError(
            f"{archive.name}: expected one file at {PACKAGE_JSON}"
        )
    metadata = json.loads(entry.payload)
    if not isinstance(metadata, dict):
        raise ManifestRewriteError(
            f"{archive.name}: package metadata is not an object"
        )
    return metadata


def _bundle_package(
    entries: dict[str, ArchiveEntry],
    dependency_name: str,
    dependency_archive: Path,
    exact_version: str,
) -> None:
    dependency_entries = _read_archive(dependency_archive)
    dependency_metadata = _read_manifest(dependency_entries, dependency_archive)
    if dependency_metadata.get("name") != dependency_name:
        raise ManifestRewriteError(
            f"{dependency_archive.name}: package name {dependency_metadata.get('name')!r} "
            f"does not match requested bundled dependency {dependency_name!r}"
        )
    if dependency_metadata.get("version") != exact_version:
        raise ManifestRewriteError(
            f"{dependency_archive.name}: bundled dependency version "
            f"{dependency_metadata.get('version')!r} does not match {exact_version!r}"
        )

    dependency_root = PurePosixPath("package/node_modules") / dependency_name
    for source_name, entry in dependency_entries.items():
        source_path = PurePosixPath(source_name)
        if not source_path.parts or source_path.parts[0] != "package":
            raise ManifestRewriteError(
                f"{dependency_archive.name}: member is outside package/: {source_name}"
            )
        relative = PurePosixPath(*source_path.parts[1:])
        if not relative.parts:
            continue
        destination_name = (dependency_root / relative).as_posix()
        if destination_name in entries:
            raise ManifestRewriteError(
                f"{dependency_archive.name}: bundled member collides at {destination_name}"
            )
        entries[destination_name] = ArchiveEntry(
            _normalized_member(entry.member, destination_name), entry.payload
        )


def _write_archive(archive: Path, entries: dict[str, ArchiveEntry]) -> None:
    descriptor, temporary_name = tempfile.mkstemp(
        dir=archive.parent, prefix=f".{archive.name}.", suffix=".tmp"
    )
    os.close(descriptor)
    temporary_path = Path(temporary_name)
    try:
        with temporary_path.open("wb") as raw_output:
            with gzip.GzipFile(
                filename="", mode="wb", fileobj=raw_output, compresslevel=9, mtime=0
            ) as compressed_output:
                with tarfile.open(
                    fileobj=compressed_output,
                    mode="w",
                    format=tarfile.PAX_FORMAT,
                ) as destination:
                    for name in sorted(entries):
                        entry = entries[name]
                        payload = entry.payload
                        if entry.member.isfile():
                            if payload is None:
                                raise ManifestRewriteError(
                                    f"{archive.name}: missing payload for {name}"
                                )
                            entry.member.size = len(payload)
                            destination.addfile(entry.member, io.BytesIO(payload))
                        else:
                            destination.addfile(entry.member)
        os.replace(temporary_path, archive)
    finally:
        temporary_path.unlink(missing_ok=True)


def rewrite_packed_manifest(
    archive: Path,
    exact_version: str,
    bundled_packages: dict[str, Path] | None = None,
) -> int:
    """Rewrite workspace specs and vendor the requested exact dependencies."""

    if not exact_version or exact_version.startswith("workspace:"):
        raise ManifestRewriteError(f"invalid exact release version: {exact_version!r}")

    try:
        entries = _read_archive(archive)
        metadata = _read_manifest(entries, archive)
        if metadata.get("version") != exact_version:
            raise ManifestRewriteError(
                f"{archive.name}: manifest version {metadata.get('version')!r} "
                f"does not match {exact_version!r}"
            )

        rewritten = 0
        for field in DEPENDENCY_FIELDS:
            if field in metadata:
                rewritten += _rewrite_workspace_specs(metadata[field], exact_version)

        dependencies = metadata.get("dependencies", {})
        if not isinstance(dependencies, dict):
            raise ManifestRewriteError(
                f"{archive.name}: dependencies must be an object"
            )
        bundled_names: list[str] = []
        for dependency_name, dependency_archive in sorted(
            (bundled_packages or {}).items()
        ):
            if dependency_name not in dependencies:
                raise ManifestRewriteError(
                    f"{archive.name}: cannot bundle undeclared dependency {dependency_name}"
                )
            dependencies[dependency_name] = exact_version
            _bundle_package(
                entries, dependency_name, dependency_archive, exact_version
            )
            bundled_names.append(dependency_name)
        if bundled_names:
            metadata["bundledDependencies"] = bundled_names

        manifest_payload = (
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n"
        ).encode("utf-8")
        manifest_member = entries[PACKAGE_JSON].member
        entries[PACKAGE_JSON] = ArchiveEntry(manifest_member, manifest_payload)
        _write_archive(archive, entries)
        return rewritten
    except (json.JSONDecodeError, tarfile.TarError, OSError) as error:
        raise ManifestRewriteError(f"{archive.name}: {error}") from error


def _parse_bundle(value: str) -> tuple[str, Path]:
    name, separator, archive = value.partition("=")
    if not separator or not name or not archive:
        raise argparse.ArgumentTypeError(
            "bundled dependency must use NAME=/path/to/package.tgz"
        )
    return name, Path(archive)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--exact-version", required=True)
    parser.add_argument(
        "--bundle",
        action="append",
        default=[],
        type=_parse_bundle,
        metavar="NAME=ARCHIVE",
    )
    args = parser.parse_args()
    bundled_packages = dict(args.bundle)
    if len(bundled_packages) != len(args.bundle):
        print("ERROR: duplicate bundled dependency name")
        return 1
    try:
        count = rewrite_packed_manifest(
            args.archive, args.exact_version, bundled_packages
        )
    except ManifestRewriteError as error:
        print(f"ERROR: {error}")
        return 1
    print(
        f"Rewrote {count} workspace dependency spec(s) and bundled "
        f"{len(bundled_packages)} package(s) in {args.archive.name}."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
