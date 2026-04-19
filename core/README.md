# RunAnywhere v2 — C++20 core

This directory is the **single source of truth** for every SDK's business
logic. Every frontend (Swift, Kotlin, Dart, TS/RN, Web) is a thin adapter
that encodes/decodes proto3 messages across the C ABI and does not contain
pipeline logic, routing logic, barge-in logic, or RAG logic.

```text
core/
├── abi/                  # L0 — stable extern "C" ABI
├── graph/                # L4 — RingBuffer, MemoryPool, StreamEdge, CancelToken
├── registry/             # L2 infra — PluginRegistry + PluginLoader<VTABLE>
├── router/               # L3 — EngineRouter, HardwareProfile
├── voice_pipeline/       # concrete VoiceAgent DAG with transactional barge-in
├── model_registry/       # download + cache
└── tests/                # gtest unit tests (ASan + UBSan + TSan in CI)
```

## Building

```bash
# macOS Debug, sanitizers on
cmake --preset macos-debug
cmake --build --preset macos-debug
ctest --preset macos-debug

# macOS Release
cmake --preset macos-release
cmake --build --preset macos-release

# Linux Debug
cmake --preset linux-debug
cmake --build --preset linux-debug

# iOS XCFramework (Phase 1)
cmake --preset ios-release && cmake --build --preset ios-release

# Android (Phase 2)
cmake --preset android-release && cmake --build --preset android-release

# WASM (Phase 3)
cmake --preset wasm-release && cmake --build --preset wasm-release
```

All presets enable `compile_commands.json` so clangd picks up full flags
automatically.

## Dependencies

Managed by vcpkg (`vcpkg.json` at repo root):

- `protobuf`       — proto3 runtime and `protoc` codegen
- `boost-asio`     — async runtime on macOS/Linux/Android
- `gtest`          — unit tests
- `spdlog`         — structured logging
- `yaml-cpp`       — solution YAML loader
- `nlohmann-json`  — model registry metadata
- `usearch`        — in-process HNSW for RAG (optional feature)

## Adding a new L2 engine

1. Create `engines/<name>/<name>_plugin.cpp` that exports
   `ra_plugin_entry` and ends with `RA_STATIC_PLUGIN_REGISTER(...)`.
2. Add a `CMakeLists.txt` that calls `ra_add_engine_plugin(...)` from
   `cmake/plugins.cmake`.
3. Append `add_subdirectory(engines/<name>)` to the root `CMakeLists.txt`.

The plugin is immediately discoverable by the `PluginRegistry` — no
frontend changes required.

## Adding a new L5 solution

1. Create `solutions/<name>/` with its own `CMakeLists.txt`.
2. Implement the solution as a DAG built on top of `core/graph` primitives.
3. Expose a factory function that takes the ergonomic config struct.
4. Add the proto3 solution config to `idl/solutions.proto`.

## Platform conditionals

- **iOS**: `RA_STATIC_PLUGINS=ON` — App Store §3.3.2 prohibits dlopen. All
  engines compile into the XCFramework.
- **Android/macOS/Linux**: `dlopen`-based plugin loading via
  `PluginLoader<VTABLE>`. Plugins ship as separate `.so`/`.dylib` files.
- **WASM**: `RA_STATIC_PLUGINS=ON` — single-threaded, no dynamic loading.
  Plugins compile into the WASM bundle.
- **iOS async**: Grand Central Dispatch (no `std::thread`). Other platforms
  use `std::jthread` or Boost.Asio.

## Design principles

See `thoughts/shared/plans/v2_rearchitecture/MASTER_PLAN.md` for the full
design document, including the before/after diagrams, the six-layer model,
and the RCLI/FastVoice reference implementations that Phase 0 ports.
