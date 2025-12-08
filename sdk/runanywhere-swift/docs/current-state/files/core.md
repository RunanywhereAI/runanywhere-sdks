# Core Module - Complete File Analysis

## Overview

The Core module is the foundational layer of the RunAnywhere Swift SDK, providing essential abstractions, protocols, and lifecycle management for all SDK components. This document provides a comprehensive analysis of all 37 files in the Core module.

**File Count Summary:**
- Components: 1 file (BaseComponent.swift - documented separately in components.md)
- Initialization: 2 files
- Models: 16 files (Configuration: 6, Framework: 3, Common: 3, Model: 4)
- Protocols: 16 files (across 10 subdirectories)
- ServiceRegistry: 2 files
- Types: 1 file
- Root files: 2 files (ModelLifecycleManager.swift, ModuleRegistry.swift)

---

## Initialization/ (2 files)

### `Core/Initialization/ComponentInitializer.swift`

**Role / Responsibility**
- Backward-compatibility wrapper for component initialization
- Delegates all operations to UnifiedComponentInitializer
- Provides simplified API surface for existing SDK consumers
- Actor-based thread-safe initialization coordinator

**Key Types**
- `ComponentInitializer` (public actor) - Legacy initialization API that wraps UnifiedComponentInitializer for backward compatibility

**Key Public APIs**
- `func initialize(_ configs: [UnifiedComponentConfig]) async -> InitializationResult` - Initialize components with unified configs
- `func getAllStatuses() async -> [ComponentStatus]` - Get all component statuses
- `func getStatus(for component: SDKComponent) async -> ComponentStatus` - Get specific component status
- `func isReady(_ component: SDKComponent) async -> Bool` - Check if component is ready
- `func areReady(_ components: [SDKComponent]) async -> Bool` - Check multiple components

**Important Internal Logic**
- All methods delegate to internal `unifiedInitializer` instance
- Maintains weak reference to ServiceContainer to avoid retain cycles
- `getAllStatusesWithParameters()` returns statuses without parameters (placeholder for future enhancement)

**Dependencies**
- Internal: UnifiedComponentInitializer, ServiceContainer, SDKLogger
- External: Foundation, Combine

**Usage & Callers**
- Used by SDK consumers who use the older initialization API
- Recommended to migrate to UnifiedComponentInitializer directly

**Potential Issues / Smells**
- `getParameters()` always returns nil - not implemented
- `getAllStatusesWithParameters()` maps all parameters to nil
- Exists solely for backward compatibility - could be deprecated in future

**Unused / Dead Code**
- `getParameters(for:)` method is a stub

---

### `Core/Initialization/UnifiedComponentInitializer.swift`

**Role / Responsibility**
- Core component initialization orchestrator
- Manages parallel and sequential component initialization based on resource requirements
- Creates and tracks component instances throughout their lifecycle
- Publishes SDK initialization events to EventBus

**Key Types**
- `UnifiedComponentInitializer` (public actor) - Main initializer that creates and manages component instances

**Key Public APIs**
- `func initialize(_ configs: [UnifiedComponentConfig]) async -> InitializationResult` - Initialize components with sorting and parallelization
- `func getAllStatuses() -> [ComponentStatus]` - Get all component statuses (synchronous access within actor)
- `func getStatus(for component: SDKComponent) -> ComponentStatus` - Get single component status
- `func isReady(_ component: SDKComponent) -> Bool` - Check readiness
- `func cleanup() async throws` - Cleanup all active components

**Important Internal Logic**
- Sorts configs by priority before initialization
- Parallelizes lightweight components (STT, TTS, VAD, Speaker Diarization, Embedding)
- Sequentializes heavy components (LLM, VLM) to avoid memory pressure
- Tracks active components in dictionary `activeComponents: [SDKComponent: Component]`
- Reinitializes existing components if parameters change
- Uses TaskGroup for parallel initialization

**Dependencies**
- Internal: EventBus, SDKLogger, Component protocols, specific component types (LLMComponent, STTComponent, etc.)
- External: Foundation

**Usage & Callers**
- Called by ComponentInitializer (backward compat wrapper)
- Used directly by SDK consumers for modern initialization API

**Potential Issues / Smells**
- VLM and Embedding components throw "not yet implemented" errors
- Wake word returns error pointing to `createVoiceAgent` method
- `parametersMatch()` only checks type and modelId - shallow comparison
- No retry logic for failed component initialization

**Unused / Dead Code**
- None identified

---

## Models/ (16 files)

### Models/Common/ (3 files)

#### `Core/Models/Common/QuantizationLevel.swift`

**Role / Responsibility**
- Defines quantization levels for model compression
- Provides standardized quantization format identifiers

**Key Types**
- `QuantizationLevel` (public enum) - Quantization levels from full precision (fp32) to extreme compression (int2, q2K)

**Key Public APIs**
- All cases are public: `.full`, `.f32`, `.half`, `.f16`, `.int8`, `.q8v0`, `.int4`, `.q4v0`, `.q4KS`, `.q4KM`, `.q5v0`, `.q5KS`, `.q5KM`, `.q6K`, `.q3KS`, `.q3KM`, `.q3KL`, `.q2K`, `.int2`, `.mixed`

**Important Internal Logic**
- Raw values are string representations matching common quantization notation
- Codable and Sendable for network/database usage

**Dependencies**
- External: Foundation

**Usage & Callers**
- Used in ModelInfoMetadata for model quantization information
- Referenced in model selection and download decisions

**Potential Issues / Smells**
- No validation or conversion between formats
- No memory/quality tradeoff guidance

**Unused / Dead Code**
- None identified

---

#### `Core/Models/Common/RequestPriority.swift`

**Role / Responsibility**
- Defines priority levels for internal request scheduling
- Provides ordering for request queue management

**Key Types**
- `RequestPriority` (internal enum) - Priority levels: low(0), normal(1), high(2), critical(3)

**Key Public APIs**
- Conforms to Comparable for priority-based sorting

**Important Internal Logic**
- Uses Int raw values for simple numeric comparison
- `<` operator compares raw values

**Dependencies**
- External: Foundation

**Usage & Callers**
- Internal SDK request queue management
- Not exposed publicly (internal visibility)

**Potential Issues / Smells**
- Internal-only visibility limits extensibility
- No dynamic priority adjustment

**Unused / Dead Code**
- Currently defined but usage not visible in Core module

---

#### `Core/Models/Common/ResourceAvailability.swift`

**Role / Responsibility**
- Captures current device resource state
- Validates if device can load a specific model
- Provides resource availability checks with detailed error messages

**Key Types**
- `ResourceAvailability` (public struct) - Container for memory, storage, accelerators, thermal state, battery, and power mode

**Key Public APIs**
- `func canLoad(model: ModelInfo) -> (canLoad: Bool, reason: String?)` - Validates if model can be loaded given current resources

**Important Internal Logic**
- Checks memory required vs available
- Validates storage space for downloads
- Blocks loading on critical thermal state
- Blocks loading in low power mode with low battery (<20%)
- Returns human-readable error messages with ByteCountFormatter

**Dependencies**
- Internal: HardwareAcceleration, ModelInfo
- External: Foundation

**Usage & Callers**
- Used by ModelLifecycleManager and component initialization
- Hardware detection services populate this struct

**Potential Issues / Smells**
- Hard-coded 20% battery threshold
- No configuration for thermal/battery policies
- Thermal check only blocks on .critical, not .serious

**Unused / Dead Code**
- None identified

---

### Models/Configuration/ (6 files)

#### `Core/Models/Configuration/APIConfiguration.swift`

**Role / Responsibility**
- Simplified network API configuration
- Defines base URL and timeout for API requests

