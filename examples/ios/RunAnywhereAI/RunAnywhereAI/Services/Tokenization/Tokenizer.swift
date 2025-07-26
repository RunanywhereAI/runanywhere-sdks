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
    private var vocabulary: [String: Int] = [:]
    private var reverseVocabulary: [Int: String] = [:]
    
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

// MARK: - BPE Tokenizer

class BPETokenizer: BaseTokenizer {
    private var merges: [(String, String)] = []
    private var vocab: [String: Int] = [:]
    private var byteEncoder: [Int: String] = [:]
    private var byteDecoder: [String: Int] = [:]
    
    override init() {
        super.init()
        initializeBytePairEncoding()
    }
    
    init(vocabPath: String, mergesPath: String) throws {
        super.init()
        try loadVocabulary(from: vocabPath)
        try loadMerges(from: mergesPath)
        initializeBytePairEncoding()
    }
    
    private func initializeBytePairEncoding() {
        // Initialize byte-level BPE
        let bytes = Array(0...255)
        var n = 0
        
        for b in bytes {
            if (b >= 33 && b <= 126) || (b >= 161 && b <= 172) || (b >= 174 && b <= 255) {
                byteEncoder[b] = String(UnicodeScalar(b)!)
                byteDecoder[String(UnicodeScalar(b)!)] = b
            } else {
                byteEncoder[b] = String(UnicodeScalar(256 + n)!)
                byteDecoder[String(UnicodeScalar(256 + n)!)] = b
                n += 1
            }
        }
    }
    
    private func loadVocabulary(from path: String) throws {
        let data = try String(contentsOfFile: path)
        let lines = data.components(separatedBy: .newlines)
        
        for (index, line) in lines.enumerated() {
            let components = line.components(separatedBy: " ")
            if let token = components.first {
                vocab[token] = index
            }
        }
    }
    
    private func loadMerges(from path: String) throws {
        let data = try String(contentsOfFile: path)
        let lines = data.components(separatedBy: .newlines)
        
        for line in lines.dropFirst() { // Skip header
            let parts = line.components(separatedBy: " ")
            if parts.count == 2 {
                merges.append((parts[0], parts[1]))
            }
        }
    }
    
    override func encode(_ text: String) -> [Int] {
        // Convert text to bytes then apply BPE
        let bytes = Array(text.utf8)
        var tokens: [String] = []
        
        for byte in bytes {
            if let encoded = byteEncoder[Int(byte)] {
                tokens.append(encoded)
            }
        }
        
        // Apply BPE merges
        tokens = applyBPE(tokens)
        
        // Convert to token IDs
        var tokenIds: [Int] = [bosToken]
        for token in tokens {
            if let id = vocab[token] {
                tokenIds.append(id)
            } else {
                tokenIds.append(vocabulary["<unk>"] ?? 3)
            }
        }
        tokenIds.append(eosToken)
        
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
        return text.replacingOccurrences(of: " ", with: "▁")
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
    private var wordPieces: [String: Int] = [:]
    private let maxInputCharsPerWord = 100
    private let unkToken = "[UNK]"
    
    init(vocabPath: String) throws {
        super.init()
        try loadVocabulary(from: vocabPath)
    }
    
    private func loadVocabulary(from path: String) throws {
        let data = try String(contentsOfFile: path)
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
            var curSubstr: String? = nil
            
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
}

class TokenizerFactory {
    static func create(type: TokenizerType) throws -> Tokenizer {
        switch type {
        case .base:
            return BaseTokenizer()
            
        case .bpe(let vocabPath, let mergesPath):
            return try BPETokenizer(vocabPath: vocabPath, mergesPath: mergesPath)
            
        case .sentencePiece(let modelPath):
            return try SentencePieceTokenizer(modelPath: modelPath)
            
        case .wordPiece(let vocabPath):
            return try WordPieceTokenizer(vocabPath: vocabPath)
        }
    }
    
    static func createForFramework(_ framework: LLMFramework, modelPath: String) -> Tokenizer {
        // Determine tokenizer type based on framework and model
        switch framework {
        case .llamaCpp:
            // llama.cpp typically uses SentencePiece
            if FileManager.default.fileExists(atPath: modelPath + ".tokenizer") {
                return (try? SentencePieceTokenizer(modelPath: modelPath + ".tokenizer")) ?? BaseTokenizer()
            }
            
        case .coreML, .mlx:
            // These might bundle their own tokenizers
            if FileManager.default.fileExists(atPath: modelPath + "/tokenizer.json") {
                return (try? BPETokenizer(vocabPath: modelPath + "/vocab.json", 
                                        mergesPath: modelPath + "/merges.txt")) ?? BaseTokenizer()
            }
            
        case .onnxRuntime, .tensorFlowLite:
            // Often use WordPiece
            if FileManager.default.fileExists(atPath: modelPath + "/vocab.txt") {
                return (try? WordPieceTokenizer(vocabPath: modelPath + "/vocab.txt")) ?? BaseTokenizer()
            }
            
        default:
            break
        }
        
        // Fallback to base tokenizer
        return BaseTokenizer()
    }
}