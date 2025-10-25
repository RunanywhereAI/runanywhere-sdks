import Foundation
#if os(iOS)
import UIKit
#endif

/// Mock network service for development mode
/// Returns predefined JSON responses without making actual network calls
public actor MockNetworkService: NetworkService {
    private let logger = SDKLogger(category: "MockNetworkService")
    private let mockDelay: UInt64 = 500_000_000 // 0.5 seconds to simulate network delay

    public init() {
        logger.info("MockNetworkService initialized - all network calls will return mock data")
    }

    // MARK: - NetworkService Protocol

    public func postRaw(_ endpoint: APIEndpoint, _ payload: Data, requiresAuth: Bool) async throws -> Data {
        logger.debug("Mock POST to \(endpoint.path)")

        // Simulate network delay
        try await Task.sleep(nanoseconds: mockDelay)

        // Return mock response based on endpoint
        return try getMockResponse(for: endpoint, method: "POST")
    }

    public func getRaw(_ endpoint: APIEndpoint, requiresAuth: Bool) async throws -> Data {
        logger.debug("Mock GET to \(endpoint.path)")

        // Simulate network delay
        try await Task.sleep(nanoseconds: mockDelay)

        // Return mock response based on endpoint
        return try getMockResponse(for: endpoint, method: "GET")
    }

    // MARK: - Mock Data Management

    private func getMockResponse(for endpoint: APIEndpoint, method: String) throws -> Data {
        // First try to load from JSON file if available
        if let fileData = loadMockFile(for: endpoint, method: method) {
            logger.debug("Loaded mock data from file for \(endpoint.path)")
            return fileData
        }

        // Otherwise return programmatic mock data
        logger.debug("Using programmatic mock data for \(endpoint.path)")
        return try getProgrammaticMockData(for: endpoint, method: method)
    }

    private func loadMockFile(for endpoint: APIEndpoint, method: String) -> Data? {
        // Build file name from endpoint path
        let fileName = buildMockFileName(for: endpoint, method: method)

        // Try to load from bundle
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            // Try to load from MockResponses directory in the SDK
            let mockDir = URL(fileURLWithPath: #file)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("MockResponses")
                .appendingPathComponent("\(fileName).json")

            if let data = try? Data(contentsOf: mockDir) {
                return data
            }

            return nil
        }

        return data
    }

    private func buildMockFileName(for endpoint: APIEndpoint, method: String) -> String {
        // Convert endpoint path to file name
        // e.g., /v1/auth/token with POST -> post_v1_auth_token
        let cleanPath = endpoint.path
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        return "\(method.lowercased())_\(cleanPath)"
    }

    private func getProgrammaticMockData(for endpoint: APIEndpoint, method: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        switch endpoint {
        case .authenticate:
            let response = AuthenticationResponse(
                accessToken: "mock-access-token-\(UUID().uuidString)",
                deviceId: "mock-device-\(UUID().uuidString)",
                expiresIn: 3600,
                organizationId: "mock-org-\(UUID().uuidString)",
                refreshToken: "mock-refresh-token-\(UUID().uuidString)",
                tokenType: "Bearer",
                userId: "mock-user-\(UUID().uuidString)"
            )
            return try encoder.encode(response)

        case .refreshToken:
            let refreshResponse = AuthenticationResponse(
                accessToken: "mock-access-token-\(UUID().uuidString)",
                deviceId: "mock-device-\(UUID().uuidString)",
                expiresIn: 3600,
                organizationId: "mock-org-\(UUID().uuidString)",
                refreshToken: "mock-refresh-token-\(UUID().uuidString)",
                tokenType: "Bearer",
                userId: "mock-user-\(UUID().uuidString)"
            )
            return try encoder.encode(refreshResponse)

        case .registerDevice:
            let deviceResponse = DeviceRegistrationResponse(
                deviceId: "mock-device-\(UUID().uuidString)",
                status: "registered",
                syncStatus: "completed"
            )
            return try encoder.encode(deviceResponse)

        case .devDeviceRegistration:
            // Mock response for development device registration
            let response: [String: Any] = [
                "success": true,
                "deviceId": "mock-dev-device-\(UUID().uuidString)",
                "registeredAt": ISO8601DateFormatter().string(from: Date())
            ]
            return try JSONSerialization.data(withJSONObject: response)

        case .healthCheck:
            let response = HealthCheckResponse(
                status: .healthy,
                version: SDKConstants.version,
                timestamp: Date(),
            )
            return try encoder.encode(response)

        case .configuration:
            let config = ConfigurationData(
                id: "mock-config-\(UUID().uuidString)",
                apiKey: "dev-mode",
                source: .remote
            )
            return try encoder.encode(config)

        case .models:
            // Legacy endpoint - return mock models for backward compatibility
            let models = createMockModels()
            return try encoder.encode(models)

        case .modelAssignments(let deviceType, let platform):
            // Return mock model assignments response as a dictionary
            let models = createMockModels()
            let assignments = models.map { model in
                [
                    "id": model.id,
                    "name": model.name,
                    "version": "1.0.0",
                    "category": model.category.rawValue,
                    "format": model.format.rawValue,
                    "download_url": model.downloadURL?.absoluteString ?? "",
                    "size": model.downloadSize ?? 0,
                    "memory_required": model.memoryRequired ?? 0,
                    "context_length": model.contextLength ?? 0,
                    "supports_thinking": model.supportsThinking,
                    "compatible_frameworks": model.compatibleFrameworks.map { $0.rawValue },
                    "preferred_framework": model.preferredFramework?.rawValue ?? "",
                    "metadata": nil as Any?,
                    "is_required": false,
                    "priority": 1
                ] as [String : Any]
            }

            let response = [
                "models": assignments,
                "device_type": deviceType,
                "platform": platform,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ] as [String : Any]

            return try JSONSerialization.data(withJSONObject: response)

        case .deviceInfo:
            let deviceInfo = DeviceInfo(
                model: "iPhone15,1",
                osVersion: "iOS 17.0",
                architecture: "arm64e",
                totalMemory: 8_000_000_000,
                availableMemory: 4_000_000_000,
                hasNeuralEngine: true,
                gpuFamily: "Apple16"
            )

            // Just return the device info directly
            return try encoder.encode(deviceInfo)

        case .telemetry:
            // Return simple success response
            let response: [String: Any] = ["success": true, "message": "Telemetry received"]
            return try JSONSerialization.data(withJSONObject: response)

        case .generationHistory:
            // Return empty array for generation history
            let emptyHistory: [String] = []
            return try encoder.encode(emptyHistory)

        case .userPreferences:
            // Return basic preferences as dictionary
            let preferences: [String: Any] = [
                "preferOnDevice": true,
                "maxCostPerRequest": 0.01,
                "preferredModels": [] as [String]
            ]
            return try JSONSerialization.data(withJSONObject: preferences)

        case .devAnalytics:
            // Mock response for analytics submission
            let response: [String: Any] = [
                "success": true,
                "analyticsId": "mock-analytics-\(UUID().uuidString)"
            ]
            return try JSONSerialization.data(withJSONObject: response)
        }
    }

    private func createMockModels() -> [ModelInfo] {
        return [
            // Apple Foundation Models (iOS 18+)
            ModelInfo(
                id: "foundation-models-default",
                name: "Apple Foundation Model",
                category: .language,
                format: .mlmodel,
                downloadURL: nil, // Built-in, no download needed
                localPath: nil,
                downloadSize: 0, // Built-in
                memoryRequired: 500_000_000, // 500MB
                compatibleFrameworks: [.foundationModels],
                preferredFramework: .foundationModels,
                contextLength: 8192,
                supportsThinking: false
            ),

            // Llama-3.2 1B Q6_K
            ModelInfo(
                id: "llama-3.2-1b-instruct-q6-k",
                name: "Llama 3.2 1B Instruct Q6_K",
                category: .language,
                format: .gguf,
                downloadURL: URL(string: "https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q6_K.gguf"),
                localPath: nil,
                downloadSize: 1_100_000_000, // ~1.1GB
                memoryRequired: 1_200_000_000, // 1.2GB
                compatibleFrameworks: [.llamaCpp],
                preferredFramework: .llamaCpp,
                contextLength: 131072,
                supportsThinking: true
            ),

            // SmolLM2 1.7B Instruct Q6_K_L
            ModelInfo(
                id: "smollm2-1.7b-instruct-q6-k-l",
                name: "SmolLM2 1.7B Instruct Q6_K_L",
                category: .language,
                format: .gguf,
                downloadURL: URL(string: "https://huggingface.co/bartowski/SmolLM2-1.7B-Instruct-GGUF/resolve/main/SmolLM2-1.7B-Instruct-Q6_K_L.gguf"),
                localPath: nil,
                downloadSize: 1_700_000_000, // ~1.7GB
                memoryRequired: 1_800_000_000, // 1.8GB
                compatibleFrameworks: [.llamaCpp],
                preferredFramework: .llamaCpp,
                contextLength: 8192,
                supportsThinking: true
            ),

            // Qwen-2.5 0.5B Q6_K
            ModelInfo(
                id: "qwen-2.5-0.5b-instruct-q6-k",
                name: "Qwen 2.5 0.5B Instruct Q6_K",
                category: .language,
                format: .gguf,
                downloadURL: URL(string: "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf"),
                localPath: nil,
                downloadSize: 650_000_000, // ~650MB
                memoryRequired: 600_000_000, // 600MB
                compatibleFrameworks: [.llamaCpp],
                preferredFramework: .llamaCpp,
                contextLength: 32768,
                supportsThinking: true
            ),

            // SmolLM2 360M Q8_0
            ModelInfo(
                id: "smollm2-360m-q8-0",
                name: "SmolLM2 360M Q8_0",
                category: .language,
                format: .gguf,
                downloadURL: URL(string: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf"),
                localPath: nil,
                downloadSize: 385_000_000, // ~385MB
                memoryRequired: 500_000_000, // 500MB
                compatibleFrameworks: [.llamaCpp],
                preferredFramework: .llamaCpp,
                contextLength: 8192,
                supportsThinking: false
            ),

            // Qwen-2.5 1.5B Q6_K
            ModelInfo(
                id: "qwen-2.5-1.5b-instruct-q6-k",
                name: "Qwen 2.5 1.5B Instruct Q6_K",
                category: .language,
                format: .gguf,
                downloadURL: URL(string: "https://huggingface.co/ZeroWw/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/Qwen2.5-1.5B-Instruct.q6_k.gguf"),
                localPath: nil,
                downloadSize: 1_400_000_000, // ~1.4GB
                memoryRequired: 1_600_000_000, // 1.6GB
                compatibleFrameworks: [.llamaCpp],
                preferredFramework: .llamaCpp,
                contextLength: 32768,
                supportsThinking: true
            ),

            // MARK: - Voice Models (WhisperKit)

            // Whisper Tiny
            ModelInfo(
                id: "whisper-tiny",
                name: "Whisper Tiny",
                category: .speechRecognition,
                format: .mlmodel,
                downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-tiny.en"),
                localPath: nil,
                downloadSize: 39_000_000, // ~39MB
                memoryRequired: 39_000_000, // 39MB
                compatibleFrameworks: [.whisperKit],
                preferredFramework: .whisperKit,
                contextLength: 0,
                supportsThinking: false
            ),

            // Whisper Base
            ModelInfo(
                id: "whisper-base",
                name: "Whisper Base",
                category: .speechRecognition,
                format: .mlmodel,
                downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-base"),
                localPath: nil,
                downloadSize: 74_000_000, // ~74MB
                memoryRequired: 74_000_000, // 74MB
                compatibleFrameworks: [.whisperKit],
                preferredFramework: .whisperKit,
                contextLength: 0,
                supportsThinking: false
            ),

            // MARK: - LiquidAI Models

            // LiquidAI LFM2 350M Q4_K_M (Smallest, fastest)
            ModelInfo(
                id: "lfm2-350m-q4-k-m",
                name: "LiquidAI LFM2 350M Q4_K_M",
                category: .language,
                format: .gguf,
                downloadURL: URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf"),
                localPath: nil,
                downloadSize: 218_690_000, // ~219MB
                memoryRequired: 250_000_000, // 250MB
                compatibleFrameworks: [.llamaCpp],
                preferredFramework: .llamaCpp,
                contextLength: 32768,
                supportsThinking: false
            ),

            // LiquidAI LFM2 350M Q8_0 (Highest quality)
            ModelInfo(
                id: "lfm2-350m-q8-0",
                name: "LiquidAI LFM2 350M Q8_0",
                category: .language,
                format: .gguf,
                downloadURL: URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf"),
                localPath: nil,
                downloadSize: 361_650_000, // ~362MB
                memoryRequired: 400_000_000, // 400MB
                compatibleFrameworks: [.llamaCpp],
                preferredFramework: .llamaCpp,
                contextLength: 32768,
                supportsThinking: false
            )
        ]
    }
}
