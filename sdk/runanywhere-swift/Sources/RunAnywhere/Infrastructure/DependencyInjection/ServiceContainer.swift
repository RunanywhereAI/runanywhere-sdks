import Foundation

/// Service container for dependency injection
public class ServiceContainer {
    /// Shared instance
    public static let shared: ServiceContainer = ServiceContainer()
    // MARK: - Core Services

    /// Configuration validator
    private(set) lazy var configurationValidator: ConfigurationValidator = {
        ConfigurationValidator()
    }()

    /// Model registry
    private(set) lazy var modelRegistry: ModelRegistry = {
        RegistryService()
    }()

    /// Framework adapter registry
    internal lazy var adapterRegistry: FrameworkAdapterRegistry = {
        FrameworkAdapterRegistryImpl()
    }()

    // MARK: - Capability Services

    /// Model loading service
    private(set) lazy var modelLoadingService: ModelLoadingService = {
        ModelLoadingService(
            registry: modelRegistry,
            adapterRegistry: adapterRegistry,
            validationService: validationService,
            memoryService: memoryService
        )
    }()

    /// Generation service
    private(set) lazy var generationService: GenerationService = {
        GenerationService(
            routingService: routingService,
            contextManager: contextManager,
            performanceMonitor: performanceMonitor
        )
    }()

    /// Streaming service
    private(set) lazy var streamingService: StreamingService = {
        StreamingService(generationService: generationService)
    }()

    /// Context manager
    private(set) lazy var contextManager: ContextManager = {
        ContextManager()
    }()

    /// Validation service
    private(set) lazy var validationService: ValidationService = {
        ValidationService()
    }()

    /// Download service
    private(set) lazy var downloadService: AlamofireDownloadService = {
        AlamofireDownloadService()
    }()

    // Download queue removed - handled by AlamofireDownloadService

    /// Progress service (implements ProgressTracker protocol)
    private(set) lazy var progressService: ProgressTracker = {
        ProgressService(
            stageManager: StageManager(),
            progressAggregator: ProgressAggregator()
        )
    }()

    // Storage service removed - replaced by SimplifiedFileManager
    // Model storage manager removed - replaced by SimplifiedFileManager

    /// Simplified file manager
    private(set) lazy var fileManager: SimplifiedFileManager = {
        do {
            return try SimplifiedFileManager()
        } catch {
            fatalError("Failed to initialize file manager: \(error)")
        }
    }()

    /// Routing service
    private(set) lazy var routingService: RoutingService = {
        RoutingService(
            costCalculator: CostCalculator(),
            resourceChecker: ResourceChecker(hardwareManager: hardwareManager)
        )
    }()

    // Memory service and monitor placeholders removed - using unifiedMemoryManager instead

    // MARK: - Monitoring Services

    /// Performance monitor
    private(set) lazy var performanceMonitor: PerformanceMonitor = {
        MonitoringService()
    }()

    // Storage monitor removed - storage monitoring handled by SimplifiedFileManager

    /// Benchmark runner
    private(set) lazy var benchmarkRunner: BenchmarkRunner = {
        BenchmarkService()
    }()

    /// A/B test runner
    private(set) lazy var abTestRunner: ABTestRunner = {
        ABTestService()
    }()

    // MARK: - Infrastructure

    /// Hardware manager
    private(set) lazy var hardwareManager: HardwareCapabilityManager = {
        HardwareCapabilityManager.shared
    }()

    /// Memory service (implements MemoryManager protocol)
    private(set) lazy var memoryService: MemoryManager = {
        MemoryService(
            allocationManager: AllocationManager(),
            pressureHandler: PressureHandler(),
            cacheEviction: CacheEviction()
        )
    }()

    /// Error recovery service
    private(set) lazy var errorRecoveryService: ErrorRecoveryService = {
        ErrorRecoveryService()
    }()

    /// Compatibility service
    private(set) lazy var compatibilityService: CompatibilityService = {
        CompatibilityService()
    }()

    /// Tokenization service
    private(set) lazy var tokenizerService: TokenizerService = {
        TokenizerService()
    }()

    /// Format detector for model validation
    private(set) lazy var formatDetector: FormatDetector = {
        FormatDetectorImpl()
    }()

