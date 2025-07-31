# LLM Unified Architecture Migration Plan

## Executive Summary

This document provides a comprehensive, step-by-step plan for migrating the current RunAnywhereAI iOS LLM framework implementation to the proposed unified architecture. The migration includes framework-specific details, cleanup instructions, and a phased approach that completely replaces the old implementation rather than maintaining parallel versions.

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
1. **Complete Replacement** - Replace old implementation entirely, no v1/v2 parallel systems
2. **Clean Architecture** - Remove all legacy code and technical debt
3. **Phased Approach** - Small, manageable phases with clear boundaries
4. **Framework Preservation** - Maintain core framework logic while unifying interfaces

## Phase 1: Foundation Layer (Week 1-2)

### 1.1 Core Protocol Definitions

#### Tasks:
1. Create new protocol files in `Services/UnifiedArchitecture/Protocols/`
2. Define core interfaces without breaking existing code

#### Implementation:

```swift
// Services/UnifiedArchitecture/Protocols/ModelLifecycleProtocol.swift
protocol ModelLifecycleManager {
    var currentState: ModelLifecycleState { get }
    func transitionTo(_ state: ModelLifecycleState) async throws
    func addObserver(_ observer: ModelLifecycleObserver)
}

// Services/UnifiedArchitecture/Protocols/UnifiedTokenizerProtocol.swift
protocol UnifiedTokenizer {
    func encode(_ text: String) -> [Int]
    func decode(_ tokens: [Int]) -> String
    var vocabularySize: Int { get }
}

// Services/UnifiedArchitecture/Protocols/ModelLoaderProtocol.swift
protocol UnifiedModelLoader {
    func loadModel(_ model: ModelInfo) async throws -> LoadedModel
    func detectOptimalFramework(for model: ModelInfo) -> LLMFramework
}
```

### 1.2 State Machine Implementation

#### Tasks:
1. Implement `ModelLifecycleStateMachine` class
2. Add state transition validation
3. Create observer pattern for state changes

#### Implementation:

```swift
// Services/UnifiedArchitecture/Core/ModelLifecycleStateMachine.swift
class ModelLifecycleStateMachine: ModelLifecycleManager {
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

### 1.3 Unified Tokenizer System

#### Tasks:
1. Create `UnifiedTokenizerManager` 
2. Build tokenizer adapters for existing implementations
3. Implement automatic tokenizer discovery

#### Implementation:

```swift
// Services/UnifiedArchitecture/Tokenization/UnifiedTokenizerManager.swift
class UnifiedTokenizerManager {
    static let shared = UnifiedTokenizerManager()
    
    private var tokenizers: [String: UnifiedTokenizer] = [:]
    private var adapters: [TokenizerFormat: TokenizerAdapter.Type] = [:]
    
    init() {
        registerDefaultAdapters()
    }
    
