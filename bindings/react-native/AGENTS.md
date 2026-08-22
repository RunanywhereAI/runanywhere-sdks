# AGENTS.md

Yarn Berry (3.6.1) workspaces monorepo: one core package + four backend packages for
on-device AI in React Native. The SDK bridges pre-built C++ inference engines
(`runanywhere-commons`) into React Native via **NitroModules** (Nitrogen/Nitro) — a
JSI-based zero-serialization bridge, NOT the classic RN bridge or TurboModules.

Swift is the alignment source of truth: `bindings/swift/ARCHITECTURE.md`, especially §4
folder layout, §12 generated proto code, and §15 build/deployment. React Native follows
that iOS 17.5+ minimum and native/proto-byte ownership model — JavaScript is the facade,
never the owner of model registry, downloads, storage paths, or native HTTP routing.

Contributor build-from-source workflow (cloning, staging natives, running the sample app)
is in [`Docs/DEVELOPMENT.md`](Docs/DEVELOPMENT.md); the public API is in
[`Docs/Documentation.md`](Docs/Documentation.md). `Docs/ARCHITECTURE.md` is an older
target-state design note (missing `mlx`/`qhexrt`) — prefer this file and the two above.

### Packages

| Package | npm name | Purpose |
|---------|----------|---------|
| `packages/core` | `@runanywhere/core` | SDK lifecycle, auth, native event/model/storage facades, all AI capability proxies |
| `packages/llamacpp` | `@runanywhere/llamacpp` | LlamaCPP backend registration (GGUF LLM + VLM) |
| `packages/mlx` | `@runanywhere/mlx` | Apple MLX backend registration (LLM, VLM, speech, embeddings; physical iOS devices only) |
| `packages/onnx` | `@runanywhere/onnx` | ONNX/Sherpa backend registration (STT, TTS, VAD) |
| `packages/qhexrt` | `@runanywhere/qhexrt` | Qualcomm Hexagon NPU backend, Android-only, **private** — public `package-sdk.sh` runs never ship it (see Packaging below) |

Workspace dependency `../proto-ts` (`@runanywhere/proto-ts`) supplies protobuf-generated
TS types.

## Common Commands

### Root-level (from `bindings/react-native/`)

```bash
yarn install                    # Install all workspace deps (node-modules linker)
yarn typecheck                  # Type-check all packages (tsc --noEmit)
yarn lint                       # ESLint all packages
yarn build                      # Build all packages (tsc emit to lib/)
yarn nitrogen:all                # Regenerate Nitrogen bridge code (core, llamacpp, onnx, qhexrt — mlx has none, see below)

# Consume or refresh staged native binaries
yarn core:download-ios          # pod install for core staged binaries
yarn core:download-android      # Gradle downloadNativeLibs for core
yarn llamacpp:download-ios      # (same pattern for llamacpp, onnx)
yarn llamacpp:download-android

yarn release                    # lerna publish (npm, main branch only)
```

`./run sdk rn build` (the repo-root wrapper) is currently **broken**: it shells out to
`scripts/build-react-native.sh`, which was deleted and is on the
`legacy-files-blocklist.yml` do-not-reintroduce list. Use the `yarn` commands above
directly instead.

### Per-package (from `packages/<core|llamacpp|mlx|onnx|qhexrt>/`)

```bash
yarn typecheck                  # tsc --noEmit
yarn lint                       # ESLint src/**/*.ts
yarn nitrogen                   # Regenerate Nitrogen bridge code (not on mlx)
```

### Tests

```bash
yarn workspace @runanywhere/core test --runInBand
```

Core unit tests cover proto bytes/wire encoding, structured SDK errors, network config
validation, generated Solutions surfaces, and other backend-neutral helpers. Native/backend
inference still requires the platform example/device workflows — a JS unit pass is not
native validation.

### Packaging for distribution

