#!/usr/bin/env python3
"""Aggregate on-device NPU E2E per-run JSON reports into a shareable summary.

Reads every ``npu_e2e_<id>.json`` pulled by run_npu_e2e.sh from a report dir,
and — for TTS models — round-trips each synthesized wav through offline whisper
to add an intelligibility WER (vs the input text), the same round-trip forge's
TTS gate uses. Canonical-suite, SDK-source, report-input, and deletion receipts
are mandatory production gates. Writes ``summary.md`` + ``summary.json`` next to the inputs.

    python3 npu_e2e_report.py <report_dir>

If ``openai-whisper`` or an expected TTS WAV is unavailable, the report still
aggregates but the production intelligibility gate fails closed. No device access —
pure post-processing.
"""
import hashlib
from importlib import metadata
import json
import re
import subprocess
import sys
import wave
from pathlib import Path

_WORD = re.compile(r"[^\W_]+(?:'[^\W_]+)*", re.UNICODE)
_ASR_ALIASES = {"mr": "mister", "neuro": "neural"}
_DIGIT_WORDS = {
    "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four",
    "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine",
}
APP_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = APP_ROOT.parents[2]
SUITES = APP_ROOT / "app" / "src" / "androidTest" / "assets" / "npu_suites"
FIXTURES = SUITES.parent / "qhexrt_fixtures"
WHISPER_PACKAGE = "openai-whisper"
WHISPER_PACKAGE_VERSION = "20250625"
WHISPER_MODEL = "base"
WHISPER_CHECKPOINT_SHA256 = "ed3a0b6b1c0edf879ad9b11b1af5a0e6ab5db9205f891f668f8b0e6c6326e34e"

GATE_SPECS = {
    "answer_keyword_coherence": {
        "required": {"metric", "suite_pass_frac", "min_inputs", "min_decode_toks"},
        "optional": {"max_new"},
    },
    "wer": {
        "required": {"metric", "suite_pass_frac", "min_inputs", "wer_max"},
        "optional": set(),
    },
    "keyword": {
        "required": {"metric", "suite_pass_frac", "min_inputs"},
        "optional": {"max_new"},
    },
    "audio_sanity_intelligibility": {
        "required": {
            "metric", "suite_pass_frac", "min_inputs", "expected_sample_rate",
            "intelligibility_wer_max", "rms_min", "min_seconds",
        },
        "optional": set(),
    },
    "embedding_retrieval_ranking": {
        "required": {
            "metric", "suite_pass_frac", "min_inputs", "min_triples",
            "expected_dimension", "minimum_pairwise_margin", "l2_norm_min",
            "l2_norm_max", "query_prefix", "document_prefix",
        },
        "optional": set(),
    },
    "inpaint_forge_parity+passthrough_detection": {
        "required": {
            "metric", "suite_pass_frac", "min_inputs", "minimum_full_cosine",
            "minimum_hole_cosine", "maximum_hole_relative_l2",
            "minimum_full_psnr_db", "minimum_hole_psnr_db", "minimum_seam_psnr_db",
            "maximum_unmasked_mean_absolute_error_rgb8",
            "maximum_unmasked_p99_absolute_error_rgb8",
            "minimum_unmasked_rgb8_within_one_lsb_fraction",
            "minimum_hole_changed_fraction",
        },
        "optional": set(),
    },
    "inpaint_execution_smoke": {
        "required": {
            "metric", "suite_pass_frac", "min_inputs",
            "maximum_unmasked_mean_absolute_error_rgb8", "minimum_hole_changed_fraction",
        },
        "optional": set(),
    },
}


def _words(s):
    out = []
    for w in _WORD.findall(s.lower()):
        w = _ASR_ALIASES.get(w, w)
        if w.isdigit():
            out.extend(_DIGIT_WORDS[ch] for ch in w)
        else:
            out.append(w)
    return out


def wer(ref, hyp):
    r, h = _words(ref), _words(hyp)
    if not r:
        return 0.0 if not h else 1.0
    # word-level Levenshtein / |ref|
    prev = list(range(len(h) + 1))
    for i in range(1, len(r) + 1):
        cur = [i] + [0] * len(h)
        for j in range(1, len(h) + 1):
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r[i - 1] != h[j - 1]))
        prev = cur
    return prev[len(h)] / len(r)


def _sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _suite_case_assets(case):
    nested = case.get("input", {}) if isinstance(case.get("input"), dict) else {}
    names = [
        nested.get("wav_asset"), nested.get("image_asset"), nested.get("mask_asset"),
        case.get("metric_image_asset"), case.get("metric_mask_asset"),
        case.get("reference_image_asset"),
    ]
    return [name for name in names if isinstance(name, str) and name]


def _executable_suite_cases(metric, cases):
    def nested(case):
        return case.get("input", {}) if isinstance(case.get("input"), dict) else {}

    if metric == "answer_keyword_coherence":
        return [case for case in cases if nested(case).get("text") and case.get("expect_keywords")]
    if metric == "wer":
        return [case for case in cases if nested(case).get("wav_asset") and case.get("gold_text")]
    if metric == "keyword":
        return [case for case in cases if nested(case).get("image_asset") and case.get("expect_keywords")]
    if metric == "audio_sanity_intelligibility":
        return [case for case in cases if nested(case).get("text")]
    if metric == "embedding_retrieval_ranking":
        return [case for case in cases if all(nested(case).get(key) for key in ("query", "positive", "negative"))]
    if metric == "inpaint_forge_parity+passthrough_detection":
        return [case for case in cases if nested(case).get("image_asset") and nested(case).get("mask_asset")
                and case.get("reference_image_asset")]
    if metric == "inpaint_execution_smoke":
        return [case for case in cases if nested(case).get("image_asset") and nested(case).get("mask_asset")]
    return []


