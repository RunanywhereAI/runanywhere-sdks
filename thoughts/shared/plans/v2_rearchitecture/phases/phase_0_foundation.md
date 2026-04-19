# Phase 0 — Foundation

> Goal: land the new infrastructure (ABI headers, L4 graph primitives,
> plugin registry scaffolding, engine router, proto3 IDL, CMake + sanitizer
> wiring) **without changing any existing behavior**. After this phase,
> nothing calls the new code yet — but every subsequent phase has the
> building blocks it needs.

---

## Prerequisites

- `feat/v2-rearchitecture` branch current with `main`.
- `docs/architecture.md` / `current_state.md` read.
- No other phase in flight.

## What this phase delivers

1. **New C ABI header tree under `sdk/runanywhere-commons/include/rac/abi/`**
   — the stable contract every future SDK frontend binds to.
2. **L4 graph primitives under `include/rac/graph/` + `src/graph/`.**
3. **Plugin registry scaffolding under `include/rac/registry/` +
   `src/registry/`.** Not yet wired to any backend.
4. **Engine router + hardware profile under `include/rac/router/` +
   `src/router/`.**
5. **proto3 IDL files under `sdk/runanywhere-commons/idl/` + codegen
   integration in CMake.** Generated `.pb.cc/.pb.h` land in
   `src/gen/` (gitignored) on build.
6. **Sanitizer wiring in CMake.** ASan + UBSan in Debug; TSan flag
   available.
7. **Primitive unit tests under `tests/core_tests/`** — ring buffer,
   memory pool, cancel token, stream edge, plugin registry, engine
   router. Target: 30+ tests, all green, ASan + UBSan clean.

**No existing code changes.** `rac_commons.a` still builds and ships with
identical behavior. Services still use callbacks; VoiceAgent still runs
the batch loop; old `rac_service_*` still drives backend registration.

---

## Exact file-level deliverables

### Headers (new)

```text
sdk/runanywhere-commons/include/rac/abi/
├── ra_version.h          RA_ABI_VERSION + RA_PLUGIN_API_VERSION macros; extern "C" ra_abi_version(), ra_plugin_api_version(), ra_build_info()
├── ra_primitives.h       ra_status_t, ra_primitive_t, ra_model_format_t, ra_runtime_id_t, opaque session handles, ra_token_callback_t, ra_transcript_chunk_t, ra_vad_event_t
├── ra_pipeline.h         ra_pipeline_t, ra_pipeline_create (proto3 bytes), ra_pipeline_run, ra_pipeline_cancel, ra_pipeline_destroy, event callback
└── ra_plugin.h           ra_engine_vtable_t, RA_PLUGIN_ENTRY_DECL macro, RA_STATIC_PLUGIN_REGISTER macro
```

Booleans are `uint8_t` with 0 / non-zero semantics — not `_Bool` — for
strict ABI compat across Swift / JNI / Dart FFI / Emscripten / MSVC.

### Headers + sources (new) — L4 graph

```text
sdk/runanywhere-commons/include/rac/graph/
├── ring_buffer.h         lock-free SPSC ring buffer for trivially-copyable T (audio hot path)
├── memory_pool.h         pool allocator for audio frames; posix_memalign / _aligned_malloc
├── cancel_token.h        hierarchical cancellation with on_cancel callbacks; UAF-proof via shared_ptr<AliveFlag>
├── stream_edge.h         typed async edge backed by std::deque<T> + mutex + condvar; BLOCK / DROP_OLDEST / DROP_NEWEST
├── pipeline_node.h       abstract base class for L3 operators; run(), initialize(), finalize(); metrics
└── graph_scheduler.h     owns one thread per node; joins on stop; reverse-order finalize() on partial-init failure

sdk/runanywhere-commons/src/graph/
└── graph_scheduler.cpp
```

### Headers + sources (new) — registry / router

