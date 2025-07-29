//
//  BertTokenizerAdapter.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import Foundation

// MARK: - BERT Tokenizer Adapter

class BertTokenizerAdapter: TokenizerAdapter {
    let tokenizer: Tokenizer
    let modelType = "bert"
    
    // BERT specific tokens
    private let clsTokenStr = "[CLS]"
    private let sepTokenStr = "[SEP]"
    private let padTokenStr = "[PAD]"
    private let unkTokenStr = "[UNK]"
    
    init(tokenizer: Tokenizer) {
        self.tokenizer = tokenizer
    }
    
    func encode(_ text: String) -> [Int] {
        // BERT specific encoding: [CLS] text [SEP]
        var tokens: [Int] = []
        
        // Add CLS token
        if let clsId = (tokenizer as? WordPieceTokenizer)?.wordPieces[clsTokenStr] {
            tokens.append(clsId)
        }
        
        // Encode text
        tokens.append(contentsOf: tokenizer.encode(text))
        
        // Add SEP token
        if let sepId = (tokenizer as? WordPieceTokenizer)?.wordPieces[sepTokenStr] {
            tokens.append(sepId)
        }
        
        return tokens
    }
    
    func decode(_ tokens: [Int]) -> String {
        // BERT specific decoding - remove special tokens
        var filteredTokens = tokens
        
        // Remove CLS and SEP tokens if present
        if let wpTokenizer = tokenizer as? WordPieceTokenizer {
            if let clsId = wpTokenizer.wordPieces[clsTokenStr] {
                filteredTokens.removeAll { $0 == clsId }
            }
            if let sepId = wpTokenizer.wordPieces[sepTokenStr] {
                filteredTokens.removeAll { $0 == sepId }
            }
            if let padId = wpTokenizer.wordPieces[padTokenStr] {
                filteredTokens.removeAll { $0 == padId }
            }
        }
        
        return tokenizer.decode(filteredTokens)
    }
    
    func decodeToken(_ token: Int) -> String {
        return tokenizer.decode([token])
    }
    
    var vocabularySize: Int {
        return tokenizer.vocabularySize
    }
    
    var bosToken: Int {
        return (tokenizer as? WordPieceTokenizer)?.wordPieces[clsTokenStr] ?? 101
    }
    
    var eosToken: Int {
        return (tokenizer as? WordPieceTokenizer)?.wordPieces[sepTokenStr] ?? 102
    }
    
    var padToken: Int {
        return (tokenizer as? WordPieceTokenizer)?.wordPieces[padTokenStr] ?? 0
    }
    
    func isCompatible(with modelPath: String) -> Bool {
        let path = modelPath.lowercased()
        return path.contains("bert") || 
               FileManager.default.fileExists(atPath: "\(modelPath)/vocab.txt")
    }
    
    static func create(from modelPath: String) -> BertTokenizerAdapter? {
        // Check for WordPiece vocabulary file
        let vocabPaths = [
            "\(modelPath)/vocab.txt",
            "\(modelPath)/bert_vocab.txt"
        ]
        
        for path in vocabPaths {
            if FileManager.default.fileExists(atPath: path) {
                if let tokenizer = try? WordPieceTokenizer(vocabPath: path) {
                    return BertTokenizerAdapter(tokenizer: tokenizer)
                }
            }
        }
        
        return nil
    }
}