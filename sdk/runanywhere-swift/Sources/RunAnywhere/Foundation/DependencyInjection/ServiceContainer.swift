import Foundation
import Pulse

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

    /// Single adapter registry for all frameworks (text and voice)
    internal let adapterRegistry = AdapterRegistry()


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
            performanceMonitor: performanceMonitor,
            modelLoadingService: modelLoadingService
        )
    }()

    /// Streaming service
    private(set) lazy var streamingService: StreamingService = {
        StreamingService(generationService: generationService, modelLoadingService: modelLoadingService)
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

    /// Configuration service
    private var _configurationService: ConfigurationServiceProtocol?
    public var configurationService: ConfigurationServiceProtocol {
        guard let service = _configurationService else {
            fatalError("ConfigurationService must be initialized via bootstrap")
        }
        return service
    }

    /// Database manager
    private lazy var databaseManager: DatabaseManager = {
        DatabaseManager.shared
    }()

    /// API client for sync operations
    private var apiClient: APIClient?

    /// Data sync service
    private var _dataSyncService: DataSyncService?

    public var dataSyncService: DataSyncService? {
        get async {
            if _dataSyncService == nil {
                // Create repositories for data sync
                let configRepo = ConfigurationRepositoryImpl(
                    databaseManager: databaseManager,
                    apiClient: apiClient
                )
                let modelRepo = ModelMetadataRepositoryImpl(
                    databaseManager: databaseManager,
                    apiClient: apiClient
                )
                let telemetryRepo = TelemetryRepositoryImpl(
                    databaseManager: databaseManager,
                    apiClient: apiClient
                )

                _dataSyncService = DataSyncService(
                    configurationRepository: configRepo,
                    modelMetadataRepository: modelRepo,
                    telemetryRepository: telemetryRepo,
                    enableAutoSync: false // Disabled: No backend currently available
                )
            }
            return _dataSyncService
        }
    }

    /// Generation analytics service
    private var _generationAnalytics: GenerationAnalyticsService?

    public var generationAnalytics: GenerationAnalyticsService {
        get async {
            if _generationAnalytics == nil {
                if let syncService = await dataSyncService {
                    let repository = GenerationAnalyticsRepositoryImpl(
                        databaseManager: databaseManager,
                        syncService: syncService
                    )

                    // Get telemetry repository - create a new instance
                    let telemetryRepo = TelemetryRepositoryImpl(
                        databaseManager: databaseManager,
                        apiClient: apiClient
                    )

                    _generationAnalytics = GenerationAnalyticsServiceImpl(
                        repository: repository,
                        telemetryService: telemetryRepo,
                        performanceMonitor: performanceMonitor
                    )
                } else {
                    // Database is required for analytics
                    logger.error("Database not available for GenerationAnalytics service")
                    fatalError("Database is required for GenerationAnalytics service")
                }
            }

            guard let analytics = _generationAnalytics else {
                logger.error("GenerationAnalytics service not available")
                fatalError("Failed to initialize GenerationAnalytics service")
            }

            return analytics
        }
    }


    // MARK: - Public Service Access

    /// Get error recovery service
    public var errorRecovery: ErrorRecoveryService {
        return errorRecoveryService
    }

    /// Get compatibility service
    public var compatibility: CompatibilityService {
        return compatibilityService
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
        // Initialize database first
        do {
            try databaseManager.setup()
            logger.info("Database initialized successfully during bootstrap")
        } catch {
            logger.error("Failed to initialize database during bootstrap: \(error)")

            // In development, reset database on schema errors
            #if DEBUG
            logger.warning("Attempting to reset database due to error: \(error)")
            do {
                try databaseManager.reset()
                logger.info("Database reset successful after error")
            } catch let resetError {
                logger.error("Failed to reset database: \(resetError)")
                throw SDKError.databaseInitializationFailed(resetError)
            }
            #else
            throw SDKError.databaseInitializationFailed(error)
            #endif
        }

        // Logger is pre-configured through LoggingManager

        // Initialize configuration service with repository
        let configRepository = ConfigurationRepositoryImpl(
            databaseManager: databaseManager,
            apiClient: apiClient
        )
        _configurationService = ConfigurationService(
            configRepository: configRepository
        )

        // Ensure configuration is loaded immediately
        if let configService = _configurationService {
            await configService.ensureConfigurationLoaded()
            logger.info("Configuration loaded during SDK initialization")
        }

        // Initialize API client if API key is provided
        if !configuration.apiKey.isEmpty {
            apiClient = APIClient(
                baseURL: "https://api.runanywhere.ai",
                apiKey: configuration.apiKey
            )
        }

        // Initialize core services
        // Initialize model registry with configuration
        await (modelRegistry as? RegistryService)?.initialize(with: configuration)

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
        // Removed tokenizer health check

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
        return downloadService.isHealthy()
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

}
