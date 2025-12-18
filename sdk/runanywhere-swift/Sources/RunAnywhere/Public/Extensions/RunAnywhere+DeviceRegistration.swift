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

        // Perform device registration (non-blocking, doesn't throw)
        if let networkService = serviceContainer.networkService {
            await serviceContainer.deviceRegistrationService.registerIfNeeded(
                networkService: networkService,
                environment: environment
            )
        }

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
        let apiClient = try await setupNetworkAndAuthentication(
            params: params,
            environment: environment,
            logger: logger
        )

        // Create and inject core services
        let coreServices = try await setupCoreServices(
            apiClient: apiClient,
            environment: environment,
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

        // Create API client for development using Supabase config
        let apiClient: APIClient
        if let supabaseConfig = SupabaseConfig.configuration(for: .development) {
            // Use Supabase for development analytics
            apiClient = APIClient(baseURL: supabaseConfig.projectURL, apiKey: supabaseConfig.anonKey)
            logger.debug("APIClient initialized for development with Supabase: \(supabaseConfig.projectURL.absoluteString)")
        } else {
            // Fallback to provided params if Supabase config unavailable
            apiClient = APIClient(baseURL: params.baseURL, apiKey: params.apiKey)
            logger.debug("APIClient initialized for development: \(params.baseURL.absoluteString)")
        }
        serviceContainer.networkService = apiClient
        serviceContainer.apiClient = apiClient

        // Create and inject core services
        let coreServices = try await setupCoreServices(
            apiClient: apiClient,
            environment: .development,
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

    /// Setup network and authentication for production/staging
    private static func setupNetworkAndAuthentication(
        params: SDKInitParams,
        environment: SDKEnvironment,
        logger: SDKLogger
    ) async throws -> APIClient {
        // Create and authenticate - AuthenticationService.createAndAuthenticate creates its own APIClient
        let (apiClient, authService) = try await AuthenticationService.createAndAuthenticate(
            baseURL: params.baseURL,
            apiKey: params.apiKey
        )

        serviceContainer.networkService = apiClient
        serviceContainer.authenticationService = authService
        serviceContainer.apiClient = apiClient
        logger.info("APIClient configured for \(environment.description)")
        logger.info("Authentication successful")

        return apiClient
    }

    /// Create and inject core services
    private static func setupCoreServices(
        apiClient: APIClient?,
        environment: SDKEnvironment,
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

        // Create TelemetryRepository with environment for correct endpoint routing
        let telemetryRepo = TelemetryRepositoryImpl(
            databaseManager: DatabaseManager.shared,
            apiClient: apiClient,
            environment: environment
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

        // Create ModelAssignmentService - use apiClient if available, otherwise skip
        if let networkService = serviceContainer.networkService {
            let modelAssignmentService = ModelAssignmentService(
                networkService: networkService,
                modelInfoService: modelInfoService
            )
            serviceContainer.setModelAssignmentService(modelAssignmentService)
        }

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
        // Events flow: Feature Analytics → EventPublisher → AnalyticsQueueManager → TelemetryRepository → RemoteTelemetryDataSource
        await serviceContainer.analyticsQueueManager.initialize(telemetryRepository: telemetryRepository)
        EventPublisher.shared.initialize(analyticsQueue: serviceContainer.analyticsQueueManager)

        logger.info("Analytics and event publisher initialized")
    }
}
