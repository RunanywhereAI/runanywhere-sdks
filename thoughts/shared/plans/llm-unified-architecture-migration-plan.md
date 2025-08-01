# LLM Unified Architecture Migration Plan - SDK vs Sample App Separation

## Implementation Status (Updated: Current)

### ✅ Completed (Phase 1 & 1.5)
- **All Core Protocols** - 9 protocol files defining the unified architecture
- **State Machine** - Thread-safe lifecycle management implementation
- **Tokenizer System** - Dynamic adapter registration with auto-detection
- **Hardware Abstraction** - Platform-agnostic hardware detection
- **SDK Integration** - Full integration with existing SDK types
- **RunAnywhereSDK** - Complete implementation with routing and lifecycle
- **Progress Tracking** - Stage-based progress with time estimation
- **Error Recovery** - Strategy-based error recovery system

### ✅ Completed (Phase 2)
- **Enhanced Download Manager** - Queue-based downloads with retry and archive extraction
- **Memory Management System** - Coordinated memory with pressure handling
- **Model Validation System** - Comprehensive validation with metadata extraction
- **Model Registry & Discovery** - Dynamic discovery with compatibility detection

### 📋 Planned (Phase 3+)
- Optional SDK Modules
- SDK Testing Framework
- Documentation
- Performance Optimization

## Executive Summary

This document provides a comprehensive, step-by-step plan for migrating the current RunAnywhereAI iOS LLM framework implementation to the proposed unified architecture. The migration separates common components into the RunAnywhere SDK while keeping framework-specific implementations in the sample app. This separation allows multiple developers to leverage the SDK's unified interface while implementing their own framework-specific adapters.

### Architecture Summary

**SDK (RunAnywhere Package)**
- Provides protocols and abstract interfaces
- Implements core infrastructure (lifecycle, memory, downloads)
- Handles common functionality (progress, errors, validation)
- Has minimal dependencies
- Framework-agnostic

**Sample App (RunAnywhereAI)**
- Implements SDK protocols
- Provides framework-specific adapters
- Demonstrates SDK usage patterns
- Shows best practices for integration

This clean separation ensures the SDK remains lightweight and flexible while the sample app serves as a comprehensive reference implementation.

## Key Architectural Decisions (Implementation Phase)

### 1. Type Deduplication
- **Decision**: Use existing `Context` and `Message` from `Configuration.swift`
- **Rationale**: Avoid duplicate types, maintain single source of truth
- **Impact**: Cleaner API, no confusion about which types to use

### 2. Component Registration Pattern
- **Decision**: SDK provides protocols, app registers implementations
- **Rationale**: Maximum flexibility, no hard dependencies
- **Impact**: SDK remains lightweight, easy to extend

### 3. Lifecycle Management
- **Decision**: Comprehensive state machine with validation
- **Rationale**: Predictable model loading, better error handling
- **Impact**: Robust model lifecycle, easier debugging

### 4. Progress Tracking
- **Decision**: Stage-based with time estimation
- **Rationale**: Better UX, predictable loading times
- **Impact**: Users can see detailed progress and ETA

### 5. Error Recovery
- **Decision**: Strategy pattern with default implementations
- **Rationale**: Extensible error handling, automatic recovery
- **Impact**: More resilient system, better user experience

## Current State Analysis

### Existing Architecture
```
UnifiedLLMService (Facade)
    ├── CoreMLService
    ├── TFLiteService
    ├── MLXService
    ├── SwiftTransformersService
    ├── ONNXService
    └── ExecuTorchService
```

### Key Issues
1. **Fragmented Lifecycle Management** - Each service manages its own lifecycle
2. **Tokenizer Chaos** - Multiple tokenizer implementations without unified interface
3. **Basic Download Management** - No queue, retry, or archive extraction
4. **No Memory Coordination** - Each framework manages memory independently
5. **Inconsistent Error Handling** - Different error types per framework
6. **Static Model Registry** - Hard-coded model lists
7. **Limited Progress Tracking** - Basic percentage-based progress
8. **Manual Hardware Detection** - Duplicated across services

## Migration Strategy

### Core Principles
1. **Modular SDK Design** - Core module with essential functionality, optional modules for specific features
2. **Out-of-the-Box Functionality** - SDK includes working implementations, not just protocols
3. **Progressive Enhancement** - Start simple with defaults, customize as needed
4. **Clean Architecture** - Remove all legacy code and technical debt
5. **Phased Approach** - Small, manageable phases with clear boundaries
6. **Framework Preservation** - Maintain core framework logic while unifying interfaces
7. **Developer Experience** - SDK provides powerful abstractions while allowing flexibility

### Architectural Separation Guidelines

#### SDK Responsibilities (What goes in the SDK):
1. **Protocol Definitions** - All interfaces that implementations must conform to
2. **Abstract Base Classes** - Common functionality that can be inherited
3. **Core Infrastructure**:
   - Model lifecycle state machine
   - Memory management system
   - Download manager with retry and archive support
   - Progress tracking system
   - Error recovery framework
4. **Utilities**:
   - Model validation framework
   - Metadata caching
   - Resource availability checking
5. **Public API** - Clean, well-documented public interface

#### Sample App Responsibilities:
1. **Framework Implementations** - All framework-specific adapters
2. **UI Components** - Views and view models
3. **Integration Examples** - SDK usage patterns
4. **Custom Extensions** - Extending SDK functionality

### Enhanced SDK Architecture (Following Industry Best Practices)

#### Modular Design Pattern
Based on patterns from Firebase, Stripe, and AWS SDK, the RunAnywhere SDK adopts a modular architecture:

```swift
// Core module (always required)
import RunAnywhere

// Optional modules as needed
import RunAnywhereHuggingFace    // For HuggingFace models
import RunAnywhereCorML          // For Core ML support
import RunAnywhereGGUF           // For GGUF/llama.cpp models
```

#### Progressive Enhancement Approach

**1. Basic Usage (Core Only)**
```swift
// Works out-of-the-box with built-in providers and formats
let sdk = RunAnywhereSDK.shared
try await sdk.initialize(apiKey: "...")

// Discover local models automatically
let models = await sdk.discoverModels()

// Load with automatic framework selection
try await sdk.loadModel("model-id")
let result = try await sdk.generate("Hello!")
```

**2. With Optional Modules**
```swift
import RunAnywhereHuggingFace

// Enhanced with HuggingFace provider
let hfProvider = HuggingFaceProvider(token: "...")
sdk.modelRegistry.registerProvider(hfProvider)

// Now can discover HuggingFace models
let hfModels = await sdk.discoverModels(from: .huggingFace)
```

**3. Custom Extensions**
```swift
// Implement custom framework adapter
class MyCustomAdapter: FrameworkAdapter {
    // Custom implementation
}

// Register with SDK
sdk.registerFrameworkAdapter(MyCustomAdapter())
```

#### Benefits of This Architecture

1. **Smaller App Size**: Include only what you need
2. **Faster Integration**: Working defaults reduce setup time
3. **Clear Upgrade Path**: Start simple, add modules as needed
4. **Community Friendly**: Easy to contribute new modules
5. **Future Proof**: New frameworks can be added without breaking changes

## SDK vs Sample App Architecture Division

### Components for SDK (RunAnywhere Swift Package)

#### Core Module (Always Included)
```swift
// Protocols with default implementations
public protocol ModelLifecycleManager { }
public protocol UnifiedTokenizer { }
public protocol HardwareDetector { }
public protocol MemoryManager { }
public protocol ProgressTracker { }
public protocol ErrorRecoveryStrategy { }
public protocol ModelValidator { }
public protocol ModelProvider { }
public protocol MetadataExtractorProtocol { }
public protocol FrameworkAdapter { }
public protocol AuthProvider { }
```

#### Core Implementations (Built-in)
- Model lifecycle state machine (concrete)
- Unified memory manager with platform defaults
- Enhanced download manager with archive support
- Progress tracking system
- Error recovery coordinator
- Model validation framework
- Dynamic model registry
- Resource availability checker
- Caching systems
- **Token management framework** (NEW)
- **Default platform implementations:**
  - DefaultiOSHardwareDetector (iOS only)
  - DefaultAndroidHardwareDetector (Android only)
  - DefaultMemoryManager (per platform)
- **Built-in format support:**
  - CoreMLMetadataExtractor
  - TFLiteMetadataExtractor
  - ONNXMetadataExtractor
  - SafetensorsMetadataExtractor
  - GGUFMetadataExtractor
- **Common tokenizer implementations:**
  - BPETokenizerAdapter
  - SentencePieceTokenizerAdapter
  - WordPieceTokenizerAdapter

