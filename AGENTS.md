# AGENTS.md

Guidance for AI coding assistants working in this repository.

> **`AGENTS.md` is the real file; each `CLAUDE.md` is a committed symlink to the
> `AGENTS.md` beside it.** Editing either name edits the same bytes. If you create a new
> `AGENTS.md` in a directory that doesn't have one, run
> `bash scripts/validation/gates/check_agents_claude_sync.sh --fix` from the repo root to
> create its `CLAUDE.md` symlink — `pr-build.yml` fails any tracked `AGENTS.md` missing one.
> Never hand-create a `CLAUDE.md` as a real file.

## Working conventions

- **Focus on simplicity.** Clean, SOLID-ish separation of concerns; reuse over
  reinvention. No mock implementations and no new unit tests unless the task explicitly
  asks for them.
- **Plan first for non-trivial work.** Write the plan to
  `thoughts/shared/plans/{descriptive_name}.md`, get it approved before implementing, and
  keep it updated (append what changed) as you go so the next engineer can pick it up.
- **Structured types over raw strings.** Enums/sealed classes/data classes for
  configuration and results — this is enforced per-SDK by lint (ktlint/detekt, SwiftLint,
  ESLint) so ad hoc strings tend to get caught anyway.
- **Read files fully** before editing them; only use offset/limit on files too large to
  read at once.
- **Use full local build parallelism** (`-j "$(sysctl -n hw.logicalcpu)"` / equivalent),
  scaling down only under real memory/thermal pressure — not because load average looks
  high.
- **Multi-agent workflows run on Sonnet.** When fanning work out to subagents (the
  `Workflow` tool, or several parallel `Agent` calls), pass `model: 'sonnet'` on every
  `agent(...)` call rather than letting them inherit the session model. A fan-out of
  8-10 probes reading large files is exactly the shape where Sonnet is the right
  cost/latency trade, and these agents are doing bounded, well-specified retrieval and
  analysis rather than open-ended reasoning. Reserve the session's stronger model for
  the synthesis step that consumes their reports, and for anything where a wrong answer
  is expensive and hard to detect — a final design decision, an adversarial verification
  pass, or a security-relevant judgement.

  ```js
  // in a Workflow script
  const findings = await parallel(LENSES.map((l) => () =>
    agent(l.prompt, { label: `probe:${l.key}`, schema: FINDINGS, model: 'sonnet' })))

  // the synthesis that reads them can stay on the session model
  const plan = await agent(synthesisPrompt, { schema: PLAN, effort: 'high' })
  ```

## The most important architectural rule: logic lives at the lowest layer that serves everyone

Each feature/modality (LLM, STT, TTS, VAD, VLM, RAG, LoRA, Voice) is invoked through
**one** SDK entry point; the SDK, and below it C++ commons, does all the heavy lifting. If
an example app builds a multi-step bootstrap sequence, hardcodes a model/engine constant,
or post-processes model output, that is a bug in the SDK, not the app — fix it down a
layer.

1. **C++ commons (`core/`)** — cross-platform, non-I/O logic: model lifecycle, registry,
   download orchestration, RAG session management, inference routing. All 5 SDKs get the
   fix for free.
2. **Platform SDK layer** — platform-specific I/O or runtime bridging only (Web OPFS,
   iOS Keychain, Android Keystore, WASM MEMFS mirroring).
3. **Example apps** — UI rendering, navigation, thin SDK calls. No business logic, no
   internal-SDK knowledge (path patterns, framework→directory mappings), no workarounds.

**iOS is the source of truth.** When behavior is ambiguous in any other SDK, check the
iOS Swift implementation first and copy the logic exactly, adapting only syntax.

---

## Repository overview

Cross-platform on-device AI SDK monorepo. A single C/C++ core (`runanywhere-commons`,
~118K first-party LOC plus ~420K generated proto bindings) implements all AI business
logic behind a pure C ABI (`rac_*` prefix). Platform SDKs are thin bridges that supply
platform services (file I/O, HTTP, Keychain, audio) via an inversion-of-control struct and
call into the C core for all inference. Protobuf IDL schemas generate type-safe bindings
for every language.

