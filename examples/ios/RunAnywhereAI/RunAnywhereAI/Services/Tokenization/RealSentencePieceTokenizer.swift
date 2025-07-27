import Foundation

// MARK: - SentencePiece Model Format

struct SentencePieceModel {
    struct Piece {
        let piece: String
        let score: Float
        let type: PieceType
        
        enum PieceType: Int {
            case normal = 1
            case unknown = 2
            case control = 3
            case userDefined = 4
            case unused = 5
            case byte = 6
        }
    }
    
    let pieces: [Piece]
    let vocab: [String: Int]
    let scores: [Float]
    let unkId: Int
    let bosId: Int
    let eosId: Int
    let padId: Int
}

// MARK: - Real SentencePiece Tokenizer

class RealSentencePieceTokenizer: Tokenizer {
    private var model: SentencePieceModel?
    private var vocab: [String: Int] = [:]
    private var reverseVocab: [Int: String] = [:]
    private var scores: [Float] = []
    private let replaceChar = "▁"  // SentencePiece space replacement
    
    var vocabularySize: Int { vocab.count }
    var eosToken: Int { model?.eosId ?? 2 }
    var bosToken: Int { model?.bosId ?? 1 }
    var padToken: Int { model?.padId ?? 0 }
    
    init(modelPath: String) throws {
        try loadModel(from: modelPath)
    }
    
    private func loadModel(from path: String) throws {
        // Try to load from tokenizer.json first (for HuggingFace format)
        if path.hasSuffix(".json") {
            try loadFromJSON(path)
        } else {
            // Load from SentencePiece .model file
            try loadFromSPModel(path)
        }
    }
    
    private func loadFromJSON(_ path: String) throws {
        let config = try TokenizerConfigLoader.load(from: path)
        
        guard config.model.type == "Unigram" else {
            throw LLMError.invalidModel("Not a SentencePiece/Unigram model")
        }
        
        if let vocab = config.model.vocab {
            self.vocab = vocab
            self.reverseVocab = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
        }
        
        // Extract special tokens
        let specialTokens = SpecialTokens(from: config)
        
        // Build model structure
        var pieces: [SentencePieceModel.Piece] = []
        for (token, id) in vocab.sorted(by: { $0.value < $1.value }) {
            let type: SentencePieceModel.Piece.PieceType
            if token.hasPrefix("<") && token.hasSuffix(">") {
                type = .control
            } else if token == specialTokens.unkToken {
                type = .unknown
            } else {
                type = .normal
            }
            
            pieces.append(SentencePieceModel.Piece(
                piece: token,
                score: 0.0,  // Scores not available in JSON format
                type: type
            ))
        }
        
        self.model = SentencePieceModel(
            pieces: pieces,
            vocab: vocab,
            scores: Array(repeating: 0.0, count: vocab.count),
            unkId: specialTokens.unkTokenId,
            bosId: specialTokens.bosTokenId,
            eosId: specialTokens.eosTokenId,
            padId: specialTokens.padTokenId
        )
    }
    
    private func loadFromSPModel(_ path: String) throws {
        // For a real implementation, this would parse the protobuf .model file
        // For now, we'll create a simplified version
        
        // Try to load accompanying vocab file
        let vocabPath = path.replacingOccurrences(of: ".model", with: ".vocab")
        if FileManager.default.fileExists(atPath: vocabPath) {
            let content = try String(contentsOfFile: vocabPath, encoding: .utf8)
            var pieces: [SentencePieceModel.Piece] = []
            
            content.enumerateLines { line, _ in
                let parts = line.split(separator: "\t")
                if parts.count >= 1 {
                    let piece = String(parts[0])
                    let score = parts.count > 1 ? Float(parts[1]) ?? 0.0 : 0.0
                    
                    self.vocab[piece] = self.vocab.count
                    pieces.append(SentencePieceModel.Piece(
                        piece: piece,
                        score: score,
                        type: .normal
                    ))
                }
            }
            
            self.reverseVocab = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })
            
