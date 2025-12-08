import Foundation

/// Remote data source for sending telemetry data to API server
public actor RemoteTelemetryDataSource: RemoteDataSource {
    public typealias Entity = TelemetryData

    private let apiClient: APIClient?
    private let logger = SDKLogger(category: "RemoteTelemetryDataSource")
    private let operationHelper = RemoteOperationHelper(timeout: 30.0)

    public init(apiClient: APIClient?) {
        self.apiClient = apiClient
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        guard apiClient != nil else {
            return false
        }

        // Telemetry should work even if connection test fails
        // We'll queue events locally
        return true
    }

    public func validateConfiguration() async throws {
        guard apiClient != nil else {
            throw DataSourceError.configurationInvalid("API client not configured")
        }
    }

    // MARK: - RemoteDataSource Protocol

    public func fetch(id: String) async throws -> TelemetryData? {
        // Telemetry is write-only to remote
        throw DataSourceError.operationFailed(
            NSError(domain: "RemoteTelemetryDataSource", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Remote telemetry fetch not supported"
            ])
        )
    }

    // swiftlint:disable:next prefer_concrete_types avoid_any_type
    public func fetchAll(filter: [String: Any]?) async throws -> [TelemetryData] {
        // Telemetry is write-only to remote
        return []
    }

    public func save(_ entity: TelemetryData) async throws -> TelemetryData {
        guard apiClient != nil else {
            throw DataSourceError.notAvailable
        }

        return try await operationHelper.withTimeout {
            // Send telemetry event to API
            // In real implementation, this would be:
            // let response: TelemetryData = try await apiClient.post(
            //     APIEndpoint.telemetry,
            //     body: entity
            // )
            // return response

            // For now, return the same entity
            return entity
        }
    }

    public func delete(id: String) async throws {
        // Telemetry deletion is typically not supported
        throw DataSourceError.operationFailed(
            NSError(domain: "RemoteTelemetryDataSource", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Remote telemetry delete not supported"
            ])
        )
    }

    // MARK: - Sync Support

    public func syncBatch(_ batch: [TelemetryData]) async throws -> [String] {
        guard let apiClient = apiClient else {
            throw DataSourceError.notAvailable
        }

        var syncedIds: [String] = []

        // Convert TelemetryData to typed TelemetryEventPayload for API transmission
        // Backend expects typed fields, not a properties dictionary
        let typedEvents = batch.map { TelemetryEventPayload(from: $0) }

        let batchRequest = TelemetryBatchRequest(
            events: typedEvents,
            deviceId: PersistentDeviceIdentity.getPersistentDeviceUUID(),
            timestamp: Date()
        )

        do {
            // POST typed batch to telemetry endpoint
            let response: TelemetryBatchResponse = try await apiClient.post(
                .telemetry,
                batchRequest,
                requiresAuth: true
            )

            if response.success {
                syncedIds = batch.map { $0.id }
            } else {
                // Still mark as synced to avoid infinite retries
                syncedIds = batch.map { $0.id }
            }
        } catch {
            logger.error("Failed to sync telemetry batch: \(error)")
        }

        return syncedIds
    }

    public func testConnection() async throws -> Bool {
        guard apiClient != nil else {
            return false
        }

        return try await operationHelper.withTimeout {
            // Test telemetry endpoint availability
            // let _: [String: Bool] = try await apiClient.get(APIEndpoint.telemetryHealth)
            return true // Assume available for telemetry
        }
    }

    // MARK: - Telemetry-specific methods

    /// Send batch of telemetry events (immediate send, no local storage)
    public func sendBatch(_ events: [TelemetryData]) async throws {
        guard let apiClient = apiClient else {
            throw DataSourceError.notAvailable
        }

        guard !events.isEmpty else {
            return
        }

        // Convert to typed payloads
        let typedEvents = events.map { TelemetryEventPayload(from: $0) }

        let batchRequest = TelemetryBatchRequest(
            events: typedEvents,
            deviceId: PersistentDeviceIdentity.getPersistentDeviceUUID(),
            timestamp: Date()
        )

        let response: TelemetryBatchResponse = try await operationHelper.withTimeout {
            try await apiClient.post(
                .telemetry,
                batchRequest,
                requiresAuth: true
            )
        }

        if !response.success {
            logger.warning("Telemetry send partial failure: \(response.errors?.joined(separator: ", ") ?? "unknown")")
        }
    }
}
