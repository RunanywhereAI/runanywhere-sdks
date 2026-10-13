# AGENTS.md — Swift SDK

Guidance for working in `bindings/swift/`, the iOS/macOS bridge (XCFramework) onto the
C++ `runanywhere-commons` core. Read the repo-root `AGENTS.md` first for cross-SDK
architecture and layering rules; this file covers what's specific to Swift.

Deeper references, not repeated here:
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — exhaustive, line-referenced walkthrough of every
  file (source of truth for anything below not covered in enough detail).
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — first-time setup, full command reference,
  PR process.
- [`README.md`](README.md) — consumer-facing install/usage, capability table, Connect (LAN
  session sharing) feature.

## Build commands

```bash
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift build     # build (needs Binaries/, see below)
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift test      # run tests
swiftlint                                       # lint (swiftlint --fix to autofix)
periphery scan                                  # unused-code detection
./scripts/package-sdk.sh --mode local           # packaging validation against Binaries/
xcodebuild build -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_REQUIRED=NO
```

`Binaries/` (git-ignored XCFrameworks) must be staged first via
`./scripts/build-core-xcframework.sh`, or `swift build` fails; `docs/DEVELOPMENT.md` has
the full first-run sequence. `swiftlint analyze` needs a compiler log
(`--compiler-log-path <xcodebuild.log>`); pre-commit runs `swiftlint --strict`, which
also fails on warning-level rules (e.g. the TODO-must-reference-an-issue custom rule).

## Package structure

Two `Package.swift` files: the repo-root one is for external SPM consumers (downloads
XCFrameworks from GitHub releases); `bindings/swift/Package.swift` is for SDK development
(references the git-ignored `Binaries/`). Swift tools version 6.2; platforms iOS 17.5+ /
macOS 14.5+ (Xcode 26+ is a hard floor because the MLX target needs the 6.2 toolchain).

Products: `RunAnywhere` (core only — model lifecycle, events; no backend does anything
without one of the below), `RunAnywhereLlamaCPP` (LLM+VLM via llama.cpp),
`RunAnywhereONNX` (STT/TTS/VAD via ONNX + Sherpa), `RunAnywhereMLX` (Apple MLX
LLM/VLM/STT/TTS), `RunAnywhereNeuRT` (Apple Neural Engine text gen + CoreML diffusion).
Three `.grpc.swift` files under `Generated/` are excluded from compilation (need iOS
18/macOS 15, above the SDK floor); an in-process C callback path replaces gRPC.

## Architecture

### Three-layer design

All business logic lives in the C++ `RACommons.xcframework`; Swift's job is platform
adaptation. The public API (`RunAnywhere` enum + extensions) calls `CppBridge`, which
calls the `rac_*` C ABI from the `CRACommons` module — implemented by the prebuilt
xcframework, never by Swift.

### Entry point and two-phase init

`RunAnywhere` (`Sources/RunAnywhere/Public/RunAnywhere.swift`) is a `public enum`
namespace, never instantiated; all consumer API is static methods on it or its
extensions. The public surface follows the cross-SDK v3 contract (14 namespaces —
`llm`, `vlm`, `stt`, `tts`, `vad`, `embeddings`, `rerank`, `images`, `diarization`,
`segmentation`, `voice`, `rag`, `models`, `lora` — plus core members `initialize`,
`reset`, `isReady`, `version`, `deviceId`, `events`) under `Public/API/`; option
defaults are read from generated IDL `defaults()`, never hand-copied, so `idl/*.proto`
stays the single source of truth. `Public/Extensions/` carries the older flat verbs
(`loadModel`, `transcribe`, `ragQuery`, …) as `@available(*, deprecated)` forwarders —
new code calls the namespaces. `voice.createSession(...)` and `rag.open(...)` hand back
long-lived sessions (`VoiceSession`, `RagSession`) with their own native handles.

- **Phase 1** (sync, ~1–5ms): validates params, registers platform callbacks (logging,
  file I/O, Keychain, HTTP transport, telemetry, device), stores to Keychain, sets
  `_isInitialized = true`.
