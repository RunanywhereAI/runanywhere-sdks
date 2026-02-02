/**
 * @file bpe_tokenizer.h
 * @brief BPE (Byte Pair Encoding) Tokenizer for CLIP Text Encoder
 *
 * Implements a CLIP-compatible BPE tokenizer that loads vocab.json and merges.txt
 * from Hugging Face format. Used by the ONNX Diffusion backend for text encoding.
 *
 * Reference: OpenAI CLIP tokenizer implementation
 */

#ifndef RUNANYWHERE_BPE_TOKENIZER_H
#define RUNANYWHERE_BPE_TOKENIZER_H

#include <cstdint>
#include <functional>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace runanywhere {
namespace diffusion {

/**
 * @brief BPE Tokenizer for CLIP text encoding
 *
 * Implements the Byte Pair Encoding algorithm used by CLIP's text encoder.
 * Supports vocab.json and merges.txt loading from Hugging Face format.
 */
class BPETokenizer {
   public:
    // CLIP tokenizer constants
    static constexpr int MAX_SEQUENCE_LENGTH = 77;
    static constexpr int START_TOKEN_ID = 49406;  // <|startoftext|>
    static constexpr int END_TOKEN_ID = 49407;    // <|endoftext|>
    static constexpr int PAD_TOKEN_ID = 49407;    // Pad with end token

    BPETokenizer();
    ~BPETokenizer();

    /**
     * @brief Load tokenizer from vocab.json and merges.txt files
     * @param vocab_path Path to vocab.json file
     * @param merges_path Path to merges.txt file
     * @return true if loaded successfully
     */
    bool load(const std::string& vocab_path, const std::string& merges_path);

    /**
     * @brief Load tokenizer from a directory containing vocab.json and merges.txt
     * @param tokenizer_dir Directory containing tokenizer files
     * @return true if loaded successfully
     */
    bool load_from_directory(const std::string& tokenizer_dir);

    /**
     * @brief Check if tokenizer is loaded and ready
     */
    bool is_loaded() const { return loaded_; }

    /**
     * @brief Tokenize text into token IDs
     * @param text Input text to tokenize
     * @return Vector of token IDs (padded to MAX_SEQUENCE_LENGTH)
     */
    std::vector<int32_t> encode(const std::string& text);

    /**
     * @brief Tokenize text with custom max length
     * @param text Input text to tokenize
     * @param max_length Maximum sequence length
     * @return Vector of token IDs (padded to max_length)
     */
    std::vector<int32_t> encode(const std::string& text, int max_length);

    /**
     * @brief Decode token IDs back to text
     * @param tokens Vector of token IDs
     * @return Decoded text
     */
    std::string decode(const std::vector<int32_t>& tokens);

    /**
     * @brief Get vocabulary size
     */
    size_t vocab_size() const { return token_to_id_.size(); }

   private:
    // Internal types
    using TokenPair = std::pair<std::string, std::string>;

    // BPE algorithm implementation
    std::vector<std::string> bpe(const std::string& token);
    std::string bytes_to_unicode(uint8_t byte);
    std::string text_to_bytes(const std::string& text);

    // Vocabulary and merges
    std::unordered_map<std::string, int32_t> token_to_id_;
    std::unordered_map<int32_t, std::string> id_to_token_;
    std::unordered_map<std::string, int> bpe_ranks_;

    // Byte encoder/decoder (CLIP's byte-level BPE)
    std::unordered_map<uint8_t, std::string> byte_encoder_;
    std::unordered_map<std::string, uint8_t> byte_decoder_;

    // Cache for BPE results
    std::unordered_map<std::string, std::vector<std::string>> bpe_cache_;

    bool loaded_ = false;

    // Helper functions
    bool load_vocab(const std::string& vocab_path);
    bool load_merges(const std::string& merges_path);
    void init_byte_encoder();
    std::string clean_text(const std::string& text);
    std::vector<std::string> tokenize_to_words(const std::string& text);
    TokenPair get_min_pair(const std::vector<std::string>& word,
                          const std::unordered_map<TokenPair, int, 
                          std::function<size_t(const TokenPair&)>>& pairs);
};

}  // namespace diffusion
}  // namespace runanywhere

#endif  // RUNANYWHERE_BPE_TOKENIZER_H