    /// Metadata extractor for model validation
    private(set) lazy var metadataExtractor: MetadataExtractor = {
        MetadataExtractorImpl()
    }()

    /// Logger
    private(set) lazy var logger: SDKLogger = {
        SDKLogger()
    }()

    // MARK: - Public Service Access

    /// Get error recovery service
    public var errorRecovery: ErrorRecoveryService {
        return errorRecoveryService
    }

    /// Get compatibility service
    public var compatibility: CompatibilityService {
        return compatibilityService
    }

    /// Get tokenizer service
    public var tokenizer: TokenizerService {
        return tokenizerService
    }

    /// Get memory service
    public var memory: MemoryManager {
        return memoryService
    }

    /// Get progress service
    public var progress: ProgressTracker {
        return progressService
    }

    // MARK: - Initialization

    public init() {
        // Container is ready for lazy initialization
    }

    /// Bootstrap all services with configuration
    public func bootstrap(with configuration: Configuration) async throws {
        // Logger is pre-configured through LoggingManager

        // Initialize core services
        // Model registry is initialized on first use

        // Configure hardware preferences
        // Hardware manager is self-configuring

        // Set memory threshold
        memoryService.setMemoryThreshold(configuration.memoryThreshold)

        // Configure download settings
        // Download service is configured via its initializer

        // Initialize monitoring if enabled
        if configuration.enableRealTimeDashboard {
            performanceMonitor.startMonitoring()
            // Storage monitoring is now handled by SimplifiedFileManager
        }

        // Start service health monitoring
        await startHealthMonitoring()
    }

    /// Check health of all services
    public func checkServiceHealth() async -> [String: Bool] {
        var health: [String: Bool] = [:]

        health["memory"] = await checkMemoryServiceHealth()
        health["download"] = await checkDownloadServiceHealth()
        health["storage"] = await checkStorageServiceHealth()
        health["validation"] = await checkValidationServiceHealth()
        health["compatibility"] = await checkCompatibilityServiceHealth()
        health["tokenizer"] = await checkTokenizerServiceHealth()

        return health
    }

    private func startHealthMonitoring() async {
        // Start periodic health checks every 30 seconds
        Task {
            while !Task.isCancelled {
                let health = await checkServiceHealth()
                let unhealthyServices = health.filter { !$0.value }.map { $0.key }

                if !unhealthyServices.isEmpty {
                    logger.warning("Unhealthy services detected: \(unhealthyServices.joined(separator: ", "))")
                }

                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            }
        }
    }

    private func checkMemoryServiceHealth() async -> Bool {
        // Basic health check - ensure memory service is responsive
        return memoryService.isHealthy()
    }

    private func checkDownloadServiceHealth() async -> Bool {
        // Check if download service can handle requests
        return await downloadService.isHealthy()
    }

    private func checkStorageServiceHealth() async -> Bool {
        // Check storage service health
        return true // SimplifiedFileManager doesn't need health checks
    }

    private func checkValidationServiceHealth() async -> Bool {
        // Check validation service
        return validationService.isHealthy()
    }

    private func checkCompatibilityServiceHealth() async -> Bool {
        // Check compatibility service
        return compatibilityService.isHealthy()
    }

    private func checkTokenizerServiceHealth() async -> Bool {
        // Check tokenizer service
        return tokenizerService.isHealthy()
    }
}

// MARK: - Private Implementation Classes

private class FrameworkAdapterRegistryImpl: FrameworkAdapterRegistry {
    private var adapters: [LLMFramework: FrameworkAdapter] = [:]

    func getAdapter(for framework: LLMFramework) -> FrameworkAdapter? {
        return adapters[framework]
    }

    func findBestAdapter(for model: ModelInfo) -> FrameworkAdapter? {
        // First try preferred framework
        if let preferred = model.preferredFramework,
           let adapter = adapters[preferred] {
            return adapter
        }

        // Then try compatible frameworks
        for framework in model.compatibleFrameworks {
            if let adapter = adapters[framework] {
                return adapter
            }
        }

        return nil
    }

    func register(_ adapter: FrameworkAdapter) {
        adapters[adapter.framework] = adapter
    }
}
