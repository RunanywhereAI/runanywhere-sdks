import Foundation

// MARK: - Tokenizer Configuration Models

/// Represents the configuration from a tokenizer.json file
struct TokenizerConfig: Codable {
    let version: String?
    let truncation: TruncationConfig?
    let padding: PaddingConfig?
    let addedTokens: [AddedToken]?
    let normalizer: NormalizerConfig?
    let preTokenizer: PreTokenizerConfig?
    let postProcessor: PostProcessorConfig?
    let decoder: DecoderConfig?
    let model: ModelConfig
    
    enum CodingKeys: String, CodingKey {
        case version
        case truncation
        case padding
        case addedTokens = "added_tokens"
        case normalizer
        case preTokenizer = "pre_tokenizer"
        case postProcessor = "post_processor"
        case decoder
        case model
    }
}

struct TruncationConfig: Codable {
    let maxLength: Int
    let strategy: String
    let direction: String?
    
    enum CodingKeys: String, CodingKey {
        case maxLength = "max_length"
        case strategy
        case direction
    }
}

struct PaddingConfig: Codable {
    let padId: Int?
    let padToken: String?
    let padToMultipleOf: Int?
    
    enum CodingKeys: String, CodingKey {
        case padId = "pad_id"
        case padToken = "pad_token"
        case padToMultipleOf = "pad_to_multiple_of"
    }
}

struct AddedToken: Codable {
    let id: Int
    let content: String
    let singleWord: Bool?
    let lstrip: Bool?
    let rstrip: Bool?
    let normalized: Bool?
    let special: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case content
        case singleWord = "single_word"
        case lstrip
        case rstrip
        case normalized
        case special
    }
}

struct NormalizerConfig: Codable {
    let type: String
}

struct PreTokenizerConfig: Codable {
    let type: String
    let addPrefixSpace: Bool?
    let trim_offsets: Bool?
    
    enum CodingKeys: String, CodingKey {
        case type
        case addPrefixSpace = "add_prefix_space"
        case trim_offsets
    }
}

struct PostProcessorConfig: Codable {
    let type: String
}

struct DecoderConfig: Codable {
    let type: String
}

struct ModelConfig: Codable {
    let type: String
    let vocab: [String: Int]?
    let merges: [String]?
    let unkToken: String?
    let continuingSubwordPrefix: String?
    let endOfWordSuffix: String?
    let fuseUnk: Bool?
    
    enum CodingKeys: String, CodingKey {
        case type
        case vocab
        case merges
        case unkToken = "unk_token"
        case continuingSubwordPrefix = "continuing_subword_prefix"
        case endOfWordSuffix = "end_of_word_suffix"
        case fuseUnk = "fuse_unk"
    }
}

// MARK: - Tokenizer Config Loader

class TokenizerConfigLoader {
    static func load(from path: String) throws -> TokenizerConfig {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(TokenizerConfig.self, from: data)
    }
    
    static func loadVocabulary(from path: String) throws -> [String: Int] {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        
        // Try to decode as JSON first
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
            return json
        }
        
        // Try text format (one token per line)
        let content = try String(contentsOf: url, encoding: .utf8)
        var vocab: [String: Int] = [:]
        
        content.enumerateLines { line, _ in
            let components = line.components(separatedBy: "\t")
            if components.count == 2,
               let index = Int(components[1]) {
                vocab[components[0]] = index
            } else {
                // Simple line-by-line format
                vocab[line] = vocab.count
            }
        }
        
        return vocab
    }
    
    static func loadMerges(from path: String) throws -> [(String, String)] {
        let url = URL(fileURLWithPath: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        var merges: [(String, String)] = []
        
        content.enumerateLines { line, _ in
            let components = line.components(separatedBy: " ")
            if components.count == 2 {
                merges.append((components[0], components[1]))
            }
        }
        
        return merges
    }
}

// MARK: - Special Tokens

struct SpecialTokens {
    let padToken: String
    let padTokenId: Int
    let bosToken: String
    let bosTokenId: Int
    let eosToken: String
    let eosTokenId: Int
    let unkToken: String
    let unkTokenId: Int
    let sepToken: String?
    let sepTokenId: Int?
    let clsToken: String?
    let clsTokenId: Int?
    let maskToken: String?
    let maskTokenId: Int?
    
    init(from config: TokenizerConfig) {
        // Extract special tokens from added_tokens
        var specialTokensMap: [String: Int] = [:]
        
        if let addedTokens = config.addedTokens {
            for token in addedTokens where token.special == true {
                specialTokensMap[token.content] = token.id
            }
        }
        
        // Common special token patterns
        self.padToken = specialTokensMap.keys.first { $0.contains("pad") } ?? "<pad>"
        self.padTokenId = specialTokensMap[padToken] ?? 0
        
        self.bosToken = specialTokensMap.keys.first { $0.contains("<s>") || $0.contains("bos") } ?? "<s>"
        self.bosTokenId = specialTokensMap[bosToken] ?? 1
        
        self.eosToken = specialTokensMap.keys.first { $0.contains("</s>") || $0.contains("eos") || $0.contains("endoftext") } ?? "</s>"
        self.eosTokenId = specialTokensMap[eosToken] ?? 2
        
        self.unkToken = config.model.unkToken ?? specialTokensMap.keys.first { $0.contains("unk") } ?? "<unk>"
        self.unkTokenId = specialTokensMap[unkToken] ?? 3
        
        self.sepToken = specialTokensMap.keys.first { $0.contains("[SEP]") || $0.contains("sep") }
        self.sepTokenId = sepToken.flatMap { specialTokensMap[$0] }
        
        self.clsToken = specialTokensMap.keys.first { $0.contains("[CLS]") || $0.contains("cls") }
        self.clsTokenId = clsToken.flatMap { specialTokensMap[$0] }
        
        self.maskToken = specialTokensMap.keys.first { $0.contains("[MASK]") || $0.contains("mask") }
        self.maskTokenId = maskToken.flatMap { specialTokensMap[$0] }
    }
}