import Foundation
import Pulse

/// Service container for dependency injection
public class ServiceContainer {
    /// Shared instance
    public static let shared: ServiceContainer = ServiceContainer()
    // MARK: - Core Services

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

    /// Database manager
    private lazy var databaseManager: DatabaseManager = {
        DatabaseManager.shared
    }()

    /// Network service (environment-based: mock or real)
    public private(set) var networkService: (any NetworkService)?

    /// Authentication service
    public private(set) var authenticationService: AuthenticationService?

    /// API client for sync operations
    private var apiClient: APIClient?

    /// Sync coordinator for centralized sync management
    private var _syncCoordinator: SyncCoordinator?
    public var syncCoordinator: SyncCoordinator? {
        get async {
            if _syncCoordinator == nil {
                _syncCoordinator = SyncCoordinator(
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

    /// Model assignment service storage (using Any to avoid circular dependency)
    private var _modelAssignmentService: Any?

    /// Set the model assignment service (called from extension)
    public func setModelAssignmentService(_ service: Any) {
        _modelAssignmentService = service
    }

    /// Get the stored model assignment service
    public func getModelAssignmentService() -> Any? {
        return _modelAssignmentService
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

    // MARK: - Public Service Access

    /// Get memory service
    public var memory: MemoryManager {
        return memoryService
    }


    // MARK: - Initialization

    public init() {
        // Container is ready for lazy initialization
    }

    /**
     * Initialize all SDK services and sync with backend
     *
     * This method performs complete SDK service initialization:
     *
     * 1. **Network Services**: Store authentication service and API client
     * 2. **Device Information**: Collect and sync device info to backend
     * 3. **Configuration Service**: Load configuration from backend/cache/defaults
     * 4. **Model Catalog**: Sync model information from backend
     * 5. **Model Registry**: Initialize for model discovery and management
     * 6. **Memory Management**: Configure memory thresholds
     * 7. **Voice Services**: Initialize voice capability (optional)
     * 8. **Analytics**: Setup telemetry and analytics tracking
     *
     * - Parameters:
     *   - params: SDK initialization parameters
     *   - authService: Configured authentication service
     *   - apiClient: Configured API client for backend communication
     *
     * - Returns: Loaded configuration data
     * - Throws: SDKError if critical service initialization fails
     */
    public func bootstrap(with params: SDKInitParams, authService: AuthenticationService, apiClient: APIClient) async throws -> ConfigurationData {
        // Step 1: Create and store network service based on environment
        self.networkService = NetworkServiceFactory.createNetworkService(
            for: params.environment,
            params: params
        )

        // Store auth service and API client if provided
        self.authenticationService = authService
        self.apiClient = apiClient

        logger.debug("Network services configured for \(params.environment.description)")

        // Step 2: Initialize and sync device information
        logger.debug("Collecting device information")
        let deviceInfoService = await self.deviceInfoService
        if let deviceInfo = await deviceInfoService.loadCurrentDeviceInfo() {
            EventBus.shared.publish(SDKDeviceEvent.deviceInfoCollected(deviceInfo: deviceInfo))

            // Sync to backend
            try? await deviceInfoService.syncToCloud()
            logger.info("Device information synced to backend")

            // Log device summary for debugging
            let summary = await deviceInfoService.getDeviceInfoSummary()
            logger.info("Device Info:\n\(summary)")
        }

        // Step 3: Initialize configuration service and load configuration
        let configRepository = ConfigurationRepositoryImpl(
            databaseManager: databaseManager,
            apiClient: apiClient
        )
        _configurationService = ConfigurationService(
            configRepository: configRepository,
            syncCoordinator: await syncCoordinator
        )

        // Load configuration from backend/cache/defaults
        var loadedConfig: ConfigurationData?
        if let configService = _configurationService {
            let effectiveConfig = await configService.loadConfigurationOnLaunch(apiKey: params.apiKey)
            loadedConfig = effectiveConfig
            EventBus.shared.publish(SDKConfigurationEvent.loaded(configuration: effectiveConfig))
            logger.info("Configuration loaded (source: \(effectiveConfig.source))")
        }

        // Step 4: Sync model catalog from backend
        logger.debug("Syncing model catalog")
        let modelInfoService = await self.modelInfoService

        // Trigger sync to fetch latest models from backend
        try? await modelInfoService.syncModelInfo()

        // Load stored models (now includes synced data)
        let storedModels = try? await modelInfoService.loadStoredModels()
        if let models = storedModels {
            logger.info("Model catalog synced: \(models.count) models available")
            EventBus.shared.publish(SDKModelEvent.catalogLoaded(models: models))
        }

        // Step 5: Initialize model registry
        await (modelRegistry as? RegistryService)?.initialize(with: params.apiKey)
        logger.debug("Model registry initialized")

        // Step 6: Configure memory management
        memoryService.setMemoryThreshold(500_000_000) // 500MB default
        logger.debug("Memory threshold configured")

        // Step 7: Initialize optional voice services
        do {
            try await voiceCapabilityService.initialize()
            logger.info("Voice capability service initialized")
        } catch {
            logger.warning("Voice service initialization failed (optional): \(error)")
        }

        // Step 8: Initialize analytics
        if let client = self.apiClient {
            let telemetryRepo = TelemetryRepositoryImpl(
                databaseManager: databaseManager,
                apiClient: client
            )
            await analyticsQueueManager.initialize(telemetryRepository: telemetryRepo)
            logger.info("Analytics initialized")
        }

        // Return the loaded configuration or create a default one
        if let config = loadedConfig {
            return config
        } else {
            // Create default configuration if none was loaded
            let defaultConfig = ConfigurationData(
                id: "default-\(UUID().uuidString)",
                apiKey: params.apiKey,
                source: .defaults
            )
            return defaultConfig
        }
    }

    /**
     * Initialize SDK services for development mode (no API authentication)
     *
     * This method performs local-only SDK service initialization:
     *
     * 1. **Device Information**: Collect local device info
     * 2. **Configuration Service**: Load configuration from defaults only
     * 3. **Model Catalog**: Use mock model data
     * 4. **Model Registry**: Initialize for model discovery and management
     * 5. **Memory Management**: Configure memory thresholds
     * 6. **Voice Services**: Initialize voice capability (optional)
     * 7. **Analytics**: Setup with local-only tracking
     *
     * - Parameters:
     *   - params: SDK initialization parameters
     *
     * - Returns: Loaded configuration data
     * - Throws: SDKError if critical service initialization fails
     */
    public func bootstrapDevelopmentMode(with params: SDKInitParams) async throws -> ConfigurationData {
        logger.info("🚀 Bootstrapping SDK in DEVELOPMENT mode")

        // Create mock network service for development
        self.networkService = NetworkServiceFactory.createNetworkService(
            for: .development,
            params: params
        )
        logger.info("🔧 Mock network service initialized")

        // Step 1: Collect device information (local only)
        logger.debug("Collecting device information")
        let deviceInfoService = await self.deviceInfoService
        if let deviceInfo = await deviceInfoService.loadCurrentDeviceInfo() {
            EventBus.shared.publish(SDKDeviceEvent.deviceInfoCollected(deviceInfo: deviceInfo))

            // Log device summary for debugging
            let summary = await deviceInfoService.getDeviceInfoSummary()
            logger.info("Device Info:\n\(summary)")
        }

        // Step 2: Create default configuration (no API needed)
        let defaultConfig = ConfigurationData(
            id: "dev-\(UUID().uuidString)",
            apiKey: params.apiKey.isEmpty ? "dev-mode" : params.apiKey,
            source: .defaults
        )

        _configurationService = ConfigurationService(
            configRepository: nil, // No repository in dev mode
            syncCoordinator: nil // No sync in dev mode
        )

        EventBus.shared.publish(SDKConfigurationEvent.loaded(configuration: defaultConfig))
        logger.info("Configuration loaded (source: defaults for development)")

        // Step 3: Mock model catalog
        logger.debug("Mock models will be provided by MockNetworkService")

        // Step 4: Initialize model registry
        await (modelRegistry as? RegistryService)?.initialize(with: params.apiKey)
        logger.debug("Model registry initialized")

        // Step 5: Configure memory management
        memoryService.setMemoryThreshold(500_000_000) // 500MB default
        logger.debug("Memory threshold configured")

        // Step 6: Initialize optional voice services
        do {
            try await voiceCapabilityService.initialize()
            logger.info("Voice capability service initialized")
        } catch {
            logger.warning("Voice service initialization failed (optional): \(error)")
        }

        // Step 7: Skip analytics initialization in development mode
        logger.info("Analytics disabled in development mode")

        logger.info("✅ Development mode bootstrap completed")

        // Return the default configuration
        return defaultConfig
    }

    // MARK: - Local Setup

    /// Setup only local services (no network calls)
    /// Called during fast initialization
    /// - Parameter params: SDK initialization parameters
    /// - Throws: SDKError if local setup fails
    public func setupLocalServices(with params: SDKInitParams) throws {
        let logger = SDKLogger(category: "ServiceContainer.LocalSetup")
        logger.info("Setting up local services...")

        // Step 1: Configure memory management
        memoryService.setMemoryThreshold(500_000_000) // 500MB default
        logger.debug("Memory threshold configured")

        // Step 2: Initialize model registry for local discovery
        // This needs to happen even in fast initialization to discover cached models
        Task {
            await (modelRegistry as? RegistryService)?.initialize(with: params.apiKey)
            logger.debug("Model registry initialized for local discovery")
        }

        // Step 3: Setup analytics for local queuing (no network submission yet)
        // Analytics will be initialized when network services are available
        logger.debug("Analytics queue ready for lazy initialization")

        logger.info("✅ Local services setup completed")
    }

    /// Initialize network services lazily when first needed
    /// - Parameter params: SDK initialization parameters
    /// - Throws: SDKError if network initialization fails
    public func initializeNetworkServices(with params: SDKInitParams) async throws {
        // Skip if already initialized
        if authenticationService != nil {
            return
        }

        let logger = SDKLogger(category: "ServiceContainer.NetworkSetup")
        logger.info("Initializing network services...")

        // Step 1: Create and store network service based on environment
        self.networkService = NetworkServiceFactory.createNetworkService(
            for: params.environment,
            params: params
        )

        // Step 2: Create API client and authentication service for production/staging
        if params.environment != .development {
            guard let baseURL = params.baseURL else {
                throw SDKError.validationFailed("Base URL is required for \(params.environment.description)")
            }

            let apiClient = APIClient(
                baseURL: baseURL,
                apiKey: params.apiKey
            )

            let authService = AuthenticationService(apiClient: apiClient)
            await apiClient.setAuthenticationService(authService)

            // Store for later use
            self.authenticationService = authService
            self.apiClient = apiClient

            // Authenticate with backend
            let authResponse = try await authService.authenticate(apiKey: params.apiKey)
            logger.info("Authentication successful, token expires in \(authResponse.expiresIn) seconds")
        }

        // Step 3: Initialize analytics with API client
        if let client = self.apiClient {
            let telemetryRepo = TelemetryRepositoryImpl(
                databaseManager: databaseManager,
                apiClient: client
            )
            await analyticsQueueManager.initialize(telemetryRepository: telemetryRepo)
            logger.info("Analytics initialized")
        }

        logger.info("✅ Network services initialization completed")
    }

    /// Reset service container state (for testing)
    public func reset() {
        authenticationService = nil
        apiClient = nil
        networkService = nil
        _syncCoordinator = nil
        _configurationService = nil
        _telemetryService = nil
        _modelInfoService = nil
        _modelAssignmentService = nil
        _deviceInfoService = nil
        _generationAnalytics = nil
        _sttAnalytics = nil
        _voiceAnalytics = nil
    }
}
