"""CLI command handlers — thin wrappers over the SDK namespaces, mirroring the verbs.

Each ``handle_*`` returns an exit code (0/1/2/130). Generation verbs auto-load and
auto-download, so there is no separate pull step. Errors surface as SDKException -> exit 1;
bad file paths -> exit 2.
"""
from __future__ import annotations

import argparse
import os
import sys

import runanywhere as ra
from runanywhere import (
    AudioFormat,
    AudioInput,
    ChatMessage,
    EmbedOptions,
    ImageInput,
    LlmOptions,
    ModelFilter,
    ModelRef,
    RagDocument,
    ReasoningMode,
    ReasoningOptions,
    Role,
    SDKException,
    SttOptions,
    TtsOptions,
)

from ..download import models_root
from . import output

DEFAULT_LLM = "qwen2.5-0.5b"
DEFAULT_VLM = "smolvlm-256m"
DEFAULT_EMBEDDER = "minilm"
DEFAULT_STT = "whisper-tiny"
DEFAULT_TTS = "piper-lessac"


# --------------------------------------------------------------------------- helpers
class _Sdk:
    """Bring the SDK up for one command and tear it down afterwards."""

    def __init__(self, args: argparse.Namespace) -> None:
        home = getattr(args, "home", None)
        if home:
            os.environ["RUNANYWHERE_HOME"] = home

    def __enter__(self) -> None:
        ra.initialize()

    def __exit__(self, exc_type: object, exc: object, tb: object) -> None:
        ra.reset()


def _dim(text: str) -> str:
    return f"\033[2m{text}\033[0m" if output.stderr_is_tty() else text


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


def _llm_options(args: argparse.Namespace, model: str) -> LlmOptions:
    options = LlmOptions(model=model)
    if getattr(args, "temperature", None) is not None:
        options.temperature = args.temperature
    if getattr(args, "max_tokens", None) is not None:
        options.max_output_tokens = args.max_tokens
    if getattr(args, "system", None):
        options.system_prompt = args.system
    # --no-think suppresses thinking at the source; otherwise thoughts are requested so the
    # CLI can render them dimmed.
    if getattr(args, "no_think", False):
        options.reasoning = ReasoningOptions(mode=ReasoningMode.OFF)
    else:
        options.reasoning = ReasoningOptions(include_in_output=True)
    return options


def _render(events, args: argparse.Namespace) -> tuple:
    """Print a generation stream; returns (answer text, terminal result)."""
    answer, result = [], None
    for event in events:
        if event.is_completed:
            result = event.result
        elif event.is_thought:
            if not getattr(args, "no_think", False):
                output.status_raw(_dim(event.text))
        elif event.is_token:
            answer.append(event.text)
            if not args.json:
                output.result_raw(event.text)
    return "".join(answer), result


# --------------------------------------------------------------------------- text
def handle_run(args: argparse.Namespace) -> int:
    prompt = args.prompt
    if prompt is None and not sys.stdin.isatty():
        prompt = sys.stdin.read().strip() or None
    try:
        with _Sdk(args):
            if args.image:
                model = args.model or DEFAULT_VLM
                options = _llm_options(args, model)
                events = ra.vlm.generate_stream(
                    ImageInput.file(args.image), prompt or "Describe the image.", options
                )
                text, _result = _render(events, args)
                if args.json:
                    output.emit_json({"model": model, "response": text})
                elif text:
                    output.result("")
                return 0

            model = args.model or DEFAULT_LLM
            options = _llm_options(args, model)
            if prompt is None:
                return _repl(options, args, model)
            text, result = _render(ra.llm.generate_stream(prompt, options), args)
            if args.json:
                body = {"model": model, "response": text}
                if result:
                    body["usage"] = {
                        "output_tokens": result.output_tokens,
                        "tokens_per_second": result.tokens_per_second,
                    }
                    if result.thinking_text:
                        body["thinking"] = result.thinking_text
                output.emit_json(body)
            elif text:
                output.result("")
        return 0
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1


def _repl(options: LlmOptions, args: argparse.Namespace, model: str) -> int:
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
        _render(ra.llm.generate_stream(line, options), args)
        output.result("")


def handle_chat(args: argparse.Namespace) -> int:
    model = args.model or DEFAULT_LLM
    try:
        with _Sdk(args):
            options = _llm_options(args, model)
            history: list = []
            if args.system:
                history.append(ChatMessage(role=Role.SYSTEM, content=args.system))
            output.status(f"chat {model} — Ctrl-D or 'exit' to quit.")
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
                history.append(ChatMessage(role=Role.USER, content=line))
                text, _result = _render(ra.llm.generate_stream(history, options), args)
                history.append(ChatMessage(role=Role.ASSISTANT, content=text.strip()))
                output.result("")
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1


