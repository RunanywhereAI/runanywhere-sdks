# v2 additions — backwards-compatibility audit

Branch: `feat/v2-rearchitecture` (13 commits ahead of main, bootstrap commit
`549f36563` plus 12 CodeRabbit follow-up fixes through `848903211`).

---

## Summary

**Yes, one genuine BC shim was introduced.** `RA_USE_LEGACY_COMMONS` in
`CMakeLists.txt:61` is declared and never wired — a dead option stub whose
sole purpose is to signal "v1 and v2 can coexist." It should be deleted.

Every engine stub (`RA_ERR_RUNTIME_UNAVAILABLE`) and every frontend
`backendUnavailable` branch is a **legitimate phase-0 placeholder** — the
integration code genuinely does not exist yet. None of those stubs exist
because v1 is still present; they exist because the Phase 0 engine work was
scoped to a separate PR.

The documentation (`docs/v2-migration.md`) actively frames v2 as "additive,
no v1 behavior change," which is an accurate description of the bootstrap PR
but will need to be rewritten when v1 is deleted.

The duplicate primitives (v2 `RingBuffer`/`MemoryPool`/`ModelRegistry` vs
v1 `sdk/runanywhere-commons/`) are clean rewrites with different namespaces
and no cross-dependency — they do not call into each other.

---

## Build toggles / coexistence flags

### `RA_USE_LEGACY_COMMONS` — `CMakeLists.txt:61`

```cmake
option(RA_USE_LEGACY_COMMONS "Fall back to sdk/runanywhere-commons for engines" OFF)
```

**Verdict: BC-SHIM — DELETE.**

- It is declared but never tested in any `if(RA_USE_LEGACY_COMMONS)` block
  in `CMakeLists.txt`, `cmake/platform.cmake`, `cmake/plugins.cmake`,
  `cmake/protobuf.cmake`, `cmake/sanitizers.cmake`, or any `CMakeLists.txt`
  under `core/`, `engines/`, or `solutions/`. Grepping the entire v2 tree
  (core/, cmake/, engines/, solutions/) returns zero hits beyond the
  declaration line.
- Its description ("Fall back to sdk/runanywhere-commons for engines") is
  a BC accommodation: it implies the v1 engine tree can substitute for v2
  engines at build time.
- Because the option is never consumed, flipping it ON does nothing. Keeping
  it in the file misleads future engineers into thinking there is a live
  fallback path.

**Action:** Delete `CMakeLists.txt:60-61` (comment + option declaration).

### No `#ifdef LEGACY_*` conditionals

Grepping `core/`, `engines/`, `cmake/`, `frontends/` for `ifdef.*LEGACY`
or `LEGACY_` returns zero hits in v2 files. The only `LEGACY` matches in
the repo are inside vendored `nlohmann/json.hpp` inside the v1 Flutter and
React Native SDKs — unrelated to v2.

### No other "fall back" CMake options

All other CMake options in `CMakeLists.txt:51-58`
(`RA_BUILD_TESTS`, `RA_BUILD_TOOLS`, `RA_BUILD_FRONTENDS`,
`RA_BUILD_ENGINES`, `RA_BUILD_SOLUTIONS`, `RA_ENABLE_SANITIZERS`,
`RA_ENABLE_TSAN`, `RA_ENABLE_LTO`) are pure feature-gating toggles
with no coexistence semantics.

---

## Stub implementations

| File | Stub-reason per code comments | Verdict |
|------|-------------------------------|---------|
| `engines/llamacpp/llamacpp_plugin.cpp:65-75` | `llm_generate()` returns `RA_ERR_RUNTIME_UNAVAILABLE`; comment says "real llama.cpp integration in next PR (Phase 0 llamacpp_engine agent)" | **LEGITIMATE-phase0-placeholder** |
| `engines/llamacpp/llamacpp_plugin.cpp:102-108` | `embed_text()` memsets zeros and returns `RA_ERR_RUNTIME_UNAVAILABLE` for same reason | **LEGITIMATE-phase0-placeholder** |
| `engines/sherpa/sherpa_plugin.cpp:56-59` | `stt_feed_audio()` returns `RA_ERR_RUNTIME_UNAVAILABLE` | **LEGITIMATE-phase0-placeholder** |
| `engines/sherpa/sherpa_plugin.cpp:86-94` | `tts_synthesize()` writes zero bytes and returns `RA_ERR_RUNTIME_UNAVAILABLE` | **LEGITIMATE-phase0-placeholder** |
| `engines/sherpa/sherpa_plugin.cpp:115-118` | `vad_feed_audio()` returns `RA_ERR_RUNTIME_UNAVAILABLE` | **LEGITIMATE-phase0-placeholder** |
| `engines/wakeword/wakeword_plugin.cpp:48-56` | `ww_feed_audio()` always writes `detected=0` and returns `RA_OK`; comment says "Real sherpa-onnx integration to be wired in next PR" | **LEGITIMATE-phase0-placeholder** (note: returns RA_OK, not RA_ERR_RUNTIME_UNAVAILABLE — intentional so the pipeline does not abort, it just never triggers) |
| `core/model_registry/model_downloader.cpp:20-34` | `StubDownloader::fetch()` returns `RA_ERR_RUNTIME_UNAVAILABLE`; comment names three future platform-specific files (`model_downloader_apple.mm`, `_android.cpp`, `_curl.cpp`) | **LEGITIMATE-phase0-placeholder** |

