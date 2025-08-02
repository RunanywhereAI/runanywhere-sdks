import Foundation

/// Builds tokenizer configurations based on model information and format
class ConfigurationBuilder {
    private let logger = SDKLogger(category: "ConfigurationBuilder")

    // Default configuration values
    private struct Defaults {
        static let maxLength = 2048
        static let paddingStrategy = TokenizerConfig.PaddingStrategy.none
        static let truncationStrategy = TokenizerConfig.TruncationStrategy.longest
    }

    func buildConfiguration(for model: ModelInfo, format: TokenizerFormat) throws -> TokenizerConfig {
        logger.debug("Building tokenizer configuration for model: \(model.name), format: \(format)")

        guard let modelPath = model.localPath else {
            throw TokenizerError.loadingFailed("Model not downloaded")
        }

        let fileLocator = TokenizerFileLocator(basePath: modelPath)

        // Find required files for the format
        let vocabPath = try findVocabFile(for: format, using: fileLocator)
        let mergesPath = findMergesFile(for: format, using: fileLocator)
        let configPath = findConfigFile(for: format, using: fileLocator)

        // Determine sequence length
        let maxLength = determineMaxLength(for: model, format: format, configPath: configPath)

        // Build configuration
        let config = TokenizerConfig(
            modelPath: modelPath,
            vocabPath: vocabPath,
            mergesPath: mergesPath,
            configPath: configPath,
            format: format,
            maxLength: maxLength,
            paddingStrategy: determinePaddingStrategy(for: format),
            truncationStrategy: determineTruncationStrategy(for: format),
            addSpecialTokens: shouldAddSpecialTokens(for: format),
            lowercaseInput: shouldLowercaseInput(for: format),
            stripAccents: shouldStripAccents(for: format),
            customTokens: extractCustomTokens(for: model, format: format),
            modelSpecificSettings: buildModelSpecificSettings(for: model, format: format)
        )

        logger.debug("Built configuration with vocab: \(vocabPath?.lastPathComponent ?? "none"), config: \(configPath?.lastPathComponent ?? "none")")

        return config
    }

    func buildDefaultConfiguration(for format: TokenizerFormat) -> TokenizerConfig {
        return TokenizerConfig(
            modelPath: URL(fileURLWithPath: ""),
            vocabPath: nil,
            mergesPath: nil,
            configPath: nil,
            format: format,
            maxLength: Defaults.maxLength,
            paddingStrategy: Defaults.paddingStrategy,
            truncationStrategy: Defaults.truncationStrategy
        )
    }

    func validateConfiguration(_ config: TokenizerConfig) throws {
        // Validate required files exist
        if let vocabPath = config.vocabPath {
            guard FileManager.default.fileExists(atPath: vocabPath.path) else {
                throw TokenizerError.configurationInvalid("Vocabulary file not found: \(vocabPath.path)")
            }
        }

        if let mergesPath = config.mergesPath {
            guard FileManager.default.fileExists(atPath: mergesPath.path) else {
                throw TokenizerError.configurationInvalid("Merges file not found: \(mergesPath.path)")
            }
        }

        if let configPath = config.configPath {
            guard FileManager.default.fileExists(atPath: configPath.path) else {
                throw TokenizerError.configurationInvalid("Config file not found: \(configPath.path)")
            }
        }

        // Validate sequence length
        guard config.maxLength > 0 && config.maxLength <= 1_000_000 else {
            throw TokenizerError.configurationInvalid("Invalid max length: \(config.maxLength)")
        }

        // Format-specific validation
        try validateFormatSpecificRequirements(config)
    }

    // MARK: - File Location

    private func findVocabFile(for format: TokenizerFormat, using locator: TokenizerFileLocator) throws -> URL? {
        let vocabNames = getVocabFileNames(for: format)

        for name in vocabNames {
            if let url = locator.findFile(named: name) {
                logger.debug("Found vocab file: \(url.lastPathComponent)")
                return url
            }
        }

        // Some formats require vocab files
        if requiresVocabFile(format) {
            throw TokenizerError.configurationInvalid("Required vocabulary file not found for format: \(format)")
        }

        return nil
    }

    private func findMergesFile(for format: TokenizerFormat, using locator: TokenizerFileLocator) -> URL? {
        guard format == .bpe else { return nil }

        let mergeNames = ["merges.txt", "merges.bpe", "bpe.txt"]

        for name in mergeNames {
            if let url = locator.findFile(named: name) {
                logger.debug("Found merges file: \(url.lastPathComponent)")
                return url
            }
        }

        return nil
    }

    private func findConfigFile(for format: TokenizerFormat, using locator: TokenizerFileLocator) -> URL? {
        let configNames = getConfigFileNames(for: format)

        for name in configNames {
            if let url = locator.findFile(named: name) {
                logger.debug("Found config file: \(url.lastPathComponent)")
                return url
            }
        }

        return nil
    }

    // MARK: - Configuration Parameters

    private func determineMaxLength(for model: ModelInfo, format: TokenizerFormat, configPath: URL?) -> Int {
        // 1. Use model's context length if available
        if let contextLength = model.contextLength, contextLength > 0 {
            return contextLength
        }

        // 2. Try to read from config file
        if let configPath = configPath,
           let maxLength = readMaxLengthFromConfig(at: configPath) {
            return maxLength
        }

        // 3. Use format-specific defaults
        switch format {
        case .huggingFace:
            return 512 // Common for BERT-like models
        case .sentencePiece:
            return 2048 // Common for LLaMA-like models
        case .wordPiece:
            return 512 // Common for BERT-like models
        case .bpe:
            return 1024 // Common for GPT-like models
        case .coreML:
            return 1024
        case .tflite:
            return 256 // More constrained for mobile
        case .custom:
            return Defaults.maxLength
        }
    }