```text
sdk/runanywhere-commons/include/rac/registry/
├── plugin_registry.h     PluginRegistry::global(), register_static, load_plugin, find(primitive, format), find_by_name, enumerate; returns shared_ptr<const PluginHandle>
└── plugin_loader.h       template<VTABLE> PluginLoader — load(dylib_path, symbols, abi, capability_gate); static-mode adopt()

sdk/runanywhere-commons/include/rac/router/
├── hardware_profile.h    HardwareProfile::detect(); cpu_vendor, cpu_brand, cpu_cores, has_metal, has_ane, has_cuda, total_ram, apple_chip_generation
└── engine_router.h       EngineRouter::route(RouteRequest) → RouteResult { shared_ptr<const PluginHandle>, score, rejection_reason }

sdk/runanywhere-commons/src/registry/plugin_registry.cpp
sdk/runanywhere-commons/src/router/hardware_profile.cpp
sdk/runanywhere-commons/src/router/engine_router.cpp
```

### proto3 IDL (new)

```text
sdk/runanywhere-commons/idl/
├── voice_events.proto    VoiceEvent (oneof: UserSaidEvent, AssistantTokenEvent, AudioFrameEvent, VADEvent, InterruptedEvent, StateChangeEvent, ErrorEvent, MetricsEvent)
├── pipeline.proto        PipelineSpec, OperatorSpec, EdgeSpec (uint32 capacity, EdgePolicy), PipelineOptions, DeviceAffinity
└── solutions.proto       SolutionConfig (oneof: VoiceAgentConfig, RAGConfig, WakeWordConfig, AgentLoopConfig, TimeSeriesConfig) + each message with every field needed
```

Proto files live inside commons because they describe the C ABI this
library exports. SDK frontends later read them via relative path for
codegen.

### CMake additions

```text
sdk/runanywhere-commons/cmake/
├── PluginSystem.cmake    rac_add_backend_plugin(NAME SOURCES DEPS ABI_VERSION) + rac_add_solution_plugin(...)
├── Protobuf.cmake        rac_protobuf_generate(TARGET PROTOS OUT_DIR) — invokes protoc --cpp_out
└── Sanitizers.cmake      INTERFACE targets rac_sanitizers_asan_ubsan + rac_sanitizers_tsan

sdk/runanywhere-commons/vcpkg.json    manages protobuf (required) and gtest (optional, FetchContent fallback)
```

Top-level `CMakeLists.txt` adds (at the top, before existing code):

```cmake
include(cmake/Sanitizers.cmake)
include(cmake/PluginSystem.cmake)
include(cmake/Protobuf.cmake)

# New static libs (nothing links them yet — landed in Phase 1+)
add_library(rac_abi STATIC src/abi/ra_version.c src/abi/ra_status.c)
add_library(rac_graph STATIC src/graph/graph_scheduler.cpp)
add_library(rac_registry STATIC src/registry/plugin_registry.cpp)
add_library(rac_router STATIC src/router/hardware_profile.cpp src/router/engine_router.cpp)

rac_protobuf_generate(TARGET rac_idl
    PROTOS idl/voice_events.proto idl/pipeline.proto idl/solutions.proto
    OUT_DIR ${CMAKE_CURRENT_BINARY_DIR}/gen)
```

### Tests (new)

```text
sdk/runanywhere-commons/tests/core_tests/
├── CMakeLists.txt              gtest / FetchContent(googletest) fallback when system gtest absent
├── ring_buffer_test.cpp        capacity rounding, push/pop FIFO, bulk ops, drain, SPSC correctness under std::thread
├── memory_pool_test.cpp        acquire/release, PooledBlock RAII, alignment guarantee
├── cancel_token_test.cpp       cancel idempotent, callback once, child propagation, late-cancel safe
├── stream_edge_test.cpp        push/pop FIFO, try_push full, close releases waiters, cancel releases waiters, clear_locked, drop-oldest policy
├── sentence_detector_test.cpp  (stub for Phase 3 port — header-only placeholder)
├── plugin_registry_test.cpp    static registration idempotent, find by primitive+format, find_by_name, concurrent enumerate
└── engine_router_test.cpp      routes to capable engine, rejects unmatched format, pinned engine bypass, hardware-profile score
```

Target: **≥30 tests**, all green under ASan + UBSan on macOS and Linux.

---

## Implementation order (step by step)

