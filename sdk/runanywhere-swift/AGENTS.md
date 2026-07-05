# runanywhere-swift (Swift SDK)

## Info

Global rules: see repo-root AGENTS.md. iOS/Swift is the canonical reference implementation for all SDK business-logic patterns.

Swift bridge over the C++ core: all business logic lives in `RACommons.xcframework`; Swift does platform adaptation only. Layering: public API (`RunAnywhere` enum + extensions) → `CppBridge` → C ABI (`rac_*` via the `CRACommons` module) → prebuilt XCFramework. Platforms iOS 17+ / macOS 14+, Swift tools 5.9. Two `Package.swift` files: repo root (external SPM consumers, downloads XCFrameworks from GitHub releases; `useLocalNatives` toggle) and this directory (dev, references git-ignored `Binaries/`). Products: `RunAnywhere`, `RunAnywhereCore`, `RunAnywhereLlamaCPP`, `RunAnywhereONNX`. Three `.grpc.swift` files are excluded from compilation (need iOS 18/macOS 15).

Key structure:
- `Sources/RunAnywhere/Public/RunAnywhere.swift` — entry point: a `public enum` namespace, never instantiated; all consumer API is static methods/extensions under `Public/Extensions/`.
- `Sources/RunAnywhere/Foundation/Bridge/CppBridge.swift` + `Extensions/CppBridge+*.swift` (~26 files) — bridge coordinator; state under `OSAllocatedUnfairLock`.
- `Sources/RunAnywhere/Adapters/` — `LLMStreamAdapter`, `VoiceAgentStreamAdapter`, `HTTPClientAdapter`.
- `Sources/RunAnywhere/Generated/` — proto `.pb.swift` (do not edit; regenerate via codegen).
- `Sources/RunAnywhere/CRACommons/include/` — C header umbrella for the XCFramework.
- `Sources/{LlamaCPPRuntime,ONNXRuntime}/` — backend modules: thin enums exposing `register(priority:)`/`unregister()` that call `rac_backend_*_register()`; main-actor isolated; ONNX also registers the Sherpa engine plugin (STT/TTS/VAD).

Patterns to preserve:
- **Two-phase init**: Phase 1 sync (~ms — validate, register platform callbacks, Keychain); Phase 2 async background `Task` (HTTP, auth, C++ state, device registration, model discovery) guarded by a single shared Task. Every public API calls `ensureServicesReady()`; failed offline HTTP retries via `retryHTTPSetup()`.
- **Component actors**: `CppBridge.LLM/.STT/.TTS/.VAD/.VLM/.VoiceAgent` — one actor per domain holding a single opaque `rac_handle_t`, lazy `getHandle()`, `destroy()`. Shutdown destroys actors sequentially, then Telemetry and Events.
- **Interop**: everything crosses via vtable structs (`rac_platform_adapter_t`, `rac_http_transport_ops_t`, `rac_secure_storage_t`, `rac_platform_llm/tts/diffusion_callbacks_t`, `rac_discovery_callbacks_t`). C callback trampolines are `@convention(c)` free functions with `Unmanaged` context; async→sync bridging via `DispatchSemaphore`/`DispatchGroup.wait()`.
- **Streaming fan-out**: one C callback per handle, fanned out to multiple `AsyncStream` consumers via UUID-keyed continuations; proto events decoded with `RALLMStreamEvent(serializedBytes:)` etc.
- **HTTP**: `URLSessionHttpTransport` (vtable: `request_send`/`request_stream`/`request_resume`) for all C++ HTTP; `HTTPClientAdapter` actor wraps `rac_http_client_*` for SDK-level requests.
- **Types**: proto-generated `RA*` types are canonical; a small set of public typealiases strip the prefix. Never hand-write enum values — change the `.proto` and regenerate.
- **Errors**: `SDKException` wraps proto `RASDKError`; `.cancelled`/`.streamCancelled` are "expected" (logging suppressed).
- **Events**: `EventBus` singleton on Combine `PassthroughSubject`, via `RunAnywhere.events`.
- **Models**: stored at `Documents/RunAnywhere/Models/{framework}/{modelId}/`; path computation delegated to C++ (`rac_model_paths_*`).
- **Security/logging**: Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, service `com.runanywhere.sdk`; `SDKLogger` only (SwiftLint errors on `print`/`NSLog`/`os_log`); secret-ish metadata keys auto-redacted.

Rules: never `NSLock` — use `OSAllocatedUnfairLock` or actors. No `as!`, no force try. TODOs need an issue number. Warnings on `Any`/`[String: Any]`/IUOs; line warn 150 / error 200; file warn 800 / error 1500. Periphery config in `.periphery.yml` (`retain_public: true`). Speaker diarization and wake-word have C ABI stubs in commons but no Swift facade yet.

## Build Info

Requires XCFrameworks in `Binaries/` (`RACommons`, `RABackendLLAMACPP`, `RABackendONNX`, `RABackendSherpa`). Native builds run from `sdk/runanywhere-commons` (CMake root; presets there); all scripts live under repo-root `scripts/`; `./run` is the dev entry point.

```bash
# Build XCFrameworks (repo root; macOS only)
./scripts/build/deps/download-onnx.sh ios && ./scripts/build/deps/download-sherpa-onnx.sh ios
./scripts/build/ios-xcframework.sh            # or: ./run sdk commons build-ios

# SDK build / test / lint (from sdk/runanywhere-swift/)
swift build
swift test
swiftlint            # or swiftlint --fix
periphery scan

# Packaging / validation (repo root)
./scripts/release/package-swift.sh --mode local

# Xcode build
xcodebuild build -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_REQUIRED=NO

# Proto codegen (repo root)
./scripts/codegen/generate_swift.sh           # or: ./run codegen swift
```

## Work Ground

- 2026-07-05: `CRACommons/include/` headers are hand-maintained flattened copies of commons public headers — no sync script exists; update them manually when commons public headers change.
- 2026-07-05: The old `sdk/runanywhere-swift/scripts/` directory is gone; build/packaging scripts moved to repo-root `scripts/build/ios-xcframework.sh` and `scripts/release/package-swift.sh`.