```bash
./scripts/package-sdk.sh                        # stages natives, type-checks, produces .tgz + .sha256 for the 4 PUBLIC packages
./scripts/package-sdk.sh --include-private-qhexrt --natives-from PATH   # INTERNAL ONLY: also stage @runanywhere/qhexrt
```

`qhexrt` is type-checked alongside the public packages but **skipped by public packaging
by default**; it ships only via the internal flag, into `dist/sdk-rn-internal/` — and the
script itself asserts no `librac_backend_qhexrt*`/`libQnn*`/`lib{a,c}dsprpc.so` ever land
in the public `dist/sdk-rn/` output. Full build-from-source steps (staging natives before
this script can run) are in `Docs/DEVELOPMENT.md`.

## Architecture

### 5-Layer Stack

```
Layer 1: TypeScript API
  RunAnywhere facade + one module per v3 namespace in Public/Api/ (llm, vlm, stt, tts, vad,
  embeddings, rerank, images, diarization, segmentation, voice, rag, models, lora) over
  internal Public/Extensions/ per-feature bridge helpers (STT, TTS, VoiceAgent, RAG, LLM,
  Models, Storage, Solutions, Hybrid, Audio, Embeddings, CUA)
  Foundation/Initialization/ (InitializationState, ServicesReadyGuard), SDKLogger

Layer 2: Nitro Bridge (JSI — no serialization)
  HybridRunAnywhereCore (C++)     — ~60 methods covering all SDK capabilities
  HybridRunAnywhereCore+MLX       — dynamic registration of the linked Swift MLX runtime
  HybridRunAnywhereLlama (C++)    — LlamaCPP backend + VLM
  HybridRunAnywhereONNX (C++)     — generic ONNX + Sherpa speech registration
  HybridRunAnywhereQHexRT (C++)   — Hexagon NPU backend registration + capability probe (Android only, no iOS side)
  HybridRunAnywhereDeviceInfo     — Platform-specific (Swift on iOS, Kotlin on Android)
  HybridLLM / HybridVoiceAgent    — Proto-byte streaming subscription objects

Layer 3: C++ Bridge Code (packages/core/cpp/)
  HybridRunAnywhereCore.cpp + extension files (+AuthDevice, +Download, +Events, +Http, +Registry, +SecureStorage, +Solutions, +Storage, +Telemetry, +Tools, +Voice)
  cpp/bridges/ — AuthBridge, DeviceBridge, ExternalConfigGuard, FileManagerBridge, HTTPBridge, InitBridge, ModelRegistryBridge, PlatformDownloadBridge, StorageBridge, TelemetryBridge

Layer 4: Platform Native Code
  iOS: PlatformAdapterBridge.m (C ABI → Swift), URLSessionHttpTransport.mm, KeychainManager.swift, HybridAudioCapture.swift/HybridAudioPlayback.swift, SDKLogger.swift
  Android: PlatformAdapterBridge.kt (JNI ↔ Kotlin), cpp-adapter.cpp (JNI_OnLoad), SecureStorageManager.kt (Android Keystore), SDKLogger.kt, OkHttpHttpTransport.kt

Layer 5: Pre-built C++ Libraries (runanywhere-commons)
  RACommons.xcframework / librac_commons.so       — Core infrastructure, registry, storage, events, proto ABI
  RABackendLLAMACPP.xcframework / .so             — llama.cpp backend
  RABackendMLX.xcframework + RunAnywhereMLXRuntime.xcframework + RunAnywhereMLXMetal.xcframework  — MLX plugin, shared Swift runtime, dynamic Metal carrier (iOS)
  RABackendONNX.xcframework / .so                 — generic ONNX backend
  RABackendSherpa.xcframework / .so               — Sherpa-ONNX speech backend
  librac_backend_qhexrt.so (+ _jni.so)            — Hexagon NPU backend (Android only, private packaging)
```

### Key Design Decisions

