#!/usr/bin/env python3
"""Focused guards for the Android Sherpa-ONNX dependency downloader."""

from __future__ import annotations

import hashlib
import io
import os
from pathlib import Path
import stat
import subprocess
import tarfile
import tempfile
import unittest


SCRIPT_DIR = Path(__file__).resolve().parent
DOWNLOADER = SCRIPT_DIR / "download-sherpa-onnx.sh"
VERSIONS = SCRIPT_DIR.parent.parent / "VERSIONS"
EMBEDDED_BUILD_ROOT = b"/home/home/Projects/sherpa-onnx"
SANITIZED_BUILD_ROOT = b"/runanywhere/third-party/sherpa"


def read_versions() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in VERSIONS.read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key] = value
    return values


def run_downloader_function(
    expression: str, *arguments: Path | str, environment: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    if environment:
        env.update(environment)
    return subprocess.run(
        [
            "/bin/bash",
            "-c",
            'source "$1"; shift; ' + expression,
            "bash",
            str(DOWNLOADER),
            *(str(argument) for argument in arguments),
        ],
        check=False,
        capture_output=True,
        text=True,
        env=env,
    )


def add_regular_file(
    archive: tarfile.TarFile, name: str, payload: bytes = b"data"
) -> None:
    member = tarfile.TarInfo(name)
    member.size = len(payload)
    member.mode = 0o644
    archive.addfile(member, io.BytesIO(payload))


def write_transform_manifest(
    path: Path,
    relative_path: str,
    raw_payload: bytes,
    expected_replacements: int,
) -> None:
    transformed = raw_payload.replace(EMBEDDED_BUILD_ROOT, SANITIZED_BUILD_ROOT)
    path.write_text(
        "# test transform manifest\n"
        f"version={read_versions()['SHERPA_ONNX_VERSION_ANDROID']}\n"
        f"{relative_path} {hashlib.sha256(raw_payload).hexdigest()} "
        f"{expected_replacements} {hashlib.sha256(transformed).hexdigest()}\n",
        encoding="utf-8",
    )


class DownloaderPinsTest(unittest.TestCase):
    def test_inspected_artifact_and_source_pins_are_exact(self) -> None:
        values = read_versions()
        self.assertEqual(values["ONNX_VERSION_ANDROID"], "1.24.3")
        self.assertEqual(
            values["ONNX_COMMIT_ANDROID"], "3a728b75062256951b6e19ce718907cf1a1d4cf0",
        )
        self.assertEqual(
            values["SHERPA_ONNX_COMMIT_ANDROID"],
            "707ffc40b0fd59c04f50998e72989dd816b1dd37",
        )
        self.assertEqual(
            values["SHERPA_ONNX_ANDROID_SHA256"],
            "6ce931ffb49605cf1448e5fa98f9804fb7fdc5bb72efded3048a84080eea477b",
        )
        self.assertEqual(
            values["SHERPA_ONNX_HEADER_COMMIT_ANDROID"],
            values["SHERPA_ONNX_UPSTREAM_COMMIT_ANDROID"],
        )

    def test_cache_identity_covers_every_supply_chain_pin(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            cache = Path(temporary_directory) / "cache"
            result = run_downloader_function(
                'write_identity_file "$CACHE_IDENTITY_FILE" print_cache_identity; '
                'cache_identity_matches; cat "$CACHE_IDENTITY_FILE"',
                environment={"RAC_SHERPA_DIR": str(cache)},
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            identity = result.stdout
            for field in (
                "repo=",
                "version=",
                "source_commit=",
                "archive_sha256=",
                "upstream_commit=",
                "patch_sha256=",
                "header_repo=",
                "header_commit=",
                "onnxruntime_version=",
                "onnxruntime_commit=",
                "embedded_path_rewrite=",
            ):
                self.assertIn(field, identity)

            identity_path = cache / ".sherpa-android-provenance"
            identity_path.write_text(identity + "tampered=true\n", encoding="utf-8")
            mismatch = run_downloader_function(
                "cache_identity_matches", environment={"RAC_SHERPA_DIR": str(cache)},
            )
            self.assertNotEqual(mismatch.returncode, 0)


class ArchiveSafetyTest(unittest.TestCase):
    def test_safe_regular_file_archive_extracts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            archive_path = root / "safe.tar.bz2"
            destination = root / "out"
            with tarfile.open(archive_path, "w:bz2") as archive:
                add_regular_file(archive, "jniLibs/arm64-v8a/libsafe.so")

            result = run_downloader_function(
                'extract_archive_safely "$1" "$2"', archive_path, destination
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue((destination / "jniLibs/arm64-v8a/libsafe.so").is_file())

    def test_unsafe_archive_members_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            unsafe_members = ("../escape.so", "/absolute.so", "dir\\windows-escape.so")
            for index, member_name in enumerate(unsafe_members):
                with self.subTest(member_name=member_name):
                    archive_path = root / f"unsafe-{index}.tar.bz2"
                    destination = root / f"out-{index}"
                    with tarfile.open(archive_path, "w:bz2") as archive:
                        add_regular_file(archive, member_name)
                    result = run_downloader_function(
                        'extract_archive_safely "$1" "$2"', archive_path, destination
                    )
                    self.assertNotEqual(result.returncode, 0)

    def test_symbolic_and_hard_links_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            for member_type in (tarfile.SYMTYPE, tarfile.LNKTYPE):
                with self.subTest(member_type=member_type):
                    archive_path = root / f"link-{member_type!r}.tar.bz2"
                    destination = root / f"out-{member_type!r}"
                    with tarfile.open(archive_path, "w:bz2") as archive:
                        member = tarfile.TarInfo("jniLibs/arm64-v8a/liblink.so")
                        member.type = member_type
                        member.linkname = "../../outside"
                        archive.addfile(member)
                    result = run_downloader_function(
                        'extract_archive_safely "$1" "$2"', archive_path, destination
                    )
                    self.assertNotEqual(result.returncode, 0)


class DigestAndElfTest(unittest.TestCase):
    def test_embedded_build_path_transform_is_exact_and_idempotent(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            library = root / "jniLibs" / "arm64-v8a" / "libsherpa.so"
            library.parent.mkdir(parents=True)
            raw_payload = b"prefix\0" + EMBEDDED_BUILD_ROOT + b"/csrc/model.cc\0suffix"
            library.write_bytes(raw_payload)
            manifest = root / "transform.txt"
            write_transform_manifest(
                manifest,
                "arm64-v8a/libsherpa.so",
                raw_payload,
                expected_replacements=1,
            )
            original_size = library.stat().st_size

            first = run_downloader_function(
                'sanitize_embedded_build_paths "$1" "$2"; validate_no_host_paths "$1"',
                root / "jniLibs", manifest,
            )
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(library.stat().st_size, original_size)
            transformed_payload = library.read_bytes()
            self.assertNotIn(EMBEDDED_BUILD_ROOT, transformed_payload)
            self.assertIn(SANITIZED_BUILD_ROOT + b"/csrc/model.cc", transformed_payload)

            second = run_downloader_function(
                'sanitize_embedded_build_paths "$1" "$2"',
                root / "jniLibs", manifest,
            )
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(library.read_bytes(), transformed_payload)

    def test_transform_rejects_corrupted_library(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            library = root / "jniLibs" / "arm64-v8a" / "libsherpa.so"
            library.parent.mkdir(parents=True)
            raw_payload = EMBEDDED_BUILD_ROOT + b"/csrc/model.cc"
            manifest = root / "transform.txt"
            write_transform_manifest(
                manifest,
                "arm64-v8a/libsherpa.so",
                raw_payload,
                expected_replacements=1,
            )
            library.write_bytes(raw_payload + b"corrupt")

            result = run_downloader_function(
                'sanitize_embedded_build_paths "$1" "$2"',
                root / "jniLibs", manifest,
            )
            self.assertNotEqual(result.returncode, 0)

    def test_transform_accepts_manifested_library_with_no_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            library = root / "jniLibs" / "arm64-v8a" / "libonnxruntime.so"
            library.parent.mkdir(parents=True)
            raw_payload = b"clean library with no embedded build root"
            library.write_bytes(raw_payload)
            manifest = root / "transform.txt"
            write_transform_manifest(
                manifest,
                "arm64-v8a/libonnxruntime.so",
                raw_payload,
                expected_replacements=0,
            )

            result = run_downloader_function(
                'sanitize_embedded_build_paths "$1" "$2"',
                root / "jniLibs", manifest,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(library.read_bytes(), raw_payload)

    def test_transform_rejects_missing_expected_marker(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            library = root / "jniLibs" / "arm64-v8a" / "libsherpa.so"
            library.parent.mkdir(parents=True)
            raw_payload = b"marker unexpectedly absent"
            library.write_bytes(raw_payload)
            manifest = root / "transform.txt"
            write_transform_manifest(
                manifest,
                "arm64-v8a/libsherpa.so",
                raw_payload,
                expected_replacements=1,
            )

            result = run_downloader_function(
                'sanitize_embedded_build_paths "$1" "$2"',
                root / "jniLibs", manifest,
            )
            self.assertNotEqual(result.returncode, 0)

    def test_unrecognized_host_path_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            library = root / "jniLibs" / "x86_64" / "libsherpa.so"
            library.parent.mkdir(parents=True)
            library.write_bytes(b"/Users/release-builder/sherpa/model.cc")
            result = run_downloader_function(
                'validate_no_host_paths "$1"',
                root / "jniLibs",
            )
            self.assertNotEqual(result.returncode, 0)

    def test_archive_digest_is_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            payload = Path(temporary_directory) / "payload"
            payload.write_bytes(b"verified artifact")
            expected = hashlib.sha256(payload.read_bytes()).hexdigest()

            valid = run_downloader_function(
                'verify_sha256 "$1" "$2"', expected, payload
            )
            self.assertEqual(valid.returncode, 0, valid.stderr)
            invalid = run_downloader_function(
                'verify_sha256 "$1" "$2"', "0" * 64, payload
            )
            self.assertNotEqual(invalid.returncode, 0)

    def test_every_pt_load_must_be_at_least_16k(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            fake_readelf = root / "readelf"
            fake_readelf.write_text('#!/bin/sh\ncat "$3"\n', encoding="utf-8")
            fake_readelf.chmod(fake_readelf.stat().st_mode | stat.S_IXUSR)

            cases = {
                "all-16k": ("  LOAD 0x0 0x0 0x0 0x1 0x1 R E 0x4000\n", True),
                "larger": ("  LOAD 0x0 0x0 0x0 0x1 0x1 R E 0x10000\n", True),
                "mixed": (
                    "  LOAD 0x0 0x0 0x0 0x1 0x1 R E 0x4000\n"
                    "  LOAD 0x1 0x1 0x1 0x1 0x1 RW  0x1000\n",
                    False,
                ),
                "unknown": ("Program Headers:\n", False),
                "malformed": ("  LOAD 0x0 0x0 0x0 0x1 0x1 R E unknown\n", False),
            }
            for name, (output, should_pass) in cases.items():
                with self.subTest(name=name):
                    shared_library = root / f"{name}.so"
                    shared_library.write_text(output, encoding="utf-8")
                    result = run_downloader_function(
                        'validate_elf_16kb_alignment "$1" "$2"',
                        shared_library,
                        fake_readelf,
                    )
                    self.assertEqual(result.returncode == 0, should_pass, result.stderr)

    def test_library_tree_fails_when_any_library_is_under_aligned(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            jni_root = root / "jniLibs/arm64-v8a"
            jni_root.mkdir(parents=True)
            fake_readelf = root / "readelf"
            fake_readelf.write_text('#!/bin/sh\ncat "$3"\n', encoding="utf-8")
            fake_readelf.chmod(fake_readelf.stat().st_mode | stat.S_IXUSR)
            (jni_root / "libgood.so").write_text(
                "  LOAD 0x0 0x0 0x0 0x1 0x1 R E 0x4000\n", encoding="utf-8"
            )
            bad_library = jni_root / "libbad.so"
            bad_library.write_text(
                "  LOAD 0x0 0x0 0x0 0x1 0x1 R E 0x1000\n", encoding="utf-8"
            )

            environment = {"RAC_SHERPA_READELF": str(fake_readelf)}
            invalid = run_downloader_function(
                'validate_library_tree "$1"', root / "jniLibs", environment=environment
            )
            self.assertNotEqual(invalid.returncode, 0)

            bad_library.write_text(
                "  LOAD 0x0 0x0 0x0 0x1 0x1 R E 0x4000\n", encoding="utf-8"
            )
            valid = run_downloader_function(
                'validate_library_tree "$1"', root / "jniLibs", environment=environment
            )
            self.assertEqual(valid.returncode, 0, valid.stderr)


if __name__ == "__main__":
    unittest.main()
