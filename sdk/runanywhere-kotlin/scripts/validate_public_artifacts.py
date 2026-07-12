#!/usr/bin/env python3
"""Validate the exact public Kotlin Maven repository release bundle."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path, PurePosixPath


MAVEN_GROUP = "io.github.sanchitmonga22"
MAVEN_ARTIFACTS = {
    "runanywhere-sdk": "sdk",
    "runanywhere-llamacpp": "llamacpp",
    "runanywhere-onnx": "onnx",
}
SUPPORTED_ABIS = {"arm64-v8a", "armeabi-v7a", "x86_64"}
ELF_MACHINE_BY_ABI = {
    "arm64-v8a": 183,
    "armeabi-v7a": 40,
    "x86_64": 62,
}
NATIVE_LIBRARIES = {
    "sdk": {
        "libc++_shared.so",
        "libomp.so",
        "librac_backend_cloud.so",
        "librac_commons.so",
        "librunanywhere_jni.so",
    },
    "llamacpp": {
        "libc++_shared.so",
        "librac_backend_llamacpp.so",
        "librac_backend_llamacpp_jni.so",
        "librunanywhere_llamacpp.so",
    },
    "onnx": {
        "libc++_shared.so",
        "libonnxruntime.so",
        "librac_backend_onnx.so",
        "librac_backend_onnx_jni.so",
        "librac_backend_sherpa.so",
        "librunanywhere_onnx.so",
        "librunanywhere_sherpa.so",
        "libsherpa-onnx-c-api.so",
        "libsherpa-onnx-jni.so",
    },
}
PRIVATE_MARKERS = ("qhexrt", "qnn")
HOST_PATH_MARKERS = (b"/Users/", b"/home/", b"/var/folders/", b"\\Users\\")
VERSION_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
FIXED_ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)


class ArtifactValidationError(RuntimeError):
    """Raised when a public Kotlin distribution is incomplete or unsafe."""


def archive_name(version: str) -> str:
    if not VERSION_PATTERN.fullmatch(version):
        raise ArtifactValidationError(f"invalid release version: {version!r}")
    return f"runanywhere-kotlin-maven-v{version}.zip"


def publication_files(artifact: str, version: str) -> set[str]:
    base = f"repository/{MAVEN_GROUP.replace('.', '/')}/{artifact}/{version}"
    prefix = f"{base}/{artifact}-{version}"
    return {
        f"{prefix}.aar",
        f"{prefix}.pom",
        f"{prefix}.module",
        f"{prefix}-sources.jar",
    }


def expected_repository_files(version: str) -> set[str]:
    return set().union(
        *(publication_files(artifact, version) for artifact in MAVEN_ARTIFACTS)
    )


def _reject_unsafe_name(label: str, name: str) -> None:
    normalized = name.replace("\\", "/")
    path = PurePosixPath(normalized)
    if path.is_absolute() or ".." in path.parts:
        raise ArtifactValidationError(f"{label}: unsafe archive entry {name!r}")
    lowered = normalized.casefold()
    if any(marker in lowered for marker in PRIVATE_MARKERS):
        raise ArtifactValidationError(
            f"{label}: private QHexRT/QNN entry is not publishable: {name}"
        )


def _validate_zip_members(
    label: str,
    archive: zipfile.ZipFile,
    *,
    require_fixed_metadata: bool = False,
) -> list[str]:
    members = archive.infolist()
    names = [member.filename for member in members]
    if len(names) != len(set(names)):
        raise ArtifactValidationError(f"{label}: duplicate archive entries")
    for member in members:
        _reject_unsafe_name(label, member.filename)
        if require_fixed_metadata:
            if member.date_time != FIXED_ZIP_TIMESTAMP:
                raise ArtifactValidationError(
                    f"{label}: non-reproducible timestamp on {member.filename}: "
                    f"{member.date_time!r}"
                )
            if member.extra:
                raise ArtifactValidationError(
                    f"{label}: host-specific ZIP metadata on {member.filename}"
                )
    return names


def _validate_nested_jar(label: str, entry_name: str, payload: bytes) -> None:
    try:
        with zipfile.ZipFile(io.BytesIO(payload)) as nested:
            for nested_name in _validate_zip_members(
                f"{label}!/{entry_name}", nested
            ):
                if nested_name.casefold().endswith((".so", ".dll", ".dylib")):
                    raise ArtifactValidationError(
                        f"{label}: native binary hidden in {entry_name}: {nested_name}"
                    )
    except zipfile.BadZipFile as error:
        raise ArtifactValidationError(
            f"{label}: embedded JAR is not a valid ZIP: {entry_name}"
        ) from error


def _validate_elf(label: str, abi: str, payload: bytes) -> None:
    if len(payload) < 20 or payload[:4] != b"\x7fELF":
        raise ArtifactValidationError(f"{label}: native library is not an ELF file")
    if payload[5] != 1:
        raise ArtifactValidationError(f"{label}: Android ELF is not little-endian")
    machine = int.from_bytes(payload[18:20], byteorder="little")
    expected_machine = ELF_MACHINE_BY_ABI[abi]
    if machine != expected_machine:
        raise ArtifactValidationError(
            f"{label}: ELF architecture mismatch for {abi}: "
            f"expected e_machine={expected_machine}, actual={machine}"
        )
    if any(marker in payload for marker in HOST_PATH_MARKERS):
        raise ArtifactValidationError(
            f"{label}: native binary exposes an absolute host build path"
        )


def _validate_aar(label: str, family: str, payload: bytes) -> None:
    expected_libs = NATIVE_LIBRARIES[family]
    try:
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            names = _validate_zip_members(label, archive)
            if "classes.jar" not in names:
                raise ArtifactValidationError(f"{label}: missing classes.jar")

            native_by_abi: dict[str, set[str]] = {}
            for name in names:
                lowered = name.casefold()
                if lowered.endswith(".jar") and not name.endswith("/"):
                    _validate_nested_jar(label, name, archive.read(name))
                if not lowered.endswith(".so"):
                    continue

                parts = PurePosixPath(name).parts
                if len(parts) != 3 or parts[0] != "jni":
                    raise ArtifactValidationError(
                        f"{label}: native library outside jni/<abi>/: {name}"
                    )
                abi, library = parts[1], parts[2]
                if abi not in SUPPORTED_ABIS:
                    raise ArtifactValidationError(
                        f"{label}: unsupported Android ABI {abi!r}"
                    )
                if library not in expected_libs:
                    raise ArtifactValidationError(
                        f"{label}: undeclared/private native library: {name}"
                    )
                _validate_elf(f"{label}!/{name}", abi, archive.read(name))
                native_by_abi.setdefault(abi, set()).add(library)

            actual_abis = set(native_by_abi)
            if actual_abis != SUPPORTED_ABIS:
                missing = sorted(SUPPORTED_ABIS - actual_abis)
                unexpected = sorted(actual_abis - SUPPORTED_ABIS)
                raise ArtifactValidationError(
                    f"{label}: Android ABI inventory mismatch: "
                    f"missing={missing}, unexpected={unexpected}"
                )
            for abi in sorted(SUPPORTED_ABIS):
                actual_libs = native_by_abi[abi]
                if actual_libs != expected_libs:
                    missing = sorted(expected_libs - actual_libs)
                    unexpected = sorted(actual_libs - expected_libs)
                    raise ArtifactValidationError(
                        f"{label}: {abi} native inventory mismatch: "
                        f"missing={missing}, unexpected={unexpected}"
                    )
    except zipfile.BadZipFile as error:
        raise ArtifactValidationError(f"{label}: invalid AAR/ZIP") from error


def _validate_sources_jar(label: str, payload: bytes) -> None:
    try:
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            names = _validate_zip_members(label, archive)
            if "META-INF/MANIFEST.MF" not in names:
                raise ArtifactValidationError(f"{label}: missing JAR manifest")
            if not any(name.endswith((".kt", ".java")) for name in names):
                raise ArtifactValidationError(f"{label}: contains no source files")
            unexpected = [
                name
                for name in names
                if name.casefold().endswith((".class", ".so", ".dll", ".dylib"))
            ]
            if unexpected:
                raise ArtifactValidationError(
                    f"{label}: sources JAR contains binary entries: {unexpected}"
                )
    except zipfile.BadZipFile as error:
        raise ArtifactValidationError(f"{label}: invalid sources JAR") from error


def _validate_pom(label: str, artifact: str, version: str, payload: bytes) -> None:
    try:
        root = ET.fromstring(payload)
    except ET.ParseError as error:
        raise ArtifactValidationError(f"{label}: invalid POM XML") from error

    namespace = {"m": "http://maven.apache.org/POM/4.0.0"}

    def text(path: str) -> str | None:
        value = root.findtext(path, namespaces=namespace)
        return value.strip() if value is not None else None

    coordinate = (
        text("m:groupId"),
        text("m:artifactId"),
        text("m:version"),
        text("m:packaging"),
    )
    expected_coordinate = (MAVEN_GROUP, artifact, version, "aar")
    if coordinate != expected_coordinate:
        raise ArtifactValidationError(
            f"{label}: POM coordinate mismatch: "
            f"expected={expected_coordinate}, actual={coordinate}"
        )

    local_dependencies: set[tuple[str | None, str | None, str | None]] = set()
    for dependency in root.findall("m:dependencies/m:dependency", namespace):
        group = dependency.findtext("m:groupId", namespaces=namespace)
        if group == MAVEN_GROUP:
            local_dependencies.add(
                (
                    group,
                    dependency.findtext("m:artifactId", namespaces=namespace),
                    dependency.findtext("m:version", namespaces=namespace),
                )
            )

    expected_dependencies = (
        set()
        if artifact == "runanywhere-sdk"
        else {(MAVEN_GROUP, "runanywhere-sdk", version)}
    )
    if local_dependencies != expected_dependencies:
        raise ArtifactValidationError(
            f"{label}: public POM dependency graph mismatch: "
            f"expected={sorted(expected_dependencies)}, "
            f"actual={sorted(local_dependencies)}"
        )


def _validate_module_metadata(
    label: str,
    artifact: str,
    version: str,
    payload: bytes,
    publication_payloads: dict[str, bytes],
) -> None:
    try:
        model = json.loads(payload)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ArtifactValidationError(f"{label}: invalid Gradle module metadata") from error

    expected_component = {
        "group": MAVEN_GROUP,
        "module": artifact,
        "version": version,
    }
    component = model.get("component", {})
    actual_component = {key: component.get(key) for key in expected_component}
    if actual_component != expected_component:
        raise ArtifactValidationError(
            f"{label}: module coordinate mismatch: "
            f"expected={expected_component}, actual={actual_component}"
        )

    variants = model.get("variants")
    if not isinstance(variants, list) or not variants:
        raise ArtifactValidationError(f"{label}: module metadata has no variants")

    local_dependencies: set[tuple[str | None, str | None, str | None]] = set()
    referenced_files: set[str] = set()
    aar_variants = 0
    for variant in variants:
        files = variant.get("files", [])
        if any(item.get("name", "").endswith(".aar") for item in files):
            aar_variants += 1
        for dependency in variant.get("dependencies", []):
            if dependency.get("group") == MAVEN_GROUP:
                dependency_version = dependency.get("version", {}).get("requires")
                local_dependencies.add(
                    (
                        dependency.get("group"),
                        dependency.get("module"),
                        dependency_version,
                    )
                )
        for file_model in files:
            name = file_model.get("name")
            if not isinstance(name, str) or file_model.get("url") != name:
                raise ArtifactValidationError(
                    f"{label}: invalid publication file reference: {file_model}"
                )
            if name not in publication_payloads:
                raise ArtifactValidationError(
                    f"{label}: metadata references undeclared file {name!r}"
                )
            referenced_files.add(name)
            file_payload = publication_payloads[name]
            if file_model.get("size") != len(file_payload):
                raise ArtifactValidationError(
                    f"{label}: incorrect size metadata for {name}"
                )
            actual_sha256 = hashlib.sha256(file_payload).hexdigest()
            if file_model.get("sha256") != actual_sha256:
                raise ArtifactValidationError(
                    f"{label}: incorrect SHA-256 metadata for {name}"
                )

    expected_dependencies = (
        set()
        if artifact == "runanywhere-sdk"
        else {(MAVEN_GROUP, "runanywhere-sdk", version)}
    )
    if local_dependencies != expected_dependencies:
        raise ArtifactValidationError(
            f"{label}: Gradle dependency graph mismatch: "
            f"expected={sorted(expected_dependencies)}, "
            f"actual={sorted(local_dependencies)}"
        )
    if aar_variants < 2:
        raise ArtifactValidationError(
            f"{label}: expected API and runtime AAR variants"
        )
    if referenced_files != set(publication_payloads):
        raise ArtifactValidationError(
            f"{label}: publication file references are incomplete: "
            f"expected={sorted(publication_payloads)}, "
            f"actual={sorted(referenced_files)}"
        )


def _validate_checksum(artifact: Path) -> None:
    checksum = artifact.with_name(f"{artifact.name}.sha256")
    fields = checksum.read_text(encoding="utf-8").strip().split()
    if len(fields) != 2 or fields[1].removeprefix("*") != artifact.name:
        raise ArtifactValidationError(
            f"{checksum.name}: expected '<sha256>  {artifact.name}'"
        )
    actual = hashlib.sha256(artifact.read_bytes()).hexdigest()
    if fields[0].casefold() != actual:
        raise ArtifactValidationError(
            f"{checksum.name}: checksum does not match {artifact.name}"
        )


def validate_public_artifacts(dist_dir: Path, version: str) -> None:
    if not dist_dir.is_dir():
        raise ArtifactValidationError(f"distribution directory is missing: {dist_dir}")

    bundle_name = archive_name(version)
    expected_dist_files = {bundle_name, f"{bundle_name}.sha256"}
    actual_dist_files = {path.name for path in dist_dir.iterdir() if path.is_file()}
    if actual_dist_files != expected_dist_files:
        missing = sorted(expected_dist_files - actual_dist_files)
        unexpected = sorted(actual_dist_files - expected_dist_files)
        raise ArtifactValidationError(
            f"public artifact set mismatch: missing={missing}, unexpected={unexpected}"
        )

    bundle = dist_dir / bundle_name
    _reject_unsafe_name(bundle.name, bundle.name)
    try:
        with zipfile.ZipFile(bundle) as repository:
            names = _validate_zip_members(
                bundle.name, repository, require_fixed_metadata=True
            )
            if names != sorted(names):
                raise ArtifactValidationError(
                    f"{bundle.name}: repository entries are not sorted"
                )
            actual_files = {name for name in names if not name.endswith("/")}
            expected_files = expected_repository_files(version)
            if actual_files != expected_files:
                missing = sorted(expected_files - actual_files)
                unexpected = sorted(actual_files - expected_files)
                raise ArtifactValidationError(
                    f"{bundle.name}: Maven repository file set mismatch: "
                    f"missing={missing}, unexpected={unexpected}"
                )

            group_path = MAVEN_GROUP.replace(".", "/")
            for artifact, family in MAVEN_ARTIFACTS.items():
                base = f"repository/{group_path}/{artifact}/{version}"
                prefix = f"{artifact}-{version}"
                aar_name = f"{prefix}.aar"
                sources_name = f"{prefix}-sources.jar"
                aar_payload = repository.read(f"{base}/{aar_name}")
                sources_payload = repository.read(f"{base}/{sources_name}")
                _validate_aar(f"{bundle.name}!/{base}/{aar_name}", family, aar_payload)
                _validate_sources_jar(
                    f"{bundle.name}!/{base}/{sources_name}", sources_payload
                )
                _validate_pom(
                    f"{bundle.name}!/{base}/{prefix}.pom",
                    artifact,
                    version,
                    repository.read(f"{base}/{prefix}.pom"),
                )
                _validate_module_metadata(
                    f"{bundle.name}!/{base}/{prefix}.module",
                    artifact,
                    version,
                    repository.read(f"{base}/{prefix}.module"),
                    {aar_name: aar_payload, sources_name: sources_payload},
                )
    except zipfile.BadZipFile as error:
        raise ArtifactValidationError(f"{bundle.name}: invalid repository ZIP") from error

    _validate_checksum(bundle)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dist", required=True, type=Path)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    try:
        validate_public_artifacts(args.dist, args.version.removeprefix("v"))
    except (ArtifactValidationError, OSError) as error:
        print(f"ERROR: {error}")
        return 1
    print("Validated exact public Kotlin Maven repository and native inventories.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
