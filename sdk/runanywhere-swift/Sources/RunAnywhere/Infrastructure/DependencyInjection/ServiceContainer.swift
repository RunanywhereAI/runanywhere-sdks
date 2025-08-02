import Foundation

/// Service container for dependency injection
public class ServiceContainer {
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
    private(set) lazy var adapterRegistry: FrameworkAdapterRegistry = {
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
    private(set) lazy var downloadService: DownloadService = {
        DownloadService(
            downloadQueue: downloadQueue,
            progressTracker: progressTracker,
            storageService: storageService
        )
    }()

    /// Download queue
    private(set) lazy var downloadQueue: DownloadQueue = {
        DownloadQueue()
    }()

    /// Progress tracker
    private(set) lazy var progressTracker: ProgressTracker = {
        ProgressTracker()
    }()

    /// Storage service
    private(set) lazy var storageService: StorageService = {
        StorageService(storageMonitor: storageMonitor)
    }()

    /// Routing service
    private(set) lazy var routingService: RoutingService = {
        RoutingService(
            costCalculator: CostCalculator(),
            resourceChecker: ResourceChecker(hardwareManager: hardwareManager)
        )
    }()

    /// Memory service
    private(set) lazy var memoryService: MemoryService = {
        MemoryService(memoryMonitor: memoryMonitor)
    }()

    /// Memory monitor
    private(set) lazy var memoryMonitor: MemoryMonitor = {
        MemoryMonitor()
    }()

    // MARK: - Monitoring Services

    /// Performance monitor
    private(set) lazy var performanceMonitor: PerformanceMonitor = {
        MonitoringService()
    }()

    /// Storage monitor
    private(set) lazy var storageMonitor: StorageMonitor = {
        StorageMonitorImpl()
    }()

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
        HardwareCapabilityManager()
    }()

    /// Logger
    private(set) lazy var logger: SDKLogger = {
        SDKLogger()
    }()

    // MARK: - Initialization

    public init() {
        // Container is ready for lazy initialization
    }

    /// Bootstrap all services with configuration
    public func bootstrap(with configuration: Configuration) async throws {
        // Configure logger
        logger.configure(with: configuration)

        // Initialize core services
        await modelRegistry.initialize(with: configuration)

        // Configure hardware preferences
        if let hwConfig = configuration.hardwarePreferences {
            hardwareManager.configure(with: hwConfig)
        }

        // Set memory threshold
        memoryService.setMemoryThreshold(configuration.memoryThreshold)

        // Configure download settings
        downloadService.configure(with: configuration.downloadConfiguration)

        // Initialize monitoring if enabled
        if configuration.enableRealTimeDashboard {
            await performanceMonitor.initialize()
            await storageMonitor.startMonitoring()
        }
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