None of these stubs exist because v1 is still alive. The `wakeword_plugin.cpp` header
even explicitly states it "replaces the 100% stub at
`sdk/runanywhere-commons/src/features/wakeword/wakeword_service.cpp`" — it is
*succeeding* the v1 stub, not deferring to it.

---

## Frontend `backendUnavailable` branches

All five frontends share the same structure: `nativeHandle == 0` / `handle === 0` /
`_nativeHandle == 0` is the condition, because the JNI/JSI/FFI bridge that would
populate the handle is not landed yet. The "TODO(phase-N)" comments identify the
correct target phase.

| Frontend | File | Condition | Error emitted | Phase tag | Verdict |
|----------|------|-----------|---------------|-----------|---------|
| Swift | `frontends/swift/Sources/RunAnywhere/Adapter/VoiceSession.swift:57-63` | `handle != nil` guard fails | `RunAnywhereError.backendUnavailable("RunAnywhereV2 C core not linked in this build")` | `TODO(phase-1)` | **LEGITIMATE-phase0-placeholder** |
| Kotlin | `frontends/kotlin/src/main/kotlin/com/runanywhere/adapter/VoiceSession.kt:20-26` | `nativeHandle == 0L` | `VoiceEvent.Error(BACKEND_UNAVAILABLE, …)` | `TODO(phase-2)` | **LEGITIMATE-phase0-placeholder** |
| Dart | `frontends/dart/lib/adapter/voice_session.dart:22-29` | `_nativeHandle == 0` | `yield VoiceError(-6, …)` | `TODO(phase-3)` | **LEGITIMATE-phase0-placeholder** |
| TS/RN | `frontends/ts/src/adapter/VoiceSession.ts:31-36` | `this.handle === 0` | `yield { kind: 'error', code: -6, … }` | `TODO(phase-3)` | **LEGITIMATE-phase0-placeholder** |
| Web | `frontends/web/src/adapter/VoiceSession.ts:23-29` | `this.handle === 0` | `yield { kind: 'error', code: -6, … }` | `TODO(phase-3)` | **LEGITIMATE-phase0-placeholder** |

None of these branches exist to keep v1 running alongside v2. They exist because
Phase 1/2/3 JNI/JSI/FFI bridges have not been landed. When a bridge is landed, the
`static create()` factory populates the handle with a real pointer and the branch
becomes unreachable. They should be deleted at that point — not before.

---

## Documentation phrasing

### `docs/v2-migration.md` — passages that imply coexistence

| Line(s) | Passage | Why it needs rewriting when v1 is deleted |
|---------|---------|-------------------------------------------|
| 1-7 | Title "RunAnywhere v1 → v2 migration"; opening sentence "This document describes the **coexistence strategy** for v1 … **v1 keeps shipping unchanged** until the Phase 1 gate lands; v2 is additive." | Framing the doc as a coexistence strategy is accurate for the bootstrap PR but will be wrong once v1 is deleted. Should become "v1 migration guide — what has moved and how to update your integration." |
| 9-14 (layout table) | Two-column table titled "v1 (current, unchanged) — v2 (new, bootstrapped in this PR)" | Column header "v1 (current, unchanged)" implies v1 is the stable baseline. Once v1 is gone the table should list what was in v1 and what replaces it. |
| 78-103 | Section "Building v1 and v2 together" with parallel build commands for both `sdk/runanywhere-kotlin` and `frontends/kotlin` | This section only makes sense while both exist. The entire section should be deleted. |
| 83-87 | "v2 is additive at the source tree level — new top-level directories, no modifications to any v1 source file. There is a single v1 footprint…" | "Additive" is the wrong long-term framing. It was accurate for the bootstrap PR. Once v1 is removed, this paragraph becomes misleading about the intent. |

