# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Yarn Berry (3.6.1) workspaces monorepo containing one core package and four backend packages for on-device AI in React Native. Version `0.20.0`. The SDK bridges pre-built C++ inference engines (`runanywhere-commons`) into React Native via **NitroModules** (Nitrogen/Nitro) — a JSI-based zero-serialization bridge, NOT the classic React Native bridge or TurboModules.

Swift alignment source of truth: `sdk/runanywhere-swift/ARCHITECTURE.md`, especially §4 folder layout, §12 generated proto code, and §15 build/deployment. React Native follows that iOS 17.5+ minimum and native/proto-byte ownership model; JavaScript is the facade, not the owner of model registry, downloads, storage paths, or native HTTP routing.

### Packages

| Package | npm Name | Purpose |
|---------|----------|---------|
| `packages/core` | `@runanywhere/core` | SDK lifecycle, auth, native event/model/storage facades, all AI capability proxies |
| `packages/llamacpp` | `@runanywhere/llamacpp` | LlamaCPP backend registration (GGUF LLM + VLM inference) |
| `packages/onnx` | `@runanywhere/onnx` | ONNX/Sherpa backend registration (STT, TTS, VAD) |
| `packages/qhexrt` | `@runanywhere/qhexrt` | Qualcomm Hexagon NPU backend registration and capability probe |

Additional workspace dependency: `../shared/proto-ts` (`@runanywhere/proto-ts`) provides protobuf-generated TypeScript types.

## Common Commands

### Root-level (from `sdk/runanywhere-react-native/`)

```bash
yarn install                    # Install all workspace deps (node-modules linker)
yarn typecheck                  # Type-check all packages (tsc --noEmit)
yarn lint                       # ESLint all packages
yarn lint:fix                   # Auto-fix lint issues
yarn build                      # Build all packages (tsc emit to lib/)
yarn clean                      # Clean all build artifacts
yarn nitrogen:all               # Regenerate Nitrogen bridge code for all packages

# Per-package Nitrogen codegen
yarn core:nitrogen              # Core + fix-nitrogen-output.js post-patch
yarn llamacpp:nitrogen          # LlamaCPP
yarn onnx:nitrogen              # ONNX

# Consume or refresh staged native binaries
yarn core:download-ios          # pod install for core staged binaries
yarn core:download-android      # Gradle downloadNativeLibs for core
yarn llamacpp:download-ios      # pod install for llamacpp
yarn llamacpp:download-android
yarn onnx:download-ios
yarn onnx:download-android

# Release
yarn release                    # lerna publish (npm, main branch only)
```

### Per-package (from `packages/core/`, `packages/llamacpp/`, or `packages/onnx/`)

```bash
yarn typecheck                  # tsc --noEmit
yarn lint                       # ESLint src/**/*.ts
yarn nitrogen                   # Regenerate Nitrogen bridge code
```

### Running tests

```bash
yarn workspace @runanywhere/core test --runInBand
```

Core unit tests cover proto bytes/wire encoding, structured SDK errors,
network configuration validation, generated Solutions surfaces, and other
backend-neutral helpers. Native/backend inference still requires the platform
example/device workflows; a JavaScript unit pass is not native validation.

### Packaging for distribution

```bash
./scripts/package-sdk.sh        # Stages natives, type-checks, produces .tgz + .sha256
```

## Architecture

### 5-Layer Stack