**Key Types**
- `APIConfiguration` (public struct) - Contains baseURL and timeoutInterval

**Key Public APIs**
- `baseURL: URL` - Base URL for API requests (default from RunAnywhereConstants)
- `timeoutInterval: TimeInterval` - Request timeout (default 30 seconds)

**Important Internal Logic**
- Default URL from RunAnywhereConstants.apiURLs.current
- Fallback to file URL if constant parsing fails

**Dependencies**
- Internal: RunAnywhereConstants
- External: Foundation

**Usage & Callers**
- Part of ConfigurationData composite
- Used by network services for API calls

**Potential Issues / Smells**
- Fallback to file URL is strange - should throw or use proper default
- No retry configuration
- No API version configuration

**Unused / Dead Code**
- None identified

---

#### `Core/Models/Configuration/ConfigurationData.swift`

**Role / Responsibility**
- Main configuration data structure composing all sub-configurations
- Works for both network API and database storage (GRDB)
- Implements sync tracking for remote configuration updates

**Key Types**
- `ConfigurationData` (public struct) - Composite configuration with routing, generation, storage, API, download, hardware
- `ConfigurationSource` (public enum) - Configuration origin: remote, consumer, defaults

**Key Public APIs**
- All configuration properties: routing, generation, storage, api, download, hardware
- `debugMode: Bool` - Debug mode flag
- `apiKey: String?` - Optional API key
- `allowUserOverride: Bool` - Whether user can override config
- `static func sdkDefaults(apiKey: String) -> ConfigurationData` - Factory for default config

**Important Internal Logic**
- GRDB FetchableRecord and PersistableRecord conformance
- RepositoryEntity protocol for database operations
- Persistence conflict policy: replace on insert/update
- Tracks sync state with `syncPending` flag
- Maintains createdAt/updatedAt timestamps

**Dependencies**
- Internal: RepositoryEntity, RoutingConfiguration, GenerationConfiguration, StorageConfiguration, APIConfiguration, ModelDownloadConfiguration, HardwareConfiguration
- External: Foundation, GRDB

**Usage & Callers**
- Central configuration used throughout SDK
- Loaded by ConfigurationService on SDK initialization
- Persisted to database for offline access

**Potential Issues / Smells**
- API key stored in configuration - security concern if logged or persisted insecurely
- No encryption for sensitive fields
- "dev-mode" magic string for empty API key

**Unused / Dead Code**
- None identified

---

#### `Core/Models/Configuration/GenerationConfiguration.swift`

**Role / Responsibility**
- Configuration for text generation behavior
- Defines default generation parameters (temperature, max tokens, etc.)
- Token budget management for usage limits

**Key Types**
- `GenerationConfiguration` (public struct) - Top-level generation config
- `DefaultGenerationSettings` (public struct) - Default generation parameters
- `TokenBudgetConfiguration` (public struct) - Token usage limits

**Key Public APIs**
- `defaults: DefaultGenerationSettings` - Default generation settings
- `tokenBudget: TokenBudgetConfiguration?` - Optional token budget
- `frameworkPreferences: [LLMFramework]` - Preferred frameworks in order
- `maxContextLength: Int` - Maximum context length (default 4096)
- `enableThinkingExtraction: Bool` - Enable reasoning extraction
- `thinkingPattern: String?` - Pattern for thinking content

**Important Internal Logic**
- Default temperature: 0.7
- Default max tokens: 256
- Default top-p: 0.9
- Token budget can enforce limits strictly or as soft limits
- Supports per-request, per-day, per-month token limits

**Dependencies**
- Internal: LLMFramework
- External: Foundation

**Usage & Callers**
- Part of ConfigurationData
- Used by LLM components for generation parameters
- Token budget enforced by usage tracking services

**Potential Issues / Smells**
- No validation that topP is in [0, 1]
- No validation that temperature is positive
- Token budget enforcement mechanism not shown
- Thinking pattern is just a string - no pattern validation

**Unused / Dead Code**
- None identified

---

#### `Core/Models/Configuration/ModelDownloadConfiguration.swift`

**Role / Responsibility**
- Configuration for model download policies
- Defines retry behavior and concurrency limits
- Network condition awareness (WiFi-only option)

**Key Types**
- `ModelDownloadConfiguration` (public struct) - Download configuration
- `DownloadPolicy` (public enum) - Download policies: automatic, wifiOnly, manual, never

**Key Public APIs**
- `policy: DownloadPolicy` - Download policy (default automatic)
- `maxConcurrentDownloads: Int` - Max concurrent downloads (default 3)
- `retryCount: Int` - Retry attempts (default 3)
- `timeout: TimeInterval` - Download timeout (default 300s)
- `enableBackgroundDownloads: Bool` - Background download support (default false)
- `func shouldAllowDownload(isWiFi: Bool, userConfirmed: Bool) -> Bool` - Check if download allowed

**Important Internal Logic**
- Automatic policy always allows downloads
- WiFi-only requires isWiFi flag
- Manual requires userConfirmed flag
- Never policy always returns false

**Dependencies**
- External: Foundation

**Usage & Callers**
- Part of ConfigurationData
- Used by ModelManager and download services

**Potential Issues / Smells**
- Background downloads default to false but iOS supports this well
- No bandwidth limit configuration
- No cellular data limit configuration
- No download scheduling options

**Unused / Dead Code**
- None identified

---

#### `Core/Models/Configuration/RoutingConfiguration.swift`

**Role / Responsibility**
- Configuration for routing decisions between on-device and cloud
- Privacy mode settings
- Custom routing rules support

**Key Types**
- `RoutingConfiguration` (public struct) - Routing configuration with policy and rules

**Key Public APIs**
- `policy: RoutingPolicy` - Routing policy (default deviceOnly)
- `cloudEnabled: Bool` - Whether cloud routing enabled (default false)
- `privacyMode: PrivacyMode` - Privacy mode for routing
- `customRules: [String: String]` - Custom routing rules (dictionary)
- `maxLatencyThreshold: Int?` - Max latency for routing (milliseconds)
- `minConfidenceScore: Double?` - Min confidence for on-device (0.0-1.0)

**Important Internal Logic**
- Custom Codable implementation to handle [String: String] instead of [String: Any]
- Custom rules stored as string dictionary for Sendable conformance

**Dependencies**
- Internal: RoutingPolicy, PrivacyMode
- External: Foundation

**Usage & Callers**
- Part of ConfigurationData
- Used by routing decision services

**Potential Issues / Smells**
- customRules as [String: String] is limiting - can't represent complex rule logic
- No validation of latency threshold or confidence score ranges
- PrivacyMode and RoutingPolicy types not defined in this file

**Unused / Dead Code**
- None identified

---

#### `Core/Models/Configuration/StorageConfiguration.swift`

**Role / Responsibility**
- Configuration for storage behavior and cache management
- Eviction policies for cache cleanup
- Auto-cleanup scheduling

**Key Types**
- `StorageConfiguration` (public struct) - Storage configuration
- `CacheEvictionPolicy` (public enum) - Eviction policies: LRU, LFU, FIFO, largest-first

**Key Public APIs**
- `maxCacheSize: Int64` - Max cache size in bytes (default 1GB)
- `evictionPolicy: CacheEvictionPolicy` - Eviction policy (default LRU)
- `directoryName: String` - Storage directory name (default "RunAnywhere")
- `enableAutoCleanup: Bool` - Auto cleanup enabled (default true)
- `autoCleanupInterval: TimeInterval` - Cleanup interval (default 24 hours)
- `minimumFreeSpace: Int64` - Min free space to maintain (default 500MB)
- `enableCompression: Bool` - Compress stored models (default false)