#### Optional SDK Modules (Modular Architecture)
```
RunAnywhereProviders/ (Model discovery & download)
├── RunAnywhereHuggingFace
│   └── HuggingFaceProvider & Auth
├── RunAnywhereOpenModels
│   ├── KaggleProvider & Auth
│   └── MicrosoftModelsProvider
└── RunAnywhereSystemModels
    └── AppleModelsProvider (iOS only)

RunAnywhereFrameworks/ (Ready-to-use adapters)
├── RunAnywhereCorML (iOS only)
│   └── CoreMLFrameworkAdapter
├── RunAnywhereONNX (cross-platform)
│   └── ONNXFrameworkAdapter
├── RunAnywhereGGUF (llama.cpp)
│   └── LlamaCppFrameworkAdapter
└── RunAnywhereSystemML
    └── FoundationModelsAdapter (iOS 18+)
```

### SDK-Provided Components:
- Core protocols and interfaces
- Base implementations for common functionality
- Optional modules for popular frameworks
- Utilities and helpers

### Sample App Implements:
- All framework-specific adapters
- Custom extensions and optimizations
- UI and integration examples

## Phase 1: SDK Foundation Layer (Week 1-2) ✅ COMPLETED

### 1.1 Core Protocol Definitions (SDK) ✅

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/Protocols/`

#### Completed Files:
- ✅ `ModelLifecycleProtocol.swift` - Lifecycle management protocols
- ✅ `UnifiedTokenizerProtocol.swift` - Tokenizer abstraction with formats
- ✅ `FrameworkAdapter.swift` - Framework adapter interface with model info
- ✅ `LLMService.swift` - Service protocol with context management
- ✅ `HardwareDetector.swift` - Hardware detection interface
- ✅ `ModelProvider.swift` - Model provider protocols with search
- ✅ `MemoryManager.swift` - Memory management interface
- ✅ `ErrorRecoveryStrategy.swift` - Error recovery protocols
- ✅ `AuthProvider.swift` - Authentication provider interface

#### Key Implementation Details:

```swift
// SDK: Sources/RunAnywhere/Protocols/ModelLifecycleProtocol.swift
public protocol ModelLifecycleManager {
    var currentState: ModelLifecycleState { get }
    func transitionTo(_ state: ModelLifecycleState) async throws
    func addObserver(_ observer: ModelLifecycleObserver)
    func removeObserver(_ observer: ModelLifecycleObserver)
    func isValidTransition(from: ModelLifecycleState, to: ModelLifecycleState) -> Bool
}

// SDK: Sources/RunAnywhere/Protocols/LLMService.swift
public protocol LLMService {
    func initialize(modelPath: String) async throws
    func generate(prompt: String, options: GenerationOptions) async throws -> String
    func streamGenerate(prompt: String, options: GenerationOptions, onToken: @escaping (String) -> Void) async throws
    func cleanup() async
    func getModelMemoryUsage() async throws -> Int64
    var isReady: Bool { get }
    var modelInfo: LoadedModelInfo? { get }
    func setContext(_ context: Context) async  // Uses existing Context from Configuration.swift
    func clearContext() async
}
```

### 1.2 State Machine Implementation (SDK) ✅

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/Core/ModelLifecycleStateMachine.swift`

#### Completed Implementation:
- ✅ Thread-safe state management with NSLock
- ✅ Valid state transition validation
- ✅ Observer pattern with weak references
- ✅ Helper methods for common operations
- ✅ Error state handling

#### Key Features:

```swift
// SDK: Sources/RunAnywhere/Core/ModelLifecycleStateMachine.swift
public class ModelLifecycleStateMachine: ModelLifecycleManager {
    private var state: ModelLifecycleState = .uninitialized
    private var observers: [UUID: ModelLifecycleObserver] = [:]

    private let validTransitions: [ModelLifecycleState: Set<ModelLifecycleState>] = [
        .uninitialized: [.discovered],
        .discovered: [.downloading],
        .downloading: [.downloaded, .error],
        .downloaded: [.extracting],
        .extracting: [.extracted, .error],
        .extracted: [.validating],
        .validating: [.validated, .error],
        .validated: [.initializing],
        .initializing: [.initialized, .error],
        .initialized: [.loading],
        .loading: [.loaded, .error],
        .loaded: [.ready],
        .ready: [.executing, .cleanup],
        .executing: [.ready, .error],
        .error: [.cleanup],
        .cleanup: [.uninitialized]
    ]

    func transitionTo(_ newState: ModelLifecycleState) async throws {
        guard isValidTransition(from: state, to: newState) else {
            throw UnifiedModelError.lifecycle(
                .invalidTransition(from: state, to: newState)
            )
        }

        let oldState = state
        state = newState

        await notifyObservers(oldState: oldState, newState: newState)
    }
}
```

### 1.3 Unified Tokenizer System (SDK) ✅

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/Tokenization/`

#### Completed Implementation:
- ✅ `UnifiedTokenizerManager.swift` with singleton pattern
- ✅ Dynamic tokenizer adapter registration
- ✅ Automatic format detection from model files
- ✅ Tokenizer caching mechanism
- ✅ BasicTokenizer as fallback implementation

#### Key Features:
- Auto-detects tokenizer format from model files
- Supports registration of custom tokenizer adapters
- Thread-safe cache management
- Format detection for HuggingFace, SentencePiece, WordPiece, BPE

```swift
// SDK: Sources/RunAnywhere/Tokenization/UnifiedTokenizerManager.swift
public class UnifiedTokenizerManager {
    static let shared = UnifiedTokenizerManager()

    private var tokenizers: [String: UnifiedTokenizer] = [:]
    private var adapters: [TokenizerFormat: TokenizerAdapter.Type] = [:]

    init() {
        registerDefaultAdapters()
    }

    private func registerDefaultAdapters() {
        // SDK provides empty registry
        // Sample app will register concrete implementations
        // This allows SDK users to register their own tokenizer adapters
    }

    func getTokenizer(for model: ModelInfo) async throws -> UnifiedTokenizer {
        // Check cache
        if let cached = tokenizers[model.id] {
            return cached
        }

        // Auto-detect and create
        let format = try detectTokenizerFormat(for: model)
        let adapter = try createAdapter(format: format, model: model)

        tokenizers[model.id] = adapter
        return adapter
    }

    private func detectTokenizerFormat(for model: ModelInfo) throws -> TokenizerFormat {
        // Check model metadata first
        if let format = model.tokenizerFormat {
            return format
        }

        // Auto-detect based on model files
        if let modelPath = model.localPath {
            let files = try FileManager.default.contentsOfDirectory(at: modelPath, includingPropertiesForKeys: nil)

            // Check for specific tokenizer files
            if files.contains(where: { $0.lastPathComponent == "tokenizer.json" }) {
                return .huggingFace
            } else if files.contains(where: { $0.lastPathComponent.contains("sentencepiece") }) {
                return .sentencePiece
            } else if files.contains(where: { $0.lastPathComponent == "vocab.txt" }) {
                return .wordPiece
            } else if files.contains(where: { $0.pathExtension == "bpe" }) {
                return .bpe
            }
        }

        // Framework-specific defaults
        switch model.format {
        case .tflite:
            return .tflite
        case .mlmodel, .mlpackage:
            return .coreML
        default:
            throw TokenizerError.formatNotDetected
        }
    }
}

// SDK only defines the protocol
// Concrete implementations like BPETokenizerAdapter go in the sample app
// This allows SDK users to provide their own tokenizer implementations
```

### 1.4 Hardware Abstraction Layer (SDK) ✅

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/Hardware/`

#### Completed Implementation:
- ✅ `HardwareCapabilityManager.swift` with singleton pattern
- ✅ Platform-specific hardware detector registration
- ✅ Optimal configuration selection based on model requirements
- ✅ Resource availability checking
- ✅ DefaultHardwareDetector as fallback

#### Key Features:
- Dynamic hardware detector registration
- Smart accelerator selection (Neural Engine, GPU, CPU)
- Memory mode selection (conservative, balanced, aggressive)
- Quantization settings based on device capabilities
- Cross-platform support (iOS, macOS)