```
Layer 1: TypeScript API
  RunAnywhere singleton + Extension modules (TextGeneration, STT, TTS, VAD, VoiceAgent, VLM, RAG, Solutions, ToolCalling)
  Proto adapters, SDK event subscriptions, ServiceContainer, SDKLogger

Layer 2: Nitro Bridge (JSI — no serialization)
  HybridRunAnywhereCore (C++)     — ~60 methods covering all SDK capabilities
  HybridRunAnywhereLlama (C++)    — LlamaCPP backend + VLM
  HybridRunAnywhereONNX (C++)     — generic ONNX + Sherpa speech registration
  HybridRunAnywhereDeviceInfo     — Platform-specific (Swift on iOS, Kotlin on Android)
  HybridLLM / HybridVoiceAgent    — Proto-byte streaming subscription objects

Layer 3: C++ Bridge Code (packages/core/cpp/)
  HybridRunAnywhereCore.cpp + extension files (+AuthDevice, +Download, +Events, +Http, +Registry, +SecureStorage, +Solutions, +Storage, +Telemetry, +Tools, +Voice)
  cpp/bridges/ — AuthBridge, DeviceBridge, ExternalConfigGuard, FileManagerBridge, HTTPBridge, InitBridge, ModelRegistryBridge, PlatformDownloadBridge, StorageBridge, TelemetryBridge

Layer 4: Platform Native Code
  iOS: PlatformAdapterBridge.m (C ABI → Swift), URLSessionHttpTransport.mm, KeychainManager.swift, AudioDecoder.m, SDKLogger.swift
  Android: PlatformAdapterBridge.kt (JNI ↔ Kotlin), okhttp_transport_adapter.cpp, SecureStorageManager.kt (Android Keystore), SDKLogger.kt, OkHttpTransport.kt

Layer 5: Pre-built C++ Libraries (runanywhere-commons)
  RACommons.xcframework / librac_commons.so       — Core infrastructure, registry, storage, events, proto ABI
  RABackendLLAMACPP.xcframework / .so             — llama.cpp backend
  RABackendONNX.xcframework / .so                 — generic ONNX backend
  RABackendSherpa.xcframework / .so               — Sherpa-ONNX speech backend
```

### Key Design Decisions

**NitroModules, not TurboModules**: All native bridging uses Nitrogen-generated `HybridObject` classes registered in `HybridObjectRegistry` at dylib load time (`+load` on iOS, `JNI_OnLoad` on Android). JavaScript calls `NitroModules.createHybridObject("RunAnywhereCore")` to get a JSI handle. There are no `RCT_EXPORT_MODULE` or `RCTBridgeModule` registrations in the SDK itself.

**Swift source of truth, no Swift package dependency**: The RN SDK directly links the same pre-built RACommons/backend binaries described by the Swift architecture doc, but it does not depend on the Swift package product. RN owns only its Nitro bridge and platform adapters.

**Backend registration is explicit**: Apps must call `LlamaCPP.register()` and `ONNX.register()` separately from `RunAnywhere.initialize()`. These register C++ backend vtables so `RunAnywhereCore`'s backend-agnostic methods know where to route inference calls.

**HTTP transport vtable pattern**: `rac_http_transport_ops_t` is a C struct of function pointers in `librac_commons.so`. On iOS, `URLSessionHttpTransport` registers URLSession-based callbacks. On Android, `RunAnywhereCorePackage`'s companion `init` block calls `racHttpTransportRegisterOkHttp()` which installs OkHttp via JNI. This must happen before any native HTTP request.

**Proto-byte streaming**: `HybridLLM` and `HybridVoiceAgent` expose `subscribeProtoEvents(handle, onBytes, onDone, onError)` returning an unsubscribe function. LLM streaming is consumed directly inside `RunAnywhere+TextGeneration` (no separate adapter); voice-agent streaming is wrapped by `VoiceAgentStreamAdapter` into an `AsyncIterable<VoiceEvent>` by decoding protobuf bytes.

**Hermes async iteration constraint**: Hermes does not support `for await...of` with NitroModules custom async iterables. Always use manual `iterator.next()` loops:
```typescript
const iterator = asyncIterable[Symbol.asyncIterator]();
let result = await iterator.next();
while (!result.done) {
  // process result.value
  result = await iterator.next();
}
```

### Entry Points and Initialization

**SDK entry**: `packages/core/src/index.ts` re-exports everything. Import order matters — `NitroModulesGlobalInit` must be first.

**NitroModules bootstrap**: `initializeNitroModulesGlobally()` in `native/NitroModulesGlobalInit.ts` guards against double-install via module-level singletons. Calls `NativeModules.NitroModules.install()` once.

**Native module singletons**: `requireNativeModule()` / `isNativeModuleAvailable()` in `native/NativeRunAnywhereCore.ts` lazily create the `HybridRunAnywhereCore` instance via `createHybridObject('RunAnywhereCore')` and cache it module-level. These are the only exports from `packages/core/src/native`.

**`RunAnywhere.initialize(options)` sequence** (`Public/RunAnywhere.ts:222`):
1. Validate API key (non-dev environments)
2. Check native module availability
3. `native.configureHttp(baseURL, apiKey)`
4. `native.initialize(configJson)` → C++ initialization
5. Native services finish initialization through the C++/proto bridge
6. `native.getPersistentDeviceUUID()` → cache device ID
7. `TelemetryService.configure()`
8. `_authenticateWithBackend()` → JWT tokens stored in secure storage
9. `_registerDeviceIfNeeded()` (non-blocking)
10. `ServiceContainer.shared.markInitialized()`

