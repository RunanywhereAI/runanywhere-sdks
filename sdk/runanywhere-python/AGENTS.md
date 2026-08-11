# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This SDK Is

`runanywhere` is the Python binding of the RunAnywhere on-device AI runtime. It runs LLM
text generation, VLM (vision-language) captioning, text embeddings, speech-to-text,
text-to-speech and voice-activity detection **entirely on the host** — no network is needed
for inference (only for downloading models). All the AI work lives in the C++
`runanywhere-commons` runtime, which is bound into a single pybind11 extension module
(`runanywhere._core`). Everything else in the package is idiomatic pure Python: the public
namespaces, an internal runtime + model-handle layer, streaming bridges, a model catalog +
downloader, options/results dataclasses, an event bus, an error type, and audio / grammar /
structured-output helpers.

**The public surface is defined by `thoughts/shared/plans/public_api_spec.md` (v3)** — the
same namespaces, verbs, option fields, defaults, event grammar and result fields as every
other SDK, with Python casing (snake_case) and `a`-prefixed async twins. Swift is the
cross-SDK reference when the spec is ambiguous.

The **behavioral bridge reference is the Electron SDK** (`sdk/runanywhere-electron`,
N-API `addon.cpp`) for handle maps, streaming, and secure-store shape. **Product /
business-logic truth is C++ commons.** The native `module.cpp` is an exact behavioral port
of `addon.cpp` (same globals, handle maps, shutdown semantics, secure store) translated
Node-API → pybind11 with snake_case names. When in doubt about AI semantics, match
commons/Swift — not a stale Electron shortcut.

## Build Commands

The native `_core` extension is gated behind `RAC_BUILD_PYTHON_MODULE` (OFF by default so
ordinary commons builds are unaffected). The wheel build is driven by scikit-build-core,
which invokes CMake at the repo root with the backends turned on.

```bash
# Build + install the wheel (compiles _core via scikit-build-core → CMake)
pip install .

# Editable install for development
pip install -e .

# Install with test extras
pip install -e ".[test]"

# Build a wheel without installing
python -m build --wheel

# Direct CMake build of just the extension (from the repo root), e.g. for iteration:
cmake -B build -DRAC_BUILD_PYTHON_MODULE=ON -DRAC_BUILD_BACKENDS=ON \
      -DRAC_STATIC_PLUGINS=ON -DRAC_BUILD_SHARED=OFF -DRAC_BUILD_PLATFORM=OFF \
      -DCMAKE_BUILD_TYPE=Release
cmake --build build --target runanywhere_core
# then point the loader at the out-of-tree build:
export RUNANYWHERE_NATIVE_PATH=/path/to/build/.../runanywhere/_native   # (Windows: set)
```

`pyproject.toml` fixes the CMake defines (`RAC_BUILD_PYTHON_MODULE=ON`,
`RAC_BUILD_BACKENDS=ON`, `RAC_STATIC_PLUGINS=ON`, `RAC_BUILD_SHARED=OFF`,
`RAC_BUILD_PLATFORM=OFF`, `CMAKE_BUILD_TYPE=Release`) and builds only the `runanywhere_core`
target. The compiled extension installs into `runanywhere/_native/` (its `install-dir`), so
it lands next to the lazy loader that imports it.

## Running Tests

The test suite is **pure Python and needs no native build** — every test that touches the
runtime substitutes a recording fake for `_core` (`tests/fake_core.py`). This is possible
because importing `runanywhere` never imports `_core` (see *Lazy-Load Design* below).

```bash
# Run the whole suite
pytest tests

# One file / one test
pytest tests/test_llm.py
pytest tests/test_llm.py::test_generate_returns_text_and_metrics -q
```

The tests prepend the package parent to `sys.path` themselves, so they run regardless of the
invocation cwd. Two fixtures in `conftest.py` do the setup: `fake_core` monkeypatches
`runanywhere._native.get_core` and resets the process-wide `runtime` + event bus around every
test, and `sdk` layers `initialize()`/`reset()` with `RUNANYWHERE_HOME` inside `tmp_path` on
top of it. `tests/test_smoke.py` is the only module that touches the real native core, and it
skips itself unless the extension loads and the model it needs is already cached.

