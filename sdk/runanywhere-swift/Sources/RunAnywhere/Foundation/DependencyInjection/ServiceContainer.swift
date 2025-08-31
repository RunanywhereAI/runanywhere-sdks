import Foundation
import Pulse

/// Service container for dependency injection
public class ServiceContainer {
    /// Shared instance
    public static let shared: ServiceContainer = ServiceContainer()
    // MARK: - Core Services

    // Configuration validator - to be implemented when needed
    // private(set) lazy var configurationValidator: ConfigurationValidator = {
    //     ConfigurationValidator()
    // }()

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

    /// Voice capability service
    private(set) lazy var voiceCapabilityService: VoiceCapabilityService = {
        VoiceCapabilityService()
    }()


    /// Download service
    private(set) lazy var downloadService: AlamofireDownloadService = {
        AlamofireDownloadService()
    }()

    // Download queue removed - handled by AlamofireDownloadService


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

    /// Storage analyzer for storage operations
    private(set) lazy var storageAnalyzer: StorageAnalyzer = {
        DefaultStorageAnalyzer(fileManager: fileManager, modelRegistry: modelRegistry)
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


    /// Logger
    private(set) lazy var logger: SDKLogger = {
        SDKLogger()
    }()

    // Configuration service is defined below in Data Services section

    /// Database manager
    private lazy var databaseManager: DatabaseManager = {
        DatabaseManager.shared
    }()

    /// API client for sync operations
    private var apiClient: APIClient?

    /// Sync coordinator for centralized sync management
    private var _syncCoordinator: SyncCoordinator?
    public var syncCoordinator: SyncCoordinator? {
        get async {
            if _syncCoordinator == nil {
                _syncCoordinator = SyncCoordinator(
                    apiClient: apiClient,
                    enableAutoSync: false // Disabled: No backend currently available
                )
            }
            return _syncCoordinator
        }
    }

    // MARK: - Data Services

    /// Configuration service
    private var _configurationService: ConfigurationService?
    public var configurationService: ConfigurationServiceProtocol {
        get async {
            if let service = _configurationService {
                return service
            }
            let configRepo = ConfigurationRepositoryImpl(
                databaseManager: databaseManager,
                apiClient: apiClient
            )
            let service = ConfigurationService(
                configRepository: configRepo,
                syncCoordinator: await syncCoordinator
            )
            _configurationService = service
            return service
        }
    }

    /// Telemetry service
    private var _telemetryService: TelemetryService?
    public var telemetryService: TelemetryService {
        get async {
            if let service = _telemetryService {
                return service
            }
            let telemetryRepo = TelemetryRepositoryImpl(
                databaseManager: databaseManager,
                apiClient: apiClient
            )
            let service = TelemetryService(
                telemetryRepository: telemetryRepo,
                syncCoordinator: await syncCoordinator
            )
            _telemetryService = service
            return service
        }
    }

    /// Model info service
    private var _modelInfoService: ModelInfoService?
    public var modelInfoService: ModelInfoService {
        get async {
            if let service = _modelInfoService {
                return service
            }
            let modelRepo = ModelInfoRepositoryImpl(
                databaseManager: databaseManager,
                apiClient: apiClient
            )
            let service = ModelInfoService(
                modelInfoRepository: modelRepo,
                syncCoordinator: await syncCoordinator
            )
            _modelInfoService = service
            return service
        }
    }

    /// Device info service
    private var _deviceInfoService: DeviceInfoService?
    public var deviceInfoService: DeviceInfoService {
        get async {
            if let service = _deviceInfoService {
                return service
            }
            let deviceRepo = DeviceInfoRepositoryImpl(
                databaseManager: databaseManager,
                apiClient: apiClient
            )
            let service = DeviceInfoService(
                deviceInfoRepository: deviceRepo,
                syncCoordinator: await syncCoordinator
            )
            _deviceInfoService = service
            return service
        }
    }

    /// Generation analytics service - using unified pattern
    private var _generationAnalytics: GenerationAnalyticsService?
    public var generationAnalytics: GenerationAnalyticsService {
        get async {
            if let service = _generationAnalytics {
                return service
            }
            let service = GenerationAnalyticsService(queueManager: analyticsQueueManager)
            _generationAnalytics = service
            return service
        }
    }

    // MARK: - Unified Analytics Services

    /// Analytics queue manager - centralized queue for all analytics
    public var analyticsQueueManager: AnalyticsQueueManager {
        AnalyticsQueueManager.shared
    }

    /// STT Analytics Service - using unified pattern
    private var _sttAnalytics: STTAnalyticsService?
    public var sttAnalytics: STTAnalyticsService {
        get async {
            if let service = _sttAnalytics {
                return service
            }
            let service = STTAnalyticsService(queueManager: analyticsQueueManager)
            _sttAnalytics = service
            return service
        }
    }

    /// Voice Analytics Service - using unified pattern
    private var _voiceAnalytics: VoiceAnalyticsService?
    public var voiceAnalytics: VoiceAnalyticsService {
        get async {
            if let service = _voiceAnalytics {
                return service
            }
            let service = VoiceAnalyticsService(queueManager: analyticsQueueManager)
            _voiceAnalytics = service
            return service
        }
    }

    /// Monitoring Analytics Service - using unified pattern
    private var _monitoringAnalytics: MonitoringAnalyticsService?
    public var monitoringAnalytics: MonitoringAnalyticsService {
        get async {
            if let service = _monitoringAnalytics {
                return service
            }
            let service = MonitoringAnalyticsService(queueManager: analyticsQueueManager)
            _monitoringAnalytics = service
            return service
        }
    }

    // MARK: - Public Service Access


    /// Get memory service
    public var memory: MemoryManager {
        return memoryService
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

        // Initialize API client if API key is provided
        if !configuration.apiKey.isEmpty {
            apiClient = APIClient(
                baseURL: RunAnywhereConstants.apiURLs.current,
                apiKey: configuration.apiKey
            )
        }

        // Initialize configuration service with repository
        let configRepository = ConfigurationRepositoryImpl(
            databaseManager: databaseManager,
            apiClient: apiClient
        )
        _configurationService = ConfigurationService(
            configRepository: configRepository,
            syncCoordinator: await syncCoordinator
        )

        // Load configuration on launch with simple fallback
        if let configService = _configurationService {
            let effectiveConfig = await configService.loadConfigurationOnLaunch(apiKey: configuration.apiKey)
            logger.info("Configuration loaded during SDK initialization (source: \(effectiveConfig.source))")
        }

        // Initialize core services
        // Initialize model registry with configuration
        await (modelRegistry as? RegistryService)?.initialize(with: configuration)

        // Populate mock data in debug mode
        if EnvironmentConfiguration.current.environment.isDebug {
            do {
                let modelService = await self.modelInfoService
                if let modelRepo = await modelService.repository as? ModelInfoRepositoryImpl {
                    try await modelRepo.checkAndPopulateMockDataIfNeeded()
                    logger.info("Mock model data population check completed")
                }
            } catch {
                logger.warning("Failed to populate mock model data: \(error)")
                // Don't fail initialization if mock population fails
            }
        }

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

        // Initialize voice capability service
        do {
            try await voiceCapabilityService.initialize()
            logger.info("Voice capability service initialized")
        } catch {
            logger.warning("Failed to initialize voice capability service: \(error)")
            // Voice is optional, don't fail the entire initialization
        }

        // Initialize unified analytics queue manager
        if let apiClient = apiClient {
            let telemetryRepo = TelemetryRepositoryImpl(
                databaseManager: databaseManager,
                apiClient: apiClient
            )
            await analyticsQueueManager.initialize(telemetryRepository: telemetryRepo)
            logger.info("Analytics queue manager initialized")
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
        health["voice"] = await voiceCapabilityService.isHealthy()
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


}