**Important Internal Logic**
- LRU (Least Recently Used) is default eviction policy
- Auto-cleanup runs every 24 hours by default
- Maintains 500MB minimum free space

**Dependencies**
- External: Foundation

**Usage & Callers**
- Part of ConfigurationData
- Used by storage management services

**Potential Issues / Smells**
- Hard-coded defaults may not suit all device types (iPhone vs iPad vs Mac)
- Compression disabled by default - could save significant space
- No per-model cache policies

**Unused / Dead Code**
- None identified

---

### Models/Framework/ (3 files)

#### `Core/Models/Framework/FrameworkModality.swift`

**Role / Responsibility**
- Defines input/output modalities that frameworks support
- Maps frameworks to their supported modalities
- Provides UI display information for modalities

**Key Types**
- `FrameworkModality` (public enum) - Modalities: textToText, voiceToText, textToVoice, imageToText, textToImage, multimodal

**Key Public APIs**
- `displayName: String` - Human-readable name
- `iconName: String` - SF Symbol icon name

**Important Internal Logic**
- Extension on LLMFramework provides:
  - `primaryModality: FrameworkModality` - Main modality for each framework
  - `supportedModalities: Set<FrameworkModality>` - All supported modalities
  - `isVoiceFramework: Bool` - Whether primarily for voice/audio
  - `isTextGenerationFramework: Bool` - Whether primarily for text generation
  - `supportsImageProcessing: Bool` - Whether supports image I/O

**Dependencies**
- Internal: LLMFramework
- External: Foundation

**Usage & Callers**
- Used by UnifiedFrameworkAdapter to determine compatibility
- Used by ModelCategory for modality mapping
- Used by component initialization to select adapters

**Potential Issues / Smells**
- Hard-coded framework-to-modality mappings - brittle if frameworks evolve
- CoreML marked as supporting all 5 modalities - overly permissive

**Unused / Dead Code**
- None identified

---

#### `Core/Models/Framework/LLMFramework.swift`

**Role / Responsibility**
- Enumeration of all supported ML frameworks
- Provides display names for UI presentation

**Key Types**
- `LLMFramework` (public enum) - All supported frameworks: CoreML, TFLite, MLX, SwiftTransformers, ONNX, ExecuTorch, LlamaCpp, FoundationModels, PicoLLM, MLC, MediaPipe, WhisperKit, OpenAIWhisper, SystemTTS

**Key Public APIs**
- `displayName: String` - Human-readable framework name

**Important Internal Logic**
- CaseIterable for iterating all frameworks
- Codable for serialization
- Sendable for concurrency

**Dependencies**
- External: Foundation

**Usage & Callers**
- Used throughout SDK for framework identification
- Used in ModelInfo for compatibility tracking
- Used in adapter registration

**Potential Issues / Smells**
- Named "LLM" Framework but includes non-LLM frameworks (Whisper, TTS)
- No version tracking for frameworks

**Unused / Dead Code**
- None identified

---

#### `Core/Models/Framework/ModelFormat.swift`

**Role / Responsibility**
- Enumeration of supported model file formats
- Used for format detection and validation

**Key Types**
- `ModelFormat` (public enum) - Formats: mlmodel, mlpackage, tflite, onnx, ort, safetensors, gguf, ggml, mlx, pte, bin, weights, checkpoint, unknown

**Key Public APIs**
- All cases public for matching file extensions

**Important Internal Logic**
- Raw values are lowercase strings matching file extensions
- CaseIterable, Codable, Sendable

**Dependencies**
- External: Foundation

**Usage & Callers**
- Used in ModelInfo for format tracking
- Used by adapters to check format compatibility
- Used by download strategies for file handling

**Potential Issues / Smells**
- No multi-file format representation (e.g., PyTorch checkpoints with multiple files)
- No format version tracking

**Unused / Dead Code**
- None identified

---

### Models/Model/ (4 files)

#### `Core/Models/Model/ModelCategory.swift`

**Role / Responsibility**
- Defines model categories based on input/output modality
- Aligns with FrameworkModality for consistency
- Provides category-to-framework mapping logic

**Key Types**
- `ModelCategory` (public enum) - Categories: language, speechRecognition, speechSynthesis, vision, imageGeneration, multimodal, audio

**Key Public APIs**
- `displayName: String` - Human-readable category name
- `iconName: String` - SF Symbol icon name
- `frameworkModality: FrameworkModality` - Corresponding modality
- `init?(from modality: FrameworkModality)` - Create from modality
- `requiresContextLength: Bool` - Whether category needs context length
- `supportsThinking: Bool` - Whether category supports reasoning
- `func isCompatible(with modality: FrameworkModality) -> Bool` - Check compatibility
- `static func from(modality:) -> ModelCategory` - Non-failable conversion
- `static func from(framework:) -> ModelCategory` - Infer from framework
- `static func from(format:frameworks:) -> ModelCategory` - Infer from format and frameworks

**Important Internal Logic**
- Language and multimodal categories support thinking/reasoning
- Audio category maps to voiceToText modality
- Multimodal category is compatible with any modality
- Format-based inference: GGUF/GGML → language, MLModel → multimodal

**Dependencies**
- Internal: FrameworkModality, LLMFramework, ModelFormat
- External: Foundation

**Usage & Callers**
- Used in ModelInfo for categorization
- Used by adapters for compatibility checking
- Used by UI for category filtering

**Potential Issues / Smells**
- Category inference from format is heuristic-based - may be inaccurate
- Audio and speechRecognition are separate but similar

**Unused / Dead Code**
- None identified

---

#### `Core/Models/Model/ModelCriteria.swift`

**Role / Responsibility**
- Filter criteria for model selection
- Supports filtering by framework, format, size, hardware requirements, tags

**Key Types**
- `ModelCriteria` (public struct) - Filter criteria for model queries

**Key Public APIs**
- All properties are optional filters:
  - `framework: LLMFramework?`
  - `format: ModelFormat?`
  - `maxSize: Int64?`
  - `minContextLength: Int?`, `maxContextLength: Int?`
  - `requiresNeuralEngine: Bool?`, `requiresGPU: Bool?`
  - `tags: [String]`
  - `quantization: String?`
  - `search: String?` - Full-text search

**Important Internal Logic**
- All fields optional for flexible filtering
- Tags as array for multi-tag filtering
- Search string for text-based queries

**Dependencies**
- Internal: LLMFramework, ModelFormat
- External: Foundation

**Usage & Callers**
- Used by ModelRegistry.filterModels()
- Used by model selection logic in components

**Potential Issues / Smells**
- No builder pattern for ergonomic criteria construction
- No validation of criteria combinations
- Search field is opaque string - no query language

**Unused / Dead Code**
- None identified

---

#### `Core/Models/Model/ModelInfo.swift`

**Role / Responsibility**
- Central model metadata structure
- Database entity with GRDB support
- Tracks download state, usage statistics, sync status
- Provides availability checks

**Key Types**
- `ModelInfo` (public struct) - Complete model metadata with database persistence

**Key Public APIs**
- Essential identifiers: `id`, `name`, `category`
- Format and location: `format`, `downloadURL`, `localPath`
- Size info: `downloadSize`, `memoryRequired`
- Framework compatibility: `compatibleFrameworks`, `preferredFramework`
- Capabilities: `contextLength`, `supportsThinking`, `thinkingPattern`
- Metadata: `metadata: ModelInfoMetadata?`
- Tracking: `source`, `createdAt`, `updatedAt`, `syncPending`, `lastUsed`, `usageCount`
- Computed: `isDownloaded: Bool`, `isAvailable: Bool`
- Database: `databaseTableName = "models"`, Column enums

