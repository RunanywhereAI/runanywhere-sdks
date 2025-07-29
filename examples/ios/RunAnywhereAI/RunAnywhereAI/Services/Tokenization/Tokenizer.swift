import Foundation

// MARK: - Tokenizer Protocol

protocol Tokenizer {
    func encode(_ text: String) -> [Int]
    func decode(_ tokens: [Int]) -> String
    var vocabularySize: Int { get }
    var eosToken: Int { get }
    var bosToken: Int { get }
    var padToken: Int { get }
}

// MARK: - Base Tokenizer Implementation

class BaseTokenizer: Tokenizer {
    var vocabulary: [String: Int] = [:]
    var reverseVocabulary: [Int: String] = [:]

    var vocabularySize: Int { vocabulary.count }
    var eosToken: Int { vocabulary["</s>"] ?? 0 }
    var bosToken: Int { vocabulary["<s>"] ?? 1 }
    var padToken: Int { vocabulary["<pad>"] ?? 2 }

    init() {
        // Initialize with special tokens
        addSpecialTokens()
    }

    private func addSpecialTokens() {
        let specialTokens = [
            "</s>",   // End of sequence
            "<s>",    // Beginning of sequence
            "<pad>",  // Padding
            "<unk>",  // Unknown token
            "<mask>"  // Mask token
        ]

        for (index, token) in specialTokens.enumerated() {
            vocabulary[token] = index
            reverseVocabulary[index] = token
        }
    }

    func encode(_ text: String) -> [Int] {
        // Basic whitespace tokenization as fallback
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        var tokens: [Int] = [bosToken]

        for word in words where !word.isEmpty {
            if let tokenId = vocabulary[word] {
                tokens.append(tokenId)
            } else {
                // Unknown token
                tokens.append(vocabulary["<unk>"] ?? 3)
            }
        }

        tokens.append(eosToken)
        return tokens
    }

    func decode(_ tokens: [Int]) -> String {
        var words: [String] = []

        for token in tokens {
            // Skip special tokens in decoding
            if token == bosToken || token == eosToken || token == padToken {
                continue
            }

            if let word = reverseVocabulary[token] {
                words.append(word)
            }
        }

        return words.joined(separator: " ")
    }
}

// MARK: - BPE Tokenizer (Legacy - Use GenericBPETokenizer instead)

class BPETokenizer: BaseTokenizer {
    var merges: [(String, String)] = []
    var vocab: [String: Int] = [:]

    override init() {
        super.init()
    }

    init(vocabPath: String, mergesPath: String) throws {
        super.init()
        try loadVocabulary(from: vocabPath)
        try loadMerges(from: mergesPath)
    }

    private func loadVocabulary(from path: String) throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        
        if let vocabDict = json as? [String: Int] {
            // Direct vocab.json format (GPT-2 style)
            vocab = vocabDict
            vocabulary = vocabDict
            for (token, id) in vocabDict {
                reverseVocabulary[id] = token
            }
        } else if let lines = String(data: data, encoding: .utf8)?.components(separatedBy: .newlines) {
            // Fallback to line-by-line format
            for (index, token) in lines.enumerated() {
                if !token.isEmpty {
                    vocab[token] = index
                    vocabulary[token] = index
                    reverseVocabulary[index] = token
                }
            }
        }
    }

    private func loadMerges(from path: String) throws {
        let data = try String(contentsOfFile: path, encoding: .utf8)
        let lines = data.components(separatedBy: .newlines)

        for line in lines.dropFirst() { // Skip header
            let parts = line.components(separatedBy: " ")
            if parts.count == 2 {
                merges.append((parts[0], parts[1]))
            }
        }
    }

    override func encode(_ text: String) -> [Int] {
        // Simple BPE encoding - model-specific logic should be in adapters
        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        let bpeTokens = applyBPE(tokens)
        
        var tokenIds: [Int] = []
        for token in bpeTokens {
            if let id = vocab[token] {
                tokenIds.append(id)
            } else {
                tokenIds.append(vocabulary["<unk>"] ?? 3)
            }
        }
        
        return tokenIds
    }

    private func applyBPE(_ tokens: [String]) -> [String] {
        var result = tokens

        for (first, second) in merges {
            var i = 0
            while i < result.count - 1 {
                if result[i] == first && result[i + 1] == second {
                    result[i] = first + second
                    result.remove(at: i + 1)
                } else {
                    i += 1
                }
            }
        }

        return result
    }
    
    override func decode(_ tokens: [Int]) -> String {
        // Simple BPE decoding - model-specific logic should be in adapters
        var decodedPieces: [String] = []
        
        for token in tokens {
            if let tokenStr = reverseVocabulary[token] {
                decodedPieces.append(tokenStr)
            }
        }
        
        return decodedPieces.joined(separator: " ")
    }
}

