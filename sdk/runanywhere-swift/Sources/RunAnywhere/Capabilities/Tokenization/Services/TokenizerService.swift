import Foundation

/// Central tokenizer service for managing tokenizer instances and operations
public class TokenizerService {
    private let adapterRegistry: AdapterRegistry
    private let tokenizerCache: TokenizerCache
    private let formatDetector: FormatDetector
    private let configurationBuilder: ConfigurationBuilder
    private let logger = SDKLogger(category: "TokenizerService")

    internal init(
        adapterRegistry: AdapterRegistry = AdapterRegistry(),
        tokenizerCache: TokenizerCache = TokenizerCache(),
        formatDetector: FormatDetector = FormatDetectorImpl(),
        configurationBuilder: ConfigurationBuilder = ConfigurationBuilder()
    ) {
        self.adapterRegistry = adapterRegistry
        self.tokenizerCache = tokenizerCache
        self.formatDetector = formatDetector
        self.configurationBuilder = configurationBuilder
    }

    // MARK: - Tokenizer Management

    func getTokenizer(for model: ModelInfo) async throws -> UnifiedTokenizer {
        // Check cache first
        if let cached = tokenizerCache.getTokenizer(for: model.id) {
            logger.debug("Retrieved tokenizer from cache for model: \(model.name)")
            return cached
        }

        logger.info("Creating new tokenizer for model: \(model.name)")

        // Detect tokenizer format
        guard let modelPath = model.localPath else {
            throw TokenizerError.modelNotFound(model.id)
        }

        guard let format = formatDetector.detectFormat(at: modelPath) else {
            throw TokenizerError.unsupportedFormat(model.format?.rawValue ?? "unknown")
        }
        logger.debug("Detected tokenizer format: \(format) for model: \(model.name)")

        // Get appropriate adapter
        guard let adapterType = adapterRegistry.getAdapter(for: format) else {
            throw TokenizerError.unsupportedFormat(format)
        }

        // Build configuration
        let config = try configurationBuilder.buildConfiguration(for: model, format: format)

        // Create and initialize tokenizer
        let adapter = try adapterType.init(config: config)

        // Load tokenizer data if model is local
        if let modelPath = model.localPath {
            try await adapter.load(from: modelPath)
        }

        // Cache the tokenizer
        tokenizerCache.setTokenizer(adapter, for: model.id)

        logger.info("Successfully created and cached tokenizer for model: \(model.name)")
        return adapter
    }

    func registerTokenizer(_ tokenizer: UnifiedTokenizer, for modelId: String) {
        tokenizerCache.setTokenizer(tokenizer, for: modelId)
        logger.info("Registered pre-initialized tokenizer for model: \(modelId)")
    }

    func removeTokenizer(for modelId: String) {
        tokenizerCache.removeTokenizer(for: modelId)
        logger.debug("Removed tokenizer from cache for model: \(modelId)")
    }

    func clearAllTokenizers() {
        tokenizerCache.clearAll()
        logger.info("Cleared all cached tokenizers")
    }

    // MARK: - Adapter Management

    func registerAdapter(_ adapterType: TokenizerAdapter.Type, for format: TokenizerFormat) {
        adapterRegistry.registerAdapter(adapterType, for: format)
        logger.info("Registered adapter for format: \(format)")
    }

    func getAvailableFormats() -> [TokenizerFormat] {
        return adapterRegistry.getAvailableFormats()
    }

    func isFormatSupported(_ format: TokenizerFormat) -> Bool {
        return adapterRegistry.isFormatSupported(format)
    }

    // MARK: - Batch Operations

    func getTokenizers(for models: [ModelInfo]) async throws -> [String: UnifiedTokenizer] {
        var tokenizers: [String: UnifiedTokenizer] = [:]

        for model in models {
            do {
                let tokenizer = try await getTokenizer(for: model)
                tokenizers[model.id] = tokenizer
            } catch {
                logger.error("Failed to get tokenizer for model \(model.name): \(error)")
                throw error
            }
        }

        return tokenizers
    }