# --------------------------------------------------------------------------- models
def handle_list(args: argparse.Namespace) -> int:
    infos = ra.models.list(None if args.all else ModelFilter(downloaded=True))
    rows = [
        [
            info.id,
            info.category.name.lower(),
            f"{info.size_bytes // (1024 * 1024)} MB" if info.size_bytes else "-",
            "yes" if info.downloaded else "no",
        ]
        for info in infos
    ]
    if args.json:
        output.emit_json(
            {
                "models": [
                    {"id": i.id, "category": i.category.name, "downloaded": i.downloaded}
                    for i in infos
                ]
            }
        )
    else:
        output.table(["MODEL", "CATEGORY", "SIZE", "DOWNLOADED"], rows)
    return 0


def handle_models(args: argparse.Namespace) -> int:
    args.all = True
    return handle_list(args)


def handle_pull(args: argparse.Namespace) -> int:
    try:
        downloaded = None
        for event in ra.models.download(args.model):
            if event.kind.name == "PROGRESS" and not (args.json or args.no_progress):
                if output.stderr_is_tty():
                    output.status_raw(f"\r{event.file} {event.percent}%   ")
            elif event.kind.name == "COMPLETED":
                downloaded = event.model
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    if not (args.json or args.no_progress):
        output.status("")
    if args.json:
        output.emit_json(
            {"id": args.model, "local_path": downloaded.local_path if downloaded else None}
        )
    else:
        output.result(f"pulled {args.model}")
    return 0


def handle_show(args: argparse.Namespace) -> int:
    info = ra.models.get(args.model)
    if info is None:
        output.error(f"model {args.model!r} not found")
        return 1
    body = {
        "id": info.id,
        "category": info.category.name,
        "name": info.name,
        "downloaded": info.downloaded,
        "size_bytes": info.size_bytes,
        "local_path": info.local_path,
    }
    if args.json:
        output.emit_json(body)
    else:
        for key, value in body.items():
            output.result(f"{key}: {value}")
    return 0


def handle_rm(args: argparse.Namespace) -> int:
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
    freed = 0
    for walk_root, _dirs, files in os.walk(directory):
        for name in files:
            try:
                freed += os.path.getsize(os.path.join(walk_root, name))
            except OSError:
                pass
    try:
        ra.models.delete(args.model)
    except SDKException as exc:
        output.error(str(exc))
        return 1
    if args.json:
        output.emit_json({"id": args.model, "freed_bytes": freed})
    else:
        output.result(f"deleted {args.model}")
    return 0


def handle_embed(args: argparse.Namespace) -> int:
    texts = list(args.text or [])
    if args.input:
        texts.insert(0, args.input)
    if not texts:
        output.error("no input text (positional or -t/--text)")
        return 2
    model = args.model or DEFAULT_EMBEDDER
    try:
        with _Sdk(args):
            vectors = ra.embeddings.embed(texts, EmbedOptions(model=model))
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    dimension = int(vectors[0].vector.shape[0]) if vectors else 0
    if args.json:
        output.emit_json(
            {
                "model": model,
                "dimension": dimension,
                "count": len(vectors),
                "vectors": [
                    {"text": texts[v.index], "values": [float(x) for x in v.vector]}
                    for v in vectors
                ],
            }
        )
    else:
        for vector in vectors:
            values = vector.vector
            output.result(
                f"{texts[vector.index][:48]!r}: dim={int(values.shape[0])} "
                f"[{values[0]:.4f}, {values[1]:.4f}, ...]"
            )
    return 0


# --------------------------------------------------------------------------- audio
def handle_stt(args: argparse.Namespace) -> int:
    model = args.model or DEFAULT_STT
    try:
        with _Sdk(args):
            transcription = ra.stt.transcribe(
                AudioInput.file(args.input), SttOptions(model=model)
            )
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    if args.json:
        output.emit_json(
            {
                "model": model,
                "text": transcription.text,
                "duration_ms": transcription.duration_ms,
            }
        )
    else:
        output.result(transcription.text)
    return 0


def handle_tts(args: argparse.Namespace) -> int:
    voice = args.voice or DEFAULT_TTS
    try:
        with _Sdk(args):
            audio = ra.tts.synthesize(args.text, TtsOptions(model=voice, format=AudioFormat.WAV))
        with open(args.output, "wb") as handle:
            handle.write(audio.data)
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    if args.json:
        output.emit_json(
            {
                "voice": voice,
                "path": args.output,
                "sample_rate": audio.sample_rate,
                "duration_ms": audio.duration_ms,
            }
        )
    else:
        output.result(args.output)
    return 0


