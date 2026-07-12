#!/usr/bin/env python3
"""Validate the exact public React Native package set and bundled payloads."""

from __future__ import annotations

import argparse
import hashlib
import json
import tarfile
from pathlib import Path, PurePosixPath


EXPECTED_PACKAGES = {
    "@runanywhere/core",
    "@runanywhere/llamacpp",
    "@runanywhere/onnx",
}
BUNDLED_PROTO = "@runanywhere/proto-ts"
PROTO_RUNTIME_DEPENDENCIES = {"@bufbuild/protobuf": "^2.12.1"}
EXPECTED_EXACT_RUNTIME_DEPENDENCIES = {
    name: {BUNDLED_PROTO} for name in EXPECTED_PACKAGES
}
CORE_PACKAGE = "@runanywhere/core"
CORE_HEADER_PREFIX = "package/android/src/main/jniLibs/include/rac/"
BUNDLED_PROTO_PREFIX = "package/node_modules/@runanywhere/proto-ts/"
PRIVACY_MANIFEST_RELATIVE_PATH = "ios/PrivacyInfo.xcprivacy"
CORE_PODSPEC_PATH = "package/RunAnywhereCore.podspec"
CORE_PRIVACY_RESOURCE_MARKER = (
    '"RunAnywhereCorePrivacy" => ["ios/PrivacyInfo.xcprivacy"]'
)
PRIVATE_PATH_MARKERS = ("qhexrt", "qnn", "adsprpc", "cdsprpc")
HOST_PATH_MARKERS = (b"/Users/", b"/home/", b"/var/folders/", b"\\Users\\")
PERSONAL_REPOSITORY_MARKERS = (
    b"github.com/siddhesh2377/",
    b"github.com/sanchitmonga22/",
)
HOST_PATH_PAYLOAD_SUFFIXES = (".so", ".a", ".dylib", ".dll", ".wasm")


class PackageValidationError(RuntimeError):
    """Raised when a public RN release package is missing or malformed."""


def _normalized_member_name(archive: Path, name: str) -> str:
    if "\\" in name:
        raise PackageValidationError(
            f"{archive.name}: unsafe archive entry uses a backslash"
        )
    normalized = name.removeprefix("./")
    path = PurePosixPath(normalized)
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise PackageValidationError(f"{archive.name}: unsafe archive entry")
    if path.parts[0] != "package":
        raise PackageValidationError(
            f"{archive.name}: archive entry is outside package/"
        )
    lowered = normalized.casefold()
    if any(marker in lowered for marker in PRIVATE_PATH_MARKERS):
        raise PackageValidationError(
            f"{archive.name}: private QHexRT/QNN entry is not publishable"
        )
    return normalized