    func preloadTokenizers(for models: [ModelInfo]) async {
        logger.info("Preloading tokenizers for \(models.count) models")

        for model in models {
            do {
                _ = try await getTokenizer(for: model)
            } catch {
                logger.warning("Failed to preload tokenizer for model \(model.name): \(error)")
            }
        }

        logger.info("Completed tokenizer preloading")
    }

    // MARK: - Statistics and Monitoring

    func getStatistics() -> TokenizerStatistics {
        let cacheStats = tokenizerCache.getStatistics()
        let registryStats = adapterRegistry.getStatistics()

        return TokenizerStatistics(
            cachedCount: cacheStats.count,
            formats: Set(registryStats.supportedFormats),
            totalMemoryUsage: cacheStats.estimatedMemoryUsage,
            hitRate: cacheStats.hitRate,
            supportedAdapters: registryStats.adapterCount
        )
    }

    func validateTokenizer(for model: ModelInfo) async throws -> TokenizerValidationResult {
        do {
            let tokenizer = try await getTokenizer(for: model)

            // Perform basic validation
            let testText = "Hello, world!"
            let encoded = tokenizer.encode(testText)
            let decoded = tokenizer.decode(encoded)

            let isValid = !encoded.isEmpty && !decoded.isEmpty

            return TokenizerValidationResult(
                isValid: isValid,
                format: (tokenizer as? TokenizerAdapter)?.format,
                vocabularySize: tokenizer.vocabularySize,
                maxSequenceLength: tokenizer.maxSequenceLength,
                testEncoding: encoded,
                testDecoding: decoded,
                errors: []
            )

        } catch {
            return TokenizerValidationResult(
                isValid: false,
                format: nil,
                vocabularySize: 0,
                maxSequenceLength: 0,
                testEncoding: [],
                testDecoding: "",
                errors: [error.localizedDescription]
            )
        }
    }

    // MARK: - Cleanup and Memory Management

    func performMaintenance() {
        logger.info("Performing tokenizer service maintenance")

        tokenizerCache.performCleanup()

        // Log statistics
        let stats = getStatistics()
        logger.info("Maintenance complete - Cached: \(stats.cachedCount), Memory: \(ByteCountFormatter.string(fromByteCount: stats.totalMemoryUsage, countStyle: .memory))")
    }

    func evictLeastUsedTokenizers(count: Int) {
        tokenizerCache.evictLeastUsed(count: count)
        logger.info("Evicted \(count) least used tokenizers")
    }

    // MARK: - Health Check

    /// Check if the tokenizer service is healthy and operational
    func isHealthy() -> Bool {
        // Basic health check - ensure essential components are available
        return true // Simple implementation for now
    }
}

/// Statistics about tokenizer service usage
struct TokenizerStatistics {
    let cachedCount: Int
    let formats: Set<TokenizerFormat>
    let totalMemoryUsage: Int64
    let hitRate: Double
    let supportedAdapters: Int

    var memoryUsageString: String {
        ByteCountFormatter.string(fromByteCount: totalMemoryUsage, countStyle: .memory)
    }

    var hitRatePercentage: String {
        String(format: "%.1f%%", hitRate * 100)
    }
}

/// Result of tokenizer validation
struct TokenizerValidationResult {
    let isValid: Bool
    let format: TokenizerFormat?
    let vocabularySize: Int
    let maxSequenceLength: Int
    let testEncoding: [Int]
    let testDecoding: String
    let errors: [String]

    var hasErrors: Bool {
        !errors.isEmpty
    }

    // MARK: - Health Check

    /// Check if the tokenizer service is healthy and operational
    public func isHealthy() -> Bool {
        // Basic health check - ensure essential components are available
        return !hasErrors
    }
}
