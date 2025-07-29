//
//  TokenizerAdapter.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import Foundation

// MARK: - Tokenizer Adapter Protocol

/// Protocol for model-specific tokenizer adapters
/// This allows framework-agnostic and model-agnostic tokenization
protocol TokenizerAdapter {
    /// The underlying tokenizer implementation
    var tokenizer: Tokenizer { get }
    
    /// Model/Framework specific configuration
    var modelType: String { get }
    
    /// Encode text to token IDs
    func encode(_ text: String) -> [Int]
    
    /// Decode token IDs to text
    func decode(_ tokens: [Int]) -> String
    
    /// Decode a single token (for streaming)
    func decodeToken(_ token: Int) -> String
    
    /// Get vocabulary size
    var vocabularySize: Int { get }
    
    /// Special tokens
    var bosToken: Int { get }
    var eosToken: Int { get }
    var padToken: Int { get }
    
    /// Check if this adapter is compatible with a model
    func isCompatible(with modelPath: String) -> Bool
}

// MARK: - Base Tokenizer Adapter

/// Base implementation of TokenizerAdapter with common functionality
class BaseTokenizerAdapter: TokenizerAdapter {
    let tokenizer: Tokenizer
    let modelType: String
    
    init(tokenizer: Tokenizer, modelType: String) {
        self.tokenizer = tokenizer
        self.modelType = modelType
    }
    
    func encode(_ text: String) -> [Int] {
        return tokenizer.encode(text)
    }
    
    func decode(_ tokens: [Int]) -> String {
        return tokenizer.decode(tokens)
    }
    
    func decodeToken(_ token: Int) -> String {
        // Default implementation: decode single token as array
        return decode([token])
    }
    
    var vocabularySize: Int {
        return tokenizer.vocabularySize
    }
    
    var bosToken: Int {
        return tokenizer.bosToken
    }
    
    var eosToken: Int {
        return tokenizer.eosToken
    }
    
    var padToken: Int {
        return tokenizer.padToken
    }
    
    func isCompatible(with modelPath: String) -> Bool {
        // Base implementation: check if model path contains model type
        return modelPath.lowercased().contains(modelType.lowercased())
    }
}

// MARK: - Tokenizer Adapter Factory

class TokenizerAdapterFactory {
    /// Create appropriate tokenizer adapter for a model
    static func createAdapter(for modelPath: String, framework: LLMFramework) -> TokenizerAdapter? {
        // Try model-specific adapters first
        let adapters: [(String) -> TokenizerAdapter?] = [
            { path in GPT2TokenizerAdapter.create(from: path) },
            { path in LlamaTokenizerAdapter.create(from: path) },
            { path in BertTokenizerAdapter.create(from: path) },
            // Add more model-specific adapters here
        ]
        
        // Try each adapter
        for createAdapter in adapters {
            if let adapter = createAdapter(modelPath) {
                print("Created tokenizer adapter: \(type(of: adapter)) for model at: \(modelPath)")
                return adapter
            }
        }
        
        // Fallback to generic adapter based on available tokenizer files
        return createGenericAdapter(for: modelPath, framework: framework)
    }
    
    private static func createGenericAdapter(for modelPath: String, framework: LLMFramework) -> TokenizerAdapter? {
        // Try to create generic tokenizer based on available files
        let fileManager = FileManager.default
        
        // Check for BPE tokenizer files
        if fileManager.fileExists(atPath: "\(modelPath)/vocab.json") &&
           fileManager.fileExists(atPath: "\(modelPath)/merges.txt") {
            if let tokenizer = try? GenericBPETokenizer(
                vocabPath: "\(modelPath)/vocab.json",
                mergesPath: "\(modelPath)/merges.txt"
            ) {
                return BaseTokenizerAdapter(tokenizer: tokenizer, modelType: "generic-bpe")
            }
        }
        
        // Check for SentencePiece model
        let spPaths = [
            "\(modelPath)/tokenizer.model",
            "\(modelPath)/spiece.model",
            "\(modelPath).tokenizer"
        ]
        
        for spPath in spPaths {
            if fileManager.fileExists(atPath: spPath) {
                if let tokenizer = try? SentencePieceTokenizer(modelPath: spPath) {
                    return BaseTokenizerAdapter(tokenizer: tokenizer, modelType: "sentencepiece")
                }
            }
        }
        
        // Check for WordPiece vocabulary
        let wpPaths = [
            "\(modelPath)/vocab.txt",
            "\(modelPath)/bert_vocab.txt"
        ]
        
        for wpPath in wpPaths {
            if fileManager.fileExists(atPath: wpPath) {
                if let tokenizer = try? WordPieceTokenizer(vocabPath: wpPath) {
                    return BaseTokenizerAdapter(tokenizer: tokenizer, modelType: "wordpiece")
                }
            }
        }
        
        // Last resort: base tokenizer
        print("Warning: No suitable tokenizer found for \(modelPath), using base tokenizer")
        return BaseTokenizerAdapter(tokenizer: BaseTokenizer(), modelType: "base")
    }
}