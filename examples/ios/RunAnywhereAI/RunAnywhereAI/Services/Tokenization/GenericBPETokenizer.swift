//
//  GenericBPETokenizer.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import Foundation

// MARK: - Generic BPE Tokenizer

/// Generic Byte-Pair Encoding tokenizer without model-specific logic
class GenericBPETokenizer: BaseTokenizer {
    private var merges: [(String, String)] = []
    private var vocab: [String: Int] = [:]

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
            // Direct vocab.json format
            vocab = vocabDict
            vocabulary = vocabDict
            for (token, id) in vocabDict {
                reverseVocabulary[id] = token
            }
        } else {
            throw TokenizerError.invalidVocabularyFormat
        }
    }

    private func loadMerges(from path: String) throws {
        let data = try String(contentsOfFile: path, encoding: .utf8)
        let lines = data.components(separatedBy: .newlines)

        // Skip any header lines (usually first line)
        let startIndex = lines.first?.contains(" ") == false ? 1 : 0

        for line in lines.dropFirst(startIndex) {
            let parts = line.components(separatedBy: " ")
            if parts.count == 2 {
                merges.append((parts[0], parts[1]))
            }
        }
    }

    override func encode(_ text: String) -> [Int] {
        // Generic BPE encoding without model-specific pre/post processing
        let tokens = tokenizeText(text)
        let bpeTokens = applyBPE(tokens)

        var tokenIds: [Int] = []
        for token in bpeTokens {
            if let id = vocab[token] {
                tokenIds.append(id)
            } else {
                // Unknown token fallback
                if let unkId = vocabulary["<unk>"] ?? vocabulary["[UNK]"] {
                    tokenIds.append(unkId)
                }
            }
        }

        return tokenIds
    }

    override func decode(_ tokens: [Int]) -> String {
        // Generic BPE decoding
        var decodedPieces: [String] = []

        for token in tokens {
            if let tokenStr = reverseVocabulary[token] {
                decodedPieces.append(tokenStr)
            }
        }

        return decodedPieces.joined()
    }

    private func tokenizeText(_ text: String) -> [String] {
        // Basic word-level tokenization
        // This is a simplified version - real implementations might use regex
        var tokens: [String] = []
        var currentToken = ""

        for char in text {
            if char.isWhitespace {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
                tokens.append(String(char))
            } else {
                currentToken.append(char)
            }
        }

        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }

        return tokens
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

// MARK: - Tokenizer Errors

enum TokenizerError: Error {
    case invalidVocabularyFormat
    case fileNotFound(String)
    case encodingError(String)
    case decodingError(String)
}
