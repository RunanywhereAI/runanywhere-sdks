import Foundation

/// Remote data source for sending telemetry data to API server
/// Routes to correct analytics endpoint based on environment
public actor RemoteTelemetryDataSource {
    private let apiClient: APIClient?
    private let environment: SDKEnvironment
    private let logger = SDKLogger(category: "RemoteTelemetryDataSource")
    private let operationHelper = RemoteOperationHelper(timeout: 30.0)

    public init(apiClient: APIClient?, environment: SDKEnvironment = .development) {
        self.apiClient = apiClient
        self.environment = environment
    }

    // MARK: - Availability Check

    public func isAvailable() async -> Bool {
        apiClient != nil
    }

    // MARK: - Single Event Methods

    /// Send a single SDK event to the backend
    /// - Parameter event: The event to send
    public func sendEvent(_ event: any SDKEvent) async {
        let payload = TelemetryEventPayload(from: event)
        do {
            try await sendPayloads([payload])
        } catch {
            logger.warning("Failed to send event: \(error.localizedDescription)")
        }
    }

    // MARK: - Telemetry Methods

    /// Send batch of typed telemetry payloads directly (preserves category → modality)
    public func sendPayloads(_ payloads: [TelemetryEventPayload]) async throws {
        guard let apiClient = apiClient else {
            throw SDKError.network(.serviceNotAvailable, "Remote telemetry data source not available")
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