## Package Structure

```text
sdk/runanywhere-python/
├── pyproject.toml            # scikit-build-core build config + project metadata
├── native/                   # the pybind11 extension source (compiled → _core)
│   ├── CMakeLists.txt        # ROOT-target module gated by RAC_BUILD_PYTHON_MODULE
│   ├── module.cpp            # binds the rac_* C ABI (port of Electron addon.cpp)
│   ├── win32_platform_adapter.{h,cpp}   # host fs/secure-store/clock/memory adapter (Windows; DPAPI)
│   └── posix_platform_adapter.{h,cpp}   # host fs/secure-store/clock/memory (POSIX; plaintext 0600)
├── runanywhere/              # the importable pure-Python package
│   ├── __init__.py           # initialize/reset/is_ready + the namespaces; imports NO _core
│   ├── api/                  # THE public surface — one module per namespace
│   │   ├── __init__.py       # re-exports the namespace singletons
│   │   ├── _common.py        # prompt/messages assembly shared by llm and vlm
│   │   ├── llm.py            # llm.generate/generate_stream/generate_structured + llm.tools
│   │   ├── vlm.py  stt.py  tts.py  vad.py  embeddings.py  rerank.py
│   │   ├── images.py  diarization.py  segmentation.py  lora.py  voice.py
│   │   ├── rag.py            # rag.open + RagSession
│   │   └── models.py         # models.list/get/register/download/delete/load/unload/state
│   ├── _runtime.py           # INTERNAL: native lifecycle + one resident model per category
│   ├── _handles.py           # INTERNAL: LLMModel/VLMModel/Embedder/STTModel/TTSVoice/Vad
│   ├── _generation.py        # INTERNAL: token stream → GenerationEvent grammar + metrics
│   ├── _options_bridge.py    # INTERNAL: LlmOptions → native kwargs; refuse unbound fields
│   ├── _rag_bridge.py        # INTERNAL: proto (de)serialization for the RAG C ABI
│   ├── _streaming.py         # bridge native callback-per-token → sync/async iterators
│   ├── inputs.py             # AudioInput/ImageInput/ChatMessage/ModelRef/RagDocument/…
│   ├── options.py            # *Options dataclasses (v3 field names and defaults)
│   ├── results.py            # result / value dataclasses with the shared metrics block
│   ├── errors.py             # SDKException + ErrorCode/ErrorCategory
│   ├── events.py             # EventBus + the event dataclasses + the singleton `bus`
│   ├── catalog.py            # curated built-in model catalog
│   ├── download.py           # stdlib-only (urllib) resolver/downloader
│   ├── grammar.py            # JSON-schema → GBNF grammar
│   ├── structured.py         # structured output + tool-call schema/prompt/parse
│   ├── audio.py              # PCM/float/WAV helpers (numpy)
│   ├── cli/                  # the `runanywhere` CLI over the namespaces
│   ├── __main__.py           # CLI entry shim (`python -m runanywhere`)
│   ├── server/               # OpenAI-compatible HTTP server — OPTIONAL [server] extra
│   │   ├── __init__.py       # create_app + serve (uvicorn lazy-imported)
│   │   ├── schemas.py        # pydantic request models
│   │   ├── errors.py         # SDK ErrorCode → HTTP status + OpenAI error body
│   │   ├── manager.py        # lazy multi-model load/cache (no fastapi import)
│   │   └── app.py            # routes: chat/completions/embeddings/audio/models/health
│   ├── py.typed              # PEP 561 marker (ships type hints)
│   └── _native/              # lazy loader for the compiled extension
│       ├── __init__.py       # get_core() — imports _core once, on demand
│       └── _core.pyi         # hand-written stub mirroring module.cpp exactly
└── tests/                    # pure-Python pytest suite (fakes the core)
```

Python target: **3.9+** (`requires-python = ">=3.9"`). The one runtime dependency is
`numpy>=1.21`; `pytest>=7` is the only test dependency. All HTTP is stdlib `urllib` — do NOT
add a third-party HTTP client. The `server/` subpackage is the sole exception: it needs the
optional `[server]` extra (fastapi/uvicorn) and MUST NOT be imported by `runanywhere/__init__.py`
(it would break the fastapi-free, native-lazy import invariant). `tests/test_server.py` gates
itself with `pytest.importorskip("fastapi")`.