def _validate_suite_payload(payload, path):
    errors = []
    gate = payload.get("gate") if isinstance(payload.get("gate"), dict) else {}
    cases = payload.get("cases") if isinstance(payload.get("cases"), list) else []
    metric = gate.get("metric")
    spec = GATE_SPECS.get(metric)
    modality_matches = {
        "answer_keyword_coherence": {"llm", "vlm_text"},
        "wer": {"asr", "asr_aed"},
        "keyword": {"vlm", "vlm_image"},
        "audio_sanity_intelligibility": {"tts"},
        "embedding_retrieval_ranking": {"embedding"},
        "inpaint_forge_parity+passthrough_detection": {"inpaint"},
        "inpaint_execution_smoke": {"inpaint"},
    }
    if payload.get("schema") != "npu_suite/v1":
        errors.append("schema must be npu_suite/v1")
    if payload.get("model_id") != path.stem:
        errors.append("model_id must equal the suite filename")
    model_arch = re.search(r"_(v[0-9]+)$", str(payload.get("model_id") or ""))
    if model_arch is None or payload.get("arch") != model_arch.group(1):
        errors.append("model_id architecture suffix must exactly equal arch")
    if not re.fullmatch(r"[0-9a-f]{40}", str(payload.get("hf_revision") or "")):
        errors.append("hf_revision must be an immutable 40-hex commit")
    coverage = payload.get("coverage") if isinstance(payload.get("coverage"), dict) else {}
    if coverage.get("scope") not in {"acceptance", "smoke_only"}:
        errors.append("coverage.scope must be acceptance or smoke_only")
    if metric == "inpaint_execution_smoke" and coverage.get("scope") != "smoke_only":
        errors.append("inpaint_execution_smoke can never claim acceptance")
    published = payload.get("published_bundle") if isinstance(payload.get("published_bundle"), dict) else None
    if published is not None:
        if published.get("revision") != payload.get("hf_revision"):
            errors.append("published_bundle revision must equal hf_revision")
        artifacts = published.get("artifact_sha256s")
        if not isinstance(artifacts, dict) or not artifacts or any(
            not isinstance(name, str) or not name or
            not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest)
            for name, digest in (artifacts.items() if isinstance(artifacts, dict) else [])
        ):
            errors.append("published_bundle artifact hashes are invalid")
    if not cases:
        errors.append("cases must be non-empty")
    if spec is None:
        errors.append(f"unsupported metric {metric!r}")
    else:
        if payload.get("modality") not in modality_matches[metric]:
            errors.append(f"modality={payload.get('modality')!r} is incompatible with metric={metric!r}")
        declared = set(gate)
        missing = spec["required"] - declared
        unknown = declared - spec["required"] - spec["optional"]
        if missing:
            errors.append(f"missing gate keys: {sorted(missing)}")
        if unknown:
            errors.append(f"unknown/unapplied gate keys: {sorted(unknown)}")
    ids = [case.get("id") for case in cases if isinstance(case, dict)]
    if len(ids) != len(cases) or any(not isinstance(case_id, str) or not case_id for case_id in ids):
        errors.append("every case needs a non-empty string id")
    elif len(ids) != len(set(ids)):
        errors.append("case ids must be unique")
    executable = _executable_suite_cases(metric, cases)
    if len(executable) != len(cases):
        errors.append(f"only {len(executable)}/{len(cases)} cases are executable for metric={metric}")
    try:
        minimum = int(gate.get("min_inputs"))
        if minimum <= 0:
            errors.append("min_inputs must be positive")
        if metric == "embedding_retrieval_ranking":
            distinct_inputs = {
                value
                for case in executable
                for value in (
                    case["input"]["query"], case["input"]["positive"], case["input"]["negative"],
                )
            }
            if len(distinct_inputs) < minimum:
                errors.append(f"{len(distinct_inputs)} distinct inputs < min_inputs={minimum}")
            if len(executable) < int(gate.get("min_triples")):
                errors.append(f"{len(executable)} triples < min_triples={gate.get('min_triples')}")
        elif len(executable) < minimum:
            errors.append(f"{len(executable)} executable cases < min_inputs={minimum}")
    except (TypeError, ValueError, KeyError):
        errors.append("min_inputs/min_triples must be valid integers")
    try:
        pass_frac = float(gate.get("suite_pass_frac"))
        if not 0.0 < pass_frac <= 1.0:
            errors.append("suite_pass_frac must be in (0, 1]")
    except (TypeError, ValueError):
        errors.append("suite_pass_frac must be numeric")
    try:
        if metric == "answer_keyword_coherence":
            if float(gate["min_decode_toks"]) < 0 or int(gate.get("max_new", 0)) < 0:
                errors.append("LLM decode/max_new thresholds must be non-negative")
        elif metric == "wer":
            if not 0.0 <= float(gate["wer_max"]) <= 1.0:
                errors.append("wer_max must be in [0, 1]")
        elif metric == "keyword" and int(gate.get("max_new", 0)) < 0:
            errors.append("max_new must be non-negative")
        elif metric == "audio_sanity_intelligibility":
            if int(gate["expected_sample_rate"]) <= 0:
                errors.append("expected_sample_rate must be positive")
            if not 0.0 <= float(gate["intelligibility_wer_max"]) <= 1.0:
                errors.append("intelligibility_wer_max must be in [0, 1]")
            if float(gate["rms_min"]) < 0 or float(gate["min_seconds"]) <= 0:
                errors.append("TTS RMS/duration thresholds are invalid")
        elif metric == "embedding_retrieval_ranking":
            if int(gate["expected_dimension"]) <= 0 or int(gate["min_triples"]) <= 0:
                errors.append("embedding dimension/min_triples must be positive")
            if float(gate["l2_norm_min"]) > float(gate["l2_norm_max"]):
                errors.append("l2_norm_min must not exceed l2_norm_max")
            if not gate["query_prefix"] or not gate["document_prefix"]:
                errors.append("embedding prefixes must be non-empty")
        elif metric == "inpaint_forge_parity+passthrough_detection":
            for key in GATE_SPECS[metric]["required"] - {"metric", "min_inputs"}:
                float(gate[key])
        elif metric == "inpaint_execution_smoke":
            if float(gate["maximum_unmasked_mean_absolute_error_rgb8"]) < 0:
                errors.append("inpaint smoke unmasked MAE ceiling must be non-negative")
            changed = float(gate["minimum_hole_changed_fraction"])
            if not 0.0 < changed <= 1.0:
                errors.append("inpaint smoke changed-hole threshold must be in (0, 1]")
    except (TypeError, ValueError, KeyError) as exc:
        errors.append(f"invalid threshold value: {exc}")
    for case in executable:
        for name in _suite_case_assets(case):
            asset = FIXTURES / name
            if not asset.is_file():
                errors.append(f"missing suite asset: {name}")
    bindings = payload.get("asset_bindings") if isinstance(payload.get("asset_bindings"), list) else []
    if bindings:
        binding_by_id = {
            binding.get("id"): binding for binding in bindings if isinstance(binding, dict) and binding.get("id")
        }
        if set(binding_by_id) != set(ids):
            errors.append("asset_bindings ids must exactly match case ids")
        digest_fields = {
            "source_image_sha256": lambda case: case.get("input", {}).get("image_asset"),
            "source_mask_sha256": lambda case: case.get("input", {}).get("mask_asset"),
        }
        if metric != "inpaint_execution_smoke":
            digest_fields.update({
                "metric_image_sha256": lambda case: case.get("metric_image_asset"),
                "metric_mask_sha256": lambda case: case.get("metric_mask_asset"),
                "reference_rgb8_sha256": lambda case: case.get("reference_image_asset"),
            })
        for case in executable:
            binding = binding_by_id.get(case.get("id"), {})
            for digest_key, asset_name in digest_fields.items():
                name = asset_name(case)
                expected = binding.get(digest_key)
                asset = FIXTURES / name if name else None
                if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
                    errors.append(f"invalid {digest_key} for case {case.get('id')}")
                elif asset is None or not asset.is_file() or _sha256(asset) != expected:
                    errors.append(f"asset digest mismatch: {name}")
    return errors, executable