**Current version**: `0.20.25` (canonical source: `core/VERSION`)

| SDK | Path | Bridge mechanism | Platforms |
|-----|------|-------------------|-----------|
| Swift | `bindings/swift/` | XCFramework + CRACommons module map | iOS 17.5+, macOS 14.5+ |
| Kotlin | `bindings/kotlin/` | JNI (`librunanywhere_jni.so`) | Android (min API 24) |
| Flutter | `bindings/flutter/` | Dart FFI | iOS, Android |
| React Native | `bindings/react-native/` | NitroModules (JSI HybridObject) | iOS 17.5+, Android arm64 |
| Web | `bindings/web/` | Emscripten WASM + TypeScript | Chrome, Safari, Firefox |
| Electron | `bindings/electron/` | Node-API addon | Windows x64 (preview) |
| Python | `bindings/python/` | pybind11 extension (`runanywhere._core`) | Windows, macOS, Linux (alpha) |

Each has its own `AGENTS.md` with full architecture, build commands, and conventions —
read it before working in that SDK.

| Native dir | Contents |
|-----------|----------|
| `core/` | C/C++ core library: all AI logic, plugin registry, event system |
| `engines/` | 7 backend plugins: llamacpp, sherpa, onnx, cloud, mlx, qhexrt, neurt |
| `runtimes/` | 3 runtime adapters: cpu (always), onnxrt, coreml |
| `idl/` | 39 Protobuf schemas + per-language codegen scripts |

### Consumer apps live in separate repos

