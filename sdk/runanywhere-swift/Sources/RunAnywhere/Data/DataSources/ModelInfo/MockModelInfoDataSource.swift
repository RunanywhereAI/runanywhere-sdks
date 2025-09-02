import Foundation

/// Mock data source for model information during development
/// Only used when environment is in debug mode
public actor MockModelInfoDataSource: RemoteDataSource {
    public typealias Entity = ModelInfo

    private let logger = SDKLogger(category: "MockModelInfoDataSource")
    private let operationHelper = RemoteOperationHelper(timeout: 1.0) // Faster for mock data

    // MARK: - Mock Data for Development

    /// Predefined models that will be returned from the mock data source
    private let mockModels: [ModelInfo] = [
        // Apple Foundation Models (iOS 26+)
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

        // Qwen3 600M Q8_0
        ModelInfo(
            id: "qwen3-600m-instruct-q8-0",
            name: "Qwen3 600M Instruct Q8_0",
            category: .language,
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/Cactus-Compute/Qwen3-600m-Instruct-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf"),
            localPath: nil,
            downloadSize: 656_000_000, // ~656MB
            memoryRequired: 800_000_000, // 800MB
            compatibleFrameworks: [.llamaCpp],
            preferredFramework: .llamaCpp,
            contextLength: 32768,
            supportsThinking: true
        ),

        // MARK: - Voice Models (WhisperKit)
        // Note: URLs provide the base path for the custom download strategy to extract model info

        // Whisper Tiny
        ModelInfo(
            id: "whisper-tiny",
            name: "Whisper Tiny",
            category: .speechRecognition,
            format: .mlmodel,
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-tiny.en"), // Base URL for strategy
            localPath: nil,
            downloadSize: 39_000_000, // ~39MB
            memoryRequired: 39_000_000, // 39MB
            compatibleFrameworks: [.whisperKit],
            preferredFramework: .whisperKit,
            contextLength: 0, // Not applicable for voice models
            supportsThinking: false
        ),

        // Whisper Base
        ModelInfo(
            id: "whisper-base",
            name: "Whisper Base",
            category: .speechRecognition,
            format: .mlmodel,
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-base"), // Base URL for strategy
            localPath: nil,
            downloadSize: 74_000_000, // ~74MB
            memoryRequired: 74_000_000, // 74MB
            compatibleFrameworks: [.whisperKit],
            preferredFramework: .whisperKit,
            contextLength: 0, // Not applicable for voice models
            supportsThinking: false
        ),

        // Whisper Small
        ModelInfo(
            id: "whisper-small",
            name: "Whisper Small",
            category: .speechRecognition,
            format: .mlmodel,
            downloadURL: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-small"), // Base URL for strategy
            localPath: nil,
            downloadSize: 244_000_000, // ~244MB
            memoryRequired: 244_000_000, // 244MB
            compatibleFrameworks: [.whisperKit],
            preferredFramework: .whisperKit,
            contextLength: 0, // Not applicable for voice models
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

        // LiquidAI LFM2 350M Q6_K (Best balance)
        ModelInfo(
            id: "lfm2-350m-q6-k",
            name: "LiquidAI LFM2 350M Q6_K",
            category: .language,
            format: .gguf,
            downloadURL: URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q6_K.gguf"),
            localPath: nil,
            downloadSize: 279_790_000, // ~280MB
            memoryRequired: 350_000_000, // 350MB
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

    public init() {
        logger.info("MockModelInfoDataSource initialized with \(mockModels.count) models")
    }

    // MARK: - DataSource Protocol

    public func isAvailable() async -> Bool {
        let environment = RunAnywhere._currentEnvironment ?? .production
        return environment == .development
    }

    public func validateConfiguration() async throws {
        let environment = RunAnywhere._currentEnvironment ?? .production
        guard environment == .development else {
            throw DataSourceError.networkUnavailable
        }
    }

    // MARK: - RemoteDataSource Protocol

    public func fetch(id: String) async throws -> ModelInfo? {
        let environment = RunAnywhere._currentEnvironment ?? .production
        guard environment == .development else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Fetching mock model: \(id)")

        return try await operationHelper.withTimeout {
            let model = self.mockModels.first { $0.id == id }
            self.logger.debug("Mock model \(id): \(model != nil ? "found" : "not found")")
            return model
        }
    }

    public func fetchAll(filter: [String: Any]? = nil) async throws -> [ModelInfo] {
        let environment = RunAnywhere._currentEnvironment ?? .production
        guard environment == .development else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Fetching all mock models")

        return try await operationHelper.withTimeout {
            self.logger.debug("Returning \(self.mockModels.count) mock models")
            return self.mockModels
        }
    }

    public func save(_ entity: ModelInfo) async throws -> ModelInfo {
        let environment = RunAnywhere._currentEnvironment ?? .production
        guard environment == .development else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Mock save for model: \(entity.id)")

        return try await operationHelper.withTimeout {
            // Mock save - just return the entity as-is
            return entity
        }
    }

    public func delete(id: String) async throws {
        let environment = RunAnywhere._currentEnvironment ?? .production
        guard environment == .development else {
            throw DataSourceError.networkUnavailable
        }

        logger.debug("Mock delete for model: \(id)")

        try await operationHelper.withTimeout {
            // Mock delete - no-op
        }
    }

    // MARK: - Sync Support

    public func syncBatch(_ batch: [ModelInfo]) async throws -> [String] {
        // Mock implementation - just return all IDs as successfully synced
        logger.debug("Mock sync for \(batch.count) model info items")
        return batch.map { $0.id }
    }

    public func testConnection() async throws -> Bool {
        let environment = RunAnywhere._currentEnvironment ?? .production
        guard environment == .development else {
            return false
        }

        return try await operationHelper.withTimeout {
            self.logger.debug("Mock connection test - always successful in debug")
            return true
        }
    }
}
