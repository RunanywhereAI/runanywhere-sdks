import contextlib
import copy
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
    def write_suite(path, model_id="model_v81"):
        payload = {
            "schema": "npu_suite/v1",
            "model_id": model_id,
            "modality": "llm",
            "cases": [{
                "id": "case0",
                "input": {"text": "The capital of France is"},
                "expect_keywords": ["paris"],
            }],
            "gate": {
                "metric": "answer_keyword_coherence",
                "suite_pass_frac": 1.0,
                "min_inputs": 1,
                "min_decode_toks": 10.0,
            },
        }
        path.write_text(json.dumps(payload))
        return payload

    def test_logical_id_resolves_arch_suffixed_suite(self):
        with tempfile.TemporaryDirectory() as tmp:
            suites = Path(tmp)
            suite = suites / "melotts_en_v81.json"
            self.write_suite(suite, "melotts_en_v81")
            with mock.patch.object(npu_e2e_report, "SUITES", suites):
                gate = npu_e2e_report._suite_gate("melotts_en", "v81")

            self.assertEqual(gate["suite_id"], "melotts_en_v81")
            self.assertEqual(gate["gate"]["suite_pass_frac"], 1.0)
            self.assertEqual(gate["gate"]["min_decode_toks"], 10.0)
            self.assertEqual(gate["suite_cases"], 1)
            self.assertEqual(gate["suite_metric"], "answer_keyword_coherence")
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

    def test_every_synced_suite_has_executable_known_gate_coverage(self):
        suites = sorted(npu_e2e_report.SUITES.glob("*.json"))
        self.assertTrue(suites)
        for path in suites:
            with self.subTest(suite=path.name):
                suite = npu_e2e_report._suite_gate(path.stem)
                self.assertTrue(suite["suite_valid"], suite["validation_errors"])
                spec = npu_e2e_report.GATE_SPECS[suite["suite_metric"]]
                self.assertEqual(
                    set(suite["gate"]),
                    spec["required"] | (set(suite["gate"]) & spec["optional"]),
                )
                self.assertEqual(len(suite["cases"]), len(suite["executable_cases"]))

    def test_impossible_min_inputs_is_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            suites = Path(tmp)
            path = suites / "model_v81.json"
            payload = self.write_suite(path)
            payload["gate"]["min_inputs"] = 2
            path.write_text(json.dumps(payload))
            with mock.patch.object(npu_e2e_report, "SUITES", suites):
                suite = npu_e2e_report._suite_gate("model", "v81")
            self.assertFalse(suite["suite_valid"])
            self.assertIn("executable cases < min_inputs", " ".join(suite["validation_errors"]))

    def test_non_executable_vlm_case_is_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            suites = Path(tmp)
            path = suites / "model_v81.json"
            payload = {
                "schema": "npu_suite/v1", "model_id": "model_v81", "modality": "vlm_image",
                "gate": {"metric": "keyword", "suite_pass_frac": 1.0, "min_inputs": 1},
                "cases": [{"id": "text_only", "input": {"text": "not an image"}}],
            }
            path.write_text(json.dumps(payload))
            with mock.patch.object(npu_e2e_report, "SUITES", suites):
                suite = npu_e2e_report._suite_gate("model", "v81")
            self.assertFalse(suite["suite_valid"])
            self.assertIn("0/1 cases are executable", " ".join(suite["validation_errors"]))

    def test_unbacked_mel_threshold_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            suites = Path(tmp)
            path = suites / "model_v81.json"
            payload = {
                "schema": "npu_suite/v1", "model_id": "model_v81", "modality": "tts",
                "gate": {
                    "metric": "audio_sanity_intelligibility", "suite_pass_frac": 1.0,
                    "min_inputs": 1, "expected_sample_rate": 24000,
                    "intelligibility_wer_max": 0.15, "rms_min": 0.005,
                    "min_seconds": 0.3, "mel_cos_floor": 0.9,
                },
                "cases": [{"id": "t0", "input": {"text": "hello"}}],
            }
            path.write_text(json.dumps(payload))
            with mock.patch.object(npu_e2e_report, "SUITES", suites):
                suite = npu_e2e_report._suite_gate("model", "v81")
            self.assertFalse(suite["suite_valid"])
            self.assertIn("unknown/unapplied gate keys", " ".join(suite["validation_errors"]))


