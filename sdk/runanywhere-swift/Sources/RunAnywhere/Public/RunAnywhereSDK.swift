import Foundation

/// The main entry point for the RunAnywhere SDK
public class RunAnywhereSDK {
    /// Shared instance of the SDK
    public static let shared: RunAnywhereSDK = RunAnywhereSDK()

    /// Current configuration
    private var configuration: Configuration?

    // MARK: - Unified Architecture Components

    /// Model lifecycle state machine
    private let lifecycleManager: ModelLifecycleStateMachine = ModelLifecycleStateMachine()

    /// Tokenizer manager
    private let tokenizerManager: UnifiedTokenizerManager = UnifiedTokenizerManager.shared

    /// Hardware capability manager
    private let hardwareManager: HardwareCapabilityManager = HardwareCapabilityManager.shared

    /// Model registry (to be provided by implementation)
    private var modelRegistry: ModelRegistry?

    /// Framework adapter registry (to be provided by implementation)
    private var adapterRegistry: FrameworkAdapterRegistry?

    /// Download manager (to be provided by implementation)
    private var downloadManager: EnhancedDownloadManager?

    /// Memory manager (to be provided by implementation)
    private var memoryManager: MemoryManager?

    /// Progress tracker
    private let progressTracker: UnifiedProgressTracker = UnifiedProgressTracker()

    /// Error recovery system
    private lazy var errorRecovery: UnifiedErrorRecovery = {
        UnifiedErrorRecovery()
    }()

    // MARK: - New Performance Components

    /// Performance monitoring system
    public let performanceMonitor: RealtimePerformanceMonitor = RealtimePerformanceMonitor.shared

    /// Benchmarking suite
    public let benchmarkSuite: BenchmarkSuite = BenchmarkSuite.shared

    /// Memory profiler
    public let memoryProfiler: MemoryProfiler = MemoryProfiler.shared

    /// Model compatibility checker
    public let compatibilityMatrix: ModelCompatibilityMatrix = ModelCompatibilityMatrix.shared

    /// Storage monitor
    public let storageMonitor: StorageMonitor = StorageMonitor.shared

    /// A/B testing framework
    public let abTesting: ABTestingFramework = ABTestingFramework.shared

    /// Currently loaded model
    private var currentModel: ModelInfo?
    private var currentService: LLMService?

    /// Private initializer to enforce singleton pattern
    private init() {
        setupLifecycleObserver()
    }

    // MARK: - Public API

    /// Initialize the SDK with the provided configuration
    /// - Parameter config: The configuration to use
    public func initialize(with config: Configuration) async throws {
        self.configuration = config

        // Configure hardware preferences if provided
        if let hwConfig = config.hardwarePreferences {
            // Hardware manager will use these preferences for optimization
        }

        // Set memory threshold
        memoryManager?.setMemoryThreshold(config.memoryThreshold)

        // Configure model providers
        for providerConfig in config.modelProviders {
            if providerConfig.enabled {
                // Provider registration will be handled by the implementation
            }
        }

        // Verify we have required components
        guard adapterRegistry != nil else {
            throw SDKError.notInitialized
        }
    }

    /// Load a model by identifier
    /// - Parameter identifier: The model identifier (e.g., "llama-3.2-1b")
    public func loadModel(_ identifier: String) async throws {
        guard configuration != nil else {
            throw SDKError.notInitialized
        }

        // Start discovery phase
        try await lifecycleManager.transitionTo(.discovered)
        progressTracker.startStage(.discovery)

        // Find model in registry
        guard let model = await findModel(identifier: identifier) else {
            throw SDKError.modelNotFound(identifier)
        }

        progressTracker.completeStage(.discovery)

        // Check if model needs download
        if model.localPath == nil {
            try await downloadModel(model)
        }

        // Validate model
        try await validateModel(model)

        // Select framework and create service
        let (framework, service) = try await selectFrameworkAndCreateService(for: model)

        // Initialize the service
        try await lifecycleManager.transitionTo(.initializing)
        progressTracker.startStage(.initialization)

        try await service.initialize(modelPath: model.localPath?.path ?? "")

        progressTracker.completeStage(.initialization)
        try await lifecycleManager.transitionTo(.initialized)

        // Load model
        try await lifecycleManager.transitionTo(.loading)
        progressTracker.startStage(.loading)

        // Service is already initialized, mark as loaded
        progressTracker.completeStage(.loading)
        try await lifecycleManager.transitionTo(.loaded)
        try await lifecycleManager.transitionTo(.ready)

        // Store references
        self.currentModel = model
        self.currentService = service
    }