### Extension Module Pattern

Each AI capability is a standalone module in `Public/Extensions/` (e.g., `LLM/RunAnywhere+TextGeneration.ts`, `STT/RunAnywhere+STT.ts`). The `RunAnywhere` object imports these via namespace imports and delegates each property/method to the corresponding extension function. This keeps the facade thin while each extension manages its own state.

### Type System

- **Proto-sourced types**: All modality types (STT, TTS, VAD, VLM, LoRA, RAG, VoiceAgent, StructuredOutput) come from `@runanywhere/proto-ts` and are re-exported from `types/index.ts`
- **RN-local enums**: Keep only RN/UI state that is not defined in proto. Public model/framework/category enums should come from `@runanywhere/proto-ts`.
- **Core interfaces**: `ModelInfo` (23 fields), `SDKInitOptions` in `types/models.ts`; `LLMGenerationOptions` from `@runanywhere/proto-ts`
- **Runtime events**: Discriminated unions keyed by `type` string in `Public/Events/SDKEventTypes.ts` — `AnySDKEvent` is the union of all 11 event categories
- **Error type**: `SDKException` (extends `Error`, wraps `SDKErrorProto`) with static factories (`notInitialized`, `invalidInput`, `modelNotFound`, etc.)

### Event System

`RunAnywhere.subscribeSDKEvents(...)` is the consumer event surface. Native events flow through `subscribeSDKEventsProto`, arrive as proto bytes, and are decoded into generated `SDKEvent` messages. There are no JS-side event sinks anymore — all SDK event observation goes through the native proto-byte stream.

### Logging

`SDKLogger` (`Foundation/Logging/Logger/SDKLogger.ts`) delegates to `LoggingManager.shared`, which fans logs out to its registered `LogDestination`s. Default destination is the console; opt-in custom destinations are registered with `RunAnywhere.addLogDestination(...)`. Verbosity is controlled via `RunAnywhere.configureLogging(...)`, `setLogLevel(...)`, and `setLocalLoggingEnabled(...)`. Pre-built category instances live in `SDKLogger`: `.shared`, `.llm`, `.stt`, `.tts`, `.download`, `.models`, `.core`, `.vad`, `.network`, `.events`, `.archive`.

On iOS, Swift `SDKLogger` uses `OSLog` with subsystem `com.runanywhere.reactnative`. The ObjC `RNSDKLoggerBridge` lets C code route logs through Swift. SwiftLint rules (`.swiftlint.yml`) enforce that all logging goes through `SDKLogger` — `print()`, `NSLog()`, `os_log()` are banned at error severity.

On Android, Kotlin `SDKLogger` uses `android.util.Log.*`.

## Build System Details

### TypeScript

No bundler — `tsc` only. Package entrypoints point `main`/`types`/`exports` at `src/index.ts` directly (consumers resolve TypeScript source via Metro). `tsconfig.base.json` at root; per-package `tsconfig.json` extends it with `composite: true`, and every backend references `core`.

### Nitrogen Code Generation

`nitrogen` CLI reads `nitro.json` + `src/specs/*.nitro.ts` → generates:
- `nitrogen/generated/shared/c++/` — C++ abstract base class headers (`HybridRunAnywhereCoreSpec.hpp`, etc.)
- `nitrogen/generated/ios/` — Swift conformance stubs, ObjC autolinking `.mm`, Ruby autolinking `.rb`
- `nitrogen/generated/android/` — Kotlin spec stubs, CMake/Gradle autolinking scripts, JNI bridge code

Core package has a post-generation fixup: `scripts/fix-nitrogen-output.js` removes a `#include <NitroModules/Null.hpp>` that doesn't exist in the pinned nitro version.

### iOS Native Build

CocoaPods reads podspecs. Each podspec:
- Bundles package-owned pre-built XCFrameworks under `ios/Binaries/`
- Compiles hand-written Swift/ObjC/ObjC++ (`ios/**/*`) and C++ bridge code (`cpp/**/*`)
- Loads `nitrogen/generated/ios/*+autolinking.rb` which adds NitroModules dep, generated source globs, and sets C++20/`objcxx` xcconfig
- Native package map mirrors Swift binary names: core gets `RACommons`, llamacpp gets `RABackendLLAMACPP`, and onnx gets `RABackendONNX` plus `RABackendSherpa`

### Android Native Build

