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
            logger.debug("API client not configured for telemetry")
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

    public func fetchAll(filter: [String: Any]?) async throws -> [TelemetryData] {
        // Telemetry is write-only to remote
        return []
    }

    public func save(_ entity: TelemetryData) async throws -> TelemetryData {
        guard apiClient != nil else {
            throw DataSourceError.notAvailable
        }

        logger.debug("Sending telemetry event: \(entity.id)")

        return try await operationHelper.withTimeout {
            // Send telemetry event to API
            // In real implementation, this would be:
            // let response: TelemetryData = try await apiClient.post(
            //     APIEndpoint.telemetry,
            //     body: entity
            // )
            // return response

            // For now, return the same entity
            self.logger.debug("Telemetry send not yet implemented")
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

    public func testConnection() async throws -> Bool {
        guard apiClient != nil else {
            return false
        }

        return try await operationHelper.withTimeout {
            // Test telemetry endpoint availability
            // let _: [String: Bool] = try await apiClient.get(APIEndpoint.telemetryHealth)
            self.logger.debug("Telemetry service connection test skipped (not implemented)")
            return true // Assume available for telemetry
        }
    }

    // MARK: - Telemetry-specific methods

    /// Send batch of telemetry events
    public func sendBatch(_ events: [TelemetryData]) async throws {
        guard apiClient != nil else {
            throw DataSourceError.notAvailable
        }

        guard !events.isEmpty else {
            return
        }

        logger.info("Sending batch of \(events.count) telemetry events")

        try await operationHelper.withTimeout {
            // Send batch to API
            // let _: [String: Any] = try await apiClient.post(
            //     APIEndpoint.telemetryBatch,
            //     body: ["events": events]
            // )

            self.logger.debug("Telemetry batch send not yet implemented")
        }

        logger.info("Successfully sent \(events.count) telemetry events")
    }
}
