import Foundation

/// Manager for unified tokenizer handling
public class UnifiedTokenizerManager {
    // MARK: - Properties
    
    /// Shared instance
    public static let shared: UnifiedTokenizerManager = UnifiedTokenizerManager()
    
    /// Cache of loaded tokenizers
    private var tokenizers: [String: UnifiedTokenizer] = [:]
    private let tokenizerLock: NSLock = NSLock()
    
    /// Registered tokenizer adapters by format
    private var adapters: [TokenizerFormat: TokenizerAdapter.Type] = [:]
    private let adapterLock: NSLock = NSLock()
    
    // MARK: - Initialization
    
    private init() {
        // SDK provides empty registry
        // Sample app will register concrete implementations
        // This allows SDK users to register their own tokenizer adapters
    }
    
    // MARK: - Public API
    
    /// Register a tokenizer adapter
    /// - Parameters:
    ///   - adapterType: The adapter type to register
    ///   - format: The format this adapter handles
    public func registerAdapter(_ adapterType: TokenizerAdapter.Type, for format: TokenizerFormat) {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        adapters[format] = adapterType
    }
    
    /// Register a pre-initialized tokenizer
    /// - Parameters:
    ///   - tokenizer: The tokenizer instance
    ///   - modelId: Model identifier
    public func registerTokenizer(_ tokenizer: UnifiedTokenizer, for modelId: String) {
        tokenizerLock.lock()
        defer { tokenizerLock.unlock() }
        tokenizers[modelId] = tokenizer
    }
    
    /// Get tokenizer for a model
    /// - Parameter model: Model information
    /// - Returns: Unified tokenizer instance
    public func getTokenizer(for model: ModelInfo) async throws -> UnifiedTokenizer {
        // Check cache first
        tokenizerLock.lock()
        if let cached = tokenizers[model.id] {
            tokenizerLock.unlock()
            return cached
        }
        tokenizerLock.unlock()
        
        // Auto-detect and create
        let format = try detectTokenizerFormat(for: model)
        let tokenizer = try await createTokenizer(format: format, model: model)
        
        // Cache for future use
        tokenizerLock.lock()
        tokenizers[model.id] = tokenizer
        tokenizerLock.unlock()
        
        return tokenizer
    }
    
    /// Remove tokenizer from cache
    /// - Parameter modelId: Model identifier
    public func removeTokenizer(for modelId: String) {
        tokenizerLock.lock()
        defer { tokenizerLock.unlock() }
        tokenizers.removeValue(forKey: modelId)
    }
    
