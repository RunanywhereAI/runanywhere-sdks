import Foundation

// MARK: - Real WordPiece Tokenizer Implementation

class RealWordPieceTokenizer: Tokenizer {
    private var vocab: [String: Int] = [:]
    private var reverseVocab: [Int: String] = [:]
    private let doLowerCase: Bool
    private let maxInputCharsPerWord = 200
    private let unkToken = "[UNK]"
    private let sepToken = "[SEP]"
    private let padToken = "[PAD]"
    private let clsToken = "[CLS]"
    private let maskToken = "[MASK]"
    
    var vocabularySize: Int { vocab.count }
    var eosToken: Int { vocab[sepToken] ?? 102 }
    var bosToken: Int { vocab[clsToken] ?? 101 }
    var padToken: Int { vocab[padToken] ?? 0 }
    
    init(vocabPath: String, doLowerCase: Bool = true) throws {
        self.doLowerCase = doLowerCase
        try loadVocabulary(from: vocabPath)
    }
    
    init(configPath: String) throws {
        // Load from tokenizer.json
        let config = try TokenizerConfigLoader.load(from: configPath)
        
        guard config.model.type == "WordPiece" else {
            throw LLMError.invalidModel("Not a WordPiece model")
        }
        
        // Check for lowercase normalization
        self.doLowerCase = config.normalizer?.type == "Lowercase" || 
                          config.normalizer?.type == "BertNormalizer"
        
        if let vocab = config.model.vocab {
            self.vocab = vocab
            self.reverseVocab = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
        }
    }
    
    private func loadVocabulary(from path: String) throws {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        
        content.enumerateLines { [weak self] line, _ in
            guard let self = self else { return }
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty {
                self.vocab[token] = self.vocab.count
            }
        }
        
        self.reverseVocab = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
    }
    
    func encode(_ text: String) -> [Int] {
        var tokens: [Int] = []
        
        // Add CLS token at the beginning
        if let clsId = vocab[clsToken] {
            tokens.append(clsId)
        }
        
        // Normalize and tokenize
        let normalizedText = normalize(text)
        let words = basicTokenize(normalizedText)
        
        for word in words {
            let wordPieces = wordPieceTokenize(word)
            tokens.append(contentsOf: wordPieces)
        }
        
        // Add SEP token at the end
        if let sepId = vocab[sepToken] {
            tokens.append(sepId)
        }
        
        return tokens
    }
    
    func decode(_ tokens: [Int]) -> String {
        var pieces: [String] = []
        
        for token in tokens {
            if let piece = reverseVocab[token] {
                // Skip special tokens
                if piece == clsToken || piece == sepToken || piece == padToken {
                    continue
                }
                
                pieces.append(piece)
            }
        }
        
        // Join pieces and handle ## prefixes
        var result = ""
        for (i, piece) in pieces.enumerated() {
            if piece.hasPrefix("##") {
                // Remove ## and append directly
                result += piece.dropFirst(2)
            } else if i > 0 {
                // Add space before non-## pieces (except first)
                result += " " + piece
            } else {
                result += piece
            }
        }
        
        return result
    }
    
    private func normalize(_ text: String) -> String {
        var normalized = text
        
        // Convert to lowercase if required
        if doLowerCase {
            normalized = normalized.lowercased()
        }
        
        // Remove accents
        normalized = removeAccents(normalized)
        
        // Normalize whitespace
        normalized = normalized.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func removeAccents(_ text: String) -> String {
        // Remove combining diacritical marks
        let mutableString = NSMutableString(string: text)
        CFStringTransform(mutableString, nil, kCFStringTransformStripCombiningMarks, false)
        return mutableString as String
    }
    
    private func basicTokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var currentToken = ""
        
        for char in text {
            if char.isWhitespace || char.isPunctuation || isChineseChar(char) {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                
                if char.isPunctuation || isChineseChar(char) {
                    tokens.append(String(char))
                }
            } else {
                currentToken.append(char)
            }
        }
        
        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }
        