**Important Internal Logic**
- `isDownloaded` checks:
  - Built-in models (scheme == "builtin") always true
  - File existence on disk
  - Directory non-empty check
- Context length defaults to 2048 for language/multimodal categories if not specified
- Thinking support based on category capability
- Default thinking pattern if model supports thinking
- GRDB replace conflict policy for upserts

**Dependencies**
- Internal: ModelCategory, ModelFormat, LLMFramework, ThinkingTagPattern, ModelInfoMetadata, ConfigurationSource, RepositoryEntity
- External: Foundation, GRDB

**Usage & Callers**
- Central model representation used everywhere
- Stored in database via GRDB
- Cached in ModelInfoCache
- Used by adapters, components, model manager

**Potential Issues / Smells**
- `additionalProperties: [String: String]` is non-Codable runtime property - may cause serialization issues
- Built-in model detection via "builtin" URL scheme is fragile
- No validation of URL schemes or paths

**Unused / Dead Code**
- None identified

---

#### `Core/Models/Model/ModelInfoMetadata.swift`

**Role / Responsibility**
- Optional metadata for models
- Provides author, license, tags, training info

**Key Types**
- `ModelInfoMetadata` (public struct) - Additional model metadata

**Key Public APIs**
- `author: String?` - Model author
- `license: String?` - License type
- `tags: [String]` - Model tags
- `description: String?` - Model description
- `trainingDataset: String?` - Training dataset
- `baseModel: String?` - Base model if fine-tuned
- `quantizationLevel: QuantizationLevel?` - Quantization level
- `version: String?` - Model version
- `minOSVersion: String?` - Minimum OS version
- `minMemory: Int64?` - Minimum memory requirement

**Important Internal Logic**
- All fields optional
- Codable and Sendable for serialization

**Dependencies**
- Internal: QuantizationLevel
- External: Foundation

**Usage & Callers**
- Nested in ModelInfo as optional metadata
- Used for model filtering and display

**Potential Issues / Smells**
- No structured license representation (just string)
- No version parsing or comparison
- minMemory separate from ModelInfo.memoryRequired - potential confusion

**Unused / Dead Code**
- None identified

---

## Protocols/ (16 files)

### Protocols/Analytics/

#### `Core/Protocols/Analytics/UnifiedAnalytics.swift`

**Role / Responsibility**
- Base protocol system for analytics services
- Defines event tracking, metrics, and session management
- Actor-based for thread-safe analytics

**Key Types**
- `AnalyticsService` (public protocol) - Base analytics service with associated types for Event and Metrics
- `AnalyticsEvent` (public protocol) - Base event protocol
- `AnalyticsMetrics` (public protocol) - Base metrics protocol
- `SessionMetadata` (public struct) - Session metadata container

**Key Public APIs**
- `func track(event: Event) async` - Track single event
- `func trackBatch(events: [Event]) async` - Track multiple events
- `func getMetrics() async -> Metrics` - Get current metrics
- `func clearMetrics(olderThan: Date) async` - Clear old metrics
- `func startSession(metadata: SessionMetadata) async -> String` - Start analytics session
- `func endSession(sessionId: String) async` - End session
- `func isHealthy() async -> Bool` - Health check

**Important Internal Logic**
- Actor-based protocol ensures thread-safety
- Associated types allow custom event/metric implementations
- Session management built-in

**Dependencies**
- Internal: AnalyticsEventData (referenced but not defined in this file)
- External: Foundation

**Usage & Callers**
- Implemented by telemetry services
- Used for tracking model usage, performance, errors

**Potential Issues / Smells**
- AnalyticsEventData protocol referenced but not defined
- No batch size limits specified
- No retry or failure handling defined

**Unused / Dead Code**
- None identified

---

### Protocols/Component/

#### `Core/Protocols/Component/Component.swift`

**Role / Responsibility**
- Core protocol that all SDK components must implement
- Defines component lifecycle, state management, and initialization
- Provides specialized protocols for different component types

**Key Types**
- `Component` (public protocol) - Base component protocol
- `LifecycleManaged` (public protocol) - Lifecycle hook protocol
- `ModelBasedComponent` (public protocol) - Components that load models
- `ServiceComponent` (public protocol) - Components that provide services
- `PipelineComponent` (public protocol) - Components that process data
- `ComponentInitResult` (public struct) - Initialization result for observability

**Key Public APIs**
- Component:
  - `static var componentType: SDKComponent { get }` - Component type identifier
  - `var state: ComponentState { get }` - Current state
  - `var parameters: any ComponentInitParameters { get }` - Init parameters
  - `func initialize(with parameters: any ComponentInitParameters) async throws` - Initialize
  - `func cleanup() async throws` - Cleanup
  - `var isReady: Bool { get }` - Ready check
  - `func transitionTo(state: ComponentState) async` - State transition
- LifecycleManaged hooks: willInitialize, didInitialize, willCleanup, didCleanup, handleMemoryPressure
- ModelBasedComponent: modelId, isModelLoaded, loadModel, unloadModel, getModelMemoryUsage
- ServiceComponent: getService, createService
- PipelineComponent: process, canConnectTo

**Important Internal Logic**
- Default `isReady` implementation: `state == .ready`
- Default lifecycle hook implementations are no-ops
- Default memory usage is 0
- Default pipeline connection check is always true

**Dependencies**
- Internal: SDKComponent, ComponentState, ComponentInitParameters
- External: Foundation

**Usage & Callers**
- Implemented by all component types (LLM, STT, TTS, VAD, etc.)
- Used by ComponentInitializer for component management

**Potential Issues / Smells**
- AnyObject constraint means only classes, not structs
- ComponentInitParameters is type-erased (any) - loses type safety
- No error recovery protocol

**Unused / Dead Code**
- None identified

---

### Protocols/Configuration/

#### `Core/Protocols/Configuration/ConfigurationServiceProtocol.swift`

**Role / Responsibility**
- Protocol for configuration management services
- Defines configuration loading, updating, and syncing

**Key Types**
- `ConfigurationServiceProtocol` (public protocol, actor) - Configuration service operations

**Key Public APIs**
- `func getConfiguration() -> ConfigurationData?` - Get current config (synchronous)
- `func ensureConfigurationLoaded() async` - Ensure config is loaded
- `func updateConfiguration(_ updates: (ConfigurationData) -> ConfigurationData) async` - Update config
- `func syncToCloud() async throws` - Sync to cloud
- `func loadConfigurationOnLaunch(apiKey: String) async -> ConfigurationData` - Load on launch
- `func setConsumerConfiguration(_ config: ConfigurationData) async throws` - Set consumer config
- `func loadConfigurationWithFallback(apiKey: String) async -> ConfigurationData` - Legacy load with fallback
- `func clearCache() async throws` - Clear cache
- `func startBackgroundSync(apiKey: String) async` - Start background sync

**Important Internal Logic**
- Actor-based for thread-safety
- Supports both immediate and fallback loading
- Background sync capability

**Dependencies**
- Internal: ConfigurationData
- External: Foundation

**Usage & Callers**
- Implemented by ConfigurationService
- Used by SDK initialization and runtime config updates

**Potential Issues / Smells**
- "Legacy methods for compatibility" comment suggests technical debt
- No configuration validation defined
- No sync conflict resolution protocol

**Unused / Dead Code**
- None identified

---

### Protocols/Downloading/

#### `Core/Protocols/Downloading/DownloadManager.swift`

**Role / Responsibility**
- Protocol for download management operations
- Defines download, cancellation, and tracking

**Key Types**
- `DownloadManager` (public protocol) - Download manager operations

