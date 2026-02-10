/**
 * @file bpe_tokenizer.cpp
 * @brief BPE Tokenizer implementation for CLIP
 *
 * Implements CLIP-compatible BPE tokenization with vocab.json and merges.txt support.
 * Based on OpenAI CLIP tokenizer and Hugging Face transformers implementation.
 */

#include "bpe_tokenizer.h"

#include <algorithm>
#include <cctype>
#include <fstream>
#include <regex>
#include <sstream>
#include <stdexcept>

#include <nlohmann/json.hpp>

#include "rac/core/rac_logger.h"

namespace runanywhere {
namespace diffusion {

// =============================================================================
// CONSTRUCTION / DESTRUCTION
// =============================================================================

BPETokenizer::BPETokenizer() {
    init_byte_encoder();
}

BPETokenizer::~BPETokenizer() = default;

// =============================================================================
// LOADING
// =============================================================================

bool BPETokenizer::load(const std::string& vocab_path, const std::string& merges_path) {
    loaded_ = false;
    token_to_id_.clear();
    id_to_token_.clear();
    bpe_ranks_.clear();
    bpe_cache_.clear();

    if (!load_vocab(vocab_path)) {
        RAC_LOG_ERROR("BPETokenizer", "Failed to load vocab from: %s", vocab_path.c_str());
        return false;
    }

    if (!load_merges(merges_path)) {
        RAC_LOG_ERROR("BPETokenizer", "Failed to load merges from: %s", merges_path.c_str());
        return false;
    }

    loaded_ = true;
    RAC_LOG_INFO("BPETokenizer", "Loaded tokenizer with %zu tokens", token_to_id_.size());
    return true;
}

bool BPETokenizer::load_from_directory(const std::string& tokenizer_dir) {
    std::string vocab_path = tokenizer_dir + "/vocab.json";
    std::string merges_path = tokenizer_dir + "/merges.txt";
    return load(vocab_path, merges_path);
}

bool BPETokenizer::load_vocab(const std::string& vocab_path) {
    std::ifstream file(vocab_path);
    if (!file.is_open()) {
        return false;
    }

    try {
        nlohmann::json vocab_json;
        file >> vocab_json;

        for (auto& [token, id] : vocab_json.items()) {
            int32_t token_id = id.get<int32_t>();
            token_to_id_[token] = token_id;
            id_to_token_[token_id] = token;
        }
        return true;
    } catch (const std::exception& e) {
        RAC_LOG_ERROR("BPETokenizer", "Error parsing vocab.json: %s", e.what());
        return false;
    }
}

bool BPETokenizer::load_merges(const std::string& merges_path) {
    std::ifstream file(merges_path);
    if (!file.is_open()) {
        return false;
    }

    std::string line;
    int rank = 0;

    // Skip header line if present (starts with #)
    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#') {
            continue;
        }

        // Each line is "token1 token2" representing a merge
        std::istringstream iss(line);
        std::string token1, token2;
        if (iss >> token1 >> token2) {
            std::string key = token1 + " " + token2;
            bpe_ranks_[key] = rank++;
        }
    }

    RAC_LOG_DEBUG("BPETokenizer", "Loaded %d merge rules", rank);
    return true;
}

// =============================================================================
// BYTE ENCODER (CLIP's byte-level BPE)
// =============================================================================