```swift
// SDK: Sources/RunAnywhere/Hardware/HardwareCapabilityManager.swift
public class HardwareCapabilityManager {
    public static let shared = HardwareCapabilityManager()

    private var registeredHardwareDetector: HardwareDetector?
    private var cachedCapabilities: DeviceCapabilities?

    /// Register a platform-specific hardware detector
    public func registerHardwareDetector(_ detector: HardwareDetector) {
        self.registeredHardwareDetector = detector
        self.cachedCapabilities = nil // Clear cache
    }

    /// Get current device capabilities
    public var capabilities: DeviceCapabilities {
        if let cached = cachedCapabilities {
            return cached
        }

        guard let detector = registeredHardwareDetector else {
            // Return minimal defaults if no detector registered
            return DeviceCapabilities(
                totalMemory: 2_000_000_000, // 2GB default
                availableMemory: 1_000_000_000, // 1GB default
                hasNeuralEngine: false,
                hasGPU: false,
                processorCount: 2
            )
        }

        cachedCapabilities = detector.detectCapabilities()
        return cachedCapabilities!
    }

    func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        var config = HardwareConfiguration()

        // Use registered hardware detector (provided by sample app)
        guard let detector = registeredHardwareDetector else {
            // Fallback to conservative defaults
            config.primaryAccelerator = .cpu
            config.memoryMode = .conservative
            config.threadCount = 2
            return config
        }

        let capabilities = detector.detectCapabilities()

        // Smart selection based on detected capabilities
        if model.estimatedMemory > 3_000_000_000 && capabilities.hasNeuralEngine {
            config.primaryAccelerator = .neuralEngine
            config.fallbackAccelerator = .gpu
        } else if capabilities.totalMemory > 8_000_000_000 {
            config.primaryAccelerator = .gpu
            config.memoryMode = .aggressive
        } else {
            config.primaryAccelerator = .cpu
            config.memoryMode = .conservative
        }

        config.threadCount = capabilities.processorCount

        return config
    }

    func checkResourceAvailability() -> ResourceAvailability {
        let thermalState = ProcessInfo.processInfo.thermalState
        let batteryLevel = UIDevice.current.batteryLevel
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        return ResourceAvailability(
            memoryAvailable: getAvailableMemory(),
            storageAvailable: getAvailableStorage(),
            acceleratorsAvailable: getAvailableAccelerators(),
            thermalState: thermalState,
            batteryLevel: batteryLevel >= 0 ? batteryLevel : nil,
            isLowPowerMode: isLowPowerMode
        )
    }
}

public struct ResourceAvailability {
    let memoryAvailable: Int64
    let storageAvailable: Int64
    let acceleratorsAvailable: [HardwareAcceleration]
    let thermalState: ProcessInfo.ThermalState
    let batteryLevel: Float?
    let isLowPowerMode: Bool

    func canLoad(model: ModelInfo) -> (canLoad: Bool, reason: String?) {
        // Check memory
        if model.estimatedMemory > memoryAvailable {
            return (false, "Insufficient memory: need \(ByteCountFormatter.string(fromByteCount: model.estimatedMemory, countStyle: .memory)), have \(ByteCountFormatter.string(fromByteCount: memoryAvailable, countStyle: .memory))")
        }

        // Check storage
        if let downloadSize = model.downloadSize, downloadSize > storageAvailable {
            return (false, "Insufficient storage: need \(ByteCountFormatter.string(fromByteCount: downloadSize, countStyle: .file)), have \(ByteCountFormatter.string(fromByteCount: storageAvailable, countStyle: .file))")
        }

        // Check thermal state
        if thermalState == .critical {
            return (false, "Device is too hot, please wait for it to cool down")
        }

        // Check battery in low power mode
        if isLowPowerMode && batteryLevel != nil && batteryLevel! < 0.2 {
            return (false, "Battery too low for model loading in Low Power Mode")
        }

        return (true, nil)
    }
}
```

## Phase 1.5: SDK Integration and Cleanup ✅ COMPLETED

### Integration with Existing SDK Implementation

#### Completed Tasks:
1. ✅ **Context/Message Deduplication**
   - Removed duplicate `GenerationContext` and `Message` from `LLMService.swift`
   - Updated `LLMService` protocol to use existing `Context` from `Configuration.swift`

2. ✅ **Configuration Enhancement**
   - Added `preferredFrameworks: [LLMFramework]`
   - Added `hardwarePreferences: HardwareConfiguration?`
   - Added `modelProviders: [ModelProviderConfig]`
   - Added `memoryThreshold: Int64`
   - Added `downloadConfiguration: DownloadConfig`

3. ✅ **GenerationOptions Enhancement**
   - Added `streamingEnabled: Bool`
   - Added `tokenBudget: TokenBudget?`
   - Added `frameworkOptions: FrameworkOptions?`
   - Added framework-specific options (CoreMLOptions, TFLiteOptions, MLXOptions, GGUFOptions)

4. ✅ **GenerationResult Enhancement**
   - Added `framework: LLMFramework?`
   - Added `hardwareUsed: HardwareAcceleration`
   - Added `memoryUsed: Int64`
   - Added `tokenizerFormat: TokenizerFormat?`
   - Added `performanceMetrics: PerformanceMetrics`

5. ✅ **Internal Types Enhancement**
   - Enhanced `InferenceRequest` with priority and token estimation
   - Enhanced `RoutingDecision` with framework selection
   - Enhanced `RoutingReason` with detailed descriptions
   - Added `RoutingContext` and `ModelSelection` types

6. ✅ **RunAnywhereSDK Complete Rewrite**
   - Integrated all unified components
   - Implemented model loading with lifecycle management
   - Added intelligent routing with framework selection
   - Added progress tracking and error recovery
   - Added component registration methods
   - Full implementation of generate() with on-device execution

### Additional Components Created:

1. ✅ **Progress Tracking** (`Progress/UnifiedProgressTracker.swift`)
   - Stage-based progress tracking
   - Time estimation based on historical data
   - Observable pattern with Combine support
   - Thread-safe implementation

2. ✅ **Error Recovery** (`ErrorHandling/UnifiedErrorRecovery.swift`)
   - Strategy pattern for different error types
   - Default strategies for download, memory, validation, framework, network errors
   - Recovery suggestions
   - Exponential backoff implementation

## Phase 2: SDK Core Services (Week 3-4) ✅ COMPLETED

### Implementation Summary

All Phase 2 components have been successfully implemented in the SDK:

1. **Enhanced Download Manager** (`Download/EnhancedDownloadManager.swift`)
   - ✅ Queue-based download management with concurrent limits
   - ✅ Retry logic with exponential backoff
   - ✅ Archive extraction support (zip, tar, gz, bz2, xz)
   - ✅ Progress tracking with time estimation
   - ✅ Checksum verification
   - ✅ Extensible download configuration

2. **Memory Management System** (`Memory/UnifiedMemoryManager.swift`)
   - ✅ Coordinated memory management across frameworks
   - ✅ Memory pressure handling with iOS notifications
   - ✅ Model unloading strategies (LRU, largest first, priority-based)
   - ✅ Real-time memory monitoring
   - ✅ Memory statistics and reporting

3. **Model Validation System** (`Validation/ModelValidator.swift`)
   - ✅ Comprehensive model validation framework
   - ✅ Checksum verification using CryptoKit
   - ✅ Format validation with auto-detection
   - ✅ Dependency checking
   - ✅ Metadata extraction for all formats
   - ✅ Framework-specific validation

4. **Model Registry & Discovery** (`Registry/DynamicModelRegistry.swift`)
   - ✅ Dynamic model discovery (local and online)
   - ✅ Compatibility matrix detection
   - ✅ Model filtering with multiple criteria
   - ✅ Provider registration system
   - ✅ Metadata caching
   - ✅ Bundle model detection

### Key Design Decisions

1. **Singleton Pattern**: Used for shared managers (Download, Memory, Registry)
2. **Protocol-Oriented**: All components implement protocols for flexibility
3. **Async/Await**: Modern Swift concurrency throughout
4. **Thread Safety**: NSLock used for critical sections
5. **Platform Support**: Conditional compilation for iOS/macOS differences

## Phase 2: SDK Core Services (Week 3-4)

### 2.1 Enhanced Download Manager (SDK)

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/Download/`

#### Tasks:
1. Add queue-based download management in SDK
2. Implement retry with exponential backoff
3. Add comprehensive archive extraction support
4. Create progress tracking system
5. Make extensible for custom download sources

#### Implementation:

```swift
// SDK: Sources/RunAnywhere/Download/EnhancedDownloadManager.swift
import Foundation
import Gzip // Add to SDK Package.swift

public class EnhancedDownloadManager: ModelStorageManager {
    private let downloadQueue = OperationQueue()
    private var activeTasks: [String: DownloadTask] = [:]

    func downloadModel(_ model: ModelInfo) async throws -> DownloadTask {
        let taskId = UUID().uuidString

        let task = DownloadTask(
            id: taskId,
            modelId: model.id,
            progress: createProgressStream(taskId),
            result: Task {
                try await performDownload(model, taskId: taskId)
            }
        )

        activeTasks[taskId] = task
        return task
    }

    private func performDownload(_ model: ModelInfo, taskId: String) async throws -> URL {
        var lastError: Error?

        // Retry logic with exponential backoff
        for attempt in 0..<3 {
            do {
                if attempt > 0 {
                    let delay = pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }

                let data = try await downloadWithProgress(
                    from: model.downloadURL,
                    taskId: taskId
                )

                let storedURL = try await storeModel(data, for: model)

                // Handle archives
                if needsExtraction(storedURL) {
                    return try await extractArchive(storedURL)
                }

                return storedURL
            } catch {
                lastError = error
                reportProgress(taskId, .retrying(attempt: attempt + 1))
            }
        }

        throw lastError ?? DownloadError.unknown
    }

    private func extractArchive(_ archive: URL) async throws -> URL {
        let ext = archive.pathExtension.lowercased()

        switch ext {
        case "zip":
            return try await extractZip(archive)
        case "gz", "tgz":
            return try await extractTarGz(archive)
        case "tar":
            return try await extractTar(archive)
        case "bz2", "tbz2":  // Add support for bzip2
            return try await extractTarBz2(archive)
        case "xz", "txz":    // Add support for xz compression
            return try await extractTarXz(archive)
        default:
            throw DownloadError.unsupportedArchive(ext)
        }
    }