**Key Public APIs**
- `func downloadModel(_ model: ModelInfo) async throws -> DownloadTask` - Start download
- `func cancelDownload(taskId: String)` - Cancel download
- `func activeDownloads() -> [DownloadTask]` - Get active downloads

**Important Internal Logic**
- Returns DownloadTask for tracking
- Task ID-based cancellation

**Dependencies**
- Internal: ModelInfo, DownloadTask
- External: Foundation

**Usage & Callers**
- Implemented by download service implementations
- Used by model manager for model downloads

**Potential Issues / Smells**
- No download prioritization API
- No pause/resume support
- DownloadTask type not defined in this file

**Unused / Dead Code**
- None identified

---

#### `Core/Protocols/Downloading/DownloadStrategy.swift`

**Role / Responsibility**
- Protocol for custom download strategies
- Allows host apps to extend download behavior
- Supports multi-file and ZIP downloads

**Key Types**
- `DownloadStrategy` (public protocol) - Custom download strategy

**Key Public APIs**
- `func canHandle(model: ModelInfo) -> Bool` - Check if strategy can handle model
- `func download(model: ModelInfo, to destinationFolder: URL, progressHandler: ((Double) -> Void)?) async throws -> URL` - Download model

**Important Internal Logic**
- Progress callback for 0.0 to 1.0 progress
- Returns destination URL after download

**Dependencies**
- Internal: ModelInfo
- External: Foundation

**Usage & Callers**
- Implemented by adapters that provide custom download logic
- Used by download manager as fallback for custom model formats

**Potential Issues / Smells**
- No resume support
- No bandwidth control
- Progress handler is optional - no way to guarantee progress updates

**Unused / Dead Code**
- None identified

---

### Protocols/Frameworks/

#### `Core/Protocols/Frameworks/UnifiedFrameworkAdapter.swift`

**Role / Responsibility**
- Unified protocol for all framework adapters (LLM, Voice, Image, etc.)
- Defines adapter capabilities, model loading, and service creation
- Lifecycle hooks for registration

**Key Types**
- `UnifiedFrameworkAdapter` (public protocol) - Base adapter protocol with default implementations

**Key Public APIs**
- `var framework: LLMFramework { get }` - Framework identifier
- `var supportedModalities: Set<FrameworkModality> { get }` - Supported modalities
- `var supportedFormats: [ModelFormat] { get }` - Supported formats
- `func canHandle(model: ModelInfo) -> Bool` - Check compatibility
- `func createService(for modality: FrameworkModality) -> Any?` - Create service
- `func loadModel(_ model: ModelInfo, for modality: FrameworkModality) async throws -> Any` - Load model
- `func configure(with hardware: HardwareConfiguration) async` - Configure hardware
- `func estimateMemoryUsage(for model: ModelInfo) -> Int64` - Estimate memory
- `func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration` - Optimal hardware config
- `@MainActor func onRegistration()` - Registration hook
- `func getProvidedModels() -> [ModelInfo]` - Models provided by adapter
- `func getDownloadStrategy() -> DownloadStrategy?` - Download strategy
- `func initializeComponent(with parameters: any ComponentInitParameters, for modality: FrameworkModality) async throws -> Any?` - Initialize component

**Important Internal Logic**
- Default `supportedModalities` from framework.supportedModalities
- Default `onRegistration()` is no-op
- Default `getProvidedModels()` returns empty array
- Default `getDownloadStrategy()` returns nil
- Default `initializeComponent()` creates service and optionally loads model

**Dependencies**
- Internal: LLMFramework, FrameworkModality, ModelFormat, ModelInfo, HardwareConfiguration, DownloadStrategy, ComponentInitParameters, ServiceContainer
- External: Foundation

**Usage & Callers**
- Implemented by all adapter types (WhisperKit, LlamaCpp, etc.)
- Used by UnifiedServiceRegistry for adapter selection

**Potential Issues / Smells**
- `createService` and `loadModel` return `Any` - type erasure loses safety
- MainActor requirement on `onRegistration()` could cause issues for adapters
- No unload or cleanup method defined

**Unused / Dead Code**
- None identified

---

### Protocols/Hardware/

#### `Core/Protocols/Hardware/HardwareDetector.swift`

**Role / Responsibility**
- Protocol for hardware capability detection
- Provides device resource information

**Key Types**
- `HardwareDetector` (public protocol) - Hardware detection operations

**Key Public APIs**
- `func detectCapabilities() -> DeviceCapabilities` - Detect device capabilities
- `func getAvailableMemory() -> Int64` - Available memory
- `func getTotalMemory() -> Int64` - Total memory
- `func hasNeuralEngine() -> Bool` - Neural Engine availability
- `func hasGPU() -> Bool` - GPU availability
- `func getProcessorInfo() -> ProcessorInfo` - Processor info
- `func getThermalState() -> ProcessInfo.ThermalState` - Thermal state
- `func getBatteryInfo() -> BatteryInfo?` - Battery info

**Important Internal Logic**
- All methods are synchronous queries
- Uses Foundation's ProcessInfo.ThermalState

**Dependencies**
- Internal: DeviceCapabilities, ProcessorInfo, BatteryInfo (defined in Infrastructure/)
- External: Foundation, UIKit (conditional)

**Usage & Callers**
- Implemented by hardware detection services
- Used for resource availability checks

**Potential Issues / Smells**
- No async variants for potentially expensive operations
- No caching strategy defined

**Unused / Dead Code**
- None identified

---

### Protocols/Lifecycle/

#### `Core/Protocols/Lifecycle/ModelLifecycleProgressObserver.swift`

**Role / Responsibility**
- Extended observer protocol for progress updates
- Provides detailed progress information during lifecycle operations

**Key Types**
- `ModelLifecycleProgressObserver` (public protocol) - Progress observer extending ModelLifecycleObserver
- `ModelLifecycleProgress` (public struct) - Progress information

**Key Public APIs**
- `func modelDidUpdateProgress(_ progress: ModelLifecycleProgress)` - Progress callback
- `ModelLifecycleProgress` properties:
  - `currentState: ModelLifecycleState`
  - `percentage: Double` (clamped 0-100)
  - `estimatedTimeRemaining: TimeInterval?`
  - `message: String?`

**Important Internal Logic**
- Percentage clamped to [0, 100] in initializer
- Optional ETA and message for flexibility

**Dependencies**
- Internal: ModelLifecycleObserver, ModelLifecycleState
- External: Foundation

**Usage & Callers**
- Implemented by UI observers for progress display
- Called by model loading/unloading operations

**Potential Issues / Smells**
- None identified

**Unused / Dead Code**
- None identified

---

#### `Core/Protocols/Lifecycle/ModelLifecycleProtocol.swift`

**Role / Responsibility**
- Defines model lifecycle states and state machine
- Observer pattern for lifecycle events
- Lifecycle management protocol

**Key Types**
- `ModelLifecycleState` (public enum) - Lifecycle states: uninitialized, discovered, downloading, downloaded, extracting, extracted, validating, validated, initializing, initialized, loading, loaded, ready, executing, error, cleanup
- `ModelLifecycleObserver` (public protocol) - Observer for state transitions
- `ModelLifecycleManager` (public protocol) - Lifecycle manager
- `ModelLifecycleError` (public enum) - Lifecycle errors

**Key Public APIs**
- Observer:
  - `func modelDidTransition(from oldState: ModelLifecycleState, to newState: ModelLifecycleState)` - State transition callback
  - `func modelDidEncounterError(_ error: Error, in state: ModelLifecycleState)` - Error callback
