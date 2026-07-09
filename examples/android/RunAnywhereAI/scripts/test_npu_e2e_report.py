import contextlib
import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import npu_e2e_report


class SuiteGateTest(unittest.TestCase):
    @staticmethod
    def write_suite(path, model_id="melotts_en_v81"):
        payload = {
            "schema": "npu_suite/v1",
            "model_id": model_id,
            "cases": [{"id": "case0", "input": {"text": "hello"}}],
            "gate": {
                "metric": "audio",
                "intelligibility_wer_max": 0.2,
                "suite_pass_frac": 0.6,
            },
        }
        path.write_text(json.dumps(payload))
        return payload

    def test_logical_id_resolves_arch_suffixed_suite(self):
        with tempfile.TemporaryDirectory() as tmp:
            suites = Path(tmp)
            suite = suites / "melotts_en_v81.json"
            self.write_suite(suite)
            with mock.patch.object(npu_e2e_report, "SUITES", suites):
                gate = npu_e2e_report._suite_gate("melotts_en", "v81")

            self.assertEqual(gate["suite_id"], "melotts_en_v81")
            self.assertEqual(gate["suite_pass_frac"], 0.6)
            self.assertEqual(gate["intelligibility_wer_max"], 0.2)
            self.assertEqual(gate["suite_cases"], 1)
            self.assertEqual(gate["suite_metric"], "audio")
            self.assertEqual(len(gate["suite_sha256"]), 64)
            self.assertTrue(gate["suite_valid"])

    def test_missing_suite_is_explicit(self):
        with tempfile.TemporaryDirectory() as tmp:
            with mock.patch.object(npu_e2e_report, "SUITES", Path(tmp)):
                gate = npu_e2e_report._suite_gate("unknown", "v81")

            self.assertIsNone(gate["suite_id"])
            self.assertIsNone(gate["suite_sha256"])
            self.assertFalse(gate["suite_valid"])

    def test_invalid_suite_fails_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            suites = Path(tmp)
            (suites / "melotts_en_v81.json").write_text("not-json")
            with mock.patch.object(npu_e2e_report, "SUITES", suites):
                gate = npu_e2e_report._suite_gate("melotts_en", "v81")

            self.assertEqual(gate["suite_id"], "melotts_en_v81")
            self.assertFalse(gate["suite_valid"])


class ProductionProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.suites = self.root / "suites"
        self.suites.mkdir()
        self.report_dir = self.root / "report"
        self.report_dir.mkdir()
        self.suite_path = self.suites / "model_v81.json"
        SuiteGateTest.write_suite(self.suite_path, "model_v81")
        self.suite_sha = hashlib.sha256(self.suite_path.read_bytes()).hexdigest()

    def tearDown(self):
        self.tmp.cleanup()

    def report(self, modality="llm"):
        return {
            "schema": "npu_e2e/v1",
            "model_id": "model",
            "modality": modality,
            "arch": "v81",
            "suite": "npu_suite/v1:answer:1cases",
            "suite_id": "model_v81",
            "suite_sha256": self.suite_sha,
            "sdk_source": {"git_revision": "abc123", "git_dirty": False},
            "delete": {
                "requested": True,
                "success": True,
                "deleted_model_ids": ["model"],
                "failed_model_ids": [],
                "skipped_model_ids": [],
                "files_deleted": True,
                "registry_updated": True,
                "dry_run": False,
            },
            "gates": {"framework_qhexrt": True, "canonical_suite": True, "delete_model": True},
            "status": "PASS",
            "detail": "ok",
        }

    @staticmethod
    def run_inputs():
        return {
            "schema": "npu_e2e_inputs/v1",
            "sdk_git": {"revision": "abc123", "dirty": False},
            "artifacts": [
                {"path": "scripts/run_npu_e2e.sh", "sha256": "1" * 64},
                {"path": "scripts/npu_e2e_report.py", "sha256": "2" * 64},
            ],
            "installed_packages": [
                {"package": "app", "sha256": "3" * 64, "matches_local": True},
                {"package": "test", "sha256": "4" * 64, "matches_local": True},
            ],
        }

    def apply(self, report):
        path = self.report_dir / "npu_e2e_model.json"
        path.write_text(json.dumps(report))
        with mock.patch.object(npu_e2e_report, "SUITES", self.suites):
            suite = npu_e2e_report._apply_production_provenance(
                report,
                path,
                self.report_dir,
                self.run_inputs(),
                "f" * 64,
                {"revision": "abc123", "dirty": False},
            )
        return report, suite

    def test_suite_receipt_applies_to_every_modality(self):
        for modality in ("llm", "stt", "tts", "vlm", "embedding"):
            with self.subTest(modality=modality):
                report, suite = self.apply(self.report(modality))
                self.assertEqual(report["status"], "PASS")
                self.assertTrue(report["gates"]["canonical_suite"])
                self.assertTrue(report["gates"]["delete_model"])
                self.assertTrue(report["gates"]["source_provenance"])
                self.assertTrue(report["suite_provenance"]["exact_match"])
                self.assertEqual(suite["suite_sha256"], self.suite_sha)
                self.assertEqual(report["provenance"]["sdk_git"]["reported_revision"], "abc123")
                self.assertEqual(report["report_inputs"][0]["role"], "device_report")
                self.assertEqual(len(report["report_inputs"][0]["sha256"]), 64)

    def test_suite_hash_mismatch_fails_closed(self):
        report = self.report()
        report["suite_sha256"] = "0" * 64
        report, _ = self.apply(report)

        self.assertEqual(report["status"], "FAIL")
        self.assertFalse(report["gates"]["canonical_suite"])
        self.assertIn("does not match", report["detail"])

    def test_missing_delete_receipt_fails_closed(self):
        report = self.report()
        report.pop("delete")
        report, _ = self.apply(report)

        self.assertEqual(report["status"], "FAIL")
        self.assertFalse(report["gates"]["delete_model"])
        self.assertIn("deletion was not fully confirmed", report["detail"])

    def test_partial_delete_receipt_fails_closed(self):
        report = self.report()
        report["delete"]["files_deleted"] = False
        report, _ = self.apply(report)

        self.assertEqual(report["status"], "FAIL")
        self.assertFalse(report["gates"]["delete_model"])

    def test_source_revision_mismatch_fails_closed(self):
        report = self.report()
        report["sdk_source"]["git_revision"] = "different"
        report, _ = self.apply(report)

        self.assertEqual(report["status"], "FAIL")
        self.assertFalse(report["gates"]["source_provenance"])
        self.assertIn("source revision", report["detail"])

    def test_installed_apk_mismatch_fails_closed(self):
        report = self.report()
        path = self.report_dir / "npu_e2e_model.json"
        path.write_text(json.dumps(report))
        run_inputs = self.run_inputs()
        run_inputs["installed_packages"][0]["matches_local"] = False
        with mock.patch.object(npu_e2e_report, "SUITES", self.suites):
            npu_e2e_report._apply_production_provenance(
                report, path, self.report_dir, run_inputs, "f" * 64,
                {"revision": "abc123", "dirty": False},
            )

        self.assertEqual(report["status"], "FAIL")
        self.assertFalse(report["gates"]["source_provenance"])

    def test_run_inputs_are_hashed(self):
        path = self.report_dir / "run_inputs.json"
        path.write_text(json.dumps({"schema": "npu_e2e_inputs/v1", "sdk_git": {"revision": "abc123"}}))

        payload, digest = npu_e2e_report._load_run_inputs(self.report_dir)

        self.assertEqual(payload["schema"], "npu_e2e_inputs/v1")
        self.assertEqual(digest, hashlib.sha256(path.read_bytes()).hexdigest())

    def test_main_writes_provenance_summary_and_returns_success(self):
        report_path = self.report_dir / "npu_e2e_model.json"
        report_path.write_text(json.dumps(self.report()))
        (self.report_dir / "run_inputs.json").write_text(json.dumps(self.run_inputs()))
        with (
            mock.patch.object(npu_e2e_report, "SUITES", self.suites),
            mock.patch.object(npu_e2e_report, "_local_git_state", return_value={"revision": "abc123", "dirty": False}),
            mock.patch.object(npu_e2e_report.sys, "argv", ["npu_e2e_report.py", str(self.report_dir)]),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            result = npu_e2e_report.main()

        self.assertEqual(result, 0)
        summary = json.loads((self.report_dir / "summary.json").read_text())
        self.assertEqual(summary[0]["suite_id"], "model_v81")
        self.assertTrue(summary[0]["suite_exact"])
        self.assertTrue(summary[0]["delete_model"])
        self.assertTrue(summary[0]["source_provenance"])
        self.assertEqual(summary[0]["sdk_git_revision"], "abc123")
        self.assertIn("model_v81@", (self.report_dir / "summary.md").read_text())

    def test_main_fails_tts_when_expected_wav_is_missing(self):
        report = self.report("tts")
        report["samples"] = [{"idx": 0, "input": "hello"}]
        (self.report_dir / "npu_e2e_model.json").write_text(json.dumps(report))
        (self.report_dir / "run_inputs.json").write_text(json.dumps(self.run_inputs()))
        with (
            mock.patch.object(npu_e2e_report, "SUITES", self.suites),
            mock.patch.object(npu_e2e_report, "_local_git_state", return_value={"revision": "abc123", "dirty": False}),
            mock.patch.object(npu_e2e_report.sys, "argv", ["npu_e2e_report.py", str(self.report_dir)]),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            result = npu_e2e_report.main()

        self.assertEqual(result, 1)
        persisted = json.loads((self.report_dir / "npu_e2e_model.json").read_text())
        self.assertFalse(persisted["gates"]["tts_intelligibility"])
        self.assertIn("WAV inputs are missing", persisted["detail"])

    def test_main_returns_failure_when_lifecycle_receipt_is_missing(self):
        report = self.report()
        report.pop("delete")
        (self.report_dir / "npu_e2e_model.json").write_text(json.dumps(report))
        with (
            mock.patch.object(npu_e2e_report, "SUITES", self.suites),
            mock.patch.object(npu_e2e_report, "_local_git_state", return_value={"revision": "abc123", "dirty": False}),
            mock.patch.object(npu_e2e_report.sys, "argv", ["npu_e2e_report.py", str(self.report_dir)]),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            result = npu_e2e_report.main()

        self.assertEqual(result, 1)
        summary = json.loads((self.report_dir / "summary.json").read_text())
        self.assertEqual(summary[0]["status"], "FAIL")
        self.assertFalse(summary[0]["delete_model"])


if __name__ == "__main__":
    unittest.main()