    private func extractTarGz(_ archive: URL) async throws -> URL {
        // Proper tar.gz extraction
        let decompressed = try Data(contentsOf: archive).gunzipped()
        let tarURL = archive.deletingPathExtension()
        try decompressed.write(to: tarURL)

        // Extract tar
        let outputDir = tarURL.deletingPathExtension()
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        task.arguments = ["-xf", tarURL.path, "-C", outputDir.path]
        try task.run()
        task.waitUntilExit()

        return outputDir
    }

    private func extractTarBz2(_ archive: URL) async throws -> URL {
        // Handle bzip2 compressed archives
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        task.arguments = ["-xjf", archive.path, "-C", archive.deletingLastPathComponent().path]
        try task.run()
        task.waitUntilExit()

        return archive.deletingPathExtension()
    }

    private func extractTarXz(_ archive: URL) async throws -> URL {
        // Handle xz compressed archives
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        task.arguments = ["-xJf", archive.path, "-C", archive.deletingLastPathComponent().path]
        try task.run()
        task.waitUntilExit()

        return archive.deletingPathExtension()
    }
}
```

### 2.2 Memory Management System (SDK)

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/Memory/`

#### Tasks:
1. Implement coordinated memory management in SDK
2. Add memory pressure handling
3. Create model unloading strategy
4. Add memory usage tracking
5. Provide hooks for framework-specific cleanup

#### Implementation:

```swift
// SDK: Sources/RunAnywhere/Memory/UnifiedMemoryManager.swift
public class UnifiedMemoryManager {
    static let shared = UnifiedMemoryManager()

    private var loadedModels: [String: LoadedModelInfo] = [:]
    private var memoryPressureObserver: NSObjectProtocol?
    private let memoryThreshold: Int64 = 500_000_000 // 500MB threshold

    struct LoadedModelInfo {
        let model: LoadedModel
        let size: Int64
        var lastUsed: Date
        weak var service: LLMService?
    }

    init() {
        setupMemoryPressureHandling()
    }

    private func setupMemoryPressureHandling() {
        // iOS memory pressure
        memoryPressureObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.handleMemoryPressure()
            }
        }

        // Also monitor available memory periodically
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task {
                await self?.checkMemoryUsage()
            }
        }
    }

    func registerLoadedModel(_ model: LoadedModel, size: Int64, service: LLMService) {
        loadedModels[model.id] = LoadedModelInfo(
            model: model,
            size: size,
            lastUsed: Date(),
            service: service
        )
    }

    private func handleMemoryPressure() async {
        let availableMemory = getAvailableMemory()

        if availableMemory < memoryThreshold {
            // Unload least recently used models
            let sortedModels = loadedModels.values.sorted { $0.lastUsed < $1.lastUsed }

            for modelInfo in sortedModels {
                if getAvailableMemory() > memoryThreshold * 2 {
                    break
                }

                await unloadModel(modelInfo.model.id)
            }
        }
    }

    private func unloadModel(_ modelId: String) async {
        guard let modelInfo = loadedModels[modelId] else { return }

        // Notify service to cleanup
        await modelInfo.service?.cleanup()

        // Remove from tracking
        loadedModels.removeValue(forKey: modelId)

        // Force memory reclaim
        autoreleasepool {
            // Trigger cleanup
        }
    }
}
```

### 2.3 Model Validation System (SDK)

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/Validation/`

#### Tasks:
1. Implement comprehensive model validation in SDK
2. Add checksum verification
3. Create format validation protocol
4. Allow framework-specific validation extensions

#### Implementation:

```swift
// SDK: Sources/RunAnywhere/Validation/ModelValidator.swift
public protocol ModelValidator {
    func validateModel(_ model: ModelInfo, at path: URL) async throws -> ValidationResult
    func validateChecksum(_ file: URL, expected: String) async throws -> Bool
    func validateFormat(_ file: URL, expectedFormat: ModelFormat) async throws -> Bool
    func validateDependencies(_ model: ModelInfo) async throws -> [MissingDependency]
}

struct ValidationResult {
    let isValid: Bool
    let warnings: [ValidationWarning]
    let errors: [ValidationError]
    let metadata: ModelMetadata?
}

class UnifiedModelValidator: ModelValidator {
    func validateModel(_ model: ModelInfo, at path: URL) async throws -> ValidationResult {
        var warnings: [ValidationWarning] = []
        var errors: [ValidationError] = []

        // Validate checksum if provided
        if let expectedChecksum = model.checksum {
            let isValid = try await validateChecksum(path, expected: expectedChecksum)
            if !isValid {
                errors.append(.checksumMismatch)
            }
        }

        // Validate format
        let formatValid = try await validateFormat(path, expectedFormat: model.format)
        if !formatValid {
            errors.append(.invalidFormat)
        }

        // Check dependencies
        let missingDeps = try await validateDependencies(model)
        if !missingDeps.isEmpty {
            errors.append(.missingDependencies(missingDeps))
        }

        // Extract and validate metadata
        let metadata = try await extractAndValidateMetadata(from: path, format: model.format)

        // Framework-specific validation
        if let frameworkErrors = try await validateFrameworkSpecific(model, at: path) {
            errors.append(contentsOf: frameworkErrors)
        }

        return ValidationResult(
            isValid: errors.isEmpty,
            warnings: warnings,
            errors: errors,
            metadata: metadata
        )
    }

    private func validateFrameworkSpecific(_ model: ModelInfo, at path: URL) async throws -> [ValidationError]? {
        switch model.format {
        case .mlmodel, .mlpackage:
            return try await validateCoreMLModel(at: path)
        case .tflite:
            return try await validateTFLiteModel(at: path)
        case .onnx:
            return try await validateONNXModel(at: path)
        case .safetensors:
            return try await validateSafetensorsModel(at: path)
        default:
            return nil
        }
    }
}
```

### 2.4 Model Registry & Discovery (SDK)

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/Registry/`

#### Tasks:
1. Create dynamic model discovery in SDK
2. Build model compatibility matrix
3. Implement runtime model detection
4. Add model metadata caching
5. Provide extension points for custom providers

#### Implementation:

```swift
// SDK: Sources/RunAnywhere/Registry/DynamicModelRegistry.swift
public class DynamicModelRegistry: ModelRegistry {
    private var registeredModels: [String: ModelInfo] = [:]
    private let localStorage = ModelLocalStorage()
    private let storageMonitor = StorageMonitorService.shared
    private let huggingFaceAuth = HuggingFaceAuthService.shared
    private let kaggleAuth = KaggleAuthService.shared
    private let keychain = KeychainService.shared
    private let onlineProviders: [ModelProvider] = [
        HuggingFaceProvider(),
        AppleModelsProvider(),
        MicrosoftModelsProvider(),
        PicovoiceProvider(),
        MLCProvider()
    ]

    func discoverModels() async -> [ModelInfo] {
        async let localModels = discoverLocalModels()
        async let onlineModels = discoverOnlineModels()

        let (local, online) = await (localModels, onlineModels)

        // Merge and deduplicate
        var allModels = local
        let localIds = Set(local.map { $0.id })

        for model in online where !localIds.contains(model.id) {
            allModels.append(model)
        }

        // Update registry
        for model in allModels {
            registeredModels[model.id] = model
        }

        return allModels
    }

    private func discoverLocalModels() async -> [ModelInfo] {
        var models: [ModelInfo] = []

        // Scan model directories
        let modelDirs = getModelDirectories()

        for dir in modelDirs {
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isDirectoryKey]
            ) {
                for url in contents {
                    if let model = await detectModel(at: url) {
                        models.append(model)
                    }
                }
            }
        }

        return models
    }

    private func detectModel(at url: URL) async -> ModelInfo? {
        // Auto-detect model format and metadata
        let format = ModelFormatDetector.detect(at: url)

        guard let format = format else { return nil }

        // Extract metadata
        let metadata = await extractMetadata(from: url, format: format)

        // Determine compatible frameworks
        let frameworks = detectCompatibleFrameworks(format: format, metadata: metadata)

        return ModelInfo(
            id: UUID().uuidString,
            name: url.lastPathComponent,
            format: format,
            localPath: url,
            compatibleFrameworks: frameworks,
            metadata: metadata
        )
    }

    func filterModels(by criteria: ModelCriteria) -> [ModelInfo] {
        return registeredModels.values.filter { model in
            // Apply all criteria
            if let framework = criteria.framework {
                guard model.compatibleFrameworks.contains(framework) else {
                    return false
                }
            }

            if let maxSize = criteria.maxSize {
                guard model.estimatedMemory <= maxSize else {
                    return false
                }
            }

            if let minContext = criteria.minContextLength {
                guard model.contextLength >= minContext else {
                    return false
                }
            }

            return true
        }
    }
}
```