1. **Create directory skeleton** (empty .gitkeep files):
   ```
   mkdir -p sdk/runanywhere-commons/{idl,include/rac/{abi,graph,registry,router},src/{abi,graph,registry,router,gen},tests/core_tests}
   ```

2. **Write `include/rac/abi/ra_version.h` + `src/abi/ra_version.c`.**
   Constants: `RA_ABI_VERSION_MAJOR=0, MINOR=1, PATCH=0`. Public C API
   `ra_abi_version()`, `ra_plugin_api_version()`, `ra_build_info()`.

3. **Write `include/rac/abi/ra_primitives.h` + `src/abi/ra_status.c`.**
   Enumerate every `ra_status_t` code. Provide `ra_status_str()`. Declare
   opaque handles (`ra_llm_session_t`, `ra_stt_session_t`, etc.). Declare
   callback function pointer types. All booleans as `uint8_t`.

4. **Write `include/rac/abi/ra_plugin.h`.** `ra_engine_vtable_t` —
   metadata struct + every L3 primitive's function pointer. `RA_PLUGIN_ENTRY_DECL(name)`
   macro expands to `extern "C" ra_plugin_entry` on dlopen platforms,
   `static <name>_fill_vtable` on static platforms (iOS/WASM). Same for
   `RA_STATIC_PLUGIN_REGISTER(name)`.

5. **Write `include/rac/abi/ra_pipeline.h`.** `ra_pipeline_*`
   functions — all taking `const uint8_t* bytes, size_t len` for proto3
   payloads. Event callback carries proto3 bytes.

6. **Write `include/rac/graph/ring_buffer.h`.** Port from the
   `feat/v2-rearchitecture` branch (reference commit `848903211` —
   `core/graph/ring_buffer.h`). `std::is_trivially_copyable_v<T>`
   enforced. `normalize_capacity()` throws `std::length_error` on
   overflow.

7. **Write `include/rac/graph/memory_pool.h`.** Early-return on
   invalid alignment or allocation failure; `PooledBlock` RAII wrapper.

8. **Write `include/rac/graph/cancel_token.h`.** `shared_ptr<CancelToken>` +
   `child()` + `on_cancel()`. Callbacks invoked on cancelling thread.
   UAF-proof via a shared `AliveFlag` the consumers capture.

9. **Write `include/rac/graph/stream_edge.h`.** `std::deque<T>` + mutex +
   two condvars. `EdgePolicy::{kBlock,kDropOldest,kDropNewest}`. Rejects
   zero capacity at construction. Carries a shared `AliveFlag` so cancel
   callbacks don't UAF the edge.

10. **Write `include/rac/graph/pipeline_node.h`.** Abstract base.
    `run()`, `initialize()`, `finalize() noexcept`. `NodeState` enum.
    `NodeMetrics` struct.

11. **Write `include/rac/graph/graph_scheduler.h` + `src/graph/graph_scheduler.cpp`.**
    Owns `std::vector<std::thread>`, one per node. `start()` does
    `initialize()` then launches. On partial-init failure iterates the
    already-initialized prefix in reverse, calling `finalize()`.
    `stop_and_join()` cancels root token and joins.

12. **Write `include/rac/registry/plugin_loader.h`.** Template
    `PluginLoader<VTABLE>`. Two code paths via `#ifdef
    RA_STATIC_PLUGINS`:
    - Static: `adopt(const VTABLE&)` returns true, vtable is stored.
    - dlopen: `load(path, symbols, abi_version, capability_check)`
      does `dlopen(RTLD_NOW | RTLD_LOCAL)`, iterates `dlsym`, captures
      errno once (fix the `dlerror()` double-call UB), optionally runs
      capability gate.

13. **Write `include/rac/registry/plugin_registry.h` + `src/registry/plugin_registry.cpp`.**
    Singleton via `PluginRegistry::global()`. Storage is
    `std::vector<std::shared_ptr<PluginHandle>>`. Lookup returns
    `shared_ptr<const PluginHandle>` — safe across concurrent
    load/unload. `enumerate()` snapshots under the lock, then invokes
    callbacks lock-free. `register_static()` called by
    `RA_STATIC_PLUGIN_REGISTER` macro.

