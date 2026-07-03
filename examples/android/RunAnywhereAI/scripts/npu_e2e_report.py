#!/usr/bin/env python3
"""Aggregate on-device NPU E2E per-run JSON reports into a shareable summary.

Reads every ``npu_e2e_<id>.json`` pulled by run_npu_e2e.sh from a report dir,
and — for TTS models — round-trips each synthesized wav through offline whisper
to add an intelligibility WER (vs the input text), the same round-trip forge's
TTS gate uses. Writes ``summary.md`` + ``summary.json`` next to the inputs.

    python3 npu_e2e_report.py <report_dir>

Whisper is optional: if ``openai-whisper`` is not importable the TTS
intelligibility leg is skipped (and clearly marked as such), so the rest of the
report still aggregates. No device access — pure post-processing.
"""
import json
import re
import sys
import wave
from pathlib import Path

INTELLIGIBILITY_WER_MAX = 0.15  # forge TTS_INTELLIGIBILITY_WER

_WORD = re.compile(r"[^\W_]+(?:'[^\W_]+)*", re.UNICODE)


def _words(s):
    return _WORD.findall(s.lower())


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


def _load_whisper():
    try:
        import whisper  # type: ignore
        return whisper.load_model("base")
    except Exception as e:  # noqa: BLE001
        print(f"  (whisper unavailable — skipping TTS intelligibility: {type(e).__name__})")
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

    wmodel = None
    rows = []
    for rp in reports:
        r = json.loads(rp.read_text())
        mid, modality = r.get("model_id", rp.stem), r.get("modality", "?")

        # --- TTS intelligibility round-trip (offline whisper) ---
        if modality == "tts":
            wavs = sorted(d.glob(f"tts_{mid}_*.wav"))
            if wavs and wmodel is None:
                wmodel = _load_whisper()
            if wavs and wmodel is not None:
                wers = []
                for s in r.get("samples", []):
                    wav = d / f"tts_{mid}_{s.get('idx')}.wav"
                    if wav.exists():
                        hyp = _transcribe(wmodel, wav)
                        w = round(wer(s.get("input", ""), hyp), 3)
                        s["intelligibility_wer"] = w
                        s["intelligibility_hyp"] = hyp
                        wers.append(w)
                if wers:
                    worst = max(wers)
                    r["intelligibility_wer"] = worst
                    ok = worst <= INTELLIGIBILITY_WER_MAX
                    r.setdefault("gates", {})["tts_intelligibility"] = ok
                    if not ok and r.get("status") == "PASS":
                        r["status"] = "FAIL"
                        r["detail"] = f"intelligibility wer={worst} > {INTELLIGIBILITY_WER_MAX}"
                    rp.write_text(json.dumps(r, indent=2))  # persist the augmented report

        gates = r.get("gates", {})
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
            "gates_pass": sum(1 for v in gates.values() if v),
            "gates_total": len(gates),
            "detail": r.get("detail", ""),
        })

    # --- summary.json ---
    (d / "summary.json").write_text(json.dumps(rows, indent=2))

    # --- summary.md ---
    def cell(v):
        return "—" if v is None else (f"{v}")
    hdr = ["model", "modality", "status", "framework", "decode_toks", "tokens_per_s",
           "ttft_ms", "rtf", "wer", "intel_wer", "sample_rate", "vision_ms",
           "download_mb", "load_ms", "peak_rss_mb", "gates"]
    lines = [
        f"# NPU E2E report — {d.name}",
        "",
        f"soc `{rows[0].get('soc')}` · arch `{rows[0].get('arch')}` · {len(rows)} model(s)",
        "",
        "| " + " | ".join(hdr) + " |",
        "|" + "|".join(["---"] * len(hdr)) + "|",
    ]
    for x in rows:
        lines.append("| " + " | ".join([
            x["model"], x["modality"],
            "✅" if x["status"] == "PASS" else "❌ " + x["status"],
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