### 2.5 Progress Tracking System (SDK)

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/Progress/`

#### Tasks:
1. Implement stage-based progress tracking in SDK
2. Add time estimation
3. Create unified progress reporting
4. Build progress aggregation for multiple operations

#### Implementation:

```swift
// SDK: Sources/RunAnywhere/Progress/UnifiedProgressTracker.swift
public class UnifiedProgressTracker: ProgressTracker {
    private var stages: [LifecycleStage: StageInfo] = [:]
    private var observers: [UUID: ProgressObserver] = [:]
    private let progressSubject = PassthroughSubject<OverallProgress, Never>()

    struct StageInfo {
        let stage: LifecycleStage
        var startTime: Date
        var progress: Double = 0
        var message: String = ""
        var subStages: [String: Double] = [:]
    }

    func startStage(_ stage: LifecycleStage) {
        stages[stage] = StageInfo(
            stage: stage,
            startTime: Date(),
            message: stage.defaultMessage
        )

        notifyProgress()
    }

    func updateStageProgress(_ stage: LifecycleStage, progress: Double, message: String? = nil) {
        guard var stageInfo = stages[stage] else { return }

        stageInfo.progress = progress
        if let message = message {
            stageInfo.message = message
        }

        stages[stage] = stageInfo
        notifyProgress()
    }

    func completeStage(_ stage: LifecycleStage) {
        guard var stageInfo = stages[stage] else { return }

        stageInfo.progress = 1.0
        stages[stage] = stageInfo

        // Store duration for future estimates
        let duration = Date().timeIntervalSince(stageInfo.startTime)
        storeStageDuration(stage, duration: duration)

        notifyProgress()
    }

    func getCurrentProgress() -> OverallProgress {
        let stageWeights: [LifecycleStage: Double] = [
            .discovery: 0.05,
            .download: 0.25,
            .extraction: 0.10,
            .validation: 0.05,
            .initialization: 0.15,
            .loading: 0.30,
            .ready: 0.10
        ]

        var totalProgress = 0.0
        var totalWeight = 0.0
        var currentStage: LifecycleStage?
        var estimatedTimeRemaining: TimeInterval?

        for (stage, info) in stages {
            let weight = stageWeights[stage] ?? 0.1
            totalProgress += info.progress * weight
            totalWeight += weight

            if info.progress < 1.0 && currentStage == nil {
                currentStage = stage
                estimatedTimeRemaining = estimateTimeRemaining(for: stage, progress: info.progress)
            }
        }

        let overallProgress = totalWeight > 0 ? totalProgress / totalWeight : 0

        return OverallProgress(
            percentage: overallProgress,
            currentStage: currentStage,
            stageProgress: stages[currentStage ?? .discovery]?.progress ?? 0,
            message: stages[currentStage ?? .discovery]?.message ?? "",
            estimatedTimeRemaining: estimatedTimeRemaining
        )
    }

    private func estimateTimeRemaining(for stage: LifecycleStage, progress: Double) -> TimeInterval? {
        guard progress > 0 else { return nil }

        let avgDuration = getAverageDuration(for: stage)
        let elapsed = Date().timeIntervalSince(stages[stage]?.startTime ?? Date())

        // Use actual progress if available, otherwise use historical average
        if elapsed > 0 {
            let estimatedTotal = elapsed / progress
            return max(0, estimatedTotal - elapsed)
        } else {
            return avgDuration * (1.0 - progress)
        }
    }
}
```

### 2.6 Error Recovery Strategy (SDK)

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/ErrorHandling/`

#### Tasks:
1. Implement comprehensive error recovery in SDK
2. Create recovery strategies for different error types
3. Add automatic retry mechanisms
4. Allow custom recovery strategies

#### Implementation:

```swift
// SDK: Sources/RunAnywhere/ErrorHandling/ErrorRecoveryStrategy.swift
public protocol ErrorRecoveryStrategy {
    func canRecover(from error: Error) -> Bool
    func recover(from error: Error, context: RecoveryContext) async throws
}

struct RecoveryContext {
    let model: ModelInfo
    let stage: LifecycleStage
    let attemptCount: Int
    let previousErrors: [Error]
    let availableResources: ResourceAvailability
}

class UnifiedErrorRecovery {
    private var strategies: [ErrorType: ErrorRecoveryStrategy] = [:]

    init() {
        registerDefaultStrategies()
    }

    private func registerDefaultStrategies() {
        registerStrategy(DownloadErrorRecovery(), for: .download)
        registerStrategy(MemoryErrorRecovery(), for: .memory)
        registerStrategy(ValidationErrorRecovery(), for: .validation)
        registerStrategy(FrameworkErrorRecovery(), for: .framework)
    }

    func registerStrategy(_ strategy: ErrorRecoveryStrategy, for errorType: ErrorType) {
        strategies[errorType] = strategy
    }

    func attemptRecovery(from error: Error, in context: RecoveryContext) async throws {
        let errorType = ErrorType(from: error)

        if let strategy = strategies[errorType],
           strategy.canRecover(from: error) {
            try await strategy.recover(from: error, context: context)
        } else {
            throw UnifiedModelError.unrecoverable(error)
        }
    }
}

// Example recovery strategies
class DownloadErrorRecovery: ErrorRecoveryStrategy {
    func canRecover(from error: Error) -> Bool {
        if case DownloadError.networkError = error { return true }
        if case DownloadError.timeout = error { return true }
        if case DownloadError.partialDownload = error { return true }
        return false
    }

    func recover(from error: Error, context: RecoveryContext) async throws {
        // Retry with exponential backoff
        let delay = pow(2.0, Double(context.attemptCount))
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

        // Try alternative download URLs if available
        if let alternativeURLs = context.model.alternativeDownloadURLs {
            for url in alternativeURLs {
                do {
                    // Attempt download from alternative URL
                    return
                } catch {
                    continue
                }
            }
        }

        // Clear partial downloads and restart
        if case DownloadError.partialDownload = error {
            try await clearPartialDownload(for: context.model)
        }
    }
}

class MemoryErrorRecovery: ErrorRecoveryStrategy {
    func canRecover(from error: Error) -> Bool {
        if case UnifiedModelError.insufficientMemory = error { return true }
        if error.localizedDescription.contains("memory") { return true }
        return false
    }

    func recover(from error: Error, context: RecoveryContext) async throws {
        let memoryManager = UnifiedMemoryManager.shared

        // Unload least recently used models
        await memoryManager.handleMemoryPressure()

        // Wait for memory to be freed
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Check if we have enough memory now
        let available = context.availableResources.memoryAvailable
        if context.model.estimatedMemory > available {
            // Try switching to more memory-efficient framework
            if let efficientFramework = findMemoryEfficientFramework(for: context.model) {
                throw UnifiedModelError.retryWithFramework(efficientFramework)
            }
        }
    }
}

class ValidationErrorRecovery: ErrorRecoveryStrategy {
    func canRecover(from error: Error) -> Bool {
        if case ValidationError.checksumMismatch = error { return true }
        if case ValidationError.corruptedFile = error { return true }
        return false
    }

    func recover(from error: Error, context: RecoveryContext) async throws {
        // Re-download the model
        let downloadManager = EnhancedDownloadManager()

        // Delete corrupted file
        if let localPath = context.model.localPath {
            try FileManager.default.removeItem(at: localPath)
        }

        // Force re-download
        context.model.localPath = nil
        throw UnifiedModelError.retryRequired("Model validation failed, re-downloading")
    }
}

class FrameworkErrorRecovery: ErrorRecoveryStrategy {
    func canRecover(from error: Error) -> Bool {
        // Framework initialization errors might be recoverable with different framework
        return true
    }

    func recover(from error: Error, context: RecoveryContext) async throws {
        let adapterRegistry = FrameworkAdapterRegistry.shared

        // Find alternative framework
        let currentFramework = context.model.preferredFramework
        let alternatives = context.model.compatibleFrameworks.filter { $0 != currentFramework }

        for framework in alternatives {
            if let adapter = adapterRegistry.getAdapter(for: framework),
               adapter.canHandle(model: context.model) {
                throw UnifiedModelError.retryWithFramework(framework)
            }
        }

        throw UnifiedModelError.noAlternativeFramework
    }
}
```

### 2.7 Model Metadata Extraction (SDK)

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/Metadata/`

#### Tasks:
1. Define metadata extraction protocol in SDK
2. Create unified metadata structure
3. Add caching for extracted metadata
4. Allow format-specific extractors in app

#### Implementation:

```swift
// SDK: Sources/RunAnywhere/Metadata/MetadataExtractor.swift
public class MetadataExtractor {
    private let cache = MetadataCache()

    func extractMetadata(from url: URL, format: ModelFormat) async -> ModelMetadata {
        // Check cache first
        if let cached = cache.get(for: url) {
            return cached
        }

        let metadata = await extractForFormat(from: url, format: format)
        cache.store(metadata, for: url)

        return metadata
    }

