//
//  LlamaTokenizerAdapter.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import Foundation

// MARK: - Llama Tokenizer Adapter

class LlamaTokenizerAdapter: TokenizerAdapter {
    let tokenizer: Tokenizer
    let modelType = "llama"

    init(tokenizer: Tokenizer) {
        self.tokenizer = tokenizer
    }

    func encode(_ text: String) -> [Int] {
        // Llama specific encoding (add BOS token)
        var tokens = tokenizer.encode(text)
        if !tokens.isEmpty && tokens[0] != bosToken {
            tokens.insert(bosToken, at: 0)
        }
        return tokens
    }

    func decode(_ tokens: [Int]) -> String {
        // Llama specific decoding
        return tokenizer.decode(tokens)
    }

    func decodeToken(_ token: Int) -> String {
        return tokenizer.decode([token])
    }

    var vocabularySize: Int {
        return tokenizer.vocabularySize
    }

    var bosToken: Int {
        return 1 // Llama BOS token
    }

    var eosToken: Int {
        return 2 // Llama EOS token
    }

    var padToken: Int {
        return 0 // Llama PAD token
    }

    func isCompatible(with modelPath: String) -> Bool {
        let path = modelPath.lowercased()
        return path.contains("llama") ||
               FileManager.default.fileExists(atPath: "\(modelPath)/tokenizer.model")
    }

    static func create(from modelPath: String) -> LlamaTokenizerAdapter? {
        // Check for SentencePiece model file
        let spPaths = [
            "\(modelPath)/tokenizer.model",
            "\(modelPath)/spiece.model"
        ]

        for path in spPaths {
            if FileManager.default.fileExists(atPath: path) {
                if let tokenizer = try? SentencePieceTokenizer(modelPath: path) {
                    return LlamaTokenizerAdapter(tokenizer: tokenizer)
                }
            }
        }

        return nil
    }
}