    /// Generate text based on the provided prompt
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options (optional)
    /// - Returns: The generation result
    public func generate(_ prompt: String, options: GenerationOptions? = nil) async throws -> GenerationResult {
        guard let config = configuration else {
            throw SDKError.notInitialized
        }

        guard let service = currentService, service.isReady else {
            throw SDKError.modelNotFound("No model loaded")
        }

        guard let model = currentModel else {
            throw SDKError.modelNotFound("No model information")
        }

        // Create inference request
        let request = InferenceRequest(prompt: prompt, options: options)

        // Make routing decision
        let routingDecision = await makeRoutingDecision(for: request, model: model, config: config)

        // Track execution state
        try await lifecycleManager.transitionTo(.executing)
        let startTime = Date()

        do {
            // Execute based on routing decision
            let result: GenerationResult

            switch routingDecision {
            case .onDevice(let framework, let reason):
                result = try await executeOnDevice(
                    request: request,
                    service: service,
                    model: model,
                    framework: framework,
                    reason: reason
                )

            case .cloud(let provider, let reason):
                // Cloud execution would be implemented here
                throw SDKError.notImplemented

            case .hybrid(let devicePortion, let framework, let reason):
                // Hybrid execution would be implemented here
                throw SDKError.notImplemented
            }

            try await lifecycleManager.transitionTo(.ready)
            return result
        } catch {
            // Handle error with recovery
            try await handleGenerationError(error, request: request, model: model)
            throw error
        }
    }

    /// Stream generate text based on the provided prompt
    /// - Parameters:
    ///   - prompt: The input prompt
    ///   - options: Generation options (optional)
    /// - Returns: An async stream of generated text
    public func streamGenerate(_ prompt: String, options: GenerationOptions? = nil) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard configuration != nil else {
                        continuation.finish(throwing: SDKError.notInitialized)
                        return
                    }

                    // TODO: Implement streaming generation
                    continuation.finish(throwing: SDKError.notImplemented)
                }
            }
        }
    }

    /// Set the context for generation
    /// - Parameter context: The context to use
    public func setContext(_ context: Context) {
        // TODO: Implement context management
    }

    /// Update the SDK configuration
    /// - Parameter config: The new configuration
    public func updateConfiguration(_ config: Configuration) async throws {
        self.configuration = config
        // TODO: Update all components with new configuration
    }
}

// MARK: - Supporting Types

/// SDK-specific errors
public enum SDKError: LocalizedError {
    case notInitialized
    case notImplemented
    case modelNotFound(String)
    case loadingFailed(String)
    case generationFailed(String)
    case frameworkNotAvailable(LLMFramework)
    case downloadFailed(Error)
    case validationFailed(ValidationError)
    case routingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "SDK not initialized. Call initialize(with:) first."
        case .notImplemented:
            return "This feature is not yet implemented."
        case .modelNotFound(let model):
            return "Model '\(model)' not found."
        case .loadingFailed(let reason):
            return "Failed to load model: \(reason)"
        case .generationFailed(let reason):
            return "Generation failed: \(reason)"
        case .frameworkNotAvailable(let framework):
            return "Framework \(framework.rawValue) not available"
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        case .validationFailed(let error):
            return "Validation failed: \(error.localizedDescription)"
        case .routingFailed(let reason):
            return "Routing failed: \(reason)"
        }
    }
}

// MARK: - Framework Registry Protocol

/// Protocol for framework adapter registry (to be implemented by app)
public protocol FrameworkAdapterRegistry {
    /// Get adapter for a specific framework
    func getAdapter(for framework: LLMFramework) -> FrameworkAdapter?

    /// Find best adapter for a model
    func findBestAdapter(for model: ModelInfo) -> FrameworkAdapter?

    /// Register an adapter
    func register(_ adapter: FrameworkAdapter)
}

// MARK: - Component Registration

public extension RunAnywhereSDK {
    /// Register framework adapter registry
    func registerAdapterRegistry(_ registry: FrameworkAdapterRegistry) {
        self.adapterRegistry = registry
    }