// MARK: - SentencePiece Tokenizer

class SentencePieceTokenizer: BaseTokenizer {
    private var pieces: [String: Int] = [:]
    private var scores: [Float] = []

    init(modelPath: String) throws {
        super.init()
        try loadModel(from: modelPath)
    }

    private func loadModel(from path: String) throws {
        // Load SentencePiece model
        // This is a simplified version - real implementation would parse the protobuf format
        let data = try Data(contentsOf: URL(fileURLWithPath: path))

        // Parse model file (simplified)
        // In reality, this would parse the SentencePiece protobuf format
    }

    override func encode(_ text: String) -> [Int] {
        // Simplified SentencePiece encoding
        var tokens: [Int] = [bosToken]

        // Apply SentencePiece algorithm
        let processed = preprocessText(text)
        let subwords = encodeAsPieces(processed)

        for subword in subwords {
            if let id = pieces[subword] {
                tokens.append(id)
            } else {
                tokens.append(vocabulary["<unk>"] ?? 3)
            }
        }

        tokens.append(eosToken)
        return tokens
    }

    private func preprocessText(_ text: String) -> String {
        // Replace spaces with special character
        text.replacingOccurrences(of: " ", with: "▁")
    }

    private func encodeAsPieces(_ text: String) -> [String] {
        // Simplified piece extraction
        var pieces: [String] = []
        var current = ""

        for char in text {
            current += String(char)
            if self.pieces[current] != nil {
                pieces.append(current)
                current = ""
            }
        }

        if !current.isEmpty {
            pieces.append(current)
        }

        return pieces
    }
}

// MARK: - WordPiece Tokenizer

class WordPieceTokenizer: BaseTokenizer {
    internal var wordPieces: [String: Int] = [:]
    private let maxInputCharsPerWord = 100
    private let unkToken = "[UNK]"

    init(vocabPath: String) throws {
        super.init()
        try loadVocabulary(from: vocabPath)
    }

    private func loadVocabulary(from path: String) throws {
        let data = try String(contentsOfFile: path, encoding: .utf8)
        let lines = data.components(separatedBy: .newlines)

        for (index, token) in lines.enumerated() {
            wordPieces[token] = index
        }
    }

    override func encode(_ text: String) -> [Int] {
        var outputTokens: [Int] = [bosToken]

        let words = basicTokenize(text)

        for word in words {
            if word.count > maxInputCharsPerWord {
                outputTokens.append(wordPieces[unkToken] ?? 3)
                continue
            }

            let subTokens = wordPieceTokenize(word)
            outputTokens.append(contentsOf: subTokens)
        }

        outputTokens.append(eosToken)
        return outputTokens
    }

    private func basicTokenize(_ text: String) -> [String] {
        // Basic whitespace and punctuation tokenization
        let pattern = "[\\s\\p{P}]+"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: text.utf16.count)

        var tokens: [String] = []
        var lastEnd = 0

        regex?.enumerateMatches(in: text, range: range) { match, _, _ in
            if let range = match?.range {
                let start = text.index(text.startIndex, offsetBy: lastEnd)
                let end = text.index(text.startIndex, offsetBy: range.location)
                let token = String(text[start..<end])
                if !token.isEmpty {
                    tokens.append(token.lowercased())
                }
                lastEnd = range.location + range.length
            }
        }

        // Add last token
        if lastEnd < text.count {
            let start = text.index(text.startIndex, offsetBy: lastEnd)
            let token = String(text[start...])
            if !token.isEmpty {
                tokens.append(token.lowercased())
            }
        }

        return tokens
    }

    private func wordPieceTokenize(_ word: String) -> [Int] {
        var outputTokens: [Int] = []
        var start = 0

        while start < word.count {
            var end = word.count
            var curSubstr: String?

            while start < end {
                let startIdx = word.index(word.startIndex, offsetBy: start)
                let endIdx = word.index(word.startIndex, offsetBy: end)
                var substr = String(word[startIdx..<endIdx])

                if start > 0 {
                    substr = "##" + substr
                }

                if wordPieces[substr] != nil {
                    curSubstr = substr
                    break
                }

                end -= 1
            }

            if curSubstr == nil {
                return [wordPieces[unkToken] ?? 3]
            }

            outputTokens.append(wordPieces[curSubstr!]!)
            start = end
        }

        return outputTokens
    }
}

// MARK: - Tokenizer Factory

enum TokenizerType {
    case base
    case bpe(vocabPath: String, mergesPath: String)
    case sentencePiece(modelPath: String)
    case wordPiece(vocabPath: String)
    case realBPE(configPath: String)
    case realSentencePiece(modelPath: String)
    case realWordPiece(vocabPath: String)
}