def _suite_gate(mid, arch=None):
    candidates = [SUITES / f"{mid}.json"]
    if arch and not mid.endswith(f"_{arch}"):
        candidates.append(SUITES / f"{mid}_{arch}.json")
    path = next((candidate for candidate in candidates if candidate.exists()), None)
    if path is None:
        return {
            "suite_id": None,
            "suite_sha256": None,
            "suite_valid": False,
            "suite_schema": None,
            "suite_model_id": None,
            "suite_cases": 0,
            "suite_metric": None,
            "coverage_scope": None,
            "coverage_reason": None,
            "hf_revision": None,
            "published_revision": None,
            "input_asset_sha256s": {},
            "gate": {},
            "cases": [],
            "executable_cases": [],
            "validation_errors": ["suite file is missing"],
        }
    raw = path.read_bytes()
    try:
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            raise ValueError("suite root must be an object")
        gate = payload.get("gate", {}) if isinstance(payload.get("gate"), dict) else {}
        cases = payload.get("cases", []) if isinstance(payload.get("cases"), list) else []
        validation_errors, executable = _validate_suite_payload(payload, path)
        if arch is not None and payload.get("arch") != arch:
            validation_errors.append(
                f"suite arch={payload.get('arch')!r} does not match requested arch={arch!r}"
            )
        suite_valid = not validation_errors
    except Exception as exc:  # noqa: BLE001
        payload = {}
        gate = {}
        cases = []
        executable = []
        validation_errors = [f"{type(exc).__name__}: {exc}"]
        suite_valid = False
    input_asset_sha256s = {}
    for case in executable:
        for name in _suite_case_assets(case):
            asset = FIXTURES / name
            if asset.is_file():
                input_asset_sha256s[name] = _sha256(asset)
    return {
        "suite_id": path.stem,
        "suite_sha256": hashlib.sha256(raw).hexdigest(),
        "suite_valid": suite_valid,
        "suite_schema": payload.get("schema"),
        "suite_model_id": payload.get("model_id"),
        "suite_cases": len(payload.get("cases", [])) if isinstance(payload.get("cases"), list) else 0,
        "suite_metric": gate.get("metric") if isinstance(gate, dict) else None,
        "coverage_scope": (payload.get("coverage") or {}).get("scope")
            if isinstance(payload.get("coverage"), dict) else None,
        "coverage_reason": (payload.get("coverage") or {}).get("reason")
            if isinstance(payload.get("coverage"), dict) else None,
        "hf_revision": payload.get("hf_revision"),
        "published_revision": (payload.get("published_bundle") or {}).get("revision")
            if isinstance(payload.get("published_bundle"), dict) else None,
        "input_asset_sha256s": dict(sorted(input_asset_sha256s.items())),
        "gate": gate,
        "cases": cases,
        "executable_cases": executable,
        "validation_errors": validation_errors,
    }


def _load_run_inputs(report_dir):
    path = report_dir / "run_inputs.json"
    if not path.is_file():
        return {}, None
    try:
        payload = json.loads(path.read_text())
        if not isinstance(payload, dict):
            raise ValueError("run inputs root must be an object")
        return payload, _sha256(path)
    except Exception as exc:  # noqa: BLE001
        return {"error": f"{type(exc).__name__}: {exc}"}, _sha256(path)