    /// Register model registry
    func registerModelRegistry(_ registry: ModelRegistry) {
        self.modelRegistry = registry
    }

    /// Register download manager
    func registerDownloadManager(_ manager: EnhancedDownloadManager) {
        self.downloadManager = manager
    }

    /// Register memory manager
    func registerMemoryManager(_ manager: MemoryManager) {
        self.memoryManager = manager
    }

    /// Register hardware detector
    func registerHardwareDetector(_ detector: HardwareDetector) {
        hardwareManager.registerHardwareDetector(detector)
    }
}

// MARK: - Default Initialization

public extension RunAnywhereSDK {

    /// Initialize SDK with optimal defaults for immediate usability
    /// This method sets up the SDK with platform-specific optimizations
    /// and sensible defaults that work out-of-the-box for local-only usage
    func initializeWithDefaults() async throws {
        // Register platform-specific hardware detector
        #if os(iOS) || os(tvOS)
        let hardwareManager = HardwareCapabilityManager.shared
        if hardwareManager.capabilities.processorType == .unknown {
            hardwareManager.registerHardwareDetector(iOSHardwareDetector())
        }
        #endif

        // Configure model discovery with standard directories
        let registry = DynamicModelRegistry.shared
        var discoveryConfig = DynamicModelRegistry.DiscoveryConfig()
        discoveryConfig.includeLocalModels = true
        discoveryConfig.includeOnlineModels = false // Apps can enable this explicitly
        registry.configure(discoveryConfig)

        // Register the registry
        registerModelRegistry(registry)

        // Initialize SDK with default configuration (local-only)
        let config = Configuration(apiKey: "local-only")
        try await initialize(with: config)

        // Trigger initial model discovery
        _ = await registry.discoverModels()
    }

    /// Quick setup for development and testing
    /// Includes more permissive settings suitable for development
    func initializeForDevelopment() async throws {
        try await initializeWithDefaults()

        // Enable online model discovery for development
        let registry = DynamicModelRegistry.shared
        var discoveryConfig = DynamicModelRegistry.DiscoveryConfig()
        discoveryConfig.includeLocalModels = true
        discoveryConfig.includeOnlineModels = true
        discoveryConfig.cacheTimeout = 300 // 5 minutes for development
        registry.configure(discoveryConfig)
    }

    /// Production-ready initialization with conservative settings
    func initializeForProduction(apiKey: String) async throws {
        // Register platform-specific hardware detector
        #if os(iOS) || os(tvOS)
        let hardwareManager = HardwareCapabilityManager.shared
        if hardwareManager.capabilities.processorType == .unknown {
            hardwareManager.registerHardwareDetector(iOSHardwareDetector())
        }
        #endif

        // Configure model discovery with conservative settings
        let registry = DynamicModelRegistry.shared
        var discoveryConfig = DynamicModelRegistry.DiscoveryConfig()
        discoveryConfig.includeLocalModels = true
        discoveryConfig.includeOnlineModels = false
        discoveryConfig.cacheTimeout = 3600 // 1 hour
        registry.configure(discoveryConfig)

        // Register the registry
        registerModelRegistry(registry)

        // Initialize SDK with production configuration
        let config = Configuration(apiKey: apiKey)
        try await initialize(with: config)

        // Trigger initial model discovery
        _ = await registry.discoverModels()
    }

    /// Initialize with a custom API key for cloud features
    /// - Parameter apiKey: Your RunAnywhere API key
    func initializeWithAPIKey(_ apiKey: String) async throws {
        // Register platform-specific hardware detector
        #if os(iOS) || os(tvOS)
        let hardwareManager = HardwareCapabilityManager.shared
        if hardwareManager.capabilities.processorType == .unknown {
            hardwareManager.registerHardwareDetector(iOSHardwareDetector())
        }
        #endif

        // Configure model discovery
        let registry = DynamicModelRegistry.shared
        var discoveryConfig = DynamicModelRegistry.DiscoveryConfig()
        discoveryConfig.includeLocalModels = true
        discoveryConfig.includeOnlineModels = true
        registry.configure(discoveryConfig)

        // Register the registry
        registerModelRegistry(registry)

        // Initialize SDK with provided API key
        let config = Configuration(apiKey: apiKey)
        try await initialize(with: config)

        // Trigger initial model discovery
        _ = await registry.discoverModels()
    }
}

