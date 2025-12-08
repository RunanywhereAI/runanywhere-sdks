# Foundation Module - Complete File Analysis

**Analysis Date:** 2025-12-07
**Module Path:** `/Sources/RunAnywhere/Foundation/`
**Total Files:** 29 Swift files

## Overview

The Foundation module provides core infrastructure services for the RunAnywhere Swift SDK. This module contains essential cross-cutting concerns including analytics, logging, dependency injection, device identity, error handling, file operations, and security.

### File Count by Subdirectory

- **Analytics/** (4 files) - Event tracking, telemetry, and analytics queuing
- **Concurrency/** (1 file) - Thread-safe locking primitives
- **Configuration/** (1 file) - SDK configuration constants
- **Constants/** (3 files) - Build tokens, error codes, SDK constants
- **Context/** (1 file) - Thread-scoped state management
- **DependencyInjection/** (3 files) - Service container, registry, lifecycle
- **DeviceIdentity/** (2 files) - Device management and persistent identity
- **ErrorTypes/** (3 files) - Unified error handling types
- **FileOperations/** (2 files) - Archive utilities and model path management
- **Logging/** (8 files) - Comprehensive logging infrastructure
- **Security/** (1 file) - Keychain-based secure storage

---

## Analytics Subdirectory (4 files)

### `Analytics/AnalyticsQueueManager.swift`

**Role / Responsibility**
- Central queue manager for all analytics events with batching and retry logic
- Handles automatic flushing based on batch size (50 events) and time interval (30 seconds)
- Converts analytics events to telemetry data and syncs to backend
- Uses Mirror reflection to extract event properties dynamically

**Key Types**
- `AnalyticsQueueManager` (actor) – Singleton actor managing the analytics event queue with automatic batching

**Key Public APIs**
- `func initialize(telemetryRepository: TelemetryRepositoryImpl)` – Initialize with repository for backend sync
- `func enqueue(_ event: any AnalyticsEvent) async` – Add single event to queue
- `func enqueueBatch(_ events: [any AnalyticsEvent]) async` – Add multiple events at once
- `func flush() async` – Force flush all pending events immediately

**Important Internal Logic**
- Uses Swift Mirror reflection to extract properties from `AnalyticsEventData` structs
- Converts camelCase property names to snake_case for backend compatibility
- Implements exponential backoff retry logic (3 attempts) with 2^n second delays
- Stores events locally first, then syncs to backend via remote data source

**Dependencies**
- Internal: `TelemetryRepositoryImpl`, `TelemetryData`, `TelemetryEventType`, `AnalyticsEvent`, `SDKLogger`
- External: Foundation

**Usage & Callers**
- Used by analytics services: `GenerationAnalyticsService`, `STTAnalyticsService`, `VoiceAnalyticsService`, `TTSAnalyticsService`
- Initialized in `ServiceContainer.bootstrap()` with telemetry repository

**Potential Issues / Smells**
- Heavy use of reflection (Mirror) may have performance implications for high-frequency events
- The `extractValue()` method handles many type conversions manually - could be simplified with Codable
- Timer-based flush runs forever in background (no explicit cleanup except deinit)

**Unused / Dead Code**
- None identified

---

### `Analytics/Models/AnalyticsContext.swift`

**Role / Responsibility**
- Defines strongly typed context categories for analytics error tracking
- Prevents string-based context mistakes across the SDK

**Key Types**
- `AnalyticsContext` (enum) – 8 predefined context types for error classification

**Key Public APIs**
- All cases: `.transcription`, `.pipelineProcessing`, `.initialization`, `.componentExecution`, `.modelLoading`, `.audioProcessing`, `.textGeneration`, `.speakerDiarization`

**Important Internal Logic**
- Simple enum with String raw values using snake_case convention
- CaseIterable for iteration support

**Dependencies**
- External: Foundation only

**Usage & Callers**
- Used in `ErrorEventData` struct for categorizing errors
- Referenced throughout analytics event creation

**Potential Issues / Smells**
- None - well-designed simple enum

**Unused / Dead Code**
- None identified

---

### `Analytics/Models/AnalyticsEventData.swift`

**Role / Responsibility**
- Defines all structured event data models for strongly typed analytics
- Provides type-safe data structures for voice, STT, generation, TTS, and monitoring events
- Ensures consistency in telemetry data sent to backend

**Key Types**
- `AnalyticsEventData` (protocol) – Base protocol requiring Codable and Sendable
- **Voice Events:** `PipelineCreationData`, `PipelineStartedData`, `PipelineCompletionData`, `StageExecutionData`, `VoiceTranscriptionData`, `TranscriptionStartData`
- **STT Events:** `STTTranscriptionData`, `FinalTranscriptData`, `PartialTranscriptData`, `SpeakerDetectionData`, `SpeakerChangeData`, `LanguageDetectionData`
- **Generation Events:** `GenerationStartData`, `GenerationCompletionData`, `StreamingUpdateData`, `FirstTokenData`, `ModelLoadingData`, `ModelUnloadingData`
- **TTS Events:** `TTSSynthesisTelemetryData`
- **STT Telemetry:** `STTTranscriptionTelemetryData`
- **Monitoring Events:** `ResourceUsageData`, `PerformanceMetricsData`, `CPUThresholdData`, `DiskSpaceWarningData`, `NetworkLatencyData`, `MemoryWarningData`, `SessionStartedData`, `SessionEndedData`
- **Error Events:** `ErrorEventData`

**Key Public APIs**
- All structs have public initializers with comprehensive parameter lists
- `GenerationCompletionData` has both legacy and full telemetry initializers for backward compatibility

**Important Internal Logic**
- Comprehensive telemetry fields include device info, model info, performance metrics
- Uses optional fields extensively to support partial data scenarios
- Timestamps are computed automatically in some structs (e.g., `ErrorEventData`)

**Dependencies**
- Internal: `AnalyticsContext`
- External: Foundation

**Usage & Callers**
- Created throughout the SDK when analytics events occur
- Consumed by `AnalyticsQueueManager` for conversion to `TelemetryData`

**Potential Issues / Smells**
- `GenerationCompletionData` has 26 properties - very large struct
- Two initializers for backward compatibility adds maintenance burden
- Some structs auto-compute timestamps which could lead to inconsistent time references

**Unused / Dead Code**
- Legacy `GenerationCompletionData` initializer may be unused if all callers use new format

---

### `Analytics/TelemetryDeviceInfo.swift`

**Role / Responsibility**
- Provides device information helper for telemetry events
- Extracts clean OS version from full version strings
- Platform-aware device model retrieval

**Key Types**
- `TelemetryDeviceInfo` (struct) – Sendable struct containing device, osVersion, platform

**Key Public APIs**
- `static var current: TelemetryDeviceInfo` – Get current device info for telemetry

**Important Internal Logic**
- Uses regex to extract clean OS version (e.g., "17.2" from "Version 17.2 (Build 21C52)")
- Regex is cached as static property for performance
- Platform detection via conditional compilation directives (#if os(iOS), etc.)

**Dependencies**
- Internal: `DeviceInfo.current`
- External: Foundation

**Usage & Callers**
- Used when creating telemetry events with device context
- Referenced in generation, STT, and TTS telemetry data

**Potential Issues / Smells**
- Private initializer prevents external instantiation (good for singleton pattern)
- Regex compilation happens once at static initialization (good performance)

**Unused / Dead Code**
- None identified

---

## Concurrency Subdirectory (1 file)

### `Concurrency/UnfairLock.swift`

**Role / Responsibility**
- Provides Swift 6-safe unfair lock primitives for synchronization
- Replaces deprecated NSLock with os_unfair_lock
- Offers both stateless and stateful lock variants

**Key Types**
- `UnfairLock` (class) – Basic unfair lock with closure-based critical sections
- `UnfairLockWithState<State>` (class) – Lock protecting a specific state value with read/write access

**Key Public APIs**
- `func withLock<Result>(_ body: () throws -> Result) rethrows -> Result` – Execute closure with lock held
- `func withLock<Result>(_ body: (State) throws -> Result) rethrows -> Result` – Read-only state access
- `func withLock<Result>(_ body: (inout State) throws -> Result) rethrows -> Result` – Mutable state access

**Important Internal Logic**
- Uses manual memory management (allocate/deallocate) for os_unfair_lock_t
- Marked `@unchecked Sendable` since os_unfair_lock is a C type
- Proper deinit cleanup to prevent memory leaks

**Dependencies**
- External: Foundation (os_unfair_lock)

**Usage & Callers**
- Used extensively: `RunAnywhereScope`, `DeviceManager`, `LoggingManager`, `AdapterRegistry`
- Critical for thread-safety across the SDK

**Potential Issues / Smells**
- Manual memory management requires careful testing
- `@unchecked Sendable` bypasses Swift's safety checks - must be verified correct

**Unused / Dead Code**
- None - both variants actively used

---

## Configuration Subdirectory (1 file)

### `Configuration/RunAnywhereConstants.swift`

**Role / Responsibility**
- Central configuration for SDK environment-specific settings
- Loads configuration from environment variables, JSON files, or defaults
- Provides API URLs and feature flags

**Key Types**
- `RunAnywhereConstants` (enum) – Container for static configuration
- `APIURLs` (struct) – Environment-specific API endpoints
- `Features` (struct) – Feature flag configuration

**Key Public APIs**
- `static let apiURLs: APIURLs` – API URLs for dev/staging/production
- `static let features: Features` – Feature flags (telemetry, debug logging)
- `var current: String` – Returns appropriate URL for build configuration (#if DEBUG)

**Important Internal Logic**
- Three-tier configuration loading: environment variables → JSON file → defaults
- JSON file loaded from main bundle: "RunAnywhereConfig.json"
- Supports nested keys with dot notation (e.g., "api.production")
- Environment variable format: `RUNANYWHERE_{KEY_UPPERCASED}` (dots → underscores)

**Dependencies**
- External: Foundation

**Usage & Callers**
- Referenced by `SDKConstants.DatabaseDefaults.apiBaseURL`
- Used for environment-specific API base URLs

**Potential Issues / Smells**
- Default URLs are placeholder "demo-api.example.com" - must be configured
- JSON file is optional (returns nil if not found) - silent failure
- Environment variables checked via ProcessInfo (testable but less discoverable)

**Unused / Dead Code**
- None identified

---

## Constants Subdirectory (3 files)

### `Constants/BuildToken.swift`

**Role / Responsibility**
- Contains development mode build token for device registration
- Provides debug token for local testing without production credentials
- Security-conscious with clear warnings and .gitignore documentation

**Key Types**
- `BuildToken` (enum) – Container for static token value

**Key Public APIs**
- `static let token: String` – Development mode token ("runanywhere_debug_token")

**Important Internal Logic**
- Extensive documentation warns this is for development only
- Token used when SDK is in `.development` mode
- Backend validates via `POST /api/v1/devices/register/dev`

**Dependencies**
- External: Foundation

**Usage & Callers**
- Used during device registration in development mode
- Referenced by authentication/registration services

**Potential Issues / Smells**
- Contains hardcoded token (acceptable for debug/dev)
- File should be in .gitignore (documented in comments)
- Production builds should use release tag tokens instead

**Unused / Dead Code**
- None - active in development mode

---

### `Constants/ErrorCodes.swift`

**Role / Responsibility**
- Defines SDK error codes with user-friendly messages
- Organized into logical categories (general, model, network, storage, memory, hardware, auth, generation)
- Provides consistent error reporting across SDK

**Key Types**
- `ErrorCode` (enum) – 40+ error codes organized by category

**Key Public APIs**
- All error cases with Int raw values (1000-1799 range)
- `var message: String` – User-friendly error message for each code

**Important Internal Logic**
- Error codes grouped by hundred ranges (1000s = general, 1100s = model, etc.)
- Each code maps to descriptive message via computed property
- Extensible design allows adding new categories

**Dependencies**
- External: Foundation

**Usage & Callers**
- Used throughout SDK for error reporting
- Referenced in error handling and telemetry

**Potential Issues / Smells**
- No automated tests to ensure all codes have messages
- Could benefit from localization support for messages

**Unused / Dead Code**
- Some codes may be defined but never thrown (requires usage audit)

---

### `Constants/SDKConstants.swift`

**Role / Responsibility**
- Defines SDK-wide constants for configuration, defaults, and limits
- Comprehensive set of default values organized by functional area
- Single source of truth for SDK behavior parameters

**Key Types**
- `SDKConstants` (enum) – Main container
- **Nested Enums:** `ConfigurationDefaults`, `DatabaseDefaults`, `TelemetryDefaults`, `ModelDefaults`, `PrivacyDefaults`, `AnalyticsDefaults`, `StorageDefaults`, `RoutingDefaults`, `ExecutionTargets`, `SessionTypes`, `PlatformDefaults`

**Key Public APIs**
- `static let version = "1.0.0"` – SDK version
- `static let platform: String` – Platform identifier (iOS/macOS/tvOS/watchOS)
- `static let defaultAPITimeout: TimeInterval = 60` – Network timeout
- `ConfigurationDefaults.cloudRoutingEnabled = false` – Force local-only execution
- `ConfigurationDefaults.analyticsEnabled = true` – Enable analytics

**Important Internal Logic**
- Platform detection via conditional compilation
- Forces device-only routing (no cloud routing)
- Hard-codes analytics to be fully enabled
- References `RunAnywhereConstants.apiURLs.current` for base URL

**Dependencies**
- Internal: `RunAnywhereConstants`, `RoutingPolicy`, `ExecutionTargets`
- External: Foundation

**Usage & Callers**
- Referenced throughout SDK for default values
- Critical for initialization and configuration

**Potential Issues / Smells**
- Hard-coded `cloudRoutingEnabled = false` conflicts with comment about intelligent routing
- Many nested enums could be overwhelming - consider splitting into multiple files
- Some values duplicated (e.g., sdkVersion appears in multiple places)

**Unused / Dead Code**
- Comment mentions `RoutingPolicy` moved to different file - potential dead reference

---

## Context Subdirectory (1 file)

### `Context/RunAnywhereScope.swift`

**Role / Responsibility**
- Manages thread-scoped state for RunAnywhere SDK (following Sentry's pattern)
- Provides thread-isolated device ID caching and registration state
- Ensures thread-safe access to per-thread scope data

**Key Types**
- `RunAnywhereScope` (class) – Thread-isolated scope container

**Key Public APIs**
- `static func getCurrentScope() -> RunAnywhereScope` – Get/create scope for current thread
- `func getCachedDeviceId() -> String?` – Get cached device ID for this scope
- `func setCachedDeviceId(_ deviceId: String?)` – Cache device ID in this scope
- `func isRegistering() -> Bool` – Check if registration in progress
- `func setRegistering(_ registering: Bool)` – Set registration state

**Important Internal Logic**
- Uses `NSMapTable<AnyObject, RunAnywhereScope>.strongToWeakObjects()` for thread → scope mapping
- Thread.current used as map key for thread isolation
- UnfairLock protects both global map and per-scope state
- Weak references prevent memory leaks when threads terminate

**Dependencies**
- Internal: `UnfairLock`
- External: Foundation

**Usage & Callers**
- Extension on `RunAnywhere` provides `getCurrentScope()` helper
- Used for thread-safe device ID management

**Potential Issues / Smells**
- NSMapTable not strongly typed - relies on AnyObject keys
- Thread.current as key may have surprising behavior with GCD thread pools
- Scope per thread may not align well with Swift's structured concurrency (actors/tasks)

**Unused / Dead Code**
- Debug properties `identifier` and `threadInfo` appear unused
- `clearAllScopes()` only for testing - document this

---

## DependencyInjection Subdirectory (3 files)

### `DependencyInjection/AdapterRegistry.swift`

**Role / Responsibility**
- Single registry for all framework adapters (text and voice)
- Manages adapter registration, retrieval, and discovery
- Provides fallback mechanisms for finding capable adapters

**Key Types**
- `AdapterRegistry` (class) – Central registry for framework adapters
- Internal: Uses `UnifiedServiceRegistry` for new architecture

**Key Public APIs**
- `func register(_ adapter: UnifiedFrameworkAdapter, priority: Int = 100)` – Register adapter with priority
- `func getAdapter(for framework: LLMFramework) -> UnifiedFrameworkAdapter?` – Get specific adapter
- `func findBestAdapter(for model: ModelInfo, modality: FrameworkModality?) async -> UnifiedFrameworkAdapter?` – Find best adapter for model
- `func getFrameworks(for modality: FrameworkModality) -> [LLMFramework]` – Get frameworks supporting modality
- `func getFrameworkAvailability() -> [FrameworkAvailability]` – Get detailed availability info

**Important Internal Logic**
- Maintains both new (UnifiedServiceRegistry) and legacy (dictionary) storage for backward compatibility
- Registration calls `adapter.onRegistration()` and registers provided models
- Uses concurrent dispatch queue for thread-safe access
- Priority-based adapter selection (higher priority preferred)
- Modality determination from model info (speech vs text)

**Dependencies**
- Internal: `UnifiedServiceRegistry`, `UnifiedFrameworkAdapter`, `ModelInfo`, `LLMFramework`, `FrameworkModality`, `ServiceContainer`, `FrameworkAvailability`
- External: Foundation

**Usage & Callers**
- Used by `ServiceContainer` for adapter management
- Called during framework adapter registration (WhisperKit, LlamaCpp, etc.)

**Potential Issues / Smells**
- Dual storage (new + legacy) adds complexity and potential inconsistency
- `@MainActor` context for registration side effects could cause unexpected delays
- Synchronous `findBestAdapterSync` method exists alongside async version - confusing API

**Unused / Dead Code**
- `findBestAdapterSync` may be unused if all callers migrated to async version

---

### `DependencyInjection/ServiceContainer.swift`

**Role / Responsibility**
- Central dependency injection container for all SDK services
- Manages service lifecycle (bootstrap, initialization, cleanup)
- Provides lazy initialization of services to optimize startup time
- Supports both production and development mode initialization

**Key Types**
- `ServiceContainer` (class) – Singleton container managing all SDK services

**Key Public APIs**
- `static let shared: ServiceContainer` – Singleton instance
- `func bootstrap(with params:authService:apiClient:) async throws -> ConfigurationData` – Full initialization
- `func bootstrapDevelopmentMode(with params:) async throws -> ConfigurationData` – Dev mode init
- `func setupLocalServices(with params:) throws` – Fast local-only setup
- `func initializeNetworkServices(with params:) async throws` – Lazy network init
- `func reset()` – Clear state for testing

**Important Internal Logic**
- **Lazy Services:** All services use lazy var for deferred initialization
- **Bootstrap Process:**
  1. Network services (auth, API client)
  2. Device info collection & sync
  3. Configuration loading (backend/cache/defaults)
  4. Model catalog sync
  5. Model registry initialization
  6. Voice services (optional)
  7. Analytics initialization
- **Development Mode:** Skips network calls, uses mock services, no analytics
- **Async Properties:** Some services use async computed properties (`configurationService`, `telemetryService`, etc.)

**Dependencies**
- Internal: Almost all SDK services (50+ dependencies)
- External: Foundation, Pulse

**Usage & Callers**
- Primary entry point for SDK initialization
- Used throughout SDK via `ServiceContainer.shared`

**Potential Issues / Smells**
- Massive god object with 50+ dependencies - violates Single Responsibility Principle
- Mix of lazy var, async computed properties, and regular properties is confusing
- `_syncCoordinator`, `_configurationService` use underscore prefixes for private storage - inconsistent pattern
- `setModelAssignmentService` uses `Any` type to avoid circular dependency - code smell
- 500+ lines in single file - should be split

**Unused / Dead Code**
- `getModelAssignmentService()` returns `Any` - callers must know type, fragile

---

### `DependencyInjection/ServiceLifecycle.swift`

**Role / Responsibility**
- Manages lifecycle of services implementing LifecycleAware protocol
- Provides coordinated start/stop of registered services
- Ensures proper cleanup order (reverse of start order)

**Key Types**
- `LifecycleAware` (protocol) – Services needing lifecycle management
- `ServiceLifecycle` (actor) – Coordinates service lifecycle
- `ServiceLifecycleError` (enum) – Lifecycle-related errors

**Key Public APIs**
- `func register(_ service: LifecycleAware, name: String)` – Register service
- `func startAll() async throws` – Start all registered services
- `func stopAll() async throws` – Stop all in reverse order
- `func start(_ name: String) async throws` – Start specific service
- `func stop(_ name: String) async throws` – Stop specific service
- `func restart(_ name: String) async throws` – Restart a service

**Important Internal Logic**
- Actor ensures thread-safe state management
- Tracks started services in Set to prevent double-start
- Stops services in reverse order of starting (LIFO cleanup)
- Idempotent start/stop (no-op if already started/stopped)

**Dependencies**
- External: Foundation

**Usage & Callers**
- Currently appears unused in the SDK
- Designed for future use with services needing coordinated lifecycle

**Potential Issues / Smells**
- Not currently integrated into SDK - dead code?
- No error handling for partial failures during startAll/stopAll
- ServiceLifecycleError cases defined but not thrown

**Unused / Dead Code**
- Entire file appears unused - no references to `ServiceLifecycle` in codebase

---

## DeviceIdentity Subdirectory (2 files)

### `DeviceIdentity/DeviceManager.swift`

**Role / Responsibility**
- Manages device identity persistence across app sessions
- Handles device ID storage in keychain and UserDefaults
- Tracks device registration state
- Provides platform-specific device information

**Key Types**
- `DeviceManager` (class) – Static methods for device identity management
- `RegistrationState` (enum) – Four states: notRegistered, registering, registered, failed

**Key Public APIs**
- `static func getStoredDeviceId() -> String?` – Retrieve stored device ID
- `static func storeDeviceId(_ deviceId: String) throws` – Store device ID securely
- `static func clearDeviceId()` – Clear stored ID
- `static func isDeviceRegistered() -> Bool` – Check registration status
- `static func generateDeviceIdentifier() -> String` – Generate new device ID
- `static func createDeviceInfo() -> [String: Any]` – Create device info dict

**Important Internal Logic**
- Tries keychain first (production), falls back to UserDefaults (development)
- Uses `identifierForVendor` on iOS, UUID fallback on other platforms
- Registration state stored in UserDefaults for quick access
- Thread-safe via UnfairLock

**Dependencies**
- Internal: `KeychainManager`, `UnfairLock`, `SDKLogger`, `SDKError`, `RunAnywhere.currentEnvironment`
- External: Foundation, UIKit (iOS/tvOS), WatchKit (watchOS)

**Usage & Callers**
- Used during SDK initialization for device registration
- Extended by `KeychainManager` for device ID operations

**Potential Issues / Smells**
- Mix of static methods and instance state (via lock) is confusing
- `createDeviceInfo()` returns untyped `[String: Any]` - should use struct
- Platform-specific code not fully testable (requires device/simulator)

**Unused / Dead Code**
- `createDeviceInfo()` appears unused - dead code?

---

### `DeviceIdentity/PersistentDeviceIdentity.swift`

**Role / Responsibility**
- Provides persistent device UUID that survives app reinstalls
- Multi-layered approach: keychain → vendor ID → new UUID
- Generates device fingerprint for identity validation
- More robust than DeviceManager's basic ID storage

**Key Types**
- `PersistentDeviceIdentity` (class) – Static methods for persistent identity

**Key Public APIs**
- `static func getPersistentDeviceUUID() -> String` – Get/generate persistent UUID
- `static func getDeviceFingerprint() -> String` – Get hardware fingerprint
- `static func validateDeviceUUID(_ uuid: String) -> Bool` – Validate UUID format

**Important Internal Logic**
- **Strategy 1:** Check persistent keychain
- **Strategy 2:** Use `identifierForVendor` (Apple's stable ID)
- **Strategy 3:** Generate new UUID and store
- **Fingerprint Components:** Memory, CPU architecture, chip name, core count, OS major version
- Uses SHA256 hash of fingerprint components
- Fingerprint stored alongside UUID for validation

**Dependencies**
- Internal: `KeychainManager`, `SDKLogger`, `DeviceKitAdapter`
- External: Foundation, UIKit (iOS/tvOS), CommonCrypto

**Usage & Callers**
- Alternative to `DeviceManager` for more persistent identity
- Used when device ID needs to survive app reinstalls

**Potential Issues / Smells**
- Overlaps with `DeviceManager` functionality - consolidation needed
- `validateDeviceUUID` only checks format, not actually validates against fingerprint
- CommonCrypto import requires manual bridging header setup
- DeviceKitAdapter dependency not shown in file - potential missing import

**Unused / Dead Code**
- File may be entirely unused if `DeviceManager` is primary identity manager

---

## ErrorTypes Subdirectory (3 files)

### `ErrorTypes/ErrorType.swift`

**Role / Responsibility**
- Categorizes errors into high-level types for analytics and handling
- Provides automatic error categorization from Error instances
- Enables consistent error classification across SDK

**Key Types**
- `ErrorType` (enum) – 9 error categories

**Key Public APIs**
- `init(from error: Error)` – Categorize any error automatically

**Important Internal Logic**
- Checks error type hierarchy (URLError, NSError)
- Inspects NSError domain for categorization
- Falls back to string matching in error description
- Keywords: "memory", "download", "validation", "hardware", "auth"

**Dependencies**
- External: Foundation

**Usage & Callers**
- Used in error handling and telemetry categorization
- Helps route errors to appropriate handlers

**Potential Issues / Smells**
- String matching on error descriptions is fragile and locale-dependent
- Many errors will fall through to `.unknown` category
- No way to explicitly specify category (only automatic inference)

**Unused / Dead Code**
- None identified

---

### `ErrorTypes/FrameworkError.swift`

**Role / Responsibility**
- Framework-specific errors for ML framework operations
- Covers initialization, loading, inference, and configuration failures

**Key Types**
- `FrameworkError` (enum) – 6 framework error cases

**Key Public APIs**
- All cases: `.notAvailable`, `.initializationFailed`, `.modelLoadFailed`, `.inferenceError`, `.unsupportedOperation`, `.configurationError`
- `var errorDescription: String?` – LocalizedError conformance

**Important Internal Logic**
- Each case has associated String value for context
- Implements LocalizedError for error description

**Dependencies**
- External: Foundation

**Usage & Callers**
- Thrown by framework adapters (LlamaCpp, CoreML, WhisperKit)
- Caught and converted to `UnifiedModelError`

**Potential Issues / Smells**
- Generic associated strings don't provide structured error data
- Could benefit from more specific cases (e.g., separate memory vs format errors)

**Unused / Dead Code**
- None identified

---

### `ErrorTypes/UnifiedModelError.swift`

**Role / Responsibility**
- Top-level unified error type for all model operations
- Wraps lower-level errors and provides recovery hints
- Supports retry logic with framework fallback

**Key Types**
- `UnifiedModelError` (enum) – 9 unified error cases

**Key Public APIs**
- Cases include: `.lifecycle`, `.framework`, `.insufficientMemory`, `.deviceNotSupported`, `.authRequired`, `.retryRequired`, `.retryWithFramework`, `.noAlternativeFramework`, `.unrecoverable`
- `var errorDescription: String?` – User-friendly descriptions

**Important Internal Logic**
- Wraps `ModelLifecycleError` and `FrameworkError`
- Memory error includes bytes required vs available
- Retry cases provide actionable recovery path
- ByteCountFormatter for human-readable memory sizes

**Dependencies**
- Internal: `ModelLifecycleError`, `FrameworkError`, `LLMFramework`
- External: Foundation

**Usage & Callers**
- Primary error type for model loading and inference
- Used by error recovery and retry logic

**Potential Issues / Smells**
- `.unrecoverable(Error)` loses type information - hard to handle
- No ErrorCode integration (separate error code system exists)

**Unused / Dead Code**
- None identified

---

## FileOperations Subdirectory (2 files)

### `FileOperations/ArchiveUtility.swift`

**Role / Responsibility**
- Handles extraction of archive files (ZIP, tar.bz2)
- Provides cross-platform archive operations
- Supports model distribution via compressed archives

**Key Types**
- `ArchiveUtility` (class) – Static utility methods for archives
- `TarHeader` (private struct) – Tar header parser

**Key Public APIs**
- `static func extractTarBz2Archive(from:to:) throws` – Extract tar.bz2 archives
- `static func extractZipArchive(from:to:overwrite:) throws` – Extract ZIP archives
- `static func createZipArchive(from:to:) throws` – Create ZIP archives
- `static func isTarBz2Archive(_ url: URL) -> Bool` – Check if URL is tar.bz2
- `static func isZipArchive(_ url: URL) -> Bool` – Check if URL is ZIP

**Important Internal Logic**
- **macOS:** Uses `/usr/bin/bunzip2` process for bz2 decompression
- **iOS:** Throws error recommending ZIP format (bz2 not fully supported)
- Uses ZIPFoundation library for ZIP operations
- Manual tar parsing (512-byte blocks, octal size fields)
- Supports tar file types: regular files, directories, skips symlinks

**Dependencies**
- Internal: `DownloadError`
- External: Foundation, ZIPFoundation

**Usage & Callers**
- Used by download service for model archive extraction
- FileManager extension provides unified `extractArchive` method

**Potential Issues / Smells**
- iOS bz2 support incomplete - throws error instead of implementing
- Manual tar parsing is complex and error-prone (should use library)
- Process-based decompression on macOS could fail without proper error handling
- No progress reporting for large archives

**Unused / Dead Code**
- `decompressBz2Manually` method effectively dead (always throws on iOS)

---

### `FileOperations/ModelPathUtils.swift`

**Role / Responsibility**
- Centralized model path calculation across SDK
- Enforces consistent directory structure: `Documents/RunAnywhere/Models/{framework}/{modelId}/`
- Provides path analysis and extraction utilities

**Key Types**
- `ModelPathUtils` (struct) – Static utility methods for model paths

**Key Public APIs**
- `static func getBaseDirectory() throws -> URL` – Get RunAnywhere base dir
- `static func getModelsDirectory() throws -> URL` – Get models directory
- `static func getFrameworkDirectory(framework:) throws -> URL` – Framework-specific dir
- `static func getModelFolder(modelId:framework:) throws -> URL` – Model folder path
- `static func getModelFilePath(modelId:framework:format:) throws -> URL` – Full model file path
- `static func getModelPath(modelInfo:) throws -> URL` – Path from ModelInfo
- `static func extractModelId(from path:) -> String?` – Extract model ID from path
- `static func extractFramework(from path:) -> LLMFramework?` – Extract framework from path

**Important Internal Logic**
- Path structure: `Documents/RunAnywhere/Models/{framework}/{modelId}/{modelId}.{format}`
- Supports legacy paths without framework component
- Directory-based models (CoreML, WhisperKit) return folder path
- File-based models return full file path with extension
- Path analysis works backward from components

**Dependencies**
- Internal: `SDKError`, `LLMFramework`, `ModelFormat`, `ModelInfo`
- External: Foundation

**Usage & Callers**
- Used throughout SDK for model path calculations
- Critical for model loading, discovery, and cleanup

**Potential Issues / Smells**
- Throws SDKError.storageError for path issues - could be more specific
- Documents directory assumption may not work for all sandboxing scenarios
- Legacy path support adds complexity

**Unused / Dead Code**
- `getExpectedModelPath` may duplicate functionality of `getModelPath`

---

## Logging Subdirectory (8 files)

### `Logging/Logger/SDKLogger.swift`

**Role / Responsibility**
- Centralized logging facade with sensitive data protection
- Provides categorized logging methods for all SDK components
- Sanitizes sensitive data based on policy

**Key Types**
- `SDKLogger` (struct) – Category-scoped logger instance

**Key Public APIs**
- `func debug/info/warning/error/fault(_ message:metadata:)` – Standard logging
- `func log(level:message:metadata:)` – Generic logging
- `func debugSensitive/infoSensitive/warningSensitive/errorSensitive` – Sensitive data logging
- `func performance(_ metric:value:metadata:)` – Performance metrics

**Important Internal Logic**
- Delegates to `LoggingManager.shared`
- Enriches metadata with sensitivity markers
- Sanitization based on `SensitiveDataPolicy`:
  - `.none` – Log as-is
  - `.sensitive` – Show in DEBUG, hide in production
  - `.critical` – Always use placeholder
  - `.redacted` – Never log
- Performance logging adds metric metadata

**Dependencies**
- Internal: `LoggingManager`, `LogLevel`, `SensitiveDataCategory`, `SensitiveDataPolicy`, `LogMetadataKeys`
- External: Foundation

**Usage & Callers**
- Used throughout SDK via `let logger = SDKLogger(category: "ComponentName")`
- Primary logging interface for all SDK components

**Potential Issues / Smells**
- Sensitive logging methods are internal - should these be public for app developers?
- Sanitization only applies to message, not metadata
- Performance logging always at `.info` level - not configurable

**Unused / Dead Code**
- Sensitive logging methods may be underutilized (most code uses standard methods)

---

### `Logging/Models/LogEntry.swift`

**Role / Responsibility**
- Single log entry structure for internal logging pipeline
- Encodable for remote transmission
- Captures timestamp, level, category, message, metadata, and device info

**Key Types**
- `LogEntry` (struct) – Internal log entry representation

**Key Public APIs**
- `init(timestamp:level:category:message:metadata:deviceInfo:)` – Create log entry
- Encodable conformance for JSON serialization

**Important Internal Logic**
- Converts metadata values to strings via `String(describing:)`
- Optional deviceInfo for privacy control
- Custom Encodable implementation to serialize level as string

**Dependencies**
- Internal: `LogLevel`, `DeviceInfo`
- External: Foundation

**Usage & Callers**
- Created by `LoggingManager` for each log call
- Passed to Pulse and remote logging services

**Potential Issues / Smells**
- Metadata conversion to String loses type information
- No structured logging support (all metadata flattened)

**Unused / Dead Code**
- None identified

---

### `Logging/Models/LoggingConfiguration.swift`

**Role / Responsibility**
- Configuration settings for logging behavior
- Controls local vs remote logging, batching, and filtering

**Key Types**
- `LoggingConfiguration` (struct) – Logging configuration

**Key Public APIs**
- `var enableLocalLogging: Bool` – Console/os_log toggle
- `var enableRemoteLogging: Bool` – Telemetry toggle
- `var remoteEndpoint: URL?` – Remote logging endpoint
- `var minLogLevel: LogLevel` – Minimum level to log
- `var batchSize: Int` – Max entries before send (default 100)
- `var batchInterval: TimeInterval` – Max wait before send (default 60s)

**Important Internal Logic**
- Public mutable properties for runtime configuration
- Defaults: local=true, remote=false, level=info, batch=100/60s

**Dependencies**
- Internal: `LogLevel`
- External: Foundation

**Usage & Callers**
- Used by `LoggingManager` to control logging behavior
- Can be updated via `LoggingManager.configure()`

**Potential Issues / Smells**
- No validation on values (e.g., negative batchSize)
- Simple struct - could benefit from builder pattern

**Unused / Dead Code**
- `batchSize` and `batchInterval` used by LogBatcher (may be unused if remote logging disabled)

---

### `Logging/Models/LogLevel.swift`

**Role / Responsibility**
- Defines log severity levels matching standard logging systems
- Provides ordering and string representation

**Key Types**
- `LogLevel` (enum) – Five severity levels

**Key Public APIs**
- Cases: `.debug`, `.info`, `.warning`, `.error`, `.fault`
- `Comparable` conformance for level filtering
- `CustomStringConvertible` for display

**Important Internal Logic**
- Int raw values for ordering (0=debug, 4=fault)
- Comparison based on raw value

**Dependencies**
- External: Foundation

**Usage & Callers**
- Used throughout logging system for level filtering
- Converted to Pulse levels in LoggingManager

**Potential Issues / Smells**
- None - clean, standard enum

**Unused / Dead Code**
- None identified

---

### `Logging/Models/SensitiveDataPolicy.swift`

**Role / Responsibility**
- Defines policies for handling sensitive data in logs
- Categorizes different types of sensitive information
- Provides sanitized placeholders for redaction

**Key Types**
- `SensitiveDataPolicy` (enum) – Four policy levels
- `SensitiveDataCategory` (enum) – 16 categories of sensitive data
- `LogMetadataKeys` (struct) – Metadata key constants

**Key Public APIs**
- `SensitiveDataPolicy` cases: `.none`, `.sensitive`, `.critical`, `.redacted`
- `SensitiveDataCategory` cases: API keys, user content, PII, config, business logic
- `var defaultPolicy: SensitiveDataPolicy` – Policy for each category
- `var sanitizedPlaceholder: String` – Redaction placeholder

**Important Internal Logic**
- **Critical policy:** User prompts, responses, PII (never log actual content)
- **Sensitive policy:** Paths, errors (log in DEBUG only)
- **Redacted policy:** Credentials (never log at all)
- Each category has specific placeholder (e.g., "[API_KEY]", "[USER_PROMPT]")

**Dependencies**
- External: Foundation

**Usage & Callers**
- Used by SDKLogger for sanitization
- Referenced in metadata for sensitive logs

**Potential Issues / Smells**
- Great design for privacy and compliance
- Could add more granular categories over time

**Unused / Dead Code**
- `LogMetadataKeys` constants may have unused entries

---

### `Logging/Protocols/RemoteLoggingService.swift`

**Role / Responsibility**
- Protocol defining interface for remote logging service integration
- Extensive documentation recommending Sentry
- Includes comparison of logging services and example implementation

**Key Types**
- `RemoteLoggingService` (protocol) – Interface for remote logging

**Key Public APIs**
- `func configure(apiKey:environment:)` – Initialize service
- `func logEvent(_ event:level:)` – Log event
- `func logError(_ error:metadata:)` – Log error with trace
- `func setUserContext(userId:metadata:)` – Add user context
- `func addBreadcrumb(message:category:level:)` – Track user actions
- `func flush()` – Send pending logs
- `func clear()` – Clear stored data

**Important Internal Logic**
- **Recommendations documented:**
  - **Sentry** (recommended): Error tracking, mobile-optimized, GDPR compliant
  - **DataDog**: Enterprise APM, expensive
  - **LogRocket**: Session replay, web-focused
  - **Custom**: Full control, requires infrastructure
- Includes Sentry implementation example in comments

**Dependencies**
- Internal: `LogEntry`, `LogLevel`, `SDKEnvironment`
- External: Foundation

**Usage & Callers**
- Currently unused - protocol defined for future integration
- Intended for production error monitoring

**Potential Issues / Smells**
- Protocol defined but not implemented anywhere
- Extensive comments could be moved to separate documentation file
- Example code in comments risks becoming outdated

**Unused / Dead Code**
- Entire protocol currently unused (no implementations)

---

### `Logging/Services/LogBatcher.swift`

**Role / Responsibility**
- Batches log entries for efficient remote submission
- Time and size-based batch flushing
- Prevents excessive network requests

**Key Types**
- `LogBatcher` (class) – Internal batching service

**Key Public APIs**
- `init(configuration:onBatchReady:)` – Initialize with config and callback
- `func add(_ entry: LogEntry)` – Add log to batch
- `func flush()` – Force flush immediately
- `func updateConfiguration(_ newConfig:)` – Update batching config

**Important Internal Logic**
- Flushes when batch size reached OR timer expires
- Timer runs on main thread (via DispatchQueue.main)
- Serial queue ensures thread-safe batch operations
- Batch ready callback receives all pending logs

**Dependencies**
- Internal: `LogEntry`, `LoggingConfiguration`
- External: Foundation

**Usage & Callers**
- Used by remote logging services (currently none implemented)
- Would be instantiated when remote logging is enabled

**Potential Issues / Smells**
- Timer on main thread could block UI if callback is slow
- No retry logic if batch delivery fails (callback handles this)
- Stops/starts timer on main thread - could race during config updates

**Unused / Dead Code**
- Currently unused since remote logging not implemented

---

### `Logging/Services/LoggingManager.swift`

**Role / Responsibility**
- Central logging coordinator for entire SDK
- Routes logs to Pulse (local) and prepares for remote service
- Manages environment-based logging configuration
- Handles sensitive data filtering for remote logs

**Key Types**
- `LoggingManager` (class) – Singleton logging manager

**Key Public APIs**
- `static let shared: LoggingManager` – Singleton instance
- `var configuration: LoggingConfiguration` – Get/set config
- `func configure(_ config:)` – Update configuration
- `func configureSDKLogging(endpoint:enabled:)` – SDK team debugging endpoint
- `func log(level:category:message:metadata:)` – Main logging method (internal)
- `func flush()` – Force flush pending logs

**Important Internal Logic**
- **Environment-based defaults:**
  - Development: local only, debug level, no device metadata
  - Staging: remote only, info level, include metadata
  - Production: remote only, warning level, include metadata
- Uses Pulse for local logging with automatic network request logging
- Converts LogLevel to Pulse Level
- Checks metadata for sensitive markers before remote logging
- Configuration protected by UnfairLockWithState

**Dependencies**
- Internal: `SDKLogger`, `LoggingConfiguration`, `LogLevel`, `LogEntry`, `DeviceInfo`, `SensitiveDataPolicy`, `LogMetadataKeys`, `UnfairLockWithState`, `RunAnywhere.currentEnvironment`, `SDKEnvironment`
- External: Foundation, Pulse

**Usage & Callers**
- Used by SDKLogger (which wraps this)
- Initialized on first access to shared singleton

**Potential Issues / Smells**
- Remote logging TODO - not yet implemented with external service
- Pulse configuration happens automatically - may conflict with app's own Pulse setup
- `configurePulse()` enables URLSessionProxyDelegate globally - could affect app's networking
- Metadata sanitization only removes marker keys, doesn't sanitize values

**Unused / Dead Code**
- `sanitizeForRemote()` method defined but never called
- Remote logging branch never executes (remote service not implemented)
- `configureSDKLogging()` creates log entry with Pulse but no remote action

---

## Security Subdirectory (1 file)

### `Security/KeychainManager.swift`

**Role / Responsibility**
- Secure storage of sensitive SDK data in iOS keychain
- Manages SDK credentials, device identity, and API keys
- Provides generic keychain operations for string and data storage

**Key Types**
- `KeychainManager` (class) – Singleton keychain manager
- `KeychainError` (enum) – Keychain operation errors

**Key Public APIs**
- **SDK Credentials:**
  - `func storeSDKParams(_ params:) throws` – Store init params
  - `func retrieveSDKParams() -> SDKInitParams?` – Retrieve params
  - `func clearSDKParams() throws` – Clear params
- **Device Identity:**
  - `func storeDeviceUUID(_ uuid:) throws` – Store device UUID
  - `func retrieveDeviceUUID() -> String?` – Retrieve UUID
  - `func storeDeviceFingerprint(_ fingerprint:) throws` – Store fingerprint
  - `func retrieveDeviceFingerprint() -> String?` – Retrieve fingerprint
- **Generic Storage:**
  - `func store(_ value: String, for key:) throws` – Store string
  - `func retrieve(for key:) throws -> String` – Retrieve string
  - `func delete(for key:) throws` – Delete item
  - `func exists(for key:) -> Bool` – Check existence

**Important Internal Logic**
- Uses `kSecClassGenericPassword` for storage
- Service name: "com.runanywhere.sdk"
- Accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (secure, no iCloud sync)
- Update-or-insert pattern (try update first, then add)
- Private enum for internal keychain keys

**Dependencies**
- Internal: `SDKLogger`, `SDKInitParams`, `SDKEnvironment`
- External: Foundation, Security framework

**Usage & Callers**
- Used by DeviceManager for device ID persistence
- Used by PersistentDeviceIdentity for UUID storage
- Could be used to persist SDK initialization across app launches

**Potential Issues / Smells**
- No access group support (commented out) - limits app extension sharing
- `OSStatus` errors wrapped but raw status codes exposed in errors
- Synchronization not handled (could lose writes if app killed before sync)

**Unused / Dead Code**
- `storeSDKParams/retrieveSDKParams` may be unused if SDK doesn't persist credentials
- `accessGroup` property exists but always nil

---

## Summary: Key Patterns and Issues

### Architectural Patterns

1. **Singleton Pattern:** Extensively used (LoggingManager, KeychainManager, AnalyticsQueueManager, ServiceContainer)
2. **Actor Pattern:** Modern Swift concurrency (AnalyticsQueueManager, ServiceLifecycle)
3. **Lock-based Synchronization:** UnfairLock for thread-safety in non-actor code
4. **Dependency Injection:** ServiceContainer as central DI container
5. **Lazy Initialization:** Most services use lazy var for deferred creation
6. **Protocol-Oriented Design:** Clear protocols for services (LifecycleAware, RemoteLoggingService)
7. **Strongly Typed Configuration:** Extensive use of enums and structs for type safety

### Code Quality Issues

**High Priority:**
1. **ServiceContainer God Object** - 500+ lines, 50+ dependencies, violates SRP
2. **Overlapping Device Identity Systems** - DeviceManager vs PersistentDeviceIdentity duplication
3. **Unused/Dead Code** - ServiceLifecycle, RemoteLoggingService protocol, LogBatcher (not integrated)
4. **Missing Remote Logging** - Infrastructure exists but not connected to actual service
5. **iOS bz2 Support Incomplete** - ArchiveUtility throws instead of implementing

**Medium Priority:**
6. **Legacy + New Dual Systems** - AdapterRegistry maintains two storage backends
7. **String-based Error Categorization** - ErrorType uses fragile string matching
8. **Async Property Confusion** - Mix of lazy var, async var, regular var in ServiceContainer
9. **Manual Memory Management** - UnfairLock uses allocate/deallocate (requires careful testing)
10. **Type Erasure Workaround** - ServiceContainer uses `Any` for ModelAssignmentService

**Low Priority:**
11. **Large Structs** - GenerationCompletionData has 26 properties
12. **Platform-Specific Code** - Some utilities incomplete on iOS vs macOS
13. **Hard-coded Defaults** - SDKConstants forces cloudRoutingEnabled=false

### Security & Privacy Strengths

- **Excellent sensitive data handling** in logging system
- **Keychain integration** for secure credential storage
- **Privacy-first logging** with categorization and sanitization
- **Thread-safe scope management** for device identity

### Testing Concerns

- **UnfairLock manual memory management** needs thorough testing
- **Thread isolation** in RunAnywhereScope needs concurrency testing
- **Platform-specific code** requires device testing (not just simulator)
- **Archive extraction** needs testing with various archive formats
- **Error categorization** string matching needs comprehensive test cases

### Recommendations

**Immediate Actions:**
1. **Remove dead code** - ServiceLifecycle, unused methods, commented code
2. **Consolidate device identity** - Merge DeviceManager and PersistentDeviceIdentity
3. **Complete or remove** - bz2 extraction on iOS (currently throws)
4. **Integrate remote logging** - Connect LogBatcher and RemoteLoggingService to Sentry/DataDog

**Refactoring Priorities:**
1. **Break up ServiceContainer** - Extract groups of related services into sub-containers
2. **Standardize async patterns** - Convert all service accessors to async or lazy var (not mix)
3. **Unify adapter storage** - Remove legacy dictionary from AdapterRegistry
4. **Type-safe metadata** - Replace [String: Any] with structured types where possible

**Architecture Improvements:**
1. **Service lifecycle integration** - Actually use ServiceLifecycle or remove it
2. **Structured logging** - Support for structured metadata (not just string conversion)
3. **Error recovery framework** - Leverage UnifiedModelError retry mechanisms systematically

---

## File Dependency Graph

**Most Depended Upon:**
- SDKLogger (used everywhere)
- UnfairLock (critical for thread-safety)
- ServiceContainer (central hub)
- SDKConstants (configuration source)

**Least Coupled:**
- BuildToken (standalone)
- LogLevel (simple enum)
- AnalyticsContext (simple enum)
- ErrorCodes (standalone)

**Circular Dependencies:**
- ServiceContainer ↔ most services (DI container pattern)
- KeychainManager → SDKLogger, DeviceManager → KeychainManager (manageable)
