import Foundation

/// Remote data source for sending telemetry data to API server
/// Routes to correct analytics endpoint based on environment
public actor RemoteTelemetryDataSource: RemoteDataSource {
    public typealias Entity = TelemetryData

    private let apiClient: APIClient?
    private let environment: SDKEnvironment
    private let logger = SDKLogger(category: "RemoteTelemetryDataSource")
    private let operationHelper = RemoteOperationHelper(timeout: 30.0)

    public init(apiClient: APIClient?, environment: SDKEnvironment = .development) {
        self.apiClient = apiClient
        self.environment = environment
        // Note: Can't use logger in init since it's an actor
        // Logging will happen when sendBatch is called
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

    public func fetch(id _: String) async throws -> TelemetryData? {
        // Telemetry is write-only to remote
        throw DataSourceError.operationFailed(
            NSError(domain: "RemoteTelemetryDataSource", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Remote telemetry fetch not supported"
            ])
        )
    }

    // swiftlint:disable:next prefer_concrete_types avoid_any_type
    public func fetchAll(_: [String: Any]?) async throws -> [TelemetryData] {
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

    public func delete(id _: String) async throws {
        // Telemetry deletion is typically not supported
        throw DataSourceError.operationFailed(
            NSError(domain: "RemoteTelemetryDataSource", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Remote telemetry delete not supported"
            ])
        )
    }

    // MARK: - Sync Support (Protocol Requirement)

    /// Sync batch from TelemetryData - not used, telemetry sends directly via sendPayloads()
    /// Required by RemoteDataSource protocol but never called for telemetry
    public func syncBatch(_ batch: [TelemetryData]) async throws -> [String] {
        // Telemetry doesn't use background sync - events are sent immediately via sendPayloads()
        // This method exists only for RemoteDataSource protocol conformance
        logger.warning("syncBatch called on TelemetryDataSource - this path is not used")
        return batch.map { $0.id }
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

    /// Send batch of typed telemetry payloads directly (preserves category → modality)
    public func sendPayloads(_ payloads: [TelemetryEventPayload]) async throws {
        guard let apiClient = apiClient else {
            throw DataSourceError.notAvailable
        }

        guard !payloads.isEmpty else {
            return
        }

        let typedEvents = payloads
        let endpoint = APIEndpoint.telemetryEndpoint(for: environment)

        // Development mode: Send array directly to Supabase REST API
        // Production mode: Send batch request wrapper to FastAPI backend
        if environment == .development {
            // Supabase needs all fields per event
            TelemetryEventPayload.productionEncodingMode = false

            // Supabase REST API expects array of rows: POST /rest/v1/table_name with body [{...}, {...}]
            let _: [TelemetryEventPayload] = try await operationHelper.withTimeout {
                try await apiClient.post(endpoint, typedEvents, requiresAuth: false)
            }
            logger.debug("Sent \(typedEvents.count) events to Supabase")
        } else {
            // FastAPI expects batch-level device_id/modality, not per-event
            TelemetryEventPayload.productionEncodingMode = true

            // Production: Group by modality and send batch requests
            // V2 modalities: llm, stt, tts, model
            // V1 fallback: "system" events use modality=nil for legacy table
            let v2Modalities: Set<String> = ["llm", "stt", "tts", "model"]
            let eventsByModality = Dictionary(grouping: typedEvents) { $0.modality ?? "system" }

            for (modality, modalityEvents) in eventsByModality where !modalityEvents.isEmpty {
                // For "system" events, use V1 path (modality=nil)
                let effectiveModality: String? = v2Modalities.contains(modality) ? modality : nil

                let batchRequest = TelemetryBatchRequest(
                    events: modalityEvents,
                    deviceId: DeviceIdentity.persistentUUID,
                    timestamp: Date(),
                    modality: effectiveModality  // nil for V1 (system), actual value for V2
                )

                let response: TelemetryBatchResponse = try await operationHelper.withTimeout {
                    try await apiClient.post(endpoint, batchRequest, requiresAuth: true)
                }

                if !response.success {
                    logger.warning("Telemetry partial failure: stored=\(response.eventsStored), skipped=\(response.eventsSkipped ?? 0)")
                }
            }
        }
    }
}
