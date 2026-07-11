import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("preflight_npu_assets.py")


class AssetPreflightTest(unittest.TestCase):
    def fixture(self, root: Path):
        assets = root / "assets"
        suites = assets / "npu_suites"
        fixtures = assets / "qhexrt_fixtures"
        suites.mkdir(parents=True)
        fixtures.mkdir()
        suite = {
            "schema": "npu_suite/v1",
            "model_id": "demo_v81",
            "hf_repo": "runanywhere/demo_HNPU",
            "arch": "v81",
            "modality": "asr",
            "cases": [{"id": "wav", "input": {"wav_asset": "input.wav"}}],
        }
        suite_path = suites / "demo_v81.json"
        suite_path.write_text(json.dumps(suite), encoding="utf-8")
        wav = fixtures / "input.wav"
        wav.write_bytes(b"RIFF synthetic wav fixture")
        files = {
            "npu_suites/demo_v81.json": hashlib.sha256(suite_path.read_bytes()).hexdigest(),
            "qhexrt_fixtures/input.wav": hashlib.sha256(wav.read_bytes()).hexdigest(),
        }
        (assets / ".qhexrt_device_assets.json").write_text(
            json.dumps({"schema": "qhexrt_android_asset_mirror/v1", "files": files}),
            encoding="utf-8",
        )
        return assets

    def run_preflight(self, assets: Path, *extra: str):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--assets", str(assets), "--arch", "v81", *extra],
            capture_output=True,
            text=True,
        )

    def test_catalog_suite_and_wav_fixture_are_verified(self):
        with tempfile.TemporaryDirectory() as temporary:
            assets = self.fixture(Path(temporary))
            result = self.run_preflight(assets, "--model", "demo")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("demo_v81", result.stdout)

    def test_ad_hoc_repo_uses_modality_alias_and_exact_suite(self):
        with tempfile.TemporaryDirectory() as temporary:
            assets = self.fixture(Path(temporary))
            result = self.run_preflight(
                assets,
                "--hf-repo", "runanywhere/demo_HNPU",
                "--modality", "stt",
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_manifest_or_fixture_fails_with_sync_instruction(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets = root / "assets"
            assets.mkdir()
            result = self.run_preflight(assets, "--model", "demo")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("sync_android_assets.sh", result.stderr)

            assets = self.fixture(root / "second")
            (assets / "qhexrt_fixtures/input.wav").unlink()
            result = self.run_preflight(assets, "--model", "demo")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("fixture is missing", result.stderr)

    def test_tampered_suite_or_fixture_fails_before_device_work(self):
        with tempfile.TemporaryDirectory() as temporary:
            assets = self.fixture(Path(temporary))
            (assets / "qhexrt_fixtures/input.wav").write_bytes(b"tampered")
            result = self.run_preflight(assets, "--model", "demo")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("mismatched", result.stderr)

    def test_payload_arch_must_match_requested_arch_and_suite_suffix(self):
        with tempfile.TemporaryDirectory() as temporary:
            assets = self.fixture(Path(temporary))
            suite_path = assets / "npu_suites/demo_v81.json"
            suite = json.loads(suite_path.read_text())
            suite["arch"] = "v79"
            suite_path.write_text(json.dumps(suite), encoding="utf-8")
            mirror_path = assets / ".qhexrt_device_assets.json"
            mirror = json.loads(mirror_path.read_text())
            mirror["files"]["npu_suites/demo_v81.json"] = hashlib.sha256(
                suite_path.read_bytes()
            ).hexdigest()
            mirror_path.write_text(json.dumps(mirror), encoding="utf-8")
            result = self.run_preflight(assets, "--model", "demo")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("architecture does not match", result.stderr)

    def test_legacy_lama_holdout_asset_is_rejected_not_ignored(self):
        with tempfile.TemporaryDirectory() as temporary:
            assets = self.fixture(Path(temporary))
            (assets / "lama_hold_restricted_source.jpg").write_bytes(b"must not ship")
            result = self.run_preflight(assets, "--model", "demo")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("must be deleted", result.stderr)


if __name__ == "__main__":
    unittest.main()