Gradle + CMake:
- `build.gradle` has a `downloadNativeLibs` task that fetches `.so` zips from GitHub Releases into `src/main/jniLibs/`
- `CMakeLists.txt` compiles `librunanywherecore.so` (C++20) from C++ bridge sources, imports `librac_commons.so` as pre-built, fetches `nlohmann/json` via CMake FetchContent
- 16KB page alignment (`-Wl,-z,max-page-size=16384`) for Android 15+ compliance
- `RunAnywhereCorePackage.kt` companion `init` block calls `System.loadLibrary("runanywherecore")` then registers OkHttp transport
- `cpp-adapter.cpp` `JNI_OnLoad` caches `PlatformAdapterBridge` method IDs for platform callbacks from C++

### Native Binary Staging

`scripts/package-sdk.sh --natives-from PATH` stages native binaries by package ownership instead of copying every binary into every package. iOS uses `ios/Binaries/`; Android uses package-specific `android/src/main/jniLibs/` contents.

## Monorepo Integration

The parent repo (`runanywhere-sdks-main`) declares these packages as workspaces in its root `package.json`:
```
sdk/runanywhere-react-native/packages/core
sdk/runanywhere-react-native/packages/llamacpp
sdk/runanywhere-react-native/packages/onnx
examples/react-native/RunAnywhereAI
sdk/shared/proto-ts
```

The inner `sdk/runanywhere-react-native/package.json` also declares workspaces (`packages/*` + `../shared/proto-ts`) for standalone operation.

## CI/CD

- **PR build** (`.github/workflows/pr-build.yml`): `rn-typecheck` job runs `yarn install --immutable` then `yarn typecheck` on `packages/core`
- **Release** (`.github/workflows/release.yml`): consumer validation clones `RunanywhereAI/react-native-starter-app` and runs `tsc --noEmit` (best-effort, `continue-on-error: true`)
- **IDL drift check** and **legacy files blocklist** workflows also reference RN SDK paths

## Key Files

| File | Purpose |
|------|---------|
| `packages/core/src/Public/RunAnywhere.ts` | Main SDK facade (~100+ methods) |
| `packages/core/src/specs/RunAnywhereCore.nitro.ts` | Complete native C++ interface contract (~60 methods) |
| `packages/core/src/native/NitroModulesGlobalInit.ts` | NitroModules singleton installation guard |
| `packages/core/src/native/NativeRunAnywhereCore.ts` | `requireNativeModule()` / `isNativeModuleAvailable()` accessors |
| `packages/core/src/Public/Extensions/Events/RunAnywhere+SDKEvents.ts` | Native proto-byte SDK event subscription |
| `packages/core/src/Adapters/VoiceAgentStreamAdapter.ts` | Proto-byte → AsyncIterable adapter for voice events |
| `packages/core/src/Foundation/Errors/SDKException.ts` | Sole throwable type with static factories |
| `packages/core/cpp/HybridRunAnywhereCore.cpp` | C++ implementation (split into +Extension files) |
| `packages/core/ios/PlatformAdapterBridge.m` | iOS C ABI → Swift bridge for secure storage, device info, HTTP |
| `packages/core/ios/URLSessionHttpTransport.mm` | iOS HTTP transport vtable implementation |
| `packages/core/android/src/main/cpp/okhttp_transport_adapter.cpp` | Android HTTP transport vtable via JNI → OkHttp |
| `packages/core/android/src/main/java/.../PlatformAdapterBridge.kt` | Android JNI ↔ Kotlin for platform ops + download callbacks |
| `../runanywhere-swift/ARCHITECTURE.md` | iOS layout, generated proto code, and build/deployment source of truth |
| `Docs/Documentation.md` | Public API reference |

## Conventions

- **Strict TypeScript**: `strict`, `noImplicitAny`, `strictNullChecks`, `noImplicitReturns`, `noFallthroughCasesInSwitch` all enabled
- **ESLint**: `@typescript-eslint/recommended` + `prettier`, `no-console: error`, `no-explicit-any: error`
- **Prettier**: single quotes, 2-space indent, es5 trailing commas
- **SwiftLint**: All iOS logging must go through `SDKLogger` — `print()`, `NSLog()`, `os_log()`, `debugPrint()`, `Logger` are banned
- **Versioning**: Core and backend packages share the same semver, managed by Lerna with conventional commits
- **Package naming**: Kotlin Nitro-generated code uses namespace `com.margelo.nitro.runanywhere.*`
