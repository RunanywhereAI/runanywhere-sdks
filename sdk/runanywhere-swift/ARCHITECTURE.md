# RunAnywhere Swift SDK — Architecture (Source of Truth)

> Updated: 2026-05-11
> Branch: feat/v2-architecture @ 40c668d86
> Purpose: The Swift SDK is the canonical reference for the cross-platform RunAnywhere SDKs. All other SDKs (Kotlin, Flutter, React Native, Web) align to this document for folder structure, naming, public API surface, bridge organization, and business logic.
> Status: 95 hand-written .swift files (16,918 LOC) + 31 generated files (~47,432 LOC). flutter analyze / swift build clean.

**How to read this document:** To align a folder structure in another SDK, read §4. To align the public API surface, read §5. To align bridge slice organization, read §6. To align cross-cutting foundation utilities, read §7. To align streaming adapters, read §8. To align infrastructure (device/download/logging), read §9. To align HTTP transport plumbing, read §10. To align native plumbing patterns for system-backed features, read §11. To understand what is codegen vs. hand-written, read §12. To understand the Swift↔C++ contract end-to-end, read §13. To align conventions (naming, concurrency, errors, logging), read §14. For build/packaging, read §15. For a complete LOC inventory, read §16. For terminology, see Appendix A. For cross-SDK mapping, see Appendix B.

## Table of Contents