            // Find special tokens
            let unkId = vocab["<unk>"] ?? 0
            let bosId = vocab["<s>"] ?? 1
            let eosId = vocab["</s>"] ?? 2
            let padId = vocab["<pad>"] ?? 3
            
            self.model = SentencePieceModel(
                pieces: pieces,
                vocab: vocab,
                scores: pieces.map { $0.score },
                unkId: unkId,
                bosId: bosId,
                eosId: eosId,
                padId: padId
            )
        } else {
            throw LLMError.fileNotFound
        }
    }
    
    func encode(_ text: String) -> [Int] {
        guard let model = model else { return [] }
        
        var tokens: [Int] = [model.bosId]
        
        // Normalize text
        let normalized = normalizeText(text)
        
        // Apply SentencePiece algorithm
        let pieces = encodeAsPieces(normalized)
        
        for piece in pieces {
            if let id = vocab[piece] {
                tokens.append(id)
            } else {
                tokens.append(model.unkId)
            }
        }
        
        tokens.append(model.eosId)
        return tokens
    }
    
    func decode(_ tokens: [Int]) -> String {
        guard let model = model else { return "" }
        
        var pieces: [String] = []
        
        for token in tokens {
            // Skip special tokens
            if token == model.bosId || token == model.eosId || token == model.padId {
                continue
            }
            
            if let piece = reverseVocab[token] {
                pieces.append(piece)
            }
        }
        
        // Join pieces and replace space marker
        let text = pieces.joined()
        return text.replacingOccurrences(of: replaceChar, with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
    
    private func normalizeText(_ text: String) -> String {
        // Replace spaces with special character
        var normalized = text
        
        // Add space at the beginning if not present
        if !normalized.isEmpty && !normalized.hasPrefix(" ") {
            normalized = " " + normalized
        }
        
        // Replace spaces with replacement character
        normalized = normalized.replacingOccurrences(of: " ", with: replaceChar)
        
        return normalized
    }
    
    private func encodeAsPieces(_ text: String) -> [String] {
        guard let model = model else { return [] }
        
        // Use a greedy algorithm to find the best segmentation
        var pieces: [String] = []
        var pos = 0
        let chars = Array(text)
        
        while pos < chars.count {
            var foundPiece = false
            var endPos = chars.count
            
            // Try to find the longest piece that exists in vocabulary
            while endPos > pos {
                let substring = String(chars[pos..<endPos])
                
                if vocab[substring] != nil {
                    pieces.append(substring)
                    pos = endPos
                    foundPiece = true
                    break
                }
                
                endPos -= 1
            }
            
            // If no piece found, use unknown token
            if !foundPiece {
                // Try byte fallback for unknown characters
                let char = String(chars[pos])
                if let byteValue = char.utf8.first {
                    let bytePiece = "<0x\(String(format: "%02X", byteValue))>"
                    if vocab[bytePiece] != nil {
                        pieces.append(bytePiece)
                    } else {
                        pieces.append("<unk>")
                    }
                } else {
                    pieces.append("<unk>")
                }
                pos += 1
            }
        }
        
        return pieces
    }
}

// MARK: - Tokenizer Extensions for Common Models

extension RealSentencePieceTokenizer {
    /// Creates a SentencePiece tokenizer for LLaMA-style models
    static func createLLaMATokenizer(modelPath: String) throws -> RealSentencePieceTokenizer {
        // Try common paths
        let paths = [
            "\(modelPath)/tokenizer.model",
            "\(modelPath)/tokenizer.json",
            "\(modelPath)/spiece.model"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return try RealSentencePieceTokenizer(modelPath: path)
            }
        }
        
        throw LLMError.fileNotFound
    }
    
    /// Creates a SentencePiece tokenizer for T5-style models
    static func createT5Tokenizer(modelPath: String) throws -> RealSentencePieceTokenizer {
        return try createLLaMATokenizer(modelPath: modelPath)
    }
}