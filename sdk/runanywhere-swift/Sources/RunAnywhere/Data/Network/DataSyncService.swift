import Foundation

/// Service for managing data persistence and synchronization
public actor DataSyncService {
    private let logger = SDKLogger(category: "DataSyncService")

    // Repositories
    private let configRepository: any ConfigurationRepository
    public let telemetryRepository: any TelemetryRepository
    private let modelMetadataRepository: any ModelMetadataRepository

    // Sync timer
    private var syncTimer: Task<Void, Never>?

    // MARK: - Initialization

    public init(
        database: DatabaseCore,
        apiClient: APIClient?,
        enableAutoSync: Bool = true
    ) {
        self.configRepository = ConfigurationRepositoryImpl(
            database: database,
            apiClient: apiClient
        )

        self.telemetryRepository = TelemetryRepositoryImpl(
            database: database,
            apiClient: apiClient
        )

        self.modelMetadataRepository = ModelMetadataRepositoryImpl(
            database: database,
            apiClient: apiClient
        )

        if enableAutoSync {
            Task {
                await startAutoSync()
            }
        }

        logger.info("DataSyncService initialized")
    }

    deinit {
        syncTimer?.cancel()
    }

    // MARK: - Configuration Management

    /// Save configuration
    public func saveConfiguration(_ config: ConfigurationData) async throws {
        try await configRepository.save(config)
    }

    /// Get current configuration
    public func getConfiguration() async throws -> ConfigurationData? {
        return try await configRepository.fetch(id: SDKConstants.ConfigurationDefaults.configurationId)
    }

    // MARK: - Telemetry Management

    /// Track a telemetry event
    public func trackEvent(
        _ type: String,
        properties: [String: String] = [:]
    ) async throws {
        // Convert string to TelemetryEventType enum, default to .custom if not found
        let eventType = TelemetryEventType(rawValue: type) ?? .custom
        try await telemetryRepository.trackEvent(eventType, properties: properties)
    }

    /// Get telemetry events
    public func getTelemetryEvents() async throws -> [TelemetryData] {
        return try await telemetryRepository.fetchAll()
    }

    // MARK: - Model Metadata Management

    /// Save model metadata
    public func saveModelMetadata(_ model: ModelInfo) async throws {
        try await modelMetadataRepository.saveModelMetadata(model)
    }

    /// Update last used date for a model
    public func updateModelLastUsed(for modelId: String) async throws {
        try await modelMetadataRepository.updateLastUsed(for: modelId)
    }

    /// Update thinking support for a model
    public func updateThinkingSupport(
        for modelId: String,
        supportsThinking: Bool,
        thinkingTagPattern: ThinkingTagPattern?
    ) async throws {
        try await modelMetadataRepository.updateThinkingSupport(
            for: modelId,
            supportsThinking: supportsThinking,
            thinkingTagPattern: thinkingTagPattern
        )
    }

    /// Load stored models
    public func loadStoredModels() async throws -> [ModelInfo] {
        return try await modelMetadataRepository.loadStoredModels()
    }

    /// Remove model metadata
    public func removeModelMetadata(_ modelId: String) async throws {
        try await modelMetadataRepository.delete(id: modelId)
    }

    // MARK: - Sync Operations

    /// Manually trigger sync for all repositories
    public func syncAll() async throws {
        logger.info("Starting manual sync")

        // Sync in parallel
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await self.configRepository.sync()
                }
                group.addTask {
                    try await self.telemetryRepository.sync()
                }
                group.addTask {
                    try await self.modelMetadataRepository.sync()
                }

                try await group.waitForAll()
            }
            logger.info("Manual sync completed")
        } catch {
            logger.error("Sync failed: \(error)")
            throw error
        }
    }

    /// Start automatic sync timer
    private func startAutoSync() {
        syncTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes

                do {
                    try await syncAll()
                } catch {
                    logger.error("Auto sync failed: \(error)")
                }
            }
        }
    }

    /// Stop automatic sync
    public func stopAutoSync() {
        syncTimer?.cancel()
        syncTimer = nil
    }
}
