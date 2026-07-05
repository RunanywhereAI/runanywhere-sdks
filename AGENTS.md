# AGENTS.md

Guidance for AI coding assistants working in this repository. This root file holds only the global rules, the repo map, and the index of per-component AGENTS.md files — component detail lives in those files, not here.

## AGENTS.md format

Every SDK and example app has its own small AGENTS.md with exactly three sections:

- `## Info` — what the project is, key directories, component-specific rules.
- `## Build Info` — build/test/lint/package commands with correct paths.
- `## Work Ground` — short dated notes agents leave for other agents (gotchas, in-flight work). Prune stale entries when you touch the file.

When you learn something component-specific that future agents need, write it into that component's Work Ground — do not grow this root file.

### Index

| Component | AGENTS.md |
|-----------|-----------|
| C++ core (CMake root) | `sdk/runanywhere-commons/AGENTS.md` |
| Engine plugins | `sdk/runanywhere-commons/engines/AGENTS.md` |
| Compute runtimes | `sdk/runanywhere-commons/runtimes/AGENTS.md` |
| Swift SDK | `sdk/runanywhere-swift/AGENTS.md` |
| Kotlin SDK | `sdk/runanywhere-kotlin/AGENTS.md` |
| Flutter SDK | `sdk/runanywhere-flutter/AGENTS.md` |
| React Native SDK | `sdk/runanywhere-react-native/AGENTS.md` |
| Web SDK | `sdk/runanywhere-web-next/AGENTS.md` |
| CLI (rcli) | `sdk/runanywhere-cli/AGENTS.md` |
| Android example | `examples/android/RunAnywhereAI/AGENTS.md` |
| iOS example | `examples/ios/RunAnywhereAI/AGENTS.md` |
| Flutter example | `examples/flutter/RunAnywhereAI/AGENTS.md` |
| React Native example | `examples/react-native/RunAnywhereAI/AGENTS.md` |
| Web example | `examples/web-next/RunAnywhereAI/AGENTS.md` |

## Global rules

### Code

- Focus on SIMPLICITY and Clean SOLID principles: reusability, clear separation of concerns.
- Do NOT write ANY MOCK IMPLEMENTATION unless specified otherwise.
- DO NOT PLAN or WRITE any unit tests unless specified otherwise.
- Always use structured/proto types, never raw strings. All cross-platform types are defined in `idl/*.proto` and code-generated — never hand-write enum values.
- Read files FULLY before changing them.
- Swift: use the latest Swift 6 APIs; never NSLock.

### Resource discipline — bounded parallelism (do NOT crash the machine)

- Never use bare `-j`. Cap native builds at `-j 2` (Gradle `--max-workers=2`, Xcode `-jobs 2`).
- One heavy build at a time; build SDKs and sample apps sequentially.
- No process/agent storms: single bounded pass, at most 2-3 agents.
- Check `uptime` before a heavy step.

### Business logic layering

Logic must live at the lowest layer that serves all consumers:

1. **C++ commons** (`sdk/runanywhere-commons/`) — all cross-platform logic. A fix here benefits every SDK.
2. **Platform SDK** — only platform-specific I/O and runtime bridging.
3. **Example apps** — only UI and thin SDK API calls. No business logic, no workarounds, no internal SDK knowledge. If an app needs a multi-step bootstrap or hardcodes a model/engine constant, that is an SDK bug — fix it a layer down.

**iOS Swift is the source of truth** for business logic. When behavior is ambiguous in any other SDK, copy the iOS implementation exactly, adapting only syntax.

## Repository map

- `sdk/runanywhere-commons/` — C/C++ core behind the `rac_*` C ABI, and the **CMake root** for all native builds (`CMakeLists.txt`, `CMakePresets.json`, `cmake/`; output in `build/<preset>/`). Contains `engines/` (llamacpp, cloud, sherpa, onnx, metalrt, genie, coreml) and `runtimes/` (cpu, onnxrt, coreml, metal).
- `sdk/runanywhere-{swift,kotlin,flutter,react-native,web-next,cli}/` — platform SDKs: thin bridges that register a platform adapter and call the C ABI.
- `sdk/shared/proto-ts/` — shared TS proto bindings (`@runanywhere/proto-ts`).
- `idl/` — protobuf schemas only; codegen tooling is `scripts/codegen/`.
- `scripts/` — ALL scripts (`lib/ setup/ build/ codegen/ release/ validation/ examples/ tests/`); see `scripts/README.md`.
- `examples/` — one sample app per SDK. `Playground/` — standalone demos, no build-system ties.
- `./run` — the single dev entry point (`./run help`).

Version source of truth: `sdk/runanywhere-commons/VERSION` (project) and `VERSIONS` (toolchain/dependency pins — referenced by CI and renovate, do not rename). JS/TS pins: `scripts/lib/versions.json`.

Root files that must stay at the root: `Package.swift`/`Package.resolved` (SwiftPM URL consumers; hand-synced with `sdk/runanywhere-swift/Package.swift`), `jitpack.yml` (JitPack), `run`, dotfile configs.

## Architecture in one paragraph

Proto schemas (`idl/`) generate committed bindings for every language (`scripts/codegen/generate_all.sh`). Each SDK does two-phase init (Phase 1 sync: platform adapter + native libs; Phase 2 async: auth, device, model assignments), then calls the C ABI. Engines register `rac_engine_vtable_t` (ABI v4, 7 primitive slots) with the plugin registry; selection is by base priority (metalrt=120, llamacpp=100, sherpa=90, onnx=50) via `rac_plugin_find()`. iOS/WASM force static plugins; other platforms dlopen. HTTP is platform-provided via `rac_http_transport_ops_t` (no libcurl). Streaming is one proto-byte callback per handle, fanned out per SDK (AsyncStream/Flow/Stream/AsyncIterable).

## CI

`pr-build.yml` (native presets from `sdk/runanywhere-commons` + per-SDK typecheck), `release.yml` (tag-triggered artifact matrix + `scripts/release/package-*.sh`), `auto-tag.yml`, `idl-drift-check.yml` (regenerates protos, fails on diff), `streaming-perf.yml`, `legacy-files-blocklist.yml`, `secret-scan.yml`, `check-no-pii-logging.yml`. The composite action `.github/actions/setup-toolchain` reads `sdk/runanywhere-commons/VERSIONS`.

Release: `scripts/release/sync-versions.sh <ver>` → PR with `release:*` label → merge → auto-tag → release build.

## Work Ground

- 2026-07-05: repo restructured — CMake root moved into commons (engines/runtimes inside it), all scripts consolidated under `scripts/`, root yarn workspace moved to the RN example app (portal: deps), idl/codegen → scripts/codegen, per-SDK ARCHITECTURE/Documentation docs deleted pending a proper docs re-make. Generated proto headers still say "Generated by idl/codegen/..." until the next regen.