### `core/README.md` — no "alongside v1" phrasing

`core/README.md` contains no v1 coexistence language. It is written entirely
from the v2-only perspective ("single source of truth", "every frontend is a thin
adapter"). No changes needed here.

---

## Duplicate primitives across layers

### `RingBuffer` / `MemoryPool`

| v2 location | v1 location | Relationship |
|-------------|-------------|--------------|
| `core/graph/ring_buffer.h` — namespace `ra::core`, C++20, SPSC lock-free, ported from RCLI | `sdk/runanywhere-commons/` — no `ring_buffer.h` or `memory_pool.h` found in source tree (v1 uses sherpa-onnx's internal buffers and OS primitives directly) | **No actual duplication.** v1 does not have a `RingBuffer` abstraction in its source. v2's `RingBuffer` is a clean greenfield C++20 port from RCLI. |
| `core/graph/memory_pool.h` — namespace `ra::core`, aligned allocation, spinlock free-list, ported from RCLI | Same — absent in v1 source | **No actual duplication.** |

### `ModelRegistry`

| v2 location | v1 location | Relationship |
|-------------|-------------|--------------|
| `core/model_registry/model_registry.h` — namespace `ra::core`, keyed by string ID, capability-indexed, C++ singleton | `sdk/runanywhere-commons/include/rac/infrastructure/model_management/rac_model_registry.h` — C ABI (`rac_model_registry_handle_t`), different schema, tracks ONNX/GGUF models with C types | **Parallel but independent.** The v2 registry is a clean rewrite with a different schema and no `#include` of or runtime linkage to the v1 header. `model_registry.h:7` comment says "Ported from KMP ModelManager.kt + Swift ModelDownloader.swift into C++." The two registries do not call into each other and serve different build trees. |

### `ModelDownloader`

| v2 location | v1 location | Relationship |
|-------------|-------------|--------------|
| `core/model_registry/model_downloader.h/.cpp` — abstract `ModelDownloader` with `StubDownloader`; platform impls planned as `model_downloader_apple.mm`, `_android.cpp`, `_curl.cpp` | `sdk/runanywhere-commons/include/rac/infrastructure/model_management/rac_download.h` | **Parallel but independent.** No cross-reference. |

### Engine / backend implementations

| v2 layer | v1 layer | Relationship |
|----------|----------|--------------|
| `engines/llamacpp/llamacpp_plugin.cpp` — vtable-based plugin, stub generate() | `sdk/runanywhere-commons/src/backends/llamacpp/llamacpp_backend.cpp` — direct llama.cpp calls behind `rac_llm_service_ops_t` vtable | **Clean rewrite behind a different ABI.** The v2 engine plugin does not `#include` any v1 header. The two exist simultaneously because v2 engine integration is a Phase 0 follow-up PR. |
| `engines/sherpa/sherpa_plugin.cpp` | `sdk/runanywhere-commons/src/backends/onnx/` | Same — parallel, independent. |
| `engines/wakeword/wakeword_plugin.cpp` | `sdk/runanywhere-commons/src/features/wakeword/wakeword_service.cpp` | Same — v2 plugin header explicitly names v1 as the file being replaced. |

---

## Recommendation

If the goal is to delete all v1 and have v2 stand alone, the following v2
items need to be changed at the same time as (or immediately after) v1 deletion:

1. **Delete `CMakeLists.txt:60-61`** — the `RA_USE_LEGACY_COMMONS` option. It
   is a dead declaration with BC semantics and zero callers.

2. **Rewrite `docs/v2-migration.md`** — remove the "coexistence strategy"
   framing, the two-column v1/v2 layout table, and the "Building v1 and v2
   together" section (lines 79-103). Replace with a flat migration guide:
   "this is what you used in v1, this is what you use in v2."

3. **Do NOT touch the engine stubs or frontend `backendUnavailable` branches
   yet** — those are tied to Phase 0/1/2/3 PR sequencing, not to v1 survival.
   They disappear naturally as each engine PR and each frontend bridge PR lands.

4. **Do NOT merge the v1 and v2 model registry or downloader** — they serve
   different build systems (v1 CMake + v1 ABI; v2 CMake + v2 ABI). The v2
   `StubDownloader` will be replaced by platform-specific implementations in
   Phase 1 (`_apple.mm`) and Phase 2 (`_android.cpp`) regardless of whether
   v1 is alive.
