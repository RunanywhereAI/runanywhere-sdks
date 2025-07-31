import Foundation

/// Protocol for unified tokenizer interface
public protocol UnifiedTokenizer {
    /// Encode text into tokens
    /// - Parameter text: The text to encode
    /// - Returns: Array of token IDs
    func encode(_ text: String) -> [Int]

    /// Decode tokens back to text
    /// - Parameter tokens: The token IDs to decode
    /// - Returns: The decoded text
    func decode(_ tokens: [Int]) -> String

    /// The size of the vocabulary
    var vocabularySize: Int { get }

    /// Maximum sequence length supported
    var maxSequenceLength: Int { get }

    /// Special tokens used by the tokenizer
    var specialTokens: SpecialTokens { get }

    /// Encode text with special tokens
    /// - Parameters:
    ///   - text: The text to encode
    ///   - addSpecialTokens: Whether to add special tokens
    /// - Returns: Array of token IDs
    func encode(_ text: String, addSpecialTokens: Bool) -> [Int]

    /// Batch encode multiple texts
    /// - Parameter texts: Array of texts to encode
    /// - Returns: Array of token arrays
    func batchEncode(_ texts: [String]) -> [[Int]]

    /// Get token for a specific word
    /// - Parameter word: The word to look up
    /// - Returns: Token ID if found, nil otherwise
    func getToken(for word: String) -> Int?
}

/// Special tokens used by tokenizers
public struct SpecialTokens {
    public let bosToken: Int?  // Beginning of sequence
    public let eosToken: Int?  // End of sequence
    public let padToken: Int?  // Padding
    public let unkToken: Int?  // Unknown
    public let sepToken: Int?  // Separator
    public let clsToken: Int?  // Classification
    public let maskToken: Int? // Mask

    public init(
        bosToken: Int? = nil,
        eosToken: Int? = nil,
        padToken: Int? = nil,
        unkToken: Int? = nil,
        sepToken: Int? = nil,
        clsToken: Int? = nil,
        maskToken: Int? = nil
    ) {
        self.bosToken = bosToken
        self.eosToken = eosToken
        self.padToken = padToken
        self.unkToken = unkToken
        self.sepToken = sepToken
        self.clsToken = clsToken
        self.maskToken = maskToken
    }
}

/// Tokenizer formats supported
public enum TokenizerFormat: String, CaseIterable {
    case huggingFace = "huggingface"
    case sentencePiece = "sentencepiece"
    case wordPiece = "wordpiece"
    case bpe = "bpe"
    case tflite = "tflite"
    case coreML = "coreml"
    case custom = "custom"
}

/// Protocol for tokenizer adapters
public protocol TokenizerAdapter: UnifiedTokenizer {
    /// The format this adapter handles
    var format: TokenizerFormat { get }

    /// Initialize with model-specific configuration
    /// - Parameter config: Configuration for the tokenizer
    init(config: TokenizerConfig) throws

    /// Load tokenizer from file
    /// - Parameter path: Path to tokenizer file
    func load(from path: URL) async throws
}

/// Configuration for tokenizers
public struct TokenizerConfig {
    public let modelPath: URL
    public let vocabPath: URL?
    public let mergesPath: URL?
    public let configPath: URL?
    public let format: TokenizerFormat
    public let maxLength: Int
    public let paddingStrategy: PaddingStrategy
    public let truncationStrategy: TruncationStrategy

    public enum PaddingStrategy {
        case none
        case longest
        case maxLength
    }

    public enum TruncationStrategy {
        case none
        case longest
        case onlyFirst
        case onlySecond
    }

    public init(
        modelPath: URL,
        vocabPath: URL? = nil,
        mergesPath: URL? = nil,
        configPath: URL? = nil,
        format: TokenizerFormat,
        maxLength: Int = 512,
        paddingStrategy: PaddingStrategy = .none,
        truncationStrategy: TruncationStrategy = .longest
    ) {
        self.modelPath = modelPath
        self.vocabPath = vocabPath
        self.mergesPath = mergesPath
        self.configPath = configPath
        self.format = format
        self.maxLength = maxLength
        self.paddingStrategy = paddingStrategy
        self.truncationStrategy = truncationStrategy
    }
}

/// Errors related to tokenization
public enum TokenizerError: LocalizedError {
    case formatNotDetected
    case unsupportedFormat(TokenizerFormat)
    case loadingFailed(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case vocabNotLoaded
    case invalidToken(Int)

    public var errorDescription: String? {
        switch self {
        case .formatNotDetected:
            return "Could not detect tokenizer format"
        case .unsupportedFormat(let format):
            return "Unsupported tokenizer format: \(format.rawValue)"
        case .loadingFailed(let reason):
            return "Failed to load tokenizer: \(reason)"
        case .encodingFailed(let reason):
            return "Encoding failed: \(reason)"
        case .decodingFailed(let reason):
            return "Decoding failed: \(reason)"
        case .vocabNotLoaded:
            return "Vocabulary not loaded"
        case .invalidToken(let token):
            return "Invalid token ID: \(token)"
        }
    }
}