// MARK: - Private Implementation

private extension RunAnywhereSDK {
    /// Setup lifecycle observer
    func setupLifecycleObserver() {
        lifecycleManager.addObserver(self)
    }

    /// Find model by identifier
    func findModel(identifier: String) async -> ModelInfo? {
        // Try to find in registry first
        if let model = modelRegistry?.getModel(by: identifier) {
            return model
        }

        // Discover models and search
        let models = await modelRegistry?.discoverModels() ?? []
        return models.first { $0.id == identifier || $0.name == identifier }
    }

    /// Download model if needed
    func downloadModel(_ model: ModelInfo) async throws {
        guard let downloadManager = downloadManager else {
            throw SDKError.notInitialized
        }

        try await lifecycleManager.transitionTo(.downloading)
        progressTracker.startStage(.download)

        do {
            let downloadTask = try await downloadManager.downloadModel(model)
            let localPath = try await downloadTask.result.value

            // Update model with local path
            var updatedModel = model
            updatedModel.localPath = localPath
            modelRegistry?.updateModel(updatedModel)
            self.currentModel = updatedModel

            progressTracker.completeStage(.download)
            try await lifecycleManager.transitionTo(.downloaded)
        } catch {
            progressTracker.failStage(.download, error: error)
            throw SDKError.downloadFailed(error)
        }
    }

    /// Validate model
    func validateModel(_ model: ModelInfo) async throws {
        guard let localPath = model.localPath else {
            throw SDKError.modelNotFound("Model not downloaded")
        }

        try await lifecycleManager.transitionTo(.validating)
        progressTracker.startStage(.validation)

        // Basic validation - could be extended with format-specific validators
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: localPath.path) else {
            throw SDKError.validationFailed(ValidationError.corruptedFile(reason: "Model file does not exist at path"))
        }