class CanonicalThresholdEvaluationTest(unittest.TestCase):
    @staticmethod
    def report(modality, cases, samples):
        ids = [case["id"] for case in cases]
        return {
            "modality": modality,
            "executed_case_ids": ids,
            "executed_case_count": len(ids),
            "samples": samples,
            "gates": {},
            "status": "PASS",
            "detail": "ok",
        }

    def test_qwen_decode_floor_regression_fails_without_unapplied_keys(self):
        suite = npu_e2e_report._suite_gate("qwen3_5_0_8b", "v81")
        self.assertTrue(suite["suite_valid"], suite["validation_errors"])
        samples = []
        for index, case in enumerate(suite["cases"]):
            samples.append({
                "id": case["id"],
                "output": case["expect_keywords"][0],
                "decode_toks": 14.85 if index == 0 else 20.0,
                "max_new": 128,
            })
        report = self.report("llm", suite["cases"], samples)

        self.assertFalse(npu_e2e_report._apply_canonical_thresholds(report, suite))
        self.assertFalse(report["gates"]["canonical_thresholds"])
        self.assertEqual(report["unapplied_gate_keys"], [])
        self.assertIn("below min_decode_toks=15.0", report["detail"])

    def test_all_qwen_declared_keys_apply_on_a_passing_fixture(self):
        suite = npu_e2e_report._suite_gate("qwen3_5_0_8b", "v81")
        samples = [{
            "id": case["id"], "output": case["expect_keywords"][0],
            "decode_toks": 15.0, "max_new": 128,
        } for case in suite["cases"]]
        report = self.report("llm", suite["cases"], samples)

        self.assertTrue(npu_e2e_report._apply_canonical_thresholds(report, suite), report["detail"])
        self.assertEqual(report["unapplied_gate_keys"], [])
        self.assertEqual(set(report["applied_gate_keys"]), set(suite["gate"]))

    def test_tts_uses_mean_intelligibility_wer_and_applies_every_field(self):
        gate = {
            "metric": "audio_sanity_intelligibility", "suite_pass_frac": 1.0,
            "min_inputs": 3, "expected_sample_rate": 24000,
            "intelligibility_wer_max": 0.15, "rms_min": 0.005, "min_seconds": 0.3,
        }
        cases = [{"id": f"t{i}", "input": {"text": f"sample {i}"}} for i in range(3)]
        suite = {"suite_valid": True, "validation_errors": [], "gate": gate,
                 "cases": cases, "executable_cases": cases}
        samples = [{
            "id": f"t{i}", "sample_rate": 24000, "rms": 0.01, "audio_s": 1.0,
            "intelligibility_wer": value,
        } for i, value in enumerate((0.0, 0.0, 0.3))]
        report = self.report("tts", cases, samples)

        self.assertTrue(npu_e2e_report._apply_canonical_thresholds(report, suite), report["detail"])
        self.assertAlmostEqual(report["intelligibility_wer"], 0.1)
        self.assertEqual(set(report["applied_gate_keys"]), set(gate))

    def test_unknown_gate_key_is_unapplied_and_fails(self):
        suite = npu_e2e_report._suite_gate("qwen3_5_0_8b", "v81")
        suite = dict(suite)
        suite["gate"] = dict(suite["gate"], edit_tol=0.1)
        samples = [{
            "id": case["id"], "output": case["expect_keywords"][0],
            "decode_toks": 20.0, "max_new": 128,
        } for case in suite["cases"]]
        report = self.report("llm", suite["cases"], samples)

        self.assertFalse(npu_e2e_report._apply_canonical_thresholds(report, suite))
        self.assertEqual(report["unapplied_gate_keys"], ["edit_tol"])

    def test_embedding_applies_every_declared_field(self):
        suite = npu_e2e_report._suite_gate("embeddinggemma_300m", "v81")
        samples = [{
            "id": case["id"], "dim": 768, "margin": 0.1,
            "query_l2": 1.0, "positive_l2": 1.0, "negative_l2": 1.0,
        } for case in suite["cases"]]
        report = self.report("embedding", suite["cases"], samples)

        self.assertTrue(npu_e2e_report._apply_canonical_thresholds(report, suite), report["detail"])
        self.assertEqual(set(report["applied_gate_keys"]), set(suite["gate"]))

    def test_inpaint_applies_every_declared_field(self):
        suite = npu_e2e_report._suite_gate("lama_dilated", "v81")
        samples = [{
            "id": case["id"], "full_cosine": 1.0, "hole_cosine": 1.0,
            "hole_relative_l2": 0.0, "full_psnr_db": 99.0, "hole_psnr_db": 99.0,
            "seam_psnr_db": 99.0, "unmasked_mae_rgb8": 0.0,
            "unmasked_p99_rgb8": 0.0, "unmasked_within_one_lsb": 1.0,
            "hole_changed_fraction": 1.0,
        } for case in suite["cases"]]
        report = self.report("inpaint", suite["cases"], samples)

        self.assertTrue(npu_e2e_report._apply_canonical_thresholds(report, suite), report["detail"])
        self.assertEqual(set(report["applied_gate_keys"]), set(suite["gate"]))

    def test_tts_declared_thresholds_each_fail_when_violated(self):
        gate = {
            "metric": "audio_sanity_intelligibility", "suite_pass_frac": 1.0,
            "min_inputs": 3, "expected_sample_rate": 24000,
            "intelligibility_wer_max": 0.15, "rms_min": 0.005, "min_seconds": 0.3,
        }
        cases = [{"id": f"t{i}", "input": {"text": f"sample {i}"}} for i in range(3)]
        base_suite = {"suite_valid": True, "validation_errors": [], "gate": gate,
                      "cases": cases, "executable_cases": cases}
        base_samples = [{
            "id": f"t{i}", "sample_rate": 24000, "rms": 0.01, "audio_s": 1.0,
            "intelligibility_wer": 0.0,
        } for i in range(3)]
        mutations = {
            "min_inputs": lambda suite, samples: suite["gate"].__setitem__("min_inputs", 4),
            "expected_sample_rate": lambda suite, samples: samples[0].__setitem__("sample_rate", 16000),
            "rms_min": lambda suite, samples: samples[0].__setitem__("rms", 0.0),
            "min_seconds": lambda suite, samples: samples[0].__setitem__("audio_s", 0.1),
            "intelligibility_wer_max": lambda suite, samples: samples[0].__setitem__("intelligibility_wer", 1.0),
        }
        for name, mutate in mutations.items():
            with self.subTest(gate=name):
                suite = copy.deepcopy(base_suite)
                samples = copy.deepcopy(base_samples)
                mutate(suite, samples)
                report = self.report("tts", cases, samples)
                self.assertFalse(npu_e2e_report._apply_canonical_thresholds(report, suite))
                self.assertIn(name, report["applied_gate_keys"])

    def test_inpaint_each_image_threshold_fails_when_violated(self):
        suite = npu_e2e_report._suite_gate("lama_dilated", "v81")
        passing = {
            "full_cosine": 1.0, "hole_cosine": 1.0, "hole_relative_l2": 0.0,
            "full_psnr_db": 99.0, "hole_psnr_db": 99.0, "seam_psnr_db": 99.0,
            "unmasked_mae_rgb8": 0.0, "unmasked_p99_rgb8": 0.0,
            "unmasked_within_one_lsb": 1.0, "hole_changed_fraction": 1.0,
        }
        violations = {
            "minimum_full_cosine": ("full_cosine", 0.0),
            "minimum_hole_cosine": ("hole_cosine", 0.0),
            "maximum_hole_relative_l2": ("hole_relative_l2", 1.0),
            "minimum_full_psnr_db": ("full_psnr_db", 0.0),
            "minimum_hole_psnr_db": ("hole_psnr_db", 0.0),
            "minimum_seam_psnr_db": ("seam_psnr_db", 0.0),
            "maximum_unmasked_mean_absolute_error_rgb8": ("unmasked_mae_rgb8", 10.0),
            "maximum_unmasked_p99_absolute_error_rgb8": ("unmasked_p99_rgb8", 10.0),
            "minimum_unmasked_rgb8_within_one_lsb_fraction": ("unmasked_within_one_lsb", 0.0),
            "minimum_hole_changed_fraction": ("hole_changed_fraction", 0.0),
        }
        for gate_key, (sample_key, value) in violations.items():
            with self.subTest(gate=gate_key):
                samples = [dict(passing, id=case["id"]) for case in suite["cases"]]
                samples[0][sample_key] = value
                report = self.report("inpaint", suite["cases"], samples)
                self.assertFalse(npu_e2e_report._apply_canonical_thresholds(report, suite))
                self.assertIn(gate_key, report["applied_gate_keys"])


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
            "suite": "npu_suite/v1:answer_keyword_coherence:1cases",
            "suite_id": "model_v81",
            "suite_sha256": self.suite_sha,
            "executed_case_ids": ["case0"],
            "executed_case_count": 1,
            "samples": [{
                "id": "case0",
                "output": "Paris",
                "decode_toks": 20.0,
                "max_new": 32,
                "pass": True,
            }],
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

    def test_registration_failure_marks_delete_not_applicable_without_cascade(self):
        report = self.report()
        report["status"] = "FAIL"
        report["phase"] = "register"
        report["detail"] = "registration failed before persistence"
        report["delete"] = {
            "applicable": False,
            "requested": False,
            "success": False,
            "reason": "registration_not_persisted",
        }
        report["gates"].pop("delete_model")
        report, _ = self.apply(report)

        self.assertEqual(report["status"], "FAIL")
        self.assertEqual(report["phase"], "register")
        self.assertNotIn("delete_model", report["gates"])
        self.assertEqual(report["detail"], "registration failed before persistence")

    def test_passing_run_cannot_bypass_delete_with_not_applicable_receipt(self):
        report = self.report()
        report["delete"] = {
            "applicable": False,
            "requested": False,
            "success": False,
            "reason": "registration_not_persisted",
        }
        report, _ = self.apply(report)

        self.assertEqual(report["status"], "FAIL")
        self.assertFalse(report["gates"]["delete_model"])
        self.assertIn("deletion was not fully confirmed", report["detail"])

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
        self.assertFalse(persisted["gates"]["tts_intelligibility_evidence"])
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