The four full consumer apps were extracted into standalone repos (history preserved); PR
against them there, not here: [runanywhere-ios](https://github.com/RunanywhereAI/runanywhere-ios),
[runanywhere-android](https://github.com/RunanywhereAI/runanywhere-android),
[runanywhere-web](https://github.com/RunanywhereAI/runanywhere-web),
[runanywhere-electron](https://github.com/RunanywhereAI/runanywhere-electron).

Two example apps remain in-tree (`bindings/flutter/example/`, `bindings/react-native/example/`).
All example apps share brand orange `#FF6900`, documented in `docs/DESIGN_GUIDELINE.md`.

### Minimal examples are how you verify an SDK change locally

Each in-repo example consumes its SDK from local source (no staging/publishing needed to
see an edit): Swift via `RUNANYWHERE_USE_LOCAL_NATIVES=1`, Kotlin via a Gradle composite
build (`includeBuild` + `dependencySubstitution`), Web via Vite aliases into
`packages/*/src`. They're deliberately minimal (one prompt in, one streamed completion
out) — feature-complete UI belongs in the consumer repos above.

---

## Cross-platform architecture

`idl/*.proto` is the schema root; `idl/codegen/generate_all.sh` emits per-language
bindings (Swift, Kotlin/Wire, TS/ts-proto, Dart), all generated and none committed — see
[`docs/reference/generated-code-contract.md`](docs/reference/generated-code-contract.md)
for the full "what generates what, when" contract before touching `idl/`.

All SDKs reach `runanywhere-commons` through the `rac_*` C API. Commons holds the
component layer (lifecycle), the service layer (dispatch), and the plugin registry, and
reaches engines through `rac_engine_vtable_t`.

| Engine | Primitives |
|---|---|
| llamacpp | LLM, VLM |
| sherpa-onnx | STT, TTS, VAD |
| onnx | Embed, Segment |
| qhexrt | Hexagon NPU |
| neurt, cloud | Apple Neural Engine, HTTP |

Backend base priorities (highest wins per primitive via `rac_plugin_find()`, no
runtime/format scoring): qhexrt=150 (QNN-context models only), mlx=110 (Apple),
llamacpp=100, sherpa=90, onnx/cloud=50. An explicit engine name is honored through
`rac_plugin_find_for_engine()` regardless of priority.

### Non-obvious invariants that span every SDK

- **Platform adapter IoC**: `rac_platform_adapter_t` is a flat C struct of function
  pointers populated by each SDK before `rac_init()`. C++ never calls platform APIs
  directly — file I/O, HTTP, Keychain, logging, memory queries all pass through it.
- **Two-phase init**: every SDK does Phase 1 (sync: register adapter, load native libs,
  configure logging) then Phase 2 (async: authenticate, register device, fetch model
  assignments, discover downloaded models).
- **Plugin ABI**: `RAC_PLUGIN_API_VERSION = 9u`; a version mismatch is an immediate
  rejection. Each vtable has 10 active primitive slots and 7 reserved. NULL slot = not
  supported. `rerank_ops` (wire value 11) was promoted from `reserved_slot_2` in ABI v8;
  wire value 6, retired in ABI v4, stays permanently retired — never reuse it. See
  `core/AGENTS.md` for the full ABI history and how to add a primitive.
- **Static vs. dynamic plugins**: iOS and WASM force `RAC_STATIC_PLUGINS=ON` (no
  `dlopen`), registered via `RAC_STATIC_PLUGIN_REGISTER(name)` + `-force_load` /
  `--whole-archive`. Android/Linux/macOS default to dynamic loading via
  `rac_registry_load_plugin()`.
- **Streaming fan-out**: C++ allows only one proto-byte callback per component handle.
  Each SDK implements its own fan-out to multiplex that into multiple subscribers (Swift
  `AsyncStream`, Kotlin `Flow`, Dart `StreamController`, TS `AsyncIterable`).
- **Proto types are canonical**: never hand-write enum values or structured types that
  exist in `idl/*.proto` — use the generated types/typealiases and regenerate instead.
- **HTTP is platform-provided**: no libcurl. Each SDK registers a
  `rac_http_transport_ops_t` (URLSession on Apple platforms, OkHttp on Android,
  `emscripten_fetch` on Web).

A side-by-side comparison of entry point / bridge / streaming / events / storage / HTTP
per SDK — useful when porting a fix across SDKs — lives in
[`docs/reference/cross-sdk-parity.md`](docs/reference/cross-sdk-parity.md).

---

## Building and running

The root `CMakeLists.txt` (version from `core/VERSION`) is the single entry point for
native builds; `CMakePresets.json` defines `macos-{debug,release}`, `linux-{debug,release,asan}`,
`ios-{device,simulator}`, `android-arm64`, `wasm`, and the `rcli-*`/`windows-*` presets.

```bash
cmake --preset macos-debug && cmake --build build/macos-debug && ctest --preset macos-debug
```

**`./run <group> [subcommand]`** is the unified wrapper for everything else — build,
lint, and run any SDK or example app from one CLI (`./run --help` for the full menu):

```bash
./run doctor                    # scan host toolchains, show what's buildable here
./run setup                     # provision env for every host-buildable target
./run sdk commons build-android # build C++ commons for all Android ABIs, stage .so files
./run sdk kotlin build          # (etc. — see per-SDK AGENTS.md for direct tool commands)
./run example android install   # build + install + launch the Kotlin minimal example
./run codegen                   # regenerate every language binding from idl/
```

For the direct `swift build` / `./gradlew` / `melos` / `yarn` / `npm` commands each SDK
uses under the hood, and its test/lint/publish targets, see that SDK's own `AGENTS.md`
(`bindings/<name>/AGENTS.md`) — the commands are kept there, not duplicated here, so they
can't drift.

Cross-platform build scripts worth knowing about at the root level:

```bash
./bindings/swift/scripts/build-core-xcframework.sh   # also syncs into RN/Flutter plugin dirs
./scripts/build/build-core-android.sh                # .so for all ABIs → every SDK's jniLibs/
./bindings/web/scripts/build-core-wasm.sh
./scripts/setup/setup-toolchain.sh                   # protoc/wire/ts-proto toolchain
./idl/codegen/generate_all.sh [--only <lang>]         # swift|kotlin|dart|ts|cpp|python
```

---

## Version management and releases

Canonical version: `core/VERSION` (single-line semver). Bump everywhere with:

```bash
./scripts/release/sync-versions.sh <version>
```

The full release runbook (version bump → PR → tag → GitHub Release → npm/Maven/pub.dev/
SwiftPM publishing → cutting the `runanywhere-swift` SPM distribution repo → starter-app
smoke tests) is a multi-step process captured in three skills — use them rather than
improvising the steps: **sdk-release** (version bump through published GitHub Release),
**sdk-publish** (registry publishing + the `runanywhere-swift` dist repo cut), and
**sdk-test-starters** (post-release device/app smoke tests).

---

## CI/CD workflows (`.github/workflows/`)

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `pr-build.yml` | PR to main, push to main/feat branch | Parallel native builds (macOS/Linux/iOS/Android) + per-SDK typecheck + centralization/coherence gates |
| `release.yml` | Tag `v*.*.*` or manual | Full artifact build matrix, SDK packaging, consumer validation, draft Release |
| `auto-tag.yml` | PR merged to main with `release:*` label | Verifies the reviewed semver bump, pushes that exact git tag |
| `idl-drift-check.yml` | Changes to `idl/` or generated files | Regenerates protos, verifies schema lock + untracked generated trees |
| `legacy-files-blocklist.yml` | All PRs/pushes | Prevents specific deleted files from being re-introduced |
| `secret-scan.yml` | PRs and pushes to main | Incremental gitleaks scan on diff range |
| `check-no-pii-logging.yml` | PRs/pushes to main/master/feat-branch | Guards against logging signed URLs alongside active-download destination paths |

---

## Platform requirements

| Platform | Min version | Build tool | Key versions |
|----------|------------|------------|--------------|
| iOS / macOS | 17.5 / 14.5 | Xcode 26+ | Swift 6.2 |
| Kotlin SDK | Android API 24 | AGP 9.2.1 / Gradle 9.5.0 | Kotlin 2.4.0, NDK 27.3.13750724 |
| Flutter | 3.44.6 | Melos / AGP 9.0.1 / Gradle 9.1.0 | Dart 3.12.2+, NDK 28.2.13676358 |
| React Native | 0.85.3 (min 0.83.1) | Yarn Berry 3.6.1 | NitroModules, Hermes |
| Web | Chrome 86+ | Vite | Emscripten 6.0.2, Node 24 LTS |
| C++ core | N/A | CMake 3.24+ | C++20, Ninja |

---

## Non-obvious configuration details

- **NDK pin**: `core/VERSIONS::NDK_VERSION` (27.3.13750724) is the single source of truth,
  mirrored into `bindings/kotlin/gradle.properties`. NDK 27 (r27d) gives 16 KB
  page-alignment required by Android 15+ — NDK 25.x's 4 KB-aligned `libc++_shared.so` /
  `libomp.so` trips Android 16's page-size enforcement. Mirror this pin whenever bumping
  it; Flutter/RN Android build files carry their own fallback literals that can drift.
- **`useLocalNatives`** (Kotlin `gradle.properties`, similarly named flags elsewhere):
  `true` builds native libs from source locally; CI and most non-local runs set it
  `false` to download prebuilt `.so`/`.xcframework`/`.wasm` from GitHub Releases instead.
- **Web SDK** has several hard-won WASM/browser runtime workarounds (VLM worker crash
  recovery, a Qwen2-VL WebGPU NaN bug, cross-origin isolation requirements) — see
  [`docs/reference/web-runtime-gotchas.md`](docs/reference/web-runtime-gotchas.md).
- **Cloud/Linux dev VM** (e.g. Cursor Cloud): what's buildable there and the
  clang/NDK/KVM gotchas are in
  [`docs/reference/cursor-cloud-environment.md`](docs/reference/cursor-cloud-environment.md).

---

## Pre-commit hooks

```bash
pre-commit run --all-files                     # everything
pre-commit run ios-sdk-swiftlint --all-files   # SwiftLint only
```

Configured hooks: gitleaks (secrets), trailing-whitespace, end-of-file-fixer, check-yaml,
check-added-large-files (1000 KB max), check-merge-conflict, object file detection,
SwiftLint (SDK + example app), periphery (unused Swift code detection).

---

## Where to look for current in-flight work

`thoughts/shared/plans/` holds active/completed execution plans (including any in-flight
SDK reorg or migration briefs — e.g. the Electron reorganization plan); `thoughts/shared/issues/`
holds tracked bug write-ups. Check these directories directly rather than trusting a
status summary written into this file — both change too often for a static snapshot here
to stay accurate.