14. **Write `include/rac/router/hardware_profile.h` + `src/router/hardware_profile.cpp`.**
    `HardwareProfile::detect()` uses `sysctlbyname` on Apple, `/proc/cpuinfo`
    on Linux/Android, `GetSystemInfo` on Windows. Detects Apple chip
    generation (M1/M2/M3/M4), Metal presence, ANE flag, CUDA visibility
    (via `/dev/nvidia*` presence check on Linux), total/available RAM.

15. **Write `include/rac/router/engine_router.h` + `src/router/engine_router.cpp`.**
    `EngineRouter::route(RouteRequest)` iterates registered plugins,
    filters by primitive + format, scores by hardware match, returns
    best. Priority: capability > format > hardware > memory-budget.
    Pinned-engine request bypasses scoring.

16. **Write proto3 IDL files** with every field we'll need across
    Phases 3, 4, 5. Booleans stay bools in `.proto`; the C ABI
    mapping to `uint8_t` is an ABI-layer concern, not a schema concern.
    Copy the schemas from `feat/v2-rearchitecture` reference commit
    `848903211`, adjusted for any field renames since (this plan's
    audit identified none).

17. **Write `cmake/Sanitizers.cmake`.** Two INTERFACE targets:
    - `rac_sanitizers_asan_ubsan` — `-fsanitize=address,undefined
      -fno-omit-frame-pointer -fno-sanitize-recover=all` in Debug only.
    - `rac_sanitizers_tsan` — `-fsanitize=thread -fno-omit-frame-pointer`
      in Debug+TSan only.
    Guard with `if(MSVC)`: MSVC ships only `/fsanitize=address`; UBSan
    and TSan unsupported there.

18. **Write `cmake/PluginSystem.cmake`.** Functions:
    - `rac_add_backend_plugin(TARGET_NAME SOURCES DEPS ABI_VERSION)` —
      builds a `SHARED` library on dlopen platforms, `STATIC` on
      iOS/WASM. Links against `rac_abi`, `rac_registry`. Hidden
      visibility, `fPIC`, `CXX_VISIBILITY_PRESET hidden`.
    - `rac_add_solution_plugin(TARGET_NAME SOURCES DEPS ABI_VERSION)` —
      same as backend plugin but also links `rac_graph`, `rac_router`.

19. **Write `cmake/Protobuf.cmake`.** `rac_protobuf_generate(TARGET
    PROTOS OUT_DIR)` invokes `protoc --cpp_out=<OUT_DIR>` for each
    `.proto`, creates a STATIC lib target that links
    `protobuf::libprotobuf`.

20. **Write `vcpkg.json`.** Dependencies: `protobuf`, `gtest` (marked
    optional, `[gmock]` feature). Pin baseline for reproducibility.

21. **Update top-level `CMakeLists.txt`.** Add:
    ```cmake
    list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
    include(Sanitizers)
    include(PluginSystem)
    include(Protobuf)

    add_library(rac_abi STATIC src/abi/ra_version.c src/abi/ra_status.c)
    target_include_directories(rac_abi PUBLIC include)
    target_link_libraries(rac_abi PUBLIC rac_sanitizers_asan_ubsan)

    add_library(rac_graph STATIC src/graph/graph_scheduler.cpp)
    target_include_directories(rac_graph PUBLIC include)
    target_link_libraries(rac_graph PUBLIC rac_abi rac_sanitizers_asan_ubsan)

    add_library(rac_registry STATIC src/registry/plugin_registry.cpp)
    target_include_directories(rac_registry PUBLIC include)
    target_link_libraries(rac_registry PUBLIC rac_abi
                                        $<$<NOT:$<PLATFORM_ID:iOS>>:${CMAKE_DL_LIBS}>)

    add_library(rac_router STATIC src/router/hardware_profile.cpp src/router/engine_router.cpp)
    target_include_directories(rac_router PUBLIC include)
    target_link_libraries(rac_router PUBLIC rac_abi rac_registry)

    rac_protobuf_generate(TARGET rac_idl
        PROTOS ${CMAKE_CURRENT_SOURCE_DIR}/idl/voice_events.proto
               ${CMAKE_CURRENT_SOURCE_DIR}/idl/pipeline.proto
               ${CMAKE_CURRENT_SOURCE_DIR}/idl/solutions.proto
        OUT_DIR ${CMAKE_CURRENT_BINARY_DIR}/gen/rac_idl)

    if(RAC_BUILD_TESTS)
        add_subdirectory(tests/core_tests)
    endif()
    ```

