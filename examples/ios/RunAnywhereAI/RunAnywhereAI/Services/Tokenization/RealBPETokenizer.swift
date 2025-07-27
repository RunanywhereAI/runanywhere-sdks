import Foundation

// MARK: - Real BPE Tokenizer Implementation

class RealBPETokenizer: Tokenizer {
    private var vocab: [String: Int] = [:]
    private var reverseVocab: [Int: String] = [:]
    private var merges: [(String, String)] = []
    private var mergeRanks: [String: Int] = [:]
    private var specialTokens: SpecialTokens?
    private let byteEncoder: [UInt8: String]
    private let byteDecoder: [String: UInt8]

    var vocabularySize: Int { vocab.count }
    var eosToken: Int { specialTokens?.eosTokenId ?? 2 }
    var bosToken: Int { specialTokens?.bosTokenId ?? 1 }
    var padToken: Int { specialTokens?.padTokenId ?? 0 }

    init(configPath: String) throws {
        // Initialize byte-level encoding
        (self.byteEncoder, self.byteDecoder) = RealBPETokenizer.createByteEncodings()

        // Load tokenizer configuration
        let config = try TokenizerConfigLoader.load(from: configPath)

        // Extract vocabulary and merges
        if let vocab = config.model.vocab {
            self.vocab = vocab
            self.reverseVocab = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
        }

        if let merges = config.model.merges {
            self.merges = RealBPETokenizer.parseMerges(merges)
            self.mergeRanks = Dictionary(uniqueKeysWithValues: self.merges.enumerated().map {
                ("\($1.0) \($1.1)", $0)
            })
        }

        self.specialTokens = SpecialTokens(from: config)
    }