## Architecture

### Layered design

```text
Public API — runanywhere.initialize + the namespaces (runanywhere/api/*)
    ↓
_runtime.Runtime (process-wide native lifecycle + one resident model per category)
    ↓
_handles (LLMModel/VLMModel/Embedder/STTModel/TTSVoice/Vad — opaque int handles)
    ↓
_native.get_core() → runanywhere._core (pybind11 extension)
    ↓
rac_* C ABI → runanywhere-commons (prebuilt/static-linked C++ runtime)
```

All business logic lives in C++. The Python layer is adaptation: lifecycle bookkeeping,
turning the blocking native token callback into Python iterators, host-side model download /
resolution, and the composition the spec puts behind one verb (messages → prompt, the tool
loop, structured parsing).

### Entry point — module-level, one call

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

### The process-wide runtime

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

### Model handles (internal)

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

### Namespace conventions

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

### Single in-flight generation

`LLMModel`/`VLMModel` each hold a `_GenerationGuard` — a **non-blocking** lock. A second
concurrent `generate` on the same model raises `SDKException.invalid_state`
immediately rather than deadlocking or queuing (a concurrent generate is a programming
error). The guard is held for the whole stream lifetime and released when the stream is
exhausted, broken out of, closed, or raises (`_guarded_iter` / `_aguarded_iter`).

### Streaming bridge

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

### Options → native kwargs

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

### Structured output, grammar & tools

`structured.py` forwards typed schema/options to commons and parses the typed result.
`llm.generate_structured` returns a `StructuredResult` (`valid=False` with the raw text when
validation fails rather than raising); grammar compilation and repair remain in commons.
Tools go through `llm.tools.register(tool, executor)`: `llm.generate` runs the
loop, executing the matched tool (awaiting a coroutine result) and feeding the observation
back, up to `max_tool_calls`. The loop also stops early when the model repeats a call with
identical arguments, since that makes no further progress. A call with no registered executor
finishes the stream with `finish_reason=TOOL_CALLS` so the caller can run it.

### Event system

`events.py` is a small typed pub/sub `EventBus` where a throwing listener never breaks an
emit. Each event family is one dataclass carrying a `kind` (`GenerationEvent`,
`TranscriptionEvent`, `VadEvent`, `RagEvent`, `ImageEvent`, `DownloadEvent`, `VoiceEvent`,
`SdkEvent`), so consumers switch on `kind` instead of isinstance chains. The stream events are
returned by the verbs; only `SdkEvent` (ready / model loaded / model unloaded / error) goes
through the process-wide singleton `bus`, exposed as `runanywhere.events`. Subscribe with
`bus.on(listener) -> off` (or `once`).

### Error system

`errors.py` defines `SDKException` (the single throwable) carrying a canonical `code`
(`ErrorCode`, exhaustive vs `idl/errors.proto`) + `category` (`ErrorCategory`) for
cross-SDK-uniform handling. `category_for_code` is a faithful port of commons
`rac_result_to_proto_category` (keep in sync). Category-specific static factories
(`not_initialized`, `validation_failed`, `model_not_found`, `generation_failed`,
`storage_error`, `invalid_state`, …) build the right code/category; `raise_for_rac(rac_code)`
maps a negative `rac_result_t` back to an `ErrorCode` (preserving the raw ABI value as
`c_abi_code`). `is_expected` (cancellation) is the "don't log as an error" flag.

### Model catalog & download

`catalog.py` is a curated built-in `CATALOG` (`id -> CatalogEntry`) so callers can load by id
(`smollm2-360m`, `qwen2.5-1.5b`, `smolvlm-256m`, `minilm`, `whisper-base`, `piper-amy`, …)
instead of files. `download.py` is **stdlib-only** (`urllib`): it resolves a catalog id, a
direct http(s) URL, a HuggingFace repo (`owner/repo` or `owner/repo:file.gguf`, auto-picking a
GGUF + any mmproj + all shards of a split GGUF), or a local path; downloads with resume
(`.part` + `Range`), reports byte progress, safely extracts `.tar.bz2` archives (path-traversal
guarded), and dedups concurrent downloads to the same destination. STT/TTS/embedder loads
reject URL/HF sources (`assert_remote_supported`) because the remote resolver is
GGUF/single-file-only.

