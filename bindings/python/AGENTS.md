# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
directory. See the repo-root `AGENTS.md` first for cross-SDK rules (business-logic layering,
version management, CI) — this file only covers what's specific to the Python binding.

## What this SDK is

`runanywhere` is the Python binding of the RunAnywhere on-device AI runtime: LLM text
generation, VLM captioning, embeddings, STT, TTS and VAD, all running **entirely on the
host** (network is only used to download models). All AI logic lives in the C++
`runanywhere-commons` runtime, bound into one pybind11 extension (`runanywhere._core`).
Everything else here is pure Python: the public namespaces, an internal runtime +
model-handle layer, streaming bridges, a model catalog/downloader, options/results
dataclasses, an event bus, an error type, and audio/grammar/structured-output helpers.

The public surface is defined by `thoughts/shared/plans/public_api_spec.md` (v3) — same
namespaces/verbs/fields/event-grammar as every other SDK, with Python snake_case and
`a`-prefixed async twins. **Swift is the cross-SDK reference** when the spec is ambiguous.
`native/module.cpp` is a behavioral port of the Electron addon (`bindings/electron/addon.cpp`)
translated Node-API → pybind11 — match commons/Swift semantics, not a stale Electron shortcut.

## Build commands

The native `_core` extension is gated behind `RAC_BUILD_PYTHON_MODULE` (OFF by default, so
ordinary commons builds are unaffected). scikit-build-core drives CMake at the repo root.

```bash
pip install .                    # build + install the wheel (compiles _core)
pip install -e .                 # editable install for development
pip install -e ".[test]"         # + test extras

python -m build --wheel          # build a wheel without installing

# Direct CMake build of just the extension, for iteration:
cmake -B build -DRAC_BUILD_PYTHON_MODULE=ON -DRAC_BUILD_BACKENDS=ON \
      -DRAC_STATIC_PLUGINS=ON -DRAC_BUILD_SHARED=OFF -DRAC_BUILD_PLATFORM=OFF \
      -DCMAKE_BUILD_TYPE=Release
cmake --build build --target runanywhere_core
export RUNANYWHERE_NATIVE_PATH=/path/to/build/.../runanywhere/_native   # (Windows: set)
```

`pyproject.toml` pins those same CMake defines and builds only `runanywhere_core`. The
compiled extension installs into `runanywhere/_native/` (`wheel.install-dir`), next to the
lazy loader that imports it. QHexRT/CUDA are opt-in build flags
(`-C cmake.define.RAC_BACKEND_QHEXRT=ON`, `RAC_GPU_CUDA=ON`) producing separate distributions,
not part of the default PyPI wheel.

## Running tests

The suite is **pure Python and needs no native build** — every test that touches the runtime
substitutes a recording fake for `_core` (`tests/fake_core.py`), which works because importing
`runanywhere` never imports `_core` (see *Lazy-load design* below).

```bash
pytest tests                                                          # whole suite
pytest tests/test_llm.py                                              # one file
pytest tests/test_llm.py::test_generate_returns_text_and_metrics -q   # one test
```

`conftest.py` provides two fixtures: `fake_core` monkeypatches
`runanywhere._native.get_core` and resets the process-wide `runtime` + event bus around every
test; `sdk` layers `initialize()`/`reset()` with `RUNANYWHERE_HOME` inside `tmp_path` on top
of it. `tests/test_smoke.py` is the only module touching the real native core — it skips
itself unless the extension is built and the model it needs is already cached.

## Package structure

```text
bindings/python/
├── pyproject.toml            # scikit-build-core build config + project metadata
├── native/                   # pybind11 extension source (compiled → _core)
│   ├── module.cpp            # binds the rac_* C ABI (port of Electron addon.cpp)
│   ├── win32_platform_adapter.{h,cpp}   # host fs/secure-store/clock/memory (Windows; DPAPI)
│   └── posix_platform_adapter.{h,cpp}   # host fs/secure-store/clock/memory (POSIX; plaintext 0600)
├── runanywhere/               # the importable pure-Python package
│   ├── __init__.py            # initialize/reset/is_ready + the namespaces; imports NO _core
│   ├── api/                   # THE public surface — one module per namespace
│   │   ├── llm.py  vlm.py  stt.py  tts.py  vad.py  embeddings.py  rerank.py
│   │   ├── images.py  diarization.py  segmentation.py  lora.py  voice.py
│   │   ├── rag.py             # rag.open + RagSession
│   │   └── models.py          # models.list/get/register/download/delete/load/unload/state
│   ├── _runtime.py            # INTERNAL: native lifecycle + one resident model per category
│   ├── _handles.py            # INTERNAL: LLMModel/VLMModel/Embedder/STTModel/TTSVoice/Vad
│   ├── _generation.py         # INTERNAL: token stream → GenerationEvent grammar + metrics
│   ├── _options_bridge.py     # INTERNAL: LlmOptions → native kwargs; refuse unbound fields
│   ├── _rag_bridge.py         # INTERNAL: proto (de)serialization for the RAG C ABI
│   ├── _streaming.py          # bridge native callback-per-token → sync/async iterators
│   ├── options.py / results.py / errors.py / events.py / inputs.py
│   ├── catalog.py             # curated built-in model catalog
│   ├── download.py            # stdlib-only (urllib) resolver/downloader
│   ├── audio.py               # audio DSP + WAV codec, thin forwards to commons rac_audio_*
│   ├── structured.py          # structured output + tool-call schema/prompt/parse
│   ├── cli/                   # the `runanywhere` CLI over the namespaces
│   ├── server/                # OpenAI-compatible HTTP server — OPTIONAL [server] extra;
│   │                          # MUST NOT be imported by __init__.py (breaks the fastapi-free invariant)
│   └── _native/                # lazy loader for the compiled extension
│       ├── __init__.py         # get_core() — imports _core once, on demand
│       └── _core.pyi           # hand-written stub mirroring module.cpp exactly
└── tests/                     # pure-Python pytest suite (fakes the core)
```