        progressTracker.completeStage(.validation)
        try await lifecycleManager.transitionTo(.validated)
    }

    /// Select framework and create service
    func selectFrameworkAndCreateService(for model: ModelInfo) async throws -> (LLMFramework, LLMService) {
        guard let adapterRegistry = adapterRegistry else {
            throw SDKError.notInitialized
        }

        // Find best adapter
        guard let adapter = adapterRegistry.findBestAdapter(for: model) else {
            throw SDKError.frameworkNotAvailable(.coreML)
        }

        // Configure adapter with hardware settings
        let hwConfig = hardwareManager.optimalConfiguration(for: model)
        await adapter.configure(with: hwConfig)

        // Create service
        let service = adapter.createService()

        return (adapter.framework, service)
    }

    /// Make routing decision
    func makeRoutingDecision(for request: InferenceRequest, model: ModelInfo, config: Configuration) async -> RoutingDecision {
        // Check user preference first
        if let preferredTarget = request.options?.preferredExecutionTarget {
            switch preferredTarget {
            case .onDevice:
                return .onDevice(framework: currentModel?.preferredFramework, reason: .userPreference(.onDevice))
            case .cloud:
                return .cloud(provider: nil, reason: .userPreference(.cloud))
            case .hybrid:
                return .hybrid(devicePortion: 0.5, framework: currentModel?.preferredFramework, reason: .userPreference(.hybrid))
            }
        }

        // Apply routing policy
        switch config.routingPolicy {
        case .preferDevice:
            return .onDevice(framework: currentModel?.preferredFramework, reason: .policyDriven(.preferDevice))
        case .preferCloud:
            return .cloud(provider: nil, reason: .policyDriven(.preferCloud))
        case .automatic:
            // Automatic routing based on various factors
            let resourceAvailability = hardwareManager.checkResourceAvailability()

            // Check if model can run on device
            let canRunOnDevice = resourceAvailability.canLoad(model: model)
            if !canRunOnDevice.canLoad {
                return .cloud(provider: nil, reason: .insufficientResources(canRunOnDevice.reason ?? "memory"))
            }

            // Default to on-device for privacy and cost savings
            return .onDevice(framework: currentModel?.preferredFramework, reason: .costOptimization(savedAmount: 0.05))

        case .custom:
            // Custom routing would be implemented based on specific rules
            return .onDevice(framework: currentModel?.preferredFramework, reason: .policyDriven(.custom))
        }
    }

    /// Execute on device
    func executeOnDevice(request: InferenceRequest, service: LLMService, model: ModelInfo, framework: LLMFramework?, reason: RoutingReason) async throws -> GenerationResult {
        let startTime = Date()
        var tokenizationTime: TimeInterval = 0
        var inferenceTime: TimeInterval = 0

        // Tokenize if needed
        let tokenizationStart = Date()
        if let tokenizer = try? await tokenizerManager.getTokenizer(for: model) {
            // Tokenization metrics would be tracked here
            tokenizationTime = Date().timeIntervalSince(tokenizationStart)
        }

        // Set context if provided
        if let context = request.options?.context {
            await service.setContext(context)
        }

        // Perform generation
        let inferenceStart = Date()
        let generatedText = try await service.generate(
            prompt: request.prompt,
            options: request.options ?? GenerationOptions()
        )
        inferenceTime = Date().timeIntervalSince(inferenceStart)

        // Get memory usage
        let memoryUsed = try await service.getModelMemoryUsage()

        // Calculate total latency
        let totalLatency = Date().timeIntervalSince(startTime) * 1000 // Convert to ms

        // Create performance metrics
        let performanceMetrics = PerformanceMetrics(
            tokenizationTimeMs: tokenizationTime * 1000,
            inferenceTimeMs: inferenceTime * 1000,
            postProcessingTimeMs: 0,
            tokensPerSecond: Double(request.options?.maxTokens ?? 100) / inferenceTime,
            peakMemoryUsage: memoryUsed,
            queueWaitTimeMs: 0
        )

        // Create result
        return GenerationResult(
            text: generatedText,
            tokensUsed: request.options?.maxTokens ?? 100,
            modelUsed: model.name,
            latencyMs: totalLatency,
            executionTarget: .onDevice,
            savedAmount: 0.05, // Example: 5 cents saved
            framework: framework,
            hardwareUsed: hardwareManager.capabilities.hasNeuralEngine ? .neuralEngine : .cpu,
            memoryUsed: memoryUsed,
            tokenizerFormat: model.tokenizerFormat,
            performanceMetrics: performanceMetrics,
            metadata: ResultMetadata(
                routingReason: convertRoutingReason(reason),
                fallbackUsed: false,
                cacheHit: false,
                modelVersion: model.metadata?.author,
                experimentId: nil,
                debugInfo: nil
            )
        )
    }

    /// Convert internal RoutingReason to public RoutingReasonType
    private func convertRoutingReason(_ reason: RoutingReason) -> RoutingReasonType {
        switch reason {
        case .privacySensitive, .insufficientResources:
            return .resourceConstraint
        case .lowComplexity, .highComplexity:
            return .performanceOptimization
        case .policyDriven:
            return .policyDriven
        case .userPreference:
            return .userPreference
        case .frameworkUnavailable, .modelNotAvailable:
            return .fallback
        case .costOptimization:
            return .costOptimization
        case .latencyOptimization:
            return .performanceOptimization
        }
    }

    /// Handle generation error
    func handleGenerationError(_ error: Error, request: InferenceRequest, model: ModelInfo) async throws {
        try await lifecycleManager.handleError(error)

        // Attempt recovery
        let context = RecoveryContext(
            model: model,
            stage: .ready,
            attemptCount: 1,
            previousErrors: [error],
            availableResources: hardwareManager.checkResourceAvailability(),
            options: RecoveryOptions()
        )

        do {
            try await errorRecovery.attemptRecovery(from: error, in: context)
        } catch {
            // Recovery failed, transition to ready state
            try? await lifecycleManager.transitionTo(.ready)
        }
    }
}

// MARK: - ModelLifecycleObserver

extension RunAnywhereSDK: ModelLifecycleObserver {
    public func modelDidTransition(from oldState: ModelLifecycleState, to newState: ModelLifecycleState) {
        // Log state transitions if debug mode is enabled
        if configuration?.debugMode == true {
            print("[RunAnywhereSDK] Model state: \(oldState.rawValue) → \(newState.rawValue)")
        }
    }

    public func modelDidEncounterError(_ error: Error, in state: ModelLifecycleState) {
        // Log errors if debug mode is enabled
        if configuration?.debugMode == true {
            print("[RunAnywhereSDK] Error in state \(state.rawValue): \(error.localizedDescription)")
        }
    }
}