void BPETokenizer::init_byte_encoder() {
    // CLIP uses a byte-to-unicode mapping for byte-level BPE
    // This maps each byte value to a unicode character
    
    std::vector<int> bs;
    std::vector<int> cs;

    // Printable ASCII characters
    for (int i = '!'; i <= '~'; ++i) {
        bs.push_back(i);
        cs.push_back(i);
    }
    // Extended Latin characters
    for (int i = 161; i <= 172; ++i) {  // ¡ to ¬
        bs.push_back(i);
        cs.push_back(i);
    }
    for (int i = 174; i <= 255; ++i) {  // ® to ÿ
        bs.push_back(i);
        cs.push_back(i);
    }

    // Map remaining bytes to higher unicode codepoints
    int n = 0;
    for (int b = 0; b < 256; ++b) {
        if (std::find(bs.begin(), bs.end(), b) == bs.end()) {
            bs.push_back(b);
            cs.push_back(256 + n);
            n++;
        }
    }

    // Create encoder/decoder maps
    // Values in cs can be >= 128, so encode as proper UTF-8 to avoid truncation.
    for (size_t i = 0; i < bs.size(); ++i) {
        int cp = cs[i];
        std::string s;
        if (cp < 0x80) {
            s.push_back(static_cast<char>(cp));
        } else if (cp < 0x800) {
            s.push_back(static_cast<char>(0xC0 | (cp >> 6)));
            s.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        } else {
            s.push_back(static_cast<char>(0xE0 | (cp >> 12)));
            s.push_back(static_cast<char>(0x80 | ((cp >> 6) & 0x3F)));
            s.push_back(static_cast<char>(0x80 | (cp & 0x3F)));
        }
        byte_encoder_[static_cast<uint8_t>(bs[i])] = s;
        byte_decoder_[s] = static_cast<uint8_t>(bs[i]);
    }
}

std::string BPETokenizer::bytes_to_unicode(uint8_t byte) {
    auto it = byte_encoder_.find(byte);
    if (it != byte_encoder_.end()) {
        return it->second;
    }
    return "";
}

std::string BPETokenizer::text_to_bytes(const std::string& text) {
    std::string result;
    for (unsigned char c : text) {
        result += bytes_to_unicode(c);
    }
    return result;
}

// =============================================================================
// TEXT PREPROCESSING
// =============================================================================

std::string BPETokenizer::clean_text(const std::string& text) {
    // Convert to lowercase and normalize whitespace
    std::string result;
    result.reserve(text.size());
    
    for (char c : text) {
        if (c == '\n' || c == '\r' || c == '\t') {
            result += ' ';
        } else {
            result += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
        }
    }
    
    // Remove extra whitespace
    std::string cleaned;
    bool prev_space = true;
    for (char c : result) {
        if (c == ' ') {
            if (!prev_space) {
                cleaned += c;
                prev_space = true;
            }
        } else {
            cleaned += c;
            prev_space = false;
        }
    }
    
    // Trim trailing space
    if (!cleaned.empty() && cleaned.back() == ' ') {
        cleaned.pop_back();
    }
    
    return cleaned;
}

std::vector<std::string> BPETokenizer::tokenize_to_words(const std::string& text) {
    // CLIP's regex pattern for tokenization
    // Matches: 's, 't, 're, 've, 'm, 'll, 'd, words, numbers, non-word non-space sequences
    std::regex pattern(R"(<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[a-zA-Z]+|[0-9]+|[^\s\w]+)");
    
    std::vector<std::string> words;
    std::string cleaned = clean_text(text);
    
    auto words_begin = std::sregex_iterator(cleaned.begin(), cleaned.end(), pattern);
    auto words_end = std::sregex_iterator();
    
    for (auto it = words_begin; it != words_end; ++it) {
        std::string word = it->str();
        // Add space prefix for non-special tokens (CLIP convention)
        if (word != "<|startoftext|>" && word != "<|endoftext|>") {
            word = " " + word;  // CLIP adds leading space via Ġ encoding
        }
        // Convert to byte representation
        std::string byte_word = text_to_bytes(word);
        if (!byte_word.empty()) {
            words.push_back(byte_word);
        }
    }
    
    return words;
}

// =============================================================================
// BPE ALGORITHM
// =============================================================================

