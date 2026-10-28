#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Exercise the schema-lock CLI in checkouts with and without spaces."""

import hashlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "schema_lock.sh"
PROTOS = {"z.proto": b'syntax = "proto3";\n', "a.proto": b"// fixture\n"}


class SchemaLockIntegrationTest(unittest.TestCase):
    def test_checkout_path_does_not_change_schema_identity(self):
        expected_digest = hashlib.sha256()
        for name, content in sorted(PROTOS.items()):
            expected_digest.update(
                f"{name}\n{hashlib.sha256(content).hexdigest()}\n".encode()
            )

        with tempfile.TemporaryDirectory() as temporary:
            for directory in ("checkout", "checkout with spaces [fixture]"):
                with self.subTest(directory=directory):
                    repo = Path(temporary) / directory
                    codegen = repo / "idl" / "codegen"
                    codegen.mkdir(parents=True)
                    script = codegen / SCRIPT.name
                    shutil.copyfile(SCRIPT, script)
                    (repo / "idl" / "VERSION").write_text("1.2.3\n")
                    (repo / "core").mkdir()
                    (repo / "core" / "VERSIONS").write_text("PROTOC_VERSION=35.1\n")
                    for name, content in PROTOS.items():
                        (repo / "idl" / name).write_bytes(content)

                    def run(*arguments):
                        return subprocess.run(
                            ["bash", script.as_posix(), *arguments],
                            capture_output=True,
                            text=True,
                            check=False,
                        )

                    printed = run("--print")
                    self.assertEqual(printed.returncode, 0, printed.stderr)
                    self.assertIn(expected_digest.hexdigest(), printed.stdout)
                    updated = run("--update")
                    self.assertEqual(updated.returncode, 0, updated.stderr)
                    checked = run("--check")
                    self.assertEqual(checked.returncode, 0, checked.stderr)
                    (repo / "idl" / "a.proto").write_bytes(b"// changed\n")
                    self.assertNotEqual(run("--check").returncode, 0)


if __name__ == "__main__":
    unittest.main()
