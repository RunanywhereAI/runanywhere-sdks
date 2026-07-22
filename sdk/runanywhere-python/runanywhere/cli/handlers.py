"""CLI command handlers — thin wrappers over the SDK, mirroring the C++ rcli commands.

Each ``handle_*`` returns an exit code (0/1/2/130). Model loads auto-download on first use (the SDK
resolves + fetches), so there's no separate auto-pull step. Errors are surfaced as SDKException ->
exit 1; bad file paths -> exit 2.
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys

from ..audio import decode_wav, downsample, encode_wav, pcm16_bytes
from ..catalog import CATALOG
from ..download import model_status, models_root, resolve_model
from ..errors import SDKException
from . import output

DEFAULT_LLM = "qwen2.5-0.5b"
DEFAULT_VLM = "smolvlm-256m"
DEFAULT_EMBEDDER = "minilm"
DEFAULT_STT = "whisper-tiny"
DEFAULT_TTS = "piper-lessac"
_FRAME = 512  # VAD frame @ 16 kHz


# --------------------------------------------------------------------------- helpers
def _client(args):
    from ..client import RunAnywhere

    return RunAnywhere(base_dir=getattr(args, "home", None))


def _dim(text: str) -> str:
    return f"\033[2m{text}\033[0m" if output.stderr_is_tty() else text


def _dir_size(directory: str) -> int:
    total = 0
    for root, _dirs, files in os.walk(directory):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def _memory_info():
    """(total_bytes, available_bytes) best-effort, stdlib-only; (None, None) if unavailable."""
    try:
        if os.name == "posix":
            page = os.sysconf("SC_PAGE_SIZE")
            total = page * os.sysconf("SC_PHYS_PAGES")
            names = os.sysconf_names
            avail = page * os.sysconf("SC_AVPHYS_PAGES") if "SC_AVPHYS_PAGES" in names else None
            return total, avail
        if os.name == "nt":
            import ctypes

            class _Mem(ctypes.Structure):
                _fields_ = [("dwLength", ctypes.c_ulong), ("dwMemoryLoad", ctypes.c_ulong),
                            ("ullTotalPhys", ctypes.c_ulonglong), ("ullAvailPhys", ctypes.c_ulonglong),
                            ("ullTotalPageFile", ctypes.c_ulonglong), ("ullAvailPageFile", ctypes.c_ulonglong),
                            ("ullTotalVirtual", ctypes.c_ulonglong), ("ullAvailVirtual", ctypes.c_ulonglong),
                            ("ullAvailExtendedVirtual", ctypes.c_ulonglong)]

            m = _Mem()
            m.dwLength = ctypes.sizeof(_Mem)
            ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(m))
            return int(m.ullTotalPhys), int(m.ullAvailPhys)
    except Exception:  # noqa: BLE001 — memory info is best-effort metadata
        pass
    return None, None


def _read_wav_16k(path: str):
    with open(path, "rb") as f:
        raw = f.read()
    rate, samples = decode_wav(raw)
    if rate != 16000:
        samples = downsample(samples, rate, 16000)
    return samples


def _gen_opts(args) -> dict:
    opts = {}
    if getattr(args, "temperature", None) is not None:
        opts["temperature"] = args.temperature
    if getattr(args, "max_tokens", None) is not None:
        opts["max_tokens"] = args.max_tokens
    if getattr(args, "system", None):
        opts["system_prompt"] = args.system
    return opts


# --------------------------------------------------------------------------- text
def handle_run(args) -> int:
    prompt = args.prompt
    if prompt is None and not sys.stdin.isatty():
        prompt = sys.stdin.read().strip() or None
    try:
        with _client(args) as ra:
            if args.image:
                vlm = ra.load_vlm(args.model or DEFAULT_VLM)
                out = []
                for tok in vlm.caption(args.image, prompt or "Describe the image."):
                    out.append(tok)
                    if not args.json:
                        output.result_raw(tok)
                if args.json:
                    output.emit_json({"model": args.model or DEFAULT_VLM, "response": "".join(out)})
                elif out:
                    output.result("")
                return 0

            model = args.model or DEFAULT_LLM
            llm = ra.load_llm(model)
            if prompt is None:
                return _repl(llm, _gen_opts(args), args, model)
            answer, final = [], None
            for ev in llm.generate_stream(prompt, **_gen_opts(args)):
                if ev.is_final:
                    final = ev.result
                elif ev.is_thinking:
                    if not args.no_think:
                        output.status_raw(_dim(ev.token))
                else:
                    answer.append(ev.token)
                    if not args.json:
                        output.result_raw(ev.token)
            text = "".join(answer)
            if args.json:
                body = {"model": model, "response": text}
                if final:
                    body["usage"] = {"tokens": final.token_count, "tokens_per_second": final.tokens_per_second}
                    if final.thinking_content:
                        body["thinking"] = final.thinking_content
                output.emit_json(body)
            elif text:
                output.result("")
        return 0
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1


def _repl(llm, opts, args, model) -> int:
    output.status(f"run {model} — Ctrl-D or 'exit' to quit.")
    while True:
        try:
            line = input("> ")
        except EOFError:
            output.status("")
            return 0
        if line.strip() in ("exit", "quit"):
            return 0
        if not line.strip():
            continue
        for ev in llm.generate_stream(line, **opts):
            if ev.is_final:
                continue
            if ev.is_thinking:
                if not args.no_think:
                    output.status_raw(_dim(ev.token))
            else:
                output.result_raw(ev.token)
        output.result("")


def handle_chat(args) -> int:
    try:
        with _client(args) as ra:
            chat = ra.create_chat(ra.load_llm(args.model or DEFAULT_LLM), system=args.system)
            output.status(f"chat {args.model or DEFAULT_LLM} — Ctrl-D or 'exit' to quit.")
            while True:
                try:
                    line = input("> ")
                except EOFError:
                    output.status("")
                    return 0
                if line.strip() in ("exit", "quit"):
                    return 0
                if not line.strip():
                    continue
                for tok in chat.send(line):
                    output.result_raw(tok)
                output.result("")
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1


# --------------------------------------------------------------------------- models
def handle_list(args) -> int:
    status = model_status()
    rows = []
    for mid, entry in sorted(CATALOG.items()):
        st = status.get(mid)
        downloaded = bool(st and st.downloaded)
        if not args.all and not downloaded:
            continue
        rows.append([mid, entry.type, f"{entry.size_mb} MB" if getattr(entry, "size_mb", None) else "-",
                     "yes" if downloaded else "no"])
    if args.json:
        output.emit_json({"models": [{"id": r[0], "type": r[1], "downloaded": r[3] == "yes"} for r in rows]})
    else:
        output.table(["MODEL", "TYPE", "SIZE", "DOWNLOADED"], rows)
    return 0


def handle_models(args) -> int:
    args.all = True
    return handle_list(args)


def handle_pull(args) -> int:
    def on_progress(p):
        if not (args.json or args.no_progress) and output.stderr_is_tty():
            output.status_raw(f"\r{p.file} {p.percent}%   ")

    try:
        resolved = resolve_model(args.model, on_progress=on_progress)
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    if not (args.json or args.no_progress):
        output.status("")
    if args.json:
        output.emit_json({"id": resolved.id, "type": resolved.type, "local_path": resolved.primary})
    else:
        output.result(f"pulled {resolved.id} -> {resolved.primary}")
    return 0


def handle_show(args) -> int:
    entry = CATALOG.get(args.model)
    if entry is None:
        output.error(f"model {args.model!r} not found")
        return 1
    st = model_status().get(args.model)
    info = {"id": args.model, "type": entry.type, "primary": entry.primary,
            "params": getattr(entry, "params", None), "size_mb": getattr(entry, "size_mb", None),
            "downloaded": bool(st and st.downloaded)}
    if args.json:
        output.emit_json(info)
    else:
        for k, v in info.items():
            output.result(f"{k}: {v}")
    return 0


def handle_rm(args) -> int:
    # Confine to the models root: a model name like "../../x" must NOT delete outside it.
    root = os.path.realpath(models_root())
    directory = os.path.realpath(os.path.join(root, args.model))
    try:
        contained = directory != root and os.path.commonpath([root, directory]) == root
    except ValueError:  # different drives on Windows
        contained = False
    if not contained:
        output.error(f"invalid model name: {args.model!r}")
        return 2
    if not os.path.isdir(directory):
        output.error(f"{args.model} is not downloaded")
        return 1
    if not args.force and output.stdout_is_tty():
        output.status_raw(f"remove {args.model}? [y/N] ")
        if input().strip().lower() not in ("y", "yes"):
            output.status("aborted")
            return 0
    freed = _dir_size(directory)
    shutil.rmtree(directory, ignore_errors=True)
    if args.json:
        output.emit_json({"id": args.model, "freed_bytes": freed})
    else:
        output.result(f"deleted {args.model}")
    return 0


def handle_embed(args) -> int:
    texts = list(args.text or [])
    if args.input:
        texts.insert(0, args.input)
    if not texts:
        output.error("no input text (positional or -t/--text)")
        return 2
    model = args.model or DEFAULT_EMBEDDER
    try:
        with _client(args) as ra:
            embedder = ra.load_embedder(model)
            vecs = [embedder.embed(t) for t in texts]
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    dim = int(vecs[0].shape[0]) if vecs else 0
    if args.json:
        output.emit_json({"model": model, "dimension": dim, "count": len(vecs),
                          "vectors": [{"text": t, "values": [float(x) for x in v]} for t, v in zip(texts, vecs)]})
    else:
        for t, v in zip(texts, vecs):
            output.result(f"{t[:48]!r}: dim={int(v.shape[0])} [{v[0]:.4f}, {v[1]:.4f}, ...]")
    return 0


# --------------------------------------------------------------------------- audio
def handle_stt(args) -> int:
    try:
        pcm = pcm16_bytes(_read_wav_16k(args.input))
        with _client(args) as ra:
            text = ra.load_stt(args.model or DEFAULT_STT).transcribe(pcm)
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    if args.json:
        output.emit_json({"model": args.model or DEFAULT_STT, "text": text})
    else:
        output.result(text)
    return 0


def handle_tts(args) -> int:
    try:
        with _client(args) as ra:
            synth = ra.load_tts(args.voice or DEFAULT_TTS).synthesize(args.text)
        with open(args.output, "wb") as f:
            f.write(encode_wav(synth.samples, synth.sample_rate))
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    duration_ms = round(len(synth.samples) / synth.sample_rate * 1000)
    if args.json:
        output.emit_json({"voice": args.voice or DEFAULT_TTS, "path": args.output,
                          "sample_rate": synth.sample_rate, "duration_ms": duration_ms})
    else:
        output.result(args.output)
    return 0


def handle_vad(args) -> int:
    try:
        samples = _read_wav_16k(args.input)
        with _client(args) as ra:
            vad = ra.create_vad()
            segs = []
            in_speech = False
            seg_start = 0.0
            per_frame = _FRAME / 16000.0
            n = 0
            for i in range(0, len(samples) - _FRAME + 1, _FRAME):
                speech = vad.detect(samples[i:i + _FRAME])
                t = n * per_frame
                if speech and not in_speech:
                    seg_start, in_speech = t, True
                elif not speech and in_speech:
                    segs.append((seg_start, t))
                    in_speech = False
                n += 1
            if in_speech:
                segs.append((seg_start, len(samples) / 16000.0))
            vad.close()
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    if args.json:
        output.emit_json({"model": args.model or "vad",
                          "segments": [{"start_s": round(a, 3), "end_s": round(b, 3)} for a, b in segs]})
    else:
        output.table(["START", "END"], [[f"{a:.3f}", f"{b:.3f}"] for a, b in segs])
    return 0


def handle_voice(args) -> int:
    try:
        pcm = pcm16_bytes(_read_wav_16k(args.input))
        with _client(args) as ra:
            agent = ra.create_voice_agent(
                ra.load_stt(args.stt or DEFAULT_STT),
                ra.load_llm(args.llm or DEFAULT_LLM),
                ra.load_tts(args.tts or DEFAULT_TTS),
            )
            turn = agent.process_turn(pcm)
        if args.output:
            with open(args.output, "wb") as f:
                f.write(encode_wav(turn.audio.samples, turn.audio.sample_rate))
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    if args.json:
        output.emit_json({"transcription": turn.transcript, "response": turn.response,
                          "reply_audio": args.output})
    else:
        output.result(f"you: {turn.transcript}")
        output.result(f"agent: {turn.response}")
        if args.output:
            output.result(f"audio: {args.output}")
    return 0


# --------------------------------------------------------------------------- info
def handle_backends(args) -> int:
    with _client(args) as ra:
        backends = ra.available_backends()
    if args.json:
        output.emit_json({"backends": backends})
    else:
        for name in backends:
            output.result(name)
    return 0


def handle_version(args) -> int:
    from .. import __version__

    if args.json:
        output.emit_json({"runanywhere": __version__})
    else:
        output.result(f"runanywhere {__version__}")
    return 0


def handle_info(args) -> int:
    from .. import __version__

    total, avail = _memory_info()
    with _client(args) as ra:
        backends = ra.available_backends()
    info = {"runanywhere": __version__, "platform": sys.platform, "models_dir": models_root(),
            "backends": backends, "memory_total_bytes": total, "memory_available_bytes": avail}
    if args.json:
        output.emit_json(info)
    else:
        for k, v in info.items():
            output.result(f"{k}: {v}")
    return 0


def handle_serve(args) -> int:
    try:
        from ..server import serve
    except ImportError:
        output.status("The OpenAI-compatible server needs extra dependencies.")
        output.status("Install them with:\n\n    pip install runanywhere[server]\n")
        return 1
    serve(host=args.host, port=args.port, api_key=args.api_key, default_llm=args.default_llm,
          allow_image_urls=args.allow_image_urls, allow_arbitrary_models=args.allow_arbitrary_models,
          log_level=args.log_level)
    return 0


# --------------------------------------------------------------------------- registration
def register(sub, gp: argparse.ArgumentParser) -> None:
    def add(name, help_text, aliases=()):
        return sub.add_parser(name, parents=[gp], help=help_text, aliases=list(aliases))

    r = add("run", "run an LLM (or VLM with --image) prompt")
    r.add_argument("model", nargs="?")
    r.add_argument("prompt", nargs="?")
    r.add_argument("--system")
    r.add_argument("--temp", "--temperature", type=float, dest="temperature")
    r.add_argument("--max-tokens", type=int)
    r.add_argument("--image")
    r.add_argument("--no-think", action="store_true", help="suppress the model's thinking output")
    r.set_defaults(handler=handle_run)

    c = add("chat", "interactive multi-turn chat")
    c.add_argument("model", nargs="?")
    c.add_argument("--system")
    c.set_defaults(handler=handle_chat)

    ls = add("list", "list models (downloaded; --all for the whole catalog)", aliases=("ls",))
    ls.add_argument("-a", "--all", action="store_true")
    ls.set_defaults(handler=handle_list)

    m = add("models", "list the full catalog + download state")
    m.set_defaults(handler=handle_models)

    p = add("pull", "download a model (catalog id, HF repo, or URL)")
    p.add_argument("model")
    p.set_defaults(handler=handle_pull)

    sh = add("show", "model registry details")
    sh.add_argument("model")
    sh.set_defaults(handler=handle_show)

    rm = add("rm", "delete a downloaded model", aliases=("remove",))
    rm.add_argument("model")
    rm.add_argument("-f", "--force", action="store_true")
    rm.set_defaults(handler=handle_rm)

    e = add("embed", "generate text embeddings")
    e.add_argument("input", nargs="?")
    e.add_argument("-m", "--model")
    e.add_argument("-t", "--text", action="append")
    e.set_defaults(handler=handle_embed)

    st = add("stt", "transcribe a WAV (speech-to-text)")
    st.add_argument("model", nargs="?")
    st.add_argument("-i", "--input", required=True)
    st.set_defaults(handler=handle_stt)

    tt = add("tts", "synthesize speech (text-to-speech)")
    tt.add_argument("voice", nargs="?")
    tt.add_argument("-t", "--text", required=True)
    tt.add_argument("-o", "--output", required=True)
    tt.set_defaults(handler=handle_tts)

    v = add("vad", "detect speech segments in a WAV")
    v.add_argument("model", nargs="?")
    v.add_argument("-i", "--input", required=True)
    v.set_defaults(handler=handle_vad)

    vo = add("voice", "full voice turn (STT -> LLM -> TTS)")
    vo.add_argument("-i", "--input", required=True)
    vo.add_argument("--stt")
    vo.add_argument("--llm")
    vo.add_argument("--tts")
    vo.add_argument("-o", "--output")
    vo.set_defaults(handler=handle_voice)

    b = add("backends", "list registered inference backends")
    b.set_defaults(handler=handle_backends)

    ve = add("version", "print the SDK version")
    ve.set_defaults(handler=handle_version)

    i = add("info", "environment summary (paths, memory, backends)")
    i.set_defaults(handler=handle_info)

    sv = add("serve", "run the local OpenAI-compatible server")
    sv.add_argument("--host", default="127.0.0.1")
    sv.add_argument("--port", type=int, default=8000)
    sv.add_argument("--api-key", default=None)
    sv.add_argument("--default-llm", default=None)
    sv.add_argument("--allow-image-urls", action="store_true")
    sv.add_argument("--allow-arbitrary-models", action="store_true")
    sv.add_argument("--log-level", default="info")
    sv.set_defaults(handler=handle_serve)