def _local_git_state():
    try:
        revision = subprocess.run(
            ["git", "-C", str(REPO_ROOT), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True,
        ).stdout.strip()
        dirty = bool(subprocess.run(
            ["git", "-C", str(REPO_ROOT), "status", "--porcelain", "--untracked-files=all"],
            check=True, capture_output=True, text=True,
        ).stdout.strip())
        return {"revision": revision, "dirty": dirty}
    except Exception as exc:  # noqa: BLE001
        return {"revision": None, "dirty": None, "error": f"{type(exc).__name__}: {exc}"}


def _fail_report(report, reason):
    report["status"] = "FAIL"
    detail = str(report.get("detail") or "").strip()
    if reason not in detail:
        report["detail"] = reason if not detail or detail == "ok" else f"{detail}; {reason}"


def _report_inputs(report_path, report_dir, model_id, run_inputs_sha256):
    inputs = [{"role": "device_report", "name": report_path.name, "sha256": _sha256(report_path)}]
    if run_inputs_sha256:
        inputs.append({"role": "run_inputs", "name": "run_inputs.json", "sha256": run_inputs_sha256})
    for wav in sorted(report_dir.glob(f"tts_{model_id}_*.wav")):
        inputs.append({"role": "tts_wav", "name": wav.name, "sha256": _sha256(wav)})
    for image in sorted(report_dir.glob(f"inpaint_{model_id}_*.png")):
        inputs.append({"role": "inpaint_output", "name": image.name, "sha256": _sha256(image)})
    return inputs


def _apply_production_provenance(report, report_path, report_dir, run_inputs, run_inputs_sha256, local_git):
    mid = report.get("model_id", report_path.stem)
    suite = _suite_gate(mid, report.get("arch"))
    descriptor = str(report.get("suite") or "")
    suite_matches = (
        descriptor.startswith("npu_suite/v1:")
        and suite["suite_valid"]
        and report.get("suite_id") == suite["suite_id"]
        and report.get("suite_sha256") == suite["suite_sha256"]
    )
    report["suite_provenance"] = {
        "reported_id": report.get("suite_id"),
        "reported_sha256": report.get("suite_sha256"),
        "local_id": suite["suite_id"],
        "local_sha256": suite["suite_sha256"],
        "schema": suite["suite_schema"],
        "model_id": suite["suite_model_id"],
        "case_count": suite["suite_cases"],
        "metric": suite["suite_metric"],
        "coverage_scope": suite["coverage_scope"],
        "coverage_reason": suite["coverage_reason"],
        "hf_revision": suite["hf_revision"],
        "published_revision": suite["published_revision"],
        "input_asset_sha256s": suite["input_asset_sha256s"],
        "validation_errors": suite["validation_errors"],
        "declared_gate_keys": sorted(suite["gate"]),
        "exact_match": suite_matches,
    }
    gates = report.setdefault("gates", {})
    gates["canonical_suite"] = suite_matches
    if not suite_matches:
        if not report.get("suite_id") or not report.get("suite_sha256"):
            state = "receipt is missing from the device report"
        elif not suite["suite_valid"]:
            state = "is missing or invalid in the local canonical assets"
        else:
            state = "does not match the test-APK receipt"
        _fail_report(report, f"canonical suite {state} for model_id={mid!r}, arch={report.get('arch')!r}")

    immutable_bundle = report.get("bundle_revision_verified") is True
    expected_acceptance = suite["coverage_scope"] == "acceptance" and immutable_bundle
    scope_receipt_ok = (
        report.get("hf_revision") == suite["hf_revision"]
        and report.get("declared_validation_scope") == suite["coverage_scope"]
        and report.get("validation_scope") == ("acceptance" if expected_acceptance else "smoke_only")
        and report.get("acceptance_eligible") is expected_acceptance
    )
    gates["suite_scope_receipt"] = scope_receipt_ok
    reported_assets = report.get("input_asset_sha256s")
    fixture_receipt_ok = (
        isinstance(reported_assets, dict)
        and reported_assets == suite["input_asset_sha256s"]
    )
    gates["suite_fixture_receipt"] = fixture_receipt_ok
    report["suite_provenance"].update({
        "bundle_revision_verified": immutable_bundle,
        "expected_acceptance_eligible": expected_acceptance,
        "scope_receipt_exact": scope_receipt_ok,
        "fixture_receipt_exact": fixture_receipt_ok,
    })
    if not scope_receipt_ok:
        _fail_report(report, "suite coverage/revision evidence is missing or inconsistent")
    elif not fixture_receipt_ok:
        _fail_report(report, "suite input fixture SHA-256 receipt is missing or inconsistent")
    elif not expected_acceptance and report.get("status") == "PASS":
        report["status"] = "SMOKE_PASS"
        report["detail"] = "mutable or smoke-scoped evidence; acceptance was not claimed"

    deletion = report.get("delete") if isinstance(report.get("delete"), dict) else {}
    delete_not_applicable = (
        report.get("status") == "FAIL"
        and deletion.get("applicable") is False
        and deletion.get("requested") is False
        and deletion.get("reason") == "registration_not_persisted"
    )
    if delete_not_applicable:
        # Registration failed before a registry entry existed, so there is
        # nothing for deleteModel() to clean up. Preserve the primary failure
        # without manufacturing a second lifecycle failure or gate.
        gates.pop("delete_model", None)
    else:
        deleted_ids = deletion.get("deleted_model_ids") if isinstance(deletion.get("deleted_model_ids"), list) else []
        delete_ok = (
            deletion.get("requested") is True
            and deletion.get("success") is True
            and mid in deleted_ids
            and deletion.get("failed_model_ids") == []
            and deletion.get("skipped_model_ids") == []
            and deletion.get("files_deleted") is True
            and deletion.get("registry_updated") is True
            and deletion.get("dry_run") is False
        )
        gates["delete_model"] = delete_ok
        if not delete_ok:
            _fail_report(report, "model deletion was not fully confirmed by the SDK lifecycle result")

    reported_git = report.get("sdk_source") if isinstance(report.get("sdk_source"), dict) else {}
    runner_git = run_inputs.get("sdk_git") if isinstance(run_inputs.get("sdk_git"), dict) else {}
    reported_revision = reported_git.get("git_revision")
    runner_revision = runner_git.get("revision")
    report["report_inputs"] = _report_inputs(report_path, report_dir, mid, run_inputs_sha256)
    artifacts = run_inputs.get("artifacts") if isinstance(run_inputs.get("artifacts"), list) else []
    artifact_paths = {item.get("path") for item in artifacts if isinstance(item, dict)}
    installed_packages = (
        run_inputs.get("installed_packages")
        if isinstance(run_inputs.get("installed_packages"), list)
        else []
    )
    installed_match = (
        len(installed_packages) == 2
        and all(
            isinstance(item, dict) and bool(item.get("sha256")) and item.get("matches_local") is True
            for item in installed_packages
        )
    )
    source_ok = (
        run_inputs.get("schema") == "npu_e2e_inputs/v1"
        and bool(run_inputs_sha256)
        and bool(reported_revision)
        and reported_revision == runner_revision
        and {"scripts/run_npu_e2e.sh", "scripts/npu_e2e_report.py"}.issubset(artifact_paths)
        and installed_match
    )
    gates["source_provenance"] = source_ok
    if not source_ok:
        _fail_report(report, "SDK source revision or sanitized run-input provenance is missing or inconsistent")
    report["provenance"] = {
        "sdk_git": {
            "reported_revision": reported_revision,
            "reported_dirty": reported_git.get("git_dirty"),
            "runner_revision": runner_revision,
            "runner_dirty": runner_git.get("dirty"),
            "aggregator_revision": local_git.get("revision"),
            "aggregator_dirty": local_git.get("dirty"),
            "reported_matches_runner": bool(reported_revision and runner_revision and reported_revision == runner_revision),
        },
        "installed_packages": installed_packages,
        "run_inputs_sha256": run_inputs_sha256,
        "source_complete": source_ok,
        "aggregator_sha256": _sha256(Path(__file__)),
    }
    return suite


def _word_repeat_ratio(value):
    words = _words(value)
    if len(words) < 2:
        return 0.0
    return sum(words[index] == words[index - 1] for index in range(1, len(words))) / (len(words) - 1)


def _answer_text(value):
    return re.sub(
        r"<think\b[^>]*>.*?(?:</think\s*>|\Z)",
        " ",
        str(value),
        flags=re.IGNORECASE | re.DOTALL,
    ).strip()


def _contains_keyword(text, keyword):
    haystack, needle = _words(text), _words(str(keyword))
    return bool(needle) and any(
        haystack[index:index + len(needle)] == needle
        for index in range(len(haystack) - len(needle) + 1)
    )


def _apply_canonical_thresholds(report, suite):
    """Recompute every declared Android gate from raw report samples; missing coverage fails closed."""
    gate = suite.get("gate", {})
    cases = suite.get("executable_cases", [])
    samples = report.get("samples") if isinstance(report.get("samples"), list) else []
    metric = gate.get("metric")
    declared = set(gate)
    applied = set()
    failures = []
    checks = []
    case_results = []

    def number(value, label):
        if isinstance(value, bool):
            raise ValueError(f"{label} is boolean")
        parsed = float(value)
        if parsed != parsed or parsed in (float("inf"), float("-inf")):
            raise ValueError(f"{label} is not finite")
        return parsed

    def check(keys, passed, detail):
        keys = {keys} if isinstance(keys, str) else set(keys)
        applied.update(key for key in keys if key in declared)
        checks.append({"gate_keys": sorted(keys), "pass": bool(passed), "detail": detail})
        if not passed:
            failures.append(detail)

    if not suite.get("suite_valid"):
        failures.extend(suite.get("validation_errors") or ["canonical suite is invalid"])
    spec = GATE_SPECS.get(metric)
    if spec is None:
        failures.append(f"unsupported canonical metric {metric!r}")
    else:
        missing = spec["required"] - declared
        unknown = declared - spec["required"] - spec["optional"]
        if missing:
            failures.append(f"missing declared gate keys {sorted(missing)}")
        if unknown:
            failures.append(f"unknown declared gate keys {sorted(unknown)}")

    expected_modality = {
        "answer_keyword_coherence": "llm",
        "wer": "stt",
        "keyword": "vlm",
        "audio_sanity_intelligibility": "tts",
        "embedding_retrieval_ranking": "embedding",
        "inpaint_forge_parity+passthrough_detection": "inpaint",
        "inpaint_execution_smoke": "inpaint",
    }.get(metric)
    check("metric", report.get("modality") == expected_modality,
          f"metric={metric!r} is incompatible with report modality={report.get('modality')!r}")

    expected_ids = [case.get("id") for case in cases]
    reported_ids = report.get("executed_case_ids") if isinstance(report.get("executed_case_ids"), list) else []
    sample_ids = [sample.get("id") for sample in samples if isinstance(sample, dict)]
    exact_execution = (
        len(samples) == len(cases)
        and len(sample_ids) == len(samples)
        and len(set(sample_ids)) == len(sample_ids)
        and sample_ids == expected_ids
        and reported_ids == expected_ids
        and report.get("executed_case_count") == len(cases)
    )
    if not exact_execution:
        failures.append(
            f"executed cases do not exactly match canonical order: expected={expected_ids}, "
            f"reported={reported_ids}, samples={sample_ids}"
        )

    try:
        minimum_inputs = int(gate.get("min_inputs"))
        if metric == "embedding_retrieval_ranking":
            coverage = len({
                value
                for case in cases
                for value in (
                    case["input"]["query"], case["input"]["positive"], case["input"]["negative"],
                )
            })
        else:
            coverage = len(cases)
        check("min_inputs", coverage >= minimum_inputs,
              f"canonical input coverage {coverage} < min_inputs={minimum_inputs}")
    except (TypeError, ValueError, KeyError) as exc:
        check("min_inputs", False, f"invalid min_inputs coverage: {exc}")

    by_id = {case.get("id"): case for case in cases}
    sample_by_id = {sample.get("id"): sample for sample in samples if isinstance(sample, dict)}
    ordered = [(by_id[case_id], sample_by_id.get(case_id, {})) for case_id in expected_ids]

    try:
        if metric == "answer_keyword_coherence":
            decode_floor = number(gate.get("min_decode_toks"), "min_decode_toks")
            case_passes = []
            decode_passes = []
            budget_passes = []
            for case, sample in ordered:
                output = str(sample.get("output") or "")
                visible_answer = _answer_text(output)
                keywords = case.get("expect_keywords") or []
                keyword_ok = bool(visible_answer) and any(
                    _contains_keyword(visible_answer, keyword) for keyword in keywords
                )
                coherent = bool(output.strip()) and _word_repeat_ratio(output) < 0.50
                passed = keyword_ok and coherent
                case_passes.append(passed)
                try:
                    decode_passes.append(number(sample.get("decode_toks"), "sample decode_toks") >= decode_floor)
                except (TypeError, ValueError):
                    decode_passes.append(False)
                if "max_new" in gate:
                    try:
                        budget_passes.append(int(sample.get("max_new")) >= int(gate["max_new"]))
                    except (TypeError, ValueError):
                        budget_passes.append(False)
                case_results.append({"id": case.get("id"), "pass": passed,
                                     "keyword_match": keyword_ok, "coherent": coherent})
            check("min_decode_toks", bool(decode_passes) and all(decode_passes),
                  f"one or more LLM cases are below min_decode_toks={decode_floor}")
            if "max_new" in gate:
                check("max_new", bool(budget_passes) and all(budget_passes),
                      f"one or more LLM cases used less than max_new={gate['max_new']}")

        elif metric == "wer":
            ceiling = number(gate.get("wer_max"), "wer_max")
            case_passes = []
            for case, sample in ordered:
                score = wer(case.get("gold_text", ""), str(sample.get("output") or ""))
                passed = score <= ceiling
                case_passes.append(passed)
                case_results.append({"id": case.get("id"), "pass": passed, "wer": round(score, 6)})
            check("wer_max", bool(case_passes), f"WER cases were not evaluable against wer_max={ceiling}")

        elif metric == "keyword":
            case_passes = []
            budget_passes = []
            for case, sample in ordered:
                output = str(sample.get("output") or "")
                visible_answer = _answer_text(output)
                keywords = case.get("expect_keywords") or []
                passed = bool(visible_answer) and any(
                    _contains_keyword(visible_answer, keyword) for keyword in keywords
                )
                case_passes.append(passed)
                if "max_new" in gate:
                    try:
                        budget_passes.append(int(sample.get("max_new")) >= int(gate["max_new"]))
                    except (TypeError, ValueError):
                        budget_passes.append(False)
                case_results.append({"id": case.get("id"), "pass": passed})
            if "max_new" in gate:
                check("max_new", bool(budget_passes) and all(budget_passes),
                      f"one or more VLM cases used less than max_new={gate['max_new']}")

        elif metric == "audio_sanity_intelligibility":
            expected_rate = int(gate.get("expected_sample_rate"))
            rms_floor = number(gate.get("rms_min"), "rms_min")
            seconds_floor = number(gate.get("min_seconds"), "min_seconds")
            wer_ceiling = number(gate.get("intelligibility_wer_max"), "intelligibility_wer_max")
            rate_checks, rms_checks, duration_checks, intelligibility_checks, wers = [], [], [], [], []
            case_passes = []
            for case, sample in ordered:
                try:
                    rate_ok = int(sample.get("sample_rate")) == expected_rate
                    rms_ok = number(sample.get("rms"), "sample rms") >= rms_floor
                    duration_ok = number(sample.get("audio_s"), "sample audio_s") >= seconds_floor
                except (TypeError, ValueError):
                    rate_ok = rms_ok = duration_ok = False
                rate_checks.append(rate_ok); rms_checks.append(rms_ok); duration_checks.append(duration_ok)
                try:
                    intelligibility = number(sample.get("intelligibility_wer"), "intelligibility_wer")
                    wers.append(intelligibility)
                    intelligibility_ok = intelligibility <= wer_ceiling
                except (TypeError, ValueError):
                    intelligibility = None
                    intelligibility_ok = False
                intelligibility_checks.append(intelligibility_ok)
                passed = rate_ok and rms_ok and duration_ok and intelligibility_ok
                case_passes.append(passed)
                case_results.append({"id": case.get("id"), "pass": passed,
                                     "intelligibility_wer": intelligibility})
            check("expected_sample_rate", bool(rate_checks) and all(rate_checks),
                  f"one or more TTS WAVs do not use expected_sample_rate={expected_rate}")
            check("rms_min", bool(rms_checks) and all(rms_checks),
                  f"one or more TTS WAVs are below rms_min={rms_floor}")
            check("min_seconds", bool(duration_checks) and all(duration_checks),
                  f"one or more TTS WAVs are below min_seconds={seconds_floor}")
            mean_wer = sum(wers) / len(wers) if len(wers) == len(cases) and wers else None
            check(
                "intelligibility_wer_max",
                mean_wer is not None and mean_wer <= wer_ceiling and all(intelligibility_checks),
                f"TTS intelligibility WER exceeds {wer_ceiling} per-case or mean={mean_wer} is incomplete",
            )
            report["intelligibility_wer"] = round(mean_wer, 6) if mean_wer is not None else None

        elif metric == "embedding_retrieval_ranking":
            expected_dimension = int(gate.get("expected_dimension"))
            min_margin = number(gate.get("minimum_pairwise_margin"), "minimum_pairwise_margin")
            norm_min = number(gate.get("l2_norm_min"), "l2_norm_min")
            norm_max = number(gate.get("l2_norm_max"), "l2_norm_max")
            query_prefix = str(gate.get("query_prefix"))
            document_prefix = str(gate.get("document_prefix"))
            triples_min = int(gate.get("min_triples"))
            dimension_checks, margin_checks, norm_checks = [], [], []
            prefix_checks = []
            case_passes = []
            for case, sample in ordered:
                try:
                    dimension_ok = int(sample.get("dim")) == expected_dimension
                    margin_ok = number(sample.get("margin"), "margin") >= min_margin
                    norm_ok = all(
                        norm_min <= number(sample.get(key), key) <= norm_max
                        for key in ("query_l2", "positive_l2", "negative_l2")
                    )
                except (TypeError, ValueError):
                    dimension_ok = margin_ok = norm_ok = False
                inputs = case.get("input", {})
                prefix_ok = (
                    str(inputs.get("query", "")).startswith(query_prefix)
                    and str(inputs.get("positive", "")).startswith(document_prefix)
                    and str(inputs.get("negative", "")).startswith(document_prefix)
                )
                passed = dimension_ok and margin_ok and norm_ok and prefix_ok
                dimension_checks.append(dimension_ok); margin_checks.append(margin_ok)
                norm_checks.append(norm_ok); prefix_checks.append(prefix_ok); case_passes.append(passed)
                case_results.append({"id": case.get("id"), "pass": passed})
            check("min_triples", len(cases) >= triples_min,
                  f"embedding triples {len(cases)} < min_triples={triples_min}")
            check("expected_dimension", bool(dimension_checks) and all(dimension_checks),
                  f"one or more embeddings are not dimension {expected_dimension}")
            check("minimum_pairwise_margin", bool(margin_checks) and all(margin_checks),
                  f"one or more retrieval margins are below {min_margin}")
            check({"l2_norm_min", "l2_norm_max"}, bool(norm_checks) and all(norm_checks),
                  f"one or more embedding norms are outside [{norm_min}, {norm_max}]")
            check({"query_prefix", "document_prefix"}, bool(prefix_checks) and all(prefix_checks),
                  "embedding task prefixes do not exactly match the canonical contract")

        elif metric == "inpaint_forge_parity+passthrough_detection":
            thresholds = {
                "minimum_full_cosine": ("full_cosine", lambda value, bar: value >= bar),
                "minimum_hole_cosine": ("hole_cosine", lambda value, bar: value >= bar),
                "maximum_hole_relative_l2": ("hole_relative_l2", lambda value, bar: value <= bar),
                "minimum_full_psnr_db": ("full_psnr_db", lambda value, bar: value >= bar),
                "minimum_hole_psnr_db": ("hole_psnr_db", lambda value, bar: value >= bar),
                "minimum_seam_psnr_db": ("seam_psnr_db", lambda value, bar: value >= bar),
                "maximum_unmasked_mean_absolute_error_rgb8": ("unmasked_mae_rgb8", lambda value, bar: value <= bar),
                "maximum_unmasked_p99_absolute_error_rgb8": ("unmasked_p99_rgb8", lambda value, bar: value <= bar),
                "minimum_unmasked_rgb8_within_one_lsb_fraction": ("unmasked_within_one_lsb", lambda value, bar: value >= bar),
                "minimum_hole_changed_fraction": ("hole_changed_fraction", lambda value, bar: value >= bar),
            }
            threshold_results = {key: [] for key in thresholds}
            case_passes = []
            for case, sample in ordered:
                passed = True
                for key, (sample_key, comparator) in thresholds.items():
                    try:
                        ok = comparator(number(sample.get(sample_key), sample_key), number(gate.get(key), key))
                    except (TypeError, ValueError):
                        ok = False
                    threshold_results[key].append(ok)
                    passed = passed and ok
                case_passes.append(passed)
                case_results.append({"id": case.get("id"), "pass": passed})
            for key, results in threshold_results.items():
                check(key, bool(results) and all(results), f"inpaint samples failed {key}")

        elif metric == "inpaint_execution_smoke":
            thresholds = {
                "maximum_unmasked_mean_absolute_error_rgb8": (
                    "unmasked_mae_rgb8", lambda value, bar: value <= bar,
                ),
                "minimum_hole_changed_fraction": (
                    "hole_changed_fraction", lambda value, bar: value >= bar,
                ),
            }
            threshold_results = {key: [] for key in thresholds}
            case_passes = []
            for case, sample in ordered:
                passed = True
                for key, (sample_key, comparator) in thresholds.items():
                    try:
                        ok = comparator(number(sample.get(sample_key), sample_key), number(gate.get(key), key))
                    except (TypeError, ValueError):
                        ok = False
                    threshold_results[key].append(ok)
                    passed = passed and ok
                case_passes.append(passed)
                case_results.append({"id": case.get("id"), "pass": passed})
            for key, results in threshold_results.items():
                check(key, bool(results) and all(results), f"inpaint smoke samples failed {key}")

        else:
            case_passes = []
    except (TypeError, ValueError, KeyError) as exc:
        failures.append(f"canonical gate evaluation error: {type(exc).__name__}: {exc}")
        case_passes = []

    try:
        pass_fraction = sum(bool(value) for value in case_passes) / len(case_passes)
        required_fraction = number(gate.get("suite_pass_frac"), "suite_pass_frac")
        check("suite_pass_frac", pass_fraction >= required_fraction,
              f"canonical case pass fraction {pass_fraction:.6f} < suite_pass_frac={required_fraction}")
    except (TypeError, ValueError, ZeroDivisionError) as exc:
        pass_fraction = 0.0
        check("suite_pass_frac", False, f"could not evaluate suite_pass_frac: {exc}")

    unapplied = declared - applied
    if unapplied:
        failures.append(f"declared gate keys were not applied: {sorted(unapplied)}")
    ok = exact_execution and not failures and not unapplied
    report["declared_gate_keys"] = sorted(declared)
    report["applied_gate_keys"] = sorted(applied)
    report["unapplied_gate_keys"] = sorted(unapplied)
    report["canonical_gate_evaluation"] = {
        "metric": metric,
        "pass_fraction": round(pass_fraction, 6),
        "case_results": case_results,
        "checks": checks,
        "pass": ok,
    }
    report.setdefault("gates", {})["canonical_thresholds"] = ok
    if not ok:
        _fail_report(report, "canonical threshold evaluation failed: " + "; ".join(dict.fromkeys(failures)))
    return ok


def _whisper_evaluator_identity():
    import whisper  # type: ignore
    version = metadata.version(WHISPER_PACKAGE)
    if version != WHISPER_PACKAGE_VERSION:
        raise RuntimeError(
            f"Whisper package mismatch: expected {WHISPER_PACKAGE_VERSION}, found {version}"
        )
    model_url = getattr(whisper, "_MODELS", {}).get(WHISPER_MODEL, "")
    if f"/{WHISPER_CHECKPOINT_SHA256}/{WHISPER_MODEL}.pt" not in model_url:
        raise RuntimeError("Whisper base checkpoint mapping does not match the pinned SHA-256")
    return {
        "package": WHISPER_PACKAGE,
        "package_version": WHISPER_PACKAGE_VERSION,
        "model": WHISPER_MODEL,
        "checkpoint_sha256": WHISPER_CHECKPOINT_SHA256,
        "language": "en",
        "task": "transcribe",
        "temperature": 0.0,
        "condition_on_previous_text": False,
        "fp16": False,
        "verified": True,
    }


def _load_whisper():
    try:
        import whisper  # type: ignore
        identity = _whisper_evaluator_identity()
        return whisper.load_model(identity["model"]), identity
    except Exception as e:  # noqa: BLE001
        print(f"  (whisper unavailable — failing TTS intelligibility: {type(e).__name__})")
        return None, {
            "package": WHISPER_PACKAGE,
            "package_version": WHISPER_PACKAGE_VERSION,
            "model": WHISPER_MODEL,
            "checkpoint_sha256": WHISPER_CHECKPOINT_SHA256,
            "verified": False,
            "error": f"{type(e).__name__}: {e}",
        }


def _transcribe(model, wav_path):
    import numpy as np  # whisper pulls numpy in
    with wave.open(str(wav_path), "rb") as w:
        n, sr = w.getnframes(), w.getframerate()
        audio = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
    if sr != 16000:  # whisper assumes a raw array is 16 kHz — resample TTS output (e.g. MeloTTS 44100) first
        audio = np.interp(np.linspace(0, len(audio), _resampled_sample_count(len(audio), sr), endpoint=False),
                          np.arange(len(audio)), audio).astype(np.float32)
    return model.transcribe(
        audio,
        language="en",
        task="transcribe",
        temperature=0.0,
        condition_on_previous_text=False,
        fp16=False,
    )["text"].strip()


def _resampled_sample_count(source_count, source_rate):
    if source_count <= 0 or source_rate <= 0:
        raise ValueError("resampling requires positive sample count and rate")
    return max(1, int(round(source_count * 16000 / source_rate)))


def main():
    if len(sys.argv) < 2:
        print("usage: npu_e2e_report.py <report_dir>")
        return 2
    d = Path(sys.argv[1])
    reports = sorted(d.glob("npu_e2e_*.json"))
    if not reports:
        print(f"no npu_e2e_*.json in {d}")
        return 1

    run_inputs, run_inputs_sha256 = _load_run_inputs(d)
    local_git = _local_git_state()
    wmodel = None
    whisper_identity = None
    whisper_attempted = False
    rows = []
    for rp in reports:
        r = json.loads(rp.read_text())
        mid, modality = r.get("model_id", rp.stem), r.get("modality", "?")
        gate = _apply_production_provenance(
            r, rp, d, run_inputs, run_inputs_sha256, local_git,
        )

        # --- TTS intelligibility round-trip (offline whisper) ---
        if modality == "tts":
            samples = r.get("samples", []) if isinstance(r.get("samples"), list) else []
            wavs = sorted(d.glob(f"tts_{mid}_*.wav"))
            if not whisper_attempted:
                whisper_attempted = True
                wmodel, whisper_identity = _load_whisper()
            r["evaluator"] = whisper_identity
            wers = []
            tts_error = None
            if not samples:
                tts_error = "TTS report has no samples for intelligibility"
            elif not wavs:
                tts_error = "TTS WAV inputs are missing for intelligibility"
            elif wmodel is None:
                tts_error = "offline Whisper is unavailable for TTS intelligibility"
            else:
                for s in samples:
                    wav = d / f"tts_{mid}_{s.get('idx')}.wav"
                    if not wav.exists():
                        tts_error = f"expected TTS WAV is missing: {wav.name}"
                        continue
                    try:
                        hyp = _transcribe(wmodel, wav)
                    except Exception as exc:  # noqa: BLE001
                        tts_error = f"TTS transcription failed for {wav.name}: {type(exc).__name__}: {exc}"
                        continue
                    else:
                        w = wer(s.get("input", ""), hyp)
                        s["intelligibility_wer"] = w
                        s["intelligibility_hyp"] = hyp
                        wers.append(w)
            complete = not tts_error and len(wers) == len(samples)
            r.setdefault("gates", {})["tts_intelligibility_evidence"] = complete
            if wers:
                r["intelligibility_wer"] = round(sum(wers) / len(wers), 6)
            if not complete:
                _fail_report(r, tts_error or "TTS intelligibility evidence is incomplete")

        _apply_canonical_thresholds(r, gate)

        if not all(r.get("gates", {}).values()):
            _fail_report(r, "one or more production gates failed")
        rp.write_text(json.dumps(r, indent=2) + "\n")

        gates = r.get("gates", {})
        provenance = r.get("provenance", {})
        sdk_git = provenance.get("sdk_git", {}) if isinstance(provenance, dict) else {}
        device_input = next((item for item in r.get("report_inputs", [])
                             if item.get("role") == "device_report"), {})
        rows.append({
            "model": mid,
            "modality": modality,
            "status": r.get("status", "?"),
            "framework": r.get("framework", "?"),
            "decode_toks": r.get("decode_toks"),
            "tokens_per_s": r.get("tokens_per_s"),
            "ttft_ms": r.get("ttft_ms"),
            "rtf": r.get("rtf"),
            "wer": r.get("wer"),
            "intel_wer": r.get("intelligibility_wer"),
            "sample_rate": r.get("sample_rate"),
            "vision_ms": r.get("vision_ms"),
            "inpaint_ms": r.get("inpaint_ms"),
            "full_psnr_db": r.get("full_psnr_db"),
            "hole_psnr_db": r.get("hole_psnr_db"),
            "seam_psnr_db": r.get("seam_psnr_db"),
            "download_mb": r.get("download_mb"),
            "load_ms": r.get("load_ms"),
            "peak_rss_mb": r.get("peak_rss_mb"),
            "soc": r.get("soc_model"),
            "arch": r.get("arch"),
            "suite_id": r.get("suite_id"),
            "suite_sha256": r.get("suite_sha256"),
            "suite_exact": r.get("suite_provenance", {}).get("exact_match"),
            "hf_revision": r.get("hf_revision"),
            "validation_scope": r.get("validation_scope"),
            "acceptance_eligible": r.get("acceptance_eligible"),
            "bundle_revision_verified": r.get("bundle_revision_verified"),
            "evaluator": r.get("evaluator"),
            "delete_model": gates.get("delete_model"),
            "source_provenance": gates.get("source_provenance"),
            "canonical_thresholds": gates.get("canonical_thresholds"),
            "declared_gate_keys": r.get("declared_gate_keys", []),
            "applied_gate_keys": r.get("applied_gate_keys", []),
            "unapplied_gate_keys": r.get("unapplied_gate_keys", []),
            "sdk_git_revision": sdk_git.get("reported_revision") or sdk_git.get("runner_revision"),
            "sdk_git_dirty": sdk_git.get("reported_dirty") if sdk_git.get("reported_dirty") is not None else sdk_git.get("runner_dirty"),
            "run_inputs_sha256": provenance.get("run_inputs_sha256"),
            "aggregator_sha256": provenance.get("aggregator_sha256"),
            "device_report_input_sha256": device_input.get("sha256"),
            "gates_pass": sum(1 for v in gates.values() if v),
            "gates_total": len(gates),
            "detail": r.get("detail", ""),
        })

    # --- summary.json ---
    (d / "summary.json").write_text(json.dumps(rows, indent=2))

    # --- summary.md ---
    def cell(v):
        return "—" if v is None else (f"{v}")
    hdr = ["model", "modality", "status", "suite", "thresholds", "delete", "framework", "decode_toks", "tokens_per_s",
           "ttft_ms", "rtf", "wer", "intel_wer", "sample_rate", "vision_ms", "inpaint_ms",
           "full_psnr_db", "hole_psnr_db", "seam_psnr_db",
           "download_mb", "load_ms", "peak_rss_mb", "gates"]
    source_revision = rows[0].get("sdk_git_revision")
    source_dirty = rows[0].get("sdk_git_dirty")
    lines = [
        f"# NPU E2E report — {d.name}",
        "",
        f"soc `{rows[0].get('soc')}` · arch `{rows[0].get('arch')}` · {len(rows)} model(s)",
        f"sdk `{source_revision or 'unknown'}` · dirty `{source_dirty if source_dirty is not None else 'unknown'}` "
        f"· run inputs `{run_inputs_sha256 or 'missing'}`",
        "",
        "| " + " | ".join(hdr) + " |",
        "|" + "|".join(["---"] * len(hdr)) + "|",
    ]
    for x in rows:
        lines.append("| " + " | ".join([
            x["model"], x["modality"],
            "✅" if x["status"] == "PASS" else (
                "🟡 SMOKE_PASS" if x["status"] == "SMOKE_PASS" else "❌ " + x["status"]
            ),
            f"{x['suite_id'] or 'missing'}@{(x['suite_sha256'] or '')[:12]}",
            "✅" if x["canonical_thresholds"] else "❌",
            "—" if x["delete_model"] is None else ("✅" if x["delete_model"] else "❌"),
            cell(x["framework"]), cell(x["decode_toks"]), cell(x["tokens_per_s"]),
            cell(x["ttft_ms"]), cell(x["rtf"]), cell(x["wer"]), cell(x["intel_wer"]),
            cell(x["sample_rate"]), cell(x["vision_ms"]), cell(x["inpaint_ms"]),
            cell(x["full_psnr_db"]), cell(x["hole_psnr_db"]), cell(x["seam_psnr_db"]),
            cell(x["download_mb"]),
            cell(x["load_ms"]), cell(x["peak_rss_mb"]),
            f"{x['gates_pass']}/{x['gates_total']}",
        ]) + " |")
    npass = sum(1 for x in rows if x["status"] == "PASS")
    nsmoke = sum(1 for x in rows if x["status"] == "SMOKE_PASS")
    nfail = len(rows) - npass - nsmoke
    lines += [
        "",
        f"**{npass} acceptance PASS, {nsmoke} non-acceptance SMOKE_PASS, {nfail} FAIL.** "
        "Per-model detail: the `npu_e2e_*.json` files in this dir.",
    ]
    for x in rows:
        if x["status"] == "FAIL":
            lines.append(f"- ❌ `{x['model']}` — {x['detail']}")
        elif x["status"] == "SMOKE_PASS":
            lines.append(f"- 🟡 `{x['model']}` — smoke evidence only; acceptance was not claimed")
    (d / "summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if nfail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
