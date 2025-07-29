//
//  TFLiteTokenizer.swift
//  RunAnywhereAI
//
//  WordPiece tokenizer implementation for TensorFlow Lite/LiteRT models
//  Based on official Google AI Edge samples
//

import Foundation

// MARK: - TFLite WordPiece Tokenizer

/// WordPiece tokenizer for TensorFlow Lite (LiteRT) models
/// Based on the official implementation from Google AI Edge samples
class TFLiteTokenizer: BaseTokenizer {
    
    // MARK: - Properties
    
    private let vocabularyIDs: [String: Int32]
    override var reverseVocabulary: [Int: String] {
        get {
            return Dictionary(uniqueKeysWithValues: _reverseVocabulary.map { (Int($0.key), $0.value) })
        }
        set {
            _reverseVocabulary = Dictionary(uniqueKeysWithValues: newValue.map { (Int32($0.key), $0.value) })
        }
    }
    private var _reverseVocabulary: [Int32: String]
    
    private static let UNKNOWN_TOKEN = "[UNK]"
    private static let MAX_INPUT_CHARS_PER_WORD = 128
    
    override var vocabularySize: Int { vocabularyIDs.count }
    
    // MARK: - Initialization
    
    /// Initialize with vocabulary from file path
    init(vocabularyPath: String) throws {
        let url = URL(fileURLWithPath: vocabularyPath)
        let content = try String(contentsOf: url, encoding: .utf8)
        
        var vocab = [String: Int32]()
        
        // Check if it's BERT vocab or average vocab based on content
        if content.contains("[PAD]") && content.contains("[CLS]") {
            // BERT vocabulary format
            for (index, line) in content.components(separatedBy: .newlines).enumerated() {
                if !line.isEmpty {
                    vocab[line] = Int32(index)
                }
            }
        } else {
            // Average word classifier format (might be different)
            for (index, line) in content.components(separatedBy: .newlines).enumerated() {
                if !line.isEmpty {
                    vocab[line] = Int32(index)
                }
            }
        }
        
        self.vocabularyIDs = vocab
        self._reverseVocabulary = vocab.reduce(into: [:]) { dict, pair in
            dict[pair.value] = pair.key
        }
        
        super.init()
    }
    
    /// Initialize for a specific model type
    init(for model: TFLiteModel) {
        switch model {
        case .mobileBert:
            self.vocabularyIDs = TFLiteTokenizer.loadBertVocabulary()
        case .avgWordClassifier:
            self.vocabularyIDs = TFLiteTokenizer.loadAverageVocabulary()
        case .custom(let vocabPath):
            do {
                let url = URL(fileURLWithPath: vocabPath)
                let content = try String(contentsOf: url, encoding: .utf8)
                var vocab = [String: Int32]()
                for (index, line) in content.components(separatedBy: .newlines).enumerated() {
                    if !line.isEmpty {
                        vocab[line] = Int32(index)
                    }
                }
                self.vocabularyIDs = vocab
            } catch {
                print("Failed to load custom vocabulary: \(error)")
                self.vocabularyIDs = [:]
            }
        }
        
        self._reverseVocabulary = vocabularyIDs.reduce(into: [:]) { dict, pair in
            dict[pair.value] = pair.key
        }
        
        super.init()
    }
    
    // MARK: - Tokenization
    
    override func encode(_ text: String) -> [Int] {
        let tokens = tokenize(text)
        return convertToIDs(tokens: tokens).map { Int($0) }
    }
    
    override func decode(_ tokens: [Int]) -> String {
        let stringTokens = tokens.compactMap { _reverseVocabulary[Int32($0)] }
        
        // Join tokens and handle WordPiece markers
        var result = ""
        for token in stringTokens {
            if token.hasPrefix("##") {
                // Continuation of previous word
                result += String(token.dropFirst(2))
            } else if !result.isEmpty {
                // New word, add space
                result += " " + token
            } else {
                // First token
                result = token
            }
        }
        
        return result
    }
    
    /// Tokenize text using WordPiece algorithm
    func tokenize(_ text: String) -> [String] {
        var outputTokens = [String]()
        
        // Split by whitespace and process each word
        text.lowercased().splitByWhitespace().forEach { rawToken in
            if rawToken.count > TFLiteTokenizer.MAX_INPUT_CHARS_PER_WORD {
                outputTokens.append(TFLiteTokenizer.UNKNOWN_TOKEN)
                return
            }
            
            let subwords = wordpieceTokenize(rawToken)
            outputTokens.append(contentsOf: subwords)
        }
        
        return outputTokens
    }
    