    /// Clear all cached tokenizers
    public func clearCache() {
        tokenizerLock.lock()
        defer { tokenizerLock.unlock() }
        tokenizers.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func detectTokenizerFormat(for model: ModelInfo) throws -> TokenizerFormat {
        // Check model metadata first
        if let format = model.tokenizerFormat {
            return format
        }
        
        // Auto-detect based on model files
        if let modelPath = model.localPath {
            return try detectFormatFromFiles(at: modelPath)
        }
        
        // Framework-specific defaults
        return try defaultFormat(for: model.format)
    }
    
    private func detectFormatFromFiles(at path: URL) throws -> TokenizerFormat {
        let fileManager = FileManager.default
        
        // Check if path is a directory
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
            throw TokenizerError.formatNotDetected
        }
        
        let files: [URL]
        if isDirectory.boolValue {
            files = try fileManager.contentsOfDirectory(
                at: path,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } else {
            // Single file, check parent directory
            let parentDir = path.deletingLastPathComponent()
            files = try fileManager.contentsOfDirectory(
                at: parentDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        }
        
        // Check for specific tokenizer files
        for file in files {
            let filename = file.lastPathComponent.lowercased()
            
            if filename == "tokenizer.json" || filename == "tokenizer_config.json" {
                return .huggingFace
            } else if filename.contains("sentencepiece") || file.pathExtension == "model" {
                return .sentencePiece
            } else if filename == "vocab.txt" || filename == "vocab.json" {
                return .wordPiece
            } else if file.pathExtension == "bpe" || filename.contains("merges") {
                return .bpe
            }
        }
        
        throw TokenizerError.formatNotDetected
    }
    
    private func defaultFormat(for modelFormat: ModelFormat) throws -> TokenizerFormat {
        switch modelFormat {
        case .tflite:
            return .tflite
        case .mlmodel, .mlpackage:
            return .coreML
        case .onnx, .ort:
            return .wordPiece // Common for ONNX models
        case .safetensors, .bin, .weights:
            return .huggingFace // Common for transformer models
        case .gguf, .ggml:
            return .sentencePiece // Common for llama models
        default:
            throw TokenizerError.formatNotDetected
        }
    }
    
    private func createTokenizer(format: TokenizerFormat, model: ModelInfo) async throws -> UnifiedTokenizer {
        adapterLock.lock()
        guard let adapterType = adapters[format] else {
            adapterLock.unlock()
            throw TokenizerError.unsupportedFormat(format)
        }
        adapterLock.unlock()
        
        // Create tokenizer configuration
        let config = try createTokenizerConfig(for: model, format: format)
        
        // Initialize adapter
        let adapter = try adapterType.init(config: config)
        
        // Load tokenizer data
        if let modelPath = model.localPath {
            try await adapter.load(from: modelPath)
        }
        
        return adapter
    }
    
    private func createTokenizerConfig(for model: ModelInfo, format: TokenizerFormat) throws -> TokenizerConfig {
        guard let modelPath = model.localPath else {
            throw TokenizerError.loadingFailed("Model not downloaded")
        }
        
        // Detect vocab and config paths
        let vocabPath = findVocabFile(near: modelPath, format: format)
        let mergesPath = findMergesFile(near: modelPath, format: format)
        let configPath = findConfigFile(near: modelPath, format: format)
        
        return TokenizerConfig(
            modelPath: modelPath,
            vocabPath: vocabPath,
            mergesPath: mergesPath,
            configPath: configPath,
            format: format,
            maxLength: model.contextLength,
            paddingStrategy: .none,
            truncationStrategy: .longest
        )
    }
    
    private func findVocabFile(near path: URL, format: TokenizerFormat) -> URL? {
        let searchPaths = [
            path.deletingLastPathComponent(),
            path
        ]
        
        let vocabNames: [String] = {
            switch format {
            case .huggingFace:
                return ["vocab.json", "tokenizer.json"]
            case .sentencePiece:
                return ["tokenizer.model", "spiece.model"]
            case .wordPiece:
                return ["vocab.txt", "vocab.json"]
            case .bpe:
                return ["vocab.json", "encoder.json"]
            default:
                return ["vocab.txt", "vocab.json"]
            }
        }()
        
        for searchPath in searchPaths {
            for vocabName in vocabNames {
                let vocabURL = searchPath.appendingPathComponent(vocabName)
                if FileManager.default.fileExists(atPath: vocabURL.path) {
                    return vocabURL
                }
            }
        }
        
        return nil
    }
    
    private func findMergesFile(near path: URL, format: TokenizerFormat) -> URL? {
        guard format == .bpe else { return nil }
        
        let searchPaths = [
            path.deletingLastPathComponent(),
            path
        ]
        
        let mergeNames = ["merges.txt", "bpe.txt", "merges.bpe"]
        
        for searchPath in searchPaths {
            for mergeName in mergeNames {
                let mergeURL = searchPath.appendingPathComponent(mergeName)
                if FileManager.default.fileExists(atPath: mergeURL.path) {
                    return mergeURL
                }
            }
        }
        
        return nil
    }
    
    private func findConfigFile(near path: URL, format: TokenizerFormat) -> URL? {
        let searchPaths = [
            path.deletingLastPathComponent(),
            path
        ]
        
        let configNames = ["tokenizer_config.json", "config.json", "tokenizer.json"]
        
        for searchPath in searchPaths {
            for configName in configNames {
                let configURL = searchPath.appendingPathComponent(configName)
                if FileManager.default.fileExists(atPath: configURL.path) {
                    return configURL
                }
            }
        }
        
        return nil
    }
}

// MARK: - Extensions

public extension UnifiedTokenizerManager {
    /// Get available tokenizer formats
    var availableFormats: [TokenizerFormat] {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        return Array(adapters.keys)
    }
    
    /// Check if a format is supported
    /// - Parameter format: Tokenizer format
    /// - Returns: Whether the format has a registered adapter
    func isFormatSupported(_ format: TokenizerFormat) -> Bool {
        adapterLock.lock()
        defer { adapterLock.unlock() }
        return adapters[format] != nil
    }
    
    /// Get tokenizer statistics
    var statistics: TokenizerStatistics {
        tokenizerLock.lock()
        defer { tokenizerLock.unlock() }
        
        return TokenizerStatistics(
            cachedCount: tokenizers.count,
            formats: Set(tokenizers.values.compactMap { ($0 as? TokenizerAdapter)?.format }),
            totalMemoryUsage: estimateMemoryUsage()
        )
    }
    
    private func estimateMemoryUsage() -> Int64 {
        // Rough estimate: assume each tokenizer uses ~10MB for vocab
        Int64(tokenizers.count) * 10_000_000
    }
}

/// Tokenizer statistics
public struct TokenizerStatistics {
    public let cachedCount: Int
    public let formats: Set<TokenizerFormat>
    public let totalMemoryUsage: Int64
}

// MARK: - Default Tokenizer Implementation

/// Basic fallback tokenizer for when no adapter is available
public class BasicTokenizer: UnifiedTokenizer {
    private let separator: String
    private var vocab: [String: Int] = [:]
    private var reverseVocab: [Int: String] = [:]
    
    public init(separator: String = " ") {
        self.separator = separator
        buildBasicVocab()
    }
    
    public func encode(_ text: String) -> [Int] {
        let words = text.components(separatedBy: separator)
        return words.compactMap { vocab[$0] ?? vocab["<unk>"] }
    }
    
    public func decode(_ tokens: [Int]) -> String {
        let words = tokens.compactMap { reverseVocab[$0] }
        return words.joined(separator: separator)
    }
    
    public var vocabularySize: Int {
        vocab.count
    }
    
    public var maxSequenceLength: Int {
        2048
    }
    
    public var specialTokens: SpecialTokens {
        SpecialTokens(
            bosToken: vocab["<bos>"],
            eosToken: vocab["<eos>"],
            padToken: vocab["<pad>"],
            unkToken: vocab["<unk>"]
        )
    }
    
    public func encode(_ text: String, addSpecialTokens: Bool) -> [Int] {
        var tokens = encode(text)
        
        if addSpecialTokens {
            if let bosToken = specialTokens.bosToken {
                tokens.insert(bosToken, at: 0)
            }
            if let eosToken = specialTokens.eosToken {
                tokens.append(eosToken)
            }
        }
        
        return tokens
    }
    
    public func batchEncode(_ texts: [String]) -> [[Int]] {
        texts.map { encode($0) }
    }
    
    public func getToken(for word: String) -> Int? {
        vocab[word]
    }
    
    private func buildBasicVocab() {
        // Build a minimal vocabulary
        let specialTokens = ["<pad>", "<unk>", "<bos>", "<eos>"]
        for (index, token) in specialTokens.enumerated() {
            vocab[token] = index
            reverseVocab[index] = token
        }
        
        // Add common words (this would be loaded from file in real implementation)
        let commonWords = ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for"]
        for (index, word) in commonWords.enumerated() {
            let tokenId = specialTokens.count + index
            vocab[word] = tokenId
            reverseVocab[tokenId] = word
        }
    }
}