    private func determinePaddingStrategy(for format: TokenizerFormat) -> TokenizerConfig.PaddingStrategy {
        switch format {
        case .wordPiece, .tflite:
            return .right // Common for BERT-like models
        case .bpe, .sentencePiece:
            return .none // Common for generative models
        default:
            return Defaults.paddingStrategy
        }
    }

    private func determineTruncationStrategy(for format: TokenizerFormat) -> TokenizerConfig.TruncationStrategy {
        switch format {
        case .wordPiece, .tflite:
            return .longest // Keep as much content as possible
        case .bpe, .sentencePiece:
            return .right // Truncate from the end
        default:
            return Defaults.truncationStrategy
        }
    }

    private func shouldAddSpecialTokens(for format: TokenizerFormat) -> Bool {
        switch format {
        case .huggingFace, .wordPiece, .bpe:
            return true
        case .sentencePiece:
            return false // SentencePiece handles this internally
        case .coreML, .tflite:
            return false // Usually pre-processed
        case .custom:
            return false
        }
    }

    private func shouldLowercaseInput(for format: TokenizerFormat) -> Bool {
        // This would typically be read from config files
        // For now, use conservative defaults
        return false
    }

    private func shouldStripAccents(for format: TokenizerFormat) -> Bool {
        // This would typically be read from config files
        return false
    }

    // MARK: - Helper Methods

    private func getVocabFileNames(for format: TokenizerFormat) -> [String] {
        switch format {
        case .huggingFace:
            return ["vocab.json", "tokenizer.json"]
        case .sentencePiece:
            return ["tokenizer.model", "spiece.model", "sentencepiece.model"]
        case .wordPiece:
            return ["vocab.txt", "vocab.json"]
        case .bpe:
            return ["vocab.json", "encoder.json"]
        case .coreML:
            return ["vocab.plist", "vocabulary.plist"]
        case .tflite:
            return ["vocab.txt", "labels.txt"]
        case .custom:
            return []
        }
    }

    private func getConfigFileNames(for format: TokenizerFormat) -> [String] {
        switch format {
        case .huggingFace:
            return ["tokenizer_config.json", "tokenizer.json", "config.json"]
        case .sentencePiece:
            return ["tokenizer_config.json", "config.json"]
        case .wordPiece:
            return ["tokenizer_config.json", "config.json"]
        case .bpe:
            return ["tokenizer_config.json", "config.json"]
        case .coreML:
            return ["config.plist", "tokenizer_config.plist"]
        case .tflite:
            return ["config.json"]
        case .custom:
            return []
        }
    }

    private func requiresVocabFile(_ format: TokenizerFormat) -> Bool {
        switch format {
        case .wordPiece, .bpe, .tflite:
            return true
        default:
            return false
        }
    }

    private func readMaxLengthFromConfig(at path: URL) -> Int? {
        do {
            let data = try Data(contentsOf: path)

            if path.pathExtension == "json" {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Try common field names
                    for key in ["max_position_embeddings", "max_length", "model_max_length", "max_seq_length"] {
                        if let maxLength = json[key] as? Int {
                            return maxLength
                        }
                    }
                }
            }

        } catch {
            logger.warning("Failed to read config file \(path.lastPathComponent): \(error)")
        }

        return nil
    }

    private func extractCustomTokens(for model: ModelInfo, format: TokenizerFormat) -> [String: Int] {
        // This would extract custom tokens from model metadata
        return [:]
    }

    private func buildModelSpecificSettings(for model: ModelInfo, format: TokenizerFormat) -> [String: Any] {
        var settings: [String: Any] = [:]

        // Add model-specific settings based on model type
        if let metadata = model.metadata {
            settings["model_type"] = metadata.description
        }

        settings["model_format"] = model.format.rawValue
        settings["tokenizer_format"] = format.rawValue

        return settings
    }

    private func validateFormatSpecificRequirements(_ config: TokenizerConfig) throws {
        switch config.format {
        case .bpe:
            guard config.vocabPath != nil else {
                throw TokenizerError.configurationInvalid("BPE format requires vocabulary file")
            }

        case .sentencePiece:
            guard config.vocabPath != nil else {
                throw TokenizerError.configurationInvalid("SentencePiece format requires model file")
            }

        case .wordPiece:
            guard config.vocabPath != nil else {
                throw TokenizerError.configurationInvalid("WordPiece format requires vocabulary file")
            }

        default:
            break
        }
    }
}

// MARK: - File Locator Helper

private class TokenizerFileLocator {
    private let basePath: URL

    init(basePath: URL) {
        self.basePath = basePath
    }

    func findFile(named name: String) -> URL? {
        // Search in multiple locations
        let searchPaths = [
            basePath,
            basePath.appendingPathComponent("tokenizer"),
            basePath.deletingLastPathComponent()
        ]

        for searchPath in searchPaths {
            let filePath = searchPath.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: filePath.path) {
                return filePath
            }
        }

        return nil
    }
}