22. **Write tests.** Port the 30+ gtests from the reference commit
    `848903211`. Path fixups: change `core/graph/ring_buffer.h` →
    `rac/graph/ring_buffer.h`, etc.

23. **Update `.gitignore`** to cover `sdk/runanywhere-commons/src/gen/`
    (the protoc output dir).

24. **Run `cmake --preset <existing-preset>`** and confirm the new
    targets build and the existing backends still build.

25. **Run `ctest`** — the new `rac_core_tests` binary plus any existing
    tests. All green.

---

## API changes in this phase

None that affect existing callers. New symbols added under the `ra_`
namespace. Old `rac_service_*` untouched.

## Acceptance criteria

- [ ] `cmake --preset macos-debug && cmake --build` succeeds.
- [ ] `cmake --preset linux-debug && cmake --build` succeeds.
- [ ] `ctest` on macos-debug: existing tests green + ≥30 new core_tests
      green, all under ASan + UBSan.
- [ ] `ctest` on macos-tsan: same tests green under TSan.
- [ ] `protoc --cpp_out=…` produces non-empty `.pb.cc/.pb.h` for all 3
      proto files.
- [ ] No existing feature regressed: spot-check that a voice agent test
      (if one exists in current `tests/`) still passes.
- [ ] No warnings at `-Wall -Wextra -Wpedantic`.

## Validation checkpoint

See `testing_strategy.md` for the umbrella discipline. Phase 0
runs the standard C++ build + test gates, plus the following
phase-specific checks:

- **Existing-test parity.** Every test in `sdk/runanywhere-commons/tests/`
  that was green before Phase 0 is still green after. This is the
  baseline that every later phase's feature-preservation matrix
  builds on.
- **New scaffolding unit tests** (≥30 across graph + registry +
  router + IDL) pass under both ASan/UBSan and TSan.
- **Dev-CLI skeleton smoke.** `./build/tools/dev-cli/ra-cli --help`
  prints the subcommand list. Each subcommand is a stub but the
  binary links and runs.
- **No feature actually changed.** This is the critical Phase 0
  check: run the feature preservation matrix's L3 + L5 smokes using
  the *pre-Phase-0* execution path (old `rac_service_*` is still
  live; no engines plug into the new registry yet). All rows green,
  proving we haven't accidentally broken anything while adding
  scaffolding.
- **Warning budget = 0.** `-Wall -Wextra -Wpedantic -Werror` on new
  sources. Existing sources grandfathered but not allowed to accrue
  new warnings touched in this phase.

## What this phase does NOT do

- No backend is plugin-registered yet.
- No L3 primitive is migrated to `Stream<T>`.
- Voice agent still uses the batch loop.
- RAG still uses the current retrieval path.
- The C ABI surface still carries struct events.
- Old `rac_service_*` is still the live registry path.

All of that lands in Phases 1–8.

---

## Known risks

| Risk | Probability | Mitigation |
| --- | --- | --- |
| protobuf not available in every build environment | Medium | `vcpkg.json` manages it; CI installs via `vcpkg install` on each runner |
| gtest missing on CI hosts | Medium | FetchContent fallback in `tests/core_tests/CMakeLists.txt` (confirmed working on macOS Sonoma + Ubuntu 22.04 in prior PR) |
| Ninja vs Xcode generator differences for iOS | Low | iOS preset already uses Xcode generator; new static libs have no generator-specific code |
| `dlopen` / `RTLD_LOCAL` behavior difference on macOS vs Linux | Low | Only `src/registry/plugin_registry.cpp` touches dlopen; Phase 0 only compiles it — Phase 1 exercises the runtime path |
| ABI-version mismatch between `RA_ABI_VERSION` and what Phase 5 proto3 wire format carries | Low | Both bumped together in Phase 5 |
