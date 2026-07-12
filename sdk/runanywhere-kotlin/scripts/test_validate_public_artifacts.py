#!/usr/bin/env python3
"""Focused synthetic coverage for the Kotlin Maven release boundary."""

from __future__ import annotations

import hashlib
import io
import json
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from validate_public_artifacts import (
    FIXED_ZIP_TIMESTAMP,
    MAVEN_ARTIFACTS,
    MAVEN_GROUP,
    NATIVE_LIBRARIES,
    SUPPORTED_ABIS,
    ArtifactValidationError,
    ELF_MACHINE_BY_ABI,
    archive_name,
    validate_public_artifacts,
)


VERSION = "1.2.3"


def _write_zip(entries: dict[str, bytes]) -> bytes:
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name in sorted(entries):
            info = zipfile.ZipInfo(name, FIXED_ZIP_TIMESTAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, entries[name])
    return output.getvalue()


def _classes_jar(entries: dict[str, bytes] | None = None) -> bytes:
    return _write_zip(
        {
            "META-INF/MANIFEST.MF": b"Manifest-Version: 1.0\n",
            **(entries or {"example/Public.class": b"class"}),
        }
    )


def _aar_bytes(
    family: str,
    *,
    missing_abi: str | None = None,
    extra_native: str | None = None,
    class_entries: dict[str, bytes] | None = None,
    wrong_architecture_abi: str | None = None,
    embed_host_path: bool = False,
) -> bytes:
    entries = {
        "AndroidManifest.xml": b"manifest",
        "classes.jar": _classes_jar(class_entries),
    }
    for abi in sorted(SUPPORTED_ABIS):
        if abi == missing_abi:
            continue
        machine = ELF_MACHINE_BY_ABI[abi]
        if abi == wrong_architecture_abi:
            machine = ELF_MACHINE_BY_ABI["arm64-v8a"]
        elf = bytearray(64)
        elf[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<H", elf, 18, machine)
        if embed_host_path:
            elf.extend(b"/Users/release-builder/private/checkout/source.cpp")
        for library in sorted(NATIVE_LIBRARIES[family]):
            entries[f"jni/{abi}/{library}"] = bytes(elf)
    if extra_native is not None:
        entries[f"jni/arm64-v8a/{extra_native}"] = bytes(elf)
    return _write_zip(entries)


def _sources_jar(artifact: str) -> bytes:
    return _write_zip(
        {
            "META-INF/MANIFEST.MF": b"Manifest-Version: 1.0\n",
            f"example/{artifact.replace('-', '_')}.kt": b"package example\n",
        }
    )


def _pom(artifact: str, *, omit_core_dependency: bool = False) -> bytes:
    dependency = ""
    if artifact != "runanywhere-sdk" and not omit_core_dependency:
        dependency = f"""
  <dependencies>
    <dependency>
      <groupId>{MAVEN_GROUP}</groupId>
      <artifactId>runanywhere-sdk</artifactId>
      <version>{VERSION}</version>
      <scope>compile</scope>
    </dependency>
  </dependencies>"""
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>{MAVEN_GROUP}</groupId>
  <artifactId>{artifact}</artifactId>
  <version>{VERSION}</version>
  <packaging>aar</packaging>{dependency}
</project>
""".encode()


def _module(
    artifact: str,
    aar_payload: bytes,
    sources_payload: bytes,
    *,
    wrong_hash: bool = False,
) -> bytes:
    dependency = []
    if artifact != "runanywhere-sdk":
        dependency = [
            {
                "group": MAVEN_GROUP,
                "module": "runanywhere-sdk",
                "version": {"requires": VERSION},
            }
        ]
    aar_name = f"{artifact}-{VERSION}.aar"
    sources_name = f"{artifact}-{VERSION}-sources.jar"

    def file_model(name: str, payload: bytes) -> dict[str, object]:
        digest = hashlib.sha256(payload).hexdigest()
        return {
            "name": name,
            "url": name,
            "size": len(payload),
            "sha256": "0" * 64 if wrong_hash and name == aar_name else digest,
        }

    model = {
        "formatVersion": "1.1",
        "component": {
            "group": MAVEN_GROUP,
            "module": artifact,
            "version": VERSION,
        },
        "variants": [
            {
                "name": "releaseApi",
                "dependencies": dependency,
                "files": [file_model(aar_name, aar_payload)],
            },
            {
                "name": "releaseRuntime",
                "dependencies": dependency,
                "files": [file_model(aar_name, aar_payload)],
            },
            {
                "name": "releaseSources",
                "files": [file_model(sources_name, sources_payload)],
            },
        ],
    }
    return json.dumps(model, sort_keys=True).encode()


def _write_distribution(
    dist: Path,
    *,
    missing_abi: tuple[str, str] | None = None,
    extra_entry: tuple[str, bytes] | None = None,
    qnn_family: str | None = None,
    private_class_family: str | None = None,
    omit_core_dependency_for: str | None = None,
    wrong_module_hash_for: str | None = None,
    wrong_architecture_family: str | None = None,
    host_path_family: str | None = None,
) -> None:
    repository_entries: dict[str, bytes] = {}
    group_path = MAVEN_GROUP.replace(".", "/")
    for artifact, family in MAVEN_ARTIFACTS.items():
        aar_payload = _aar_bytes(
            family,
            missing_abi=(
                missing_abi[1]
                if missing_abi is not None and missing_abi[0] == family
                else None
            ),
            extra_native="libQnnHtp.so" if qnn_family == family else None,
            class_entries=(
                {"private/qhexrt/Bridge.class": b"class"}
                if private_class_family == family
                else None
            ),
            wrong_architecture_abi=(
                "x86_64" if wrong_architecture_family == family else None
            ),
            embed_host_path=host_path_family == family,
        )
        sources_payload = _sources_jar(artifact)
        base = f"repository/{group_path}/{artifact}/{VERSION}"
        prefix = f"{artifact}-{VERSION}"
        repository_entries[f"{base}/{prefix}.aar"] = aar_payload
        repository_entries[f"{base}/{prefix}-sources.jar"] = sources_payload
        repository_entries[f"{base}/{prefix}.pom"] = _pom(
            artifact,
            omit_core_dependency=omit_core_dependency_for == artifact,
        )
        repository_entries[f"{base}/{prefix}.module"] = _module(
            artifact,
            aar_payload,
            sources_payload,
            wrong_hash=wrong_module_hash_for == artifact,
        )
    if extra_entry is not None:
        repository_entries[extra_entry[0]] = extra_entry[1]

    bundle = dist / archive_name(VERSION)
    bundle.write_bytes(_write_zip(repository_entries))
    digest = hashlib.sha256(bundle.read_bytes()).hexdigest()
    bundle.with_name(f"{bundle.name}.sha256").write_text(
        f"{digest}  {bundle.name}\n", encoding="utf-8"
    )


class PublicArtifactValidationTest(unittest.TestCase):
    def test_accepts_exact_declared_maven_repository(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_distribution(dist)
            validate_public_artifacts(dist, VERSION)

    def test_rejects_each_public_aar_when_one_supported_abi_is_missing(self) -> None:
        for family in sorted(NATIVE_LIBRARIES):
            with self.subTest(
                family=family
            ), tempfile.TemporaryDirectory() as temporary:
                dist = Path(temporary)
                _write_distribution(dist, missing_abi=(family, "x86_64"))
                with self.assertRaisesRegex(
                    ArtifactValidationError,
                    rf"runanywhere-{family}.*Android ABI inventory mismatch: "
                    rf"missing=\['x86_64'\]",
                ):
                    validate_public_artifacts(dist, VERSION)

    def test_rejects_loose_or_jvm_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_distribution(dist)
            (dist / f"runanywhere-sdk-{VERSION}.jar").write_bytes(b"not public")
            with self.assertRaisesRegex(
                ArtifactValidationError, "artifact set mismatch"
            ):
                validate_public_artifacts(dist, VERSION)

    def test_rejects_native_library_for_the_wrong_abi(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_distribution(dist, wrong_architecture_family="llamacpp")
            with self.assertRaisesRegex(
                ArtifactValidationError, "ELF architecture mismatch for x86_64"
            ):
                validate_public_artifacts(dist, VERSION)

    def test_rejects_absolute_host_path_in_native_library(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_distribution(dist, host_path_family="sdk")
            with self.assertRaisesRegex(
                ArtifactValidationError, "absolute host build path"
            ):
                validate_public_artifacts(dist, VERSION)

    def test_rejects_qhexrt_repository_entry(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_distribution(
                dist,
                extra_entry=("repository/private/qhexrt/readme.txt", b"private"),
            )
            with self.assertRaisesRegex(ArtifactValidationError, "QHexRT/QNN entry"):
                validate_public_artifacts(dist, VERSION)

    def test_rejects_qnn_native_hidden_in_public_aar(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_distribution(dist, qnn_family="onnx")
            with self.assertRaisesRegex(ArtifactValidationError, "QHexRT/QNN entry"):
                validate_public_artifacts(dist, VERSION)

    def test_rejects_private_class_hidden_in_classes_jar(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_distribution(dist, private_class_family="sdk")
            with self.assertRaisesRegex(ArtifactValidationError, "QHexRT/QNN entry"):
                validate_public_artifacts(dist, VERSION)

    def test_rejects_backend_pom_without_exact_core_dependency(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_distribution(
                dist, omit_core_dependency_for="runanywhere-llamacpp"
            )
            with self.assertRaisesRegex(
                ArtifactValidationError, "POM dependency graph mismatch"
            ):
                validate_public_artifacts(dist, VERSION)

    def test_rejects_incorrect_gradle_metadata_hash(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_distribution(dist, wrong_module_hash_for="runanywhere-onnx")
            with self.assertRaisesRegex(
                ArtifactValidationError, "incorrect SHA-256 metadata"
            ):
                validate_public_artifacts(dist, VERSION)

    def test_rejects_mismatched_bundle_checksum(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            _write_distribution(dist)
            bundle = dist / archive_name(VERSION)
            bundle.with_name(f"{bundle.name}.sha256").write_text(
                f"{'0' * 64}  {bundle.name}\n", encoding="utf-8"
            )
            with self.assertRaisesRegex(
                ArtifactValidationError, "checksum does not match"
            ):
                validate_public_artifacts(dist, VERSION)


if __name__ == "__main__":
    unittest.main()