**NitroModules, not TurboModules**: All native bridging uses Nitrogen-generated `HybridObject` classes registered in `HybridObjectRegistry` at dylib load time (`+load` on iOS, `JNI_OnLoad` on Android). JavaScript calls `NitroModules.createHybridObject("RunAnywhereCore")` to get a JSI handle. There are no `RCT_EXPORT_MODULE`/`RCTBridgeModule` registrations in the SDK.

**Swift source of truth, no consumer SPM setup**: The RN SDK directly links the same pre-built RACommons/backend binaries described by the Swift architecture doc. React Native consumers receive the complete MLX payload (plugin + runtime + Metal carrier + Hub/Crypto resource bundles) through CocoaPods rather than adding a separate Swift package dependency; RN does not duplicate MLX inference sources.

**Backend registration is explicit**: apps call `LlamaCPP.register()`, `MLX.register()`, `ONNX.register()` (and, where licensed, `QHexRT.register()`) separately from `RunAnywhere.initialize()`. MLX and QHexRT both reuse the core Nitro object rather than adding a second HybridObject; MLX discovers the linked Swift runtime through exported C symbols.

**MLX execution is physical-device-only**: the packaged arm64 simulator slices exist for package/compile/link/startup validation only. `MLX.register()` and `MLX.isAvailable()` return `false` in the iOS Simulator.

**HTTP transport vtable pattern**: `rac_http_transport_ops_t` is a C struct of function pointers in `librac_commons.so`. iOS's `URLSessionHttpTransport` registers URLSession callbacks; Android's `RunAnywhereCorePackage` companion `init` block calls `racHttpTransportRegisterOkHttp()` (JNI → `OkHttpHttpTransport.kt`). This must happen before any native HTTP request.

**Proto-byte streaming**: `HybridLLM`/`HybridVoiceAgent` expose `subscribeProtoEvents(handle, onBytes, onDone, onError)` returning an unsubscribe function. LLM streaming is consumed directly inside `RunAnywhere+TextGeneration`; voice-agent streaming is wrapped by `VoiceAgentStreamAdapter` into an `AsyncIterable<VoiceEvent>`.

**Hermes async iteration constraint**: Hermes does not support `for await...of` with NitroModules custom async iterables. Always use manual `iterator.next()` loops:
```typescript
const iterator = asyncIterable[Symbol.asyncIterator]();
let result = await iterator.next();
while (!result.done) {
  // process result.value
  result = await iterator.next();
}
```
(Every public API returning an `AsyncIterable` is affected; see `Docs/DEVELOPMENT.md` for the full surface list.)

### Entry Points and Initialization

**SDK entry**: `packages/core/src/index.ts` re-exports everything. Import order matters — `NitroModulesGlobalInit` must be first.

**NitroModules bootstrap**: `initializeNitroModulesGlobally()` in `native/NitroModulesGlobalInit.ts` guards against double-install via module-level singletons; calls `NativeModules.NitroModules.install()` once.

**Native module singletons**: `requireNativeModule()` / `isNativeModuleAvailable()` in `native/NativeRunAnywhereCore.ts` lazily create and cache the `HybridRunAnywhereCore` instance. These are the only exports from `packages/core/src/native`.

**`RunAnywhere.initialize({ apiKey, baseUrl, environment })` sequence** (`Public/RunAnywhere.ts`):
1. Join any in-flight `reset()`, then validate the base URL and (outside development) the API key
2. Install NitroModules and check native module availability
3. `native.initialize(configJson)` → commons Phase 1; the facade opens here, so `isReady` is true and local inference works
4. Kick the network phase in the background (`completeServicesInitialization()`): HTTP/auth setup, device registration, model assignments, downloaded-model discovery, telemetry flush

Callers never await step 4. `ensureServicesReady()` (`Foundation/Initialization/ServicesReadyGuard.ts`) joins it — or retries just the HTTP/auth half after an offline boot — before any call that needs the backend. A generation bump invalidates both phases when `reset()` runs mid-flight.