    /// Convert tokens to vocabulary IDs
    func convertToIDs(tokens: [String]) -> [Int32] {
        return tokens.compactMap { vocabularyIDs[$0] }
    }
    
    // MARK: - Private Methods
    
    /// Perform WordPiece tokenization on a single word
    private func wordpieceTokenize(_ token: String) -> [String] {
        var start = token.startIndex
        var subwords = [String]()
        
        // Find all subwords in token
        while start < token.endIndex {
            var end = token.endIndex
            var foundSubword = false
            
            // Find longest known subword from start
            while start < end {
                var substr = String(token[start..<end])
                
                // Add ## prefix for continuation subwords
                if start > token.startIndex {
                    substr = "##" + substr
                }
                
                if vocabularyIDs[substr] != nil {
                    // Found a valid subword
                    foundSubword = true
                    subwords.append(substr)
                    break
                } else {
                    end = token.index(before: end)
                }
            }
            
            if foundSubword {
                // Move to next position
                start = end
            } else {
                // No valid subword found, mark as unknown
                return [TFLiteTokenizer.UNKNOWN_TOKEN]
            }
        }
        
        return subwords
    }
    
    // MARK: - Vocabulary Loading
    
    private static func loadBertVocabulary() -> [String: Int32] {
        guard let path = Bundle.main.path(forResource: "bert_vocab", ofType: "txt") else {
            print("BERT vocabulary file not found")
            return [:]
        }
        
        return loadVocabularyFromFile(path)
    }
    
    private static func loadAverageVocabulary() -> [String: Int32] {
        guard let path = Bundle.main.path(forResource: "average_vocab", ofType: "txt") else {
            print("Average vocabulary file not found")
            return [:]
        }
        
        return loadVocabularyFromFile(path)
    }
    
    private static func loadVocabularyFromFile(_ path: String) -> [String: Int32] {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            var vocab = [String: Int32]()
            
            for (index, line) in content.components(separatedBy: .newlines).enumerated() {
                if !line.isEmpty {
                    vocab[line] = Int32(index)
                }
            }
            
            return vocab
        } catch {
            print("Failed to load vocabulary: \(error)")
            return [:]
        }
    }
}

// MARK: - Model Types

enum TFLiteModel {
    case mobileBert
    case avgWordClassifier
    case custom(vocabPath: String)
}

// MARK: - String Extension

extension String {
    /// Split string by whitespace (normalized)
    func splitByWhitespace() -> [String] {
        // Normalize to NFC (Normalization Form Canonical Composition)
        return self.precomposedStringWithCanonicalMapping
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }
}

// MARK: - Data Extension (from official samples)

extension Data {
    /// Creates a new buffer by copying the buffer pointer of the given array
    init<T>(copyingBufferOf array: [T]) {
        self = array.withUnsafeBufferPointer(Data.init)
    }
    
    /// Convert Data to array representation
    func toArray<T>(type: T.Type) -> [T] where T: AdditiveArithmetic {
        var array = [T](repeating: T.zero, count: self.count / MemoryLayout<T>.stride)
        _ = array.withUnsafeMutableBytes { self.copyBytes(to: $0) }
        return array
    }
}

// MARK: - TFLite Tokenizer Factory Extension

extension TokenizerFactory {
    /// Create a TensorFlow Lite tokenizer for a model
    static func createTFLiteTokenizer(modelPath: String) -> Tokenizer? {
        let modelName = URL(fileURLWithPath: modelPath).lastPathComponent
        
        // Determine model type based on name
        if modelName.contains("bert") {
            return TFLiteTokenizer(for: .mobileBert)
        } else if modelName.contains("average") {
            return TFLiteTokenizer(for: .avgWordClassifier)
        } else {
            // Look for vocabulary file in model directory
            let modelDir = URL(fileURLWithPath: modelPath).deletingLastPathComponent()
            let vocabPath = modelDir.appendingPathComponent("vocab.txt").path
            
            if FileManager.default.fileExists(atPath: vocabPath) {
                return TFLiteTokenizer(for: .custom(vocabPath: vocabPath))
            }
        }
        
        // Fallback to base tokenizer
        return TFLiteTokenizer(for: .avgWordClassifier)
    }
}