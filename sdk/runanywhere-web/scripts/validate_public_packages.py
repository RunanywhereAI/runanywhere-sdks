#!/usr/bin/env python3
"""Validate Web release tarballs and their self-contained proto dependency."""

from __future__ import annotations

import argparse
import hashlib
import json
import tarfile
from pathlib import Path, PurePosixPath


PROTO_PACKAGE = "@runanywhere/proto-ts"
EXPECTED_PACKAGES = {
    PROTO_PACKAGE,
    "@runanywhere/web",
    "@runanywhere/web-llamacpp",
    "@runanywhere/web-onnx",
}
PROTO_CONSUMERS = {"@runanywhere/web", "@runanywhere/web-llamacpp"}
PROTO_RUNTIME_DEPENDENCIES = {"@bufbuild/protobuf": "^2.12.1"}
BUNDLED_PROTO_PREFIX = "package/node_modules/@runanywhere/proto-ts/"
PRIVATE_PATH_MARKERS = ("qhexrt", "qnn", "adsprpc", "cdsprpc")
HOST_PATH_MARKERS = (b"/Users/", b"/var/folders/", b"\\Users\\")
HOME_PATH_MARKER = b"/home/"
EMSCRIPTEN_VIRTUAL_HOME = b"/home/web_user"
PATH_TOKEN_TERMINATORS = frozenset(b"\x00\t\n\r \"'`,:;)]}")
PERSONAL_REPOSITORY_MARKERS = (
    b"github.com/siddhesh2377/",
    b"github.com/sanchitmonga22/",
)


class PackageValidationError(RuntimeError):
    """Raised when a Web release package is missing or malformed."""


def _contains_host_build_path(payload: bytes) -> bool:
    if any(marker in payload for marker in HOST_PATH_MARKERS):
        return True

    offset = 0
    while True:
        offset = payload.find(HOME_PATH_MARKER, offset)
        if offset < 0:
            return False
        virtual_home_end = offset + len(EMSCRIPTEN_VIRTUAL_HOME)
        if payload.startswith(EMSCRIPTEN_VIRTUAL_HOME, offset) and (
            virtual_home_end == len(payload)
            or payload[virtual_home_end] in PATH_TOKEN_TERMINATORS
        ):
            offset = virtual_home_end
            continue
        return True


def _validate_archive_members(archive: Path, bundle: tarfile.TarFile) -> None:
    names: set[str] = set()
    for member in bundle.getmembers():
        if "\\" in member.name:
            raise PackageValidationError(
                f"{archive.name}: unsafe archive entry uses a backslash"
            )
        normalized = member.name.removeprefix("./")
        path = PurePosixPath(normalized)
        if (
            path.is_absolute()
            or ".." in path.parts
            or not path.parts
            or path.parts[0] != "package"
        ):
            raise PackageValidationError(f"{archive.name}: unsafe archive entry")
        if normalized in names:
            raise PackageValidationError(
                f"{archive.name}: duplicate archive entry {normalized}"
            )
        names.add(normalized)
        lowered_name = normalized.casefold()
        if any(marker in lowered_name for marker in PRIVATE_PATH_MARKERS):
            raise PackageValidationError(
                f"{archive.name}: private QHexRT/QNN entry is not publishable"
            )
        if not member.isfile() and not member.isdir():
            raise PackageValidationError(
                f"{archive.name}: links and special archive entries are not publishable"
            )
        if not member.isfile():
            continue
        source = bundle.extractfile(member)
        if source is None:
            raise PackageValidationError(
                f"{archive.name}: cannot read archive member {normalized}"
            )
        payload = source.read()
        lowered_payload = payload.lower()
        if any(marker in lowered_payload for marker in PERSONAL_REPOSITORY_MARKERS):
            raise PackageValidationError(
                f"{archive.name}: personal GitHub repository reference is not publishable"
            )
        if (
            "/wasm/" in lowered_name
            and lowered_name.endswith((".js", ".wasm"))
            and _contains_host_build_path(payload)
        ):
            raise PackageValidationError(
                f"{archive.name}: Web runtime exposes an absolute host build path"
            )


def _file_hashes(bundle: tarfile.TarFile, prefix: str) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for member in bundle.getmembers():
        member_name = member.name.removeprefix("./")
        if not member.isfile() or not member_name.startswith(prefix):
            continue
        source = bundle.extractfile(member)
        if source is None:
            raise PackageValidationError(f"cannot read archive member {member_name}")
        hashes[member_name.removeprefix(prefix)] = hashlib.sha256(
            source.read()
        ).hexdigest()
    return hashes


def _archive_contents(
    archive: Path,
) -> tuple[str, dict[str, object], dict[str, str], dict[str, str]]:
    with tarfile.open(archive, "r:gz") as bundle:
        _validate_archive_members(archive, bundle)
        try:
            manifest_file = bundle.extractfile("package/package.json")
        except KeyError as error:
            raise PackageValidationError(
                f"{archive.name}: missing package/package.json"
            ) from error
        if manifest_file is None:
            raise PackageValidationError(
                f"{archive.name}: package/package.json is not a file"
            )
        metadata = json.load(manifest_file)
        if not isinstance(metadata, dict):
            raise PackageValidationError(
                f"{archive.name}: package metadata is not an object"
            )
        name = metadata.get("name")
        if not isinstance(name, str) or not name:
            raise PackageValidationError(f"{archive.name}: package name is missing")
        package_hashes = _file_hashes(bundle, "package/")
        bundled_proto_hashes = _file_hashes(bundle, BUNDLED_PROTO_PREFIX)
    return name, metadata, package_hashes, bundled_proto_hashes


