import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("build-core-android.sh")
SOURCE = SCRIPT.read_text(encoding="utf-8")


def function_source(name: str, next_name: str) -> str:
    start = SOURCE.index(f"{name}() {{")
    end = SOURCE.index(f"\n{next_name}() {{", start)
    return SOURCE[start:end]


class BuildCoreAndroidGuardTest(unittest.TestCase):
    def run_bash(self, source: str, env=None):
        return subprocess.run(
            ["bash", "-c", source],
            env={**os.environ, **(env or {})},
            capture_output=True,
            text=True,
        )

    def test_load_alignment_rejects_readelf_failure_zero_or_malformed_loads(self):
        function = function_source("validate_elf_16kb_alignment", "validate_staged_abi_16kb_alignment")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            readelf = root / "llvm-readelf"
            readelf.write_text(
                "#!/bin/sh\n"
                "case \"$READELF_CASE\" in\n"
                " valid) echo '  LOAD 0 0 0 0 0 R E 0x4000';;\n"
                " low) echo '  LOAD 0 0 0 0 0 R E 0x1000';;\n"
                " malformed) echo '  LOAD 0 0 0 0 0 R E banana';;\n"
                " partial_fail) echo '  LOAD 0 0 0 0 0 R E 0x4000'; exit 9;;\n"
                " empty) :;;\n"
                "esac\n",
                encoding="utf-8",
            )
            readelf.chmod(0o755)
            library = root / "lib.so"
            library.write_bytes(b"fixture")
            command = f'{function}\nANDROID_READELF="{readelf}"\nvalidate_elf_16kb_alignment "{library}"'
            self.assertEqual(self.run_bash(command, {"READELF_CASE": "valid"}).returncode, 0)
            for case in ("low", "malformed", "partial_fail", "empty"):
                result = self.run_bash(command, {"READELF_CASE": case})
                self.assertNotEqual(result.returncode, 0, case)

    def test_selected_prebuilt_requires_both_outputs_and_exact_engine_marker(self):
        function = function_source("validate_linked_qhexrt_outputs", "stage_qhexrt_qnn_runtime_libs")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            engine, jni = root / "engine.so", root / "jni.so"
            jni.write_bytes(b"jni")
            command = f'{function}\nvalidate_linked_qhexrt_outputs "{engine}" "{jni}"'
            self.assertNotEqual(self.run_bash(command).returncode, 0)
            engine.write_bytes(b"qhexrt shell only")
            self.assertNotEqual(self.run_bash(command).returncode, 0)
            engine.write_bytes(b"prefix qhexrt:engine-available suffix")
            self.assertEqual(self.run_bash(command).returncode, 0)

    def test_qairt_discovery_skips_newer_runtime_with_wrong_identity(self):
        functions = function_source("qairt_identity_matches", "validate_linked_qhexrt_outputs")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo = root / "runanywhere-sdks"
            repo.mkdir()
            manifest = root / "qhexrt-prebuilt.json"
            expected = b"matching runtime"
            manifest.write_text(json.dumps({
                "build": {"qnn_sdk": {
                    "metadata_file": "sdk.yaml",
                    "metadata_sha256": hashlib.sha256(expected).hexdigest(),
                }},
            }), encoding="utf-8")
            matching = root / "qairt" / "2.47.0"
            mismatched = root / "qairt" / "9.99.0"
            for candidate, metadata in ((matching, expected), (mismatched, b"different runtime")):
                (candidate / "lib" / "aarch64-android").mkdir(parents=True)
                (candidate / "sdk.yaml").write_bytes(metadata)
            command = (
                f'{functions}\n'
                f'REPO_ROOT="{repo}"\n'
                f'find_qairt_root "{manifest}"'
            )
            result = self.run_bash(command, {
                "QAIRT_ROOT": "",
                "QNN_SDK_ROOT": "",
                "QNN_ROOT": "",
            })
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(Path(result.stdout.strip()).resolve(), matching.resolve())

    def test_explicit_qnn_sdk_root_has_precedence_and_must_match_identity(self):
        functions = function_source("qairt_identity_matches", "validate_linked_qhexrt_outputs")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo = root / "runanywhere-sdks"
            repo.mkdir()
            manifest = root / "qhexrt-prebuilt.json"
            expected = b"matching runtime"
            manifest.write_text(json.dumps({
                "build": {"qnn_sdk": {
                    "metadata_file": "sdk.yaml",
                    "metadata_sha256": hashlib.sha256(expected).hexdigest(),
                }},
            }), encoding="utf-8")
            explicit = root / "explicit-qairt"
            fallback = root / "qairt" / "9.99.0"
            for candidate, metadata in ((explicit, b"wrong runtime"), (fallback, expected)):
                (candidate / "lib" / "aarch64-android").mkdir(parents=True)
                (candidate / "sdk.yaml").write_bytes(metadata)
            command = (
                f'{functions}\n'
                f'REPO_ROOT="{repo}"\n'
                f'find_qairt_root "{manifest}"'
            )
            env = {
                "QAIRT_ROOT": "",
                "QNN_SDK_ROOT": str(explicit),
                "QNN_ROOT": "",
            }
            result = self.run_bash(command, env)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")
            self.assertIn("QNN_SDK_ROOT does not match", result.stderr)

            (explicit / "sdk.yaml").write_bytes(expected)
            result = self.run_bash(command, env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(Path(result.stdout.strip()), explicit)

    def test_stub_never_discovers_or_stages_sibling_qairt(self):
        function = function_source("qairt_identity_matches", "validate_elf_16kb_alignment")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            stub = root / "stub.so"
            stub.write_bytes(b"qhexrt shell")
            called = root / "qairt-discovery-called"
            shell = (
                f'{function}\n'
                f'find_qairt_root() {{ touch "{called}"; echo "{root}/qairt"; }}\n'
                'copy_if_exists() { return 99; }\n'
                f'stage_qhexrt_qnn_runtime_libs arm64-v8a "{stub}" "{root}/selected" "{root}/dest"\n'
            )
            result = self.run_bash(shell)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(called.exists())

    def test_qairt_metadata_must_match_selected_prebuilt(self):
        function = function_source("qairt_identity_matches", "validate_elf_16kb_alignment")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            engine = root / "engine.so"
            engine.write_bytes(b"qhexrt:engine-available")
            selected = root / "selected"
            selected.mkdir()
            qairt = root / "qairt"
            qairt.mkdir()
            (qairt / "sdk.yaml").write_bytes(b"wrong runtime")
            (selected / "qhexrt-prebuilt.json").write_text(json.dumps({
                "build": {"qnn_sdk": {
                    "metadata_file": "sdk.yaml",
                    "metadata_sha256": hashlib.sha256(b"expected runtime").hexdigest(),
                }},
            }), encoding="utf-8")
            shell = (
                f'{function}\n'
                f'find_qairt_root() {{ echo "{qairt}"; }}\n'
                f'stage_qhexrt_qnn_runtime_libs arm64-v8a "{engine}" "{selected}" "{root}/dest"\n'
            )
            result = self.run_bash(shell)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("changed after identity-aware discovery", result.stderr)

    def test_absent_prebuilt_explicitly_clears_cached_backend_and_stale_outputs(self):
        self.assertIn('"-DRAC_BACKEND_QHEXRT=OFF" "-UQHEXRT_ROOT"', SOURCE)
        self.assertIn('if [ "${QHEXRT_ENABLED}" -eq 1 ]; then', SOURCE)
        self.assertIn('-name "librac_backend_qhexrt.so"', SOURCE)
        self.assertIn('-delete', SOURCE)

    def test_reusable_presets_force_every_public_android_backend_on(self):
        for setting in (
            '"-DRAC_BUILD_BACKENDS=ON"',
            '"-DRAC_BACKEND_CLOUD=ON"',
            '"-DRAC_BACKEND_RAG=ON"',
            '"-DRAC_BACKEND_LLAMACPP=ON"',
            '"-DRAC_BACKEND_ONNX=ON"',
            '"-DRAC_RUNTIME_ONNXRT=ON"',
            '"-DRAC_BACKEND_SHERPA=ON"',
        ):
            self.assertIn(setting, SOURCE)


if __name__ == "__main__":
    unittest.main()