- [§1 Overview & Goals](#1-overview--goals)
- [§2 Two-Phase Init](#2-two-phase-init)
- [§3 Platform Adapter IoC](#3-platform-adapter-ioc)
- [§4 Top-Level Folder Tree](#4-top-level-folder-tree)
- [§5 Public API](#5-public-api)
- [§6 CppBridge Architecture](#6-cppbridge-architecture)
- [§7 Foundation Utilities](#7-foundation-utilities)
- [§8 Adapters & Streaming](#8-adapters--streaming)
- [§9 Infrastructure](#9-infrastructure)
- [§10 HttpTransport](#10-httptransport)
- [§11 Features (system-backed)](#11-features-system-backed)
- [§12 Generated Code](#12-generated-code)
- [§13 How Swift Talks to C++](#13-how-swift-talks-to-c)
- [§14 Conventions & Idioms](#14-conventions--idioms)
- [§15 Build & Deployment](#15-build--deployment)
- [§16 File-by-File Inventory](#16-file-by-file-inventory)
- [Appendix A — Glossary](#appendix-a--glossary)
- [Appendix B — Cross-SDK Alignment Quick Reference](#appendix-b--cross-sdk-alignment-quick-reference)

---

## §1 Overview & Goals

### §1.1 Goals

The Swift SDK (`sdk/runanywhere-swift/`) is a thin platform bridge that adapts Apple platform services (file I/O, HTTP via URLSession, Keychain, audio capture/playback) into the inversion-of-control struct (`rac_platform_adapter_t`) required by the C++ `runanywhere-commons` core. It is the designated source-of-truth for all other SDK implementations: when business logic is unclear in Kotlin, Flutter, or React Native, the Swift implementation is the reference. All AI inference, model routing, and event orchestration run inside `RACommons.xcframework`; Swift only supplies platform services and exposes a public Swift API surface.

### §1.2 Platform requirements

- iOS deployment target: 17.0 (`Package.swift:24`)
- macOS deployment target: 14.0 (`Package.swift:25`)
- Swift tools version: 5.9 (`Package.swift:1`)
- Xcode required: 15+
- Current SDK version: `0.19.13` (`sdk/runanywhere-swift/VERSION:1`)

### §1.3 Package layout (preview)

A high-level glance follows; the full tree is documented in §4.

```
sdk/runanywhere-swift/
├── Package.swift               ← local dev manifest (references Binaries/)
├── Sources/
│   ├── RunAnywhere/            ← Adapters, CRACommons, Features, Foundation, Generated, HttpTransport, Infrastructure, Public
│   ├── LlamaCPPRuntime/        ← LlamaCPPBackend C bridge headers
│   └── ONNXRuntime/            ← ONNXBackend C bridge headers
├── Tests/RunAnywhereTests/     ← 6 test files
└── Binaries/                   ← git-ignored XCFrameworks
```

---

## §2 Two-Phase Init

The Swift SDK follows a strict two-phase initialization contract identical to the contract every other RunAnywhere SDK obeys:

- **Phase 1 (synchronous)** — register the platform adapter (§3), wire the HTTP transport (§10), configure logging, call `rac_sdk_init_phase1_proto`. After Phase 1 returns, the SDK is `isInitialized = true` and the C ABI can be called.
- **Phase 2 (async)** — spawn a detached Task that performs HTTP setup, authentication, device registration, model assignment fetch, and downloaded-model discovery via `rac_sdk_init_phase2_proto`. Phase 2 failures are non-fatal — the SDK proceeds in offline mode.

The Swift-side entry point for both phases is documented in detail in §5.1 (caller surface, `RunAnywhere.initialize` and `RunAnywhere.completeServicesInitialization`). The lower-level C ABI plumbing — `CppBridge.SdkInit.phase1`, `phase2`, `retryHTTP` — is documented in §13.7. Cross-SDK alignment for this pattern is in Appendix B.

---

## §3 Platform Adapter IoC

`rac_platform_adapter_t` is a flat C struct of 18 function-pointer slots and one `void* user_data`. Swift populates this struct and passes it via `rac_set_platform_adapter()` before calling `rac_init()`. C++ never calls platform APIs directly — file I/O, secure storage, logging, error tracking, clock, memory queries, HTTP download, archive extraction, directory enumeration, and vendor ID resolution all route through this struct.

The Swift implementation of every slot lives in `Foundation/Bridge/Extensions/CppBridge+PlatformAdapter.swift` (733 LOC). Each slot is a file-scope `@convention(c)` free function assigned by name into a static `var adapter: rac_platform_adapter_t`. The struct is stored as a `static var` (not `let`) because C++ holds a pointer to it for the process lifetime; a guard flag prevents re-registration.

The full slot map and per-slot implementation notes are documented in §6.5.18 (Swift impl) and §13.3 (C ABI contract).

---

## §4 Top-Level Folder Tree

```
sdk/runanywhere-swift/
├── Package.swift               ← local dev manifest (references Binaries/)
├── Package.resolved
├── VERSION                     ← 0.19.13
├── AGENTS.md
├── README.md
├── ARCHITECTURE.md             ← this document
├── scripts/
├── Sources/
│   ├── RunAnywhere/
│   │   ├── Adapters/           ← LLMStreamAdapter, VoiceAgentStreamAdapter, HandleStreamAdapter
│   │   ├── CRACommons/         ← C bridge module: module.modulemap + include/ (97 rac_*.h) + shim.c
│   │   ├── Features/           ← AudioCapture, AudioPlayback, SystemTTS, FoundationModels, Diffusion
│   │   ├── Foundation/         ← Bridge/, Errors/, Security/, Constants/, Core/
│   │   ├── Generated/          ← Proto-generated *.pb.swift + RAConvenience + ModalityProtoABI+Generated
│   │   ├── HttpTransport/      ← URLSessionHttpTransport.swift
│   │   ├── Infrastructure/     ← Device/, Download/, FileManagement/, Logging/
│   │   └── Public/             ← RunAnywhere.swift + Extensions/RunAnywhere+*.swift
│   ├── LlamaCPPRuntime/
│   │   └── include/            ← LlamaCPPBackend C bridge headers
│   └── ONNXRuntime/
│       └── include/            ← ONNXBackend C bridge headers
├── Tests/
│   └── RunAnywhereTests/       ← 6 test files
└── Binaries/                   ← git-ignored XCFrameworks (4 present)
    ├── RACommons.xcframework
    ├── RABackendLLAMACPP.xcframework
    ├── RABackendONNX.xcframework
    └── RABackendSherpa.xcframework
```

The seven top-level subdirectories under `Sources/RunAnywhere/` are each documented in detail later: `Public/` (§5), `Foundation/Bridge/` (§6), `Foundation/` non-bridge (§7), `Adapters/` (§8), `Infrastructure/` (§9), `HttpTransport/` (§10), `Features/` (§11), `Generated/` (§12).

---

## §5 Public API

The public API of the SDK is delivered through a single namespace `enum RunAnywhere` plus 25 capability-extension files under `Public/Extensions/`. Every public method validates `isInitialized`, optionally awaits `ensureServicesReady()`, and delegates to either a `CppBridge` actor/namespace or directly to a C ABI symbol via `NativeProtoABI`. No business logic lives in Swift; every method is a thin facade.

### §5.1 Entry Point — `enum RunAnywhere`

File: `sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift` (~404 LOC)

`RunAnywhere` is declared as `public enum RunAnywhere` (line 27) — a caseless enum used as an uninstantiable namespace. All state and behavior are `static`.

#### Internal state fields (not public)

| Symbol | Type | Purpose | Line |
|---|---|---|---|
| `initParams` | `SDKInitParams?` | Persisted params from `initialize(…)` | 32 |
| `currentEnvironment` | `SDKEnvironment?` | Environment set at Phase 1 | 33 |
| `isInitializedFlag` | `Bool` | Set `true` when Phase 1 completes | 34 |
| `hasCompletedServicesInit` | `Bool` | Set `true` when Phase 2 completes | 37 |
| `hasCompletedHTTPSetup` | `Bool` | Set `true` when HTTP/auth succeeds in Phase 2 | 39 |
| `_servicesInitTask` | `Task<Void, Error>?` | Shared Phase 2 task (prevents duplicate concurrent inits) | 43 |
| `_servicesInitLock` | `DispatchQueue` | Serializes check-and-set on `_servicesInitTask` | 46 |

#### State accessors (all `public static`)

| Symbol | Type | Returns | Backing | Line |
|---|---|---|---|---|
| `isInitialized` | `Bool` | `true` after Phase 1 completes | `isInitializedFlag` | 51 |
| `areServicesReady` | `Bool` | `true` after Phase 2 completes | `hasCompletedServicesInit` | 54 |
| `isActive` | `Bool` | `isInitializedFlag && initParams != nil` | both internal flags | 57 |
| `version` | `String` | SDK version string | `SDKConstants.version` | 60 |
| `environment` | `SDKEnvironment?` | Current environment or `nil` | `currentEnvironment` | 63 |
| `deviceId` | `String` | Keychain-persisted device UUID | `CppBridge.Device.persistentId` | 68 |
| `events` | `EventBus` | The event bus singleton | `EventBus.shared` | 73 |
| `isAuthenticated` | `Bool` | Whether auth token is present | `CppBridge.Auth.isAuthenticated` | 84 |

#### Static methods (public)

| Symbol | Signature | Throws? | Calls | Line |
|---|---|---|---|---|
| `initialize(apiKey:baseURL:environment:)` | `static func (String?, String?, SDKEnvironment) throws` | yes | `performCoreInit(with:startBackgroundServices:)` | 112 |
| `initialize(apiKey:baseURL:environment:)` | `static func (String, URL, SDKEnvironment) throws` | yes | `performCoreInit(with:startBackgroundServices:)` | 131 |
| `completeServicesInitialization()` | `static func () async throws` | yes | `_performServicesInitialization()` under `_servicesInitLock` | 229 |
| `getUserId()` | `static func () -> String?` | no | `CppBridge.State.userId` | 78 |
| `getOrganizationId()` | `static func () -> String?` | no | `CppBridge.State.organizationId` | 81 |
| `isDeviceRegistered()` | `static func () -> Bool` | no | `CppBridge.Device.isRegistered` | 87 |
| `reset()` | `static func () async` | no | `CppBridge.shutdown()`, `CppBridge.State.shutdown()` | 92 |

#### Two-phase init detail

##### Phase 1 — `performCoreInit(with:startBackgroundServices:)` (synchronous, lines 142–222)

Runs entirely on the calling thread. The steps in order:

1. **Guard idempotency** (line 143): returns immediately if `isInitializedFlag` is already `true`.
2. **Set environment + params** (lines 149–150): writes `currentEnvironment` and `initParams`; calls `Logging.shared.applyEnvironmentConfiguration(params.environment)` so all subsequent logs carry the correct verbosity.
3. **Initialize C++ bridges** (line 156): calls `CppBridge.initialize(environment:)` — registers platform adapter (file I/O, logging, Keychain, clock, memory queries), wires telemetry callbacks, and wires device callbacks. Must precede any C ABI call.
4. **Emit init-started event** (line 159): `CppBridge.Events.emitSDKInitStarted()`.
5. **Persist credentials to Keychain** (lines 163–165): `KeychainManager.shared.storeSDKParams(params)` — skipped for `.development`.
6. **Set model-paths base directory** (lines 170–176): `CppBridge.ModelPaths.setBaseDirectory(documentsURL)` — configures the C++ model registry's root path before any model calls.
7. **C++ Phase 1 proto** (lines 179–184): `CppBridge.SdkInit.phase1(environment:apiKey:baseURL:deviceId:)` — calls `rac_sdk_init_phase1_proto` in commons; validates inputs and runs `rac_state_initialize`.
8. **SDK config / Keychain auth-storage install** (lines 189–194): `CppBridge.State.initialize(environment:apiKey:baseURL:deviceId:)` — idempotent re-init that wires version/platform metadata not touched by Phase 1 proto.
9. **Set `isInitializedFlag = true`** (line 196).
10. **Emit init-completed event** (line 200): `CppBridge.Events.emitSDKInitCompleted(durationMs:)`.
11. **Spawn Phase 2** (lines 204–213): `Task.detached(priority: .userInitiated)` calls `completeServicesInitialization()`. Errors are caught and logged as non-critical warnings — Phase 1 always returns to the caller before Phase 2 starts.

On any error in steps 5–8: `initParams` is cleared, `isInitializedFlag` stays `false`, `CppBridge.Events.emitSDKInitFailed(error:)` fires, and the error is rethrown (lines 215–221).

##### Phase 2 — `_performServicesInitialization()` (async, lines 254–312)

Runs inside the single shared `Task` serialized by `_servicesInitLock`. Steps:

1. **Step 1 — HTTP transport + auth** (lines 263–275): if `CppBridge.HTTP.shared.isConfigured` is `false`, calls `setupHTTP(params:environment:logger:)`. For `.development`: tries `CppBridge.DevConfig.configureHTTP()` (Supabase from C++ config). For staging/production: calls `CppBridge.HTTP.shared.configure(baseURL:apiKey:)` then `CppBridge.Auth.authenticate(apiKey:)`. Tolerates failure — proceeds in offline mode. On success, calls `CppBridge.Telemetry.flush()`.
2. **Step 2 — Platform plugin registration** (line 278): `await MainActor.run { CppBridge.initializeServices() }` — must be on the main actor (Apple restriction for `@MainActor` platform plugins).
3. **Step 3 — C++ Phase 2 proto** (line 283): `CppBridge.SdkInit.phase2()` — calls `rac_sdk_init_phase2_proto` in commons, which drives device registration, model assignments, and HTTP-state snapshot.
4. **Step 4 — Dev-mode device registration** (lines 296–302): only for `.development` when `CppBridge.DevConfig.hasUsableDevelopmentRegistrationConfig`; calls `CppBridge.Device.registerIfNeeded(environment:)` with build token. Non-critical — failure is logged as a warning.
5. **Step 5 — Model discovery** (lines 306–309): `CppBridge.ModelRegistry.shared.discoverDownloadedModels()` — filesystem scan using the C++ registry handle.
6. **Set `hasCompletedServicesInit = true`** (line 311).

`completeServicesInitialization()` (the public wrapper, lines 229–248) is safe to call concurrently: the first caller creates the `Task`, subsequent concurrent callers receive the same `Task` via `_servicesInitLock.sync { }` and await its result without spawning duplicates.

### §5.2 Configuration — SDKEnvironment

File: `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Configuration/SDKEnvironment.swift` (~239 LOC)

#### Typealias

```swift
public typealias SDKEnvironment = RASDKEnvironment  // line 20
```

`RASDKEnvironment` is the proto3-generated enum from `idl/model_types.proto`. The hand-written enum was removed; all SDK logic operates on the generated type through extensions.

Cases (from proto): `.development`, `.staging`, `.production`, `.unspecified` (proto default), `UNRECOGNIZED` (proto catch-all).

#### Codable conformance (lines 29–39)

`RASDKEnvironment` is extended to conform to `Codable`. Decoding reads a single `String` value and maps it via `RASDKEnvironment.from(wireString:)` (codegen accessor from `Generated/RAConvenience.swift`), defaulting to `.unspecified` on unknown strings. Encoding writes `self.wireString` — the lowercase wire-format string from the proto annotation.

#### Extension computed properties (lines 43–133)

| Symbol | Type | Mechanism | Line |
|---|---|---|---|
| `deployableCases` | `static [RASDKEnvironment]` | Hardcoded array `[.development, .staging, .production]` | 47 |
| `cEnvironment` | `rac_environment_t` | Switch to C enum constants (`RAC_ENV_DEVELOPMENT`, `RAC_ENV_STAGING`, `RAC_ENV_PRODUCTION`) | 54 |
| `description` | `String` | Switch returning human-readable label | 64 |
| `isProduction` | `Bool` | `rac_env_is_production(cEnvironment)` | 74 |
| `isTesting` | `Bool` | `rac_env_is_testing(cEnvironment)` | 77 |
| `requiresBackendURL` | `Bool` | `rac_env_requires_backend_url(cEnvironment)` | 80 |
| `isCompatibleWithCurrentBuild` | `Bool` | Swift `#if DEBUG` check; production returns `false` in DEBUG builds | 86 |
| `isDebugBuild` | `static Bool` | `#if DEBUG` flag | 102 |
| `defaultLogLevel` | `LogLevel` | Switch: `.development` → `.debug`, `.staging` → `.info`, `.production` → `.warning` | 113 |
| `shouldSendTelemetry` | `Bool` | `rac_env_should_send_telemetry(cEnvironment)` | 123 |
| `useMockData` | `Bool` | `self == .development` | 126 |
| `shouldSyncWithBackend` | `Bool` | `rac_env_should_sync_with_backend(cEnvironment)` | 129 |
| `requiresAuthentication` | `Bool` | `rac_env_requires_auth(cEnvironment)` | 132 |

All C-delegating properties call into the `CRACommons` module via the `cEnvironment` bridge property.

#### `SDKInitParams` struct (lines 136–239)

`public struct SDKInitParams` — value type carrying the three init parameters.

| Field | Type | Line |
|---|---|---|
| `apiKey` | `String` | 138 |
| `baseURL` | `URL` | 143 |
| `environment` | `SDKEnvironment` | 145 |

Initializers:

- `init(apiKey:baseURL:environment:)` (URL overload, line 162): stages/production; calls `Self.validate(apiKey:baseURL:environment:)` which invokes `rac_validate_api_key` and `rac_validate_base_url` C functions.
- `init(apiKey:baseURL:environment:)` (String overload, line 176): parses URL string first, then delegates to the URL overload.
- `init(forDevelopmentWithAPIKey:)` (line 186): sets `.development`, uses `developmentPlaceholderURL` (`https://dev.runanywhere.local`), skips validation.

Validation (lines 194–238) calls `rac_validate_api_key(ptr, cEnv)` and `rac_validate_base_url(ptr, cEnv)`, mapping C result codes (`RAC_VALIDATION_API_KEY_REQUIRED`, `RAC_VALIDATION_API_KEY_TOO_SHORT`, etc.) to `SDKException` with `.invalidApiKey` or `.validationFailed` codes.

### §5.3 Events — EventBus

File: `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Events/EventBus.swift` (~91 LOC)

#### Declaration and singleton

```swift
public final class EventBus: @unchecked Sendable  // line 25
public static let shared = EventBus()              // line 29
```

`@unchecked Sendable` — the class manages its own thread safety through Combine's subject internals. The singleton is accessed via `RunAnywhere.events` (which returns `EventBus.shared`, `RunAnywhere.swift` line 73).

#### Backing mechanism

```swift
private let subject = PassthroughSubject<RASDKEvent, Never>()  // line 33
```

A single `PassthroughSubject` holds all event flow. Events originate from two sources:

1. **Native C++ subscription** (lines 45–47, inside `private init()`): `CppBridge.Events.subscribeSDKEvents { [weak self] event in self?.subject.send(event) }` — registers a closure with the C++ event system; `nativeSubscriptionId` (line 40) stores the returned handle for teardown.
2. **Direct Swift publish** (lines 59–63): `publish(_:)` calls `CppBridge.Events.publishSDKEvent(event)` first; if that returns `false` (C++ routing did not handle it), the event is sent directly into `subject`.

On `deinit` (lines 50–53): `CppBridge.Events.unsubscribeSDKEvents(nativeSubscriptionId)` cleans up the C++ subscription when `nativeSubscriptionId != 0`.

#### Public methods

| Symbol | Signature | Returns | Line |
|---|---|---|---|
| `publish(_:)` | `func (RASDKEvent)` | `Void` | 59 |
| `events` | `var` (computed) | `AnyPublisher<RASDKEvent, Never>` | 36 |
| `events(for:)` | `func (RAEventCategory) -> AnyPublisher<RASDKEvent, Never>` | filtered publisher | 68 |
| `on(_:)` | `func ((RASDKEvent) -> Void) -> AnyCancellable` | cancellable subscription | 75 |
| `on(_:handler:)` | `func (RAEventCategory, (RASDKEvent) -> Void) -> AnyCancellable` | category-filtered cancellable | 82 |

`events(for:)` (lines 68–71): chains `.filter { $0.category == category }` on `subject` before erasing to `AnyPublisher`. No pre-defined category stream properties exist in this file — filtering is always done at subscription time via the `RAEventCategory` enum value.

`on(_:)` (lines 75–79): returns `subject.sink { handler($0) }` as `AnyCancellable`.

`on(_:handler:)` (lines 82–88): delegates to `events(for: category).sink { handler($0) }`.

#### Thread safety

`PassthroughSubject` in Combine serializes `send(_:)` calls through its internal lock. The `[weak self]` closure from `CppBridge.Events.subscribeSDKEvents` can be called from any C++ thread; `subject.send(event)` inside it is safe because Combine's subject handles concurrent sends. No additional locking is present in this file.

#### Event type

All events are typed as `RASDKEvent` (proto-generated). Category filtering uses `RAEventCategory` (also proto-generated). The event category set is defined in `idl/*.proto`, not in this file.

### §5.4 Capability Extensions

All capability-specific public API is delivered through `public extension RunAnywhere` blocks in `Public/Extensions/<Domain>/RunAnywhere+<Topic>.swift` files. Each method is a thin facade: validate `isInitialized`, optionally call `ensureServicesReady()`, delegate to `CppBridge` or `NativeProtoABI`.

#### §5.4.1 LLM

The LLM extensions (`Public/Extensions/LLM/`) form the public LLM surface of the Swift SDK. Every method is a thin facade that validates `isInitialized`, calls `ensureServicesReady()`, and then delegates immediately to a `CppBridge` actor or C ABI function. No business logic lives in Swift.

##### §5.4.1.1 RunAnywhere+TextGeneration.swift

**File:** `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+TextGeneration.swift` (LOC: 76)
**Mirrors C ABI:** `CppBridge.LLM.shared.generate`, `CppBridge.LLM.shared.generateStream`, `CppBridge.LLM.shared.cancel`, `CppBridge.StructuredOutput.parse`, `CppBridge.StructuredOutput.makeParseRequest`
**Concurrency:** `async throws` (generate, generateStream), `async` (cancelGeneration), `throws` (extractStructuredOutput — sync)

| Symbol | Signature | Line | Calls | Notes |
|---|---|---|---|---|
| `generate` | `static func generate(_ request: RALLMGenerateRequest) async throws -> RALLMGenerationResult` | 18 | `CppBridge.LLM.shared.generate(request)` | Guards `isInitialized`; awaits `ensureServicesReady()` |
| `generateStream` | `static func generateStream(_ request: RALLMGenerateRequest) async throws -> AsyncStream<RALLMStreamEvent>` | 36 | `CppBridge.LLM.shared.generateStream(request)` | Returns stream object; stream events arrive from C++ fan-out |
| `cancelGeneration` | `static func cancelGeneration() async` | 54 | `CppBridge.LLM.shared.cancel()` | No-ops if not initialized |
| `extractStructuredOutput` | `static func extractStructuredOutput(text: String, schema: RAJSONSchema) throws -> RAStructuredOutputResult` | 68 | `CppBridge.StructuredOutput.parse(...)`, `CppBridge.StructuredOutput.makeParseRequest(text:schema:)` | Sync; parses raw text against a JSON schema via C++ |

`generate` and `generateStream` log generation parameters (temperature, top_p, max_tokens, system_prompt presence, streaming flag) at `SDKLogger.llm.info` level before delegating to `CppBridge.LLM.shared`. The `RALLMGenerateRequest` proto is passed directly — no Swift-side modification. `extractStructuredOutput` is the only synchronous public method.

##### §5.4.1.2 RunAnywhere+ToolCalling.swift

**File:** `Public/Extensions/LLM/RunAnywhere+ToolCalling.swift` (LOC: 442)
**Mirrors C ABI:** `rac_tool_calling_run_loop_proto` (loaded dynamically via `NativeProtoABI.load`), `rac_proto_buffer_init`, `rac_proto_buffer_copy`, `rac_proto_buffer_set_error`, `rac_tool_value_to_json_proto` / `rac_tool_value_from_json_proto`

| Symbol | Signature | Line | Calls | Notes |
|---|---|---|---|---|
| `registerTool` | `static func registerTool(_ definition: RAToolDefinition, executor: @escaping ToolExecutor) async` | 104 | `ToolRegistry.shared.register` | Stores closure in actor-isolated `ToolRegistry` |
| `unregisterTool` | `static func unregisterTool(_ toolName: String) async` | 114 | `ToolRegistry.shared.unregister(_:)` | Removes by name |
| `getRegisteredTools` | `static func getRegisteredTools() async -> [RAToolDefinition]` | 122 | `ToolRegistry.shared.getAll()` | |
| `clearTools` | `static func clearTools() async` | 127 | `ToolRegistry.shared.clear()` | |
| `executeTool` | `static func executeTool(_ toolCall: RAToolCall) async -> RAToolResult` | 139 | `ToolRegistry.shared.get`, executor, `makeToolResult` | Dispatches one tool call |
| `generateWithTools` | `static func generateWithTools(prompt:options:toolOptions:) async throws -> RAToolCallingResult` | 187 | `ToolCallingRunLoopProtoABI.runLoop` (C), `NativeProtoABI.require`, `NativeProtoABI.decode` | Delegates entire loop to C++; Swift provides trampoline |

`ToolRegistry` is a private Swift `actor` (line 26) keyed by tool name. `generateWithTools` serializes a `RAToolCallingSessionCreateRequest` proto, looks up the `rac_tool_calling_run_loop_proto` C symbol at runtime via `NativeProtoABI.load`, then calls it synchronously on `DispatchQueue.global(qos: .userInitiated)` wrapped in `withCheckedThrowingContinuation`. `toolExecuteTrampoline` (line 351) is a `@convention(c)` free function (no captures); it deserializes incoming `RAToolCall` proto bytes, then uses a `DispatchSemaphore` + `Task.detached` to bridge from the synchronous C callback to the async `executeTool` Swift method. `ToolResultBox` (line 398) is an `@unchecked Sendable` wrapper for ferrying the async `RAToolResult` across the semaphore boundary.

##### §5.4.1.3 RunAnywhere+StructuredOutput.swift

**File:** `Public/Extensions/LLM/RunAnywhere+StructuredOutput.swift` (LOC: 94)
**Mirrors C ABI:** `rac_structured_output_*_proto` (via `CppBridge.StructuredOutput.generate`, `.generateStream`, `.preparePrompt`)

| Symbol | Signature | Line | Calls | Notes |
|---|---|---|---|---|
| `generateStructured` | `static func generateStructured(prompt:schema:options:) async throws -> RAStructuredOutputResult` | 22 | `CppBridge.StructuredOutput.generate(...)`, `.makeGenerateRequest`, `RAStructuredOutputOptions.defaults(schema:)` | Full pipeline in C++; `options` param ignored today |
| `generateStructuredStream` | `static func generateStructuredStream(prompt:schema:options:) -> AsyncStream<RAStructuredOutputStreamEvent>` | 44 | `CppBridge.StructuredOutput.generateStream`, `.makeGenerateRequest` | Not async/throws; returns error stream on failure |
| `generateWithStructuredOutput` | `static func generateWithStructuredOutput(prompt:structuredOutput:options:) async throws -> RALLMGenerationResult` | 66 | `CppBridge.StructuredOutput.preparePrompt`, `.toRALLMGenerateRequest`, `generate(_:)` | Two-step path: optional prompt prep then standard LLM generate |

##### §5.4.1.4 RunAnywhere+LoRA.swift

**File:** `Public/Extensions/LLM/RunAnywhere+LoRA.swift` (LOC: 211)
**Mirrors C ABI:** `CppBridge.LLM.shared.applyLoraAdapters`, `.removeLoraAdapters`, `.listLoraAdapters`, `.getLoraState`, `.checkLoraCompatibility`; `CppBridge.LoraRegistry.shared.*`

`RunAnywhere.lora` is a static accessor returning a stateless `LoRA: Sendable` struct. Public methods:

| Symbol | Signature | Line | Calls |
|---|---|---|---|
| `apply` | `(_ request: RALoRAApplyRequest) async throws -> RALoRAApplyResult` | 38 | `CppBridge.LLM.shared.getHandle()`, `.applyLoraAdapters(handle:_:)` |
| `remove` | `(_ request: RALoRARemoveRequest) async throws -> RALoRAState` | 52 | `CppBridge.LLM.shared.removeLoraAdapters(handle:_:)` |
| `list` | `() async throws -> RALoRAState` | 61 | `.listLoraAdapters(handle:_:)` |
| `state` | `() async throws -> RALoRAState` | 70 | `.getLoraState(handle:_:)` |
| `checkCompatibility` | `(_ config: RALoRAAdapterConfig) async -> RALoraCompatibilityResult` | 82 | `.checkLoraCompatibility(handle:_:)`; non-throwing |
| `register` | `(_ entry: RALoraAdapterCatalogEntry) async throws -> RALoraAdapterCatalogEntry` | 98 | `CppBridge.LoraRegistry.shared.requireHandle()`, `.register(handle:_:)` |
| `listCatalog` | `(_ request: RALoraAdapterCatalogListRequest) async throws -> RALoraAdapterCatalogListResult` | 107 | `.listCatalog(handle:_:)` |
| `queryCatalog` | `(_ query: RALoraAdapterCatalogQuery) async throws -> RALoraAdapterCatalogListResult` | 118 | `.queryCatalog(handle:_:)` |
| `getCatalogEntry` | `(_ request: RALoraAdapterCatalogGetRequest) async throws -> RALoraAdapterCatalogGetResult` | 129 | `.getCatalogEntry(handle:_:)` |
| `markDownloadCompleted` | `(_ request: RALoraAdapterDownloadCompletedRequest) async throws -> RALoraAdapterDownloadCompletedResult` | 144 | `.markDownloadCompleted(handle:_:)` |
| `markImportCompleted` | same | 160 | Sets `imported = true`; delegates to `markDownloadCompleted` |
| `adaptersForModel` | `(_ modelId: String) async throws -> [RALoraAdapterCatalogEntry]` | 175 | `queryCatalog(_:)` |
| `allRegistered` | `() async throws -> [RALoraAdapterCatalogEntry]` | 192 | `listCatalog()` |

The `LoRA` struct has two distinct backends: runtime operations go through `CppBridge.LLM.shared`; catalog operations go through `CppBridge.LoraRegistry.shared`. Every method independently calls `getHandle()` / `requireHandle()`.

##### §5.4.1.5 EmbeddingsProto+Helpers.swift

**File:** `Public/Extensions/LLM/EmbeddingsProto+Helpers.swift` (LOC: 41)
**Mirrors C ABI:** None (pure Swift math; norms from proto fields)

| Symbol | Signature | Line |
|---|---|---|
| `cosineSimilarity(with:)` | `func cosineSimilarity(with other: RAEmbeddingVector) -> Float` | 18 |
| `computeNorm` | `func computeNorm() -> Float` | 28 |
| `RAEmbeddingsResult.processingTime` | `var processingTime: TimeInterval` | 40 |

`cosineSimilarity` checks the proto's pre-computed `norm` field (`hasNorm`) before falling back to `l2()`. `l2` computes L2 norm via a simple summation loop.

##### §5.4.1.6 StructuredOutputProto+Helpers.swift

**File:** `Public/Extensions/LLM/StructuredOutputProto+Helpers.swift` (LOC: 98)
**Mirrors C ABI:** `rac_structured_output_schema_to_json_proto` (direct call at line 45)

| Symbol | Line |
|---|---|
| `RAStructuredOutputOptions.defaults(schema:includeSchemaInPrompt:strict:)` | 14 |
| `RAJSONSchema.jsonSchemaString` | 38 |
| `RAStructuredOutputValidation.init(isValid:containsJson:errorMessage:rawOutput:)` | 59 |
| `RAStructuredOutputResult.success` | 76 |
| `RANamedEntity.init(text:entityType:startOffset:endOffset:confidence:)` | 82 |
| `RANamedEntity.length` | 97 |

`jsonSchemaString` is the only place in these helper files that calls a C ABI symbol directly. It serializes `self` to proto bytes, passes them to `rac_structured_output_schema_to_json_proto`, reads the output `rac_proto_buffer_t`, and decodes the result as UTF-8.

##### §5.4.1.7 ToolCallingTypes.swift

**File:** `Public/Extensions/LLM/ToolCallingTypes.swift` (LOC: 156)
**Mirrors C ABI:** `rac_tool_value_to_json_proto`, `rac_tool_value_from_json_proto` (both via `NativeProtoABI.load`)

| Symbol | Line |
|---|---|
| `ToolExecutor` typealias — `@Sendable ([String: RAToolValue]) async throws -> [String: RAToolValue]` | 19 |
| `RAToolValue` scalar inits (String/Int/Double/Bool) | 40 |
| `RAToolValue.array(_:)`, `.object(_:)` | 45/50 |
| `RAToolValue.toJSONString(pretty:)` | 66 |
| `RAToolValue.parseObjectJSON(_:)` | 86 |
| `RAToolValue.jsonString(from:)` | 98 |
| `RAToolParameter.init(...)` | 106 |
| `RAToolDefinition.init(...)` | 118 |
| `RAToolCallingOptions.defaults()` | 130 |

`toJSONString` and `parseObjectJSON` both call `NativeProtoABI.invoke` which serializes the input proto to bytes, calls the named C symbol, and deserializes the output buffer.

#### §5.4.2 Speech (STT, TTS, VAD, VLM, VoiceAgent)

##### §5.4.2.1 RunAnywhere+STT.swift

**File:** `Public/Extensions/STT/RunAnywhere+STT.swift` (LOC: 89)

| Symbol | Signature | Line | Calls |
|---|---|---|---|
| `transcribe` | `static func transcribe(audio: Data, options: RASTTOptions) async throws -> RASTTOutput` | 18 | `RunAnywhere.currentModel`, `CppBridge.STT.shared.transcribe` |
| `transcribeStream` | `static func transcribeStream(audio: AsyncStream<Data>, options: RASTTOptions) -> AsyncStream<RASTTPartialResult>` | 51 | `RunAnywhere.currentModel`, `CppBridge.STT.shared.transcribeStream` |

`transcribeStream` wraps an `AsyncStream<Data>` input (chunked PCM) and yields `RASTTPartialResult` events. The outer stream drives a `Task` that iterates `audio` chunk-by-chunk; each chunk builds an `RASTTTranscriptionRequest`. Cancellation is checked via `Task.isCancelled` before each chunk. Both methods guard against model absence by querying `RunAnywhere.currentModel` with `RACurrentModelRequest { category = .speechRecognition }`.

##### §5.4.2.2 RASTTConfiguration+Helpers.swift

**File:** `Public/Extensions/STT/RASTTConfiguration+Helpers.swift` (LOC: 57)

| Symbol | Line |
|---|---|
| `RASTTLanguage.fromBcp47(_:)` | 27 |
| `RASTTLanguage.bcp47Code` | 50 |
| `RASTTOutput.detectedLanguageCode` | 56 |

`fromBcp47` strips the region subtag by splitting on `-` and lowercasing the base component. `defaults()` / `validate()` factories for `RASTTOptions` live in `Generated/RAConvenience.swift`.

##### §5.4.2.3 RunAnywhere+TTS.swift

**File:** `Public/Extensions/TTS/RunAnywhere+TTS.swift` (LOC: 154)

| Symbol | Signature | Line | Calls |
|---|---|---|---|
| `synthesize` | `static func synthesize(_ text: String, options: RATTSOptions) async throws -> RATTSOutput` | 24 | `CppBridge.TTS.shared.synthesize` |
| `synthesizeStream` | `static func synthesizeStream(_ text: String, options: RATTSOptions) -> AsyncStream<RATTSOutput>` | 49 | `CppBridge.TTS.shared.synthesizeStream` |
| `stopSynthesis` | `static func stopSynthesis() async` | 85 | `CppBridge.TTS.shared.stop` |
| `speak` | `static func speak(_ text: String, options: RATTSOptions) async throws -> RATTSSpeakResult` | 95 | `synthesize`, `convertPCMToWAV`, `ttsAudioPlayback.play` |
| `stopSpeaking` | `static func stopSpeaking() async` | 118 | `ttsAudioPlayback.stop`, `stopSynthesis` |

`speak` is a higher-level convenience: calls `synthesize` to obtain `RATTSOutput`, then invokes the C ABI function `rac_audio_float32_to_wav` to convert PCM to WAV, frees the C-allocated buffer via `rac_free`, and passes the WAV bytes to the `AudioPlaybackManager` singleton (§11.3).

##### §5.4.2.4 RATTSConfiguration+Helpers.swift

**File:** `Public/Extensions/TTS/RATTSConfiguration+Helpers.swift` (LOC: 37)

| Symbol | Line |
|---|---|
| `RATTSOutput.duration` | 18 |
| `RATTSSpeakResult.init(output:)` | 24 |
| `RATTSSpeakResult.duration` | 36 |

##### §5.4.2.5 RunAnywhere+VAD.swift

**File:** `Public/Extensions/VAD/RunAnywhere+VAD.swift` (LOC: 68)

| Symbol | Signature | Line | Calls |
|---|---|---|---|
| `detectVoiceActivity` | `static func detectVoiceActivity(_ audioData: Data, options: RAVADOptions?) async throws -> RAVADResult` | 22 | `CppBridge.VAD.shared.processLifecycle` |
| `streamVAD` | `static func streamVAD(audio: AsyncStream<Data>) -> AsyncStream<RAVADResult>` | 46 | `detectVoiceActivity` |
| `resetVAD` | `static func resetVAD() async throws` | 62 | `CppBridge.VAD.shared.reset` |

`streamVAD` creates a `Task` that iterates the input `AsyncStream<Data>`, calls `detectVoiceActivity` for each chunk (swallowing errors via `try?`), and yields each `RAVADResult`. `detectVoiceActivity` calls `processLifecycle(request:)` — the lifecycle path ensures the Silero model loaded via `RunAnywhere.loadModel` is used rather than an energy-based fallback.

##### §5.4.2.6 RAVADConfiguration+Helpers.swift

**File:** `Public/Extensions/VAD/RAVADConfiguration+Helpers.swift` (LOC: 44)

| Symbol | Line |
|---|---|
| `RAVADConfiguration.frameLengthSeconds` | 19 |
| `RAVADResult.duration` | 25 |
| `RASpeechActivityEvent.timestamp` | 31 |
| `RASpeechActivityEvent.duration` | 35 |
| `RASpeechActivityKind.isTransition` | 41 |

##### §5.4.2.7 RunAnywhere+VisionLanguage.swift

**File:** `Public/Extensions/VLM/RunAnywhere+VisionLanguage.swift` (LOC: 87)

| Symbol | Signature | Line | Calls |
|---|---|---|---|
| `processImage` | `static func processImage(_ image: RAVLMImage, options: RAVLMGenerationOptions) async throws -> RAVLMResult` | 25 | `isVLMModelLoaded`, `CppBridge.VLM.shared.process` |
| `processImageStream` | `static func processImageStream(_ image: RAVLMImage, options: RAVLMGenerationOptions) async throws -> AsyncStream<RASDKEvent>` | 53 | `isVLMModelLoaded`, `CppBridge.VLM.shared.processStream` |
| `cancelVLMGeneration` | `static func cancelVLMGeneration() async` | 84 | `CppBridge.VLM.shared.cancel` |

The `rac_vlm_image_t` C struct is retroactively conformed to `@unchecked Sendable` at line 18. `processImageStream` is `async throws` (unlike STT/TTS stream variants) — it awaits model-load validation and returns the `AsyncStream<RASDKEvent>` produced by `CppBridge.VLM.shared.processStream`. Each element is an `RASDKEvent` enabling per-token streaming.

##### §5.4.2.8 RAVLMImage+Helpers.swift

**File:** `Public/Extensions/VLM/RAVLMImage+Helpers.swift` (LOC: 186)

| Symbol | Line |
|---|---|
| `RAVLMConfiguration.defaults(modelId:)` | 13 |
| `RAVLMGenerationOptions.defaults(prompt:)` | 25 |
| `RAVLMImage.fromEncoded(_:format:)` | 52 |
| `RAVLMImage.fromFilePath(_:)` | 59 |
| `RAVLMImage.fromBase64(_:)` | 67 |
| `RAVLMImage.fromRawRGB(_:width:height:)` | 76 |
| `RAVLMImage.fromRawRGBA(_:width:height:)` | 87 |
| `RAVLMImage.fromUIImage(_:)` (UIKit) | 102 |
| `RAVLMImage.fromPixelBuffer(_:)` (CoreVideo) | 150 |

`_raToRGBData()` helpers on `UIImage` and `CVPixelBuffer` are gated behind `#if canImport(UIKit)` and `#if canImport(CoreVideo)`. They render via `CGContext` into an RGBA buffer then strip the alpha channel in a stride loop to produce packed RGB.

##### §5.4.2.9 RunAnywhere+VoiceAgent.swift

**File:** `Public/Extensions/VoiceAgent/RunAnywhere+VoiceAgent.swift` (LOC: 151)

| Symbol | Signature | Line | Calls |
|---|---|---|---|
| `initializeVoiceAgent` | `static func initializeVoiceAgent(_ config: RAVoiceAgentComposeConfig) async throws` | 24 | `CppBridge.VoiceAgent.shared.getHandle`, `.initialize` |
| `initializeVoiceAgentWithLoadedModels` | `static func initializeVoiceAgentWithLoadedModels() async throws` | 46 | `CppBridge.STT/LLM/TTS.shared.currentModelId/currentVoiceId`, `.initialize` |
| `getVoiceAgentComponentStates` | `static func getVoiceAgentComponentStates() async throws -> RAVoiceAgentComponentStates` | 88 | `CppBridge.VoiceAgent.shared.requireExistingHandle`, `.componentStatesProto` |
| `processVoiceTurn` | `static func processVoiceTurn(_ audioData: Data) async throws -> RAVoiceAgentResult` | 99 | `CppBridge.VoiceAgent.shared.isReady`, `.processVoiceTurnProto` |
| `streamVoiceAgent` | `static func streamVoiceAgent() -> AsyncStream<RAVoiceEvent>` | 117 | `CppBridge.VoiceAgent.shared.getHandle`, `VoiceAgentStreamAdapter` |
| `cleanupVoiceAgent` | `static func cleanupVoiceAgent() async` | 148 | `CppBridge.VoiceAgent.shared.cleanup` |

`streamVoiceAgent` creates a `Task` that obtains `rac_voice_agent_handle_t`, instantiates a `VoiceAgentStreamAdapter(handle:)` (see §8.3), and iterates its `stream()` method.

##### §5.4.2.10 VoiceAgentTypes.swift

**File:** `Public/Extensions/VoiceAgent/VoiceAgentTypes.swift` (LOC: 51)

Typealiases: `VoiceAgentResult = RAVoiceAgentResult`, `VoiceAgentComponentStates = RAVoiceAgentComponentStates`, `VoiceAgentConfig = RAVoiceAgentComposeConfig`, `VoiceSessionConfig = RAVoiceSessionConfig`, `VoiceSessionError = RAVoiceSessionError`. Extensions: `RAComponentLifecycleState.isLoaded`/`isLoading`, `RAVoiceSessionConfig.silenceDuration` (TimeInterval ↔ ms), `RAVoiceSessionConfig.autoPlayTTS`, `RAVoiceSessionError: LocalizedError`.

#### §5.4.3 Storage, Models, RAG, Solutions, Events

##### §5.4.3.1 ModelTypes.swift

**Path:** `Public/Extensions/Models/ModelTypes.swift` (LOC: 331)
**Calls:** `rac_model_format_wire_string`, `rac_inference_framework_*`, `rac_model_category_*`, `rac_archive_type_*`

Type aliases: `ModelSource = RAModelSource`, `ModelFormat = RAModelFormat`, `ModelCategory = RAModelCategory`, `InferenceFramework = RAInferenceFramework`, `ArchiveType = RAArchiveType`, `ArchiveStructure = RAArchiveStructure`.

Public symbols:

| Symbol | Line | Calls |
|---|---|---|
| `RAModelFormat.wireString` | 101 | `rac_model_format_wire_string` |
| `RAModelFormat.fromWireString(_:)` | 110 | — (case-insensitive scan) |
| `RAModelCategory.requiresContextLength` | 140 | `rac_model_category_requires_context_length` |
| `RAModelCategory.supportsThinking` | 145 | `rac_model_category_supports_thinking` |
| `RAInferenceFramework.wireString` | 173 | `rac_inference_framework_wire_string` |
| `RAInferenceFramework.displayName` | 180 | `rac_inference_framework_display_name` |
| `RAInferenceFramework.analyticsKey` | 187 | `rac_inference_framework_analytics_key` |
| `RAInferenceFramework.toCFramework()` | 198 | `rac_inference_framework_from_proto` |
| `RAInferenceFramework.fromCFramework(_:)` | 207 | `rac_inference_framework_to_proto` |
| `RAInferenceFramework.init?(caseInsensitive:)` | 218 | `rac_inference_framework_from_string` |
| `RAInferenceFramework.knownCases` | 225 | 23 concrete cases |
| `RAArchiveType.fileExtension` | 298 | `rac_archive_type_extension` |
| `RAArchiveType.from(url:)` | 307 | `rac_archive_type_from_path` |

`Codable` conformances on every enum round-trip through `wireString` / `from(wireString:)`. Pre-IDL case aliases (`systemTTS`, `picoLLM`, `piperTTS`, etc.) forward to the renamed proto cases.

##### §5.4.3.2 ModelTypes+Artifacts.swift

**Path:** `Public/Extensions/Models/ModelTypes+Artifacts.swift` (LOC: 473)
**Calls:** `rac_model_info_make_proto` (via `NativeProtoABI`), `rac_artifact_expected_files_proto`, `rac_path_is_non_empty_directory`, `rac_archive_type_from_path`

| Symbol | Line | Notes |
|---|---|---|
| `RAModelInfo.make(id:name:category:format:framework:...)` | 249 | Canonical factory; posts `RAModelInfoMakeRequest` proto to C ABI |
| `RAModelInfo.expectedArtifactFiles` | 376 | Falls through to C ABI if top-level manifest absent |
| `RAModelInfo.isDownloadedOnDisk` | 332 | Probes disk; directory → C ABI, file → `FileManager` |
| `RAModelInfo.inferredArtifact(from:format:)` | 415 | URL suffix → archive oneof; falls back to `.singleFile` |
| `RAModelInfo.setArtifact(_:)` | 396 | Updates `artifactType`, re-derives expected-files manifest |
| `RAModelInfo.setLocalPath(_:)` | 390 | Normalises path, stamps `isDownloaded`/`isAvailable` |
| `RAModelFileDescriptor.init(url:filename:isRequired:)` | 47 | |
| `Collection<RAModelFileDescriptor>.resolvedPrimaryModelPath` | 78 | Looks for `.primaryModel` role |
| `RAModelLoadResult.resolvedPrimaryModelPath` | 104 | Delegates to `resolvedArtifacts` |
| `RACurrentModelResult.lifecyclePrimaryArtifactPath` | 154 | |

Role accessors `resolvedVisionProjectorPath`, `resolvedTokenizerPath`, `resolvedConfigPath`, `resolvedVocabularyPath` are provided on both collection and result types (lines 80–157).

##### §5.4.3.3 RunAnywhere+ModelLifecycle.swift

**Path:** `Public/Extensions/Models/RunAnywhere+ModelLifecycle.swift` (LOC: 58)
**Calls:** `CppBridge.ModelLifecycle.load/unload/currentModel/componentSnapshot`

| Symbol | Signature | Line |
|---|---|---|
| `loadModel(_:)` | `static func loadModel(_ request: RAModelLoadRequest) async -> RAModelLoadResult` | 25 |
| `unloadModel(_:)` | `static func unloadModel(_ request: RAModelUnloadRequest) async -> RAModelUnloadResult` | 39 |
| `currentModel(_:)` | `static func currentModel(_ request: RACurrentModelRequest) -> RACurrentModelResult` | 49 |
| `componentLifecycleSnapshot(_:)` | `static func componentLifecycleSnapshot(_ component: RASDKComponent) -> RAComponentLifecycleSnapshot?` | 53 |

##### §5.4.3.4 RunAnywhere+ModelRegistry.swift

**Path:** `Public/Extensions/Models/RunAnywhere+ModelRegistry.swift` (LOC: 44)
**Calls:** `CppBridge.ModelRegistry.shared.list/get`

| Symbol | Signature | Line |
|---|---|---|
| `listModels(_:)` | `static func listModels(_ request: RAModelListRequest) async -> RAModelListResult` | 11 |
| `queryModels(_:)` | `static func queryModels(_ query: RAModelQuery) async -> RAModelListResult` | 22 |
| `getModel(_:)` | `static func getModel(_ request: RAModelGetRequest) async -> RAModelGetResult` | 28 |
| `downloadedModels()` | `static func downloadedModels() async -> RAModelListResult` | 39 |

##### §5.4.3.5 RunAnywhere+Storage.swift

**Path:** `Public/Extensions/Storage/RunAnywhere+Storage.swift` (LOC: 379)
**Calls:** `rac_register_model_from_url_proto`, `CppBridge.Download.shared.plan/.start/.pollProgress`, `CppBridge.ModelRegistry.shared.save/importModel`, `CppBridge.Storage.shared.info/delete`, `CppBridge.FileManager.clearCache/clearTemp`

Public symbols — model registration (3 overloads):

| Symbol | Line |
|---|---|
| `registerModel(id:name:url:framework:modality:...)` | 19 (Single-URL overload) |
| `registerModel(archive:structure:id:name:...)` | 82 (Archive overload) |
| `registerModel(multiFile:id:name:...)` | 135 (Multi-file overload) |

Public symbols — download & import:

| Symbol | Line |
|---|---|
| `downloadModel(_:onProgress:)` | 177 |
| `importModel(_:)` | 246 |

Public symbols — storage management:

| Symbol | Line |
|---|---|
| `getStorageInfo(_:)` | 254 |
| `deleteStorage(_:)` | 259 |
| `clearCache()` | 265 |
| `cleanTempFiles()` | 277 |

`downloadModel` plans → starts → polls progress at 250 ms intervals. On completion `persistDownloadCompletion` creates `RAModelImportRequest` and calls `importModel`. Private helper `registerModelFromUrl(_:)` (line 290) serialises the request proto and calls `rac_register_model_from_url_proto` directly via `rac_proto_buffer_t`.

##### §5.4.3.6 StorageProto+Helpers.swift

**Path:** `Public/Extensions/Storage/StorageProto+Helpers.swift` (LOC: 152)
**Calls:** none (pure Swift ergonomics)

| Symbol | Line |
|---|---|
| `RADeviceStorageInfo.init(totalBytes:freeBytes:usedBytes:)` | 13 |
| `RADeviceStorageInfo.usagePercentage` | 27 |
| `RAAppStorageInfo.init(documentsBytes:cacheBytes:appSupportBytes:totalBytes:)` | 36 |
| `RAStorageInfo.empty` | 53 |
| `RAStorageInfo.totalModelsSizeBytes` | 63 |
| `RAStorageInfo.appStorage` / `.deviceStorage` | 67 |
| `RAStorageInfo.totalModelsSize` | 77 |
| `RAStorageInfo.modelCount` | 81 |
| `RAStorageInfo.storedModels` | 83 |
| `RAModelStorageMetrics.init(modelID:sizeOnDiskBytes:lastUsedMs:)` | 97 |
| `RAStoredModel.id`/`.size`/`.path`/`.createdDate` | 112–121 |
| `RAStorageAvailability.make(...)` | 139 |

##### §5.4.3.7 RunAnywhere+Solutions.swift

**Path:** `Public/Extensions/Solutions/RunAnywhere+Solutions.swift` (LOC: 188)
**Calls:** `rac_solution_create_from_proto/from_yaml`, `rac_solution_start/stop/cancel/feed/close_input/destroy`

`SolutionHandle` is a `public final class` (line 29) wrapping `OSAllocatedUnfairLock<rac_solution_handle_t?>`. `deinit` calls `rac_solution_destroy` if non-nil.

| Method | Line |
|---|---|
| `start()` | 45 |
| `stop()` | 50 |
| `cancel()` | 55 |
| `feed(_ item: String)` | 60 |
| `closeInput()` | 67 |
| `destroy()` | 72 |
| `isAlive` | 86 |

`RunAnywhere.solutions` (line 115) is a computed static property returning a `Solutions` Sendable value type with three `run` overloads:

| Method | Line |
|---|---|
| `run(configBytes: Data)` | 133 (canonical) |
| `run(config: RASolutionConfig)` | 156 |
| `run(yaml: String)` | 164 |

All call private `ensureReady()` gating on `RunAnywhere.isInitialized`.

##### §5.4.3.8 RunAnywhere+RAG.swift

**Path:** `Public/Extensions/RAG/RunAnywhere+RAG.swift` (LOC: 237)
**Calls:** `CppBridge.RAG.shared.createPipeline/setProtoSession/destroy/requireProtoSession/ingest/statsProto/clearProto/query`, `loadModel(_:)`

13 public RAG entry points (line numbers in source):

| Symbol | Line |
|---|---|
| `ragResolvedConfiguration(embeddingModel:llmModel:baseConfiguration:)` | 24 |
| `ragCreatePipeline(embeddingModel:llmModel:baseConfiguration:)` | 44 |
| `ragCreatePipeline(config:)` | 59 (canonical) |
| `ragDestroyPipeline()` | 72 |
| `ragIngest(text:metadataJSON:)` | 87 |
| `ragIngest(_ document:)` | 103 |
| `ragAddDocumentsBatch(documents:)` | 121 |
| `ragGetDocumentCount()` | 140 |
| `ragGetStatistics()` | 154 |
| `ragClearDocuments()` | 165 |
| `ragDocumentCount` (computed) | 174 |
| `ragQuery(question:options:)` | 193 |
| `ragQuery(_ options:)` | 202 |

##### §5.4.3.9 RAGProto+Helpers.swift

**Path:** `Public/Extensions/RAG/RAGProto+Helpers.swift` (LOC: 80)
**Calls:** none (pure Swift ergonomics; `defaults()` comes from `Generated/RAConvenience.swift`)

| Symbol | Line |
|---|---|
| `RARAGConfiguration.resolvingLifecycleArtifacts(embedding:llm:)` | 25 |
| `RARAGDocument.init(text:metadataJSON:)` | 39 |
| `RARAGQueryOptions.defaults(question:)` | 60 |
| `RARAGResult.totalTime` | 71 |
| `RARAGStatistics.lastUpdated` | 76 |

##### §5.4.3.10 RunAnywhere+SDKEvents.swift

**Path:** `Public/Extensions/Events/RunAnywhere+SDKEvents.swift` (LOC: 46)
**Calls:** `CppBridge.Events.subscribeSDKEvents/unsubscribeSDKEvents/publishSDKEvent/pollSDKEvent/publishSDKFailure`

| Symbol | Signature | Line | Returns |
|---|---|---|---|
| `subscribeSDKEvents(_:)` | `@discardableResult static func ((RASDKEvent) -> Void) -> UInt64` | 13 | Subscription ID |
| `unsubscribeSDKEvents(_:)` | `static func (UInt64)` | 17 | — |
| `publishSDKEvent(_:)` | `@discardableResult static func (RASDKEvent) -> Bool` | 21 | success flag |
| `pollSDKEvent()` | `static func () -> RASDKEvent?` | 26 | Optional event |
| `publishSDKFailure(errorCode:message:component:operation:recoverable:)` | `@discardableResult static func ...` | 31 | success flag |

#### §5.4.4 Hardware, Logging, PluginLoader

##### §5.4.4.1 RunAnywhere+Hardware.swift

**Path:** `Public/Extensions/RunAnywhere+Hardware.swift` (LOC: 52)

The file adds two things: a convenience computed property on the proto-generated `RAHardwareProfile` type, and the `RunAnywhere.hardware` namespace.

`RAHardwareProfile.hasNeuralEngine` (lines 14–19) is a Swift computed property that bridges to the proto-generated backing field `hasNeuralEngine_p`.

`RunAnywhere.hardware` (lines 31–51) is a static computed property returning a freshly allocated `Hardware: Sendable` value. The struct's `init()` is `fileprivate`. Methods delegate to `CppBridge.Hardware`:

| Method | Delegation target |
|---|---|
| `getProfile() throws -> RAHardwareProfileResult` | `CppBridge.Hardware.getProfile()` |
| `getAccelerators() throws -> [RAAcceleratorInfo]` | `CppBridge.Hardware.getAccelerators()` |
| `setAcceleratorPreference(_:) throws` | `CppBridge.Hardware.setAcceleratorPreference(_:)` |

##### §5.4.4.2 RunAnywhere+Logging.swift

**Path:** `Public/Extensions/RunAnywhere+Logging.swift`

All six methods are `public static` on `RunAnywhere`. None call the C ABI directly; every call routes to `Logging.shared` (§9.4).

| Method | Parameters | Calls |
|---|---|---|
| `configureLogging(_:)` | `LoggingConfiguration` | `Logging.shared.configure(config)` |
| `setLocalLoggingEnabled(_:)` | `Bool` | `Logging.shared.setLocalLoggingEnabled(enabled)` |
| `setLogLevel(_:)` | `LogLevel` | `Logging.shared.setMinLogLevel(level)` |
| `addLogDestination(_:)` | `LogDestination` | `Logging.shared.addDestination(destination)` |
| `setDebugMode(_:)` | `Bool` | Composes `setLogLevel(.debug/.info)` + `setLocalLoggingEnabled` |
| `flushLogs()` | — | `Logging.shared.flush()` |

##### §5.4.4.3 RunAnywhere+PluginLoader.swift

**Path:** `Public/Extensions/RunAnywhere+PluginLoader.swift` (LOC: 142)

`PluginInfo` (lines 19–30) — `Sendable` struct with `name: String` (library stem) and `path: String`.

`RunAnywhere.pluginLoader` (lines 43–141) returns a `PluginLoaderNamespace()` Sendable value with a `fileprivate init()`:

| Member | C ABI call | Notes |
|---|---|---|
| `apiVersion: UInt32` | `rac_plugin_api_version()` | Compile-time constant exposed at runtime |
| `registeredCount: Int` | `rac_registry_plugin_count()` | Direct return |
| `registeredNames() -> [String]` | `rac_registry_list_plugins`, `rac_registry_free_plugin_list` | Allocates a C pointer array; frees in `defer` |
| `listLoaded() -> [PluginInfo]` | (delegates to `registeredNames()`) | Path is empty because registry does not store it |
| `load(path:) throws -> PluginInfo` | `rac_registry_load_plugin` | Derives `name` via `URL.deletingPathExtension().lastPathComponent`; strips `lib` prefix |
| `unload(name:) throws` | `rac_registry_unload_plugin` | Passes name as C string |

On platforms where `dlopen` is banned (iOS, WASM), the C ABI returns `featureNotAvailable`; Swift propagates via `throwIfFailed`.

---

## §6 CppBridge Architecture

The `CppBridge` namespace and its 38 extension files comprise the entire Swift↔C++ surface. Section §6.1 covers the namespace itself and shared state, §6.2–§6.4 cover the three core types (`ComponentActor`, `ComponentVTable`, `HTTPClientAdapter`), §6.5 walks through each `CppBridge+*.swift` slice, and §6.6 lists the type-helper extensions on proto types.

### §6.1 CppBridge namespace + shared state

**Path:** `Sources/RunAnywhere/Foundation/Bridge/CppBridge.swift`
**Type:** `public enum CppBridge` (namespace, never instantiated)
**LOC:** 203

#### Shared state

State is held in a private value type `CppBridgeSharedState` (struct, lines 62–66) with three fields:

- `environment: SDKEnvironment` — defaults to `.development`
- `isInitialized: Bool` — true after Phase 1 completes
- `servicesInitialized: Bool` — true after Phase 2 completes

The struct is wrapped in a single `OSAllocatedUnfairLock<CppBridgeSharedState>` at line 68–69:

```swift
private static let state =
    OSAllocatedUnfairLock<CppBridgeSharedState>(initialState: CppBridgeSharedState())
```

Two public computed properties read from it under the lock: `isInitialized` (line 73) and `servicesInitialized` (line 78), each calling `state.withLock { $0.fieldName }`.

#### Phase 1 — `initialize(environment:)` (lines 89–125)

Reads-then-conditionally-writes the lock in one atomic block (lines 90–95) to guard against double-init. If `isInitialized` is already true, the call is a no-op. Otherwise it:

1. Calls `PlatformAdapter.register()` (line 99) — registers file ops, logging, Keychain, clock.
2. Calls `URLSessionHttpTransport.register()` (line 106) — registers Apple's URLSession as the `rac_http_transport_ops_t` vtable before any C++ code that might issue HTTP.
3. Calls `rac_configure_logging(environment.cEnvironment)` (line 111) — suppresses C++ stderr in production.
4. Calls `Events.register()` (line 114).
5. Calls `Telemetry.initialize(environment:)` (line 117).
6. Calls `Device.register()` (line 120).
7. Sets `isInitialized = true` under the lock (line 122).

#### Phase 2 — `initializeServices()` (lines 133–167)

Annotated `@MainActor`. Reads both `servicesInitialized` and `environment` in one lock call (lines 135–137) and returns early if already done. Otherwise:

1. Calls `Platform.register()` — registers Foundation Models and System TTS platform service callbacks. (Model assignment needs no Swift callbacks: commons routes the fetch through the registered URLSession HTTP transport, and `rac_sdk_init_phase2_proto` owns the fetch itself.)
2. Sets `servicesInitialized = true` under the lock.

#### `shutdown()` (lines 176–202)

`async` because destroying actor-isolated AI components requires `await`. Reads `isInitialized` (line 177); returns early if Phase 1 never ran. Destroy order (lines 181–186):

```
LLM → STT → TTS → VAD → VoiceAgent → VLM
```

Then calls `Telemetry.shutdown()` (line 191) and `Events.unregister()` (line 192). Resets both state flags to false under the lock (lines 196–199). `PlatformAdapter` and `Device` callbacks are not unregistered because they are backed by static C function pointers that remain valid for the process lifetime.

#### Subnamespaces declared in extension files

The `CppBridge` enum is the single namespace; all sub-namespaces live in `Foundation/Bridge/Extensions/` (25 files listed in the header comment). None are declared in `CppBridge.swift` itself — only the lifecycle methods and the shared-state lock are here. Extension files cover: `PlatformAdapter`, `Environment`, `DevConfig`, `Endpoints`, `Telemetry`, `Events`, `Device`, `State`, `HTTP`, `Auth`, `Services`, `ModelPaths`, `ModelRegistry`, `Download`, `Platform`, `LLM`, `STT`, `TTS`, `VAD`, `VoiceAgent`, `Storage`, `Strategy`, `FileManager`, `LoraRegistry`, `VLM`.

#### Cross-cutting helpers

- **Logger**: constructed inline as `SDKLogger(category: "CppBridge")` at call sites (lines 124, 166, 201). No shared logger field — each log site creates a transient instance.
- **Concurrency**: the enum itself uses `OSAllocatedUnfairLock` for synchronous flag reads/writes (Swift 6 replacement for `NSLock`). All async work is delegated to the individual component actors or `Task.detached`.

### §6.2 ComponentActor — generic per-handle actor

**Path:** `Sources/RunAnywhere/Foundation/Bridge/ComponentActor.swift`
**Type:** `public actor ComponentActor` (declared as `extension CppBridge`)
**LOC:** 203

#### State fields (lines 37–54)

| Field | Type | Purpose |
|---|---|---|
| `vtable` | `ComponentVTable` | Immutable, set at init; provides all C function pointers |
| `handle` | `rac_handle_t?` | Nil until first successful `getHandle()`; nil again after `destroy()` |
| `loadedAssetId` | `String?` | Tracks last successfully loaded model/voice id |
| `isClosed` | `Bool` | Set true by `destroy()`; blocks further handle creation |
| `logger` | `SDKLogger` | Category keyed as `"CppBridge.\(vtable.component.label)"` |

#### `init(vtable:)` (lines 58–61)

Accepts a `ComponentVTable` and builds a `SDKLogger` whose category includes the proto component label (e.g., `"CppBridge.LLM"`).

#### `getHandle() throws -> rac_handle_t` (lines 66–90)

The lazy-creation gate. Path:

1. Returns existing `handle` if non-nil (line 67).
2. Throws `.notInitialized` if `isClosed` is true (lines 69–75).
3. Calls `vtable.create(&newHandle)` (line 79); throws `.notInitialized` if the result is not `RAC_SUCCESS` or the output pointer is nil (lines 80–86).
4. Stores the new handle and logs (lines 87–88).

#### State queries

- `isLoaded: Bool` (lines 95–98) — returns false if `handle` is nil, otherwise calls `vtable.isLoaded(handle) == RAC_TRUE`.
- `currentAssetId: String?` (line 102) — read-only proxy for `loadedAssetId`.
- `isShutDown: Bool` (line 106) — returns `isClosed`.
- `existingHandle() -> rac_handle_t?` (line 110) — returns the raw handle without triggering creation.

#### `loadModel(path:id:name:) throws` (lines 117–146)

Throws `.notImplemented` if `vtable.loadModel` is nil (lines 122–127). Otherwise:

1. Calls `getHandle()` (line 129).
2. Bridges three Swift strings to C via nested `withCString` closures (lines 130–135).
3. Throws `.modelLoadFailed` if the result is not `RAC_SUCCESS` (lines 137–143).
4. Sets `loadedAssetId = id` and logs (lines 144–145).

#### `markAssetLoaded(_ id: String?)` (lines 153–155)

Writes `loadedAssetId` without touching the C side. Called by VAD's modality-specific load path to clear the asset id on unload.

#### `unload()` (lines 159–164)

Calls `vtable.cleanup(handle)` and clears `loadedAssetId`. Safe to call when `handle` is nil (guard at line 160).

#### `destroy()` (lines 168–176)

Calls `vtable.destroy(handle)` if non-nil, then sets `handle = nil`, `loadedAssetId = nil`, `isClosed = true`. Subsequent `getHandle()` throws `.notInitialized`.

#### Component label helper (lines 182–203)

Private extension on `RASDKComponent` defines `var label: String` mapping proto enum cases to short strings used in logs and error messages: `llm` → `"LLM"`, `stt` → `"STT"`, `tts` → `"TTS"`, `vad` → `"VAD"`, `vlm` → `"VLM"`, `voiceAgent` → `"VoiceAgent"`, `diffusion` → `"Diffusion"`, `rag` → `"RAG"`, `embeddings` → `"Embeddings"`, `wakeword` → `"Wakeword"`, `speakerDiarization` → `"SpeakerDiarization"`.

#### Thread safety

Actor isolation guarantees that all fields are accessed from one logical thread. No locks are needed inside the actor. The `vtable` field is `let` and its type `ComponentVTable` is `Sendable` (see §6.3), so passing vtables across concurrency boundaries is safe.

#### Consumers

`CppBridge.LLM`, `CppBridge.STT`, `CppBridge.TTS`, `CppBridge.VAD`, and `CppBridge.VLM` each wrap a `ComponentActor` instance. `VoiceAgent` does NOT use this scaffold — its handle type is `rac_voice_agent_handle_t` and creation is async-composite (see §6.5.30).

### §6.3 ComponentVTable — 5 typed modality vtables

**Path:** `Sources/RunAnywhere/Foundation/Bridge/ComponentVTable.swift`
**Type:** `public struct ComponentVTable: Sendable` (declared as `extension CppBridge`)
**LOC:** 137

```swift
public struct ComponentVTable: Sendable {
    public let component: RASDKComponent
    public let create: @Sendable (_ out: UnsafeMutablePointer<rac_handle_t?>) -> rac_result_t
    public let isLoaded: @Sendable (_ handle: rac_handle_t) -> rac_bool_t
    public let cleanup: @Sendable (_ handle: rac_handle_t) -> Void
    public let destroy: @Sendable (_ handle: rac_handle_t) -> Void
    public let loadModel: (@Sendable (...) -> rac_result_t)?
}
```

All closure fields are `@Sendable` to satisfy Swift 6 actor-crossing rules. The struct itself is `Sendable`.

Static vtable instances:

| Instance | Component | C function bindings |
|---|---|---|
| `ComponentVTable.llm` (lines 68–77) | `.llm` | `rac_llm_component_*` |
| `ComponentVTable.stt` (lines 80–89) | `.stt` | `rac_stt_component_*` |
| `ComponentVTable.tts` (lines 93–102) | `.tts` | `rac_tts_component_*`; `loadModel` slot maps to `rac_tts_component_load_voice` |
| `ComponentVTable.vad` (lines 105–114) | `.vad` | `rac_vad_component_*` |
| `ComponentVTable.vlm` (lines 124–136) | `.vlm` | `rac_vlm_component_*`; `loadModel` passes `nil` for `vision_projector_path` |

The inline comment at lines 117–123 documents that the `loadModel` slot is "dead in practice" for VLM — it is retained only to keep the `ComponentVTable` shape uniform across all five modalities.

### §6.4 HTTPClientAdapter — HTTP routing actor

**Path:** `Sources/RunAnywhere/Foundation/Bridge/HTTPClientAdapter.swift`
**Type:** `public actor HTTPClientAdapter`
**Alias:** Referenced as `HTTPService = HTTPClientAdapter`
**LOC:** 336

#### State and configuration (lines 19–37)

- `shared: HTTPClientAdapter` — static singleton (line 21).
- `baseURL: URL?` — nil until `configure(baseURL:apiKey:)` succeeds.
- `apiKey: String?` — nil until configured.
- `logger: SDKLogger` — category `"HTTPClientAdapter"` (line 25).
- `executionQueue: DispatchQueue` — static concurrent queue (`qos: .userInitiated`) at lines 29–33; runs blocking C ABI calls off the Swift concurrency pool.
- `defaultTimeoutMs: Int32` — static constant `30_000` (line 35).

#### `configure(baseURL:apiKey:)` (lines 41–63)

Two overloads: `URL` and `String`. The `URL` overload trims whitespace from `apiKey`, guards both values through `CppBridge.DevConfig.isUsableHTTPURL` and `CppBridge.DevConfig.isUsableCredential`, then stores `self.baseURL` and `self.apiKey`. `isConfigured: Bool` — returns `baseURL != nil`. `hasUsableConfiguration: Bool` re-checks both values through `DevConfig` guards.

#### Public API

- `postRaw(_ path: String, _ payload: Data, requiresAuth: Bool) async throws -> Data` (line 72)
- `getRaw(_ path: String, requiresAuth: Bool) async throws -> Data` (line 76)
- `post(_ path: String, json: String, requiresAuth: Bool) async throws -> Data` (lines 81–86)
- `static fetchURL(_ url: URL, timeoutMs: Int32) async throws -> Data` (lines 93–103) — one-shot absolute URL fetch with no base URL or auth

#### Internal pipeline — `execute(method:path:body:requiresAuth:)` (lines 107–130)

Guards `baseURL`; throws `.serviceNotAvailable` if nil. Builds the full URL via `Self.buildURL(base:path:)`. Resolves auth token. Checks `RAC_ENDPOINT_DEV_DEVICE_REGISTER` for Supabase UPSERT semantics. Delegates to `Self.dispatch(...)`.

#### Token resolution — `resolveToken(requiresAuth:)` (lines 132–146)

Calls `rac_auth_get_valid_token(&tokenPtr, &needsRefresh)`. If `status == 1` or `needsRefresh`, calls `CppBridge.Auth.refreshToken()` then retries. Falls back to `apiKey` or throws `.authenticationFailed`.

#### `dispatch(...)` / `syncDispatch(...)` (lines 170–264)

Wraps `withCheckedThrowingContinuation` to bridge async Swift to the blocking `syncDispatch`. The continuation resumes on `executionQueue.async`. `syncDispatch`:

1. Creates an `rac_http_client_t` handle; `defer`s `rac_http_client_destroy`.
2. Fetches canonical SDK headers via `rac_http_default_headers`.
3. Adds `"X-Platform"`, `"apikey"`, `"Prefer: return=representation"` if apiKey is set, `"Authorization: Bearer <token>"` if authToken is set.
4. `strdup`s method/URL strings; `defer`s `free`.
5. Calls into `send(...)`.
6. Maps transport-layer failures: `RAC_ERROR_TIMEOUT` → `.timeout`, otherwise → `.networkError`.

#### Error mapping — `mapAPIError(statusCode:body:url:)` (lines 312–335)

Calls `rac_api_error_from_response(statusCode, bodyC, urlC, &apiError)`. Maps status codes: 401 → `(.authenticationFailed, .auth)`, 403 → `(.forbidden, .auth)`, 500–599 → `(.serverError, .network)`, all others → `(.httpError, .network)`.

### §6.5 Bridge Extension Slices

**Path prefix:** `sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/`

#### §6.5.1 CppBridge+Auth.swift

**LOC:** 274 — `CppBridge.Auth` — `public enum` (stateless namespace)

| Method | Line | C ABI |
|---|---|---|
| `authenticate(apiKey:)` async throws | 28 | `rac_auth_request_to_json`, `rac_auth_handle_authenticate_response` |
| `refreshToken()` async throws | 72 | `rac_auth_build_refresh_request`, `rac_auth_handle_refresh_response` |
| `clearAuth()` throws | 111 | `rac_auth_clear` |
| `isAuthenticated` | 118 | `rac_auth_is_authenticated` |
| `buildAuthenticateRequestJSON(...)` | 162 | `rac_auth_request_to_json` |
| `buildRefreshRequestJSON(...)` | 197 | `rac_refresh_request_to_json` |
| `parseAPIError(...)` | 225 | `rac_api_error_from_response`, `rac_api_error_free` |

`authenticate` follows a three-step pipeline: (1) call `buildAuthenticateRequestJSON`; (2) POST the JSON to `RAC_ENDPOINT_AUTHENTICATE` via `CppBridge.HTTP.shared.post`; (3) hand response bytes to the private `handleAuthResponse` helper, which null-terminates the byte buffer and invokes `rac_auth_handle_authenticate_response`. All in-memory token state lives inside C++.

#### §6.5.2 CppBridge+Device.swift

**LOC:** 265 — `CppBridge.Device` — `public enum` with `cachedPersistentId: OSAllocatedUnfairLock<String?>`

| Method | Line | C ABI |
|---|---|---|
| `persistentId` | 44 | `rac_device_get_or_create_persistent_id` |
| `register()` | 83 | `rac_device_manager_set_callbacks` |
| `registerIfNeeded(environment:)` async throws | 209 | `rac_device_manager_register_if_needed` |
| `isRegistered` | 246 | `rac_device_manager_is_registered` |
| `clearRegistration()` | 251 | `rac_device_manager_clear_registration` |
| `deviceId` | 256 | `rac_device_manager_get_device_id` |

`register()` populates a `rac_device_callbacks_t` struct with five `@convention(c)` closures: `get_device_info`, `get_device_id`, `is_registered`/`set_registered` (read/write `UserDefaults` under `com.runanywhere.sdk.deviceRegistered`), and `http_post` (bridges Swift async HTTP to a synchronous C callback via `DispatchSemaphore`).

#### §6.5.3 CppBridge+Download.swift

**LOC:** 192 — `CppBridge.Download` — `public actor` (singleton)

| Method | Line | C ABI |
|---|---|---|
| `plan(_:)` | 79 | `rac_download_plan_proto` |
| `start(_:)` | 96 | `rac_download_start_proto` |
| `cancel(_:)` | 112 | `rac_download_cancel_proto` |
| `resume(_:)` | 131 | `rac_download_resume_proto` |
| `pollProgress(_:)` | 149 | `rac_download_progress_poll_proto` |
| `progressEvents()` (nonisolated) | 167 | `rac_download_set_progress_proto_callback` |

All five synchronous operations follow an identical pattern: serialize via `NativeProtoABI.invoke`, lazily-resolved `dlsym` function pointer from `DownloadProtoABI`. `progressEvents()` returns an `AsyncStream<RADownloadProgress>`: retains a `DownloadProtoProgressBox`, passes its opaque pointer as `userData` to `rac_download_set_progress_proto_callback`, and installs a C-compatible free function `downloadProtoProgressCallback`.

#### §6.5.4 CppBridge+Environment.swift

**LOC:** 210 — Three separate `public enum` namespaces: `CppBridge.Environment`, `CppBridge.DevConfig`, `CppBridge.Endpoints`

| Method | Line | C ABI |
|---|---|---|
| `Environment.toC` / `fromC` | 20 / 29 | (switch literal) |
| `Environment.requiresAuth` | 40 | `rac_env_requires_auth` |
| `Environment.requiresBackendURL` | 45 | `rac_env_requires_backend_url` |
| `Environment.validateAPIKey` / `validateBaseURL` | 50 / 55 | `rac_validate_api_key` / `rac_validate_base_url` |
| `DevConfig.configureHTTP` async | 132 | (delegates to `CppBridge.HTTP`) |
| `Endpoints.deviceRegistration` | 196 | `rac_endpoint_device_registration` |
| `Endpoints.telemetry` | 201 | `rac_endpoint_telemetry` |
| `Endpoints.modelAssignments` | 206 | `rac_endpoint_model_assignments` |

`DevConfig.looksLikePlaceholder` scans for regex patterns (`YOUR_|<your|REPLACE_ME|PLACEHOLDER`). `DevConfig.hasUsableDevelopmentRegistrationConfig` is a compound predicate (supabase config AND build token both valid).

#### §6.5.5 CppBridge+FileManager.swift

**LOC:** 263 — `CppBridge.FileManager` — `public enum` (stateless namespace)

| Method | Line | C ABI |
|---|---|---|
| `createDirectoryStructure` | 41 | `rac_file_manager_create_directory_structure` |
| `calculateDirectorySize(at:)` | 48 | `rac_file_manager_calculate_dir_size` |
| `modelsStorageUsed` | 57 | `rac_file_manager_models_storage_used` |
| `clearCache` / `clearTemp` | 65 / 70 | `rac_file_manager_clear_cache` / `_clear_temp` |
| `cacheSize` | 75 | `rac_file_manager_cache_size` |
| `deleteModel` | 86 | `rac_file_manager_delete_model` |
| `modelFolderExists` / `modelFolderHasContents` | 93 / 103 | `rac_file_manager_model_folder_exists` |
| `getStorageInfo` | 115 | `rac_file_manager_get_storage_info` |
| `checkStorage` | 122 | `rac_file_manager_check_storage` |

Every public method calls `makeCallbacks()` to build a fresh `rac_file_callbacks_t` whose eight slots point to module-private free functions: `fmCreateDirectoryCallback`, `fmDeletePathCallback`, `fmListDirectoryCallback`, `fmFreeEntriesCallback`, `fmPathExistsCallback`, `fmGetFileSizeCallback`, `fmGetAvailableSpaceCallback`, `fmGetTotalSpaceCallback`. These callbacks delegate to `Foundation.FileManager.default`.

#### §6.5.6 CppBridge+Hardware.swift

**LOC:** 74 — `CppBridge.Hardware` — `public enum` (stateless)

| Method | Line | C ABI |
|---|---|---|
| `getProfile()` throws | 34 | `rac_hardware_profile_get`, `rac_hardware_profile_free` |
| `getAccelerators()` throws | 44 | `rac_hardware_get_accelerators`, `rac_hardware_profile_free` |
| `setAcceleratorPreference(_:)` throws | 55 | `rac_hardware_set_accelerator_preference` |

`getProfile` and `getAccelerators` both use `NativeProtoABI.getBytes` — the request-less GET helper.

#### §6.5.7 CppBridge+HTTP.swift

**LOC:** 49 — `CppBridge.HTTP` — `public enum` (façade over `HTTPClientAdapter.shared`)

| Method | Line |
|---|---|
| `shared` | 22 |
| `configure(baseURL: URL, apiKey:)` async | 26 |
| `configure(baseURL: String, apiKey:)` async | 31 |
| `isConfigured` { get async } | 37 |
| `hasUsableConfiguration` { get async } | 43 |

Every member directly delegates to `HTTPClientAdapter.shared`. No C ABI symbols are called.

#### §6.5.8 CppBridge+LLM.swift

**LOC:** 74 — `CppBridge.LLM` — `public actor` (singleton); wraps `ComponentActor(vtable: .llm)`

| Method | Line | C ABI |
|---|---|---|
| `getHandle()` async throws | 33 | via `ComponentActor` |
| `isLoaded` { get async } | 40 | via `ComponentActor` |
| `currentModelId` { get async } | 45 | via `ComponentActor` |
| `loadModel(_:modelId:modelName:)` async throws | 52 | via `ComponentActor` |
| `unload()` async | 57 | via `ComponentActor` |
| `cancel()` async | 62 | `rac_llm_component_cancel` |
| `destroy()` async | 70 | via `ComponentActor` |

#### §6.5.9 CppBridge+LoraRegistry.swift

**LOC:** 50 — `CppBridge.LoraRegistry` — `public actor`, holds `rac_lora_registry_handle_t?`

| Method | Line | C ABI |
|---|---|---|
| `requireHandle()` throws | 40 | `rac_get_lora_registry` |

#### §6.5.10 CppBridge+ModelAssignment.swift (removed)

Deleted: model assignment no longer needs Swift-side callbacks. Commons (`model_assignment.cpp`) routes the fetch through the registered `rac_http_transport_ops_t` (URLSession) with control-plane auth headers when no per-SDK `rac_assignment_callbacks_t.http_get` is registered.

#### §6.5.11 CppBridge+ModelLifecycle.swift

**LOC:** 133 — `CppBridge.ModelLifecycle` — `public enum`; `ModelLifecycleProtoABI` resolves five `dlsym` symbols

| Method | Line | C ABI |
|---|---|---|
| `load(_:)` async | 45 | `rac_model_lifecycle_load_proto` |
| `unload(_:)` | 85 | `rac_model_lifecycle_unload_proto` |
| `currentModel(_:)` | 101 | `rac_model_lifecycle_current_model_proto` |
| `componentSnapshot(component:)` | 112 | `rac_component_lifecycle_snapshot_proto` |
| `reset()` | 129 | `rac_model_lifecycle_reset` |

`load` awaits `CppBridge.ModelRegistry.shared.getHandle()` to obtain the `rac_model_registry_handle_t` before invoking the proto symbol.

#### §6.5.12 CppBridge+ModelPaths.swift

**LOC:** 185 — `CppBridge.ModelPaths` — `public enum`; all path methods use a 1024-byte stack `[CChar]` buffer

| Method | Line | C ABI |
|---|---|---|
| `setBaseDirectory(_:)` throws | 26 | `rac_model_paths_set_base_dir` |
| `baseDirectory` | 43 | `rac_model_paths_get_base_dir` |
| `getModelsDirectory()` throws | 52 | `rac_model_paths_get_models_directory` |
| `getFrameworkDirectory(framework:)` throws | 65 | `rac_model_paths_get_framework_directory` |
| `getModelFolder(modelId:framework:)` throws | 78 | `rac_model_paths_get_model_folder` |
| `getExpectedModelPath(modelId:framework:format:)` throws | 92 | `rac_model_paths_get_expected_model_path` |
| `getCacheDirectory()` throws | 116 | `rac_model_paths_get_cache_directory` |
| `getDownloadsDirectory()` throws | 127 | `rac_model_paths_get_downloads_directory` |
| `getTempDirectory()` throws | 138 | `rac_model_paths_get_temp_directory` |
| `extractModelId(from:)` | 153 | `rac_model_paths_extract_model_id` |
| `extractFramework(from:)` | 165 | `rac_model_paths_extract_framework` |
| `isModelPath(_:)` | 176 | `rac_model_paths_is_model_path` |

#### §6.5.13 CppBridge+ModelRegistry.swift

**LOC:** 515 — `CppBridge.ModelRegistry` — `public actor` (singleton); wraps C++ global registry handle

| Method | Line | C ABI |
|---|---|---|
| `save(_:)` throws | 139 | `rac_model_registry_register_proto` |
| `update(_:)` throws | 169 | `rac_model_registry_update_proto` |
| `get(modelId:)` | 198 | `rac_model_registry_get_proto`, `_proto_free` |
| `getAll()` | 224 | `rac_model_registry_list_proto` |
| `getDownloaded()` | 249 | `rac_model_registry_list_downloaded_proto` |
| `query(_:)` | 275 | `rac_model_registry_query_proto` |
| `list(_:)` | 312 | (delegates) |
| `get(_:)` | 320 | (delegates) |
| `getByFrameworks(_:)` | 338 | (filters in Swift) |
| `updateDownloadStatus(modelId:localPath:)` throws | 347 | (composed) |
| `updateLastUsed(modelId:)` throws | 358 | (composed) |
| `remove(modelId:)` throws | 372 | `rac_model_registry_remove_proto` |
| `discoverDownloadedModels(_:)` | 402 | `rac_model_registry_discover_proto` |
| `refresh(_:)` | 429 | `rac_model_registry_refresh_proto` |
| `importModel(_:)` throws | 450 | `rac_model_registry_import_proto` |

#### §6.5.14 CppBridge+NativeProtoABI.swift

**LOC:** 178 — `NativeProtoABI` — `internal enum` (not nested under `CppBridge`); central shared ABI utility

| Method | Line |
|---|---|
| `load<T>(_:as:)` | 33 |
| `freeBuffer` (static let) | 40 |
| `canReceiveProtoBuffer` | 42 |
| `missingSymbolMessage(_:)` | 46 |
| `require<T>(_:named:)` throws | 50 |
| `withSerializedBytes<Req,Res>(_:_:)` throws | 57 |
| `decode<Resp>(_:from:)` throws | 70 |
| `free(_:)` | 84 |
| `invoke<Req,Res>(_:symbol:symbolName:responseType:)` throws | 88 |
| `getBytes<Res>(symbol:...)` throws | 113 |
| `invoke<Ctx,Req,Res>(_:on:symbol:...)` throws | 157 (context-threaded) |

`load` resolves symbols at call time using `dlsym(bitPattern: -2)` (Darwin `RTLD_DEFAULT`). The unary `invoke` orchestrates the standard round-trip: serialize → call → decode → `defer free`.

#### §6.5.15 CppBridge+RAG.swift

**LOC:** 56 — `CppBridge.RAG` — `public actor`; holds `rac_handle_t?` proto session handle

| Method | Line | C ABI |
|---|---|---|
| `isCreated` | 30 | — |
| `destroy()` | 33 | `destroyRAGProtoSessionIfAvailable` |
| `setProtoSession(_:)` | 41 | (destroys prior on replace) |
| `requireProtoSession()` throws | 49 | — |

#### §6.5.16 CppBridge+Storage.swift

**LOC:** 226 — `CppBridge.Storage` — `public actor`; owns `rac_storage_analyzer_handle_t`

| Method | Line | C ABI |
|---|---|---|
| `info(_:)` async | 77 | `rac_storage_analyzer_info_proto` |
| `delete(_:)` async | 92 | `rac_storage_analyzer_delete_proto` |

`init()` fills `rac_storage_callbacks_t` with five C function pointer slots and calls `rac_storage_analyzer_create`. `deinit` calls `rac_storage_analyzer_destroy`. Both ops await `CppBridge.ModelRegistry.shared.getHandle()`.

#### §6.5.17 CppBridge+ModalityProtoABI.swift

**LOC:** 424 — Hand-written companion to the code-generated `Generated/ModalityProtoABI+Generated.swift`. Retains only genuinely irregular C ABI methods that codegen cannot template.

C symbol type declarations (private enums with `@convention(c)` typealiases and lazy-loaded symbol pointers via `NativeProtoABI.load(_:as:)`):

| Enum | Symbol |
|---|---|
| `VADComponentProtoABI` | `rac_vad_component_process_proto`, `rac_vad_component_set_activity_proto_callback` |
| `VoiceAgentStateProtoABI` | `rac_voice_agent_process_voice_turn_proto` |
| `VLMCustomProtoABI` | `rac_vlm_process_proto`, `rac_vlm_process_stream_proto` |
| `RAGSessionProtoABI` | `rac_rag_session_destroy_proto` |

Shared streaming scaffolding:

- **`ProtoStreamYielder` protocol (line 116):** Non-generic protocol exposing `yield(bytes:size:)`.
- **`protoStreamTrampoline` (line 123):** Module-level `@convention(c)` constant. Recovers the `ProtoStreamYielder` via `Unmanaged<AnyObject>.fromOpaque(userData).takeUnretainedValue()`.
- **`ProtoStreamContext<Event: Message>` (line 133):** Generic `final class @unchecked Sendable` holding an `AsyncStream<Event>.Continuation`. Static factory `runRequestStream(...)` (line 170) serializes request, retains context via `Unmanaged.passRetained`, launches `Task.detached`, invokes the C streaming function with the trampoline.
- **`ProtoProgressContext<Event: Message>` (line 209):** For long-lived callback registrations (VAD activity events indefinitely).
- **`decodeBuffer` free function (line 232):** Shared helper.

| Method | Line | C ABI |
|---|---|---|
| `CppBridge.VAD.process` | 258 | `rac_vad_component_process_proto` |
| `CppBridge.VAD.setActivityCallbackProto` | 283 | `rac_vad_component_set_activity_proto_callback` |
| `CppBridge.VoiceAgent.processVoiceTurnProto` | 315 | `rac_voice_agent_process_voice_turn_proto` |
| `CppBridge.VLM.process` | 335 | `rac_vlm_process_proto` |
| `CppBridge.VLM.processStream` | 361 | `rac_vlm_process_stream_proto` |
| `destroyRAGProtoSessionIfAvailable` | 251 | `rac_rag_session_destroy_proto` |

`CppBridge.EmbeddingsProto` is declared as an empty enum at line 419; its methods are generated into `ModalityProtoABI+Generated.swift`.

#### §6.5.18 CppBridge+Platform.swift

**LOC:** 367 — `CppBridge.Platform` (pure namespace enum). Callback-registration bridge for Apple platform services (Foundation Models LLM, System TTS).

| Method | Line | C ABI |
|---|---|---|
| `Platform.register()` `@MainActor` | 41 | `rac_backend_platform_register`, `rac_platform_llm_set_callbacks`, `rac_platform_tts_set_callbacks`, `rac_plugin_entry_platform`, `rac_plugin_register` |
| `Platform.unregister()` | 106 | `rac_backend_platform_unregister` |
| `Platform.getFoundationModelsService()` `@available(iOS 26, macOS 26, *)` | 356 | — |
| `Platform.getSystemTTSService()` | 361 | — |

`register()` runs four steps in sequence:

1. **`registerLLMCallbacks()` (line 119):** Fills a `rac_platform_llm_callbacks_t` struct with four slots — `can_handle` (checks `SystemFoundationModels.isAvailable`), `create` (constructs `SystemFoundationModelsService()`, blocks on `DispatchGroup.wait()`, returns sentinel `0xF00DADE1`), `generate`, `destroy`.
2. **`registerTTSCallbacks()` (line 240):** Fills a `rac_platform_tts_callbacks_t` struct with five slots. `create` calls `DispatchQueue.main.sync` to construct `SystemTTSService()` on the main thread (required by `AVSpeechSynthesizer`). Returns sentinel `0x5157E775`.
3. **`rac_backend_platform_register()` (line 59):** Registers the module record. Tolerates `RAC_ERROR_MODULE_ALREADY_REGISTERED`.
4. **`registerPlatformPlugin()` (line 84):** Calls `rac_plugin_entry_platform()` to obtain the vtable pointer, rebinds it as `rac_engine_vtable_t`, and calls `rac_plugin_register`.

#### §6.5.19 CppBridge+PlatformAdapter.swift

**LOC:** 733 — `CppBridge.PlatformAdapter` (pure namespace enum). Full `rac_platform_adapter_t` vtable construction.

`CppBridge.PlatformAdapter.register()` (line 43) is called first in the SDK init sequence. Populates static `var adapter` (line 37, `rac_platform_adapter_t()`) and calls `rac_set_platform_adapter(&adapter)`.

| Slot | Swift function | Line | Implementation |
|---|---|---|---|
| `adapter.log` | `platformLogCallback` | 101 | Converts `rac_log_level_t` → `SDKLogger`; parses `"message \| key=value"` metadata |
| `adapter.file_exists` | `platformFileExistsCallback` | 176 | `FileManager.default.fileExists(atPath:)` |
| `adapter.file_read` | `platformFileReadCallback` | 187 | `Data(contentsOf:)`, allocates `UnsafeMutablePointer<UInt8>` |
| `adapter.file_write` | `platformFileWriteCallback` | 215 | `Data(bytes:count:).write(to:)` |
| `adapter.file_delete` | `platformFileDeleteCallback` | 236 | `FileManager.default.removeItem(atPath:)` |
| `adapter.secure_get` | `platformSecureGetCallback` | 254 | Keychain `SecItemCopyMatching` |
| `adapter.secure_set` | `platformSecureSetCallback` | 290 | Delete-then-add: `SecItemDelete` + `SecItemAdd` |
| `adapter.secure_delete` | `platformSecureDeleteCallback` | 327 | `SecItemDelete`; `errSecItemNotFound` treated as success |
| `adapter.now_ms` | `platformNowMsCallback` | 350 | `Int64(Date().timeIntervalSince1970 * 1000)` |
| `adapter.get_memory_info` | `platformGetMemoryInfoCallback` | 403 | `task_info(mach_task_self_, TASK_VM_INFO, ...)` |
| `adapter.track_error` | `platformTrackErrorCallback` | 439 | JSON-parses C++ structured error and routes to `Logging.shared` |
| `adapter.http_download` | `platformHttpDownloadCallback` | 629 | Dispatches async on `platformHttpDownloadQueue`; calls `rac_http_download_execute` |
| `adapter.http_download_cancel` | `platformHttpDownloadCancelCallback` | 719 | Sets `cancelFlag.cancel()` |
| `adapter.extract_archive` | `nil` | 76 | Explicitly nil |
| `adapter.get_vendor_id` | `platformGetVendorIdCallback` | 363 | `UIDevice.current.identifierForVendor?.uuidString` (iOS only) |

All Keychain callbacks use service identifier `"com.runanywhere.sdk"` and `kSecClassGenericPassword`. `PlatformDownloadCancelFlag` (line 548) wraps `OSAllocatedUnfairLock<Bool>`. The progress trampoline `platformDownloadProgressTrampoline` (line 600) checks `cancelFlag.isCancelled` and returns `RAC_FALSE` to abort.

#### §6.5.20 CppBridge+SDKEvents.swift

**LOC:** 150 — `CppBridge.Events` (pure namespace enum, also defined in `CppBridge+Telemetry.swift`). Proto-byte subscription bus.

`SDKEventProtoABI` (private enum, line 12) loads six symbols via `NativeProtoABI.load`: `rac_sdk_event_subscribe`, `_unsubscribe`, `_publish_proto`, `_poll`, `_publish_failure`, `_clear_queue`.

| Method | Line | C ABI |
|---|---|---|
| `subscribeSDKEvents(_:)` | 66 | `rac_sdk_event_subscribe` |
| `unsubscribeSDKEvents(_:)` | 82 | `rac_sdk_event_unsubscribe` |
| `publishSDKEvent(_:)` | 95 | `rac_sdk_event_publish_proto` |
| `pollSDKEvent()` | 106 | `rac_sdk_event_poll` |
| `publishSDKFailure(...)` | 120 | `rac_sdk_event_publish_failure` |
| `clearSDKEventQueue()` | 147 | `rac_sdk_event_clear_queue` |

`SDKEventSubscriptionBox` (line 42) is a `final class` retained via `Unmanaged.passRetained` and stored as `UInt(bitPattern:)` in `sdkEventSubscriptionPointers` (line 50, `OSAllocatedUnfairLock<[UInt64: UInt]>`).

#### §6.5.21 CppBridge+SdkInit.swift

**LOC:** 135 — `CppBridge.SdkInit` (pure namespace enum). Data-envelope bridge for the two-phase C++ init ABI.

| Method | Line | C ABI |
|---|---|---|
| `phase1(environment:apiKey:baseURL:deviceId:)` throws | 45 | `rac_sdk_init_phase1_proto` |
| `phase2()` throws | 75 | `rac_sdk_init_phase2_proto` |
| `retryHTTP()` throws | 93 | `rac_sdk_retry_http_proto` |

`phase1` builds `RASdkInitPhase1Request` (environment via `mapEnvironment`, apiKey, baseURL, deviceID). Calls `NativeProtoABI.invoke`, then `assertSuccess`. `phase2` builds an empty `RASdkInitPhase2Request()` and delegates entirely to commons. Non-fatal sub-step failures return `success=true` with warning flags.

#### §6.5.22 CppBridge+State.swift

**LOC:** 273 — `CppBridge.State` (pure namespace enum). State-mirror bridge.

| Property/Method | Line | C ABI |
|---|---|---|
| `initialize(environment:apiKey:baseURL:deviceId:)` | 36 | `rac_state_initialize`, `rac_sdk_init` |
| `isInitialized` | 88 | `rac_state_is_initialized` |
| `reset()` | 92 | `rac_state_reset`, `rac_auth_reset` |
| `shutdown()` | 98 | `rac_state_shutdown`, `rac_auth_reset` |
| `environment` | 108 | `rac_state_get_environment` |
| `baseURL` / `apiKey` / `deviceId` | 112 / 118 / 124 | `rac_state_get_*` |
| `accessToken` / `isAuthenticated` / `tokenNeedsRefresh` | 136 / 142 / 147 | `rac_auth_*` |
| `userId` / `organizationId` | 152 / 157 | `rac_auth_get_*` |
| `clearAuth()` | 164 | `rac_auth_clear` |
| `setDeviceRegistered(_:)` / `isDeviceRegistered` | 173 / 178 | `rac_state_*_device_registered` |

`installAuthSecureStorage()` (line 189) wires Keychain into the C auth manager via `rac_secure_storage_t` with three file-scope C function pointers (store/retrieve/delete), then calls `rac_auth_load_stored_tokens()`.

#### §6.5.23 CppBridge+Strategy.swift

**LOC:** 67 — Extensions on `ArchiveType` and `ArchiveStructure`. Delegates bidirectional conversion to commons mappers.

| Method | Line | C ABI |
|---|---|---|
| `ArchiveType.toC()` | 19 | `rac_archive_type_from_proto` |
| `ArchiveType.init?(from:)` | 30 | `rac_archive_type_to_proto` |
| `ArchiveStructure.toC()` | 47 | `rac_archive_structure_from_proto` |
| `ArchiveStructure.init(from:)` | 58 | `rac_archive_structure_to_proto` |

#### §6.5.24 CppBridge+StructuredOutput.swift

**LOC:** 84 — `CppBridge.StructuredOutput` (pure namespace enum). Thin proto-byte bridge.

`StructuredOutputGeneratedProtoABI` loads three symbols via `NativeProtoABI.load`: `rac_structured_output_parse_proto`, `_generate_proto`, `_prepare_prompt_proto`.

| Method | Line | C ABI |
|---|---|---|
| `parse(_:)` throws | 26 | `rac_structured_output_parse_proto` |
| `generate(_:)` throws | 38 | `rac_structured_output_generate_proto` |
| `preparePrompt(prompt:options:requestID:)` throws | 47 | `rac_structured_output_prepare_prompt_proto` |
| `makeParseRequest(text:schema:requestID:)` | 60 | — |
| `makeGenerateRequest(prompt:options:requestID:)` | 72 | — |

#### §6.5.25 CppBridge+Telemetry.swift

**LOC:** 260 — `CppBridge.Events` (analytics registration) and `CppBridge.Telemetry` (telemetry manager).

| Method | Line | C ABI |
|---|---|---|
| `Events.register()` | 35 | `rac_analytics_events_set_callback` |
| `Events.unregister()` | 53 | `rac_analytics_events_set_callback(nil, nil)` |
| `Telemetry.initialize(environment:)` | 89 | `rac_telemetry_manager_create`, `_set_device_info`, `_set_http_callback` |
| `Telemetry.shutdown()` | 126 | `rac_telemetry_manager_flush`, `_destroy` |
| `Telemetry.trackAnalyticsEvent(...)` | 141 | `rac_telemetry_manager_track_analytics` |
| `Telemetry.flush()` | 150 | `rac_telemetry_manager_flush` |
| `Events.emitSDKInitStarted/Completed/Failed/ModelsLoaded` | 216–247 | `rac_sdk_event_publish_proto` |

`telemetryHttpCallback` (line 162) receives endpoint, jsonBody, requiresAuth from C++ and launches a `Task` calling `performTelemetryHTTP`.

#### §6.5.26 CppBridge+ToolCalling.swift

**LOC:** 83 — `CppBridge.ToolCalling` (pure namespace enum). Request-builder bridge; no parsing logic in Swift.

| Method | Line |
|---|---|
| `makePromptFormatRequest(...)` | 31 |
| `makeValidationRequest(...)` | 39 |
| `bridgeOptions(_:tools:)` | 51 |

`bridgeOptions` maps the format hint string to `RAToolCallFormatName` enum value: `lfm/liquid/pythonic/hermes` → `.pythonic`; `openai/openai_functions` → `.openaiFunctions`; `xml` → `.xml`; `native` → `.native`; `json/default/auto` → `.json`.

#### §6.5.27 CppBridge+STT.swift

**LOC:** 112 — `CppBridge.STT` — `public actor`. `ComponentActor(vtable: .stt)` wrapper with STT-specific model load.

| Method/Property | Line | C ABI |
|---|---|---|
| `getHandle()` async throws | 43 | via `ComponentActor` |
| `isLoaded` { get async } | 50 | via `ComponentActor` |
| `currentModelId` | 55 | — |
| `supportsStreaming` { get async } | 58 | `rac_stt_component_supports_streaming` |
| `loadModel(_:modelId:modelName:framework:)` async throws | 68 | `rac_stt_component_configure` + `ComponentActor.loadModel` |
| `unload()` async | 99 | via `ComponentActor` |
| `destroy()` async | 107 | via `ComponentActor` |

Mirrors `loadedModelId: String?` as actor-private state for the same-model fast-path. Before `inner.loadModel`, if `framework != RAC_FRAMEWORK_UNKNOWN`, configures the component via `rac_stt_component_configure(handle, &config)`.

#### §6.5.28 CppBridge+TTS.swift

**LOC:** 77 — `CppBridge.TTS` — `public actor`. Voice-terminology API.

| Method/Property | Line | C ABI |
|---|---|---|
| `getHandle()` async throws | 41 | via `ComponentActor` |
| `currentVoiceId` { get async } | 48 | via `inner.currentAssetId` |
| `loadVoice(_:voiceId:voiceName:)` async throws | 55 | via `ComponentActor.loadModel` |
| `unload()` async | 60 | via `ComponentActor` |
| `stop()` async | 64 | `rac_tts_component_stop` |
| `destroy()` async | 72 | via `ComponentActor` |

The `.tts` vtable's `loadModel` slot forwards to `rac_tts_component_load_voice`.

#### §6.5.29 CppBridge+VAD.swift

**LOC:** 148 — `CppBridge.VAD` — `public actor`. Extended lifecycle API.

| Method/Property | Line | C ABI |
|---|---|---|
| `getHandle()` async throws | 47 | via `ComponentActor` |
| `isInitialized` { get async } | 54 | `rac_vad_component_is_initialized` |
| `isModelLoaded` { get async } | 64 | via `ComponentActor.isLoaded` |
| `currentModelId` | 69 | — |
| `loadModel(_:modelId:modelName:)` async throws | 76 | via `ComponentActor.loadModel` |
| `unloadModel()` async | 93 | `rac_vad_component_unload`, `ComponentActor.markAssetLoaded(nil)` |
| `initialize(_:)` throws | 107 | via `configureLifecycle` |
| `start()` / `stop()` / `reset()` throws | 115 / 121 / 127 | via lifecycle proto |
| `cleanup()` async | 134 | `rac_vad_component_cleanup` |
| `destroy()` async | 143 | via `ComponentActor` |

`loadModel` clears `loadedModelId = nil` before the C call so a failed load does not prevent retry. `unloadModel` reverts to energy-based VAD.

#### §6.5.30 CppBridge+VLM.swift

**LOC:** 102 — `CppBridge.VLM` — `public actor`. Lifecycle-routing actor.

| Method/Property | Line | C ABI |
|---|---|---|
| `getHandle()` async throws | 53 | via `ComponentActor.getHandle()` |
| `cancel()` async | 66 | `cancelLifecycle()` |
| `supportsStreaming` { get async } | 79 | `rac_vlm_component_supports_streaming` |
| `state` { get async } | 85 | `rac_vlm_component_get_state` |
| `destroy()` async | 98 | via `ComponentActor` |

In V2 the per-handle component is not loaded with a model; `rac_vlm_process_proto` routes through the lifecycle-owned VLM service.

#### §6.5.31 CppBridge+VoiceAgent.swift

**LOC:** 90 — `CppBridge.VoiceAgent` — `public actor`. Composite handle actor.

| Method/Property | Line | C ABI |
|---|---|---|
| `getHandle()` async throws | 31 | `rac_voice_agent_create` |
| `requireExistingHandle()` throws | 54 | — |
| `isReady` | 64 | `rac_voice_agent_is_ready` |
| `cleanup()` | 74 | `rac_voice_agent_cleanup` |
| `destroy()` | 81 | `rac_voice_agent_cleanup`, `_destroy` |

`getHandle()` composite creation: concurrently gathers four handles via `async throws` (`LLM.shared.getHandle`, `STT`, `TTS`, `VAD`), then calls `rac_voice_agent_create(llm, stt, tts, vad, &newHandle)`.

### §6.6 Type-Helper Extensions

Seven files under `Foundation/Bridge/Extensions/` form the type-conversion layer between proto-generated Swift types (`RA*`) and the C ABI exposed by `CRACommons`. They are consumed exclusively by the `CppBridge+*.swift` domain slices; no public RunAnywhere API calls them directly.

#### §6.6.1 ModelTypes+CppBridge.swift

**LOC:** 144 — Extends `ModelCategory`, `ModelFormat`, `InferenceFramework`, `ModelSource`, `RAModelInfo`.

- `ModelCategory.toC()` (line 17) — calls `rac_model_category_from_proto`
- `ModelCategory.init(from:)` (line 25) — calls `rac_model_category_to_proto`
- `ModelFormat.toC()`/`init(from:)` (lines 40/48) — mirror category pattern
- `InferenceFramework.toC()`/`init(from:)` (lines 63/67) — forwarders
- `ModelSource.init(from:)` (line 77) — `rac_model_source_to_proto`
- `RAModelInfo.init(from cModel: rac_model_info_t)` (line 91) — full struct unpack
- Private `apply(cArtifact:)` (line 120) — switches on `cArtifact.kind` for the artifact oneof

#### §6.6.2 RAAudioFormat+Extensions.swift

**LOC:** 38 — `Codable` conformance for `RAAudioFormat`. `init(from decoder:)` decodes a single `String` value then calls `RAAudioFormat.from(wireString:)`; encodes via `self.wireString` preserving lowercase short names (`"pcm"`, `"wav"`).

#### §6.6.3 RAChatMessage+Extensions.swift

**LOC:** 48 — Extends `RAMessageRole`. `wireString` (line 16): `"user"`, `"assistant"`, `"system"`, `"tool"`, `"unspecified"`. `init?(wireString:)` (line 27). `Codable` conformance.

#### §6.6.4 RALLMTypes+CppBridge.swift

**LOC:** 117 — Extends `RALLMGenerationOptions`, `RALLMGenerationResult`, `RAThinkingTagPattern`, `RAExecutionTarget`.

- `RALLMGenerationOptions.defaults()` (line 14): `maxTokens=100, temperature=0.8, topP=1.0, topK=0, repetitionPenalty=1.0`
- `init(maxTokens:temperature:topP:topK:...)` (line 24) convenience init
- `toRALLMGenerateRequest(prompt:)` (line 50) — converts to `RALLMGenerateRequest` proto
- `tokensUsed`/`latencyMs`/`timeToFirstTokenMs` (line 92–94) — shorthand accessors
- `RAThinkingTagPattern.defaultPattern` (line 100): `<think>...</think>`
- `RAExecutionTarget.wireString` (line 109)

#### §6.6.5 RASTTTypes+CppBridge.swift

**LOC:** 97 — Extends `RASTTConfiguration`, `RASTTOptions`, `RASTTOutput`, `RASTTPartialResult`.

- `RASTTConfiguration.modelId` (line 14) — nil-guard
- `RASTTOptions.languageString` (line 20) — maps `RASTTLanguage` to BCP-47
- `RASTTOptions.init(language:detectLanguage:...)` (line 39)
- `languageFromString(_:)` (line 58) — splits on `-`
- `RASTTOutput.timestamp` (line 83) — `Date()` at access
- `RASTTPartialResult.transcript` (line 96) — alias for `text`

#### §6.6.6 RATTSTypes+CppBridge.swift

**LOC:** 69 — Extends `RATTSConfiguration`, `RATTSOptions`, `RATTSOutput`.

- `RATTSConfiguration.modelId` (line 14)
- `RATTSOptions.init(voice:language:rate:...)` (line 20)
- `rate` / `language` / `useSSML` aliases (lines 41/45/49) — `speakingRate`/`languageCode`/`enableSsml`
- `RATTSOutput.format` (line 61) — alias for `audioFormat`

#### §6.6.7 RAVADTypes+CppBridge.swift

**LOC:** 27 — Extends `RAVADConfiguration`, `RAVADResult`.

- `RAVADConfiguration.modelId` (line 14)
- `RAVADResult.isSpeechDetected` (line 25) — alias for `isSpeech`
- `RAVADResult.energyLevel` (line 26) — alias for `energy`

---

## §7 Foundation Utilities

### §7.1 SDKConstants

**File:** `Sources/RunAnywhere/Foundation/Constants/SDKConstants.swift` (37 LOC)

`SDKConstants` is a `public enum` (caseless, used as a namespace). All members are `public static let` constants.

| Constant | Value / Derivation |
|---|---|
| `version` | `"0.19.13"` (line 14) — kept in sync with `sdk/runanywhere-commons/VERSION` |
| `name` | `"RunAnywhere SDK"` (line 17) |
| `userAgent` | `"\(name)/\(version) (Swift)"` (line 20) |
| `platform` | Compile-time conditional (lines 23–33): `"ios"`, `"macos"`, `"tvos"`, `"watchos"`, or `"unknown"` |
| `productionLogLevel` | `"error"` (line 36) |

### §7.2 RASDKComponent+DisplayName

**File:** `Sources/RunAnywhere/Foundation/Core/RASDKComponent+DisplayName.swift` (27 LOC)

A `public extension` on the proto-generated `RASDKComponent` enum. The single computed property `displayName: String` maps every enum case to a human-readable string via a `switch`: `.llm` → `"Language Model"`, `.vlm` → `"Vision Language Model"`, `.stt` → `"Speech to Text"`, `.tts` → `"Text to Speech"`, `.vad` → `"Voice Activity Detection"`, `.voiceAgent` → `"Voice Agent"`, `.embeddings` → `"Embedding"`, `.diffusion` → `"Image Generation"`, `.rag` → `"Retrieval-Augmented Generation"`, `.wakeword` → `"Wake Word"`, `.speakerDiarization` → `"Speaker Diarization"`, `default` → `"Unknown"`.

### §7.3 Errors

#### §7.3.1 SDKException

**File:** `Sources/RunAnywhere/Foundation/Errors/SDKException.swift` (359 LOC)

`SDKException` is declared at line 20 as:

```swift
public struct SDKException: Error, LocalizedError, Sendable, CustomStringConvertible
```

It is a value type (`struct`) with `Sendable` conformance, making it safe to cross actor boundaries.

**Stored properties (lines 23–29):**
- `proto: RASDKError` — the canonical proto-encoded error (`errors.pb.swift`); this is the wire-canonical source of truth.
- `underlying: (any Error)?` — optional Swift error that is not part of the wire proto.
- `stackTrace: [String]` — captured at construction via `Thread.callStackSymbols`; never sent over the wire.

**Initializers:**
- `init(proto:underlying:)` (line 31) — direct proto wrapper; `stackTrace` captured here.
- `init(code:message:category:underlying:)` (line 37) — constructs a proto in-line; maps `RAErrorCode.rawValue` to a negative `cAbiCode` via the formula at line 49 (`-Int32(raw)` for values 1–899).

**Convenience accessors (lines 62–64):** `code`, `category`, `message` — each delegates to the corresponding field on `proto`.

**`LocalizedError` conformance (lines 68–97):**
- `errorDescription` → `proto.message`
- `failureReason` → `"[\(proto.category)] \(proto.code)"`
- `recoverySuggestion` — switch on `proto.code` returns plain-English strings for `.notInitialized`, `.modelNotFound`, `.networkUnavailable`, `.insufficientStorage`, `.insufficientMemory`, `.microphonePermissionDenied`, `.timeout`, `.invalidApiKey`, `.cancelled`; `default` → nil.

**`Equatable` and `Hashable` (lines 121–135):** equality and hashing operate on `proto.code`, `proto.category`, and `proto.message` only.

**`telemetryProperties` (lines 111–116):** returns a `[String: String]` with keys `error_code`, `error_category`, `error_message`.

**Generic factory (lines 141–153):**
```swift
static func make(code:message:category:underlying:shouldLog:)
```
Calls `SDKException(code:...)`, then conditionally calls `ex.log()` when `shouldLog` is true and `!code.isExpected`.

**Common shortcut factories (lines 158–198):** `.modelNotFound(_:)`, `.notInitialized(_:)`, `.invalidConfiguration(_:)`, `.validationFailed(_:)`, `.cancelled(_:)` (with `shouldLog: false`), `.notImplemented(_:)`, `.timeout(_:)`, `.networkError(_:)`.

**Conversion from arbitrary `Error` (lines 203–247):** `from(_ error:category:)` first checks identity pass-through, then inspects `NSError.domain == NSURLErrorDomain` to call `fromURLError(...)`, falling back to `.unknown`. URL error mapping (lines 229–244) translates `NSURLError` codes to `RAErrorCode`.

**ONNX error mapping (lines 252–296):** `fromONNXCode(_ code:Int32)` maps ONNX Runtime C codes (-1 through -10) to `RAErrorCode` values.

**`RAErrorCode.isExpected` (lines 301–310):** extension on the proto enum; returns `true` for `.cancelled` and `.streamCancelled` only.

**Logging hook (lines 316–348):** `log(file:line:function:)` maps `.cancelled` to `LogLevel.info`; all others to `.error`. Metadata includes `error_code`, `error_category`, `source_file`, `source_line`, `source_function`, optionally `underlying_error`, `failure_reason`, and up to 5 SDK frames from `stackTrace`.

**C ABI accessor (lines 354–357):** `rawCABICode: Int32` returns `proto.cAbiCode`.

#### §7.3.2 RASDKError+Helpers

**File:** `Sources/RunAnywhere/Foundation/Errors/RASDKError+Helpers.swift` (97 LOC)

Extends the proto-generated value type `RASDKError` with Swift conveniences. Because `RASDKError` is a proto value type and cannot conform to `Error` directly, the extension provides factory and bridging methods rather than protocol conformances.

**`RASDKError` factories:**
- `make(code:message:category:nestedMessage:)` (line 30) — constructs a `RASDKError` by setting fields directly.
- `from(rcResult:)` (line 52) — maps a `rac_result_t` to an `RASDKError?` via the C ABI function `rac_result_to_proto_error`. Returns `nil` on `RAC_SUCCESS`; otherwise allocates a `rac_proto_buffer_t`, deserializes, and returns the parsed error.
- `summary: String` (line 71) — formatted as `"[\(category)] \(code): \(message)"`.
- `throwAsException()` (line 76) — wraps `self` in `SDKException(proto: self)` and throws.

**`SDKException` C ABI bridge extension:**
- `SDKException.from(rcResult:)` (line 86) — delegates to `RASDKError.from(rcResult:)`, then wraps the result.
- `SDKException.throwIfError(_ result:)` (line 92) — calls `from(rcResult:)` and throws if non-nil. The standard pattern for checking `rac_result_t` return values.

### §7.4 KeychainManager

**File:** `Sources/RunAnywhere/Foundation/Security/KeychainManager.swift` (251 LOC)

`public final class KeychainManager` — singleton accessed via `KeychainManager.shared`. Uses Security framework.

**Configuration:**
- `serviceName = "com.runanywhere.sdk"` — the `kSecAttrService` value for all items.
- `accessGroup: String? = nil` — app group sharing disabled.

**`KeychainKey` enum (lines 19–27):** private, `RawValue: String`. Four cases: `apiKey`, `baseURL`, `environment`, `deviceUUID` (all prefixed `com.runanywhere.sdk.`).

**SDK credential methods:**
- `storeSDKParams(_ params:)` (line 38) — stores `apiKey`, `baseURL.absoluteString`, `environment.wireString`.
- `retrieveSDKParams()` (line 53) — reconstructs an `SDKInitParams?` by reading all three keys.
- `clearSDKParams()` (line 68) — calls `delete(for:)` on all three keys.

**Device identity methods:**
- `storeDeviceUUID(_:)` (line 79), `retrieveDeviceUUID()` (line 86).

**Generic storage methods:**
- `store(_ value:String, for key:)` (line 97) — UTF-8 encode then delegate.
- `store(_ data:Data, for key:)` (line 110) — update-first pattern: `SecItemUpdate`; if `errSecItemNotFound`, `SecItemAdd`.
- `retrieve(for key:)` (line 131), `retrieveData(for key:)` (line 145).
- `retrieveDataIfExists(for key:)` (line 169) — returns `nil` (no throw) for `errSecItemNotFound`.
- `retrieveIfExists(for key:)` (line 196), `delete(for key:)` (line 211, idempotent), `exists(for key:)` (line 223).

**`baseQuery(for key:)` (line 233):** Builds the shared query dictionary with `kSecClass = kSecClassGenericPassword`, `kSecAttrService = "com.runanywhere.sdk"`, `kSecAttrAccount = key`, `kSecAttrSynchronizable = false`, `kSecAttrAccessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.

---

## §8 Adapters & Streaming

### §8.1 HandleStreamAdapter (generic)

**File:** `Sources/RunAnywhere/Adapters/HandleStreamAdapter.swift` (389 LOC)

```swift
public final class HandleStreamAdapter<Handle: Hashable, Event: Message>: @unchecked Sendable
```

Declared at line 61. `Handle: Hashable` enables per-handle keying. `Event: Message` (SwiftProtobuf) enables deserialization via `Event(serializedBytes:)`. `@unchecked Sendable` — safety is rooted in `OSAllocatedUnfairLock`.

**Type aliases (lines 67–80):**
- `CCallback` — `@convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?) -> Void`
- `Register` — `@Sendable (Handle, CCallback?, UnsafeMutableRawPointer?) -> rac_result_t`
- `Unregister` — `@Sendable (Handle) -> Void`
- `IsTerminalEvent` — `@Sendable (Event) -> Bool` — optional predicate

**`HandleFanOut` (private inner class, lines 84–236):**
- `FanOutState` struct: `continuations: [UUID: AsyncStream<Event>.Continuation]`, `userPtr: UnsafeMutableRawPointer?`, `installed: Bool`. Guarded by `OSAllocatedUnfairLock<FanOutState>`.
- `attach(_ continuation:)` (line 113) — checks `installed`, calls `install()` if needed, stores continuation under a new `UUID`.
- `detach(_ id:)` (line 128) — removes; if map empties, calls `tearDown()`.
- `install()` (line 139) — uses `Unmanaged.passRetained(self).toOpaque()` to produce `userPtr`. Trampoline recovers via `Unmanaged<AnyObject>.fromOpaque(userData).takeUnretainedValue()`.
- `deliverBytes(_:_:)` (line 175) — deserializes to `Event`; on failure calls `finishAll()`. On success, calls `broadcast(event)`.
- `broadcast(_:)` (line 185) — if terminal, atomically clears continuations under lock before iterating. Yields, then finishes if terminal.
- `tearDown()` (line 221) — calls `unregister(handle)`, releases retained pointer, removes from `HandleStreamAdapter.removeFanOut(for: storeKey)`.

**Static fan-out registry (lines 239–275):** Because Swift forbids generic stored statics, the lock is held by the non-generic singleton `HandleStreamAdapterRegistry.shared`. `HandleStreamStoreKey` (line 374): `Hashable & Sendable` struct with `streamKey: String` and `handleHash: Int`.

**`stream()` (line 327):** Returns `AsyncStream<Event>`. Resolves or creates per-handle `HandleFanOut`, calls `attach`. Sets `continuation.onTermination` to call `fanOut.detach(id)`.

**`tearDown()` (public, line 351):** Force-tears down. Intended for component destruction paths.

### §8.2 LLMStreamAdapter (specialization)

**File:** `Sources/RunAnywhere/Adapters/LLMStreamAdapter.swift` (58 LOC)

```swift
public typealias LLMStreamAdapter = HandleStreamAdapter<rac_handle_t, RALLMStreamEvent>
```

`convenience init(handle: rac_handle_t)` wires:
- `streamKey: "llm"`
- `register: { h, cb, ud in rac_llm_set_stream_proto_callback(h, cb, ud) }`
- `unregister: { h in _ = rac_llm_unset_stream_proto_callback(h) }`
- `isTerminalEvent: { $0.isFinal }`

### §8.3 VoiceAgentStreamAdapter (specialization)

**File:** `Sources/RunAnywhere/Adapters/VoiceAgentStreamAdapter.swift` (59 LOC)

```swift
public typealias VoiceAgentStreamAdapter = HandleStreamAdapter<rac_voice_agent_handle_t, RAVoiceEvent>
```

`convenience init(handle: rac_voice_agent_handle_t)` wires:
- `streamKey: "voice-agent"`
- `register: { h, cb, ud in rac_voice_agent_set_proto_callback(h, cb, ud) }`
- `unregister: { h in _ = rac_voice_agent_set_proto_callback(h, nil, nil) }` — same symbol for install and clear
- No `isTerminalEvent` (omitted, defaults to `nil`) — voice events fan out indefinitely

---

## §9 Infrastructure

### §9.1 Device

**File:** `Sources/RunAnywhere/Infrastructure/Device/Models/Domain/DeviceInfo.swift`

`DeviceInfo` is a `public struct` conforming to `Codable`, `Sendable`, and `Equatable`. It carries 19 fields that mirror the backend `schemas/device.py DeviceInfo` schema. All property names use camelCase; `CodingKeys` maps each to snake_case for JSON serialization.

#### Fields

| Swift property | JSON key | Type | Semantics |
|---|---|---|---|
| `deviceModel` | `device_model` | `String` | Human-readable model name |
| `deviceName` | `device_name` | `String` | User-assigned device name |
| `platform` | `platform` | `String` | `"ios"`, `"macos"`, or `"web"` |
| `osVersion` | `os_version` | `String` | Cleaned version string |
| `formFactor` | `form_factor` | `String` | `"phone"`, `"tablet"`, `"laptop"`, `"desktop"`, etc. |
| `architecture` | `architecture` | `String` | `"arm64"` or `"x86_64"` |
| `chipName` | `chip_name` | `String` | Chip model |
| `totalMemory` | `total_memory` | `Int` | `ProcessInfo.processInfo.physicalMemory` |
| `availableMemory` | `available_memory` | `Int` | physical minus `mach_task_basic_info.resident_size` |
| `hasNeuralEngine` | `has_neural_engine` | `Bool` | `architecture == "arm64"` |
| `neuralEngineCores` | `neural_engine_cores` | `Int` | `16` on arm64, `0` on x86_64 |
| `gpuFamily` | `gpu_family` | `String` | Hard-coded `"apple"` |
| `batteryLevel` | `battery_level` | `Double?` | iOS only |
| `batteryState` | `battery_state` | `String?` | `"charging"/"full"/"unplugged"/nil` |
| `isLowPowerMode` | `is_low_power_mode` | `Bool` | `ProcessInfo.isLowPowerModeEnabled` |
| `coreCount` | `core_count` | `Int` | `ProcessInfo.processorCount` |
| `performanceCores` | `performance_cores` | `Int` | Estimated P-cores |
| `efficiencyCores` | `efficiency_cores` | `Int` | `coreCount - performanceCores` |
| `deviceFingerprint` | `device_fingerprint` | `String?` | `CppBridge.Device.persistentId` |

#### Population path (`DeviceInfo.current`)

1. `ProcessInfo.processInfo` provides `processorCount`, `physicalMemory`, `isLowPowerModeEnabled`.
2. `getModelIdentifier()` reads `hw.machine` (iOS) or `hw.model` (macOS) via `sysctlbyname`.
3. `getChipName(for:)` maps model-ID prefix strings to chip names (e.g. `"iPhone17,1"` → `"A18 Pro"`).
4. `getCoreDistribution(totalCores:modelId:)` heuristically splits P/E cores.
5. Platform blocks populate `platform`, `formFactor`, `deviceModel`, `deviceName`, battery fields.
6. `getAvailableMemory()` calls `task_info(mach_task_self_, MACH_TASK_BASIC_INFO, ...)`.
7. `deviceFingerprint` is populated from `CppBridge.Device.persistentId`.

#### Computed properties

- `cleanOSVersion`, `deviceType`, `modelName`, `deviceId`.

### §9.2 Download

**File:** `Sources/RunAnywhere/Infrastructure/Download/Models/Output/DownloadProgress.swift`

`RADownloadProgress`, `RADownloadStage`, and `RADownloadState` are proto-generated. This file adds Swift sugar on top via extensions.

#### `RADownloadStage` extension

- `displayName: String` — UI labels.
- `progressRange: (start: Double, end: Double)` — downloading = 0–80%, extracting = 80–95%, validating = 95–99%, completed = 100%.

#### `RADownloadProgress` extension

- `percentage: Double` — returns `stageProgress` while in `.downloading` stage; `overallProgress` otherwise.
- `speed: Double?`, `estimatedTimeRemaining: TimeInterval?`.
- Factory methods: `extraction(modelId:progress:totalBytes:)`, `completed(modelId:totalBytes:)`, `failed(_:modelId:bytesDownloaded:totalBytes:)`.

### §9.3 FileManagement

**File:** `Sources/RunAnywhere/Infrastructure/FileManagement/Utilities/FileOperationsUtilities.swift`

`FileOperationsUtilities` is a `public struct` with two static methods:
- `existsWithType(at url: URL) -> (exists: Bool, isDirectory: Bool)` — calls `FileManager.default.fileExists(atPath:isDirectory:)`.
- `fileSize(at url: URL) -> Int64?` — calls `attributesOfItem(atPath:)` and extracts `.size`.

### §9.4 Logging

#### §9.4.1 SDKLogger

**File:** `Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift`

Three layers: `LogLevel` enum, `Logging` singleton (router), `SDKLogger` struct (per-component wrapper).

**`LogLevel`** — `public enum LogLevel: Int, Comparable` with cases `.debug = 0`, `.info = 1`, `.warning = 2`, `.error = 3`, `.fault = 4`.

**`LogEntry`** — `public struct LogEntry: Sendable` captures `timestamp`, `level`, `category`, `message`, `metadata`, `deviceInfo`.

**`LogDestination` protocol** — `public protocol LogDestination: AnyObject, Sendable` with `identifier`, `isAvailable`, `write(_:)`, `flush()`.

**`Logging` singleton** — `public final class Logging: @unchecked Sendable` holds state inside `OSAllocatedUnfairLock<State>`. `log` flow:

1. Snapshot `(config, destinations)`.
2. Guard `level >= config.minLogLevel`.
3. Assemble `LogEntry`.
4. Print to console if `enableLocalLogging`.
5. Iterate `destinations`.

Metadata sanitization: `sanitizeMetadata(_:)` calls `rac_log_metadata_should_redact(_:_:)` (a C ABI function); keys returning `1` have values replaced with `"[REDACTED]"`.

**`SDKLogger` struct** — `public struct SDKLogger: Sendable` wraps `category: String`. Methods: `debug` (`@inlinable`, no-ops in non-DEBUG), `info`, `warning`, `error`, `fault`, `logError`.

Pre-instantiated: `SDKLogger.shared` ("RunAnywhere"), `.llm`, `.stt`, `.tts`, `.download`, `.models`.

Environment presets: `.development` → minLevel `.debug`; `.staging` → `.info`; `.production` → `.warning`.

#### §9.4.2 Custom Log Destinations

`LogDestination` remains the extension point for additional sinks. Built-in logging now routes to the OS log/console path plus any app-registered custom destinations.

Additional: `captureError(_:context:)`, `setUser(...)`, `clearUser()`, `flush(timeout:)`, `close()`.

---

## §10 HttpTransport

### §10.1 URLSessionHttpTransport.swift (685 LOC)

**File:** `Sources/RunAnywhere/HttpTransport/URLSessionHttpTransport.swift`

`public enum URLSessionHttpTransport` is a caseless enum used as a namespace. It is the sole implementation of the `rac_http_transport_ops_t` vtable for all Apple platforms, replacing libcurl.

#### Static state

| Member | Type | Purpose |
|---|---|---|
| `registrationState` | `OSAllocatedUnfairLock<Bool>` | Ensures `register()` is idempotent |
| `sharedSession` | `URLSession` | Backing session for `request_send`; 60s request timeout, 600s resource timeout, no cache |
| `streamingSessionOverride` | `OSAllocatedUnfairLock<URLSession?>` | Optional host-supplied session for streaming |
| `streamRegistry` | `StreamRegistry` | Tracks live streaming tasks for `cancelAllStreams()` |
| `ops` | `rac_http_transport_ops_t` (nonisolated unsafe) | The C vtable struct |

#### `register()`

1. Acquires `registrationState` lock; returns early if already `true`.
2. Assigns three C function pointer slots: `ops.request_send`, `ops.request_stream`, `ops.request_resume`.
3. Calls `rac_http_transport_register(&ops, nil)`.
4. On `RAC_ERROR_*`: rolls back `registrationState` to `false`.

#### `unregister()`

Passes `nil` to `rac_http_transport_register`, calls `cancelAllStreams()`, clears `streamingSessionOverride`.

#### Internal types

**`RequestSnapshot`** — materializes a `rac_http_request_t` into Swift value types before any async boundary: `method`, `url`, `headers`, `body`, `timeoutMs`. `makeURLRequest(additionalRangeFromByte:)` appends `"Range: bytes=N-"` header when needed.

**`ResponseWriter`** — writes back into `rac_http_response_t` using `malloc` / `strdup` to match the ownership contract `rac_http_response_free` expects.

**`RequestExecutor`** — two static entry points:

`send(req:out:)` — single-shot buffered request:
1. Snapshots the request.
2. Creates `DispatchSemaphore(value: 0)`.
3. Calls `sharedSession.dataTask(with:completionHandler:)`, signals semaphore.
4. Calls `semaphore.wait()` to block the C thread.
5. Maps transport errors via `mapTransportError(_:)`.
6. Writes response with `ResponseWriter.write(...)`.

`stream(req:chunkFn:chunkUserData:out:resumeFromByte:)` — streaming / resume:
1. Snapshots the request; if `resumeFromByte > 0`, the `Range` header is injected.
2. Creates a `StreamDelegate`.
3. Checks `streamingSessionOverride`: uses the override if set; otherwise creates a per-call session with `timeoutIntervalForResource = 24 * 60 * 60` and `waitsForConnectivity = true`.
4. For host-owned sessions, attaches `delegate` via `task.delegate = delegate` (iOS 15+ task-level delegate API).
5. Registers in `streamRegistry`, calls `task.resume()`, then `delegate.completion.wait()`.
6. After completion: calls `session.finishTasksAndInvalidate()` if owned.
7. Appends synthetic `"X-RAC-Range-Honored"` header (`"true"` for 206, `"false"` for 200 to range request).

`mapTransportError(_:)` converts `NSURLErrorDomain` codes: `NSURLErrorTimedOut` → `RAC_ERROR_TIMEOUT`, `NSURLErrorCancelled` → `RAC_ERROR_CANCELLED`, all others → `RAC_ERROR_NETWORK_ERROR`.

**`StreamRegistry`** — `private final class StreamRegistry: @unchecked Sendable` wraps `OSAllocatedUnfairLock<[Int: StreamDelegate]>`. `cancelAll()` snapshots dictionary under lock, then sets `cancelled = true` and `cancel()` on each entry outside the lock.

**`StreamDelegate`** — `URLSessionDataDelegate` bridges callbacks to the synchronous C ABI:

- `didReceive response` — captures `HTTPURLResponse`. When `statusCode == 206` and `resumeFromByte > 0`: initializes `totalBytesReceived = resumeFromByte`.
- `didReceive data` — increments `totalBytesReceived`, calls `chunkFn(base, data.count, totalBytesReceived, contentLength, chunkUserData)`. If returns `RAC_FALSE`: cancels.
- `didCompleteWithError` — signals `completion` semaphore.

---

## §11 Features (system-backed)

### §11.1 SystemFoundationModelsModule + SystemFoundationModelsService

**Files:**
- `Sources/RunAnywhere/Features/LLM/System/SystemFoundationModelsModule.swift`
- `Sources/RunAnywhere/Features/LLM/System/SystemFoundationModelsService.swift`

#### `SystemFoundationModels`

`public enum SystemFoundationModels` is a caseless namespace.

- `isAvailable: Bool` — delegates to `unavailableReason == nil`.
- `unavailableReason: String?` — returns disqualifying messages: Simulator, OS < iOS 26.0 / macOS 26.0, `FoundationModels` not importable, `SystemLanguageModel.default.availability` checks.

The comment states: "The C++ platform backend handles registration with the service registry. This Swift module provides the actual implementation through callbacks."

#### `SystemFoundationModelsService`

`@available(iOS 26.0, macOS 26.0, *) public class SystemFoundationModelsService`

Uses `LanguageSessionWrapper` (private struct containing a `LanguageModelSession`) as the session container.

`initialize(modelPath:)`:
1. Calls `SystemFoundationModels.unavailableReason`; throws `SDKException(.serviceNotAvailable)` if non-nil.
2. Calls private `initializeFoundationModel()` which fetches `SystemLanguageModel.default`, calls `checkModelAvailability(_:)`, then creates `LanguageModelSession(instructions:)` with a fixed system prompt.

`generate(prompt:options:)`:
1. Guards non-nil `session` and `!session.isResponding`.
2. Calls `performGeneration(with:prompt:temperature:)` which calls `session.respond(to:prompt, options: GenerationOptions(temperature:))`.
3. Catches `LanguageModelSession.GenerationError.exceededContextWindowSize` → `SDKException(.contextTooLong)`.

`streamGenerate(prompt:options:onToken:)`:
1. Iterates `for try await partialResponse in responseStream`: computes delta between `partialResponse.content` and `previousContent`, calls `onToken(newTokens)`.
2. Converts Foundation Models' cumulative-content stream into incremental tokens.

`cleanup()` sets `session = nil`.

### §11.2 AudioCaptureManager

**File:** `Sources/RunAnywhere/Features/STT/Services/AudioCaptureManager.swift`

`public class AudioCaptureManager: ObservableObject, @unchecked Sendable`. Marked `@unchecked Sendable` because mutations route to the main queue and `AVAudioEngine` is used only from `DispatchQueue.global(qos: .userInitiated)`.

Published properties: `isRecording: Bool`, `audioLevel: Float`. Target sample rate is `Double(RAC_STT_DEFAULT_SAMPLE_RATE)` (16000 Hz).

#### `requestPermission() async -> Bool`

Platform-conditional: iOS 17+ → `AVAudioApplication.requestRecordPermission()`; iOS <17 → `AVAudioSession.sharedInstance().requestRecordPermission` wrapped in `withCheckedContinuation`; macOS → `AVCaptureDevice.requestAccess(for: .audio)`.

#### `startRecording(onAudioData:)`

1. iOS/tvOS: configures `AVAudioSession` with `.record` / `.measurement`.
2. Creates `AVAudioEngine` and reads `inputNode`.
3. macOS only: calls `configureMacOSInputDevice(engine:)` before `engine.prepare()`.
4. Reads `inputFormat` from `inputNode.outputFormat(forBus: 0)`.
5. Creates target `AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)`.
6. Creates `AVAudioConverter(from: inputFormat, to: outputFormat)`.
7. Installs a tap on `inputNode` (bus 0, bufferSize 4096): each buffer calls `updateAudioLevel`, `convert`, `bufferToData`, then dispatches `onAudioData(audioData)` to main queue.
8. Starts engine on background queue.

#### `stopRecording(deactivateSession:)`

Captures engine/node references, nils them out immediately (logical stop), then dispatches `removeTap` and `engine.stop()` to background queue. Deactivates `AVAudioSession` via `Task.detached` if requested.

#### Audio level calculation

Reads `floatChannelData` from each buffer and calls `rac_audio_compute_level_db(channelData.pointee, frames, &dbLevel)` — the RMS-to-dB calculation lives in C++ commons.

#### macOS Bluetooth input handling

`configureMacOSInputDevice(engine:)` uses `MacAudioDeviceQuery` (CoreAudio HAL wrapper). If default input is Bluetooth, overrides to `builtInInputDevice()` via `AudioUnitSetProperty(kAudioOutputUnitProperty_CurrentDevice)`. Falls back to any non-Bluetooth input.

#### `convert(buffer:using:to:)`

Calls `converter.reset()` before each conversion to clear "end-of-stream" state that persists across calls on macOS.

### §11.3 AudioPlaybackManager

**File:** `Sources/RunAnywhere/Features/TTS/Services/AudioPlaybackManager.swift`

`public class AudioPlaybackManager: NSObject, ObservableObject, AVAudioPlayerDelegate`. Holds a single `AVAudioPlayer?` and bridges its delegate callbacks to both async/await and completion-handler call sites.

Published properties: `isPlaying: Bool`, `currentTime: TimeInterval`, `duration: TimeInterval`.

#### `play(_ audioData: Data) async throws`

Wraps `startPlayback(_:)` in `withCheckedThrowingContinuation`. Stores the continuation in `playbackContinuation`; `cleanupPlayback(success:)` resumes it.

#### `play(_ audioData: Data, completion:)`

Stores completion in `playbackCompletion`; `cleanupPlayback` invokes it.

#### `startPlayback(_:)`

1. Calls `configureAudioSession()`: iOS/tvOS sets `AVAudioSession` to `.playback` / `.default` with `.duckOthers`.
2. Creates `AVAudioPlayer(data: audioData)`.
3. Sets `delegate = self`, calls `prepareToPlay()`.
4. Reads `duration`, resets `currentTime = 0.0`.
5. Calls `audioPlayer.play()`.
6. Sets `isPlaying = true`.
7. Starts a `Timer` firing every 0.1s to update `currentTime`.

`stop()` / `pause()` / `resume()` operate on the player. `cleanupPlayback(success:)` invalidates timer, deactivates session, sets `isPlaying = false`, resumes/fails continuation, invokes completion handler.

### §11.4 SystemTTSService

**File:** `Sources/RunAnywhere/Features/TTS/System/SystemTTSService.swift`

`@MainActor public final class SystemTTSService: NSObject`, conforming to `AVSpeechSynthesizerDelegate`. The synthesizer is `nonisolated(unsafe)` so `nonisolated` accessors can read `isSpeaking` without hopping.

#### `speak(text:options:) async throws`

Uses `Task.detached { @MainActor [self] in ... }.value` to isolate AVFoundation from caller's async context. Inside:
1. iOS/tvOS: switches `AVAudioSession` to `.playback` / `.default` / `.duckOthers`.
2. Calls `createUtterance(text:options:)`.
3. Uses `withCheckedThrowingContinuation`; stores in `speechCompletion`.
4. Calls `synthesizer.speak(utterance)`.
5. Completion fires via delegate callbacks.

#### `resolveVoice(options:)` resolution order

1. If `options.voice` is empty/`"system"`/`"system-tts"` → `AVSpeechSynthesisVoice(language: languageCode)`.
2. `AVSpeechSynthesisVoice(identifier: voiceId)`.
3. `AVSpeechSynthesisVoice(language: voiceId)`.
4. `AVSpeechSynthesisVoice(language: languageCode)`.

`availableVoices: [String]` — `nonisolated`: `AVSpeechSynthesisVoice.speechVoices().map { $0.identifier }`.

`stop()` calls `synthesizer.stopSpeaking(at: .immediate)` then resumes `speechCompletion` with `.success(())`.

---

## §12 Generated Code

The `Generated/` directory contains 31 files: 29 proto-generated `.pb.swift` files and 2 non-proto codegen outputs (`RAConvenience.swift` and `ModalityProtoABI+Generated.swift`). All carry a `// DO NOT EDIT.` header.

### §12.1 Proto-generated `.pb.swift` files

`generate_swift.sh` invokes `protoc --swift_out="Visibility=Public:<OUT_DIR>"` against every `.proto` file in `idl/`. Output: `sdk/runanywhere-swift/Sources/RunAnywhere/Generated/`.

The 29 generated files:

| File | Domain |
|------|--------|
| `chat.pb.swift` | Chat session types |
| `component_types.pb.swift` | Component lifecycle states |
| `diffusion_options.pb.swift` | Image-generation options |
| `download_service.pb.swift` | Download orchestration messages |
| `embeddings_options.pb.swift` | Embedding configuration |
| `errors.pb.swift` | `RASDKError`, `RASDKException` |
| `hardware_profile.pb.swift` | Device capability profile |
| `lifecycle_service.pb.swift` | Lifecycle control messages |
| `llm_options.pb.swift` | LLM generation options |
| `llm_service.pb.swift` | LLM request/response types |
| `lora_options.pb.swift` | LoRA adapter options |
| `model_types.pb.swift` | `RAModelInfo`, `RAModelFormat`, etc. |
| `pipeline.pb.swift` | Composed-pipeline types |
| `rac_options.pb.swift` | Custom option extensions |
| `rag.pb.swift` | RAG session, document, query types |
| `router.pb.swift` | `RAFrameworksForCapabilityRequest/Response` |
| `sdk_events.pb.swift` | `RASDKEvent`, lifecycle event messages |
| `sdk_init.pb.swift` | `RASdkInitPhase{1,2}Request`, `RASdkInitResult` |
| `solutions.pb.swift` | Solution-runtime types |
| `storage_types.pb.swift` | Storage analyzer types |
| `structured_output.pb.swift` | Structured-output request/response |
| `stt_options.pb.swift` | STT configuration and results |
| `thinking_tag_pattern.pb.swift` | Thinking-tag parser config |
| `tool_calling.pb.swift` | Tool-use request/response types |
| `tts_options.pb.swift` | TTS synthesis options |
| `vad_options.pb.swift` | VAD configuration and statistics |
| `vlm_options.pb.swift` | VLM input/output types |
| `voice_agent_service.pb.swift` | Voice agent compose-config |
| `voice_events.pb.swift` | `RAVoiceEvent` streaming events |

All public types carry the `RA` prefix; SDK callers use typealiases that strip it (see §14.1).

Three gRPC stub files (`voice_agent_service.grpc.swift`, `llm_service.grpc.swift`, `download_service.grpc.swift`) are explicitly deleted by `generate_swift.sh` because they require macOS 15/iOS 18.

### §12.2 `RAConvenience.swift` — annotation-driven convenience codegen

`RAConvenience.swift` is generated by `idl/codegen/generate_swift_convenience.py`. Reads every `idl/*.proto` to extract custom option annotations from `idl/rac_options.proto`:
- `rac_wire_string` — string serialization key
- `rac_display_name`
- `rac_analytics_key`
- `rac_default` — default field values
- `rac_required` / `rac_min` / `rac_max` / `rac_min_float` / `rac_max_float`

Produces:
- **`wireString` and `from(wireString:)`** on `RAAudioFormat`, `RAModelCategory`, `RASDKEnvironment`, `RAModelSource`, `RAArchiveStructure`, `RASTTLanguage`.
- **`.defaults()` factory methods** on `RAEmbeddingsConfiguration`, `RAEmbeddingsOptions`, `RAVADConfiguration`, `RARAGConfiguration`, `RARAGQueryOptions`, `RASTTConfiguration`, `RASTTOptions`, `RATTSConfiguration`, `RATTSOptions`.
- **`.validate()` methods** on `RAEmbeddingsConfiguration`, `RAVADConfiguration`, `RARAGConfiguration`, `RASTTConfiguration`.

### §12.3 `ModalityProtoABI+Generated.swift` — YAML-driven ABI facade codegen

Generated by `idl/codegen/generate_swift_modality_abi.py` from `idl/codegen/swift-modality-abi.yaml`. 832 lines, 36 generated methods across 12 modality namespaces.

Five generatable `kind` values (plus `custom` left hand-written):

| `kind` | C ABI shape | Generated Swift shape |
|--------|-------------|----------------------|
| `invoke` | `(bytes, size, outBuffer) -> rc` | `func name(_ request: Req) throws -> Resp` |
| `stream` | `(bytes, size, callback, userData) -> rc` | `func name(_ request: Req) throws -> AsyncStream<Resp>` |
| `getWithContext` | `(handle, outBuffer) -> rc` | `func name(handle: Ctx) throws -> Resp` |
| `voidCall` | `(handle[, bytes, size]) -> rc` | `func name(handle: Ctx[, request: Req]) throws` |
| `createHandle` | `(bytes, size, outHandle*) -> rc` | `func name(request: Req) throws -> Ctx` |
| `invokeOutOnly` | `(outBuffer) -> rc` | `func name() throws -> Resp` |

The 12 modality namespaces: `LLM`, `StructuredOutput`, `STT`, `TTS`, `VAD`, `VoiceAgent`, `VLM`, `Embeddings`, `RAG`, `RAGFreeFunctions`, `LoRA`, `LoraRegistry`.

### §12.4 Full file inventory

| File | Kind |
|------|------|
| 29 × `*.pb.swift` | Proto-generated (`protoc --swift_out`) |
| `RAConvenience.swift` | Annotation codegen |
| `ModalityProtoABI+Generated.swift` | YAML-driven ABI codegen |

No hand-written helpers exist inside `Generated/`. All helpers (`NativeProtoABI`, `ProtoStreamContext`) live in `Foundation/Bridge/Extensions/`.

---

## §13 How Swift Talks to C++

### §13.1 The `rac_*` C ABI surface and the CRACommons module

The C ABI is exposed to Swift through the `CRACommons` clang module:

```
module CRACommons {
    umbrella header "CRACommons.h"
    export *
    module * { export * }
    link framework "Accelerate"
}
```

The umbrella header `CRACommons.h` includes every `rac_*.h` from `include/` — 96 headers covering all features. A single `import CRACommons` brings the entire C API into scope.

The `shim.c` file contains no real code (SPM requires at least one source file for a C target). All implementations live in `RACommons.xcframework`.

All C functions follow `rac_<subsystem>_<verb>[_<modifier>]`. Proto-byte APIs follow: `rac_result_t rac_<X>_proto(const uint8_t* request_bytes, size_t request_size, rac_proto_buffer_t* out_result)`.

### §13.2 The `rac_proto_buffer_t` lifecycle

Defined in `CRACommons/include/rac_proto_buffer.h`:

```c
typedef struct rac_proto_buffer {
    uint8_t* data;
    size_t size;
    rac_result_t status;
    char* error_message;
} rac_proto_buffer_t;
```

Lifecycle: caller declares on the stack, calls `rac_proto_buffer_init()`, passes pointer to the C function, C fills `data`/`size` with heap-allocated bytes, caller decodes via `NativeProtoABI.decode(_:from:)`, then caller calls `rac_proto_buffer_free()`.

Swift manages this in `NativeProtoABI`:
- `NativeProtoABI.free(_:)` wraps `rac_proto_buffer_free`.
- `NativeProtoABI.invoke(_:symbol:symbolName:responseType:)` handles the complete call: serializes via `request.serializedData()`, passes pointer + count, checks `status == RAC_SUCCESS`, decodes via `init(serializedBytes:)`, and calls `defer { free(&outBuffer) }`.
- `NativeProtoABI.withSerializedBytes(_:_:)` handles `Data → UnsafePointer<UInt8>` binding.

### §13.3 Platform Adapter IoC

`rac_platform_adapter_t` is a flat C struct of 18 function-pointer fields and one `void* user_data`. Swift populates it via `rac_set_platform_adapter()` before `rac_init()`.

| Field | Purpose |
|-------|---------|
| `file_exists` | Check file existence |
| `file_read` | Read file into C-owned buffer |
| `file_write` | Write buffer to file |
| `file_delete` | Delete file |
| `secure_get` / `secure_set` / `secure_delete` | Keychain/Secure storage CRUD |
| `log` | Structured log delivery |
| `track_error` | Error JSON to platform error tracking (optional, can be NULL) |
| `now_ms` | Millisecond clock |
| `get_memory_info` | RAM usage query |
| `http_download` / `http_download_cancel` | Platform-managed HTTP download |
| `extract_archive` | Archive extraction (ZIP/TAR) |
| `file_list_directory` | Two-call directory enumeration |
| `is_non_empty_directory` | Directory probe |
| `get_vendor_id` | Apple `identifierForVendor` (optional) |
| `user_data` | Opaque context |

NULL fields cause C++ to fall back or return `RAC_ERROR_NOT_SUPPORTED`. See §6.5.19 for the Swift implementation of each slot.

### §13.4 Plugin ABI v4 — `rac_engine_vtable_t`

Every backend publishes a single `rac_engine_vtable_t`:

- `rac_engine_metadata_t metadata` — `abi_version` (must equal `RAC_PLUGIN_API_VERSION`), `name`, `display_name`, `engine_version`, `priority`, `capability_flags`, optional `runtimes[]` + `formats[]`.
- `rac_result_t (*capability_check)(void)` — called once after ABI version validation.
- `void (*on_unload)(void)` — called on unload.
- 7 named primitive slots: `llm_ops`, `stt_ops`, `tts_ops`, `vad_ops`, `embedding_ops`, `vlm_ops`, `diffusion_ops`. NULL means the engine does not serve that primitive. (The former `rerank_ops` was removed in ABI v4.)
- 10 `const void* reserved_slot_N` fields.

`metadata.abi_version` must equal `RAC_PLUGIN_API_VERSION` (currently `4u`); mismatch causes `RAC_ERROR_ABI_VERSION_MISMATCH`. On iOS, `RAC_STATIC_PLUGINS=ON` forces static registration via `RAC_STATIC_PLUGIN_REGISTER(name)` + `-force_load`; no `dlopen`.

### §13.5 Streaming fan-out — `HandleStreamAdapter`

C++ allows only one proto-byte callback registration per component handle. `HandleStreamAdapter<Handle, Event>` multiplexes one C callback to multiple `AsyncStream<Event>` consumers. See §8.1 for the full implementation.

Summary:
1. A global `OSAllocatedUnfairLock<[HandleStreamStoreKey: AnyObject]>` maps `(streamKey, handle.hashValue)` → `HandleFanOut`.
2. First `stream()` creates a `HandleFanOut`, installs trampoline via `register(handle, trampoline, userPtr)`.
3. Subsequent `stream()` calls reuse the existing `HandleFanOut`.
4. Trampoline calls `HandleStreamFanOutEntry.deliverBytes(_:_:)`, which deserializes via `Event(serializedBytes:)` and calls `broadcast`.
5. `broadcast` yields to each continuation, finishes if terminal, calls `tearDown`.
6. `onTermination` of each `AsyncStream` calls `fanOut.detach(id)`.

### §13.6 Symbol loading — `NativeProtoABI.load`

```swift
static func load<T>(_ symbolName: String, as _: T.Type) -> T? {
    guard let symbol = dlsym(defaultHandle, symbolName) else { return nil }
    return unsafeBitCast(symbol, to: T.self)
}
```

`defaultHandle` is `UnsafeMutableRawPointer(bitPattern: -2)` (Darwin `RTLD_DEFAULT`). Every C symbol table uses this at file scope to resolve lazily at first access. `nil` result → `NativeProtoABI.require(_:named:)` throws `SDKException(code: .notSupported, ...)`.

### §13.7 Two-phase initialization

**Phase 1 (synchronous)** — `CppBridge.SdkInit.phase1()` builds `RASdkInitPhase1Request` proto (environment, apiKey, baseURL, deviceId), calls `NativeProtoABI.invoke` against `rac_sdk_init_phase1_proto`. C++ validates inputs, calls `rac_state_initialize()`, returns `RASdkInitResult`.

**Phase 2 (async)** — `CppBridge.SdkInit.phase2()` sends `RASdkInitPhase2Request()` (empty) to `rac_sdk_init_phase2_proto`. C++ owns the step list: HTTP transport setup, authentication, device registration, model assignment fetch, discovered-model scan.

Before `phase1()` is called, Swift performs synchronously:
- Registers the platform adapter via `rac_set_platform_adapter()`
- Registers HTTP transport ops via `rac_http_transport_register()`
- Registers backend plugins via `rac_backend_*_register()`
- Configures logging level

See §5.1 for the public `RunAnywhere.initialize` caller surface.

### §13.8 Concurrency contract

C callbacks may arrive on any thread. Swift handles this at three layers:

- **Actor isolation** — `CppBridge.LLM`, `.STT`, `.TTS`, `.VAD`, `.VLM`, `.VoiceAgent` are Swift `actor` types. `VoiceAgent.getHandle()` is `async throws` because it awaits four other actors.
- **`OSAllocatedUnfairLock`** — all non-actor shared state. `NSLock` is forbidden.
- **`@convention(c)` trampolines** — streaming callbacks are pure free functions. Context is threaded via `Unmanaged.passRetained` / `.fromOpaque` / `.takeUnretainedValue`.
- **Async-to-sync bridging** — `DispatchSemaphore` or `DispatchGroup.wait()`.
- **`AsyncStream` continuations** — `continuation.yield(_:)` is safe from any thread.

---

## §14 Conventions & Idioms

### §14.1 Naming

**`RA*` prefix for proto typealiases.** Every proto-generated Swift type keeps its `RA` prefix verbatim. Public extensions then declare short typealiases that strip it. Examples in `Public/Extensions/Models/ModelTypes.swift:36-41`:

```swift
public typealias ModelSource = RAModelSource
public typealias ModelFormat = RAModelFormat
public typealias InferenceFramework = RAInferenceFramework
```

`Public/Configuration/SDKEnvironment.swift:20` declares `public typealias SDKEnvironment = RASDKEnvironment`.

**`CppBridge` as the bridge namespace.** The bridge is a `public enum CppBridge` declared at `Foundation/Bridge/CppBridge.swift:55`. All 26 domain extensions live in `Foundation/Bridge/Extensions/CppBridge+<Domain>.swift` files.

**`SDK*` for SDK-public abstractions.** Core cross-cutting SDK types are named with the `SDK` prefix: `SDKEnvironment`, `SDKException`, `SDKLogger`, `SDKConstants`. These are the hand-written (non-generated) public types; `RA*` types are codegen-produced.

**`+CppBridge` suffix for C-bridge extensions on proto types.** Files that add C-ABI bridge methods to proto-generated types use `<ProtoType>+CppBridge.swift`: `RALLMTypes+CppBridge.swift`, `RASTTTypes+CppBridge.swift`, `RATTSTypes+CppBridge.swift`, `RAVADTypes+CppBridge.swift`, `ModelTypes+CppBridge.swift`.

**`+Helpers` suffix for proto convenience extensions.** Files in `Public/Extensions/` that add Swift-friendly computed properties and factory methods to proto types are named `<ProtoType>+Helpers.swift`: `RAVLMImage+Helpers.swift`, `StorageProto+Helpers.swift`, `RAGProto+Helpers.swift`, `StructuredOutputProto+Helpers.swift`, `EmbeddingsProto+Helpers.swift`, etc.

**`RunAnywhere+<Topic>` for public capability extensions.** All public SDK API is delivered as `public extension RunAnywhere` blocks in `Public/Extensions/<Domain>/RunAnywhere+<Topic>.swift` files.

**File names match the contained type exactly** in PascalCase. `SDKException.swift` contains `struct SDKException`, etc.

### §14.2 Concurrency

**`actor` for any type holding mutable C handle state.** Every C++ component with a `rac_handle_t` is wrapped in a Swift `actor`:

- `CppBridge.LLM`, `.STT`, `.TTS`, `.VAD`, `.VLM`, `.VoiceAgent` actors
- `CppBridge.ModelRegistry`, `.Download`, `.Storage`, `.RAG`, `.LoraRegistry` actors
- `HTTPClientAdapter` actor
- `ComponentActor` (generic scaffold)

Private actors for internal state: `ToolRegistry` actor in `RunAnywhere+ToolCalling.swift:26`.

**`enum` for stateless namespaces.** `RunAnywhere`, `CppBridge`, `URLSessionHttpTransport`, `SDKConstants` — all `public enum`. This pattern prevents instantiation.

**`final class` for shared-state singletons.** `EventBus`, `KeychainManager`, `Logging` — all `public final class` with `@unchecked Sendable` and a `public static let shared`.

**`Sendable` conformance everywhere a type crosses actor boundaries.** `SDKException`, `LogEntry`, `LoggingConfiguration`, `LogLevel`. The `EventBus` and `Logging` singletons use `@unchecked Sendable` because they manage their own thread safety via `OSAllocatedUnfairLock`.

**`AsyncStream` for streaming events.** The fan-out pattern in `Adapters/HandleStreamAdapter.swift` delivers proto-deserialized events to multiple `AsyncStream` consumers.

**`OSAllocatedUnfairLock<T>` (Swift 6) for non-actor synchronization.** Used in `URLSessionHttpTransport`, `Logging.shared` state, `CppBridge` shared state. The project enforces this — `NSLock` is forbidden per AGENTS.md.

**`withCheckedThrowingContinuation` for async/await over C callbacks.** Used in `SystemTTSService`, `AudioPlaybackManager`, `AudioCaptureManager`, `HTTPClientAdapter`, `RunAnywhere+ToolCalling`.

**`DispatchSemaphore` / `DispatchGroup.wait()` for async-to-sync C ABI bridging.** Required because the C ABI is synchronous.

### §14.3 Error Model

**Single `SDKException` struct** declared at `Foundation/Errors/SDKException.swift:20`:

```swift
public struct SDKException: Error, LocalizedError, Sendable, CustomStringConvertible
```

**Proto-backed.** Wraps the generated `RASDKError` (from `Generated/errors.pb.swift`) with `RAErrorCode` and `RAErrorCategory` fields. The `cAbiCode` field round-trips the C ABI's `rac_result_t` convention (positive proto code ↔ negative C result).

**Stack trace capture at construction.** `self.stackTrace = Thread.callStackSymbols` is called in both `init` overloads.

**Named static factory methods.** `.modelNotFound(_:)`, `.notInitialized(_:)`, `.invalidConfiguration(_:)`, `.validationFailed(_:)`, `.cancelled(_:)`, `.notImplemented(_:)`, `.timeout(_:)`, `.networkError(_:)`. Additional category-specific factories via `SDKException.make(code:message:category:underlying:shouldLog:)`.

**`from(_:)` for arbitrary-error wrapping.** `SDKException.from(_ error: any Error, category:)` first checks if the error is already an `SDKException` (returns unchanged), then delegates `NSURLErrorDomain` codes to `fromURLError(_:category:)`, otherwise wraps as `.unknown`.

**`RAErrorCode.isExpected` classification.** Returns `true` for `.cancelled` and `.streamCancelled` only. The `make(code:...:shouldLog:)` factory checks `!code.isExpected` to suppress logging for expected cancellations.

**`RASDKError+Helpers.swift` companion.** The proto value type itself gains factory methods (`RASDKError.make(...)`) and a C-ABI mapper `RASDKError.from(rcResult:)` that delegates to `rac_result_to_proto_error`.

### §14.4 Logging

**`SDKLogger` struct.** `public struct SDKLogger: Sendable` carrying a `category: String`. Methods: `debug(_:metadata:)` (`@inlinable`, no-ops outside `DEBUG`), `info`, `warning`, `error`, `fault`, `logError(_:additionalInfo:file:line:function:)`.

**Pre-instantiated convenience loggers.** `SDKLogger.shared` (category "RunAnywhere"), `.llm`, `.stt`, `.tts`, `.download`, `.models`. Per-file loggers are created as `private static let logger = SDKLogger(category: "...")`.

**`Logging.shared` as the central routing service.** `final class Logging` routes entries to `[LogDestination]` instances. The `LogDestination` protocol defines `write(_ entry: LogEntry)` and `flush()`.

**`os_log` backing.** `Logging` prints to console via `print(output)` when `config.enableLocalLogging` is true.

**Custom destinations registered explicitly.** `RunAnywhere.addLogDestination(_:)` appends a destination after deduplicating by identifier.

**`rac_log_metadata_should_redact` for sensitive metadata.** `Logging.shouldRedact(_:)` calls the C ABI to check redaction; the substring policy (keys like `key`, `secret`, `password`, `token`, `auth`, `credential`) lives in C++.

**Category convention.** Per-file loggers use the file or class name as category. The `ComponentActor` sets `self.logger = SDKLogger(category: "CppBridge.\(vtable.component.label)")`.

### §14.5 Doc-Comment Convention

Triple-slash `///` is used for all public symbol documentation throughout the codebase. `SDKException.swift` documents every public property and method with `///`. `EventBus.swift:13-23` includes a multi-line usage example. Public extension methods have one-line summary comments. Factory shortcuts each have a one-line `/// Common shortcut: ...` doc.

---

## §15 Build & Deployment

### §15.1 Package.swift

The file at `sdk/runanywhere-swift/Package.swift` is the **local development manifest**. A second `Package.swift` exists at the repository root for external SPM consumers; that root-level file downloads XCFrameworks from GitHub releases. The local manifest references `Binaries/` directly.

**Platform block** (`Package.swift:23-26`): `.iOS(.v17)`, `.macOS(.v14)`.

**Products** (`Package.swift:27-47`):
- `RunAnywhere` — library bundling `RunAnywhere`, `LlamaCPPRuntime`, `ONNXRuntime` (full stack)
- `RunAnywhereCore` — only the `RunAnywhere` target (core, no backends)
- `RunAnywhereLlamaCPP` — `LlamaCPPRuntime` only
- `RunAnywhereONNX` — `ONNXRuntime` only

**External dependencies** (`Package.swift:48-57`):
- `swift-crypto` ≥ 3.0.0
- `Files` (JohnSundell) ≥ 4.3.0
- `DeviceKit` ≥ 5.6.0
- `swift-protobuf` ≥ 1.27.0

**Targets** (`Package.swift:58-234`):

| Target | Type | Path | Key dependencies |
|--------|------|------|-----------------|
| `CRACommons` | regular | `Sources/RunAnywhere/CRACommons` | `RACommonsBinary` |
| `LlamaCPPBackend` | regular | `Sources/LlamaCPPRuntime/include` | `CRACommons`, `RABackendLlamaCPPBinary` |
| `ONNXBackend` | regular | `Sources/ONNXRuntime/include` | `CRACommons`, `RABackendONNXBinary`, `RABackendSherpaBinary` |
| `RunAnywhere` | regular | `Sources/RunAnywhere` | Crypto, Files, DeviceKit, SwiftProtobuf, CRACommons, RACommonsBinary |
| `LlamaCPPRuntime` | regular | `Sources/LlamaCPPRuntime` | RunAnywhere, LlamaCPPBackend, RABackendLlamaCPPBinary |
| `ONNXRuntime` | regular | `Sources/ONNXRuntime` | RunAnywhere, ONNXBackend, RABackendONNXBinary, RABackendSherpaBinary |
| `RunAnywhereTests` | test | `Tests/RunAnywhereTests` | RunAnywhere |
| `RACommonsBinary` | binary | `Binaries/RACommons.xcframework` | — |
| `RABackendLlamaCPPBinary` | binary | `Binaries/RABackendLLAMACPP.xcframework` | — |
| `RABackendONNXBinary` | binary | `Binaries/RABackendONNX.xcframework` | — |
| `RABackendSherpaBinary` | binary | `Binaries/RABackendSherpa.xcframework` | — |

**Excluded files** (`Package.swift:120-139`): The `RunAnywhere` target excludes `CRACommons` (sibling target), `Generated/router.pb.swift`, `Generated/diffusion_options.pb.swift` (zero consumers in Swift SDK).

**linkerSettings** for `RunAnywhere` target (`Package.swift:144-151`): `-lc++`, `-lz`, `-lbz2`, `-framework CFNetwork`, `-framework Security`, `-framework SystemConfiguration`.

**linkerSettings** for `LlamaCPPRuntime` (`Package.swift:171-176`): `-lc++`, `-framework Accelerate`, `-framework Metal`, `-framework MetalKit`.

**linkerSettings** for `ONNXRuntime` (`Package.swift:197-203`): `-lc++`, `-framework Accelerate`, `-framework CoreML`, `-larchive`, `-lbz2`.

### §15.2 XCFramework structure

All five XCFrameworks live in `sdk/runanywhere-swift/Binaries/` (git-ignored):

| XCFramework | Slices | Disk size |
|-------------|--------|-----------|
| `RACommons.xcframework` | ios-arm64, ios-arm64-simulator, macos-arm64 | 56M |
| `RABackendLLAMACPP.xcframework` | ios-arm64, ios-arm64-simulator | 34M |
| `RABackendONNX.xcframework` | ios-arm64, ios-arm64-simulator | 60M |
| `RABackendSherpa.xcframework` | ios-arm64, ios-arm64-simulator | 31M |

`RACommons` is the only framework with a macOS slice. Each xcframework is a static archive (`.a`) with a `Headers/` directory per slice.

### §15.3 CRACommons module map

File: `Sources/RunAnywhere/CRACommons/include/module.modulemap`

```
module CRACommons {
    umbrella header "CRACommons.h"
    export *
    module * { export * }
    link framework "Accelerate"
}
```

The `include/` directory contains 97 `rac_*.h` headers. The `shim.c` file contains only a comment.

### §15.4 Static plugins (RAC_STATIC_PLUGINS=ON)

iOS does not permit `dlopen` for code not embedded at app launch. All backends are statically linked into the app binary via `.binaryTarget` + regular target dependencies. Backend registration happens by calling a single C function per backend (e.g., `rac_backend_llamacpp_register()`). The `-force_load` linker behavior is achieved through the `RABackendLlamaCPPBinary` binary target dependency. Backend registration is guarded by a static `isRegistered` bool per module.

### §15.5 Tests

Test target: `RunAnywhereTests` at `Tests/RunAnywhereTests/` (`Package.swift:209-213`).

Six test files:
- `AudioCaptureManagerTests.swift`
- `LoRAProtoSurfaceTests.swift`
- `ModelImportProtoSurfaceTests.swift`
- `ModelLifecycleResolvedArtifactsTests.swift`
- `StructuredOutputProtoSurfaceTests.swift`
- `ToolCallingProtoHelpersTests.swift`

**How to run:**
```bash
swift test
xcodebuild test -scheme RunAnywhere -destination 'platform=iOS Simulator,name=iPhone 16 Pro' CODE_SIGNING_REQUIRED=NO
```

Tests require the `Binaries/` XCFrameworks (built locally via `sdk/runanywhere-swift/scripts/build-core-xcframework.sh` or copied from CI artifacts).

---

## §16 File-by-File Inventory

### Hand-Written Files (95 files, 16,918 LOC)

| Path (relative to `Sources/RunAnywhere/`) | LOC |
|---|---:|
| Foundation/Bridge/Extensions/CppBridge+PlatformAdapter.swift | 733 |
| HttpTransport/URLSessionHttpTransport.swift | 685 |
| Features/STT/Services/AudioCaptureManager.swift | 573 |
| Foundation/Bridge/Extensions/CppBridge+ModelRegistry.swift | 515 |
| Public/Extensions/Models/ModelTypes+Artifacts.swift | 473 |
| Public/Extensions/LLM/RunAnywhere+ToolCalling.swift | 442 |
| Foundation/Bridge/Extensions/CppBridge+ModalityProtoABI.swift | 424 |
| Infrastructure/Logging/SDKLogger.swift | 416 |
| Public/RunAnywhere.swift | 403 |
| Adapters/HandleStreamAdapter.swift | 388 |
| Public/Extensions/Storage/RunAnywhere+Storage.swift | 379 |
| Foundation/Bridge/Extensions/CppBridge+Platform.swift | 367 |
| Foundation/Errors/SDKException.swift | 358 |
| Foundation/Bridge/HTTPClientAdapter.swift | 336 |
| Public/Extensions/Models/ModelTypes.swift | 331 |
| Infrastructure/Device/Models/Domain/DeviceInfo.swift | 305 |
| Foundation/Bridge/Extensions/CppBridge+Auth.swift | 274 |
| Foundation/Bridge/Extensions/CppBridge+State.swift | 273 |
| Foundation/Bridge/Extensions/CppBridge+Device.swift | 265 |
| Foundation/Bridge/Extensions/CppBridge+FileManager.swift | 263 |
| Foundation/Bridge/Extensions/CppBridge+Telemetry.swift | 260 |
| Features/TTS/Services/AudioPlaybackManager.swift | 260 |
| Foundation/Security/KeychainManager.swift | 251 |
| Features/LLM/System/SystemFoundationModelsService.swift | 249 |
| Public/Configuration/SDKEnvironment.swift | 239 |
| Public/Extensions/RAG/RunAnywhere+RAG.swift | 237 |
| Foundation/Bridge/Extensions/CppBridge+Storage.swift | 226 |
| Public/Extensions/LLM/RunAnywhere+LoRA.swift | 211 |
| Foundation/Bridge/Extensions/CppBridge+Environment.swift | 210 |
| Foundation/Bridge/CppBridge.swift | 203 |
| Foundation/Bridge/ComponentActor.swift | 203 |
| Foundation/Bridge/Extensions/CppBridge+Download.swift | 192 |
| Public/Extensions/Solutions/RunAnywhere+Solutions.swift | 188 |
| Public/Extensions/VLM/RAVLMImage+Helpers.swift | 186 |
| Foundation/Bridge/Extensions/CppBridge+ModelPaths.swift | 185 |
| Foundation/Bridge/Extensions/CppBridge+NativeProtoABI.swift | 178 |
| Features/TTS/System/SystemTTSService.swift | 178 |
| Public/Extensions/LLM/ToolCallingTypes.swift | 156 |
| Public/Extensions/TTS/RunAnywhere+TTS.swift | 154 |
| Public/Extensions/Storage/StorageProto+Helpers.swift | 152 |
| Infrastructure/Download/Models/Output/DownloadProgress.swift | 152 |
| Public/Extensions/VoiceAgent/RunAnywhere+VoiceAgent.swift | 151 |
| Foundation/Bridge/Extensions/CppBridge+SDKEvents.swift | 150 |
| Foundation/Bridge/Extensions/CppBridge+VAD.swift | 148 |
| Foundation/Bridge/Extensions/ModelTypes+CppBridge.swift | 144 |
| Public/Extensions/RunAnywhere+PluginLoader.swift | 142 |
| Foundation/Bridge/ComponentVTable.swift | 137 |
| Foundation/Bridge/Extensions/CppBridge+SdkInit.swift | 135 |
| Foundation/Bridge/Extensions/CppBridge+ModelLifecycle.swift | 133 |
| Foundation/Bridge/Extensions/RALLMTypes+CppBridge.swift | 117 |
| Foundation/Bridge/Extensions/CppBridge+STT.swift | 112 |
| Foundation/Bridge/Extensions/CppBridge+VLM.swift | 102 |
| Public/Extensions/LLM/StructuredOutputProto+Helpers.swift | 98 |
| Foundation/Errors/RASDKError+Helpers.swift | 97 |
| Foundation/Bridge/Extensions/RASTTTypes+CppBridge.swift | 97 |
| Features/LLM/System/SystemFoundationModelsModule.swift | 97 |
| Public/Extensions/LLM/RunAnywhere+StructuredOutput.swift | 94 |
| Public/Events/EventBus.swift | 90 |
| Foundation/Bridge/Extensions/CppBridge+VoiceAgent.swift | 90 |
| Public/Extensions/STT/RunAnywhere+STT.swift | 89 |
| Public/Extensions/VLM/RunAnywhere+VisionLanguage.swift | 87 |
| Foundation/Bridge/Extensions/CppBridge+StructuredOutput.swift | 84 |
| Foundation/Bridge/Extensions/CppBridge+ToolCalling.swift | 83 |
| Public/Extensions/RAG/RAGProto+Helpers.swift | 80 |
| Foundation/Bridge/Extensions/CppBridge+TTS.swift | 77 |
| Public/Extensions/LLM/RunAnywhere+TextGeneration.swift | 76 |
| Foundation/Bridge/Extensions/CppBridge+LLM.swift | 74 |
| Foundation/Bridge/Extensions/CppBridge+Hardware.swift | 74 |
| Foundation/Bridge/Extensions/RATTSTypes+CppBridge.swift | 69 |
| Public/Extensions/VAD/RunAnywhere+VAD.swift | 68 |
| Foundation/Bridge/Extensions/CppBridge+Strategy.swift | 67 |
| Adapters/VoiceAgentStreamAdapter.swift | 59 |
| Public/Extensions/Models/RunAnywhere+ModelLifecycle.swift | 58 |
| Adapters/LLMStreamAdapter.swift | 58 |
| Public/Extensions/STT/RASTTConfiguration+Helpers.swift | 57 |
| Public/Extensions/RunAnywhere+Logging.swift | 57 |
| Foundation/Bridge/Extensions/CppBridge+RAG.swift | 56 |
| Public/Extensions/RunAnywhere+Hardware.swift | 52 |
| Public/Extensions/VoiceAgent/VoiceAgentTypes.swift | 51 |
| Foundation/Bridge/Extensions/CppBridge+LoraRegistry.swift | 50 |
| Foundation/Bridge/Extensions/CppBridge+HTTP.swift | 49 |
| Foundation/Bridge/Extensions/RAChatMessage+Extensions.swift | 48 |
| Public/Extensions/Events/RunAnywhere+SDKEvents.swift | 46 |
| Public/Extensions/VAD/RAVADConfiguration+Helpers.swift | 44 |
| Public/Extensions/Models/RunAnywhere+ModelRegistry.swift | 44 |
| Public/Extensions/LLM/EmbeddingsProto+Helpers.swift | 41 |
| Foundation/Bridge/Extensions/RAAudioFormat+Extensions.swift | 38 |
| Public/Extensions/TTS/RATTSConfiguration+Helpers.swift | 37 |
| Foundation/Constants/SDKConstants.swift | 37 |
| Infrastructure/FileManagement/Utilities/FileOperationsUtilities.swift | 31 |
| Foundation/Core/RASDKComponent+DisplayName.swift | 27 |
| Foundation/Bridge/Extensions/RAVADTypes+CppBridge.swift | 27 |

### Generated Files (31 files, ~47,432 LOC total)

All files in `Generated/` are produced by `idl/codegen/generate_all.sh` and must not be edited by hand.

| Generated File | LOC | Notes |
|---|---:|---|
| sdk_events.pb.swift | 6,896 | Largest generated file |
| model_types.pb.swift | 5,305 | Model type protos |
| tool_calling.pb.swift | 2,727 | Tool-calling schema |
| voice_events.pb.swift | 2,578 | Voice agent events |
| structured_output.pb.swift | 2,307 | Structured output |
| diffusion_options.pb.swift | 2,024 | Diffusion options |
| stt_options.pb.swift | 1,967 | STT options |
| vlm_options.pb.swift | 1,848 | VLM options |
| tts_options.pb.swift | 1,649 | TTS options |
| rag.pb.swift | 1,603 | RAG protos |
| ModalityProtoABI+Generated.swift | 832 | 36 methods across 12 modalities |
| RAConvenience.swift | 410 | wireString, defaults, validate |
| Remaining 19 `.pb.swift` files | ~13,336 | llm_service, errors, chat, router, pipeline, etc. |

### Top 20 Largest Hand-Written Files

| Rank | File | LOC |
|---:|---|---:|
| 1 | Foundation/Bridge/Extensions/CppBridge+PlatformAdapter.swift | 733 |
| 2 | HttpTransport/URLSessionHttpTransport.swift | 685 |
| 3 | Features/STT/Services/AudioCaptureManager.swift | 573 |
| 4 | Foundation/Bridge/Extensions/CppBridge+ModelRegistry.swift | 515 |
| 5 | Public/Extensions/Models/ModelTypes+Artifacts.swift | 473 |
| 6 | Public/Extensions/LLM/RunAnywhere+ToolCalling.swift | 442 |
| 7 | Foundation/Bridge/Extensions/CppBridge+ModalityProtoABI.swift | 424 |
| 8 | Infrastructure/Logging/SDKLogger.swift | 416 |
| 9 | Public/RunAnywhere.swift | 403 |
| 10 | Adapters/HandleStreamAdapter.swift | 388 |
| 11 | Public/Extensions/Storage/RunAnywhere+Storage.swift | 379 |
| 12 | Foundation/Bridge/Extensions/CppBridge+Platform.swift | 367 |
| 13 | Foundation/Errors/SDKException.swift | 358 |
| 14 | Foundation/Bridge/HTTPClientAdapter.swift | 336 |
| 15 | Public/Extensions/Models/ModelTypes.swift | 331 |
| 16 | Infrastructure/Device/Models/Domain/DeviceInfo.swift | 305 |
| 17 | Foundation/Bridge/Extensions/CppBridge+Auth.swift | 274 |
| 18 | Foundation/Bridge/Extensions/CppBridge+State.swift | 273 |
| 19 | Foundation/Bridge/Extensions/CppBridge+Device.swift | 265 |
| 20 | Foundation/Bridge/Extensions/CppBridge+FileManager.swift | 263 |

---

## Appendix A — Glossary

- **`rac_handle_t`** — Opaque pointer to a C++ component instance. Allocated and freed by `rac_*_component_create`/`_destroy`. Per-modality variants: `rac_voice_agent_handle_t`, `rac_solution_handle_t`, `rac_model_registry_handle_t`, `rac_lora_registry_handle_t`, `rac_storage_analyzer_handle_t`.
- **`rac_*` symbol convention** — Every C function exported by `RACommons.xcframework` is prefixed `rac_<subsystem>_<verb>[_<modifier>]`. The naming is mechanical and exhaustively documented in `CRACommons/include/`.
- **`RAErrorCode`** — Proto-generated error code enum (in `errors.pb.swift`). Round-trips with C ABI `rac_result_t` via `cAbiCode` (positive proto ↔ negative C). Codes `.cancelled` / `.streamCancelled` are classified `isExpected`.
- **`RAC_API`** — Visibility macro in C headers that controls symbol export. All `RAC_API`-marked functions are present in `dlsym` lookups via `NativeProtoABI.load`.
- **`SDKException`** — Swift `struct` conforming to `Error, LocalizedError, Sendable, CustomStringConvertible`. Wraps `RASDKError` proto + Swift `underlying` error + `Thread.callStackSymbols`.
- **`EventBus`** — Singleton at `Public/Events/EventBus.swift`. Backed by Combine `PassthroughSubject<RASDKEvent, Never>`. Accessed via `RunAnywhere.events`.
- **`CppBridge.*`** — The `public enum CppBridge` namespace and its 38 extension slices in `Foundation/Bridge/Extensions/`. The single Swift↔C++ surface.
- **`ComponentActor`** — Generic Swift `actor` (`Foundation/Bridge/ComponentActor.swift`) that manages handle creation, `isLoaded`, `loadModel`, `unload`, `destroy` generically across LLM/STT/TTS/VAD/VLM.
- **`ComponentVTable`** — `public struct ComponentVTable: Sendable` (`Foundation/Bridge/ComponentVTable.swift`). 5 typed static instances (`.llm`, `.stt`, `.tts`, `.vad`, `.vlm`) wire each component's C function pointers.
- **`HandleStreamAdapter`** — Generic fan-out streaming adapter (`Adapters/HandleStreamAdapter.swift`). Multiplexes one C callback to many `AsyncStream` consumers.
- **`NativeProtoABI`** — Internal Swift `enum` (`CppBridge+NativeProtoABI.swift`) holding `load`, `require`, `withSerializedBytes`, `decode`, `free`, `invoke` helpers for the proto-byte ABI. All other slices call through this enum.
- **`RA*` typealias prefix** — Proto-generated Swift types keep their `RA` prefix. Public extensions then declare typealiases stripping it for the caller's convenience.
- **`RAC_STATIC_PLUGINS`** — CMake flag forcing static plugin registration on iOS/WASM. Combined with `-force_load` linker flags via `RAC_STATIC_PLUGIN_REGISTER(name)` macro.
- **`RAC_PLUGIN_API_VERSION`** — C macro currently `3u`. `rac_engine_vtable_t.metadata.abi_version` must equal this; mismatch causes `RAC_ERROR_ABI_VERSION_MISMATCH`.
- **Proto-byte buffer** — A `rac_proto_buffer_t` filled by C++ with serialized proto bytes. Swift wraps in `Data`, deserializes to the response type, then frees via `rac_proto_buffer_free` (via `NativeProtoABI.free`).
- **Two-phase init** — Swift SDK contract: synchronous Phase 1 (`rac_sdk_init_phase1_proto`) registers platform services and validates inputs; async Phase 2 (`rac_sdk_init_phase2_proto`) performs HTTP/auth/device registration. Phase 2 failures are non-fatal.
- **Platform adapter IoC** — `rac_platform_adapter_t` flat C struct of function pointers. Swift populates this struct; C++ calls into it for all platform services (file I/O, Keychain, logging, clock, memory, HTTP download).
- **Streaming fan-out** — `HandleStreamAdapter` pattern: one C callback per handle, multiplexed to many Swift `AsyncStream` consumers via UUID-keyed continuations.

---

## Appendix B — Cross-SDK Alignment Quick Reference

| Swift concept | Kotlin equivalent | Flutter equivalent | React Native equivalent | Web equivalent |
|---|---|---|---|---|
| **Entry point** | `enum RunAnywhere` (namespace) | `object RunAnywhere` (KMP common) | `RunAnywhereSDK.instance` (singleton) | `RunAnywhere` object (Nitro hybrid) | `RunAnywhere` object (module export) |
| **Two-phase init** | `initialize()` + `completeServicesInitialization()` | Same | Same | Same | Same |
| **Bridge namespace** | `CppBridge` enum + extensions | `CppBridge` object + extensions (commonMain) | `DartBridge` + `DartBridge*.dart` | `HybridRunAnywhereCore` (Nitro) | `LlamaCppBridge` + `SherpaONNXBridge` |
| **Modality actors** | Swift `actor` per component (`.LLM`, `.STT`, etc.) | KMP `class` with `Mutex`-guarded handle | Dart isolate-safe wrappers around FFI handles | Nitro `HybridObject` per modality | TypeScript class per modality |
| **Streaming primitive** | `AsyncStream<Event>` | `Flow<Event>` | `Stream<Event>` (via `StreamController.broadcast`) | `AsyncIterable<Event>` (manual iteration; Hermes does not support `for await...of` w/ NitroModules) | `AsyncIterable<Event>` |
| **Error type** | `SDKException` (proto-backed struct) | `SDKException` (proto-backed class) | `SDKException` (proto-backed class) | `SDKException` (proto-backed class) | `SDKException` (proto-backed class) |
| **Event bus** | `EventBus` (Combine `PassthroughSubject`) | `EventBus` (Kotlin `SharedFlow`) | `EventBus` (custom pub/sub via `dart:async broadcast StreamController`) | `EventBus` (RN `NativeEventEmitter`) | `EventBus` (custom pub/sub) |
| **Secure storage** | Keychain (Security.framework) | EncryptedSharedPrefs (Android) / AES-encrypted files (JVM) | flutter_secure_storage + cache | Keychain (iOS) / EncryptedSharedPrefs (Android) | `localStorage` |
| **HTTP transport** | URLSession (`URLSessionHttpTransport` enum) | OkHttp (Android/JVM) | OkHttp (Android) / URLSession (iOS) | OkHttp (Android) / URLSession (iOS) | `emscripten_fetch` / `fetch()` |
| **Platform adapter IoC** | `rac_platform_adapter_t` populated in `CppBridge+PlatformAdapter.swift` | Same struct populated via JNI in jvmAndroidMain | Same struct populated via Dart FFI | Same struct populated via NitroModules C++ bridge | Same struct populated in JS callbacks via emscripten |
| **FFI mechanism** | XCFramework + `module.modulemap` (clang module) | JNI (`librunanywhere_jni.so`) | Dart FFI (`ffi` package) | NitroModules (JSI HybridObject) | Emscripten WASM + JS glue |
| **Concurrency for non-actor state** | `OSAllocatedUnfairLock` (Swift 6) | `Mutex` (kotlinx-coroutines) | `Lock` (`package:sync`) | JS single-thread (no locks needed) | JS single-thread (no locks needed) |
| **Async-to-sync C bridge** | `DispatchSemaphore` / `DispatchGroup.wait()` | `runBlocking` + `CountDownLatch` | Future-based; await via `Completer` | `withCheckedThrowingContinuation` analog | Promise-based; awaited via `await` |
| **Codegen languages** | protoc-gen-swift + `RAConvenience.swift` + `ModalityProtoABI+Generated.swift` | Wire Kotlin + Kotlin convenience codegen | protoc-gen-dart + Dart convenience codegen | ts-proto + nitrogen for HybridObjects | ts-proto + TS codegen |
| **Plugin static linking** | `-force_load` per `.binaryTarget` | `--whole-archive` via Gradle | `-all_load` via Flutter podspec | Manually linked in app target | Static linking forced (no `dlopen` in WASM) |

---