class TokenizerFactory {
    static func create(type: TokenizerType) throws -> Tokenizer {
        switch type {
        case .base:
            return BaseTokenizer()

        case .bpe(let vocabPath, let mergesPath):
            return try GenericBPETokenizer(vocabPath: vocabPath, mergesPath: mergesPath)

        case .sentencePiece(let modelPath):
            return try SentencePieceTokenizer(modelPath: modelPath)

        case .wordPiece(let vocabPath):
            return try WordPieceTokenizer(vocabPath: vocabPath)

        case .realBPE(let configPath):
            // For now, fallback to GenericBPE
            return (try? GenericBPETokenizer(vocabPath: configPath.replacingOccurrences(of: "tokenizer.json", with: "vocab.json"), 
                                            mergesPath: configPath.replacingOccurrences(of: "tokenizer.json", with: "merges.txt"))) ?? BaseTokenizer()

        case .realSentencePiece(let modelPath):
            return (try? SentencePieceTokenizer(modelPath: modelPath)) ?? BaseTokenizer()

        case .realWordPiece(let vocabPath):
            return (try? WordPieceTokenizer(vocabPath: vocabPath)) ?? BaseTokenizer()
        }
    }

    /// Create tokenizer for a framework and model - DEPRECATED, use createAdapter instead
    static func createForFramework(_ framework: LLMFramework, modelPath: String) -> Tokenizer {
        // First try to load real tokenizers with proper model files

        // Check for tokenizer.json (most modern models)
        let tokenizerJsonPath = "\(modelPath)/tokenizer.json"
        if FileManager.default.fileExists(atPath: tokenizerJsonPath) {
            // For now, try to infer from associated files since we don't have a full JSON parser
            if FileManager.default.fileExists(atPath: "\(modelPath)/vocab.json") &&
               FileManager.default.fileExists(atPath: "\(modelPath)/merges.txt") {
                // Likely BPE tokenizer (GPT-2 style)
                return (try? BPETokenizer(vocabPath: "\(modelPath)/vocab.json", mergesPath: "\(modelPath)/merges.txt")) ?? BaseTokenizer()
            }
        }

        // Framework-specific tokenizer detection
        switch framework {
        case .llamaCpp:
            // llama.cpp typically uses SentencePiece
            let spPaths = [
                "\(modelPath)/tokenizer.model",
                "\(modelPath)/spiece.model",
                "\(modelPath).tokenizer"
            ]

            for path in spPaths {
                if FileManager.default.fileExists(atPath: path) {
                    return (try? SentencePieceTokenizer(modelPath: path)) ?? BaseTokenizer()
                }
            }

        case .coreML, .mlx:
            // These might use BPE tokenizers
            // Check for standard names first
            if FileManager.default.fileExists(atPath: "\(modelPath)/vocab.json") &&
                FileManager.default.fileExists(atPath: "\(modelPath)/merges.txt") {
                return (try? BPETokenizer(vocabPath: "\(modelPath)/vocab.json",
                                         mergesPath: "\(modelPath)/merges.txt")) ?? BaseTokenizer()
            }
            // Check for GPT-2 specific names
            if FileManager.default.fileExists(atPath: "\(modelPath)/gpt2-vocab.json") &&
                FileManager.default.fileExists(atPath: "\(modelPath)/gpt2-merges.txt") {
                print("Found GPT-2 tokenizer files!")
                do {
                    let tokenizer = try BPETokenizer(vocabPath: "\(modelPath)/gpt2-vocab.json",
                                                    mergesPath: "\(modelPath)/gpt2-merges.txt")
                    print("Successfully loaded BPE tokenizer with \(tokenizer.vocabularySize) tokens")
                    return tokenizer
                } catch {
                    print("Failed to load BPE tokenizer: \(error)")
                    return BaseTokenizer()
                }
            }

        case .onnxRuntime, .tensorFlowLite:
            // Often use WordPiece for BERT-style models
            let vocabPaths = [
                "\(modelPath)/vocab.txt",
                "\(modelPath)/bert_vocab.txt"
            ]

            for path in vocabPaths {
                if FileManager.default.fileExists(atPath: path) {
                    return (try? WordPieceTokenizer(vocabPath: path)) ?? BaseTokenizer()
                }
            }

        case .foundationModels:
            // Apple's models might have their own format
            // For now, use base tokenizer
            break

        default:
            break
        }

        // Fallback to base tokenizer
        print("Warning: No suitable tokenizer found for \(framework), using base tokenizer")
        return BaseTokenizer()
    }

    /// Creates the best available tokenizer for a given model directory
    static func createBestTokenizer(modelPath: String) -> Tokenizer {
        // Try each framework's expected tokenizer format
        for framework in LLMFramework.allCases {
            let tokenizer = createForFramework(framework, modelPath: modelPath)
            if !(tokenizer is BaseTokenizer) {
                print("Found tokenizer for framework: \(framework)")
                return tokenizer
            }
        }

        return BaseTokenizer()
    }
}