### Namespace Module Pattern

Each namespace is one module in `Public/Api/` (`Llm.ts`, `Stt.ts`, `Voice.ts`, …); the `RunAnywhere` facade only holds lifecycle plus those namespaces. Shared plumbing lives beside them: `Types.ts`, `Options.ts` (public bag → proto message, defaults from generated `*Defaults()` helpers), `Inputs.ts`, `Results.ts`, `Stream.ts`, `Bridge.ts` (preflight guards, proto encode/decode).

**Never write a default value in TypeScript** — `Options.ts` merges caller options over the generated defaults so the IDL keeps the only declaration. `Public/Extensions/` files are internal bridge helpers, not public API; some namespaces (`llm`, `vlm`, `vad`, `images`, `embeddings`) call the Nitro proto verbs directly and have no extension file.

### Type System, Events, and Logging

Modality types (STT, TTS, VAD, VLM, LoRA, RAG, VoiceAgent, StructuredOutput) come from `@runanywhere/proto-ts`, re-exported from `types/index.ts` — keep RN-local enums only for state proto doesn't define. `SDKException` (wraps `SDKErrorProto`) with static factories (`notInitialized`, `invalidInput`, `modelNotFound`, …) is the sole throwable. `RunAnywhere.events` (`Public/Api/Events.ts`) decodes native proto-byte events into `AnySDKEvent` (11 categories) — there are no JS-side event sinks.

`SDKLogger` (`Foundation/Logging/Logger/SDKLogger.ts`) delegates to `LoggingManager.shared`; verbosity via `RunAnywhere.logging.configure/.setLevel/.setLocalEnabled`. iOS `SDKLogger` uses `OSLog` (subsystem `com.runanywhere.reactnative`) via the `RNSDKLoggerBridge` ObjC shim; Android uses `android.util.Log.*`. SwiftLint bans direct `print()`/`NSLog()`/`os_log()`/`debugPrint()`/`Logger` at error severity — see Conventions.

## Build System Details

No JS bundler — `tsc` only; package entrypoints point `main`/`types`/`exports` straight at `src/index.ts` (Metro resolves TS source). `nitrogen` (reading `nitro.json` + `src/specs/*.nitro.ts`) generates C++ spec headers, Swift/ObjC iOS glue, and Kotlin/CMake/JNI Android glue under `nitrogen/generated/`; core's `scripts/fix-nitrogen-output.js` post-patch removes a `#include <NitroModules/Null.hpp>` that doesn't exist in the pinned nitro version — every `nitrogen` script call chains it.

iOS: CocoaPods podspecs bundle the package-owned XCFrameworks (`ios/Binaries/`), compile `ios/**/*` + `cpp/**/*`, and load the generated `*+autolinking.rb`. Android: Gradle's `downloadNativeLibs` task fetches `.so` zips into `src/main/jniLibs/`; `CMakeLists.txt` compiles `librunanywherecore.so` (C++20) and imports `librac_commons.so` prebuilt, linked with `-Wl,-z,max-page-size=16384` for Android 15+ 16 KB page-size compliance. Full contributor build-from-source + native-staging steps: `Docs/DEVELOPMENT.md`.

## Monorepo Integration

The parent repo (`runanywhere-sdks`) declares these packages as workspaces in its root `package.json` (`bindings/react-native/packages/*`, `example`, `bindings/proto-ts`), and the inner `bindings/react-native/package.json` declares the same set by local path for standalone operation.

**Both declarations are required, and they must stay in sync.** Yarn picks the owning project by walking up to the *nearest* `yarn.lock`, so `bindings/react-native/yarn.lock` makes the inner project the owner of everything beneath it — including `example/`. Any package under `bindings/react-native/` that the inner `workspaces` array omits is disowned, and `yarn workspace <name> run …` fails from anywhere with "doesn't seem to be part of the project declared in …". The root declaration is what keeps the root `yarn.lock` covering these packages — the repo-root lockfile gate in `rn-typecheck`. Because `example` is a member of the inner project, workspace-wide `yarn typecheck`/`yarn lint` fan out over the example app too.