def _workspace_protocol_specs(
    value: object, path: str = "package"
) -> list[tuple[str, str]]:
    matches: list[tuple[str, str]] = []
    if isinstance(value, dict):
        for key, nested in value.items():
            matches.extend(_workspace_protocol_specs(nested, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            matches.extend(_workspace_protocol_specs(nested, f"{path}[{index}]"))
    elif isinstance(value, str) and value.startswith("workspace:"):
        matches.append((path, value))
    return matches


def _validate_manifest(
    archive: Path, name: str, metadata: dict[str, object], expected_version: str | None,
) -> str:
    version = metadata.get("version")
    if not isinstance(version, str) or not version:
        raise PackageValidationError(f"{archive.name}: package version is missing")
    if expected_version is not None and version != expected_version:
        raise PackageValidationError(
            f"{archive.name}: package version {version!r} does not match {expected_version!r}"
        )
    workspace_specs = _workspace_protocol_specs(metadata)
    if workspace_specs:
        path, spec = workspace_specs[0]
        raise PackageValidationError(
            f"{archive.name}: workspace protocol is not publishable at {path}: {spec}"
        )

    dependencies = metadata.get("dependencies", {})
    if not isinstance(dependencies, dict):
        raise PackageValidationError(f"{archive.name}: dependencies must be an object")
    bundled_dependencies = metadata.get("bundledDependencies")
    if name in PROTO_CONSUMERS:
        if dependencies.get(PROTO_PACKAGE) != version:
            raise PackageValidationError(
                f"{archive.name}: {PROTO_PACKAGE} must use exact release version "
                f"{version!r}, found {dependencies.get(PROTO_PACKAGE)!r}"
            )
        if bundled_dependencies != [PROTO_PACKAGE]:
            raise PackageValidationError(
                f"{archive.name}: bundledDependencies must be exactly "
                f"[{PROTO_PACKAGE!r}], found {bundled_dependencies!r}"
            )
        for dependency, expected_spec in PROTO_RUNTIME_DEPENDENCIES.items():
            if dependencies.get(dependency) != expected_spec:
                raise PackageValidationError(
                    f"{archive.name}: bundled proto runtime dependency {dependency} "
                    f"must use {expected_spec!r}, found {dependencies.get(dependency)!r}"
                )
    elif bundled_dependencies:
        raise PackageValidationError(
            f"{archive.name}: unexpected bundledDependencies {bundled_dependencies!r}"
        )
    return version


def _assert_matching_proto(
    archive: Path, actual: dict[str, str], expected: dict[str, str]
) -> None:
    if actual == expected:
        return
    missing = sorted(expected.keys() - actual.keys())
    unexpected = sorted(actual.keys() - expected.keys())
    mismatched = sorted(
        path
        for path in expected.keys() & actual.keys()
        if expected[path] != actual[path]
    )
    raise PackageValidationError(
        f"{archive.name}: bundled proto-ts inventory mismatch: "
        f"missing={missing}, unexpected={unexpected}, mismatched={mismatched}"
    )


def validate_public_packages(
    dist_dir: Path, expected_version: str | None = None
) -> None:
    packages: dict[
        str, tuple[Path, dict[str, object], dict[str, str], dict[str, str]]
    ] = {}
    versions: set[str] = set()
    for archive in sorted(dist_dir.glob("*.tgz")):
        name, metadata, package_hashes, proto_hashes = _archive_contents(archive)
        if name in packages:
            raise PackageValidationError(f"duplicate public package {name}")
        versions.add(_validate_manifest(archive, name, metadata, expected_version))
        packages[name] = (archive, metadata, package_hashes, proto_hashes)

    actual_names = set(packages)
    if actual_names != EXPECTED_PACKAGES:
        raise PackageValidationError(
            "public package set mismatch: "
            f"missing={sorted(EXPECTED_PACKAGES - actual_names)}, "
            f"unexpected={sorted(actual_names - EXPECTED_PACKAGES)}"
        )
    if len(versions) != 1:
        raise PackageValidationError(
            f"public packages do not share one release version: {sorted(versions)}"
        )

    proto_archive, _, proto_hashes, _ = packages[PROTO_PACKAGE]
    expected_proto_hashes = {
        path: digest
        for path, digest in proto_hashes.items()
        if not path.startswith("node_modules/")
    }
    if "package.json" not in expected_proto_hashes:
        raise PackageValidationError(
            f"{proto_archive.name}: proto package manifest is missing"
        )
    for name in PROTO_CONSUMERS:
        archive, _, _, bundled_proto_hashes = packages[name]
        _assert_matching_proto(archive, bundled_proto_hashes, expected_proto_hashes)
    onnx_archive, _, _, onnx_bundled_proto = packages["@runanywhere/web-onnx"]
    if onnx_bundled_proto:
        raise PackageValidationError(
            f"{onnx_archive.name}: unexpectedly bundles proto-ts"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dist", required=True, type=Path)
    parser.add_argument("--expected-version")
    args = parser.parse_args()
    try:
        validate_public_packages(args.dist, args.expected_version)
    except (PackageValidationError, json.JSONDecodeError, tarfile.TarError) as error:
        print(f"ERROR: {error}")
        return 1
    print(
        "Validated the exact Web package set, versions, and self-contained "
        "proto-ts payloads."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