## Lazy-Load Design (important)

**Importing `runanywhere` does NOT load the compiled `_core` extension.** Every pure-Python
module stays importable — and the whole test suite runs — without a native build. This is a
hard invariant:

- `runanywhere/__init__.py` must import **no** `_core`, directly or transitively. Its module
  docstring says so; do not break it (e.g. don't add a top-level `from ._native import _core`
  anywhere on the import path of `__init__`).
- The only door to the extension is `runanywhere._native.get_core()`. It is called lazily on
  the **first** `RunAnywhere.initialize()` (and by the client's load paths via the same cached
  core). On first call it: adds the native dir to the DLL search path on Windows
  (`os.add_dll_directory`, so `onnxruntime.dll` and the bundled sherpa/llama DLLs resolve),
  honours the `RUNANYWHERE_NATIVE_PATH` override (load an out-of-tree build by file path),
  imports `_core`, caches it, and raises `SDKException` (category IO) on failure — with a
  message that hints the module may not be built or a dependent DLL is missing.
- Tests exploit this by monkeypatching `get_core` to return a `FakeCore`.

`_native/_core.pyi` is a hand-written stub that mirrors `native/module.cpp`'s bound surface
exactly (snake_case, opaque `int` handles). **When you change a binding in `module.cpp`,
update `_core.pyi` in the same change.**

### Runtime env vars

- **`RUNANYWHERE_NATIVE_PATH`** — load an out-of-tree `_core` (a build-dir path), instead of
  the one bundled in `runanywhere/_native/`.
- **`RUNANYWHERE_LOG_LEVEL`** — `trace`/`debug`/`info`/`warning`/`error`/`fatal`. The native
  runtime's logger defaults to **`warning`** here (it would otherwise default to `info` and
  flood stderr on every load/generate); set `info`/`debug` to see the full native logs.

## Cross-Platform Notes

- **Windows** is the first-class target (the M0 harness proved the full static-lib set links
  on MSVC). `native/CMakeLists.txt` selects `win32_platform_adapter.cpp`, links `Crypt32`,
  re-adds the bundled-libs `link_directories` (libarchive/zlib statics leak as bare names on
  MSVC), and compiles with `/EHsc /Zc:__cplusplus /utf-8 /bigobj`. The loader adds the native
  dir to the DLL search path so co-located runtime DLLs resolve.
- **POSIX** uses `posix_platform_adapter.cpp`; the module resolves its co-located bundled
  shared libs via rpath (`$ORIGIN` on Linux, `@loader_path` on macOS) — the loader does no
  DLL-path manipulation there.
- The native extension + its bundled runtime libraries ship inside `runanywhere/_native/`
  (the wheel `install-dir`). `cibuildwheel` repairs wheels per platform (`delvewheel` on
  Windows, `auditwheel` on Linux, `delocate` on macOS) to vendor those runtime libs.
- Path handling is host-agnostic: `download.is_remote_source` treats a Windows drive path or
  a backslash path as local, and archive extraction is path-traversal safe on any OS.

## Conventions

- **Every module opens with a one-line docstring** and `from __future__ import annotations`.
- Full type hints on public functions/methods; `@dataclass` for structured types;
  `snake_case` functions/methods, `PascalCase` classes, `UPPER_SNAKE` constants; ~100-column
  lines. **No shebang, no SPDX header** on library modules.
- Prefer the stdlib; `numpy` is available; **do not** add a third-party HTTP client — HTTP is
  `urllib`.
- Async twins are prefixed `a` (`generate`/`agenerate`, `send`/`asend`,
  `process_turn`/`aprocess_turn`).
- Blocking native calls that aren't token-streamed (`transcribe`, `synthesize`) get an async
  twin via `loop.run_in_executor(None, …)`.