std::vector<std::string> BPETokenizer::bpe(const std::string& token) {
    // Check cache
    auto cache_it = bpe_cache_.find(token);
    if (cache_it != bpe_cache_.end()) {
        return cache_it->second;
    }

    // Initialize word as individual characters
    std::vector<std::string> word;
    for (size_t i = 0; i < token.size(); ++i) {
        word.push_back(std::string(1, token[i]));
    }
    
    // Add end-of-word marker (</w>) to last character
    if (!word.empty()) {
        word.back() += "</w>";
    }

    if (word.size() <= 1) {
        bpe_cache_[token] = word;
        return word;
    }

    // Iteratively merge most frequent pairs
    while (true) {
        // Find all adjacent pairs and their ranks
        int min_rank = INT_MAX;
        std::pair<int, int> min_pair_idx = {-1, -1};
        
        for (size_t i = 0; i < word.size() - 1; ++i) {
            std::string pair_key = word[i] + " " + word[i + 1];
            auto rank_it = bpe_ranks_.find(pair_key);
            if (rank_it != bpe_ranks_.end() && rank_it->second < min_rank) {
                min_rank = rank_it->second;
                min_pair_idx = {static_cast<int>(i), static_cast<int>(i + 1)};
            }
        }

        // No more merges possible
        if (min_pair_idx.first == -1) {
            break;
        }

        // Merge the pair with minimum rank
        std::vector<std::string> new_word;
        size_t i = 0;
        while (i < word.size()) {
            if (static_cast<int>(i) == min_pair_idx.first) {
                new_word.push_back(word[i] + word[i + 1]);
                i += 2;
            } else {
                new_word.push_back(word[i]);
                i += 1;
            }
        }
        word = std::move(new_word);

        if (word.size() == 1) {
            break;
        }
    }

    bpe_cache_[token] = word;
    return word;
}

// =============================================================================
// ENCODING / DECODING
// =============================================================================

std::vector<int32_t> BPETokenizer::encode(const std::string& text) {
    return encode(text, MAX_SEQUENCE_LENGTH);
}

std::vector<int32_t> BPETokenizer::encode(const std::string& text, int max_length) {
    if (!loaded_) {
        RAC_LOG_ERROR("BPETokenizer", "Tokenizer not loaded");
        return std::vector<int32_t>(max_length, PAD_TOKEN_ID);
    }

    std::vector<int32_t> tokens;
    tokens.push_back(START_TOKEN_ID);

    // Tokenize text into words
    std::vector<std::string> words = tokenize_to_words(text);

    // Apply BPE to each word and convert to token IDs
    for (const auto& word : words) {
        std::vector<std::string> bpe_tokens = bpe(word);
        for (const auto& bpe_token : bpe_tokens) {
            auto it = token_to_id_.find(bpe_token);
            if (it != token_to_id_.end()) {
                tokens.push_back(it->second);
            } else {
                // Handle unknown tokens - try without </w>
                std::string clean_token = bpe_token;
                if (clean_token.size() > 4 && clean_token.substr(clean_token.size() - 4) == "</w>") {
                    clean_token = clean_token.substr(0, clean_token.size() - 4);
                }
                auto clean_it = token_to_id_.find(clean_token);
                if (clean_it != token_to_id_.end()) {
                    tokens.push_back(clean_it->second);
                }
                // Skip unknown tokens silently
            }
        }
        
        // Stop if we're getting close to max length
        if (tokens.size() >= static_cast<size_t>(max_length - 1)) {
            break;
        }
    }

    // Add end token
    tokens.push_back(END_TOKEN_ID);

    // Truncate if too long
    if (tokens.size() > static_cast<size_t>(max_length)) {
        tokens.resize(max_length);
        tokens.back() = END_TOKEN_ID;
    }

    // Pad to max_length
    while (tokens.size() < static_cast<size_t>(max_length)) {
        tokens.push_back(PAD_TOKEN_ID);
    }

    return tokens;
}

std::string BPETokenizer::decode(const std::vector<int32_t>& tokens) {
    if (!loaded_) {
        return "";
    }

    std::string result;
    for (int32_t token_id : tokens) {
        // Skip special tokens
        if (token_id == START_TOKEN_ID || token_id == END_TOKEN_ID || 
            token_id == PAD_TOKEN_ID) {
            continue;
        }

        auto it = id_to_token_.find(token_id);
        if (it != id_to_token_.end()) {
            std::string token = it->second;
            // Remove </w> marker
            if (token.size() > 4 && token.substr(token.size() - 4) == "</w>") {
                token = token.substr(0, token.size() - 4);
            }
            // Convert byte representation back to text
            for (char c : token) {
                std::string s(1, c);
                auto byte_it = byte_decoder_.find(s);
                if (byte_it != byte_decoder_.end()) {
                    result += static_cast<char>(byte_it->second);
                } else {
                    result += c;
                }
            }
        }
    }

    return result;
}

}  // namespace diffusion
}  // namespace runanywhere