def handle_vad(args: argparse.Namespace) -> int:
    try:
        with _Sdk(args):
            result = ra.vad.detect(AudioInput.file(args.input))
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    if args.json:
        output.emit_json(
            {
                "is_speech": result.is_speech,
                "segments": [
                    {"start_ms": s.start_ms, "end_ms": s.end_ms} for s in result.segments
                ],
            }
        )
    else:
        output.table(
            ["START", "END"],
            [[f"{s.start_ms / 1000:.3f}", f"{s.end_ms / 1000:.3f}"] for s in result.segments],
        )
    return 0


def handle_voice(args: argparse.Namespace) -> int:
    """One voice turn over a WAV file: stt -> llm -> tts.

    ``voice.create_session`` needs a microphone and the native voice agent, neither of which
    this SDK has, so the CLI composes the three namespaces for this file-in / file-out demo.
    """
    try:
        with _Sdk(args):
            transcript = ra.stt.transcribe(
                AudioInput.file(args.input), SttOptions(model=args.stt or DEFAULT_STT)
            ).text.strip()
            answer = ra.llm.generate(
                transcript or "Say hello.",
                LlmOptions(model=args.llm or DEFAULT_LLM, max_output_tokens=128),
            ).text.strip()
            audio = ra.tts.synthesize(
                answer, TtsOptions(model=args.tts or DEFAULT_TTS, format=AudioFormat.WAV)
            )
        if args.output:
            with open(args.output, "wb") as handle:
                handle.write(audio.data)
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    if args.json:
        output.emit_json(
            {"transcription": transcript, "response": answer, "reply_audio": args.output}
        )
    else:
        output.result(f"you: {transcript}")
        output.result(f"agent: {answer}")
        if args.output:
            output.result(f"audio: {args.output}")
    return 0


def handle_rag(args: argparse.Namespace) -> int:
    """Ingest text files, then answer one question over them."""
    try:
        with _Sdk(args):
            with ra.rag.open(
                ModelRef(args.embedder or DEFAULT_EMBEDDER),
                ModelRef(args.model or DEFAULT_LLM),
            ) as session:
                session.ingest([RagDocument.file(path) for path in args.files])
                result = session.query(args.question, LlmOptions(max_output_tokens=192))
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    if args.json:
        output.emit_json(
            {
                "answer": result.answer,
                "sources": [{"text": m.text, "score": m.score} for m in result.sources],
            }
        )
    else:
        output.result(result.answer.strip())
        for match in result.sources:
            output.status(f"  source (score {match.score:.2f}): {match.text[:70]}")
    return 0


# --------------------------------------------------------------------------- info
def handle_backends(args: argparse.Namespace) -> int:
    try:
        names = ra.backends()
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    if args.json:
        output.emit_json({"backends": names})
    else:
        for name in names:
            output.result(name)
    return 0


def handle_version(args: argparse.Namespace) -> int:
    if args.json:
        output.emit_json({"runanywhere": ra.__version__})
    else:
        output.result(f"runanywhere {ra.__version__}")
    return 0


def handle_info(args: argparse.Namespace) -> int:
    total, avail = _memory_info()
    try:
        names = ra.backends()
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
    info = {
        "runanywhere": ra.__version__,
        "platform": sys.platform,
        "models_dir": models_root(),
        "backends": names,
        "memory_total_bytes": total,
        "memory_available_bytes": avail,
    }
    if args.json:
        output.emit_json(info)
    else:
        for key, value in info.items():
            output.result(f"{key}: {value}")
    return 0


def handle_serve(args: argparse.Namespace) -> int:
    try:
        from ..server import serve
    except ImportError:
        output.status("The OpenAI-compatible server needs extra dependencies.")
        output.status("Install them with:\n\n    pip install runanywhere[server]\n")
        return 1
    try:
        serve(host=args.host, port=args.port, api_key=args.api_key, default_llm=args.default_llm,
              allow_image_urls=args.allow_image_urls, allow_arbitrary_models=args.allow_arbitrary_models,
              log_level=args.log_level)
    except (SDKException, OSError) as exc:
        output.error(str(exc))
        return 1
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
    c.add_argument("--no-think", action="store_true", help="suppress the model's thinking output")
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

    vo = add("voice", "one voice turn (stt -> llm -> tts)")
    vo.add_argument("-i", "--input", required=True)
    vo.add_argument("--stt")
    vo.add_argument("--llm")
    vo.add_argument("--tts")
    vo.add_argument("-o", "--output")
    vo.set_defaults(handler=handle_voice)

    rg = add("rag", "answer a question over local text files")
    rg.add_argument("question")
    rg.add_argument("files", nargs="+")
    rg.add_argument("-m", "--model")
    rg.add_argument("--embedder")
    rg.set_defaults(handler=handle_rag)

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