The example sets `installConfig.hoistingLimits: "workspaces"`, so its deps stay in `example/node_modules` instead of hoisting — making it a hoisting boundary that `@runanywhere/proto-ts` (an *external* workspace at `../proto-ts`) must be linkable into. The example's `@bufbuild/protobuf` range must therefore stay compatible with the one `proto-ts`/`packages/*` declare (`^2.12.1`); a looser range resolves to a second protobuf runtime copy and install fails with YN0071 "Cannot link @runanywhere/proto-ts … conflicts with parent dependency".

## CI/CD (`.github/workflows/`)

`pr-build.yml`'s `rn-typecheck` job does more than its name suggests: generate IDL (`ts,cpp`) → install root + `bindings/react-native` workspaces → **compile the RN C++ headers against the generated Nitro specs** (`check_rn_cpp_headers_compile.sh` — catches a stale hand-written `override` against a regenerated pure-virtual, which no other CI job would) → `yarn typecheck` and `yarn lint` (whole RN workspace, example included) → Jest for `@runanywhere/core` and for the RN example.

`release.yml`'s `validate_consumer_react_native` job (clones `RunanywhereAI/react-native-starter-app`, runs `tsc --noEmit`) is **off by default** — it only runs on manual `workflow_dispatch` with `validate_external_starters: true`, not on every release.

`legacy-files-blocklist.yml` forbids reintroducing `scripts/build-react-native.sh` (see the `./run sdk rn build` gotcha above) and two now-removed `VoiceSessionHandle`/`RunAnywhere+VoiceSession` files.

## Key Files

| File | Purpose |
|------|---------|
| `packages/core/src/Public/RunAnywhere.ts` | SDK facade: lifecycle + the v3 namespaces |
| `packages/core/src/specs/RunAnywhereCore.nitro.ts` | Complete native C++ interface contract (~60 methods) |
| `packages/core/src/native/NativeRunAnywhereCore.ts` + `NitroModulesGlobalInit.ts` | Native module singleton + install guard |
| `packages/core/src/Adapters/VoiceAgentStreamAdapter.ts` | Proto-byte → AsyncIterable adapter for voice events |
| `packages/core/src/Foundation/Errors/SDKException.ts` | Sole throwable type with static factories |
| `packages/core/cpp/HybridRunAnywhereCore.cpp` | C++ implementation (split into `+Extension` files) |
| `packages/core/ios/PlatformAdapterBridge.m` / `android/.../PlatformAdapterBridge.kt` | Platform C ABI ↔ native bridge for secure storage, device info, HTTP |
| `../swift/ARCHITECTURE.md` | iOS layout, generated proto code, and build/deployment source of truth |

## Conventions

- **Strict TypeScript**: `strict`, `noImplicitAny`, `strictNullChecks`, `noImplicitReturns`, `noFallthroughCasesInSwitch` all enabled
- **ESLint**: `@typescript-eslint/recommended` + `prettier`, `no-console: error`, `no-explicit-any: error`
- **Prettier**: single quotes, 2-space indent, es5 trailing commas
- **SwiftLint** (`.swiftlint.yml`, `packages/{core,llamacpp,onnx}/ios` only — mlx/qhexrt have no iOS side): `print()`, `NSLog()`, `os_log()`, `debugPrint()`, `Logger` are all banned as lint errors; use `SDKLogger`
- **Versioning**: core + backend packages share one semver (currently `0.20.25`), managed by Lerna with conventional commits
- **Package naming**: Kotlin Nitro-generated code uses namespace `com.margelo.nitro.runanywhere.*`
