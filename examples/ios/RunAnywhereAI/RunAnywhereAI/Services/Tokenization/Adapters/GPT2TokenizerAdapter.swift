//
//  GPT2TokenizerAdapter.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import Foundation

// MARK: - GPT-2 Tokenizer Adapter

class GPT2TokenizerAdapter: TokenizerAdapter {
    let tokenizer: Tokenizer
    let modelType = "gpt2"
    
    // GPT-2 specific configuration
    private let gpt2VocabSize = 50257
    private let gpt2BosToken = 50256
    private let gpt2EosToken = 50256
    private let gpt2PadToken = 50256
    
    init(tokenizer: Tokenizer) {
        self.tokenizer = tokenizer
    }
    
    func encode(_ text: String) -> [Int] {
        // GPT-2 doesn't use BOS/EOS tokens during encoding
        let encoded = tokenizer.encode(text)
        // Remove any BOS/EOS tokens that the base tokenizer might have added
        return encoded.filter { $0 != tokenizer.bosToken && $0 != tokenizer.eosToken }
    }
    
    func decode(_ tokens: [Int]) -> String {
        // GPT-2 specific decoding
        return decodeGPT2Tokens(tokens)
    }
    
    func decodeToken(_ token: Int) -> String {
        // Decode single token for streaming
        return decodeGPT2Tokens([token])
    }
    
    private func decodeGPT2Tokens(_ tokens: [Int]) -> String {
        // Get raw token strings from vocabulary
        var tokenStrings: [String] = []
        
        for token in tokens {
            // Skip special tokens
            if token == gpt2BosToken || token == gpt2EosToken || token == gpt2PadToken {
                continue
            }
            
            // Try to get token string from tokenizer
            if let bpeTokenizer = tokenizer as? BPETokenizer,
               let tokenStr = bpeTokenizer.reverseVocabulary[token] ?? 
                             bpeTokenizer.vocab.first(where: { $0.value == token })?.key {
                tokenStrings.append(tokenStr)
            } else {
                // Fallback to base tokenizer decode
                let decoded = tokenizer.decode([token])
                if !decoded.isEmpty {
                    tokenStrings.append(decoded)
                }
            }
        }
        
        // GPT-2 specific post-processing
        var result = tokenStrings.joined()
        
        // Handle GPT-2 byte-level BPE decoding
        result = decodeBytes(result)
        
        // Replace GPT-2 space token
        result = result.replacingOccurrences(of: "Ġ", with: " ")
        
        // Clean up any remaining artifacts
        result = result.replacingOccurrences(of: "Ċ", with: "\n")
        result = result.replacingOccurrences(of: "č", with: "\n")
        
        return result
    }
    
    private func decodeBytes(_ text: String) -> String {
        // GPT-2 uses a specific byte-to-unicode mapping
        let byteDecoder = createByteDecoder()
        
        var result = ""
        for char in text {
            if let mappedByte = byteDecoder[String(char)] {
                result += String(bytes: [UInt8(mappedByte)], encoding: .utf8) ?? String(char)
            } else {
                result += String(char)
            }
        }
        
        return result
    }
    
    private func createByteDecoder() -> [String: Int] {
        // GPT-2 byte decoder mapping
        var decoder: [String: Int] = [:]
        
        // Create the standard GPT-2 byte mapping
        let bytes = Array(0...255)
        var n = 0
        
        for b in bytes {
            // Printable ASCII range and extended ASCII
            if (b >= 33 && b <= 126) || (b >= 161 && b <= 172) || (b >= 174 && b <= 255) {
                decoder[String(UnicodeScalar(b)!)] = b
            } else {
                // Map non-printable bytes to unicode points starting at 256
                decoder[String(UnicodeScalar(256 + n)!)] = b
                n += 1
            }
        }
        
        return decoder
    }
    
    var vocabularySize: Int {
        return gpt2VocabSize
    }
    
    var bosToken: Int {
        return gpt2BosToken
    }
    
    var eosToken: Int {
        return gpt2EosToken
    }
    
    var padToken: Int {
        return gpt2PadToken
    }
    
    func isCompatible(with modelPath: String) -> Bool {
        // Check for GPT-2 specific files or naming
        let path = modelPath.lowercased()
        return path.contains("gpt2") || path.contains("gpt-2") ||
               (FileManager.default.fileExists(atPath: "\(modelPath)/gpt2-vocab.json") &&
                FileManager.default.fileExists(atPath: "\(modelPath)/gpt2-merges.txt"))
    }
    
    // MARK: - Factory Method
    
    static func create(from modelPath: String) -> GPT2TokenizerAdapter? {
        // Try to load GPT-2 tokenizer files
        let fileManager = FileManager.default
        
        // Check for GPT-2 specific tokenizer files
        let vocabPaths = [
            "\(modelPath)/gpt2-vocab.json",
            "\(modelPath)/vocab.json"
        ]
        
        let mergesPaths = [
            "\(modelPath)/gpt2-merges.txt",
            "\(modelPath)/merges.txt"
        ]
        
        var vocabPath: String?
        var mergesPath: String?
        
        // Find available vocab file
        for path in vocabPaths {
            if fileManager.fileExists(atPath: path) {
                vocabPath = path
                break
            }
        }
        
        // Find available merges file
        for path in mergesPaths {
            if fileManager.fileExists(atPath: path) {
                mergesPath = path
                break
            }
        }
        
        // Create tokenizer if both files found
        if let vocab = vocabPath, let merges = mergesPath {
            do {
                let tokenizer = try BPETokenizer(vocabPath: vocab, mergesPath: merges)
                print("Created GPT-2 tokenizer adapter with vocab: \(vocab)")
                return GPT2TokenizerAdapter(tokenizer: tokenizer)
            } catch {
                print("Failed to create GPT-2 tokenizer: \(error)")
            }
        }
        
        return nil
    }
}