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
import json
import re
import subprocess
import sys
import wave
from pathlib import Path

INTELLIGIBILITY_WER_MAX = 0.15  # forge TTS_INTELLIGIBILITY_WER

_WORD = re.compile(r"[^\W_]+(?:'[^\W_]+)*", re.UNICODE)
_ASR_ALIASES = {"mr": "mister", "neuro": "neural"}
_DIGIT_WORDS = {
    "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four",
    "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine",
}
APP_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = APP_ROOT.parents[2]
SUITES = APP_ROOT / "app" / "src" / "androidTest" / "assets" / "npu_suites"


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


def _suite_gate(mid, arch=None):
    candidates = [SUITES / f"{mid}.json"]
    if arch and not mid.endswith(f"_{arch}"):
        candidates.append(SUITES / f"{mid}_{arch}.json")
    path = next((candidate for candidate in candidates if candidate.exists()), None)
    if path is None:
        return {
            "intelligibility_wer_max": INTELLIGIBILITY_WER_MAX,
            "suite_pass_frac": 1.0,
            "suite_id": None,
            "suite_sha256": None,
            "suite_valid": False,
            "suite_schema": None,
            "suite_model_id": None,
            "suite_cases": 0,
            "suite_metric": None,
        }
    raw = path.read_bytes()
    try:
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            raise ValueError("suite root must be an object")
        gate = payload.get("gate", {})
        cases = payload.get("cases", [])
        suite_valid = (
            payload.get("schema") == "npu_suite/v1"
            and payload.get("model_id") == path.stem
            and isinstance(gate, dict)
            and isinstance(cases, list)
            and bool(cases)
        )
    except Exception:  # noqa: BLE001
        payload = {}
        gate = {}
        suite_valid = False
    return {
        "intelligibility_wer_max": gate.get("intelligibility_wer_max", INTELLIGIBILITY_WER_MAX),
        "suite_pass_frac": gate.get("suite_pass_frac", 1.0),
        "suite_id": path.stem,
        "suite_sha256": hashlib.sha256(raw).hexdigest(),
        "suite_valid": suite_valid,
        "suite_schema": payload.get("schema"),
        "suite_model_id": payload.get("model_id"),
        "suite_cases": len(payload.get("cases", [])) if isinstance(payload.get("cases"), list) else 0,
        "suite_metric": gate.get("metric") if isinstance(gate, dict) else None,
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

    deletion = report.get("delete") if isinstance(report.get("delete"), dict) else {}
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


def _load_whisper():
    try:
        import whisper  # type: ignore
        return whisper.load_model("base")
    except Exception as e:  # noqa: BLE001
        print(f"  (whisper unavailable — failing TTS intelligibility: {type(e).__name__})")
        return None


def _transcribe(model, wav_path):
    import numpy as np  # whisper pulls numpy in
    with wave.open(str(wav_path), "rb") as w:
        n, sr = w.getnframes(), w.getframerate()
        audio = np.frombuffer(w.readframes(n), dtype=np.int16).astype(np.float32) / 32768.0
    if sr != 16000:  # whisper assumes a raw array is 16 kHz — resample TTS output (e.g. MeloTTS 44100) first
        audio = np.interp(np.linspace(0, len(audio), int(len(audio) * 16000 / sr), endpoint=False),
                          np.arange(len(audio)), audio).astype(np.float32)
    return model.transcribe(audio, language="en", fp16=False)["text"].strip()


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
            if wavs and not whisper_attempted:
                whisper_attempted = True
                wmodel = _load_whisper()
            wers = []
            passed = 0
            tts_error = None
            if not samples:
                tts_error = "TTS report has no samples for intelligibility"
            elif not wavs:
                tts_error = "TTS WAV inputs are missing for intelligibility"
            elif wmodel is None:
                tts_error = "offline Whisper is unavailable for TTS intelligibility"
            else:
                wer_max = float(gate["intelligibility_wer_max"])
                pass_frac = float(gate["suite_pass_frac"])
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
                        w = round(wer(s.get("input", ""), hyp), 3)
                        s["intelligibility_wer"] = w
                        s["intelligibility_hyp"] = hyp
                        s["intelligibility_pass"] = w <= wer_max
                        wers.append(w)
                        if w <= wer_max:
                            passed += 1
            complete = not tts_error and len(wers) == len(samples)
            worst = max(wers) if wers else None
            frac = round(passed / len(wers), 2) if wers else 0.0
            ok = complete and frac >= float(gate["suite_pass_frac"]) - 1e-9
            r.setdefault("gates", {})["tts_intelligibility"] = ok
            if wers:
                r["intelligibility_wer"] = worst
                r["intelligibility_pass_frac"] = frac
            if not ok:
                reason = tts_error or (
                    f"intelligibility pass_frac={frac} < {gate['suite_pass_frac']} (worst wer={worst})"
                )
                _fail_report(r, reason)
            elif r.get("status") == "FAIL" and "intelligibility" in r.get("detail", ""):
                if all(r.get("gates", {}).values()):
                    r["status"] = "PASS"
                    r["detail"] = "ok"

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
            "download_mb": r.get("download_mb"),
            "load_ms": r.get("load_ms"),
            "peak_rss_mb": r.get("peak_rss_mb"),
            "soc": r.get("soc_model"),
            "arch": r.get("arch"),
            "suite_id": r.get("suite_id"),
            "suite_sha256": r.get("suite_sha256"),
            "suite_exact": r.get("suite_provenance", {}).get("exact_match"),
            "delete_model": gates.get("delete_model"),
            "source_provenance": gates.get("source_provenance"),
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
    hdr = ["model", "modality", "status", "suite", "delete", "framework", "decode_toks", "tokens_per_s",
           "ttft_ms", "rtf", "wer", "intel_wer", "sample_rate", "vision_ms",
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
            "✅" if x["status"] == "PASS" else "❌ " + x["status"],
            f"{x['suite_id'] or 'missing'}@{(x['suite_sha256'] or '')[:12]}",
            "✅" if x["delete_model"] else "❌",
            cell(x["framework"]), cell(x["decode_toks"]), cell(x["tokens_per_s"]),
            cell(x["ttft_ms"]), cell(x["rtf"]), cell(x["wer"]), cell(x["intel_wer"]),
            cell(x["sample_rate"]), cell(x["vision_ms"]), cell(x["download_mb"]),
            cell(x["load_ms"]), cell(x["peak_rss_mb"]),
            f"{x['gates_pass']}/{x['gates_total']}",
        ]) + " |")
    npass = sum(1 for x in rows if x["status"] == "PASS")
    lines += ["", f"**{npass}/{len(rows)} models PASS.** Per-model detail: the `npu_e2e_*.json` files in this dir."]
    for x in rows:
        if x["status"] != "PASS":
            lines.append(f"- ❌ `{x['model']}` — {x['detail']}")
    (d / "summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0 if npass == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
