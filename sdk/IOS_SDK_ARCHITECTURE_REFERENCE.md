# iOS SDK Architecture Reference
**For Kotlin SDK Alignment**

**Generated:** 2025-10-20
**Purpose:** Comprehensive iOS SDK architecture documentation to serve as SOURCE OF TRUTH for Kotlin Multiplatform SDK development

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Package Structure Overview](#package-structure-overview)
3. [Infrastructure Pattern](#infrastructure-pattern)
4. [Core Architecture Principles](#core-architecture-principles)
5. [Component Architecture](#component-architecture)
6. [Protocol-Driven Design](#protocol-driven-design)
7. [Service Container & Dependency Injection](#service-container--dependency-injection)
8. [Event System Architecture](#event-system-architecture)
9. [Module Registry Pattern](#module-registry-pattern)
10. [Translation Guide: iOS to Kotlin](#translation-guide-ios-to-kotlin)
11. [Critical Implementation Patterns](#critical-implementation-patterns)

---

## Executive Summary

The iOS SDK is a **production-ready, feature-complete AI SDK** with:
- **224 Swift files**, ~33,191 lines of code
- **8 major components**: STT, TTS, LLM, VAD, Voice Agent, Wake Word, Speaker Diarization, VLM
- **Clean architecture** with clear separation of concerns
- **Protocol-oriented design** throughout
- **Event-driven communication** via centralized EventBus
- **Plugin architecture** via ModuleRegistry
- **Comprehensive infrastructure** for platform abstraction

**Key Insight for Kotlin SDK:**
The iOS SDK demonstrates a mature architecture where:
1. **ALL business logic lives in Core/ and Capabilities/**
2. **Platform-specific code is isolated in Infrastructure/**
3. **Protocols define contracts, implementations live in platform modules**
4. **Component-based architecture with lifecycle management**

---

## Package Structure Overview

### High-Level Organization

```
Sources/RunAnywhere/
├── Core/                    # Core architecture & protocols
│   ├── Components/          # Base component classes
│   ├── Protocols/           # All protocol definitions
│   ├── Models/              # Core data models
│   ├── Initialization/      # Initialization system
│   ├── ServiceRegistry/     # Adapter registry
│   ├── ModuleRegistry.swift # Plugin system
│   └── Types/               # Common types
│
├── Components/              # AI component implementations
│   ├── STT/                 # Speech-to-text
│   ├── TTS/                 # Text-to-speech
│   ├── LLM/                 # Language models
│   ├── VAD/                 # Voice activity detection
│   ├── VoiceAgent/          # Pipeline orchestration
│   ├── WakeWord/            # Wake word detection
│   ├── SpeakerDiarization/  # Speaker identification
│   └── VLM/                 # Vision language models
│
├── Capabilities/            # Cross-cutting capabilities
│   ├── TextGeneration/      # Text generation services
│   ├── Voice/               # Voice processing
│   ├── Memory/              # Memory management
│   ├── ModelLoading/        # Model loading
│   ├── Registry/            # Model registry
│   ├── Routing/             # On-device/cloud routing
│   ├── DeviceCapability/    # Hardware detection
│   ├── StructuredOutput/    # JSON schema validation
│   └── Analytics/           # Analytics services
│
├── Data/                    # Data layer
│   ├── Network/             # HTTP client & auth
│   ├── Storage/             # Database & file storage
│   ├── Repositories/        # Repository pattern
│   ├── DataSources/         # Local & remote data sources
│   ├── Services/            # Data services
│   ├── Sync/                # Sync coordinator
│   └── Models/              # Data models
│
├── Foundation/              # Foundation services
│   ├── DependencyInjection/ # ServiceContainer
│   ├── Logging/             # Logging system
│   ├── Analytics/           # Analytics queue
│   ├── Security/            # Keychain manager
│   ├── DeviceIdentity/      # Device management
│   ├── Configuration/       # Constants
│   ├── ErrorTypes/          # Error definitions
│   ├── Context/             # Execution scope
│   └── FileOperations/      # File utilities
│
├── Public/                  # Public API
│   ├── RunAnywhere.swift    # Main entry point
│   ├── Extensions/          # Public API extensions
│   ├── Events/              # Event system
│   ├── Models/              # Public models
│   ├── Configuration/       # Public configuration
│   ├── Errors/              # Public errors
│   ├── StructuredOutput/    # Generatable protocol
│   └── Utilities/           # Public utilities
│
└── Infrastructure/          # Platform-specific implementations
    └── Voice/
        └── Platform/
            ├── iOSAudioSession.swift   # iOS audio handling
            └── macOSAudioSession.swift # macOS audio handling
```

### Key Insights

1. **Core/** - All protocols and base classes (platform-agnostic contracts)
2. **Components/** - AI capabilities with protocol-based services
3. **Capabilities/** - Cross-cutting concerns (memory, routing, analytics)
4. **Data/** - Clean data layer with repository pattern
5. **Foundation/** - Infrastructure services (DI, logging, security)
6. **Public/** - Clean public API surface
7. **Infrastructure/** - Platform-specific implementations

---

## Infrastructure Pattern

### What is Infrastructure/?

The `Infrastructure/` folder contains **platform-specific implementations** that abstract away OS-level APIs.

**Current Structure:**
```
Infrastructure/
└── Voice/
    └── Platform/
        ├── iOSAudioSession.swift   (178 lines)
        └── macOSAudioSession.swift (227 lines)
```

### iOS Audio Session Example

```swift
// Infrastructure/Voice/Platform/iOSAudioSession.swift
#if os(iOS) || os(tvOS) || os(watchOS)
import AVFoundation

public class IOSAudioSession {
    private let audioSession = AVAudioSession.sharedInstance()

    /// Configure audio session for voice processing
    public func configure(for mode: VoiceProcessingMode) throws {
        let category: AVAudioSession.Category
        let options: AVAudioSession.CategoryOptions

        switch mode {
        case .recording:
            category = .record
            options = [.allowBluetooth]
        case .playback:
            category = .playback
            options = [.allowBluetooth, .allowAirPlay]
        case .conversation:
            category = .playAndRecord
            options = [.defaultToSpeaker, .allowBluetooth, .duckOthers]
        }

        try audioSession.setCategory(category, mode: .voiceChat, options: options)
        try audioSession.setPreferredSampleRate(16000)
        try audioSession.setPreferredIOBufferDuration(0.005)
    }

    public func activate() throws { /* ... */ }
    public func deactivate() throws { /* ... */ }
    public func requestMicrophonePermission() async -> Bool { /* ... */ }
    public var hasMicrophonePermission: Bool { /* ... */ }
}
#endif
```

### macOS Audio Session Example

```swift
// Infrastructure/Voice/Platform/macOSAudioSession.swift
#if os(macOS)
import AVFoundation

public class MacOSAudioSession {
    // macOS-specific audio handling
    public func configure(for mode: VoiceProcessingMode) throws {
        // Different implementation for macOS
    }
}
#endif
```

### Pattern Translation to Kotlin

**Kotlin Multiplatform Equivalent:**

```kotlin
// commonMain/kotlin/com/runanywhere/sdk/infrastructure/voice/AudioSession.kt
expect class AudioSession() {
    suspend fun configure(mode: VoiceProcessingMode)
    suspend fun activate()
    suspend fun deactivate()
    suspend fun requestMicrophonePermission(): Boolean
    val hasMicrophonePermission: Boolean
}

// androidMain/kotlin/com/runanywhere/sdk/infrastructure/voice/AudioSession.android.kt
actual class AudioSession {
    private val audioManager = context.getSystemService(AudioManager::class.java)

    actual suspend fun configure(mode: VoiceProcessingMode) {
        // Android-specific implementation
        when (mode) {
            VoiceProcessingMode.RECORDING -> {
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            }
            // ...
        }
    }
    // ...
}

// iosMain/kotlin/com/runanywhere/sdk/infrastructure/voice/AudioSession.ios.kt
actual class AudioSession {
    actual suspend fun configure(mode: VoiceProcessingMode) {
        // iOS-specific implementation (if needed from Kotlin)
    }
}

// jvmMain/kotlin/com/runanywhere/sdk/infrastructure/voice/AudioSession.jvm.kt
actual class AudioSession {
    actual suspend fun configure(mode: VoiceProcessingMode) {
        // JVM desktop implementation
    }
}
```

**Key Principle:**
- **Protocol/Interface in commonMain** (or Core/ equivalent)
- **expect class in commonMain** for platform-specific implementations
- **actual class in each platform module** (androidMain, iosMain, jvmMain)

---

## Core Architecture Principles

### 1. Protocol-Oriented Design

**Every service has a protocol:**
```swift
// Protocol in Core/
public protocol STTService: AnyObject {
    func initialize(modelPath: String?) async throws
    func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult
    func streamTranscribe<S: AsyncSequence>(...) async throws -> STTTranscriptionResult
    var isReady: Bool { get }
    var currentModel: String? { get }
    func cleanup() async
}

// Implementation registered via ModuleRegistry
class WhisperKitSTTService: STTService {
    // WhisperKit-specific implementation
}
```

### 2. Component-Based Architecture

**All components extend BaseComponent:**
```swift
// Core/Components/BaseComponent.swift
@MainActor
open class BaseComponent<TService: AnyObject>: Component {
    public private(set) var state: ComponentState = .notInitialized
    public private(set) var service: TService?
    public let configuration: any ComponentConfiguration
    public weak var serviceContainer: ServiceContainer?
    public let eventBus: EventBus = EventBus.shared

    // Lifecycle methods
    public func initialize() async throws {
        updateState(.initializing)
        try configuration.validate()
        service = try await createService()
        try await initializeService()
        updateState(.ready)
        eventBus.publish(ComponentInitializationEvent.componentReady(...))
    }

    open func createService() async throws -> TService {
        fatalError("Override in subclass")
    }

    open func initializeService() async throws {
        // Optional override
    }

    public func cleanup() async throws {
        try await performCleanup()
        service = nil
        state = .notInitialized
    }
}
```

### 3. Event-Driven Communication

**EventBus is the single source of events:**
```swift
// Public/Events/EventBus.swift
public final class EventBus {
    public static let shared = EventBus()

    // Typed event publishers
    private let componentSubject = PassthroughSubject<ComponentInitializationEvent, Never>()
    private let generationSubject = PassthroughSubject<SDKGenerationEvent, Never>()
    private let voiceSubject = PassthroughSubject<SDKVoiceEvent, Never>()

    public var componentEvents: AnyPublisher<ComponentInitializationEvent, Never> {
        componentSubject.eraseToAnyPublisher()
    }

    public func publish(_ event: ComponentInitializationEvent) {
        componentSubject.send(event)
    }
}

// Usage
EventBus.shared.publish(ComponentInitializationEvent.componentReady(component: .stt))
```

### 4. Dependency Injection via ServiceContainer

```swift
// Foundation/DependencyInjection/ServiceContainer.swift
public class ServiceContainer {
    public static let shared = ServiceContainer()

    // Lazy initialization
    private(set) lazy var modelRegistry: ModelRegistry = { RegistryService() }()
    private(set) lazy var memoryService: MemoryManager = { MemoryService(...) }()
    private(set) lazy var routingService: RoutingService = { RoutingService(...) }()

    // Bootstrap modes
    public func bootstrap() async throws {
        // Full production initialization
    }

    public func bootstrapDevelopmentMode() async throws {
        // Local-only mode
    }

    public func setupLocalServices(with params: SDKInitParams) throws {
        // Fast local setup
    }
}
```

### 5. Plugin Architecture via ModuleRegistry

```swift
// Core/ModuleRegistry.swift
@MainActor
public final class ModuleRegistry {
    public static let shared = ModuleRegistry()

    // Priority-based provider storage
    private struct PrioritizedProvider<Provider> {
        let provider: Provider
        let priority: Int
    }

    private var sttProviders: [PrioritizedProvider<STTServiceProvider>] = []
    private var llmProviders: [PrioritizedProvider<LLMServiceProvider>] = []

    // Registration with priority
    public func registerSTT(_ provider: STTServiceProvider, priority: Int = 100) {
        let prioritizedProvider = PrioritizedProvider(provider: provider, priority: priority)
        sttProviders.append(prioritizedProvider)
        sttProviders.sort { $0.priority > $1.priority }
    }

    // Provider lookup (highest priority first)
    public func sttProvider(for modelId: String? = nil) -> STTServiceProvider? {
        if let modelId = modelId {
            return sttProviders.first { $0.provider.canHandle(modelId: modelId) }?.provider
        }
        return sttProviders.first?.provider
    }
}
```

---

## Component Architecture

### Component Lifecycle

**State Machine:**
```
NOT_INITIALIZED → CHECKING → INITIALIZING → READY → ERROR
                                              ↓
                                           CLEANUP → NOT_INITIALIZED
```

**Component States:**
```swift
public enum ComponentState: String, Sendable {
    case notInitialized = "not_initialized"
    case checking = "checking"
    case initializing = "initializing"
    case ready = "ready"
    case failed = "failed"
}
```

### Component Protocol

```swift
// Core/Protocols/Component/Component.swift
public protocol Component: AnyObject, Sendable {
    static var componentType: SDKComponent { get }
    var state: ComponentState { get }
    var parameters: any ComponentInitParameters { get }
    func initialize(with parameters: any ComponentInitParameters) async throws
    func cleanup() async throws
    var isReady: Bool { get }
    func transitionTo(state: ComponentState) async
}
```

### Component Configuration Pattern

**Every component has:**
1. **Configuration struct** (implements `ComponentConfiguration`)
2. **Input model** (implements `ComponentInput`)
3. **Output model** (implements `ComponentOutput`)
4. **Service protocol**
5. **Service provider protocol**

**Example: STT Component**

```swift
// 1. Configuration
public struct STTConfiguration: ComponentConfiguration, ComponentInitParameters {
    public var componentType: SDKComponent { .stt }
    public let modelId: String?
    public let language: String
    public let sampleRate: Int
    public let enablePunctuation: Bool
    // ...

    public func validate() throws {
        // Validation logic
    }
}

// 2. Input
public struct STTInput: ComponentInput {
    public let audioData: Data
    public let options: STTOptions

    public func validate() throws {
        guard !audioData.isEmpty else {
            throw STTError.insufficientAudioData
        }
    }
}

// 3. Output
public struct STTOutput: ComponentOutput {
    public let transcript: String
    public let confidence: Float
    public let segments: [STTSegment]
    public let timestamp: Date
}

// 4. Service Protocol
public protocol STTService: AnyObject {
    func initialize(modelPath: String?) async throws
    func transcribe(audioData: Data, options: STTOptions) async throws -> STTTranscriptionResult
    var isReady: Bool { get }
    func cleanup() async
}

// 5. Service Provider Protocol
public protocol STTServiceProvider {
    func createSTTService(configuration: STTConfiguration) async throws -> STTService
    func canHandle(modelId: String?) -> Bool
    var name: String { get }
}
```

### Component Implementation Pattern

```swift
// Components/STT/STTComponent.swift
@MainActor
public final class STTComponent: BaseComponent<STTService> {
    public override class var componentType: SDKComponent { .stt }

    private let sttConfig: STTConfiguration

    public init(configuration: STTConfiguration, serviceContainer: ServiceContainer? = nil) {
        self.sttConfig = configuration
        super.init(configuration: configuration, serviceContainer: serviceContainer)
    }

    // Service creation via ModuleRegistry
    public override func createService() async throws -> STTService {
        guard let provider = ModuleRegistry.shared.sttProvider(for: sttConfig.modelId) else {
            throw STTError.noVoiceServiceAvailable
        }
        return try await provider.createSTTService(configuration: sttConfig)
    }

    // Public API
    public func transcribe(_ input: STTInput) async throws -> STTOutput {
        try ensureReady()
        guard let service = service else {
            throw STTError.serviceNotInitialized
        }

        let result = try await service.transcribe(
            audioData: input.audioData,
            options: input.options
        )

        return STTOutput(
            transcript: result.transcript,
            confidence: result.confidence,
            segments: result.segments,
            timestamp: Date()
        )
    }
}
```

---

## Protocol-Driven Design

### Core Protocol Hierarchy

```
Component (base)
├── LifecycleManaged
├── ModelBasedComponent
├── ServiceComponent
└── PipelineComponent
```

**Protocol Definitions:**

```swift
// Base Component Protocol
public protocol Component: AnyObject, Sendable {
    static var componentType: SDKComponent { get }
    var state: ComponentState { get }
    var parameters: any ComponentInitParameters { get }
    func initialize(with parameters: any ComponentInitParameters) async throws
    func cleanup() async throws
    var isReady: Bool { get }
    func transitionTo(state: ComponentState) async
}

// Lifecycle Management
public protocol LifecycleManaged: Component {
    func willInitialize() async throws
    func didInitialize() async
    func willCleanup() async
    func didCleanup() async
    func handleMemoryPressure() async
}

// Model-Based Components
public protocol ModelBasedComponent: Component {
    var modelId: String? { get }
    var isModelLoaded: Bool { get }
    func loadModel(modelId: String) async throws
    func unloadModel() async throws
    func getModelMemoryUsage() async -> Int64
}

// Service Components
public protocol ServiceComponent: Component {
    associatedtype ServiceType
    func getService() -> ServiceType?
    func createService() async throws -> ServiceType
}

// Pipeline Components
public protocol PipelineComponent: Component {
    associatedtype Input
    associatedtype Output
    func process(_ input: Input) async throws -> Output
    func canConnectTo(_ component: any Component) -> Bool
}
```

### Service Protocols

**All service protocols follow this pattern:**

```swift
// Memory Management
public protocol MemoryManager {
    func requestMemory(_ bytes: Int64, priority: Int) async throws -> Bool
    func releaseMemory(_ bytes: Int64)
    func getCurrentUsage() -> MemoryUsage
    func handlePressure(_ level: MemoryPressureLevel) async
}

// Model Registry
public protocol ModelRegistry {
    func register(_ model: ModelInfo) async throws
    func getModel(id: String) async -> ModelInfo?
    func listModels(category: ModelCategory?) async -> [ModelInfo]
    func search(criteria: ModelCriteria) async -> [ModelInfo]
}

// Hardware Detection
public protocol HardwareDetector {
    func detect() async -> HardwareCapabilities
    func supports(_ requirement: HardwareRequirement) -> Bool
}

// Storage Analysis
public protocol StorageAnalyzer {
    func analyze() async -> StorageInfo
    func getRecommendations() async -> [StorageRecommendation]
    func checkAvailability(for size: Int64) async -> StorageAvailability
}
```

---

## Service Container & Dependency Injection

### ServiceContainer Structure

**The ServiceContainer is the heart of dependency injection:**

```swift
// Foundation/DependencyInjection/ServiceContainer.swift
public class ServiceContainer {
    public static let shared = ServiceContainer()

    // MARK: - Core Services
    private(set) lazy var modelRegistry: ModelRegistry = { RegistryService() }()
    internal let adapterRegistry = AdapterRegistry()

    // MARK: - Capability Services
    private(set) lazy var modelLoadingService: ModelLoadingService = {
        ModelLoadingService(
            registry: modelRegistry,
            adapterRegistry: adapterRegistry,
            memoryService: memoryService
        )
    }()

    private(set) lazy var generationService: GenerationService = {
        GenerationService(
            routingService: routingService,
            modelLoadingService: modelLoadingService
        )
    }()

    private(set) lazy var streamingService: StreamingService = {
        StreamingService(
            generationService: generationService,
            modelLoadingService: modelLoadingService
        )
    }()

    private(set) lazy var voiceCapabilityService: VoiceCapabilityService = {
        VoiceCapabilityService()
    }()

    // MARK: - Infrastructure
    private(set) lazy var hardwareManager: HardwareCapabilityManager = {
        HardwareCapabilityManager.shared
    }()

    private(set) lazy var memoryService: MemoryManager = {
        MemoryService(
            allocationManager: AllocationManager(),
            pressureHandler: PressureHandler(),
            cacheEviction: CacheEviction()
        )
    }()

    private(set) lazy var routingService: RoutingService = {
        RoutingService(
            costCalculator: CostCalculator(),
            resourceChecker: ResourceChecker(hardwareManager: hardwareManager)
        )
    }()

    // MARK: - Data Services (async)
    public var configurationService: ConfigurationServiceProtocol {
        get async {
            if let service = _configurationService {
                return service
            }
            let service = ConfigurationService(...)
            _configurationService = service
            return service
        }
    }

    // MARK: - Bootstrap Modes
    public func bootstrap() async throws {
        // Full production initialization with network
        try await initializeNetworkServices()
        try await initializeDataLayer()
    }

    public func bootstrapDevelopmentMode() async throws {
        // Local-only mode (no network)
        try setupLocalServices()
    }

    public func setupLocalServices(with params: SDKInitParams) throws {
        // Fast local setup (no async)
        // Initialize logger, file manager, database
    }
}
```

### Initialization Modes

**1. Fast Local Initialization (Default)**
```swift
// Used by RunAnywhere.initialize()
try serviceContainer.setupLocalServices(with: params)
// No network calls, returns immediately
```

**2. Full Bootstrap (Production)**
```swift
// Used when network is needed
try await serviceContainer.bootstrap()
// Initializes network, auth, sync
```

**3. Development Mode**
```swift
// For local development
try await serviceContainer.bootstrapDevelopmentMode()
// Uses mock services, no auth
```

### Lazy vs Eager Initialization

**Lazy (Preferred):**
```swift
private(set) lazy var memoryService: MemoryManager = {
    MemoryService(
        allocationManager: AllocationManager(),
        pressureHandler: PressureHandler(),
        cacheEviction: CacheEviction()
    )
}()
```

**Async Lazy (For Network Services):**
```swift
private var _configurationService: ConfigurationService?
public var configurationService: ConfigurationServiceProtocol {
    get async {
        if let service = _configurationService {
            return service
        }
        let service = ConfigurationService(...)
        _configurationService = service
        return service
    }
}
```

---

## Event System Architecture

### EventBus Design

**Centralized, type-safe event distribution:**

```swift
// Public/Events/EventBus.swift
public final class EventBus: @unchecked Sendable {
    public static let shared = EventBus()

    // Typed event subjects
    private let componentSubject = PassthroughSubject<ComponentInitializationEvent, Never>()
    private let generationSubject = PassthroughSubject<SDKGenerationEvent, Never>()
    private let voiceSubject = PassthroughSubject<SDKVoiceEvent, Never>()
    private let modelSubject = PassthroughSubject<SDKModelEvent, Never>()

    // Public publishers
    public var componentEvents: AnyPublisher<ComponentInitializationEvent, Never> {
        componentSubject.eraseToAnyPublisher()
    }

    public var generationEvents: AnyPublisher<SDKGenerationEvent, Never> {
        generationSubject.eraseToAnyPublisher()
    }

    // Publishing
    public func publish(_ event: ComponentInitializationEvent) {
        componentSubject.send(event)
        allEventsSubject.send(event) // Also publish to all events
    }
}
```

### Event Types

**Component Initialization Events:**
```swift
public enum ComponentInitializationEvent: SDKEvent {
    case componentChecking(component: SDKComponent, modelId: String?)
    case componentInitializing(component: SDKComponent, modelId: String?)
    case componentReady(component: SDKComponent, modelId: String?)
    case componentFailed(component: SDKComponent, error: Error)
    case componentStateChanged(component: SDKComponent, oldState: ComponentState, newState: ComponentState)
}
```

**Generation Events:**
```swift
public enum SDKGenerationEvent: SDKEvent {
    case generationStarted(modelId: String)
    case generationTokenReceived(token: String, metadata: [String: Any])
    case generationCompleted(result: GenerationResult)
    case generationFailed(error: Error)
}
```

**Voice Events:**
```swift
public enum SDKVoiceEvent: SDKEvent {
    case pipelineStarted
    case speechDetected
    case transcriptionPartial(text: String)
    case transcriptionFinal(text: String)
    case responseGenerated(text: String)
    case audioGenerated(data: Data)
    case pipelineCompleted
}
```

### Event Subscription Pattern

```swift
// Subscribe to component events
var cancellables = Set<AnyCancellable>()

EventBus.shared.componentEvents
    .sink { event in
        switch event {
        case .componentReady(let component, _):
            print("\(component) is ready")
        case .componentFailed(let component, let error):
            print("\(component) failed: \(error)")
        default:
            break
        }
    }
    .store(in: &cancellables)

// Filter specific events
EventBus.shared.componentEvents
    .compactMap { event -> String? in
        if case .componentReady(let component, let modelId) = event {
            return "\(component) ready with model: \(modelId ?? "default")"
        }
        return nil
    }
    .sink { message in
        print(message)
    }
    .store(in: &cancellables)
```

---

## Module Registry Pattern

### Plugin Architecture

**ModuleRegistry enables external implementations:**

```swift
// Core/ModuleRegistry.swift
@MainActor
public final class ModuleRegistry {
    public static let shared = ModuleRegistry()

    private struct PrioritizedProvider<Provider> {
        let provider: Provider
        let priority: Int
    }

    private var sttProviders: [PrioritizedProvider<STTServiceProvider>] = []
    private var llmProviders: [PrioritizedProvider<LLMServiceProvider>] = []

    // Registration with priority
    public func registerSTT(_ provider: STTServiceProvider, priority: Int = 100) {
        let prioritized = PrioritizedProvider(provider: provider, priority: priority)
        sttProviders.append(prioritized)
        sttProviders.sort { $0.priority > $1.priority } // Highest priority first
    }

    // Provider lookup
    public func sttProvider(for modelId: String? = nil) -> STTServiceProvider? {
        if let modelId = modelId {
            return sttProviders.first { $0.provider.canHandle(modelId: modelId) }?.provider
        }
        return sttProviders.first?.provider
    }

    // Availability checks
    public var hasSTT: Bool { !sttProviders.isEmpty }
    public var hasLLM: Bool { !llmProviders.isEmpty }
}
```

### Provider Protocol Pattern

```swift
// Service Provider Protocol
public protocol STTServiceProvider {
    func createSTTService(configuration: STTConfiguration) async throws -> STTService
    func canHandle(modelId: String?) -> Bool
    var name: String { get }
}

// Example Implementation
public class WhisperKitProvider: STTServiceProvider {
    public var name: String { "WhisperKit" }

    public func canHandle(modelId: String?) -> Bool {
        guard let modelId = modelId else { return true }
        return modelId.contains("whisper")
    }

    public func createSTTService(configuration: STTConfiguration) async throws -> STTService {
        return WhisperKitSTTService(configuration: configuration)
    }
}
```

### Registration Flow

**In App Initialization:**
```swift
import RunAnywhere
import WhisperKit // External module

// Register external providers
ModuleRegistry.shared.registerSTT(WhisperKitProvider(), priority: 100)
ModuleRegistry.shared.registerLLM(LlamaProvider(), priority: 100)

// SDK components will automatically use registered providers
let sttComponent = STTComponent(configuration: STTConfiguration(modelId: "whisper-base"))
try await sttComponent.initialize()
// WhisperKitProvider is automatically selected
```

### Priority System

**Higher priority = preferred:**
```swift
// Register multiple providers
ModuleRegistry.shared.registerSTT(WhisperKitProvider(), priority: 200)  // Preferred
ModuleRegistry.shared.registerSTT(WhisperCPPProvider(), priority: 100)  // Fallback

// First provider that can handle the model is selected
let provider = ModuleRegistry.shared.sttProvider(for: "whisper-base")
// Returns WhisperKitProvider (higher priority)
```

---

## Translation Guide: iOS to Kotlin

### 1. Package Structure Mapping

**iOS → Kotlin Multiplatform**

| iOS Package | KMP Package | Location |
|-------------|-------------|----------|
| `Core/` | `core/` | `commonMain/kotlin/core/` |
| `Components/` | `components/` | `commonMain/kotlin/components/` |
| `Capabilities/` | `capabilities/` | `commonMain/kotlin/capabilities/` |
| `Data/` | `data/` | `commonMain/kotlin/data/` |
| `Foundation/` | `foundation/` | `commonMain/kotlin/foundation/` |
| `Public/` | `public/` or top-level | `commonMain/kotlin/` |
| `Infrastructure/` | `infrastructure/` | `commonMain/kotlin/infrastructure/` (expect) + platform actuals |

### 2. Protocol → Interface/Expect Pattern

**iOS Protocol:**
```swift
// Core/Protocols/Memory/MemoryManager.swift
public protocol MemoryManager {
    func requestMemory(_ bytes: Int64, priority: Int) async throws -> Bool
    func releaseMemory(_ bytes: Int64)
    func getCurrentUsage() -> MemoryUsage
}
```

**Kotlin Translation:**
```kotlin
// commonMain/kotlin/core/protocols/memory/MemoryManager.kt
interface MemoryManager {
    suspend fun requestMemory(bytes: Long, priority: Int): Boolean
    fun releaseMemory(bytes: Long)
    fun getCurrentUsage(): MemoryUsage
}
```

### 3. Platform-Specific Code

**iOS (Compiler Directives):**
```swift
#if os(iOS) || os(tvOS)
import AVFoundation

public class IOSAudioSession {
    private let audioSession = AVAudioSession.sharedInstance()
    // iOS-specific implementation
}
#endif
```

**Kotlin (expect/actual):**
```kotlin
// commonMain
expect class AudioSession() {
    suspend fun configure(mode: VoiceProcessingMode)
}

// androidMain
actual class AudioSession {
    actual suspend fun configure(mode: VoiceProcessingMode) {
        // Android AudioManager
    }
}

// iosMain (if needed)
actual class AudioSession {
    actual suspend fun configure(mode: VoiceProcessingMode) {
        // iOS AVAudioSession (via Kotlin/Native)
    }
}

// jvmMain
actual class AudioSession {
    actual suspend fun configure(mode: VoiceProcessingMode) {
        // Desktop audio (javax.sound or similar)
    }
}
```

### 4. Async/Await → Coroutines

**iOS:**
```swift
public func transcribe(audioData: Data, options: STTOptions) async throws -> STTResult {
    let result = try await service.transcribe(audioData: audioData, options: options)
    return result
}
```

**Kotlin:**
```kotlin
suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTResult = withContext(Dispatchers.IO) {
    val result = service.transcribe(audioData, options)
    result
}
```

### 5. AsyncSequence → Flow

**iOS:**
```swift
public func streamTranscribe<S: AsyncSequence>(
    audioStream: S,
    options: STTOptions,
    onPartial: @escaping (String) -> Void
) async throws -> STTResult where S.Element == Data
```

**Kotlin:**
```kotlin
fun streamTranscribe(
    audioStream: Flow<ByteArray>,
    options: STTOptions,
    onPartial: (String) -> Unit
): Flow<STTResult> = flow {
    audioStream.collect { audioData ->
        // Process and emit
    }
}
```

### 6. Combine → Flow

**iOS EventBus:**
```swift
private let componentSubject = PassthroughSubject<ComponentInitializationEvent, Never>()

public var componentEvents: AnyPublisher<ComponentInitializationEvent, Never> {
    componentSubject.eraseToAnyPublisher()
}

public func publish(_ event: ComponentInitializationEvent) {
    componentSubject.send(event)
}
```

**Kotlin EventBus:**
```kotlin
object EventBus {
    private val _componentEvents = MutableSharedFlow<ComponentInitializationEvent>()
    val componentEvents: SharedFlow<ComponentInitializationEvent> = _componentEvents.asSharedFlow()

    fun publish(event: ComponentInitializationEvent) {
        _componentEvents.tryEmit(event)
    }
}

// Usage
EventBus.componentEvents
    .filterIsInstance<ComponentInitializationEvent.ComponentReady>()
    .collect { event ->
        println("Component ${event.component} ready")
    }
```

### 7. Sendable → @Serializable (or thread-safe)

**iOS:**
```swift
public struct STTConfiguration: ComponentConfiguration, Sendable {
    public let modelId: String?
    public let language: String
}
```

**Kotlin:**
```kotlin
@Serializable
data class STTConfiguration(
    val modelId: String?,
    val language: String
) : ComponentConfiguration
```

### 8. @MainActor → Main Dispatcher

**iOS:**
```swift
@MainActor
public final class STTComponent: BaseComponent<STTService> {
    // All methods run on MainActor
}
```

**Kotlin:**
```kotlin
class STTComponent(configuration: STTConfiguration) : BaseComponent<STTService>(configuration) {
    // Use Dispatchers.Main.immediate when needed
    suspend fun initialize() = withContext(Dispatchers.Main.immediate) {
        // Initialization
    }
}
```

### 9. Lazy Initialization

**iOS:**
```swift
private(set) lazy var memoryService: MemoryManager = {
    MemoryService(
        allocationManager: AllocationManager(),
        pressureHandler: PressureHandler()
    )
}()
```

**Kotlin:**
```kotlin
val memoryService: MemoryManager by lazy {
    MemoryService(
        allocationManager = AllocationManager(),
        pressureHandler = PressureHandler()
    )
}
```

### 10. Component Structure

**iOS BaseComponent:**
```swift
@MainActor
open class BaseComponent<TService: AnyObject>: Component {
    public private(set) var state: ComponentState = .notInitialized
    public private(set) var service: TService?
    public let configuration: any ComponentConfiguration

    open func createService() async throws -> TService {
        fatalError("Override in subclass")
    }
}
```

**Kotlin BaseComponent:**
```kotlin
abstract class BaseComponent<TService : Any>(
    protected val configuration: ComponentConfiguration,
    serviceContainer: ServiceContainer? = null
) : Component {
    override var state: ComponentState = ComponentState.NOT_INITIALIZED
        protected set

    protected var service: TService? = null

    protected abstract suspend fun createService(): TService
}
```

---

## Critical Implementation Patterns

### 1. Component Initialization Pattern

**ALWAYS follow this flow:**

```kotlin
// 1. Define Configuration
data class STTConfiguration(
    val modelId: String?,
    val language: String = "en",
    val sampleRate: Int = 16000
) : ComponentConfiguration {
    override fun validate() {
        require(sampleRate > 0) { "Sample rate must be positive" }
    }
}

// 2. Define Service Protocol (in commonMain)
interface STTService {
    suspend fun initialize(modelPath: String?)
    suspend fun transcribe(audioData: ByteArray, options: STTOptions): STTTranscriptionResult
    val isReady: Boolean
    suspend fun cleanup()
}

// 3. Define Service Provider Protocol
interface STTServiceProvider {
    suspend fun createSTTService(configuration: STTConfiguration): STTService
    fun canHandle(modelId: String?): Boolean
    val name: String
}

// 4. Component Implementation
class STTComponent(configuration: STTConfiguration) : BaseComponent<STTService>(configuration) {
    override val componentType = SDKComponent.STT

    override suspend fun createService(): STTService {
        val provider = ModuleRegistry.sttProvider(configuration.modelId)
            ?: throw SDKError.ComponentNotAvailable("No STT provider available")
        return provider.createSTTService(configuration)
    }

    suspend fun transcribe(input: STTInput): STTOutput {
        ensureReady()
        val service = service ?: throw SDKError.ComponentNotReady("STT service not initialized")

        val result = service.transcribe(input.audioData, input.options)
        return STTOutput(
            transcript = result.transcript,
            confidence = result.confidence,
            timestamp = Clock.System.now()
        )
    }
}

// 5. External Provider Implementation (in external module)
class WhisperKitProvider : STTServiceProvider {
    override val name = "WhisperKit"

    override fun canHandle(modelId: String?): Boolean {
        return modelId == null || modelId.contains("whisper")
    }

    override suspend fun createSTTService(configuration: STTConfiguration): STTService {
        return WhisperKitSTTService(configuration)
    }
}
```

### 2. Event Publishing Pattern

```kotlin
// ALWAYS publish events at key lifecycle points
override suspend fun initialize() {
    updateState(ComponentState.INITIALIZING)

    try {
        // Validation
        eventBus.publish(ComponentInitializationEvent.ComponentChecking(componentType, null))
        configuration.validate()

        // Service creation
        eventBus.publish(ComponentInitializationEvent.ComponentInitializing(componentType, null))
        service = createService()

        // Ready
        updateState(ComponentState.READY)
        eventBus.publish(ComponentInitializationEvent.ComponentReady(componentType, null))
    } catch (e: Exception) {
        updateState(ComponentState.FAILED)
        eventBus.publish(ComponentInitializationEvent.ComponentFailed(componentType, e))
        throw e
    }
}
```

### 3. Provider Registration Pattern

```kotlin
// ModuleRegistry (singleton in commonMain)
object ModuleRegistry {
    private data class PrioritizedProvider<T>(
        val provider: T,
        val priority: Int
    )

    private val sttProviders = mutableListOf<PrioritizedProvider<STTServiceProvider>>()

    fun registerSTT(provider: STTServiceProvider, priority: Int = 100) {
        sttProviders.add(PrioritizedProvider(provider, priority))
        sttProviders.sortByDescending { it.priority }
    }

    fun sttProvider(modelId: String? = null): STTServiceProvider? {
        return if (modelId != null) {
            sttProviders.firstOrNull { it.provider.canHandle(modelId) }?.provider
        } else {
            sttProviders.firstOrNull()?.provider
        }
    }

    val hasSTT: Boolean get() = sttProviders.isNotEmpty()
}
```

### 4. Service Container Pattern

```kotlin
class ServiceContainer {
    companion object {
        val shared = ServiceContainer()
    }

    // Lazy services
    val modelRegistry: ModelRegistry by lazy {
        RegistryService()
    }

    val memoryService: MemoryManager by lazy {
        MemoryService(
            allocationManager = AllocationManager(),
            pressureHandler = PressureHandler(),
            cacheEviction = CacheEviction()
        )
    }

    val routingService: RoutingService by lazy {
        RoutingService(
            costCalculator = CostCalculator(),
            resourceChecker = ResourceChecker(hardwareManager)
        )
    }

    // Bootstrap modes
    suspend fun bootstrap() {
        // Full initialization
    }

    suspend fun bootstrapDevelopmentMode() {
        // Local only
    }

    fun setupLocalServices(params: SDKInitParams) {
        // Fast local setup
    }
}
```

### 5. Infrastructure Pattern (expect/actual)

```kotlin
// commonMain/infrastructure/voice/AudioSession.kt
expect class AudioSession() {
    suspend fun configure(mode: VoiceProcessingMode)
    suspend fun activate()
    suspend fun deactivate()
    suspend fun requestMicrophonePermission(): Boolean
    val hasMicrophonePermission: Boolean
}

// androidMain/infrastructure/voice/AudioSession.android.kt
actual class AudioSession actual constructor() {
    private val audioManager = /* get AudioManager */

    actual suspend fun configure(mode: VoiceProcessingMode) {
        when (mode) {
            VoiceProcessingMode.RECORDING -> {
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            }
            VoiceProcessingMode.PLAYBACK -> {
                audioManager.mode = AudioManager.MODE_NORMAL
            }
            VoiceProcessingMode.CONVERSATION -> {
                audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                audioManager.isSpeakerphoneOn = true
            }
        }
    }

    // ... other methods
}
```

---

## Key Takeaways for Kotlin SDK

### ✅ DO

1. **Define ALL protocols in commonMain** (as interfaces)
2. **Use expect/actual ONLY for platform-specific implementations** (like Infrastructure/)
3. **Keep business logic in commonMain** (Core/, Capabilities/, Components/)
4. **Follow iOS naming exactly** (STTComponent, not SpeechToTextComponent)
5. **Implement BaseComponent pattern** for all components
6. **Use Flow instead of AsyncSequence** for reactive streams
7. **Use coroutines instead of async/await** (suspend functions)
8. **Publish events at lifecycle transitions** (checking, initializing, ready, failed)
9. **Register providers via ModuleRegistry** (priority-based)
10. **Use ServiceContainer for dependency injection** (lazy initialization)
11. **Implement strong typing** (data classes for all models)
12. **Validate configurations** in validate() method
13. **Follow Component → Service → Provider pattern**
14. **Use sealed classes for errors** (type-safe error handling)
15. **Implement health checks** for all components

### ❌ DON'T

1. **DON'T invent your own logic** - copy iOS exactly
2. **DON'T put business logic in platform modules** (androidMain, jvmMain)
3. **DON'T use generic names** - follow iOS naming
4. **DON'T skip event publishing** - events are critical for observability
5. **DON'T hardcode services** - use ModuleRegistry for extensibility
6. **DON'T bypass ServiceContainer** - use DI consistently
7. **DON'T skip validation** - validate all inputs and configurations
8. **DON'T create components without provider pattern** - maintain extensibility
9. **DON'T ignore lifecycle states** - follow state machine exactly
10. **DON'T use strings for types** - use enums/sealed classes

---

## Component Checklist

When implementing a new component, ensure:

- [ ] Configuration struct (implements ComponentConfiguration)
- [ ] Input model (implements ComponentInput with validate())
- [ ] Output model (implements ComponentOutput with timestamp)
- [ ] Service protocol (interface in commonMain)
- [ ] Service provider protocol (with canHandle and name)
- [ ] Component class (extends BaseComponent)
- [ ] createService() implementation (uses ModuleRegistry)
- [ ] Public API methods (transcribe, generate, etc.)
- [ ] Event publishing (checking, initializing, ready, failed)
- [ ] Error handling (sealed class for errors)
- [ ] State validation (ensureReady() before operations)
- [ ] Cleanup implementation (performCleanup())
- [ ] ModuleRegistry registration support
- [ ] Documentation (KDoc matching iOS)

---

## Summary

The iOS SDK provides a **complete, production-ready architecture** that the Kotlin SDK must replicate exactly:

1. **Package Structure**: 7 main packages (Core, Components, Capabilities, Data, Foundation, Public, Infrastructure)
2. **Protocol-Driven**: Every service has a protocol, implementations are pluggable
3. **Component-Based**: All AI capabilities are components with lifecycle management
4. **Event-Driven**: EventBus for all inter-component communication
5. **Plugin Architecture**: ModuleRegistry for external implementations
6. **Dependency Injection**: ServiceContainer with lazy initialization
7. **Platform Abstraction**: Infrastructure/ for platform-specific code
8. **Strong Typing**: Data classes for all models, sealed classes for errors
9. **Reactive Streams**: Flow/AsyncSequence for streaming operations
10. **Clean Architecture**: Clear separation of concerns, testable design

**Next Steps:**
1. Review this document thoroughly
2. Create implementation plans for each missing component
3. Always check iOS implementation before writing Kotlin code
4. Translate iOS patterns to Kotlin idioms (not reinvent)
5. Maintain architectural consistency across platforms