    private func extractForFormat(from url: URL, format: ModelFormat) async -> ModelMetadata {
        switch format {
        case .mlmodel, .mlpackage:
            return await extractCoreMLMetadata(from: url)
        case .tflite:
            return await extractTFLiteMetadata(from: url)
        case .onnx:
            return await extractONNXMetadata(from: url)
        case .safetensors:
            return await extractSafetensorsMetadata(from: url)
        case .gguf:
            return await extractGGUFMetadata(from: url)
        case .pte:
            return await extractExecuTorchMetadata(from: url)
        default:
            return await extractGenericMetadata(from: url)
        }
    }

    private func extractCoreMLMetadata(from url: URL) async -> ModelMetadata {
        var metadata = ModelMetadata()

        if url.pathExtension == "mlpackage" {
            // Read Metadata.json from mlpackage
            let metadataURL = url.appendingPathComponent("Metadata.json")
            if let data = try? Data(contentsOf: metadataURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                metadata.author = json["author"] as? String
                metadata.description = json["description"] as? String
                metadata.version = json["version"] as? String
            }
        } else {
            // For .mlmodel, compile and inspect
            if let model = try? MLModel(contentsOf: url) {
                let description = model.modelDescription
                metadata.inputShapes = description.inputDescriptionsByName.mapValues { desc in
                    desc.multiArrayConstraint?.shape.map { $0.intValue } ?? []
                }
                metadata.outputShapes = description.outputDescriptionsByName.mapValues { desc in
                    desc.multiArrayConstraint?.shape.map { $0.intValue } ?? []
                }
            }
        }

        return metadata
    }

    private func extractSafetensorsMetadata(from url: URL) async -> ModelMetadata {
        var metadata = ModelMetadata()

        // Read safetensors header
        if let file = try? FileHandle(forReadingFrom: url) {
            defer { try? file.close() }

            // First 8 bytes contain header size
            let headerSizeData = file.readData(ofLength: 8)
            guard headerSizeData.count == 8 else { return metadata }

            let headerSize = headerSizeData.withUnsafeBytes { $0.load(as: UInt64.self) }
            let headerData = file.readData(ofLength: Int(headerSize))

            if let json = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] {
                // Extract tensor information
                if let tensors = json["tensors"] as? [String: Any] {
                    metadata.tensorCount = tensors.count
                    metadata.parameterCount = calculateParameterCount(from: tensors)
                }

                // Extract model config if present
                if let config = json["__metadata__"] as? [String: Any] {
                    metadata.modelType = config["model_type"] as? String
                    metadata.architecture = config["architecture"] as? String
                }
            }
        }

        return metadata
    }

    private func extractGGUFMetadata(from url: URL) async -> ModelMetadata {
        var metadata = ModelMetadata()

        // GGUF has rich metadata in header
        if let file = try? FileHandle(forReadingFrom: url) {
            defer { try? file.close() }

            // Read GGUF magic and version
            let magic = file.readData(ofLength: 4)
            guard String(data: magic, encoding: .utf8) == "GGUF" else { return metadata }

            let version = file.readData(ofLength: 4).withUnsafeBytes { $0.load(as: UInt32.self) }
            metadata.formatVersion = String(version)

            // Read metadata key-value pairs
            let metadataKVCount = file.readData(ofLength: 8).withUnsafeBytes { $0.load(as: UInt64.self) }

            for _ in 0..<metadataKVCount {
                if let (key, value) = readGGUFKeyValue(from: file) {
                    switch key {
                    case "general.architecture":
                        metadata.architecture = value as? String
                    case "general.quantization_version":
                        metadata.quantization = value as? String
                    case "llama.context_length":
                        metadata.contextLength = value as? Int
                    case "llama.embedding_length":
                        metadata.embeddingDimension = value as? Int
                    case "llama.block_count":
                        metadata.layerCount = value as? Int
                    default:
                        break
                    }
                }
            }
        }

        return metadata
    }
}

struct ModelMetadata {
    var author: String?
    var description: String?
    var version: String?
    var modelType: String?
    var architecture: String?
    var quantization: String?
    var formatVersion: String?

    var inputShapes: [String: [Int]]?
    var outputShapes: [String: [Int]]?

    var contextLength: Int?
    var embeddingDimension: Int?
    var layerCount: Int?
    var parameterCount: Int64?
    var tensorCount: Int?

    var requirements: ModelRequirements?
}
```

## Phase 3: Optional SDK Modules (Week 5-6)

### 3.1 Module Architecture

The SDK will provide optional modules for common frameworks and providers:

```swift
// Core module (always required)
import RunAnywhere

// Optional modules
import RunAnywhereHuggingFace    // HuggingFace provider
import RunAnywhereCorML          // Core ML adapter
import RunAnywhereGGUF           // GGUF/llama.cpp support
import RunAnywhereONNX           // ONNX runtime
import RunAnywhereProviders      // Model providers
```

### 3.2 Module Implementations

#### HuggingFace Module
- Model discovery from HuggingFace Hub
- Authentication integration
- Metadata extraction
- Download management

#### CoreML Module
- Basic Core ML adapter
- Model compilation support
- Neural Engine optimization
- Common Core ML tokenizers

#### GGUF Module
- GGUF/GGML format support
- Quantization detection
- llama.cpp integration
- Memory-mapped loading

#### ONNX Module
- ONNX runtime adapter
- Execution provider selection
- Session management
- ONNX tokenizer support

#### Providers Module
- Kaggle provider
- Microsoft models provider
- Apple models provider
- Custom provider base classes


## SDK Package Structure

### Target Directory Structure

#### SDK Directory Structure
```
sdk/runanywhere-swift/
├── Package.swift
├── README.md
├── Sources/
│   ├── RunAnywhere/                    # Core module (always included)
│   │   ├── Public/                     # Public API
│   │   │   ├── RunAnywhereSDK.swift   # ✅ Main SDK entry point
│   │   │   ├── Configuration.swift    # ✅ SDK configuration
│   │   │   ├── GenerationOptions.swift # ✅ Generation options
│   │   │   └── GenerationResult.swift  # ✅ Generation results
│   │   ├── Internal/                   # Internal types
│   │   │   └── Types.swift            # ✅ Internal types
│   │   ├── Protocols/                  # All protocol definitions
│   │   │   ├── ModelLifecycleProtocol.swift    # ✅ Lifecycle management
│   │   │   ├── UnifiedTokenizerProtocol.swift  # ✅ Tokenizer abstraction
│   │   │   ├── FrameworkAdapter.swift          # ✅ Framework adapter interface
│   │   │   ├── LLMService.swift               # ✅ Service protocol
│   │   │   ├── HardwareDetector.swift         # ✅ Hardware detection
│   │   │   ├── ModelProvider.swift            # ✅ Model providers
│   │   │   ├── MemoryManager.swift            # ✅ Memory management
│   │   │   ├── ErrorRecoveryStrategy.swift    # ✅ Error recovery
│   │   │   └── AuthProvider.swift             # ✅ Authentication
│   │   ├── Core/                       # Core implementations
│   │   │   └── ModelLifecycleStateMachine.swift # ✅ State machine
│   │   ├── Hardware/                   # Hardware management
│   │   │   └── HardwareCapabilityManager.swift  # ✅ Hardware detection
│   │   ├── Tokenization/              # Tokenizer system
│   │   │   └── UnifiedTokenizerManager.swift    # ✅ Tokenizer management
│   │   ├── Progress/                  # Progress tracking
│   │   │   └── UnifiedProgressTracker.swift     # ✅ Progress system
│   │   ├── ErrorHandling/             # Error handling
│   │   │   └── UnifiedErrorRecovery.swift       # ✅ Error recovery
│   │   ├── Download/                  # ✅ Enhanced download manager
│   │   ├── Registry/                  # ✅ Model registry
│   │   ├── Validation/                # ✅ Model validation
│   │   ├── Memory/                    # ✅ Memory management
│   │   └── RunAnywhere.swift          # ✅ Module entry point
│   │
│   └── [PLANNED - Optional Modules]:
│       ├── RunAnywhereHuggingFace/    # HuggingFace integration
│       ├── RunAnywhereCorML/          # Core ML adapters
│       ├── RunAnywhereGGUF/           # GGUF/llama.cpp support
│       ├── RunAnywhereONNX/           # ONNX runtime support
│       ├── RunAnywhereProviders/      # Model providers
│       └── RunAnywhereSystemModels/   # System models
└── Tests/
    └── RunAnywhereTests/              # Unit tests (to be added)
```

### Package.swift for SDK

```swift
// sdk/runanywhere-swift/Package.swift
import PackageDescription