- Manager:
  - `var currentState: ModelLifecycleState { get }` - Current state
  - `func transitionTo(_ state: ModelLifecycleState) async throws` - Transition
  - `func addObserver(_ observer: ModelLifecycleObserver)` - Add observer
  - `func removeObserver(_ observer: ModelLifecycleObserver)` - Remove observer
  - `func isValidTransition(from: ModelLifecycleState, to: ModelLifecycleState) -> Bool` - Validate transition
- State extension:
  - `isProcessing: Bool` - Whether state is processing

**Important Internal Logic**
- Processing states: downloading, extracting, validating, initializing, loading, executing
- Errors include: invalidTransition, statePrerequisiteNotMet, transitionFailed, invalidState

**Dependencies**
- External: Foundation

**Usage & Callers**
- Implemented by lifecycle management services
- Used by model loading components

**Potential Issues / Smells**
- State machine transitions not defined - up to implementer
- No built-in state transition validation

**Unused / Dead Code**
- None identified

---

### Protocols/Registry/

#### `Core/Protocols/Registry/ModelRegistry.swift`

**Role / Responsibility**
- Protocol for model registry operations
- Model discovery, registration, filtering, and updates

**Key Types**
- `ModelRegistry` (public protocol) - Model registry operations

**Key Public APIs**
- `func discoverModels() async -> [ModelInfo]` - Discover available models
- `func registerModel(_ model: ModelInfo)` - Register model
- `func getModel(by id: String) -> ModelInfo?` - Get by ID
- `func filterModels(by criteria: ModelCriteria) -> [ModelInfo]` - Filter models
- `func updateModel(_ model: ModelInfo)` - Update model
- `func removeModel(_ id: String)` - Remove model

**Important Internal Logic**
- Async discovery for remote model fetching
- Synchronous CRUD operations for local registry

**Dependencies**
- Internal: ModelInfo, ModelCriteria
- External: Foundation

**Usage & Callers**
- Implemented by model registry service
- Used by components for model lookup

**Potential Issues / Smells**
- No batch operations
- No pagination for large model lists

**Unused / Dead Code**
- None identified

---

### Protocols/Storage/

#### `Core/Protocols/Storage/ModelStorageStrategy.swift`

**Role / Responsibility**
- Protocol for custom model storage strategies
- Extends DownloadStrategy with file management
- Handles both downloading and local storage discovery

**Key Types**
- `ModelStorageStrategy` (public protocol) - Storage strategy extending DownloadStrategy
- `ModelStorageDetails` (public struct) - Storage information

**Key Public APIs**
- `func findModelPath(modelId: String, in modelFolder: URL) -> URL?` - Find model in storage
- `func detectModel(in modelFolder: URL) -> (format: ModelFormat, size: Int64)?` - Detect model
- `func isValidModelStorage(at modelFolder: URL) -> Bool` - Validate storage
- `func getModelStorageInfo(at modelFolder: URL) -> ModelStorageDetails?` - Get storage details
- Default implementations provided for single-file models

**Important Internal Logic**
- Default findModelPath searches for files containing model ID
- Default detectModel looks for files with format extensions
- Default isValidModelStorage checks if any model file exists
- Default getModelStorageInfo returns basic details

**Dependencies**
- Internal: DownloadStrategy, ModelFormat
- External: Foundation

**Usage & Callers**
- Implemented by adapters with custom storage (e.g., multi-file models)
- Used by model manager for local model detection

**Potential Issues / Smells**
- Default implementations may not work for complex multi-file models
- No versioning support for model updates

**Unused / Dead Code**
- None identified

---

#### `Core/Protocols/Storage/StorageAnalyzer.swift`

**Role / Responsibility**
- Protocol for storage analysis operations
- Provides storage information and recommendations

**Key Types**
- `StorageAnalyzer` (public protocol) - Storage analysis operations

**Key Public APIs**
- `func analyzeStorage() async -> StorageInfo` - Analyze overall storage
- `func getModelStorageUsage() async -> ModelStorageInfo` - Get model storage usage
- `func checkStorageAvailable(for modelSize: Int64, safetyMargin: Double) -> StorageAvailability` - Check availability
- `func getRecommendations(for storageInfo: StorageInfo) -> [StorageRecommendation]` - Get recommendations
- `func calculateSize(at url: URL) async throws -> Int64` - Calculate directory/file size

**Important Internal Logic**
- Safety margin for storage checks
- Recommendation system for storage optimization

**Dependencies**
- Internal: StorageInfo, ModelStorageInfo, StorageAvailability, StorageRecommendation
- External: Foundation

**Usage & Callers**
- Implemented by storage analyzer service
- Used for storage monitoring and cleanup decisions

**Potential Issues / Smells**
- Types referenced (StorageInfo, etc.) not defined in this file
- No streaming calculation for large directories

**Unused / Dead Code**
- None identified

---

#### `Core/Protocols/Storage/StorageMonitoring.swift`

**Role / Responsibility**
- Protocol for storage monitoring operations
- Start/stop monitoring, get current info

**Key Types**
- `StorageMonitoring` (public protocol) - Storage monitoring operations

**Key Public APIs**
- `func startMonitoring()` - Start monitoring
- `func stopMonitoring()` - Stop monitoring
- `func getStorageInfo() async -> StorageInfo` - Get current info
- `var isMonitoring: Bool { get }` - Monitoring state

**Important Internal Logic**
- Simple start/stop lifecycle
- Async storage info retrieval

**Dependencies**
- Internal: StorageInfo
- External: Foundation

**Usage & Callers**
- Implemented by storage monitoring service
- Used for continuous storage observation

**Potential Issues / Smells**
- No monitoring interval configuration
- No event subscription mechanism

**Unused / Dead Code**
- None identified

---

### Protocols/Voice/

#### `Core/Protocols/Voice/WakeWordDetector.swift`

**Role / Responsibility**
- Protocol for wake word detection in audio streams
- Supports both buffered and streaming audio
- Configurable sensitivity and wake words

**Key Types**
- `WakeWordDetector` (public protocol) - Wake word detector
- `WakeWordDetection` (public struct) - Detection result
- `WakeWordConfig` (public struct) - Configuration
- `NoiseSuppressionLevel` (public enum) - Noise suppression levels

**Key Public APIs**
- Detector:
  - `func initialize(wakeWords: [String]) async throws` - Initialize
  - `func startListening() async throws` - Start listening
  - `func stopListening() async` - Stop listening
  - `func processAudio(_ audio: Data) async -> WakeWordDetection?` - Process buffer
  - `func processStream(_ audioStream: AsyncStream<VoiceAudioChunk>) -> AsyncThrowingStream<WakeWordDetection, Error>` - Process stream
  - `var isListening: Bool`, `var wakeWords: [String]`, `var sensitivity: Float`
  - Callbacks: `onWakeWordDetected`, `onListeningStateChanged`
  - `func addWakeWord(_ word: String) async throws` - Add wake word
  - `func removeWakeWord(_ word: String) async` - Remove wake word
  - `func clearWakeWords() async` - Clear all
- Detection: wakeWord, confidence, timestamp, audioSegment, startTime, endTime, isConfirmed, duration
- Config: wakeWords, confidenceThreshold (default 0.7), continuousListening, preprocessingEnabled, noiseSuppression, modelPath, bufferSize (default 1024), sampleRate (default 16000)
- NoiseSuppressionLevel: none, low, medium, high with factor (0.0, 0.25, 0.5, 0.75)

**Important Internal Logic**
- Supports both single-shot and continuous listening
- Noise suppression with configurable levels
- Audio segment capture for confirmed detections
- Duration calculated from start/end times

**Dependencies**
- Internal: VoiceAudioChunk
- External: Foundation

