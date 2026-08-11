#!/usr/bin/env python3
"""Focused guards for the canonical per-ABI Android release archive."""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile


SCRIPT = Path(__file__).resolve().parent / "build-android.sh"
ABI = "arm64-v8a"
LIBRARIES = {
    "jni": (
        "libc++_shared.so",
        "libomp.so",
        "librac_backend_cloud.so",
        "librac_commons.so",
        "librunanywhere_jni.so",
    ),
    "llamacpp": (
        "libc++_shared.so",
        "librac_backend_llamacpp.so",
        "librac_backend_llamacpp_jni.so",
        "librunanywhere_llamacpp.so",
    ),
    "onnx": (
        "libc++_shared.so",
        "libonnxruntime.so",
        "librac_backend_onnx.so",
        "librac_backend_onnx_jni.so",
        "librac_backend_sherpa.so",
        "librunanywhere_onnx.so",
        "librunanywhere_sherpa.so",
        "libsherpa-onnx-c-api.so",
        "libsherpa-onnx-jni.so",
    ),
}


def run_function(expression: str, *arguments: Path | str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "/bin/bash",
            "-c",
            'source "$1"; shift; ' + expression,
            "bash",
            str(SCRIPT),
            *(str(argument) for argument in arguments),
        ],
        check=False,
        capture_output=True,
        text=True,
    )


def write_elf(path: Path, marker: bytes = b"") -> None:
    path.write_bytes(b"\x7fELF" + b"\0" * 60 + marker)
    path.chmod(0o755)


def make_staging(parent: Path) -> Path:
    staging = parent / ABI
    for component, libraries in LIBRARIES.items():
        component_dir = staging / component
        component_dir.mkdir(parents=True)
        for library in libraries:
            write_elf(component_dir / library, f"{component}/{library}".encode())
    return staging


class AndroidArchiveContractTest(unittest.TestCase):
    def test_release_version_rejects_path_or_shell_syntax(self) -> None:
        accepted = run_function('validate_release_version "$1"', "0.19.15-rc.1")
        self.assertEqual(accepted.returncode, 0, accepted.stderr)
        for version in ("../private", "0.19.15/extra", "$(touch nope)", "", " release"):
            with self.subTest(version=version):
                rejected = run_function('validate_release_version "$1"', version)
                self.assertNotEqual(rejected.returncode, 0)
                self.assertIn("invalid Android release version", rejected.stderr)

    def test_archive_is_exact_and_reproducible(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            staging_parent = root / "staging"
            staging = make_staging(staging_parent)
            archive = root / "RACommons-android-arm64-v8a-v1.2.3.zip"
            expression = (
                'validate_staging_root "$1"; '
                'create_deterministic_archive "$2" "$3" "$4"; '
                'write_checksum "$4"'
            )

            first = run_function(expression, staging, staging_parent, ABI, archive)
            self.assertEqual(first.returncode, 0, first.stderr)
            first_digest = hashlib.sha256(archive.read_bytes()).hexdigest()

            for path in staging.rglob("*"):
                os.utime(path, (1_700_000_000, 1_700_000_000), follow_symlinks=False)
                path.chmod(0o700 if path.is_dir() else 0o600)
            second = run_function(expression, staging, staging_parent, ABI, archive)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(), first_digest)

            expected = {f"{ABI}/"}
            for component, libraries in LIBRARIES.items():
                expected.add(f"{ABI}/{component}/")
                expected.update(f"{ABI}/{component}/{library}" for library in libraries)
            with zipfile.ZipFile(archive) as release:
                self.assertEqual(set(release.namelist()), expected)
                self.assertNotIn(f"{ABI}/unified/", release.namelist())
                for info in release.infolist():
                    self.assertEqual(info.date_time, (1980, 1, 1, 0, 0, 0))
                    self.assertEqual((info.external_attr >> 16) & 0o777, 0o755)

            checksum = archive.with_name(f"{archive.name}.sha256").read_text(encoding="utf-8")
            self.assertEqual(checksum, f"{first_digest}  {archive.name}\n")

    def test_rejects_private_native(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging = make_staging(Path(temporary_directory))
            write_elf(staging / "onnx" / "libQnnHtp.so")
            result = run_function('validate_staging_root "$1"', staging)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("private QHexRT/QNN", result.stderr)

    def test_rejects_undeclared_native(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging = make_staging(Path(temporary_directory))
            write_elf(staging / "jni" / "libunexpected.so")
            result = run_function('validate_staging_root "$1"', staging)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("undeclared native input", result.stderr)

    def test_rejects_nested_or_extra_component(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging = make_staging(Path(temporary_directory))
            (staging / "unified").mkdir()
            result = run_function('validate_staging_root "$1"', staging)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("exactly {jni,llamacpp,onnx}", result.stderr)

            (staging / "unified").rmdir()
            (staging / "onnx" / "nested").mkdir()
            nested = run_function('validate_staging_root "$1"', staging)
            self.assertNotEqual(nested.returncode, 0)
            self.assertIn("non-regular or nested input", nested.stderr)

    def test_rejects_undeclared_root_file_or_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging = make_staging(Path(temporary_directory))
            (staging / "manifest.json").write_text("{}", encoding="utf-8")
            extra_file = run_function('validate_staging_root "$1"', staging)
            self.assertNotEqual(extra_file.returncode, 0)
            self.assertIn("exactly {jni,llamacpp,onnx}", extra_file.stderr)

            (staging / "manifest.json").unlink()
            (staging / "alias").symlink_to(staging / "jni", target_is_directory=True)
            symlink = run_function('validate_staging_root "$1"', staging)
            self.assertNotEqual(symlink.returncode, 0)
            self.assertIn("exactly {jni,llamacpp,onnx}", symlink.stderr)

    def test_rejects_symlink_non_elf_and_missing_input(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            staging = make_staging(Path(temporary_directory))
            target = staging / "jni" / "librac_commons.so"
            target.unlink()
            target.symlink_to(staging / "jni" / "libomp.so")
            symlink = run_function('validate_staging_root "$1"', staging)
            self.assertNotEqual(symlink.returncode, 0)
            self.assertIn("non-regular or nested input", symlink.stderr)

            target.unlink()
            target.write_bytes(b"not an ELF")
            non_elf = run_function('validate_staging_root "$1"', staging)
            self.assertNotEqual(non_elf.returncode, 0)
            self.assertIn("input is not ELF", non_elf.stderr)

            target.unlink()
            missing = run_function('validate_staging_root "$1"', staging)
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn("native inventory mismatch", missing.stderr)


if __name__ == "__main__":
    unittest.main()