    init(vocabPath: String, mergesPath: String) throws {
        // Initialize byte-level encoding
        (self.byteEncoder, self.byteDecoder) = RealBPETokenizer.createByteEncodings()

        // Load vocabulary
        self.vocab = try TokenizerConfigLoader.loadVocabulary(from: vocabPath)
        self.reverseVocab = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })

        // Load merges
        let mergeList = try TokenizerConfigLoader.loadMerges(from: mergesPath)
        self.merges = mergeList
        self.mergeRanks = Dictionary(uniqueKeysWithValues: mergeList.enumerated().map {
            ("\($1.0) \($1.1)", $0)
        })

        // Create default special tokens
        self.specialTokens = nil
    }

    private static func createByteEncodings() -> ([UInt8: String], [String: UInt8]) {
        var byteEncoder: [UInt8: String] = [:]
        var byteDecoder: [String: UInt8] = [:]

        let bs = Array(0...255)
        var cs = bs.filter { (33...126).contains($0) || (161...172).contains($0) || (174...255).contains($0) }

        var n = 0
        for b in 0...255 {
            if cs.contains(where: { $0 == UInt8(b) }) {
                byteEncoder[UInt8(b)] = String(UnicodeScalar(b)!)
                byteDecoder[String(UnicodeScalar(b)!)] = UInt8(b)
            } else {
                cs.append(256 + n)
                byteEncoder[UInt8(b)] = String(UnicodeScalar(256 + n)!)
                byteDecoder[String(UnicodeScalar(256 + n)!)] = UInt8(b)
                n += 1
            }
        }

        return (byteEncoder, byteDecoder)
    }

    private static func parseMerges(_ mergeStrings: [String]) -> [(String, String)] {
        mergeStrings.compactMap { merge in
            let parts = merge.split(separator: " ")
            guard parts.count == 2 else { return nil }
            return (String(parts[0]), String(parts[1]))
        }
    }

    func encode(_ text: String) -> [Int] {
        var tokens: [Int] = []

        // Add BOS token if needed
        if let specialTokens = specialTokens {
            tokens.append(specialTokens.bosTokenId)
        } else {
            tokens.append(bosToken)
        }

        // Pre-tokenize by splitting on whitespace and special characters
        let words = preTokenize(text)

        for word in words {
            // Convert word to bytes and encode
            let bytes = Array(word.utf8)
            var bpeTokens: [String] = []

            for byte in bytes {
                if let encoded = byteEncoder[byte] {
                    bpeTokens.append(encoded)
                }
            }

            // Apply BPE merges
            bpeTokens = applyBPE(bpeTokens)

            // Convert to token IDs
            for token in bpeTokens {
                if let id = vocab[token] {
                    tokens.append(id)
                } else if let unkId = specialTokens?.unkTokenId {
                    tokens.append(unkId)
                } else {
                    tokens.append(vocab["<unk>"] ?? 3)
                }
            }
        }

        // Add EOS token
        if let specialTokens = specialTokens {
            tokens.append(specialTokens.eosTokenId)
        } else {
            tokens.append(eosToken)
        }

        return tokens
    }

    func decode(_ tokens: [Int]) -> String {
        var text = ""

        for token in tokens {
            // Skip special tokens
            if let specialTokens = specialTokens {
                if token == specialTokens.bosTokenId ||
                    token == specialTokens.eosTokenId ||
                    token == specialTokens.padTokenId {
                    continue
                }
            }

            if let tokenStr = reverseVocab[token] {
                // Decode byte-level tokens back to text
                var bytes: [UInt8] = []
                for char in tokenStr {
                    if let byte = byteDecoder[String(char)] {
                        bytes.append(byte)
                    } else if let scalar = char.unicodeScalars.first,
                              scalar.value < 256 {
                        bytes.append(UInt8(scalar.value))
                    }
                }

                if let decoded = String(bytes: bytes, encoding: .utf8) {
                    text += decoded
                }
            }
        }

        return text
    }

    private func preTokenize(_ text: String) -> [String] {
        // GPT-style pre-tokenization: split on whitespace but keep it attached to words
        let pattern = #"'s|'t|'re|'ve|'m|'ll|'d| ?\p{L}+| ?\p{N}+| ?[^\s\p{L}\p{N}]+|\s+(?!\S)|\s+"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return text.split(separator: " ").map(String.init)
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private func applyBPE(_ tokens: [String]) -> [String] {
        guard tokens.count > 1 else { return tokens }

        var word = tokens

        while true {
            var pairs: [(String, String)] = []
            for i in 0..<(word.count - 1) {
                pairs.append((word[i], word[i + 1]))
            }

            // Find the pair with the lowest merge rank
            var minRank = Int.max
            var minPair: (String, String)?

            for pair in pairs {
                let pairStr = "\(pair.0) \(pair.1)"
                if let rank = mergeRanks[pairStr], rank < minRank {
                    minRank = rank
                    minPair = pair
                }
            }

            // If no merge found, we're done
            guard let mergePair = minPair else { break }

            // Apply the merge
            var newWord: [String] = []
            var i = 0

            while i < word.count {
                if i < word.count - 1 &&
                    word[i] == mergePair.0 &&
                    word[i + 1] == mergePair.1 {
                    newWord.append(mergePair.0 + mergePair.1)
                    i += 2
                } else {
                    newWord.append(word[i])
                    i += 1
                }
            }

            word = newWord

            if word.count == 1 {
                break
            }
        }

        return word
    }
}

// MARK: - Tokenizer Extensions for Common Models

extension RealBPETokenizer {
    /// Creates a BPE tokenizer for GPT-style models
    static func createGPTTokenizer(modelPath: String) throws -> RealBPETokenizer {
        let configPath = "\(modelPath)/tokenizer.json"
        if FileManager.default.fileExists(atPath: configPath) {
            return try RealBPETokenizer(configPath: configPath)
        }

        // Try alternative paths
        let vocabPath = "\(modelPath)/vocab.json"
        let mergesPath = "\(modelPath)/merges.txt"

        if FileManager.default.fileExists(atPath: vocabPath) &&
            FileManager.default.fileExists(atPath: mergesPath) {
            return try RealBPETokenizer(vocabPath: vocabPath, mergesPath: mergesPath)
        }

        throw LLMError.modelNotFound
    }

    /// Creates a BPE tokenizer for RoBERTa-style models
    static func createRoBERTaTokenizer(modelPath: String) throws -> RealBPETokenizer {
        // RoBERTa uses similar structure to GPT
        try createGPTTokenizer(modelPath: modelPath)
    }
}