**Usage & Callers**
- Implemented by wake word detection services
- Used by voice agent for wake word activation

**Potential Issues / Smells**
- Callbacks are optional - no guarantee of notification
- No multi-wake-word priority configuration
- No false positive rate tuning

**Unused / Dead Code**
- None identified

---

## ServiceRegistry/ (2 files)

### `Core/ServiceRegistry/AdapterSelectionStrategy.swift`

**Role / Responsibility**
- Strategies for selecting the best adapter from multiple candidates
- Provides default, pattern-based, and explicit framework strategies

**Key Types**
- `AdapterSelectionStrategy` (public protocol) - Strategy protocol
- `DefaultAdapterSelectionStrategy` (public struct) - Prefer model's preferred/compatible frameworks
- `PatternBasedAdapterSelectionStrategy` (public struct) - Pattern matching on model ID
- `ExplicitFrameworkStrategy` (public struct) - Always prefer specific framework

**Key Public APIs**
- Protocol: `func selectAdapter(from candidates: [UnifiedFrameworkAdapter], for model: ModelInfo, modality: FrameworkModality) -> UnifiedFrameworkAdapter?`
- DefaultAdapterSelectionStrategy: Priority order - preferred framework, compatible frameworks, first available
- PatternBasedAdapterSelectionStrategy: `init(patterns: [String: LLMFramework])` - e.g., ["whisper": .whisperKit]
- ExplicitFrameworkStrategy: `init(preferredFramework: LLMFramework)` - Always prefer specified framework

**Important Internal Logic**
- Default strategy:
  1. Model's preferredFramework
  2. compatibleFrameworks in order
  3. First available adapter
- Pattern strategy:
  - Matches lowercase model ID against patterns
  - Falls back to default strategy if no match
- Explicit strategy:
  - Forces specific framework
  - Falls back to first available if preferred not found

**Dependencies**
- Internal: UnifiedFrameworkAdapter, ModelInfo, FrameworkModality, LLMFramework
- External: Foundation

**Usage & Callers**
- Used by UnifiedServiceRegistry for adapter selection
- Can be customized for specific selection logic

**Potential Issues / Smells**
- Pattern matching is case-insensitive substring - could have false positives
- No priority weighting in default strategy

**Unused / Dead Code**
- None identified

---

### `Core/ServiceRegistry/UnifiedServiceRegistry.swift`

**Role / Responsibility**
- Central registry for managing multiple adapters per modality
- Supports adapter priority and automatic selection
- Maintains backward compatibility with framework-based lookup

**Key Types**
- `UnifiedServiceRegistry` (public actor) - Thread-safe adapter registry
- `RegisteredAdapter` (private struct) - Wrapper with priority and registration date

**Key Public APIs**
- `func register(_ adapter: UnifiedFrameworkAdapter, priority: Int = 100)` - Register adapter with priority
- `func findAdapters(for model: ModelInfo, modality: FrameworkModality) -> [UnifiedFrameworkAdapter]` - Find all compatible adapters
- `func findBestAdapter(for model: ModelInfo, modality: FrameworkModality) -> UnifiedFrameworkAdapter?` - Find best adapter
- `func getAdapter(for framework: LLMFramework) -> UnifiedFrameworkAdapter?` - Backward compatible lookup
- `func getFrameworks(for modality: FrameworkModality) -> [LLMFramework]` - Get registered frameworks
- `func getAllAdapters() -> [UnifiedFrameworkAdapter]` - Get all adapters

**Important Internal Logic**
- Stores adapters in two maps:
  - `adaptersByModality: [FrameworkModality: [RegisteredAdapter]]` - Primary storage
  - `adaptersByFramework: [LLMFramework: UnifiedFrameworkAdapter]` - Backward compat
- Adapters sorted by priority (higher first), then registration date (earlier first)
- Duplicates removed when re-registering same framework
- `findBestAdapter` uses same priority order as DefaultAdapterSelectionStrategy

**Dependencies**
- Internal: UnifiedFrameworkAdapter, ModelInfo, FrameworkModality, LLMFramework
- External: Foundation

**Usage & Callers**
- Used by component initialization to find adapters
- Populated by adapter registration during SDK setup

**Potential Issues / Smells**
- Two storage mechanisms increase complexity
- No unregister method
- Priority system not documented - magic number 100 as default

**Unused / Dead Code**
- None identified

---

## Types/ (1 file)

### `Core/Types/TelemetryEventType.swift`

**Role / Responsibility**
- Enumeration of standard telemetry event types
- Covers model, generation, STT, TTS, and system events

**Key Types**
- `TelemetryEventType` (public enum) - Standard event types

**Key Public APIs**
- Model events: modelLoaded, modelLoadFailed, modelUnloaded
- LLM generation: generationStarted, generationCompleted, generationFailed
- STT events: sttModelLoaded, sttModelLoadFailed, sttTranscriptionStarted, sttTranscriptionCompleted, sttTranscriptionFailed, sttStreamingUpdate
- TTS events: ttsModelLoaded, ttsModelLoadFailed, ttsSynthesisStarted, ttsSynthesisCompleted, ttsSynthesisFailed
- System events: error, performance, memory, custom

**Important Internal Logic**
- Raw values are string event names
- Codable for serialization

**Dependencies**
- External: Foundation

**Usage & Callers**
- Used by telemetry services for event categorization
- Used by analytics tracking

**Potential Issues / Smells**
- No VLM, Wake Word, or Speaker Diarization event types
- Custom event is generic - no type safety

**Unused / Dead Code**
- None identified

---

## Root Files (2 files)

### `Core/ModelLifecycleManager.swift`

**Role / Responsibility**
- Centralized tracker for model lifecycle across all modalities
- Maintains state of loaded models with framework and memory info
- Publishes lifecycle events via Combine
- Caches service instances for reuse (LLM, STT, TTS)

**Key Types**
- `ModelLoadState` (public enum) - Model states: notLoaded, loading(progress), loaded, unloading, error(String)
- `LoadedModelState` (public struct) - Non-Sendable state with service references
- `Modality` (public enum) - Modalities: llm, stt, tts, vlm, speakerDiarization, wakeWord
- `ModelLifecycleEvent` (public enum) - Lifecycle events
- `ModelLifecycleTracker` (public final class, @MainActor, ObservableObject) - Main tracker singleton

**Key Public APIs**
- `@Published var modelsByModality: [Modality: LoadedModelState]` - Current models by modality
- `let lifecycleEvents: PassthroughSubject<ModelLifecycleEvent, Never>` - Event publisher
- `func loadedModel(for modality: Modality) -> LoadedModelState?` - Get loaded model
- `func isModelLoaded(for modality: Modality) -> Bool` - Check if loaded
- `func allLoadedModels() -> [LoadedModelState]` - Get all loaded
- `func isModelLoaded(_ modelId: String) -> Bool` - Check by ID
- State management (internal):
  - `func modelWillLoad(modelId:modelName:framework:modality:)` - Start loading
  - `func updateLoadProgress(modelId:modality:progress:)` - Update progress
  - `func modelDidLoad(modelId:modelName:framework:modality:memoryUsage:llmService:sttService:ttsService:)` - Finish loading
  - `func modelLoadFailed(modelId:modality:error:)` - Load failed
  - `func modelWillUnload(modelId:modality:)` - Start unloading
  - `func modelDidUnload(modelId:modality:)` - Finish unloading
- Service access:
  - `func llmService(for modelId: String) -> (any LLMService)?` - Get cached LLM service
  - `func sttService(for modelId: String) -> (any STTService)?` - Get cached STT service
  - `func ttsService(for modelId: String) -> (any TTSService)?` - Get cached TTS service