let package = Package(
    name: "RunAnywhere",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        // Core module (always included)
        .library(
            name: "RunAnywhere",
            targets: ["RunAnywhere"]
        ),
        // Optional modules
        .library(
            name: "RunAnywhereHuggingFace",
            targets: ["RunAnywhereHuggingFace"]
        ),
        .library(
            name: "RunAnywhereCorML",
            targets: ["RunAnywhereCorML"]
        ),
        .library(
            name: "RunAnywhereGGUF",
            targets: ["RunAnywhereGGUF"]
        ),
        .library(
            name: "RunAnywhereONNX",
            targets: ["RunAnywhereONNX"]
        ),
        .library(
            name: "RunAnywhereProviders",
            targets: ["RunAnywhereProviders"]
        ),
        .library(
            name: "RunAnywhereSystemModels",
            targets: ["RunAnywhereSystemModels"]
        ),
    ],
    dependencies: [
        // Archive handling
        .package(url: "https://github.com/1024jp/GzipSwift", from: "6.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.0"),
    ],
    targets: [
        // Core module
        .target(
            name: "RunAnywhere",
            dependencies: [
                .product(name: "Gzip", package: "GzipSwift"),
                "ZIPFoundation"
            ],
            path: "Sources/RunAnywhere"
        ),
        // Optional modules
        .target(
            name: "RunAnywhereHuggingFace",
            dependencies: ["RunAnywhere"],
            path: "Sources/RunAnywhereHuggingFace"
        ),
        .target(
            name: "RunAnywhereCorML",
            dependencies: ["RunAnywhere"],
            path: "Sources/RunAnywhereCorML"
        ),
        .target(
            name: "RunAnywhereGGUF",
            dependencies: ["RunAnywhere"],
            path: "Sources/RunAnywhereGGUF"
        ),
        .target(
            name: "RunAnywhereONNX",
            dependencies: ["RunAnywhere"],
            path: "Sources/RunAnywhereONNX"
        ),
        .target(
            name: "RunAnywhereProviders",
            dependencies: ["RunAnywhere"],
            path: "Sources/RunAnywhereProviders"
        ),
        .target(
            name: "RunAnywhereSystemModels",
            dependencies: ["RunAnywhere"],
            path: "Sources/RunAnywhereSystemModels"
        ),
        // Tests
        .testTarget(
            name: "RunAnywhereTests",
            dependencies: ["RunAnywhere"]
        ),
    ]
)
```


## SDK Public API Design (As Implemented)

### Core Public Interfaces

The SDK exposes a clean, extensible public API:

```swift
// Main SDK entry point - FULLY IMPLEMENTED
public class RunAnywhereSDK {
    public static let shared = RunAnywhereSDK()

    // Configuration
    public func initialize(with config: Configuration) async throws

    // Model operations
    public func loadModel(_ identifier: String) async throws
    public func generate(_ prompt: String, options: GenerationOptions? = nil) async throws -> GenerationResult
    public func streamGenerate(_ prompt: String, options: GenerationOptions? = nil) -> AsyncThrowingStream<String, Error>

    // Context management
    public func setContext(_ context: Context)
    public func updateConfiguration(_ config: Configuration) async throws

    // Component registration (for extensibility)
    public func registerAdapterRegistry(_ registry: FrameworkAdapterRegistry)
    public func registerModelRegistry(_ registry: ModelRegistry)
    public func registerDownloadManager(_ manager: ModelStorageManager)
    public func registerMemoryManager(_ manager: MemoryManager)
    public func registerHardwareDetector(_ detector: HardwareDetector)
}

// Public protocols that must be implemented
public protocol FrameworkAdapter { }
public protocol HardwareDetector { }
public protocol ModelProvider { }
public protocol MetadataExtractorProtocol { }
public protocol TokenizerAdapter { }
public protocol LLMService { }

// Public data types
public struct ModelInfo { }
public struct GenerationOptions { }
public struct GenerationResult { }
public struct ProgressInfo { }
public enum LLMFramework { }
public enum ModelFormat { }
```

### Extension Points

The SDK is designed for extensibility:

1. **Custom Frameworks** - Implement `FrameworkAdapter` and `LLMService`
2. **Custom Model Sources** - Implement `ModelProvider`
3. **Custom Tokenizers** - Implement `TokenizerAdapter`
4. **Platform-Specific Hardware** - Implement `HardwareDetector`
5. **Custom Metadata** - Implement `MetadataExtractorProtocol`

## Phase 4: SDK Integration into RunAnywhereSDK (Week 7)

### 4.1 Update RunAnywhereSDK to Use Unified Architecture

#### Location: `sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhereSDK.swift`

#### Tasks:
1. Integrate all unified components into SDK
2. Provide clean public API
3. Allow framework adapter registration
4. Maintain backward compatibility

#### Implementation:

```swift
// SDK: Sources/RunAnywhere/Public/RunAnywhereSDK.swift
import Foundation

public class RunAnywhereSDK {
    public static let shared = RunAnywhereSDK()

    // Unified components
    private let lifecycleManager = ModelLifecycleStateMachine()
    private let downloadManager = EnhancedDownloadManager()
    private let memoryManager = UnifiedMemoryManager.shared
    private let progressTracker = UnifiedProgressTracker.shared
    private let modelRegistry = DynamicModelRegistry()
    private let hardwareManager = HardwareCapabilityManager.shared
    private let tokenizerManager = UnifiedTokenizerManager.shared
    private let errorRecovery = UnifiedErrorRecovery()

    // Framework adapters registry
    private var frameworkAdapters: [LLMFramework: FrameworkAdapter] = [:]

    // Current state
    private var currentAdapter: FrameworkAdapter?
    private var currentService: LLMService?

    /// Register a framework adapter
    public func registerFrameworkAdapter(_ adapter: FrameworkAdapter) {
        frameworkAdapters[adapter.framework] = adapter
    }

    /// Load a model with optional framework preference
    public func loadModel(_ identifier: String, preferredFramework: LLMFramework? = nil) async throws {
        // Use unified architecture to load model
        let model = try await modelRegistry.findModel(identifier: identifier)

        // Select best framework adapter
        let adapter = preferredFramework.flatMap { frameworkAdapters[$0] }
            ?? findBestAdapter(for: model)

        guard let adapter = adapter else {
            throw SDKError.noCompatibleFramework
        }

        // Use lifecycle manager for loading
        try await loadModelWithAdapter(model, adapter: adapter)
    }

    /// Generate text using loaded model
    public func generate(_ prompt: String, options: GenerationOptions? = nil) async throws -> GenerationResult {
        guard let service = currentService else {
            throw SDKError.modelNotLoaded
        }

        let result = try await service.generate(prompt: prompt, options: options ?? GenerationOptions())

        // Track usage for cost calculation
        return GenerationResult(
            text: result,
            executionTarget: determineExecutionTarget(),
            tokensUsed: calculateTokens(prompt: prompt, response: result),
            costSaved: calculateCostSavings()
        )
    }
}
```


## Migration Timeline

### Week 1-2: Foundation & Protocols ✅ COMPLETED
- [x] Create unified protocol definitions (9 protocol files)
- [x] Implement lifecycle state machine
- [x] Build unified tokenizer system
- [x] Centralize hardware detection
- [x] Integrate with existing SDK types
- [x] Implement RunAnywhereSDK with full routing
- [x] Add progress tracking system
- [x] Add error recovery system

### Week 3-4: Core Services ✅ COMPLETED
- [x] Implement enhanced download manager with archive support
- [x] Build unified memory manager implementation
- [x] Create dynamic model registry
- [x] Add model validation system
- [x] Implement metadata extraction

### Week 5-6: Optional SDK Modules 📋 PLANNED
- [ ] Create HuggingFace module
- [ ] Create CoreML module
- [ ] Create GGUF module
- [ ] Create ONNX module
- [ ] Create Providers module

### Week 7: SDK Testing & Documentation 📋 PLANNED
- [ ] Write comprehensive unit tests
- [ ] Create integration tests
- [ ] Write API documentation
- [ ] Create usage examples

### Week 8: SDK Release Preparation 📋 PLANNED
- [ ] Package optimization
- [ ] Performance benchmarking
- [ ] Security audit
- [ ] Release notes preparation

### Week 9: Validation & Stabilization 📋 PLANNED
- [ ] Validate all migrations complete
- [ ] Verify framework compatibility
- [ ] Performance validation
- [ ] Fix any issues

## Deployment Strategy

### Single Cutover Approach
Since we're replacing the entire implementation without maintaining parallel versions:

1. **Pre-deployment Checklist**
   - [ ] All components implemented
   - [ ] Framework adapters verified
   - [ ] Existing models verified to work
   - [ ] Backup created

2. **Deployment Steps**
   - Stop current version
   - Deploy new unified architecture
   - Run model migration script
   - Verify all frameworks working
   - Monitor for issues

3. **Rollback Plan**
   - Keep backup branch for 2 weeks
   - Database of model paths unchanged
   - Quick revert if critical issues

## Additional Service-Specific Considerations

### LlamaCpp Integration
1. **Binary Dependencies**: llama.cpp requires C++ binaries compiled for iOS
2. **Model Format Detection**: Auto-detect GGUF vs GGML format
3. **Quantization Metadata**: Parse quantization level from model filename
4. **Context Splitting**: Handle models with varying context lengths

### Foundation Models Integration
1. **Platform Gating**: Strict iOS version checking (26+)
2. **No Download Flow**: Skip download manager for system models
3. **Privacy Settings**: Integrate with system privacy preferences
4. **Entitlements**: May require special app entitlements

### PicoLLM Integration
1. **License Validation**: API key must be validated before model loading
2. **Model Registry**: PicoLLM models come from Picovoice's registry
3. **Compression Format**: Custom ultra-compressed format
4. **Wake Word Integration**: Consider integration with Porcupine wake word

### MLC Integration
1. **Compilation Cache**: Essential for performance (compilation is slow)
2. **Target Detection**: Auto-detect optimal compilation target
3. **Model Variants**: Same model may have multiple compiled variants
4. **Storage Management**: Compiled models use more storage

## Risk Mitigation

### Technical Risks
1. **Breaking Changes**
   - Mitigation: Keep old implementation, use feature flags

2. **Performance Regression**
   - Mitigation: Comprehensive benchmarking, A/B testing

3. **Memory Issues**
   - Mitigation: Aggressive testing, memory profiling

4. **Binary Dependencies** (LlamaCpp)
   - Mitigation: Pre-compiled XCFramework, fallback to CPU-only

5. **Platform Requirements** (Foundation Models)
   - Mitigation: Runtime detection, graceful degradation

### Process Risks
1. **Timeline Slippage**
   - Mitigation: Phased approach, can ship incrementally

2. **Integration Issues**
   - Mitigation: Extensive testing, gradual rollout

3. **License Compliance** (PicoLLM)
   - Mitigation: Clear documentation, license validation

### Performance Targets

```swift
struct PerformanceTargets {
    // Loading performance
    static let modelLoadTime: TimeInterval = 5.0 // seconds max
    static let modelSwitchTime: TimeInterval = 2.0 // seconds max