        return tokens
    }
    
    private func isChineseChar(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let value = scalar.value
        
        return (0x4E00 <= value && value <= 0x9FFF) ||
               (0x3400 <= value && value <= 0x4DBF) ||
               (0x20000 <= value && value <= 0x2A6DF) ||
               (0x2A700 <= value && value <= 0x2B73F) ||
               (0x2B740 <= value && value <= 0x2B81F) ||
               (0x2B820 <= value && value <= 0x2CEAF) ||
               (0xF900 <= value && value <= 0xFAFF) ||
               (0x2F800 <= value && value <= 0x2FA1F)
    }
    
    private func wordPieceTokenize(_ word: String) -> [Int] {
        if word.count > maxInputCharsPerWord {
            return [vocab[unkToken] ?? 0]
        }
        
        var outputTokens: [Int] = []
        var start = 0
        let chars = Array(word)
        
        while start < chars.count {
            var end = chars.count
            var curSubstr: String?
            
            while start < end {
                var substr = String(chars[start..<end])
                
                // Add ## prefix for sub-words (not at the beginning)
                if start > 0 {
                    substr = "##" + substr
                }
                
                if vocab[substr] != nil {
                    curSubstr = substr
                    break
                }
                
                end -= 1
            }
            
            if let substr = curSubstr {
                if let tokenId = vocab[substr] {
                    outputTokens.append(tokenId)
                }
                start = end
            } else {
                // Unknown token
                return [vocab[unkToken] ?? 0]
            }
        }
        
        return outputTokens
    }
}

// MARK: - Tokenizer Extensions for BERT Models

extension RealWordPieceTokenizer {
    /// Creates a WordPiece tokenizer for BERT-style models
    static func createBERTTokenizer(modelPath: String, doLowerCase: Bool = true) throws -> RealWordPieceTokenizer {
        // Try common paths
        let paths = [
            "\(modelPath)/tokenizer.json",
            "\(modelPath)/vocab.txt",
            "\(modelPath)/bert_vocab.txt"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                if path.hasSuffix(".json") {
                    return try RealWordPieceTokenizer(configPath: path)
                } else {
                    return try RealWordPieceTokenizer(vocabPath: path, doLowerCase: doLowerCase)
                }
            }
        }
        
        throw LLMError.fileNotFound
    }
    
    /// Encodes text for BERT with proper formatting
    func encodeBERT(_ text: String, maxLength: Int = 512) -> (inputIds: [Int], attentionMask: [Int]) {
        let tokens = encode(text)
        
        // Truncate if needed
        let truncated = Array(tokens.prefix(maxLength))
        
        // Pad if needed
        var padded = truncated
        let paddingLength = maxLength - truncated.count
        if paddingLength > 0 {
            let padId = vocab[padToken] ?? 0
            padded.append(contentsOf: Array(repeating: padId, count: paddingLength))
        }
        
        // Create attention mask
        let attentionMask = padded.map { token in
            token != (vocab[padToken] ?? 0) ? 1 : 0
        }
        
        return (padded, attentionMask)
    }
    
    /// Encodes two sequences for BERT (e.g., question-answering)
    func encodePair(_ textA: String, _ textB: String, maxLength: Int = 512) -> (inputIds: [Int], attentionMask: [Int], tokenTypeIds: [Int]) {
        // Encode both texts
        let tokensA = encode(textA)
        let tokensB = encode(textB)
        
        // Remove CLS/SEP from individual encodings
        let cleanTokensA = Array(tokensA.dropFirst().dropLast())
        let cleanTokensB = Array(tokensB.dropFirst().dropLast())
        
        // Combine: [CLS] A [SEP] B [SEP]
        var combined: [Int] = []
        combined.append(vocab[clsToken] ?? 101)
        combined.append(contentsOf: cleanTokensA)
        combined.append(vocab[sepToken] ?? 102)
        combined.append(contentsOf: cleanTokensB)
        combined.append(vocab[sepToken] ?? 102)
        
        // Truncate if needed
        let truncated = Array(combined.prefix(maxLength))
        
        // Create token type IDs
        var tokenTypeIds: [Int] = []
        var inSegmentB = false
        for (i, token) in truncated.enumerated() {
            if i > 0 && token == (vocab[sepToken] ?? 102) && !inSegmentB {
                inSegmentB = true
            }
            tokenTypeIds.append(inSegmentB ? 1 : 0)
        }
        
        // Pad if needed
        var padded = truncated
        let paddingLength = maxLength - truncated.count
        if paddingLength > 0 {
            let padId = vocab[padToken] ?? 0
            padded.append(contentsOf: Array(repeating: padId, count: paddingLength))
            tokenTypeIds.append(contentsOf: Array(repeating: 0, count: paddingLength))
        }
        
        // Create attention mask
        let attentionMask = padded.map { token in
            token != (vocab[padToken] ?? 0) ? 1 : 0
        }
        
        return (padded, attentionMask, tokenTypeIds)
    }
}