Python target **3.9+**. Runtime dependency: `numpy>=1.21` only. All HTTP is stdlib `urllib` —
do NOT add a third-party HTTP client. `server/` is the sole exception, needing the optional
`[server]` extra (fastapi/uvicorn); `tests/test_server.py` gates itself with
`pytest.importorskip("fastapi")`.

## Architecture

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

All business logic lives in C++. Python is adaptation: lifecycle bookkeeping, turning the
blocking native token callback into Python iterators, host-side model download/resolution,
and the composition the spec puts behind one verb (messages → prompt, the tool loop,
structured parsing). **Full per-component detail (entry point, the runtime singleton, model
handles, streaming bridge GIL discipline, options bridge, events, errors, catalog/download) is
in [`docs/reference/architecture.md`](docs/reference/architecture.md)** — read it before
touching any of those files.

## Lazy-load design (important)

**Importing `runanywhere` does NOT load the compiled `_core` extension.** Every pure-Python
module stays importable — and the whole test suite runs — without a native build. This is a
hard invariant:

- `runanywhere/__init__.py` must import **no** `_core`, directly or transitively.
- The only door to the extension is `runanywhere._native.get_core()`, called lazily on the
  first `initialize()`. It adds the native dir to the DLL search path on Windows
  (`os.add_dll_directory`), honours `RUNANYWHERE_NATIVE_PATH` (load an out-of-tree build),
  imports `_core`, caches it, and raises `SDKException` (category IO) on failure.
- Tests exploit this by monkeypatching `get_core` to return a `FakeCore`.

`_native/_core.pyi` is a hand-written stub mirroring `native/module.cpp`'s bound surface
exactly (snake_case, opaque `int` handles). **When you change a binding in `module.cpp`,
update `_core.pyi` in the same change.**

Runtime env vars: **`RUNANYWHERE_NATIVE_PATH`** loads an out-of-tree `_core` build by path;
**`RUNANYWHERE_LOG_LEVEL`** (`trace`/`debug`/`info`/`warning`/`error`/`fatal`) — the native
logger defaults to `warning` here (would otherwise default to `info` and flood stderr on
every load/generate).

## Cross-platform notes

- **Windows**: `native/CMakeLists.txt` selects `win32_platform_adapter.cpp`, links `Crypt32`,
  and compiles with `/EHsc /Zc:__cplusplus /utf-8 /bigobj`; the loader adds the native dir to
  the DLL search path.
- **POSIX**: `posix_platform_adapter.cpp`; co-located bundled shared libs resolve via rpath
  (`$ORIGIN` on Linux, `@loader_path` on macOS) — no DLL-path manipulation.
- The native extension + bundled runtime libs ship inside `runanywhere/_native/` (the wheel
  `install-dir`). `cibuildwheel` repairs wheels per platform (`delvewheel`/`auditwheel`/
  `delocate`). See [`PACKAGING.md`](PACKAGING.md) for the full release/publish checklist.
- `download.is_remote_source` treats a Windows drive path or backslash path as local; archive
  extraction is path-traversal safe on any OS.

## Conventions

- Every module opens with a one-line docstring and `from __future__ import annotations`.
- Full type hints; `@dataclass` for structured types; `snake_case`/`PascalCase`/`UPPER_SNAKE`;
  ~100-column lines. No shebang, no SPDX header on library modules.
- Prefer the stdlib; `numpy` is available; **never** add a third-party HTTP client.
- Async twins are prefixed `a` (`generate`/`agenerate`); blocking calls that aren't
  token-streamed (`transcribe`, `synthesize`) get one via `loop.run_in_executor(None, …)`.
- Raise `SDKException` (via its factories) only — never a bare `Exception` on the public
  surface. A verb the bridge cannot serve raises `not_implemented` naming the exact missing
  `rac_*` symbols — never a stubbed plausible-looking result.
- Keep the public surface in sync: anything public is imported and listed in
  `runanywhere/__init__.py`'s `__all__`, and re-exported from its module's `__all__`.
- One in-flight generation per model handle (`_GenerationGuard`) — a second concurrent
  `generate` is a programming error → `invalid_state`, not a silent queue.

The fuller PR-review checklist (typed contracts, honesty/readiness claims, concurrency/native
safety, security basics, anti-patterns) is in
[`docs/reference/best-practices.md`](docs/reference/best-practices.md).

## Definition of done (Python SDK change)

- Typed public API (dataclasses / IntEnums / stubs updated), errors are structured
  `SDKException`s with correct categories.
- Native leases/cancel/unload paths stay race-safe.
- Hermetic tests cover the new behavior (or explicitly skip with reason).
- Docs/AGENTS/README honesty matches reality (don't claim POSIX secure-store encryption, NPU
  support, or remote auth that isn't wired).
- IDL/proto regen committed when schemas change (`idl/codegen/generate_python.sh`); never
  hand-edit `_pb2.py`.

## Commit style

One logical change per commit; short, direct subject lines; **no** `Co-Authored-By:` trailer.
