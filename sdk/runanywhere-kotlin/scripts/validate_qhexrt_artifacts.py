#!/usr/bin/env python3
"""Validate the QHexRT Kotlin Maven repository release bundle."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import struct
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path, PurePosixPath


MAVEN_GROUP = "io.github.sanchitmonga22"
ARTIFACT = "runanywhere-qhexrt-android"
ABI = "arm64-v8a"
ELF_MACHINE_AARCH64 = 183
HOST_LIBS = {
    "libc++_shared.so",
    "librac_backend_qhexrt.so",
    "librac_backend_qhexrt_jni.so",
    "libQnnHtp.so",
    "libQnnHtpNetRunExtensions.so",
    "libQnnHtpPrepare.so",
    "libQnnSystem.so",
    "libQnnHtpV75CalculatorStub.so",
    "libQnnHtpV75Stub.so",
    "libQnnHtpV79CalculatorStub.so",
    "libQnnHtpV79Stub.so",
    "libQnnHtpV81CalculatorStub.so",
    "libQnnHtpV81Stub.so",
}
SKEL_LIBS = {
    "libQnnHtpV75Skel.so",
    "libQnnHtpV79Skel.so",
    "libQnnHtpV81Skel.so",
}
HOST_PATH_MARKERS = (b"/Users/", b"/home/", b"/var/folders/", b"\\Users\\")
VERSION_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
FIXED_ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
MAVEN_LICENSE = (
    "RunAnywhere License",
    "https://github.com/RunanywhereAI/runanywhere-sdks/blob/main/LICENSE",
    "repo",
)
REQUIRED_NOTICES = "META-INF/THIRD-PARTY-NOTICES-QAIRT.txt"


class ArtifactValidationError(RuntimeError):
    """Raised when a QHexRT Kotlin distribution is incomplete or unsafe."""


def archive_name(version: str) -> str:
    if not VERSION_PATTERN.fullmatch(version):
        raise ArtifactValidationError(f"invalid release version: {version!r}")
    return f"runanywhere-kotlin-qhexrt-maven-v{version}.zip"


def publication_prefix(version: str) -> str:
    base = f"repository/{MAVEN_GROUP.replace('.', '/')}/{ARTIFACT}/{version}"
    return f"{base}/{ARTIFACT}-{version}"


def expected_repository_files(version: str) -> set[str]:
    prefix = publication_prefix(version)
    return {
        f"{prefix}.aar",
        f"{prefix}.pom",
        f"{prefix}.module",
        f"{prefix}-sources.jar",
    }


def _reject_unsafe_name(label: str, name: str) -> None:
    normalized = name.replace("\\", "/")
    path = PurePosixPath(normalized)
    if path.is_absolute() or ".." in path.parts:
        raise ArtifactValidationError(f"{label}: unsafe archive entry {name!r}")


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
                    f"{label}: unexpected ZIP extra field on {member.filename}"
                )
    if names != sorted(names):
        raise ArtifactValidationError(f"{label}: archive entries are not sorted")
    return names


def _validate_host_elf(label: str, data: bytes) -> None:
    if len(data) < 20 or data[:4] != b"\x7fELF":
        raise ArtifactValidationError(f"{label}: not a little-endian ELF shared object")
    if data[5] != 1:
        raise ArtifactValidationError(f"{label}: ELF endianness is not little-endian")
    e_machine = struct.unpack_from("<H", data, 18)[0]
    if e_machine != ELF_MACHINE_AARCH64:
        raise ArtifactValidationError(
            f"{label}: unexpected ELF e_machine {e_machine} (want {ELF_MACHINE_AARCH64})"
        )
    for marker in HOST_PATH_MARKERS:
        if marker in data:
            raise ArtifactValidationError(
                f"{label}: host path marker {marker!r} found in native binary"
            )


def _validate_aar(aar_bytes: bytes) -> None:
    with zipfile.ZipFile(io.BytesIO(aar_bytes)) as aar:
        names = set(aar.namelist())
        host_prefix = f"jni/{ABI}/"
        skel_prefix = f"assets/runanywhere/qhexrt/skels/{ABI}/"
        found_host = {
            PurePosixPath(name).name
            for name in names
            if name.startswith(host_prefix) and name.endswith(".so")
        }
        found_skel = {
            PurePosixPath(name).name
            for name in names
            if name.startswith(skel_prefix) and name.endswith(".so")
        }
        if found_host != HOST_LIBS:
            raise ArtifactValidationError(
                f"AAR host lib inventory mismatch: got={sorted(found_host)} "
                f"want={sorted(HOST_LIBS)}"
            )
        if found_skel != SKEL_LIBS:
            raise ArtifactValidationError(
                f"AAR skel inventory mismatch: got={sorted(found_skel)} "
                f"want={sorted(SKEL_LIBS)}"
            )
        if "classes.jar" not in names:
            raise ArtifactValidationError("AAR missing classes.jar")
        with zipfile.ZipFile(io.BytesIO(aar.read("classes.jar"))) as classes:
            class_names = set(classes.namelist())
            if REQUIRED_NOTICES not in class_names:
                raise ArtifactValidationError(
                    f"AAR classes.jar missing {REQUIRED_NOTICES}"
                )
            notices = classes.read(REQUIRED_NOTICES).decode("utf-8", errors="replace")
            if "Qualcomm" not in notices or "QAIRT" not in notices:
                raise ArtifactValidationError(
                    f"{REQUIRED_NOTICES} does not mention Qualcomm QAIRT redistributables"
                )
            if "META-INF/LICENSE.runanywhere-qhexrt.txt" not in class_names:
                raise ArtifactValidationError(
                    "AAR classes.jar missing META-INF/LICENSE.runanywhere-qhexrt.txt"
                )
        for name in sorted(found_host):
            _validate_host_elf(f"AAR:{host_prefix}{name}", aar.read(f"{host_prefix}{name}"))


def _validate_pom(pom_bytes: bytes, version: str) -> None:
    root = ET.fromstring(pom_bytes)
    ns = ""
    if root.tag.startswith("{"):
        ns = root.tag.split("}")[0][1:]

    def text(tag: str) -> str:
        node = root.find(f"{{{ns}}}{tag}" if ns else tag)
        return (node.text or "").strip() if node is not None else ""

    if text("groupId") != MAVEN_GROUP:
        raise ArtifactValidationError(f"POM groupId mismatch: {text('groupId')}")
    if text("artifactId") != ARTIFACT:
        raise ArtifactValidationError(f"POM artifactId mismatch: {text('artifactId')}")
    if text("version") != version:
        raise ArtifactValidationError(f"POM version mismatch: {text('version')}")

    licenses = root.findall(f".//{{{ns}}}license" if ns else ".//license")
    if not licenses:
        raise ArtifactValidationError("POM missing license")
    license_name = (licenses[0].findtext(f"{{{ns}}}name" if ns else "name") or "").strip()
    license_url = (licenses[0].findtext(f"{{{ns}}}url" if ns else "url") or "").strip()
    if (license_name, license_url, "repo") != MAVEN_LICENSE and license_name != MAVEN_LICENSE[0]:
        raise ArtifactValidationError(
            f"POM license mismatch: name={license_name!r} url={license_url!r}"
        )

    deps = root.findall(f".//{{{ns}}}dependency" if ns else ".//dependency")
    dep_ids = {
        (
            (dep.findtext(f"{{{ns}}}groupId" if ns else "groupId") or "").strip(),
            (dep.findtext(f"{{{ns}}}artifactId" if ns else "artifactId") or "").strip(),
        )
        for dep in deps
    }
    if (MAVEN_GROUP, "runanywhere-sdk") not in dep_ids:
        raise ArtifactValidationError("POM missing dependency on runanywhere-sdk")


def _validate_module(module_bytes: bytes, version: str) -> None:
    data = json.loads(module_bytes.decode("utf-8"))
    component = data.get("component") or {}
    if component.get("group") != MAVEN_GROUP:
        raise ArtifactValidationError(f"module group mismatch: {component.get('group')}")
    if component.get("module") != ARTIFACT:
        raise ArtifactValidationError(f"module name mismatch: {component.get('module')}")
    if component.get("version") != version:
        raise ArtifactValidationError(f"module version mismatch: {component.get('version')}")


def validate_dist(dist_dir: Path, version: str) -> None:
    zip_name = archive_name(version)
    zip_path = dist_dir / zip_name
    sha_path = dist_dir / f"{zip_name}.sha256"
    if not zip_path.is_file():
        raise ArtifactValidationError(f"missing archive: {zip_path}")
    if not sha_path.is_file():
        raise ArtifactValidationError(f"missing checksum: {sha_path}")

    expected_sha = sha_path.read_text(encoding="utf-8").strip().split()[0]
    actual_sha = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    if expected_sha != actual_sha:
        raise ArtifactValidationError("archive SHA-256 does not match sidecar")

    with zipfile.ZipFile(zip_path) as archive:
        names = _validate_zip_members(
            "maven-bundle", archive, require_fixed_metadata=True
        )
        expected = expected_repository_files(version)
        actual_files = {name for name in names if not name.endswith("/")}
        if actual_files != expected:
            raise ArtifactValidationError(
                f"maven repository file set mismatch: got={sorted(actual_files)} "
                f"want={sorted(expected)}"
            )
        prefix = publication_prefix(version)
        _validate_aar(archive.read(f"{prefix}.aar"))
        _validate_pom(archive.read(f"{prefix}.pom"), version)
        _validate_module(archive.read(f"{prefix}.module"), version)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dist", required=True, type=Path)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    try:
        validate_dist(args.dist, args.version)
    except ArtifactValidationError as exc:
        print(f"ERROR: {exc}", flush=True)
        return 1
    print(
        f">> QHexRT artifacts validated: {archive_name(args.version)} "
        f"({ARTIFACT}:{args.version})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