- Errors: raise `SDKException` (via its factories) only — never a bare `Exception` on the
  public surface.
- Keep the public surface in sync: anything meant to be public is imported and listed in
  `runanywhere/__init__.py`'s `__all__`, and re-exported from its module's `__all__`.
- Keep the native bridge behavior aligned with the Electron addon when they intentionally
  mirror each other; **business logic truth is C++ commons** (Swift is the cross-SDK
  reference for product semantics).

## Python SDK Best Practices

Adapted from `thoughts/shared/plans/BEST_PRACTISES.md` for this package. Follow these on
every change; they are the bar for review.

### Ownership and layering

- **C++ commons owns truth** for inference, model lifecycle, registry, RAG, cancel, and
  error categories. Python must not re-implement those rules in the facade.
- The Python layer owns: platform adapter I/O, pybind11 bridging, host download/catalog,
  streaming fan-out (`_streaming.py`), the composition the spec puts behind one verb
  (messages, grammar, the tool loop), the CLI/server, and honesty in docs/API surface.
- Keep routers/handlers thin. `runanywhere/server/` and `runanywhere/cli/` are adaptation
  over the namespaces — no new AI business logic in a FastAPI route or a CLI handler. If a
  command needs multi-step orchestration, push it into the namespace or into commons.
- One verb per job. `llm.generate` loads and downloads what it needs; never make a caller
  assemble register → download → load themselves.

### Typed contracts at every boundary

- Public options/results are dataclasses or IntEnums — never raw string status codes.
- Native error codes come from `idl/errors.proto` / `rac_error.h`. Keep `ErrorCode` /
  `ErrorCategory` exhaustive relative to the IDL and map categories with
  `category_for_code` as a faithful port of commons `rac_result_to_proto_category`
  (AUTH is only 320–329; unmapped failures → INTERNAL, not UNSPECIFIED).
- Registry framework/category ints are **C ABI enums** (`RAC_FRAMEWORK_*`,
  `RAC_MODEL_CATEGORY_*`), not proto wire values. Name them and pin them in tests.
- Generated RAG protos live in `runanywhere/_proto/`; regenerate via
  `idl/codegen/generate_python.sh` (wired into `generate_all.sh`). Never hand-edit
  `_pb2.py`.
- Keep `_native/_core.pyi` in lockstep with `native/module.cpp` bindings.

### Honesty and readiness

- Document what is actually true today. Do not claim encryption, remote auth, or NPU
  support that is not wired.
  - Secure store: DPAPI on Windows; **plaintext mode-0600 files on POSIX**.
  - `initialize` runs the control plane only with credentials: authenticate + telemetry flush
    over a stdlib-`urllib` transport (no libcurl). Keyless, it does no network work;
    `api_key`/`base_url` map to that handshake. The HTTP server's optional Bearer `api_key`
    is a separate thing, configured on `serve()` / the CLI.
  - Desktop wheels report CPU backends (llamacpp/onnx/sherpa). QHexRT/Windows Snapdragon
    HNPU is not available until packaging and runtime exist.
- A verb the bridge cannot serve raises `not_implemented` naming the exact missing `rac_*`
  symbols. Never return a plausible empty result instead.
- If a capability cannot be done properly (missing HTTP transport, lifecycle migration),
  document it as deferred — do not stub or mock it into the public surface.

### Concurrency and native safety

- Every modality unload that can race an in-flight op uses `take_handle_when_idle`
  (including VAD). Blocking ops take `begin_op` / `OpScope` leases.
- Stream teardown must set the stop `Event` **and** call component cancel
  (`cancel_generate` / `cancel_generate_vlm`) via `_streaming.on_stop` so decode stops
  promptly, not only on the next token callback.
- One in-flight generation per model handle (`_GenerationGuard`); a second concurrent
  generate is a programming error → `invalid_state`, not a silent queue.
- Win32 file sizing uses `_fseeki64` / `_ftelli64` (plain `ftell`/`long` truncates >2GB).
- Secure-store keys must reject path separators / `..` / absolute paths (`secure_key_ok`
  + Python `_validate_secure_key`).

### Errors and observability