- **Phase 2** (async background `Task`, guarded by `_servicesInitLock` so concurrent
  callers can't double-init): HTTP transport, auth, C++ state, platform services
  (`@MainActor`), model paths, device registration, downloaded-model discovery.

Every public API call goes through `ensureServicesReady()` (O(1) once Phase 2 is done);
if HTTP failed during offline init, it retries via `retryHTTPSetup()`.

### CppBridge

`CppBridge` (`Foundation/Bridge/CppBridge.swift`) is an enum namespace whose state is
guarded by `OSAllocatedUnfairLock<CppBridgeSharedState>`; sub-namespaces live as
extensions in `Foundation/Bridge/Extensions/CppBridge+*.swift` (34 files). Most
capability sub-namespaces are Swift `actor`s, each wrapping one opaque `rac_handle_t`
with lazy `getHandle()` and a `destroy()`: `LLM`, `STT`, `TTS`, `VAD`, `VLM`,
`VoiceAgent`, `RAG`, `Diffusion`, `Rerank`, `Diarization`, `Storage`, `LoraRegistry`,
`ModelRegistry`, `Download`. `VoiceAgent.getHandle()` is `async throws` because it
gathers handles from four component actors before building its composite handle.
Everything else (`PlatformAdapter`, `Environment`, `Events`, `Telemetry`, `Device`,
`HTTP`, `Auth`, `ModelPaths`, `Connect`, …) is a plain namespace, no actor. `Connect`
backs `ConnectSession`, trusted-LAN model sharing (macOS host, iOS/iPadOS client) — see
README.md for the feature, ARCHITECTURE.md §6.5 for the bridge slice.

Shutdown (`CppBridge.shutdown()`) destroys AI actors sequentially — LLM → STT → TTS →
VAD → VoiceAgent → VLM — then Telemetry and Events.

### C to Swift interop

Cross-boundary calls use vtable-based function-pointer structs: `rac_platform_adapter_t`
(file ops, logging, Keychain, clock, memory), `rac_http_transport_ops_t` (URLSession),
`rac_secure_storage_t` (auth tokens), `rac_platform_llm/tts/diffusion_callbacks_t`
(Apple platform services), `rac_discovery_callbacks_t` (model-discovery filesystem
callbacks). Async Swift bridges to the synchronous C ABI via `DispatchSemaphore` or
`DispatchGroup.wait()`.

### Backend module pattern

Each backend is a thin `public enum` with static `register(priority:)` /
`unregister()` / `autoRegister`, whose job is calling `rac_backend_*_register()`.
Registration state is main-actor isolated so register/unregister can't race.

| Module | Capabilities | Framework case |
|--------|-------------|-----------------|
| `LlamaCPPRuntime` | LLM + VLM (unified llama.cpp vtable) | `.llamaCpp` |
| `ONNXRuntime` | Embeddings + Sherpa-ONNX plugin (STT/TTS/VAD) | `.onnx`; also registers Sherpa separately |
| `MLXRuntime` | LLM/VLM/embeddings (mlx-swift-lm) + STT/TTS/VAD (mlx-audio-swift) | `.mlx` |
| `NeuRTRuntime` | Apple Neural Engine text gen + CoreML diffusion | `.coreml` — **not** `.neurt`; commons maps `INFERENCE_FRAMEWORK_COREML` → `RAC_ENGINE_ID_NEURT`, there is no `.neurt` framework case |

### Streaming, HTTP, types, errors, events

`LLMStreamAdapter` / `VoiceAgentStreamAdapter` fan out one C callback per handle to
multiple Swift `AsyncStream` consumers via UUID-keyed continuations
(`OSAllocatedUnfairLock`-guarded), deserializing proto events with
`RALLMStreamEvent(serializedBytes:)` / `RAVoiceEvent(serializedBytes:)`.

`URLSessionHttpTransport` is the registered `rac_http_transport_ops_t` vtable (all C++
HTTP flows through it: buffered `request_send`, per-chunk `request_stream`, resumable
`request_resume` with `Range:` headers). `HTTPClientAdapter` (actor, aliased
`HTTPService`) separately wraps `rac_http_client_*` for SDK-level requests (auth,
device registration, telemetry) on a concurrent `DispatchQueue`.

Proto-generated `RA*`-prefixed types (`.pb.swift` in `Generated/`) are canonical; a
handful of public typealiases strip the prefix at the SDK surface (e.g.
`InferenceFramework = RAInferenceFramework`). Extensions add C-bridge methods
(`withCOptions<T>(_:)`, `init(from cResult:)`) and `Codable` conformance.

`SDKException` (`Foundation/Errors/SDKException.swift`) wraps proto `RASDKError`,
captures `Thread.callStackSymbols` at construction, and exposes category factories
(`.stt(...)`, `.llm(...)`, `.network(...)`). `.cancelled` / `.streamCancelled` are
"expected" and suppress logging.

`EventBus` (singleton, Combine `PassthroughSubject<any SDKEvent, Never>`) covers `sdk`,
`model`, `llm`, `stt`, `tts`, `voice`, `rag`, `storage`, `device`, `network`, `error` —
accessed via `RunAnywhere.events`.

### Model management, security, logging

Models live at `Documents/RunAnywhere/Models/{framework}/{modelId}/`; path computation
and model-file-extension → framework detection (`.gguf`/`.bin`→LlamaCPP,
`.onnx`/`.ort`→ONNX, `.mlmodelc`/`.mlpackage`→CoreML, `.json` QNN bundles→QHexRT) are
commons-side, reached via `rac_model_paths_*`. Download orchestration
(`rac_http_download_execute`) runs on a concurrent `DispatchQueue`; cancellation is an
`OSAllocatedUnfairLock<Bool>` polled by the C++ progress callback.

`KeychainManager` uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (no iCloud sync)
under service `com.runanywhere.sdk`. `DeviceIdentity.persistentUUID` resolves Keychain →
`identifierForVendor` (iOS) → new UUID.

`SDKLogger` wraps `Logging.shared`; `debug()` is `@inlinable` and no-ops outside
`DEBUG`. Metadata keys containing `key`/`secret`/`password`/`token`/`auth`/`credential`
are auto-redacted. C++ logs arrive via `platformLogCallback`, parsing structured
`"message | key=value"` metadata.

## Conventions enforced by SwiftLint

Errors (block CI and `--strict` pre-commit): no `print()`/`NSLog()`/`os_log()`/
`debugPrint()`/`Logger(` — use `SDKLogger` only; no `as!`/`force_cast`/`force_try`.

Warnings (still block `--strict` pre-commit, not plain `swiftlint`): no `Any`/
`AnyObject`/`[String: Any]`; no implicitly-unwrapped optionals; sorted imports; TODOs
must reference an issue (`// TODO: #123 - description`); lines warn@150/error@200;
files warn@800/error@1500; function bodies warn@80/error@300; cyclomatic complexity
warn@15/error@30.

Concurrency: never `NSLock` — use `OSAllocatedUnfairLock` or a Swift actor; C callback
trampolines are `@convention(c)` free functions (no captures) using
`Unmanaged.passRetained`/`.release()` for context. Naming: platform impls get an
explicit prefix (`AndroidTTSService`); `CppBridge+{Domain}.swift` per extension.

Periphery (`.periphery.yml`) scans `RunAnywhere`, `ONNXRuntime`, `LlamaCPPRuntime`
(not the MLX/NeuRT targets) with `retain_public: true`, `retain_codable_properties: true`.

## Key file locations

| File | Purpose |
|------|---------|
| `Sources/RunAnywhere/Public/RunAnywhere.swift` | SDK entry point, two-phase init |
| `Sources/RunAnywhere/Foundation/Bridge/CppBridge.swift` | Bridge coordinator, init/shutdown |
| `Sources/RunAnywhere/Foundation/Bridge/Extensions/` | 42 CppBridge domain extensions |
| `Sources/RunAnywhere/Adapters/` | LLMStreamAdapter, VoiceAgentStreamAdapter, HTTPClientAdapter |
| `Sources/RunAnywhere/HttpTransport/URLSessionHttpTransport.swift` | HTTP vtable |
| `Sources/RunAnywhere/Public/Extensions/` | Public API extensions, one per feature |
| `Sources/RunAnywhere/Generated/` | Proto-generated `.pb.swift` (never hand-edit) |
| `Sources/RunAnywhere/CRACommons/include/` | C header umbrella for RACommons.xcframework |
| `Sources/{LlamaCPPRuntime,ONNXRuntime,MLXRuntime,NeuRTRuntime}/` | Backend module registrations |
| `Sources/RunAnywhere/Features/` | Platform services (audio capture/playback, system TTS, Foundation Models) |

## Dependencies

| Package | Purpose |
|---------|---------|
| swift-crypto, swift-protobuf | Crypto ops; proto-generated type support |
| Files (JohnSundell) | Filesystem abstractions |
| DeviceKit | Device model identification |
| mlx-swift, mlx-swift-lm (RunanywhereAI forks) | MLX core + LLM/VLM/embeddings — pin exactly, mirrored in `Generated/Versions.swift` |
| mlx-audio-swift (RunanywhereAI fork) | MLX STT/TTS/VAD/diarization |
| swift-transformers (huggingface) | Tokenizers for MLX |

## Capability notes

Speaker diarization (`RunAnywhere.diarization`) and semantic segmentation
(`RunAnywhere.segmentation`) each require their backend registered. There is no
wake-word facade.

Three spec fields have no commons emitter, so they read as absent rather than wrong:
`VoiceEvent` has no audio-level event; `SegmentationOptions.includeDiagnosticImage` has
no field on `SegmentationResult` to land in; `LoadOptions.contextLength`, `.threads`,
`.useGpu` are logged and dropped (commons load ABI doesn't carry them).
