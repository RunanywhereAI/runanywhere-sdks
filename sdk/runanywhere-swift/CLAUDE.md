# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build
swift build

# Run tests
swift test

# Lint
swiftlint

# Lint with autofix
swiftlint --fix

# Analyzer (requires Xcode build log)
swiftlint analyze --compiler-log-path <path-to-xcodebuild-log>

# Unused code detection
periphery scan

# Build validation with XCFrameworks
./scripts/package-sdk.sh --mode local

# Build for specific platform via Xcode
xcodebuild build -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_REQUIRED=NO
```

## Package Structure

Two `Package.swift` files exist:
- **Root** (`runanywhere-sdks/Package.swift`): For external SPM consumers — downloads XCFrameworks from GitHub releases.
- **Local** (`sdk/runanywhere-swift/Package.swift`): For SDK development — references `Binaries/` directory (git-ignored).

Products: `RunAnywhere` (all backends), `RunAnywhereCore` (core only), `RunAnywhereLlamaCPP`, `RunAnywhereONNX`, `RunAnywhereMetalRT`, `RunAnywhereWhisperKit`.

Platforms: iOS 17+, macOS 14+. Swift tools version 5.9.

Three `.grpc.swift` files are excluded from compilation (require macOS 15/iOS 18).

## Architecture

### Three-Layer Design

All business logic lives in the C++ `RACommons.xcframework`. Swift's role is platform adaptation.

```
Public API (RunAnywhere enum + extensions)
    ↓
CppBridge (enum namespace with actor sub-namespaces)
    ↓
C ABI (rac_* functions from CRACommons module)
    ↓
