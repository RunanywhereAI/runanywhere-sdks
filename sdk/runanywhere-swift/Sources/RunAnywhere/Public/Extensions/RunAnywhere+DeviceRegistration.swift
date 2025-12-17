import Foundation

// MARK: - Device Registration (Direct Service Orchestration)

extension RunAnywhere {

    /// Container for core services during initialization
    internal struct CoreServices {
        let configService: ConfigurationService
        let telemetryRepo: TelemetryRepositoryImpl
        let modelInfoService: ModelInfoService
    }

    /// Ensure device is registered with backend (lazy registration)
    /// Orchestrates service initialization directly
    /// Note: This is O(1) after first successful call due to isBootstrapped flag
    internal static func ensureDeviceRegistered() async throws {
        // Fast path: already bootstrapped, return immediately (O(1))
        if isBootstrapped {
            return
        }

        guard let params = initParams, let environment = currentEnvironment else {
            throw RunAnywhereError.notInitialized
        }

        let logger = SDKLogger(category: "RunAnywhere.Bootstrap")

        // Initialize services based on environment
        if environment != .development && serviceContainer.authenticationService == nil {
            try await initializeProductionServices(params: params, environment: environment, logger: logger)
        } else if environment == .development && serviceContainer.networkService == nil {
            try await initializeDevelopmentServices(params: params, logger: logger)
        }

        // Now perform actual device registration
        try await serviceContainer.deviceRegistrationService.ensureDeviceRegistered(
            params: params,
            environment: environment,
            serviceContainer: serviceContainer
        )

        // Mark bootstrap as complete - subsequent calls will be O(1)
        isBootstrapped = true
    }

    /// Initialize production/staging services
    private static func initializeProductionServices(
        params: SDKInitParams,
        environment: SDKEnvironment,
        logger: SDKLogger
    ) async throws {
        logger.info("Initializing network and authentication services...")

        // Setup network and authentication
        let (networkService, apiClient, _) = try await setupNetworkAndAuthentication(
            params: params,
            environment: environment,
            logger: logger
        )

        // Create and inject core services
        let coreServices = try await setupCoreServices(
            apiClient: apiClient,
            networkService: networkService,
            logger: logger
        )

        // Load configuration and models
        try await loadConfigurationAndModels(
            configService: coreServices.configService,
            modelInfoService: coreServices.modelInfoService,
            apiKey: params.apiKey,
            logger: logger
        )

        // Initialize analytics
        try await initializeAnalytics(
            telemetryRepository: coreServices.telemetryRepo,
            apiKey: params.apiKey,
            logger: logger
        )

        logger.info("✅ Production/staging bootstrap completed")
    }

    /// Initialize development mode services
    private static func initializeDevelopmentServices(
        params: SDKInitParams,
        logger: SDKLogger
    ) async throws {
        logger.info("Initializing development mode services (full service stack)...")

        // Setup network service and API client for development
        let networkService = NetworkServiceFactory.createNetworkService(for: .development, params: params)
        serviceContainer.networkService = networkService

        let apiClient = networkService as? APIClient
        serviceContainer.apiClient = apiClient
        logger.debug("Network service and API client initialized (development mode)")

        // Create and inject core services
        let coreServices = try await setupCoreServices(
            apiClient: apiClient,
            networkService: networkService,
            logger: logger
        )

        // Load configuration and models
        try await loadConfigurationAndModels(
            configService: coreServices.configService,
            modelInfoService: coreServices.modelInfoService,
            apiKey: params.apiKey,
            logger: logger
        )

        // Initialize analytics
        try await initializeAnalytics(
            telemetryRepository: coreServices.telemetryRepo,
            apiKey: params.apiKey,
            logger: logger
        )

        logger.info("✅ Development mode bootstrap completed (all services active)")
    }

    /// Setup network service and authentication
    private static func setupNetworkAndAuthentication(
        params: SDKInitParams,
        environment: SDKEnvironment,
        logger: SDKLogger
    ) async throws -> (NetworkService, APIClient, AuthenticationService) {
        // Setup network service
        let networkService = NetworkServiceFactory.createNetworkService(for: environment, params: params)
        serviceContainer.networkService = networkService
        logger.debug("Network service configured for \(environment.description)")

        // Create API client and authentication service
        let (apiClient, authService) = try await AuthenticationService.createAndAuthenticate(
            baseURL: params.baseURL,
            apiKey: params.apiKey
        )
        serviceContainer.authenticationService = authService
        serviceContainer.apiClient = apiClient
        logger.info("Authentication successful")

        return (networkService, apiClient, authService)
    }

    /// Create and inject core services
    private static func setupCoreServices(
        apiClient: APIClient?,
        networkService: NetworkService,
        logger: SDKLogger
    ) async throws -> CoreServices {
        logger.debug("Creating core services...")

        // Create SyncCoordinator
        let syncCoordinator = SyncCoordinator(enableAutoSync: false)
        serviceContainer.setSyncCoordinator(syncCoordinator)

        // Create ConfigurationService
        let configRepo = ConfigurationRepositoryImpl(
            databaseManager: DatabaseManager.shared,
            apiClient: apiClient
        )
        let configService = ConfigurationService(
            configRepository: configRepo,
            syncCoordinator: syncCoordinator
        )
        serviceContainer.setConfigurationService(configService)

        // Create TelemetryRepository
        let telemetryRepo = TelemetryRepositoryImpl(
            databaseManager: DatabaseManager.shared,
            apiClient: apiClient
        )

        // Create ModelInfoService
        let modelRepo = ModelInfoRepositoryImpl(
            databaseManager: DatabaseManager.shared,
            apiClient: apiClient
        )
        let modelInfoService = ModelInfoService(
            modelInfoRepository: modelRepo,
            syncCoordinator: syncCoordinator
        )
        serviceContainer.setModelInfoService(modelInfoService)

        // Create ModelAssignmentService
        let modelAssignmentService = ModelAssignmentService(
            networkService: networkService,
            modelInfoService: modelInfoService
        )
        serviceContainer.setModelAssignmentService(modelAssignmentService)

        logger.info("Core services created and injected")

        return CoreServices(
            configService: configService,
            telemetryRepo: telemetryRepo,
            modelInfoService: modelInfoService
        )
    }

    /// Load configuration and sync model catalog
    private static func loadConfigurationAndModels(
        configService: ConfigurationService,
        modelInfoService: ModelInfoService,
        apiKey: String,
        logger: SDKLogger
    ) async throws {
        // Load configuration
        let config = await configService.loadConfigurationOnLaunch(apiKey: apiKey)
        EventPublisher.shared.track(SDKLifecycleEvent.configLoaded(source: config.source.rawValue))
        logger.info("Configuration loaded (source: \(config.source))")

        // Sync model catalog
        try? await modelInfoService.syncModelInfo()
        _ = try? await modelInfoService.loadStoredModels()
        logger.debug("Model catalog synced")
    }

    /// Initialize analytics and event publisher
    private static func initializeAnalytics(
        telemetryRepository: TelemetryRepositoryImpl,
        apiKey: String,
        logger: SDKLogger
    ) async throws {
        // Initialize model registry
        await (serviceContainer.modelRegistry as? RegistryService)?.initialize(with: apiKey)
        logger.debug("Model registry initialized")

        // Initialize analytics and event publisher
        await serviceContainer.analyticsQueueManager.initialize(telemetryRepository: telemetryRepository)
        EventPublisher.shared.initialize(analyticsQueue: serviceContainer.analyticsQueueManager)
        logger.info("Analytics and event publisher initialized")
    }
}