def _validate_archive_members(archive: Path, bundle: tarfile.TarFile) -> None:
    names: set[str] = set()
    for member in bundle.getmembers():
        normalized = _normalized_member_name(archive, member.name)
        if normalized in names:
            raise PackageValidationError(
                f"{archive.name}: duplicate archive entry {normalized}"
            )
        names.add(normalized)
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
        if normalized.casefold().endswith(HOST_PATH_PAYLOAD_SUFFIXES) and any(
            marker in payload for marker in HOST_PATH_MARKERS
        ):
            raise PackageValidationError(
                f"{archive.name}: binary payload exposes an absolute host build path"
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


def _file_bytes(bundle: tarfile.TarFile, member_name: str) -> bytes | None:
    try:
        source = bundle.extractfile(member_name)
    except KeyError:
        return None
    if source is None:
        raise PackageValidationError(f"cannot read archive member {member_name}")
    return source.read()


def _archive_contents(
    archive: Path,
) -> tuple[
    str,
    dict[str, object],
    dict[str, str],
    dict[str, str],
    dict[str, str],
    str | None,
]:
    with tarfile.open(archive, "r:gz") as bundle:
        _validate_archive_members(archive, bundle)
        try:
            package_json = bundle.extractfile("package/package.json")
        except KeyError as error:
            raise PackageValidationError(
                f"{archive.name}: missing package/package.json"
            ) from error
        if package_json is None:
            raise PackageValidationError(
                f"{archive.name}: package/package.json is not a file"
            )
        metadata = json.load(package_json)
        if not isinstance(metadata, dict):
            raise PackageValidationError(
                f"{archive.name}: package metadata is not an object"
            )
        name = metadata.get("name")
        if not isinstance(name, str) or not name:
            raise PackageValidationError(f"{archive.name}: package name is missing")
        header_hashes = (
            _file_hashes(bundle, CORE_HEADER_PREFIX) if name == CORE_PACKAGE else {}
        )
        bundled_proto_hashes = _file_hashes(bundle, BUNDLED_PROTO_PREFIX)
        privacy_manifest_hashes: dict[str, str] = {}
        for member in bundle.getmembers():
            member_name = member.name.removeprefix("./")
            if not member.isfile() or not member_name.endswith(
                "/PrivacyInfo.xcprivacy"
            ):
                continue
            source = bundle.extractfile(member)
            if source is None:
                raise PackageValidationError(
                    f"cannot read archive member {member_name}"
                )
            privacy_manifest_hashes[member_name.removeprefix("package/")] = (
                hashlib.sha256(source.read()).hexdigest()
            )
        podspec_bytes = _file_bytes(bundle, CORE_PODSPEC_PATH)
        core_podspec = (
            podspec_bytes.decode("utf-8") if podspec_bytes is not None else None
        )
    return (
        name,
        metadata,
        header_hashes,
        bundled_proto_hashes,
        privacy_manifest_hashes,
        core_podspec,
    )


def _proto_archive_hashes(proto_archive: Path) -> dict[str, str]:
    if not proto_archive.is_file():
        raise PackageValidationError(
            f"proto-ts package archive is missing: {proto_archive}"
        )
    with tarfile.open(proto_archive, "r:gz") as bundle:
        hashes = _file_hashes(bundle, "package/")
    if "package.json" not in hashes:
        raise PackageValidationError(
            f"{proto_archive.name}: missing package/package.json"
        )
    return hashes


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
    archive: Path,
    name: str,
    metadata: dict[str, object],
    expected_version: str | None,
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
    for dependency in EXPECTED_EXACT_RUNTIME_DEPENDENCIES.get(name, set()):
        actual_spec = dependencies.get(dependency)
        if actual_spec != version:
            raise PackageValidationError(
                f"{archive.name}: {dependency} must use exact release version {version!r}, "
                f"found {actual_spec!r}"
            )
    for dependency, expected_spec in PROTO_RUNTIME_DEPENDENCIES.items():
        if dependencies.get(dependency) != expected_spec:
            raise PackageValidationError(
                f"{archive.name}: bundled proto runtime dependency {dependency} "
                f"must use {expected_spec!r}, found {dependencies.get(dependency)!r}"
            )

    bundled_dependencies = metadata.get("bundledDependencies")
    if bundled_dependencies != [BUNDLED_PROTO]:
        raise PackageValidationError(
            f"{archive.name}: bundledDependencies must be exactly [{BUNDLED_PROTO!r}], "
            f"found {bundled_dependencies!r}"
        )
    return version


def _assert_matching_inventory(
    archive: Path,
    label: str,
    actual: dict[str, str],
    expected: dict[str, str],
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
        f"{archive.name}: {label} inventory mismatch: "
        f"missing={missing}, unexpected={unexpected}, mismatched={mismatched}"
    )


def validate_public_packages(
    dist_dir: Path,
    rac_headers: Path,
    proto_archive: Path,
    privacy_manifest: Path,
    expected_version: str | None = None,
) -> None:
    if not rac_headers.is_dir():
        raise PackageValidationError(
            f"public RAC header directory is missing: {rac_headers}"
        )
    expected_proto_hashes = _proto_archive_hashes(proto_archive)
    if not privacy_manifest.is_file():
        raise PackageValidationError(
            f"canonical Apple privacy manifest is missing: {privacy_manifest}"
        )
    expected_privacy_hashes = {
        PRIVACY_MANIFEST_RELATIVE_PATH: hashlib.sha256(
            privacy_manifest.read_bytes()
        ).hexdigest()
    }

    packages: dict[
        str,
        tuple[
            Path,
            dict[str, object],
            dict[str, str],
            dict[str, str],
            dict[str, str],
            str | None,
        ],
    ] = {}
    package_versions: set[str] = set()
    for archive in sorted(dist_dir.glob("*.tgz")):
        (
            name,
            metadata,
            header_hashes,
            proto_hashes,
            privacy_hashes,
            core_podspec,
        ) = _archive_contents(archive)
        if name in packages:
            raise PackageValidationError(f"duplicate public package {name}")
        package_versions.add(
            _validate_manifest(archive, name, metadata, expected_version)
        )
        _assert_matching_inventory(
            archive, "bundled proto-ts", proto_hashes, expected_proto_hashes
        )
        expected_privacy = expected_privacy_hashes if name == CORE_PACKAGE else {}
        _assert_matching_inventory(
            archive, "Apple privacy manifest", privacy_hashes, expected_privacy
        )
        if name == CORE_PACKAGE and (
            core_podspec is None
            or "s.resource_bundles" not in core_podspec
            or CORE_PRIVACY_RESOURCE_MARKER not in core_podspec
        ):
            raise PackageValidationError(
                f"{archive.name}: RunAnywhereCore.podspec does not wire "
                f"{PRIVACY_MANIFEST_RELATIVE_PATH} as the core privacy resource bundle"
            )
        packages[name] = (
            archive,
            metadata,
            header_hashes,
            proto_hashes,
            privacy_hashes,
            core_podspec,
        )

    actual = set(packages)
    if actual != EXPECTED_PACKAGES:
        missing = sorted(EXPECTED_PACKAGES - actual)
        unexpected = sorted(actual - EXPECTED_PACKAGES)
        raise PackageValidationError(
            f"public package set mismatch: missing={missing}, unexpected={unexpected}"
        )
    if len(package_versions) != 1:
        raise PackageValidationError(
            f"public packages do not share one release version: {sorted(package_versions)}"
        )

    expected_headers = {
        header.relative_to(rac_headers).as_posix(): hashlib.sha256(
            header.read_bytes()
        ).hexdigest()
        for header in rac_headers.rglob("*")
        if header.is_file()
    }
    core_archive, _, actual_headers, _, _, _ = packages[CORE_PACKAGE]
    _assert_matching_inventory(
        core_archive, "RAC header", actual_headers, expected_headers
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dist", required=True, type=Path)
    parser.add_argument("--rac-headers", required=True, type=Path)
    parser.add_argument("--proto-archive", required=True, type=Path)
    parser.add_argument("--privacy-manifest", required=True, type=Path)
    parser.add_argument("--expected-version")
    args = parser.parse_args()
    try:
        validate_public_packages(
            args.dist,
            args.rac_headers,
            args.proto_archive,
            args.privacy_manifest,
            args.expected_version,
        )
    except (PackageValidationError, json.JSONDecodeError, tarfile.TarError) as error:
        print(f"ERROR: {error}")
        return 1
    print(
        "Validated the exact public RN package set, bundled proto-ts payloads, "
        "dependency versions, RAC headers, and the canonical Apple privacy manifest."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
