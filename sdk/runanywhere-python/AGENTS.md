# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This SDK Is

`runanywhere` is the Python binding of the RunAnywhere on-device AI runtime. It runs LLM
text generation, VLM (vision-language) captioning, text embeddings, speech-to-text,
text-to-speech and voice-activity detection **entirely on the host** — no network is needed
for inference (only for downloading models). All the AI work lives in the C++
`runanywhere-commons` runtime, which is bound into a single pybind11 extension module
(`runanywhere._core`). Everything else in the package is idiomatic pure Python: a thin,
instantiable client over that core, model-handle wrappers, streaming bridges, a model
catalog + downloader, options/results dataclasses, an event bus, an error type, and audio /
grammar / structured-output helpers.

The **behavioral source of truth is the Electron SDK** (`sdk/runanywhere-electron`, the
N-API addon `addon.cpp` + its TypeScript surface). The native `module.cpp` is an exact
behavioral port of `addon.cpp` (same globals, handle maps, shutdown semantics, secure
store) translated Node-API → pybind11 with snake_case names; the Python modules port the
TypeScript facade (`RunAnywhere.ts`, `Chat.ts`, `VoiceAgent.ts`, `events.ts`, `errors.ts`)
class-for-class. When in doubt about semantics, match the Electron SDK.

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
runtime substitutes a recording fake for `_core` (see `tests/test_client.py`'s `FakeCore`).
This is possible because importing `runanywhere` never imports `_core` (see *Lazy-Load
Design* below).

```bash
# Run the whole suite
pytest tests

# One file / one test
pytest tests/test_client.py
pytest tests/test_client.py::test_context_manager_initializes_and_shuts_down -q
```

The tests prepend the package parent to `sys.path` themselves, so they run regardless of the
invocation cwd. They monkeypatch `runanywhere._native.get_core` to return the fake and reset
the process-wide native-lifecycle globals (`client._init_count`, `client._native_up`) around
each test so ordering never leaks between tests.

## Package Structure

```
sdk/runanywhere-python/
├── pyproject.toml            # scikit-build-core build config + project metadata
├── native/                   # the pybind11 extension source (compiled → _core)
│   ├── CMakeLists.txt        # ROOT-target module gated by RAC_BUILD_PYTHON_MODULE
│   ├── module.cpp            # binds the rac_* C ABI (port of Electron addon.cpp)
│   ├── win32_platform_adapter.{h,cpp}   # host fs/secure-store/clock/memory adapter (Windows; DPAPI)
│   └── posix_platform_adapter.{h,cpp}   # host fs/secure-store/clock/memory adapter (POSIX)
├── runanywhere/              # the importable pure-Python package
│   ├── __init__.py           # public surface; imports NO _core (direct or transitive)
│   ├── client.py             # the instantiable RunAnywhere client
│   ├── models.py             # LLMModel/VLMModel/Embedder/STTModel/TTSVoice/Vad handles
│   ├── chat.py               # Chat / ChatMessage (multi-turn)
│   ├── voice_agent.py        # VoiceAgent (STT → LLM → TTS)
│   ├── _streaming.py         # bridge native callback-per-token → sync/async iterators
│   ├── options.py            # *Options dataclasses + generate_kwargs assembly
│   ├── results.py            # result / value dataclasses (+ Synthesis NamedTuple)
│   ├── errors.py             # SDKException + ErrorCode/ErrorCategory
│   ├── events.py             # EventBus + event dataclasses + the singleton `bus`
│   ├── catalog.py            # curated built-in model catalog
│   ├── download.py           # stdlib-only (urllib) resolver/downloader
│   ├── grammar.py            # JSON-schema → GBNF grammar
│   ├── structured.py         # structured output + tool-call schema/prompt/parse
│   ├── stream_metrics.py     # wrap a token stream in LLMStreamEvent + metrics
│   ├── audio.py              # PCM/float/WAV helpers (numpy)
│   ├── py.typed              # PEP 561 marker (ships type hints)
│   └── _native/              # lazy loader for the compiled extension
│       ├── __init__.py       # get_core() — imports _core once, on demand
│       └── _core.pyi         # hand-written stub mirroring module.cpp exactly
└── tests/                    # pure-Python pytest suite (fakes the core)
```

Python target: **3.9+** (`requires-python = ">=3.9"`). The one runtime dependency is
`numpy>=1.21`; `pytest>=7` is the only test dependency. All HTTP is stdlib `urllib` — do NOT
add a third-party HTTP client.

## Architecture

### Layered design

```
Public API (runanywhere.__init__ re-exports)
    ↓
RunAnywhere client (client.py — instantiable, ref-counts the shared core)
    ↓
Model handle wrappers (models.py: LLMModel/VLMModel/Embedder/STTModel/TTSVoice/Vad)
    ↓
_native.get_core() → runanywhere._core (pybind11 extension)
    ↓
rac_* C ABI → runanywhere-commons (prebuilt/static-linked C++ runtime)
```

All business logic lives in C++. The Python layer is adaptation: lifecycle bookkeeping,
turning the blocking native token callback into Python iterators, host-side model download /
resolution, and the ergonomic composition helpers (chat / structured / tools / voice).

### Entry point — the instantiable client

Unlike the Swift SDK (a static `enum` namespace), `RunAnywhere` here is an **instantiable
class** (`client.py`), so tests and multi-tenant hosts can hold independent handles. A client
is inert until `initialize()` and is usable as a context manager (`__enter__` → `initialize`,
`__exit__` → `shutdown`). `initialize()` returns `self` so it can be chained
(`RunAnywhere().initialize()`).

### Shared-core ref-counting

The native core is a **single process-wide runtime**, so multiple `RunAnywhere` clients share
one instance. Module-level state in `client.py` — `_state_lock` (an `RLock`), `_init_count`,
`_native_up` — coordinates this: the first client to `initialize()` calls
`core.initialize(secure_dir, base_dir)` and emits `InitializedEvent` + `ServicesReadyEvent`;
later clients only bump the ref-count. On `shutdown()`, a client unloads the models it loaded,
decrements the ref-count, and only the last client down calls `core.shutdown()` and emits
`ShutdownEvent`. Events are emitted **outside** the lock so a listener cannot deadlock the
lifecycle. `initialize()`/`shutdown()` are idempotent per instance.

Default dirs: base = `~/.runanywhere`, secure = `<base>/secure` (mirrors the Electron facade
default), both overridable via the constructor.

### Model handles

Each `load_*` on the client resolves the model to concrete paths (downloading if needed),
calls the matching `core.load_*` to get an **opaque integer handle**, wraps it in a handle
class, weakly registers it (`WeakSet`) so client shutdown can unload it, and emits
`ModelLoadedEvent`. Handle classes (`models.py`) hold `(core, handle)` and expose the domain
API; each `unload()`/`close()` calls the matching `core.unload_*` and emits
`ModelUnloadedEvent`.

- `LLMModel` — `generate`/`agenerate` (token iterators), `generate_text`/`agenerate_text`,
  `generate_stream`/`agenerate_stream` (LLMStreamEvent + metrics), `generate_structured`,
  `generate_tool_call`, `generate_with_tools` (+ async twins). Composition helpers build on
  the single token stream with **no extra native calls**.
- `VLMModel` — `caption`/`acaption` + `_text` twins over an image path + prompt.
- `Embedder` — `embed(text) -> np.ndarray` (L2-normalized float32).
- `STTModel` — `transcribe(pcm16) -> str`; `atranscribe` runs it on the default executor.
- `TTSVoice` — `synthesize(text) -> Synthesis`; `asynthesize` on the executor.
- `Vad` — `detect`/`is_speech_active`/`set_threshold`/`reset`/`close` (built-in energy VAD).

### Single in-flight generation

`LLMModel`/`VLMModel` each hold a `_GenerationGuard` — a **non-blocking** lock. A second
concurrent `generate`/`caption` on the same model raises `SDKException.invalid_state`
immediately rather than deadlocking or queuing (a concurrent generate is a programming
error). The guard is held for the whole stream lifetime and released when the stream is
exhausted, broken out of, closed, or raises (`_guarded_iter` / `_aguarded_iter`).

### Streaming bridge

`_streaming.py` turns the blocking native streaming call (which invokes an
`on_token(str) -> bool | None` callback once per token, returning `False` to stop the C loop
early) into Python iterators:

- `iter_tokens` (sync) — runs `native_call` on a daemon worker thread; tokens cross to the
  consumer through a bounded `queue.Queue` (backpressure). On close/break/exception a
  `threading.Event` is set so the next `on_token` returns `False` and the C loop unwinds; the
  queue is drained (so a parked worker unblocks) and the worker joined. Worker exceptions are
  re-raised in the consumer.
- `aiter_tokens` (async) — same worker model, but hands each token to the running event loop
  via `loop.call_soon_threadsafe` into a bounded `asyncio.Queue`; the worker blocks on a
  `concurrent.futures.Future` until the token is accepted (backpressure). Teardown joins the
  worker off-loop via `run_in_executor` so it never blocks the event loop.

The GIL discipline lives on the C++ side: `generate`/`generate_vlm` release the GIL around
the blocking `rac_*_generate_stream` and re-acquire it inside the token callback; all other
blocking calls release the GIL only around the C call and build numpy/str/tuple results with
the GIL held.

### Options → native kwargs

`options.py` defines the `*Options` dataclasses. Only a fixed key set
(`max_tokens`, `temperature`, `top_p`, `top_k`, `system_prompt`, `grammar`) is forwarded to
`core.generate`; `generate_kwargs` keeps only those known keys whose value is non-`None`
(a `None` means "unset" so the backend applies its own default). Generation options are
passed as loose `**opts` kwargs through the handle methods.

### Structured output, grammar & tools

`grammar.py` compiles a JSON schema to a GBNF grammar (`json_schema_to_grammar`);
`structured.py` builds `object_grammar`, the tool-call schema/prompt, parses model output
(`parse_structured`), and defines `ToolSpec`/`ToolCall`/`ToolRun`. `generate_structured`
constrains decoding to the schema's grammar and returns the parsed object;
`generate_tool_call` forces a well-formed `{name, arguments}`; `generate_with_tools` also runs
the selected tool's `execute` (awaited if it returns a coroutine, in the async variant).

### Event system

`events.py` is a small typed pub/sub `EventBus` where a throwing listener never breaks an
emit. Event types are frozen dataclasses (`InitializedEvent`, `ServicesReadyEvent`,
`ShutdownEvent`, `ModelLoadedEvent`, `ModelUnloadedEvent`, `GenerationEvent`); the union is
`RunAnywhereEvent`. A single process-wide singleton `bus` is exposed as
`RunAnywhere.events`. Subscribe with `bus.on(listener) -> off` (or `once`).

### Error system

`errors.py` defines `SDKException` (the single throwable) carrying a canonical `code`
(`ErrorCode`) + `category` (`ErrorCategory`) for cross-SDK-uniform handling, mirroring the
Swift/Kotlin/RN/Web/Electron SDKs. `category_for_code` is a verbatim port of the commons
range table (keep in sync). Category-specific static factories (`not_initialized`,
`validation_failed`, `model_not_found`, `generation_failed`, `invalid_state`, …) build the
right code/category; `raise_for_rac(rac_code)` maps a negative `rac_result_t` back to an
`ErrorCode` (preserving the raw ABI value as `c_abi_code`). `is_expected` (cancellation) is
the "don't log as an error" flag.

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
- Keep behavior faithful to the Electron SDK; only translate to idiomatic Python.

## Commit Style

- **One file per commit** — single-file commits, not batched.
- **Short, direct messages** — terse subject, no fluff.
- **No author/co-author trailer** — do not append `Co-Authored-By:` or any author line.

## Key File Locations

| File | Purpose |
|------|---------|
| `runanywhere/client.py` | The instantiable `RunAnywhere` client; shared-core ref-counting, lifecycle, load paths |
| `runanywhere/_native/__init__.py` | `get_core()` — the single lazy door to the extension |
| `runanywhere/_native/_core.pyi` | Hand-written stub mirroring `native/module.cpp` |
| `native/module.cpp` | pybind11 bindings of the `rac_*` C ABI (port of Electron `addon.cpp`) |
| `native/CMakeLists.txt` | `RAC_BUILD_PYTHON_MODULE`-gated `runanywhere_core` target |
| `runanywhere/models.py` | Loaded-model handle classes + `_GenerationGuard` |
| `runanywhere/_streaming.py` | Native callback-per-token → sync/async iterators |
| `runanywhere/download.py` | urllib resolver/downloader (catalog / URL / HF / local) |
| `runanywhere/errors.py` | `SDKException`, `ErrorCode`, `ErrorCategory`, `raise_for_rac` |
| `runanywhere/events.py` | `EventBus` + event dataclasses + the singleton `bus` |
| `pyproject.toml` | scikit-build-core build + project metadata |
| `tests/test_client.py` | `FakeCore` pattern for native-free tests |