    // Memory targets
    static let memoryOverhead: Double = 1.1 // 10% max overhead vs old implementation
    static let minimumFreeMemory: Int64 = 500_000_000 // 500MB minimum

    // Tokenization performance
    static let tokenizationSpeed: Int = 10000 // tokens/second minimum
    static let decodingSpeed: Int = 5000 // tokens/second minimum

    // Download performance
    static let downloadSpeedEfficiency: Double = 0.8 // 80% of network speed
    static let compressionRatio: Double = 0.7 // 30% size reduction expected

    // Framework switching
    static let frameworkSwitchTime: TimeInterval = 3.0 // seconds max

    // Error recovery
    static let maxRecoveryAttempts: Int = 3
    static let recoverySuccessRate: Double = 0.9 // 90% recovery success
}
```

## Missing Use Cases and Edge Cases

### Edge Cases to Handle

#### 1. Model Format Conflicts
- **Issue**: Same model file with different framework interpretations
- **Solution**: Framework priority system in SDK, override capability in app
```swift
// SDK provides priority mechanism
public protocol FrameworkPriorityResolver {
    func resolveConflict(model: ModelInfo, adapters: [FrameworkAdapter]) -> FrameworkAdapter?
}
```

#### 2. Partial Download Recovery
- **Issue**: Large model downloads interrupted
- **Solution**: Resume capability in download manager
```swift
// SDK implementation
class EnhancedDownloadManager {
    func resumeDownload(taskId: String, from: Int64) async throws -> DownloadTask
}
```

#### 3. Multi-Model Memory Pressure
- **Issue**: Loading multiple models causing memory warnings
- **Solution**: Intelligent model eviction and priority queuing
```swift
// SDK provides eviction policy
enum EvictionPolicy {
    case leastRecentlyUsed
    case leastFrequentlyUsed
    case largestFirst
    case custom((LoadedModel, LoadedModel) -> Bool)
}
```

#### 4. Framework Version Conflicts
- **Issue**: Different frameworks requiring different versions of dependencies
- **Solution**: Dynamic framework loading with version checking

#### 5. Corrupted Model Recovery
- **Issue**: Model files corrupted during download or storage
- **Solution**: Checksum validation and automatic re-download

### Additional Use Cases

#### 1. Offline Model Management
- **Requirement**: Work without network connectivity
- **Implementation**: Local model discovery, offline-first design

#### 2. Model Preloading
- **Requirement**: Preload models for instant switching
- **Implementation**: Background loading queue with priority

#### 3. A/B Testing Support
- **Requirement**: Compare different models/frameworks
- **Implementation**: Parallel model loading and result comparison

#### 4. Custom Model Formats
- **Requirement**: Support proprietary model formats
- **Implementation**: Extensible format detection and adapter system

#### 5. Model Version Management
- **Requirement**: Handle multiple versions of same model
- **Implementation**: Version tracking in model registry

#### 6. Cross-Device Model Sync
- **Requirement**: Sync models across user's devices
- **Implementation**: Model manifest with cloud sync capability

#### 7. Background Model Updates
- **Requirement**: Update models without user intervention
- **Implementation**: Background download with notification system

#### 8. Model Warmup
- **Requirement**: Prepare models for first use
- **Implementation**: Warmup protocol in framework adapter

#### 9. Quantization Selection
- **Requirement**: Choose optimal quantization based on device
- **Implementation**: Automatic quantization level selection

#### 10. Model Chaining
- **Requirement**: Use output of one model as input to another
- **Implementation**: Pipeline support in SDK

## Success Criteria

### SDK Success Metrics

1. **API Design**
   - Clean, intuitive public API
   - Well-documented interfaces
   - Easy framework adapter registration
   - Flexible for different use cases

2. **Functionality**
   - All core features working
   - Proper error propagation
   - Progress tracking exposed
   - Memory management effective

3. **Performance**
   - Minimal overhead vs direct implementation
   - Efficient resource management
   - Fast model switching
   - Low memory footprint

### Sample App Success Metrics

1. **Framework Coverage**
   - All 10 frameworks implemented
   - Framework-specific features preserved
   - Proper adapter pattern usage
   - Clean separation from SDK

2. **Developer Experience**
   - Clear example of SDK usage
   - Well-organized code structure
   - Easy to understand patterns
   - Good testing coverage

3. **User Experience**
   - Intuitive UI for model selection
   - Real-time progress updates
   - Clear error messages
   - Performance metrics display



## Enhanced SDK Architecture Benefits

### Immediate Out-of-the-Box Value

1. **Working Defaults**
   - Built-in hardware detection for iOS/Android
   - Common format support (CoreML, ONNX, GGUF, etc.)
   - Popular tokenizers included
   - Basic authentication framework

2. **Modular Enhancement**
   - Start with core, add modules as needed
   - HuggingFace integration ready to use
   - Framework adapters for quick prototyping
   - Progressive complexity management

3. **Developer Experience**
   - Single line model loading with smart defaults
   - Automatic framework selection
   - Built-in progress tracking
   - Comprehensive error recovery

### For Advanced Users

1. **Full Extensibility**
   - Override any default implementation
   - Create custom framework adapters
   - Build proprietary model providers
   - Implement specialized tokenizers

2. **Performance Optimization**
   - Custom hardware detection strategies
   - Framework-specific optimizations
   - Memory management customization
   - Advanced caching strategies

3. **Enterprise Features**
   - Custom authentication providers
   - Compliance and security extensions
   - Advanced monitoring and analytics
   - Multi-tenant support

### Comparison with Top SDKs

| Feature | RunAnywhere | Firebase | Stripe | AWS SDK |
|---------|------------|----------|---------|----------|
| Modular Architecture | ✓ | ✓ | ✓ | ✓ |
| Working Defaults | ✓ | ✓ | ✓ | ✓ |
| Optional Modules | ✓ | ✓ | ✓ | ✓ |
| Custom Extensions | ✓ | ✓ | ✓ | ✓ |
| Progressive Enhancement | ✓ | ✓ | ✓ | ✗ |
| Built-in Providers | ✓ | ✓ | ✓ | ✓ |

### Migration Impact

1. **Reduced Sample App Complexity**
   - Focus on advanced examples
   - Demonstrate extensibility
   - Show best practices
   - UI/UX reference implementation

2. **SDK Adoption**
   - Lower barrier to entry
   - Faster time to first model
   - Clear upgrade path
   - Community-friendly architecture

## Implementation Guidelines

### SDK Development

1. **Keep It Lean**
   - Only essential functionality
   - Well-defined protocols
   - Minimal dependencies
   - Clear documentation

2. **Design for Extension**
   - Protocol-oriented design
   - Dependency injection
   - Observable patterns
   - Async/await throughout

3. **Provide Defaults**
   - Sensible default implementations
   - Common tokenizer formats
   - Basic error recovery
   - Standard progress tracking


## Conclusion

This migration plan separates the unified LLM architecture into:

1. **RunAnywhere SDK** - Core infrastructure and abstractions
2. **Sample App** - Framework implementations and UI

This separation provides:

- **Flexibility** for developers to implement custom frameworks
- **Maintainability** through clear separation of concerns
- **Reusability** of core components across projects
- **Scalability** for adding new frameworks and features

The SDK becomes a powerful foundation for any iOS app using on-device language models, while the sample app demonstrates best practices and provides reference implementations for all supported frameworks.