- Raise `SDKException` only on the public surface; map I/O/download failures to
  `STORAGE_ERROR` (or the correct category), not `GENERATION_FAILED`.
- Prefer factories (`storage_error`, `model_load_failed`, …) so code/category stay
  consistent.
- Never log secrets, secure-store values, or signed URLs alongside destination paths.
- EventBus listeners must not break emit — failures are swallowed/logged, not re-raised
  into the lifecycle path.

### Testing

- Hermetic by default: `FakeCore` / no network / no real keys / no models required for
  the unit suite.
- Pin ABI and category tables with tests so silent drift fails CI.
- CI builds a wheel, repairs it, installs into a clean env, and runs pytest from a
  relocated `tests/` dir — local verification should match that shape when touching
  packaging.
- Support the claimed Python range (3.9+); Linux CI matrices both 3.9 and 3.12.

### Security basics

- Validate all external inputs (URLs, archive members, secure keys, model ids).
- SSRF: connect-by-IP, no open redirects on host download paths.
- Do not require cloud credentials to initialize or run unit tests.
- Treat AI output as untrusted: structured/tool paths parse and validate before use.

### Anti-patterns (do not)

- Re-implement commons business logic in Python “for convenience”.
- Hand-write error codes or framework ints that diverge from IDL/C ABI.
- Leave dead constructor knobs that imply remote auth.
- Claim “encrypted secure store” on POSIX.
- Use `generation_failed` for disk/tar/HTTP I/O.
- Unload with plain `take_handle` while another thread may still be inside `rac_*`.
- Add mock/stub public APIs for unfinished capabilities.
- Mount server admin/eval shortcuts without an explicit, documented opt-in.

### Definition of done (Python SDK change)

- Typed public API (dataclasses / IntEnums / stubs updated).
- Errors are structured `SDKException`s with correct categories.
- Native leases/cancel/unload paths stay race-safe.
- Hermetic tests cover the new behavior (or explicitly skip with reason).
- Docs/AGENTS/README honesty matches reality.
- IDL/proto regen committed when schemas change; drift CI stays green.

## Commit Style

- Prefer **one logical change per commit** (thematic multi-file OK when one concern).
- **Short, direct messages** — terse subject, no fluff.
- **No author/co-author trailer** — do not append `Co-Authored-By:` or any author line.

## Key File Locations

| File | Purpose |
|------|---------|
| `runanywhere/__init__.py` | `initialize`/`reset`/`is_ready`/`version`/`device_id` + every public re-export |
| `runanywhere/api/` | The public namespaces, one module per modality |
| `runanywhere/_runtime.py` | Native lifecycle + the resident model per category + resolution |
| `runanywhere/_handles.py` | Loaded-model handle classes + `_GenerationGuard` |
| `runanywhere/_generation.py` | Token stream → event grammar, metrics, thinking split, stop sequences |
| `runanywhere/_options_bridge.py` | `LlmOptions` → native kwargs; refuses knobs the bridge lacks |
| `runanywhere/_native/__init__.py` | `get_core()` — the single lazy door to the extension |
| `runanywhere/_native/_core.pyi` | Hand-written stub mirroring `native/module.cpp` |
| `native/module.cpp` | pybind11 bindings of the `rac_*` C ABI (port of Electron `addon.cpp`) |
| `native/CMakeLists.txt` | `RAC_BUILD_PYTHON_MODULE`-gated `runanywhere_core` target |
| `runanywhere/_streaming.py` | Native callback-per-token → sync/async iterators (+ `on_stop` cancel hook) |
| `runanywhere/download.py` | urllib resolver/downloader (catalog / URL / HF / local) |
| `runanywhere/errors.py` | `SDKException`, exhaustive `ErrorCode`, `ErrorCategory`, `raise_for_rac` |
| `runanywhere/events.py` | Event dataclasses + `EventBus` + the singleton `bus` |
| `runanywhere/_rag_bridge.py` | Proto (de)serialization for the RAG C ABI |
| `pyproject.toml` | scikit-build-core build + project metadata |
| `tests/fake_core.py` | The recording `FakeCore` behind every native-free test |
| `tests/conftest.py` | The `fake_core` / `sdk` fixtures + the native/model skip gates |
