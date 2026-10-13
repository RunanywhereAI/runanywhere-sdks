# Python SDK — architecture deep dive

Per-component detail behind the layered summary in `../../AGENTS.md`. Read that file
first; come here when you're actually changing one of these components.

## Entry point — module-level, one call

`runanywhere.initialize(api_key=None, base_url=None, environment=PRODUCTION)` is the whole
bring-up, and `reset()` the whole teardown; `is_ready()`, `version()`, `device_id()`,
`backends()` and the `events` bus sit beside them. There is no client object to construct and
no second init phase. The namespaces (`runanywhere.llm`, `.rag`, `.models`, …) are singletons
created at import time; they hold no native state, so importing them costs nothing.

`api_key` and `base_url` drive the control plane: with both set, `initialize` runs the
two-phase handshake — authenticate, then flush telemetry — via `configure_control_plane` in
`native/module.cpp` (mirroring rcli's bootstrap). HTTP goes through a **stdlib-`urllib`
transport** the module registers with commons (`rac_http_transport_register`), so there is no
libcurl / third-party client in the wheel — the same pattern Swift (URLSession) and Kotlin
(OkHttp) use to supply their own transport. Keyless, `initialize` does no network work. The
transport/telemetry callbacks re-acquire the GIL to call the `urllib` poster.

## The process-wide runtime

`_runtime.Runtime` (the module-level `runtime` singleton) owns the native core and keeps **one
resident model per `ModelCategory`**. Asking for a different id in the same category swaps it;
that map is what `models.state()` reports and `models.unload()` clears. Generation verbs call
`runtime.llm(options.model)` and get the resident handle back, loading (and downloading) only
when the id differs. `initialize`/`reset` are idempotent and guarded by one `RLock`; events are
emitted outside it so a listener cannot deadlock the lifecycle.

Default dirs: base = `~/.runanywhere` (override with `RUNANYWHERE_HOME`), secure =
`<base>/secure`.

`runtime.resolve()` tolerates a local path that does not exist yet (`models.register` records
models whose files arrive later); `runtime.resolve_for_load()` refuses one, so a bad path is a
`MODEL_NOT_FOUND` instead of an opaque native failure.

## Model handles (internal)

`_handles.py` holds `(core, handle)` and exposes the primitive the namespaces build on —
nothing here is public. Each `unload()` calls the matching `core.unload_*` and is idempotent;
using a handle afterwards raises `invalid_state` rather than passing a dead handle to C.

- `LLMModel` — `generate`/`agenerate` (raw token iterators), `cancel`.
- `VLMModel` — `generate`/`agenerate` over `(image_path, prompt)`, `cancel`.
- `Embedder` — `embed(text) -> np.ndarray`, `embed_batch(texts) -> list[np.ndarray]`.
- `STTModel` — `transcribe(pcm16) -> str`; `atranscribe` runs it on the default executor.
- `TTSVoice` — `synthesize(text) -> Synthesis`; `asynthesize` on the executor.
- `Vad` — energy VAD by default; `load_model` upgrades to Silero/sherpa model VAD;
  `process`/`set_threshold`/`reset`.

Everything above the handles — the `started`/`token`/`completed` grammar, the metrics block,
thinking splitting, stop-sequence truncation — lives in `_generation.py`, so `llm` and `vlm`
share one implementation.

## Namespace conventions

- One module per namespace in `runanywhere/api/`, ending in the singleton the package
  re-exports (`llm = Llm()`).
- Sync verb plus an `a`-prefixed async twin. Streaming verbs return an iterator /
  async-iterator of the event dataclass; one-shot verbs collect that same stream.
- Options are always the second positional argument and always optional; a prompt is never a
  field inside options.
- Where the pybind11 bridge binds nothing (rerank, diarization, segmentation, images, lora,
  the voice agent, streaming STT, TTS playback) the verb exists and raises
  `SDKException.not_implemented` **naming the exact missing `rac_*` symbols**. Never stub a
  plausible-looking result.

## Single in-flight generation

`LLMModel`/`VLMModel` each hold a `_GenerationGuard` — a **non-blocking** lock. A second
concurrent `generate` on the same model raises `SDKException.invalid_state`
immediately rather than deadlocking or queuing (a concurrent generate is a programming
error). The guard is held for the whole stream lifetime and released when the stream is
exhausted, broken out of, closed, or raises (`_guarded_iter` / `_aguarded_iter`).

## Streaming bridge

`_streaming.py` turns the blocking native streaming call (which invokes an
`on_token(str) -> bool | None` callback once per token, returning `False` to stop the C loop
early) into Python iterators:

- `iter_tokens` (sync) — runs `native_call` on a daemon worker thread; tokens cross to the
  consumer through a bounded `queue.Queue` (backpressure). On close/break/exception a
  `threading.Event` is set so the next `on_token` returns `False`, optional `on_stop`
  fires (wired to `rac_*_component_cancel`), the queue is drained, and the worker joined.
  Worker exceptions are re-raised in the consumer.
- `aiter_tokens` (async) — same worker model, but hands each token to the running event loop
  via `loop.call_soon_threadsafe` into a bounded `asyncio.Queue`; the worker blocks on a
  `concurrent.futures.Future` until the token is accepted (backpressure). Teardown joins the
  worker off-loop via `run_in_executor` so it never blocks the event loop.

The GIL discipline lives on the C++ side: `generate`/`generate_vlm` release the GIL around
the blocking `rac_*_generate_stream` and re-acquire it inside the token callback; all other
blocking calls release the GIL only around the C call and build numpy/str/tuple results with
the GIL held.

## Options → native kwargs

`options.py` defines the `*Options` dataclasses with the v3 spec's field names and defaults.
`_options_bridge.llm_kwargs` maps `LlmOptions` onto the kwargs `native/module.cpp`'s
`generate` actually accepts: `max_output_tokens` → `max_tokens`, `reasoning.mode == OFF` →
typed `reasoning.mode=OFF`, and `structured_output.schema` → typed
`StructuredOutputOptions.schema`; `temperature` / `top_p` / `top_k` / `system_prompt` pass
through verbatim. Commons owns schema-to-GBNF compilation and repair.

**A knob the bridge cannot carry is never silently dropped.** Setting `min_p`,
`frequency_penalty`, `presence_penalty`, `repetition_penalty`, `seed`, `reasoning.pattern`,
`structured_output.strict=False`, or structured output on `vlm` raises
`not_implemented` naming the missing bridge parameter. `check_stt_options`,
`check_tts_options` and `check_embed_options` do the same for the STT/TTS/embedding knobs that
have no bound options struct. When `module.cpp` gains a parameter, delete the guard — do not
start ignoring the field.

## Structured output, grammar & tools

`structured.py` forwards typed schema/options to commons and parses the typed result.
`llm.generate_structured` returns a `StructuredResult` (`valid=False` with the raw text when
validation fails rather than raising); grammar compilation and repair remain in commons.
Tools go through `llm.tools.register(tool, executor)`: `llm.generate` runs the
loop, executing the matched tool (awaiting a coroutine result) and feeding the observation
back, up to `max_tool_calls`. The loop also stops early when the model repeats a call with
identical arguments, since that makes no further progress. A call with no registered executor
finishes the stream with `finish_reason=TOOL_CALLS` so the caller can run it.

## Event system

`events.py` is a small typed pub/sub `EventBus` where a throwing listener never breaks an
emit. Each event family is one dataclass carrying a `kind` (`GenerationEvent`,
`TranscriptionEvent`, `VadEvent`, `RagEvent`, `ImageEvent`, `DownloadEvent`, `VoiceEvent`,
`SdkEvent`), so consumers switch on `kind` instead of isinstance chains. The stream events are
returned by the verbs; only `SdkEvent` (ready / model loaded / model unloaded / error) goes
through the process-wide singleton `bus`, exposed as `runanywhere.events`. Subscribe with
`bus.on(listener) -> off` (or `once`).

## Error system

`errors.py` defines `SDKException` (the single throwable) carrying a canonical `code`
(`ErrorCode`, exhaustive vs `idl/errors.proto`) + `category` (`ErrorCategory`) for
cross-SDK-uniform handling. `category_for_code` is a faithful port of commons
`rac_result_to_proto_category` (keep in sync). Category-specific static factories
(`not_initialized`, `validation_failed`, `model_not_found`, `generation_failed`,
`storage_error`, `invalid_state`, …) build the right code/category; `raise_for_rac(rac_code)`
maps a negative `rac_result_t` back to an `ErrorCode` (preserving the raw ABI value as
`c_abi_code`). `is_expected` (cancellation) is the "don't log as an error" flag.

## Model catalog & download

`catalog.py` is a curated built-in `CATALOG` (`id -> CatalogEntry`) so callers can load by id
(`smollm2-360m`, `qwen2.5-1.5b`, `smolvlm-256m`, `minilm`, `whisper-base`, `piper-amy`, …)
instead of files. `download.py` is **stdlib-only** (`urllib`): it resolves a catalog id, a
direct http(s) URL, a HuggingFace repo (`owner/repo` or `owner/repo:file.gguf`, auto-picking a
GGUF + any mmproj + all shards of a split GGUF), or a local path; downloads with resume
(`.part` + `Range`), reports byte progress, safely extracts `.tar.bz2` archives (path-traversal
guarded), and dedups concurrent downloads to the same destination. STT/TTS/embedder loads
reject URL/HF sources (`assert_remote_supported`) because the remote resolver is
GGUF/single-file-only.