- `func clearAll()` - Clear all models

**Important Internal Logic**
- MainActor ensures UI-safe access
- ObservableObject for SwiftUI integration
- Singleton pattern via `shared` instance
- Service caching eliminates redundant model loads
- Progress tracking during loading
- Event publishing for all state transitions
- LoadedModelState stores service instances alongside metadata

**Dependencies**
- Internal: LLMFramework, LLMService, STTService, TTSService, SDKLogger
- External: Foundation, Combine

**Usage & Callers**
- Used by all components for lifecycle tracking
- UI observes published properties for state display
- Services check for cached instances before loading

**Potential Issues / Smells**
- LoadedModelState is non-Sendable due to service references - limits concurrency
- Only supports one model per modality - can't track multiple LLMs
- Service caching only for LLM/STT/TTS - not VLM, Wake Word, Speaker Diarization
- No memory limit enforcement
- No automatic cleanup of unused models

**Unused / Dead Code**
- VLM, Speaker Diarization, Wake Word modalities defined but no service caching

---

### `Core/ModuleRegistry.swift`

**Role / Responsibility**
- Central registry for external AI module implementations
- Plugin-based architecture for optional dependencies
- Provider registration with priority support
- Thread-safe model info caching

**Key Types**
- `ModelInfoCache` (public final class, Sendable) - Thread-safe model info cache using OSAllocatedUnfairLock
- `ModuleRegistry` (public final class, @MainActor) - Main registry singleton
- `PrioritizedProvider<Provider>` (private struct) - Provider wrapper with priority
- Service provider protocols: TTSServiceProvider, VLMServiceProvider, SpeakerDiarizationServiceProvider
- `AutoRegisteringModule` (public protocol) - Protocol for auto-registration

**Key Public APIs**
- ModelInfoCache:
  - `func cacheModels(_ models: [ModelInfo])` - Cache models
  - `func modelInfo(for modelId: String) -> ModelInfo?` - Get cached info
  - `func clear()` - Clear cache
  - `func contains(_ modelId: String) -> Bool` - Check existence
- ModuleRegistry registration:
  - `func registerSTT(_ provider: STTServiceProvider, priority: Int = 100)` - Register STT with priority
  - `func registerLLM(_ provider: LLMServiceProvider, priority: Int = 100)` - Register LLM
  - `func registerTTS(_ provider: TTSServiceProvider, priority: Int = 100)` - Register TTS
  - `func registerSpeakerDiarization(_ provider: SpeakerDiarizationServiceProvider)` - Register speaker diarization
  - `func registerVLM(_ provider: VLMServiceProvider)` - Register VLM
  - `func registerWakeWord(_ provider: WakeWordServiceProvider)` - Register wake word
- Provider access:
  - `func sttProvider(for modelId: String?) -> STTServiceProvider?` - Get STT provider (highest priority match)
  - `func allSTTProviders(for modelId: String?) -> [STTServiceProvider]` - Get all STT providers
  - Same for LLM, TTS (with priority), and single-provider access for Speaker Diarization, VLM, Wake Word
- Availability:
  - `var hasSTT: Bool`, `var hasLLM: Bool`, `var hasTTS: Bool`, `var hasSpeakerDiarization: Bool`, `var hasVLM: Bool`, `var hasWakeWord: Bool`
  - `var registeredModules: [String]` - List of module names

**Important Internal Logic**
- ModelInfoCache uses OSAllocatedUnfairLock (Swift 6) for efficient thread-safe access
- Providers sorted by priority (higher first) after registration
- Priority system for STT, LLM, TTS; first-match for others
- MainActor isolation for ModuleRegistry
- Provider filtering by modelId via canHandle()
- Automatic sorting maintains priority order

**Dependencies**
- Internal: ModelInfo, STTServiceProvider, LLMServiceProvider, SpeakerDiarizationServiceProvider, VLMServiceProvider, WakeWordServiceProvider, TTSServiceProvider, SpeakerDiarizationService, TTSConfiguration, TTSService, VLMConfiguration, VLMService, SpeakerDiarizationConfiguration
- External: Foundation, os (OSAllocatedUnfairLock)

**Usage & Callers**
- Used by components to find service providers
- External modules register on app launch
- ModelInfoCache used by adapters for synchronous model info lookup

**Potential Issues / Smells**
- Speaker Diarization, VLM, Wake Word don't support priority
- No unregister method
- Print statements instead of proper logging
- AutoRegisteringModule protocol defined but no implementation shown
- STTServiceProvider, LLMServiceProvider defined elsewhere but TTSServiceProvider defined here

**Unused / Dead Code**
- AutoRegisteringModule protocol and example implementation in comments

---

## Summary

### Key Architectural Patterns

1. **Actor-based Concurrency**: Component initialization, service registries, configuration services use actors for thread-safety
2. **Protocol-Oriented Design**: Heavy use of protocols for abstraction (Component, Service Providers, Adapters)
3. **Plugin Architecture**: ModuleRegistry enables optional dependencies via provider registration
4. **Composite Configuration**: ConfigurationData composes multiple sub-configurations
5. **Observer Pattern**: Lifecycle events, analytics events, model lifecycle events
6. **Strategy Pattern**: Adapter selection, download strategies, storage strategies
7. **Singleton Pattern**: ModelLifecycleTracker, ModuleRegistry, ModelInfoCache
8. **Type Erasure**: Component protocols use `any`, adapters return `Any` for services

### Cross-Cutting Concerns

1. **Thread Safety**: Actors, OSAllocatedUnfairLock, MainActor isolation
2. **Sendable Conformance**: Most data models are Sendable for concurrency
3. **Database Persistence**: GRDB integration for ConfigurationData and ModelInfo
4. **Event Bus**: Centralized event publishing for initialization, lifecycle changes
5. **Service Caching**: ModelLifecycleTracker caches service instances
6. **Priority-based Selection**: Adapters and providers support priority

### Common Issues & Technical Debt

1. **Type Safety**: Extensive use of type erasure (`Any`, `any`) reduces compile-time safety
2. **Magic Values**: Hard-coded thresholds (20% battery, 100 default priority, 1GB cache)
3. **Incomplete Implementations**: VLM, Embedding, Wake Word components throw "not implemented"
4. **Inconsistent Provider APIs**: Some support priority (STT/LLM/TTS), others don't
5. **Security Concerns**: API keys in configuration without encryption
6. **Naming Confusion**: LLMFramework includes non-LLM frameworks; ModelInfo.memoryRequired vs ModelInfoMetadata.minMemory
7. **Limited Error Recovery**: No retry logic, no fallback mechanisms
8. **String-based Types**: Custom rules as [String: String], search as String - limits expressiveness
9. **Legacy Compatibility**: ComponentInitializer exists solely for backward compat

### Recommendations

1. **Consolidate Provider APIs**: Unify priority support across all provider types
2. **Improve Type Safety**: Use concrete types instead of `Any` where possible
3. **Complete Implementations**: Finish VLM, Embedding, Wake Word components
4. **Add Configuration Validation**: Validate ranges, formats, required fields
5. **Enhance Error Handling**: Add retry logic, fallback strategies, circuit breakers
6. **Security Hardening**: Encrypt sensitive configuration data, use keychain for API keys
7. **Remove Magic Values**: Make all thresholds configurable
8. **Improve Documentation**: Add inline docs for complex protocols
9. **Deprecate Legacy APIs**: Create migration path for ComponentInitializer users
10. **Add Telemetry**: Track adapter selection decisions, component initialization failures

---

**Total Files Analyzed**: 37 files across 10 subdirectories
**Documentation Coverage**: 100% of Core module files