RACommons.xcframework (prebuilt C++ binary)
```

### Entry Point

`RunAnywhere` is a `public enum` (namespace, never instantiated) at `Sources/RunAnywhere/Public/RunAnywhere.swift`. All consumer API is static methods on this enum or its extensions.

### Two-Phase Initialization

- **Phase 1** (synchronous, ~1-5ms): Validates params, registers platform callbacks (logging, file I/O, Keychain, HTTP transport, telemetry, device), stores to Keychain. Sets `_isInitialized = true`.
- **Phase 2** (async background `Task`): Sets up HTTP transport, authenticates, initializes C++ state, registers platform services (`@MainActor`), sets model paths, registers device, discovers downloaded models. Guarded by a single shared `Task` under `_servicesInitLock: DispatchQueue` to prevent duplicate concurrent inits.

Every public API method calls `ensureServicesReady()` which is O(1) after Phase 2 completes. If HTTP failed during offline init, it retries via `retryHTTPSetup()`.

### CppBridge

`CppBridge` at `Sources/RunAnywhere/Foundation/Bridge/CppBridge.swift` is an enum namespace. Its state is guarded by `OSAllocatedUnfairLock<CppBridgeSharedState>`. Sub-namespaces are organized as extensions in `Foundation/Bridge/Extensions/CppBridge+*.swift` (~26 extension files).

**Component actors** (one per AI domain): `CppBridge.LLM`, `.STT`, `.TTS`, `.VAD`, `.VLM`, `.VoiceAgent` — each is a Swift `actor` holding a single opaque `rac_handle_t`, with lazy creation via `getHandle()`, and `destroy()` for cleanup. `VoiceAgent.getHandle()` is `async throws` because it must gather handles from all four component actors before creating its composite handle.

**Infrastructure actors**: `CppBridge.ModelRegistry`, `CppBridge.Download` — also Swift actors wrapping C++ state.

**Pure namespaces** (no actors): `CppBridge.PlatformAdapter`, `.Environment`, `.DevConfig`, `.Endpoints`, `.Events`, `.Telemetry`, `.Device`, `.State`, `.HTTP`, `.Auth`, `.ModelPaths`, `.Services`, `.Platform`, `.FileManager`, `.Storage`, `.Strategy`, `.LoraRegistry`.

Shutdown sequence in `CppBridge.shutdown()`: destroys AI actors sequentially (LLM → STT → TTS → VAD → VoiceAgent → VLM), then Telemetry and Events.

### C↔Swift Interop Pattern

All cross-boundary communication uses **vtable-based function pointer structs**:
- `rac_platform_adapter_t` — file ops, logging, Keychain, clock, memory
- `rac_http_transport_ops_t` — HTTP transport (URLSession)
- `rac_secure_storage_t` — auth token persistence
- `rac_platform_llm/tts/diffusion_callbacks_t` — Apple platform services
- `rac_whisperkit_coreml_stt_callbacks_t` — WhisperKit STT
- `rac_discovery_callbacks_t` — filesystem callbacks for model discovery

Async Swift bridged to synchronous C ABI via `DispatchSemaphore` or `DispatchGroup.wait()`.

### Backend Module Pattern

Each runtime backend (`LlamaCPPRuntime`, `ONNXRuntime`, `MetalRTRuntime`, `WhisperKitRuntime`) is a thin `public enum` conforming to `RunAnywhereModule` whose primary job is calling a single `rac_backend_*_register()` C function. Registration is guarded by a static `isRegistered` bool.

| Module | Capabilities | Priority | Framework |
|--------|-------------|----------|-----------|
| `LlamaCPP` | `.llm` | 100 | `.llamaCpp` |
| `ONNX` | `.stt, .tts, .vad` | 100 | `.onnx` |
| `MetalRT` | `.llm, .vlm, .stt, .tts` | 100 | `.metalrt` |
| `WhisperKitSTT` | `.stt` | 200 | `.whisperKitCoreML` |

### Streaming Architecture

`LLMStreamAdapter` and `VoiceAgentStreamAdapter` use a **fan-out pattern**: one C callback registration per native handle, fanning out to multiple Swift `AsyncStream` consumers via UUID-keyed continuations. State guarded by `OSAllocatedUnfairLock`. Proto events deserialized from bytes via `RALLMStreamEvent(serializedBytes:)` / `RAVoiceEvent(serializedBytes:)`.

### HTTP Layer

Two paths sharing the same transport vtable:
- **`URLSessionHttpTransport`** — registered as `rac_http_transport_ops_t` vtable; three slots: `request_send` (buffered), `request_stream` (per-chunk), `request_resume` (with `Range: bytes=N-` header). All C++ HTTP flows through Apple's URLSession.
- **`HTTPClientAdapter`** (actor, aliased as `HTTPService`) — wraps `rac_http_client_*` for SDK-level requests (auth, device registration, telemetry). Runs blocking calls on a concurrent `DispatchQueue`.

### Type System

Proto-generated types (`RA*` prefix from `.pb.swift` files in `Generated/`) are the canonical wire types. Public Swift types are typealiases stripping the prefix (e.g., `typealias SDKComponent = RASDKComponent`, `typealias InferenceFramework = RAInferenceFramework`). Extensions on these typealiases add Swift-side computed properties, C-bridge methods (`withCOptions<T>(_:)`, `init(from cResult:)`), and `Codable` conformance.

### Error System

`SDKException` (struct at `Foundation/Errors/SDKException.swift`) wraps proto `RASDKError`. Captures `Thread.callStackSymbols` at construction. Category-specific static factories: `.stt(code, message)`, `.llm(...)`, `.network(...)`, etc. Codes `.cancelled` and `.streamCancelled` are classified as "expected" (suppress logging).

### Event System

`EventBus` (singleton) backed by Combine `PassthroughSubject<any SDKEvent, Never>`. Categories: `sdk`, `model`, `llm`, `stt`, `tts`, `voice`, `rag`, `storage`, `device`, `network`, `error`. Accessed via `RunAnywhere.events`.

### Model Management

Models stored at `Documents/RunAnywhere/Models/{framework}/{modelId}/`. Path computation delegated to C++ via `rac_model_paths_*`. Model registry is a Swift actor wrapping the C++ global registry. Model file type detection: `.gguf`/`.bin` → LlamaCPP, `.onnx`/`.ort` → ONNX, `.mlmodelc`/`.mlpackage` → CoreML, `.safetensors`/`.json` → MetalRT.

Download orchestration in `DownloadAdapter` runs `rac_http_download_execute` on a concurrent `DispatchQueue`. Cancellation via `OSAllocatedUnfairLock<Bool>` polled by the C++ progress callback.

### Security

`KeychainManager` uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (no iCloud sync) under service `com.runanywhere.sdk`. Stores API key, base URL, environment, device UUID, and auth tokens.

`DeviceIdentity.persistentUUID` resolution: Keychain → `identifierForVendor` (iOS) → new UUID.

### Logging

`SDKLogger` struct wraps `Logging.shared` singleton. `debug()` is `@inlinable` and no-ops in non-`DEBUG` builds. Metadata keys containing `key`, `secret`, `password`, `token`, `auth`, `credential` are auto-redacted.

C++ logs arrive via `platformLogCallback`; structured metadata in `"message | key=value"` format is parsed.

## Conventions and Rules

### Enforced by SwiftLint (errors, not warnings)

- No `print()`, `NSLog()`, `os_log()`, `debugPrint()`, or `Logger(` — use `SDKLogger` exclusively
- No `as!` force casts
- No `force_cast`, `force_try`
- TODOs must reference a GitHub issue number: `// TODO: #123 - description`

### Enforced by SwiftLint (warnings)

- No `Any` or `AnyObject` types — use specific types or protocols
- No `[String: Any]` dictionaries — define a struct
- No implicitly unwrapped optionals
- Sorted imports
- Lines: warn at 150 chars, error at 200
- Files: warn at 800 lines, error at 1500
- Function bodies: warn at 80 lines, error at 300
- Cyclomatic complexity: warn at 15, error at 30

### Concurrency

- **Never use `NSLock`** — use `OSAllocatedUnfairLock` (Swift 6 API) or Swift actors
- Bridge actors hold one opaque C handle each; all access is concurrency-safe via actor isolation
- C callback trampolines use `@convention(c)` free functions (no captures) with `Unmanaged.passRetained`/`.release()` for context passing
- Async-to-sync bridging uses `DispatchSemaphore` or `DispatchGroup.wait()` — required because the C ABI is synchronous

### Naming

- Platform-specific implementations use prefixes: `AndroidTTSService`, `JvmTTSService`, etc.
- Proto-generated types keep `RA` prefix; public typealiases strip it
- CppBridge extensions follow `CppBridge+{Domain}.swift` naming

### Periphery (unused code detection)

Configured in `.periphery.yml`. Scans `RunAnywhere`, `ONNXRuntime`, `LlamaCPPRuntime` targets. `retain_public: true`, `retain_codable_properties: true`.

## Key File Locations

| File | Purpose |
|------|---------|
| `Sources/RunAnywhere/Public/RunAnywhere.swift` | SDK entry point, two-phase init |
| `Sources/RunAnywhere/Foundation/Bridge/CppBridge.swift` | Bridge coordinator, init sequence, shutdown |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/` | ~26 CppBridge domain extensions |
| `Sources/RunAnywhere/Adapters/` | LLMStreamAdapter, VoiceAgentStreamAdapter, HTTPClientAdapter, DownloadAdapter |
| `Sources/RunAnywhere/HttpTransport/URLSessionHttpTransport.swift` | HTTP vtable (Apple URLSession) |
| `Sources/RunAnywhere/Public/Extensions/` | All RunAnywhere+{Feature}.swift public API extensions |
| `Sources/RunAnywhere/Generated/` | Proto-generated .pb.swift files (do not edit) |
| `Sources/RunAnywhere/CRACommons/include/` | C header umbrella for RACommons.xcframework |
| `Sources/RunAnywhere/Foundation/Security/KeychainManager.swift` | Keychain CRUD |
| `Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift` | Logging system |
| `Sources/RunAnywhere/Foundation/Errors/SDKException.swift` | Error type wrapping RASDKError |
| `Sources/RunAnywhere/Core/Module/RunAnywhereModule.swift` | Backend module protocol |
| `Sources/{LlamaCPPRuntime,ONNXRuntime,MetalRTRuntime,WhisperKitRuntime}/` | Backend module registrations |
| `Sources/RunAnywhere/Features/` | Platform services (AudioCapture, AudioPlayback, SystemTTS, FoundationModels, Diffusion) |

## Dependencies

| Package | Purpose |
|---------|---------|
| swift-crypto | Cryptographic operations |
| Files (JohnSundell) | Filesystem abstractions |
| DeviceKit | Device model identification |
| sentry-cocoa | Error reporting (optional) |
| ml-stable-diffusion | CoreML image generation |
| WhisperKit | CoreML speech recognition |
| swift-protobuf | Proto-generated type support |

## Stub Features

`SpeakerDiarization` and `WakeWord` are stub facades — all methods throw `.featureNotAvailable`. The C ABI exists in commons but is not yet wired through `CRACommons`.
