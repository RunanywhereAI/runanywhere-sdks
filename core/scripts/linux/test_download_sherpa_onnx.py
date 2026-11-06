#!/usr/bin/env python3
"""Focused guards for the Linux Sherpa-ONNX dependency downloader."""

from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT_DIR = Path(__file__).resolve().parent
DOWNLOADER = SCRIPT_DIR / "download-sherpa-onnx.sh"
CORE_DIR = SCRIPT_DIR.parent.parent


class InheritedVersionKeyTest(unittest.TestCase):
    def test_key_missing_from_versions_is_not_satisfied_by_environment(self) -> None:
        for key, arch in (
            ("SHERPA_ONNX_VERSION_LINUX", "x86_64"),
            ("SHERPA_ONNX_REPO_DESKTOP", "x86_64"),
            ("SHERPA_ONNX_RELEASE_TAG_DESKTOP", "x86_64"),
            ("SHERPA_ONNX_COMMIT_DESKTOP", "x86_64"),
            ("ONNX_VERSION_LINUX", "x86_64"),
            ("SHERPA_ONNX_LINUX_X64_SHA256", "x86_64"),
            ("SHERPA_ONNX_LINUX_AARCH64_SHA256", "aarch64"),
        ):
            with self.subTest(key=key), tempfile.TemporaryDirectory() as temporary_directory:
                # Mirror core/ so the script's ROOT_DIR resolves to the edited VERSIONS.
                core = Path(temporary_directory) / "core"
                (core / "scripts" / "linux").mkdir(parents=True)
                shutil.copy(DOWNLOADER, core / "scripts" / "linux")
                shutil.copy(CORE_DIR / "scripts" / "load-versions.sh", core / "scripts")
                lines = (CORE_DIR / "VERSIONS").read_text(encoding="utf-8").splitlines()
                (core / "VERSIONS").write_text(
                    "\n".join(line for line in lines if not line.startswith(f"{key}="))
                    + "\n",
                    encoding="utf-8",
                )
                destination = Path(temporary_directory) / "dest"
                destination.mkdir()
                (destination / "keep").touch()

                result = subprocess.run(
                    ["/bin/bash", str(core / "scripts" / "linux" / "download-sherpa-onnx.sh")],
                    check=False,
                    capture_output=True,
                    text=True,
                    env={
                        **os.environ,
                        key: "stale",
                        "RAC_SHERPA_DIR": str(destination),
                        "RAC_PLATFORM_ARCH": arch,
                    },
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"{key} is not set", result.stderr)
                self.assertTrue((destination / "keep").exists())


if __name__ == "__main__":
    unittest.main()