    private func registerDefaultAdapters() {
        // Wrap existing tokenizers
        adapters[.bpe] = BPETokenizerAdapter.self
        adapters[.sentencePiece] = SentencePieceAdapter.self
        adapters[.wordPiece] = WordPieceAdapter.self
        adapters[.tflite] = TFLiteTokenizerAdapter.self
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

// Adapter example wrapping existing tokenizer
class BPETokenizerAdapter: UnifiedTokenizer {
    private let wrapped: GenericBPETokenizer
    
    init(modelPath: URL) throws {
        self.wrapped = try GenericBPETokenizer(modelPath: modelPath)
    }
    
    func encode(_ text: String) -> [Int] {
        return wrapped.encode(text)
    }
    
    func decode(_ tokens: [Int]) -> String {
        return wrapped.decode(tokens)
    }
}
```

### 1.4 Hardware Abstraction Layer

#### Tasks:
1. Centralize hardware detection
2. Create capability-based configuration
3. Remove duplicate detection code

#### Implementation:

```swift
// Services/UnifiedArchitecture/Hardware/HardwareCapabilityManager.swift
class HardwareCapabilityManager {
    static let shared = HardwareCapabilityManager()
    
    private lazy var capabilities: DeviceCapabilities = detectCapabilities()
    
    func optimalConfiguration(for model: ModelInfo) -> HardwareConfiguration {
        var config = HardwareConfiguration()
        
        // Smart selection based on model size and device
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
        
        config.threadCount = ProcessInfo.processInfo.processorCount
        
        return config
    }
    
    private func detectCapabilities() -> DeviceCapabilities {
        // Centralized detection logic
        var caps = DeviceCapabilities()
        
        // Neural Engine detection
        caps.hasNeuralEngine = detectNeuralEngine()
        
        // Memory
        caps.totalMemory = ProcessInfo.processInfo.physicalMemory
        caps.availableMemory = getAvailableMemory()
        
        // GPU
        caps.hasGPU = MTLCreateSystemDefaultDevice() != nil
        
        return caps
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

struct ResourceAvailability {
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

## Phase 2: Core Services (Week 3-4)

### 2.1 Enhanced Download Manager

#### Tasks:
1. Add queue-based download management
2. Implement retry with exponential backoff
3. Add comprehensive archive extraction support
4. Create progress tracking system

#### Implementation:

```swift
// Services/UnifiedArchitecture/Download/EnhancedDownloadManager.swift
import Gzip // Add to Package.swift

class EnhancedDownloadManager: ModelStorageManager {
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

### 2.2 Memory Management System

#### Tasks:
1. Implement coordinated memory management
2. Add memory pressure handling
3. Create model unloading strategy
4. Add memory usage tracking

#### Implementation:

```swift
// Services/UnifiedArchitecture/Memory/UnifiedMemoryManager.swift
class UnifiedMemoryManager {
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

### 2.3 Model Validation System

#### Tasks:
1. Implement comprehensive model validation
2. Add checksum verification
3. Create format validation
4. Build dependency checking

#### Implementation:

```swift
// Services/UnifiedArchitecture/Validation/ModelValidator.swift
protocol ModelValidator {
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

### 2.4 Model Registry & Discovery

#### Tasks:
1. Create dynamic model discovery
2. Build model compatibility matrix
3. Implement runtime model detection
4. Add model metadata caching
5. Integrate authentication services
6. Add storage monitoring

#### Implementation:

```swift
// Services/UnifiedArchitecture/Registry/DynamicModelRegistry.swift
class DynamicModelRegistry: ModelRegistry {
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

### 2.5 Progress Tracking System

#### Tasks:
1. Implement stage-based progress tracking
2. Add time estimation
3. Create unified progress reporting
4. Build progress aggregation for multiple operations

#### Implementation:

```swift
// Services/UnifiedArchitecture/Progress/UnifiedProgressTracker.swift
class UnifiedProgressTracker: ProgressTracker {
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

### 2.6 Error Recovery Strategy

#### Tasks:
1. Implement comprehensive error recovery
2. Create recovery strategies for different error types
3. Add automatic retry mechanisms
4. Build error context preservation

#### Implementation:

```swift
// Services/UnifiedArchitecture/ErrorHandling/ErrorRecoveryStrategy.swift
protocol ErrorRecoveryStrategy {
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

### 2.7 Model Metadata Extraction

#### Tasks:
1. Implement metadata extraction for each model format
2. Create unified metadata structure
3. Add caching for extracted metadata
4. Build format-specific extractors

#### Implementation:

```swift
// Services/UnifiedArchitecture/Metadata/MetadataExtractor.swift
class MetadataExtractor {
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

## Phase 3: Framework-Specific Migration Details

### 3.0 Framework Analysis Summary

Based on the analysis of all framework implementations, here are the specific migration requirements for each:

#### CoreMLService Specifics
- **Model Adapters**: Uses `CoreMLModelAdapter` factory pattern - preserve this
- **Tokenizer Adapters**: `TokenizerAdapterFactory` creates model-specific adapters
- **Compilation Logic**: Complex .mlmodel compilation to .mlmodelc - must preserve
- **Directory Models**: Special handling for .mlpackage directories
- **Hardware Detection**: Neural Engine detection logic - centralize this
- **Sliding Window**: Context management with maxSequenceLength - preserve

#### TFLiteService Specifics
- **Delegates**: Complex CoreML/Metal delegate configuration - preserve
- **CocoaPods Dependency**: Framework availability checks needed
- **Tensor Management**: Manual tensor shape handling - abstract this
- **Kaggle Auth**: Some models require authentication - integrate with KeychainService
- **Limited Formats**: Only .tflite support, no archive handling

#### MLXService Specifics
- **Archive Handling**: Models come as tar.gz - needs extraction support
- **Directory Structure**: Complex multi-file models (config.json, weights.safetensors)
- **Device Requirements**: A17 Pro/M3+ checking - centralize
- **Custom Tokenizer**: Internal MLXTokenizer implementation
- **Unified Memory**: Special memory architecture considerations

#### SwiftTransformersService Specifics
- **Strict Requirements**: Models must have 'input_ids' input
- **Bundled Models**: Legacy support for app bundle models - remove
- **Metadata Validation**: Checks for hub identifiers and structure
- **Compilation**: Reuses Core ML compilation logic
- **Limited Models**: Very specific model requirements

#### ONNXService Specifics
- **Execution Providers**: CoreML/CPU provider selection
- **Session Management**: ORTEnv and ORTSession lifecycle
- **Custom Tokenizer**: Basic ONNX tokenizer implementation
- **Format Support**: .onnx and .ort files

#### ExecuTorchService Specifics
- **Module Pattern**: Uses Module class for loading
- **PTE Format**: PyTorch Edge format only
- **Tokenizer Files**: Separate tokenizer file support
- **Manual Loop**: Requires manual generation loop

#### LlamaCppService Specifics
- **Format Support**: GGUF and GGML formats - extensive quantization support
- **Hardware**: Metal and CPU acceleration
- **Quantization**: Supports Q2, Q3, Q4, Q5, Q6, Q8 quantization formats
- **Context Length**: Variable context length up to 32768 tokens
- **Streaming**: Native streaming support
- **Batching**: Supports batch inference
- **Memory Mapping**: Efficient memory-mapped model loading

#### FoundationModelsService Specifics (iOS 18+)
- **Apple Integration**: Uses Apple's Foundation Models framework
- **Model Size**: ~3B parameter models
- **Platform Requirements**: iOS 26+, Xcode 26 beta required
- **System Integration**: Deep OS integration with privacy features
- **Model Access**: System-provided models, no download needed
- **Privacy**: Differential privacy and on-device processing

#### PicoLLMService Specifics
- **Ultra-Compressed Models**: Optimized for edge devices
- **Memory Efficiency**: Extremely low memory footprint
- **Low Latency**: Optimized for real-time responses
- **Offline Capable**: No network connectivity required
- **Pre-trained Models**: Uses Picovoice's pre-trained models
- **License**: Requires Picovoice API key

#### MLCService Specifics
- **Universal Deployment**: Machine Learning Compilation approach
- **Multi-Backend**: Supports various hardware backends
- **Model Compilation**: JIT compilation for target hardware
- **Format Support**: Supports compiled model formats
- **Memory Efficiency**: Optimized memory usage through compilation
- **High Throughput**: Optimized for batch processing

## Phase 4: Framework Adapters (Week 5-6)

### 3.1 Base Framework Adapter

#### Tasks:
1. Create base adapter class
2. Define common adapter interface
3. Implement shared functionality
4. Build adapter factory

#### Implementation:

```swift
// Services/UnifiedArchitecture/Adapters/BaseFrameworkAdapter.swift
protocol FrameworkAdapter {
    var framework: LLMFramework { get }
    var supportedFormats: [ModelFormat] { get }
    
    func canHandle(model: ModelInfo) -> Bool
    func createService() -> LLMService
    func configure(with hardware: HardwareConfiguration) async
}

class BaseFrameworkAdapter: FrameworkAdapter {
    let framework: LLMFramework
    let supportedFormats: [ModelFormat]
    
    private let hardwareManager = HardwareCapabilityManager.shared
    private let progressTracker = UnifiedProgressTracker()
    private let memoryManager = UnifiedMemoryManager.shared
    
    init(framework: LLMFramework, formats: [ModelFormat]) {
        self.framework = framework
        self.supportedFormats = formats
    }
    
    func canHandle(model: ModelInfo) -> Bool {
        // Check format compatibility
        guard supportedFormats.contains(model.format) else {
            return false
        }
        
        // Check hardware requirements
        let hardware = hardwareManager.capabilities
        return model.hardwareRequirements.allSatisfy { req in
            hardware.supports(req)
        }
    }
    
    func configure(with hardware: HardwareConfiguration) async {
        // Base configuration applicable to all frameworks
    }
}
```

### 4.2 Framework-Specific Adapter Implementations

#### Tasks:
1. Create adapter for each framework preserving core logic
2. Extract framework-specific code into adapters
3. Implement unified interface while maintaining functionality
4. Handle framework-specific requirements

#### Core ML Adapter (Preserving Existing Logic):

```swift
// Services/UnifiedArchitecture/Adapters/CoreMLFrameworkAdapter.swift
class CoreMLFrameworkAdapter: BaseFrameworkAdapter {
    init() {
        super.init(
            framework: .coreML,
            formats: [.mlmodel, .mlpackage]
        )
    }
    
    func createService() -> LLMService {
        // Wrap existing CoreMLService with unified interface
        return UnifiedCoreMLService()
    }
}

// IMPORTANT: This is a WRAPPER, not inheritance
// We preserve ALL existing CoreMLService logic
class UnifiedCoreMLAdapter: LLMService {
    private let coreMLService = CoreMLService() // Existing service
    private let lifecycleManager = ModelLifecycleStateMachine()
    private let tokenizerManager = UnifiedTokenizerManager.shared
    private let progressTracker = UnifiedProgressTracker()
    
    // Preserve existing model adapter factory
    private let adapterFactory = CoreMLAdapterFactory.self
    
    func initialize(modelPath: String) async throws {
        try await lifecycleManager.transitionTo(.initializing)
        progressTracker.startStage(.initialization)
        
        do {
            // Use EXISTING CoreMLService initialization
            try await coreMLService.initialize(modelPath: modelPath)
            
            // Wrap existing tokenizer adapter with unified interface
            if let existingAdapter = coreMLService.tokenizerAdapter {
                let unifiedAdapter = CoreMLTokenizerWrapper(existing: existingAdapter)
                tokenizerManager.registerTokenizer(unifiedAdapter, for: modelPath)
            }
            
            progressTracker.completeStage(.initialization)
            try await lifecycleManager.transitionTo(.initialized)
        } catch {
            progressTracker.failStage(.initialization, error: error)
            try await lifecycleManager.transitionTo(.error(error))
            throw UnifiedModelError.framework(
                FrameworkError(framework: .coreML, underlying: error)
            )
        }
    }
    
    // Delegate all operations to existing service
    func generate(prompt: String, options: GenerationOptions) async throws -> String {
        try await coreMLService.generate(prompt: prompt, options: options)
    }
    
    // PRESERVE: Model compilation logic
    private func preserveCompilationLogic() {
        // The existing compilation logic in CoreMLService.initialize() 
        // lines 110-145 is preserved and called through delegation
    }
    
    // PRESERVE: Model adapter pattern
    private func preserveAdapterPattern() {
        // CoreMLAdapterFactory.createAdapter() logic preserved
        // GPT2CoreMLAdapter and other adapters remain unchanged
    }
}
```

#### TensorFlow Lite Adapter (Preserving Delegate Logic):

```swift
// Services/UnifiedArchitecture/Adapters/TFLiteFrameworkAdapter.swift
class UnifiedTFLiteAdapter: LLMService {
    private let tfliteService = TFLiteService()
    private let lifecycleManager = ModelLifecycleStateMachine()
    
    // PRESERVE: Complex delegate configuration
    private func preserveDelegateConfiguration() {
        // Lines 99-121 in TFLiteService - delegate selection logic
        // This MUST be preserved as-is for proper acceleration
    }
    
    // PRESERVE: Tensor shape management
    private func preserveTensorHandling() {
        // Lines 283-300 - createTensorInput logic
        // Critical for proper model input formatting
    }
    
    // INTEGRATE: Kaggle authentication
    func initialize(modelPath: String) async throws {
        // Check if model requires Kaggle auth
        if requiresKaggleAuth(modelPath) {
            let kaggleService = KaggleAuthService.shared
            guard kaggleService.hasValidCredentials() else {
                throw UnifiedModelError.authRequired("Kaggle")
            }
        }
        
        try await tfliteService.initialize(modelPath: modelPath)
    }
}
```

#### MLX Adapter (Handling Archives & Device Requirements):

```swift
class UnifiedMLXAdapter: LLMService {
    private let mlxService = MLXService()
    private let downloadManager = EnhancedDownloadManager()
    
    // PRESERVE: Device compatibility checking
    private func checkDeviceRequirements() throws {
        // A17 Pro/M3+ requirement from MLXService.isMLXSupported()
        guard ProcessInfo.processInfo.processorHasARM64E else {
            throw UnifiedModelError.deviceNotSupported("MLX requires A17 Pro/M3+")
        }
    }
    
    // HANDLE: Archive extraction
    func initialize(modelPath: String) async throws {
        try checkDeviceRequirements()
        
        // Check if model needs extraction
        if modelPath.hasSuffix(".tar.gz") {
            let extracted = try await downloadManager.extractTarGz(URL(fileURLWithPath: modelPath))
            try await mlxService.initialize(modelPath: extracted.path)
        } else {
            try await mlxService.initialize(modelPath: modelPath)
        }
    }
    
    // PRESERVE: MLXModelWrapper directory structure handling
    private func preserveDirectoryHandling() {
        // Lines 33-59 in MLXService - directory vs file detection
    }
}
```

#### Swift Transformers Adapter (Strict Validation):

```swift
class UnifiedSwiftTransformersAdapter: LLMService {
    private let swiftTransformersService = SwiftTransformersService()
    
    // PRESERVE: Strict model validation
    private func validateModelCompatibility(_ modelPath: String) throws {
        // Lines 188-209 - input_ids validation
        // This is CRITICAL - Swift Transformers will crash without proper inputs
    }
    
    // REMOVE: Bundled model support
    func initialize(modelPath: String) async throws {
        // Remove lines 122-131 - bundled model checking
        // All models must be downloaded, not bundled
        
        try validateModelCompatibility(modelPath)
        try await swiftTransformersService.initialize(modelPath: modelPath)
    }
}
```

#### LlamaCpp Adapter (GGUF/GGML Support):

```swift
class UnifiedLlamaCppAdapter: LLMService {
    private let llamaCppService = LlamaCppService()
    private let lifecycleManager = ModelLifecycleStateMachine()
    
    // PRESERVE: Quantization format handling
    private func detectQuantizationFormat(_ modelPath: String) -> QuantizationFormat? {
        // Detect Q2, Q3, Q4, Q5, Q6, Q8 formats from filename or metadata
    }
    
    // PRESERVE: Memory mapping
    func initialize(modelPath: String) async throws {
        try await lifecycleManager.transitionTo(.initializing)
        
        // Check format
        guard modelPath.hasSuffix(".gguf") || modelPath.hasSuffix(".ggml") else {
            throw UnifiedModelError.unsupportedFormat("LlamaCpp requires GGUF/GGML")
        }
        
        // Configure hardware acceleration
        let hardware = HardwareCapabilityManager.shared.capabilities
        if hardware.hasGPU {
            llamaCppService.enableMetalAcceleration()
        }
        
        try await llamaCppService.initialize(modelPath: modelPath)
        try await lifecycleManager.transitionTo(.initialized)
    }
    
    // PRESERVE: Streaming capabilities
    func streamGenerate(prompt: String, options: GenerationOptions, onToken: @escaping (String) -> Void) async throws {
        try await llamaCppService.streamGenerate(prompt: prompt, options: options, onToken: onToken)
    }
}
```

#### Foundation Models Adapter (iOS 18+ System Models):

```swift
@available(iOS 18.0, *)
class UnifiedFoundationModelsAdapter: LLMService {
    private let foundationService = FoundationModelsService()
    
    // SPECIAL: No model download needed
    func initialize(modelPath: String) async throws {
        // Foundation Models are system-provided
        // modelPath is ignored or used as identifier only
        
        guard #available(iOS 26.0, *) else {
            throw UnifiedModelError.platformNotSupported("Foundation Models require iOS 26+")
        }
        
        try await foundationService.initialize(modelPath: "system")
    }
    
    // PRESERVE: Privacy features
    func configurePrivacy(options: PrivacyOptions) {
        foundationService.setDifferentialPrivacy(enabled: options.differentialPrivacy)
        foundationService.setOnDeviceOnly(options.onDeviceOnly)
    }
}
```

#### PicoLLM Adapter (Ultra-Compressed Models):

```swift
class UnifiedPicoLLMAdapter: LLMService {
    private let picoService = PicoLLMService()
    private let keychain = KeychainService.shared
    
    // REQUIRE: API key validation
    func initialize(modelPath: String) async throws {
        // Check for Picovoice API key
        guard let apiKey = try? keychain.retrieveAPIKey(for: "picovoice") else {
            throw UnifiedModelError.authRequired("Picovoice API key required")
        }
        
        picoService.setAPIKey(apiKey)
        
        // PicoLLM models are pre-optimized
        try await picoService.initialize(modelPath: modelPath)
    }
    
    // PRESERVE: Edge optimization
    func configureForEdge() {
        picoService.setLowLatencyMode(true)
        picoService.setMemoryOptimization(.aggressive)
    }
}
```

#### MLC Adapter (Universal Compilation):

```swift
class UnifiedMLCAdapter: LLMService {
    private let mlcService = MLCService()
    private let compilationCache = CompilationCache.shared
    
    // PRESERVE: JIT compilation
    func initialize(modelPath: String) async throws {
        // Check if model is already compiled for this device
        let deviceId = HardwareCapabilityManager.shared.deviceIdentifier
        let cacheKey = "\(modelPath)-\(deviceId)"
        
        if let compiledPath = compilationCache.getCompiledModel(key: cacheKey) {
            try await mlcService.initialize(modelPath: compiledPath)
        } else {
            // Compile for current hardware
            let compiled = try await compileForDevice(modelPath)
            compilationCache.store(key: cacheKey, path: compiled)
            try await mlcService.initialize(modelPath: compiled)
        }
    }
    
    private func compileForDevice(_ modelPath: String) async throws -> String {
        let hardware = HardwareCapabilityManager.shared.capabilities
        
        var target = "auto"
        if hardware.hasNeuralEngine {
            target = "apple-neural-engine"
        } else if hardware.hasGPU {
            target = "metal"
        }
        
        return try await mlcService.compile(modelPath: modelPath, target: target)
    }
}
```

### 3.3 Adapter Registry & Factory

#### Tasks:
1. Create adapter registry
2. Implement automatic adapter selection
3. Build adapter caching
4. Add adapter configuration

#### Implementation:

```swift
// Services/UnifiedArchitecture/Adapters/FrameworkAdapterRegistry.swift
class FrameworkAdapterRegistry {
    static let shared = FrameworkAdapterRegistry()
    
    private var adapters: [LLMFramework: FrameworkAdapter] = [:]
    
    init() {
        registerDefaultAdapters()
    }
    
    private func registerDefaultAdapters() {
        register(CoreMLFrameworkAdapter())
        register(TFLiteFrameworkAdapter())
        register(MLXFrameworkAdapter())
        register(SwiftTransformersAdapter())
        register(ONNXFrameworkAdapter())
        register(ExecuTorchAdapter())
        register(LlamaCppFrameworkAdapter())
        register(FoundationModelsAdapter())
        register(PicoLLMFrameworkAdapter())
        register(MLCFrameworkAdapter())
    }
    
    func register(_ adapter: FrameworkAdapter) {
        adapters[adapter.framework] = adapter
    }
    
    func getAdapter(for framework: LLMFramework) -> FrameworkAdapter? {
        return adapters[framework]
    }
    
    func findBestAdapter(for model: ModelInfo) -> FrameworkAdapter? {
        // Get hardware capabilities
        let hardware = HardwareCapabilityManager.shared.capabilities
        
        // Score each adapter
        let scores = adapters.values.compactMap { adapter -> (FrameworkAdapter, Double)? in
            guard adapter.canHandle(model: model) else { return nil }
            
            let score = calculateScore(
                adapter: adapter,
                model: model,
                hardware: hardware
            )
            
            return (adapter, score)
        }
        
        // Return highest scoring adapter
        return scores.max(by: { $0.1 < $1.1 })?.0
    }
    
    private func calculateScore(
        adapter: FrameworkAdapter,
        model: ModelInfo,
        hardware: DeviceCapabilities
    ) -> Double {
        var score = 0.0
        
        // Hardware optimization score
        if adapter.framework == .coreML && hardware.hasNeuralEngine {
            score += 10.0
        }
        
        // Memory efficiency score
        let memoryScore = adapter.estimatedMemoryEfficiency(for: model)
        score += memoryScore * 5.0
        
        // Performance score
        let perfScore = adapter.estimatedPerformance(for: model, on: hardware)
        score += perfScore * 8.0
        
        return score
    }
}
```

## Phase 5: Cleanup & Code Removal (Week 7)

### 5.1 Remove Legacy Code

#### Files to DELETE Completely:
```
Services/
├── UnifiedLLMService.swift (DELETE - replaced by new implementation)
├── BundledModelsService.swift (DELETE - no more bundled models)
├── ModelURLRegistry.swift (DELETE - replaced by DynamicModelRegistry)
├── Tokenization/
│   ├── BaseTokenizer.swift (DELETE - replaced by unified system)
│   ├── TokenizerFactory.swift (DELETE - replaced by UnifiedTokenizerManager)
│   └── TokenizerAdapterFactory.swift (DELETE - integrated into unified)
└── ModelManagement/
    └── ModelCompatibilityChecker.swift (DELETE - integrated into registry)
```

#### Code to REMOVE from existing files:

**1. Remove from all LLMService implementations:**
```swift
// DELETE these properties from each service:
override var supportedModels: [ModelInfo] {
    get { ModelURLRegistry.shared.getAllModels(for: .xxx) }
    set { }
}

// DELETE hardcoded model lists
// DELETE duplicate hardware detection code
// DELETE basic error handling
```

**2. Remove from CoreMLService:**
```swift
// DELETE lines 319-341: isNeuralEngineAvailable() 
// Replaced by HardwareCapabilityManager

// DELETE manual tokenizer adapter creation (lines 166-174)
// Replaced by UnifiedTokenizerManager
```

**3. Remove from TFLiteService:**
```swift
// DELETE duplicate delegate configuration logic
// Keep only the core configuration, remove UI decisions
```

**4. Remove from SwiftTransformersService:**
```swift
// DELETE lines 122-131: Bundled model support
// DELETE all references to app bundle models
```

### 5.2 Consolidate Duplicate Code

#### Hardware Detection Consolidation:
```swift
// CREATE: Services/UnifiedArchitecture/Hardware/HardwareDetection.swift
// MOVE all hardware detection from:
// - CoreMLService.isNeuralEngineAvailable()
// - TFLiteService.DeviceCapabilities
// - MLXService.isMLXSupported()
// - DeviceCapabilities.swift
// INTO: HardwareCapabilityManager
```

#### Tokenizer Consolidation:
```swift
// MOVE all tokenizers to unified system:
// - TFLiteTokenizer → TFLiteTokenizerAdapter
// - MLXTokenizer → MLXTokenizerAdapter  
// - ONNXTokenizer → ONNXTokenizerAdapter
// - GenericBPETokenizer → BPETokenizerAdapter
```

### 5.3 Update Dependencies

#### Package.swift Updates:
```swift
dependencies: [
    // ADD:
    .package(url: "https://github.com/1024jp/GzipSwift", from: "6.0.0"),
    
    // KEEP existing:
    .package(url: "https://github.com/apple/swift-transformers", from: "0.1.22"),
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.25.0"),
    // etc...
]
```

#### Remove CocoaPods (if migrating to SPM):
```bash
# Optional: If moving TensorFlow Lite to SPM
rm Podfile Podfile.lock
rm -rf Pods/
# Update .gitignore
```

## Phase 6: Integration Layer (Week 8)

### 6.1 Replace UnifiedLLMService

#### Tasks:
1. Replace existing UnifiedLLMService completely
2. No v1/v2 versioning - direct replacement
3. Maintain same public API for compatibility
4. Remove all feature flags

#### Implementation:

```swift
// Services/UnifiedLLMService.swift (REPLACE ENTIRE FILE)
@MainActor
class UnifiedLLMService: ObservableObject {
    static let shared = UnifiedLLMService()
    
    // SAME public interface - no breaking changes
    @Published var currentService: LLMService?
    @Published var isLoading = false
    @Published var error: Error?
    @Published var currentFramework: LLMFramework?
    @Published var currentModel: ModelInfo?
    
    // New unified components (private)
    private let modelRegistry = DynamicModelRegistry()
    private let lifecycleManager = ModelLifecycleStateMachine()
    private let downloadManager = EnhancedDownloadManager()
    private let memoryManager = UnifiedMemoryManager.shared
    private let progressTracker = UnifiedProgressTracker()
    private let adapterRegistry = FrameworkAdapterRegistry.shared
    private let tokenizerManager = UnifiedTokenizerManager.shared
    
    // PUBLIC API - Keep exactly the same
    func loadModel(_ model: ModelInfo, framework: LLMFramework? = nil) async throws {
        NSLog("🔍 UnifiedService.loadModel called with model: %@, framework: %@", 
              model.name, framework?.displayName ?? "auto")
        
        // Direct implementation - no feature flags
        try await loadModelImpl(model, framework: framework)
    }
    
    private func loadModelImpl(_ model: ModelInfo, framework: LLMFramework?) async throws {
        let errorRecovery = UnifiedErrorRecovery()
        let validator = UnifiedModelValidator()
        let metadataExtractor = MetadataExtractor()
        
        // Check resource availability first
        let resources = HardwareCapabilityManager.shared.checkResourceAvailability()
        let (canLoad, reason) = resources.canLoad(model: model)
        if !canLoad {
            throw UnifiedModelError.resourceUnavailable(reason ?? "Insufficient resources")
        }
        
        // Start lifecycle
        try await lifecycleManager.transitionTo(.discovered(model))
        
        // Download if needed
        if model.localPath == nil {
            try await lifecycleManager.transitionTo(.downloading(progress: 0))
            
            do {
                let downloadTask = try await downloadManager.downloadModel(model)
                let localPath = try await downloadTask.result.value
                model.localPath = localPath
                try await lifecycleManager.transitionTo(.downloaded(location: localPath))
            } catch {
                let context = RecoveryContext(
                    model: model,
                    stage: .download,
                    attemptCount: 1,
                    previousErrors: [error],
                    availableResources: resources
                )
                try await errorRecovery.attemptRecovery(from: error, in: context)
                // Retry after recovery
                return try await loadModelImpl(model, framework: framework)
            }
        }
        
        // Extract if needed
        if downloadManager.needsExtraction(model.localPath!) {
            try await lifecycleManager.transitionTo(.extracting)
            let extracted = try await downloadManager.extractArchive(model.localPath!)
            model.localPath = extracted
            try await lifecycleManager.transitionTo(.extracted(location: extracted))
        }
        
        // Validate model
        try await lifecycleManager.transitionTo(.validating)
        let validationResult = try await validator.validateModel(model, at: model.localPath!)
        
        if !validationResult.isValid {
            let context = RecoveryContext(
                model: model,
                stage: .validation,
                attemptCount: 1,
                previousErrors: validationResult.errors,
                availableResources: resources
            )
            try await errorRecovery.attemptRecovery(from: validationResult.errors.first!, in: context)
            // Retry after recovery
            return try await loadModelImpl(model, framework: framework)
        }
        
        try await lifecycleManager.transitionTo(.validated)
        
        // Extract metadata
        let metadata = await metadataExtractor.extractMetadata(
            from: model.localPath!,
            format: model.format
        )
        model.metadata = metadata
        
        // Find best adapter
        let adapter = framework.flatMap { adapterRegistry.getAdapter(for: $0) }
            ?? adapterRegistry.findBestAdapter(for: model)
        
        guard let adapter = adapter else {
            throw UnifiedModelError.noCompatibleFramework(model: model)
        }
        
        // Configure hardware
        let hardwareConfig = HardwareCapabilityManager.shared.optimalConfiguration(for: model)
        await adapter.configure(with: hardwareConfig)
        
        // Create service
        let service = adapter.createService()
        
        // Initialize with error recovery
        try await lifecycleManager.transitionTo(.initializing)
        
        do {
            try await service.initializeModel(model)
            try await lifecycleManager.transitionTo(.initialized)
        } catch {
            let context = RecoveryContext(
                model: model,
                stage: .initialization,
                attemptCount: 1,
                previousErrors: [error],
                availableResources: resources
            )
            try await errorRecovery.attemptRecovery(from: error, in: context)
            
            // Check if we should retry with different framework
            if case UnifiedModelError.retryWithFramework(let newFramework) = error {
                return try await loadModelImpl(model, framework: newFramework)
            }
        }
        
        // Load
        try await lifecycleManager.transitionTo(.loading)
        try await service.loadModel(model)
        try await lifecycleManager.transitionTo(.loaded)
        
        // Ready
        try await lifecycleManager.transitionTo(.ready)
        
        // Update state
        self.currentService = service
        self.currentFramework = adapter.framework
        self.currentModel = model
        
        // Register with memory manager
        let modelSize = try await service.getModelMemoryUsage()
        memoryManager.registerLoadedModel(
            LoadedModel(
                id: model.id,
                framework: adapter.framework,
                service: service,
                tokenizer: try await tokenizerManager.getTokenizer(for: model),
                metadata: metadata
            ),
            size: modelSize,
            service: service
        )
    }
}
```

### 6.2 Cutover Strategy

#### Step 1: Pre-cutover Preparation
```swift
// 1. Ensure all new components are tested
// 2. Run integration tests
// 3. Create backup branch: git checkout -b pre-unified-backup

// 2. Scan for existing models that need migration
let existingModels = ModelManager.shared.downloadedModels
print("Found \(existingModels.count) existing models to preserve")
```

#### Step 2: Cutover Execution
```bash
# 1. Stop the app
# 2. Apply all changes from unified architecture
# 3. Delete old files as listed in Phase 5.1
# 4. Update imports in all Swift files
```

#### Step 3: Model Migration
```swift
// Simple path update for existing models
func updateModelPaths() {
    let modelsDir = FileManager.default.urls(for: .documentDirectory, 
                                           in: .userDomainMask).first!
                                           .appendingPathComponent("Models")
    
    // Models stay in same location, just update registry
    let registry = DynamicModelRegistry()
    registry.scanAndRegisterLocalModels(in: modelsDir)
}
```

#### Step 4: Verify Cutover
```swift
// Test each framework
let frameworks: [LLMFramework] = [.coreML, .tensorFlowLite, .mlx, 
                                  .swiftTransformers, .onnxRuntime, .execuTorch,
                                  .llamaCpp, .foundationModels, .picoLLM, .mlc]

for framework in frameworks {
    let adapter = FrameworkAdapterRegistry.shared.getAdapter(for: framework)
    assert(adapter != nil, "\(framework) adapter missing!")
}
```

### 6.3 UI Updates

#### Tasks:
1. Update views to use enhanced features
2. No dual-mode UI - single implementation
3. Add new progress tracking UI
4. Enhanced error display

#### Update UnifiedModelsView:

```swift
// Views/UnifiedModelsView.swift (UPDATE EXISTING)
struct UnifiedModelsView: View {
    @StateObject private var modelManager = ModelManager.shared
    @StateObject private var unifiedService = UnifiedLLMService.shared // Same name!
    @StateObject private var progressTracker = UnifiedProgressTracker.shared
    
    var body: some View {
        List {
            // Models from dynamic registry
            Section("Available Models") {
                ForEach(unifiedService.discoveredModels) { model in
                    UnifiedModelRow(model: model)
                }
            }
            
            // Downloaded models with memory info
            Section("Downloaded Models") {
                ForEach(modelManager.downloadedModels) { model in
                    DownloadedModelRow(model: model)
                        .overlay(alignment: .topTrailing) {
                            if let memory = memoryManager.getModelMemoryUsage(model.id) {
                                Text(ByteCountFormatter.string(fromByteCount: memory, countStyle: .memory))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                }
            }
        }
    }
}

struct UnifiedModelRow: View {
    let model: ModelInfo
    @StateObject private var progressTracker = UnifiedProgressTracker.shared
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(model.name)
                Spacer()
                Text(model.format.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Show compatible frameworks
            HStack {
                ForEach(model.compatibleFrameworks, id: \.self) { framework in
                    FrameworkBadge(framework: framework)
                }
            }
            
            // Progress if loading
            if let progress = progressTracker.getProgress(for: model.id) {
                ProgressView(value: progress.percentage)
                Text(progress.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
```

## Migration Timeline

### Week 1-2: Foundation & Protocols
- [ ] Create unified protocol definitions
- [ ] Implement lifecycle state machine
- [ ] Build unified tokenizer system
- [ ] Centralize hardware detection

### Week 3-4: Core Services
- [ ] Implement enhanced download manager with archive support
- [ ] Build unified memory manager
- [ ] Create dynamic model registry
- [ ] Add stage-based progress tracking

### Week 5-6: Framework Adapters
- [ ] Create adapters preserving framework logic
- [ ] Extract common patterns
- [ ] Build adapter registry
- [ ] Preserve framework-specific features

### Week 7: Cleanup Phase
- [ ] Delete legacy files
- [ ] Remove duplicate code
- [ ] Consolidate tokenizers
- [ ] Update dependencies

### Week 8: Integration & Cutover
- [ ] Replace UnifiedLLMService
- [ ] Update UI components
- [ ] Migrate existing models
- [ ] Complete cutover

### Week 9: Validation & Stabilization
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

## Migration Validation

### Validation Checklist

```swift
struct MigrationValidation {
    static func validateMigration() async throws {
        // 1. Verify all models in old registry exist in new
        let oldModels = ModelURLRegistry.shared.getAllModels()
        let newModels = await DynamicModelRegistry().discoverModels()
        
        for oldModel in oldModels {
            assert(newModels.contains { $0.id == oldModel.id }, "Model \(oldModel.name) missing in new registry")
        }
        
        // 2. Test each framework adapter
        for framework in LLMFramework.allCases {
            let adapter = FrameworkAdapterRegistry.shared.getAdapter(for: framework)
            assert(adapter != nil, "\(framework) adapter missing")
        }
        
        // 3. Verify no old code references remain
        verifyNoLegacyReferences()
        
        // 4. Check memory usage is comparable or better
        let oldMemoryUsage = measureOldImplementationMemory()
        let newMemoryUsage = measureNewImplementationMemory()
        assert(newMemoryUsage <= oldMemoryUsage * 1.1, "Memory usage regression detected")
        
        // 5. Validate all tokenizers work
        try await validateAllTokenizers()
        
        // 6. Verify resource management
        verifyResourceManagement()
    }
}
```

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

## Success Criteria

1. **Functionality**
   - All existing features work
   - No increase in crash rate
   - Better error messages
   - All 10 frameworks functional

2. **Performance**
   - Model loading ≤ 5 seconds
   - Memory usage ≤ 110% of current
   - Inference speed maintained
   - Tokenization ≥ 10k tokens/sec

3. **Maintainability**
   - Reduced code duplication by 70%
   - Consistent error handling
   - Easy to add new frameworks
   - Single source of truth for each concern

4. **User Experience**
   - Stage-based progress tracking
   - Clearer error messages with recovery options
   - Smoother model switching
   - Resource availability warnings

## Detailed Cleanup Instructions

### Files to Delete (Complete List)

```bash
# Core files to remove
rm Services/UnifiedLLMService.swift.backup  # After creating backup
rm Services/BundledModelsService.swift
rm Services/ModelURLRegistry.swift
rm Services/ModelCompatibilityChecker.swift

# Tokenizer files to remove
rm Services/Tokenization/BaseTokenizer.swift
rm Services/Tokenization/TokenizerFactory.swift
rm Services/Tokenization/TokenizerAdapterFactory.swift

# Duplicate functionality
rm Utils/DeviceCapabilities.swift  # Merged into HardwareCapabilityManager
```

### Code Sections to Remove

#### From Each Framework Service:
```swift
// REMOVE from CoreMLService.swift:
// Lines 54-62: supportedModels getter/setter
// Lines 319-341: isNeuralEngineAvailable()
// Lines 166-174: Manual tokenizer adapter creation

// REMOVE from TFLiteService.swift:
// Lines 43-52: supportedModels getter/setter
// Duplicate hardware detection code

// REMOVE from MLXService.swift:
// Lines 159-168: supportedModels getter/setter
// Manual model search logic (replaced by registry)

// REMOVE from SwiftTransformersService.swift:
// Lines 57-72: supportedModels getter/setter
// Lines 122-131: Bundled model support

// REMOVE from ONNXService.swift:
// Lines 120-129: supportedModels getter/setter

// REMOVE from ExecuTorchService.swift:
// Lines 79-88: supportedModels getter/setter
```

### Import Updates

```swift
// Replace in all files:
// OLD: import ModelURLRegistry
// NEW: import DynamicModelRegistry

// OLD: import TokenizerFactory
// NEW: import UnifiedTokenizerManager

// OLD: import DeviceCapabilities
// NEW: import HardwareCapabilityManager
```

## Framework Preservation Guidelines

### What to Keep Intact:
1. **Core ML**: Compilation logic, model adapters, sliding window
2. **TFLite**: Delegate configuration, tensor management
3. **MLX**: Directory structure handling, device checks
4. **Swift Transformers**: Model validation, input requirements
5. **ONNX**: Session management, execution providers
6. **ExecuTorch**: Module loading pattern
7. **LlamaCpp**: Quantization formats, memory mapping, streaming
8. **Foundation Models**: System integration, privacy features
9. **PicoLLM**: Edge optimization, ultra-compression
10. **MLC**: JIT compilation, multi-backend support

### What to Abstract:
1. Hardware detection → HardwareCapabilityManager
2. Tokenizer creation → UnifiedTokenizerManager
3. Model discovery → DynamicModelRegistry
4. Progress tracking → UnifiedProgressTracker
5. Memory management → UnifiedMemoryManager
6. API key management → KeychainService integration
7. Compilation caching → CompilationCache

## Conclusion

This migration plan provides a complete replacement strategy for the current LLM framework implementation. By removing all legacy code and technical debt while preserving framework-specific logic, we achieve:

1. **Clean Architecture** - No v1/v2 confusion, single implementation
2. **Preserved Functionality** - All framework features maintained
3. **Unified Interface** - Consistent API across frameworks
4. **Better Maintainability** - 70% less code duplication
5. **Enhanced Features** - Progress tracking, memory management, dynamic discovery

The phased approach allows for systematic implementation with clear milestones and a definitive cutover point.