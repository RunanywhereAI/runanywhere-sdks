/**
 * @file onnx_embedding_provider.cpp
 * @brief ONNX embedding provider implementation
 */

#include "onnx_embedding_provider.h"
#include "rac/features/rag/ort_guards.h"
#include "rac/core/rac_logger.h"
#include "../../backends/onnx/onnx_backend.h"

#include <nlohmann/json.hpp>
#include <onnxruntime_c_api.h>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <cctype>
#include <unordered_map>
#include <list>
#include <mutex>

#if defined(__aarch64__) && defined(__ARM_NEON)
#include <arm_neon.h>
#endif

#define LOG_TAG "RAG.ONNXEmbedding"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)
#define LOGW(...) RAC_LOG_WARNING(LOG_TAG, __VA_ARGS__)

namespace runanywhere {
namespace rag {

// =============================================================================
// SIMPLE TOKENIZER (Word-level for MVP)
// =============================================================================

class SimpleTokenizer {
public:
    SimpleTokenizer() {
        // Special tokens (defaults; may be overridden by vocab load)
        token_to_id_["[CLS]"] = 101;
        token_to_id_["[SEP]"] = 102;
        token_to_id_["[PAD]"] = 0;
        token_to_id_["[UNK]"] = 100;
        cls_id_ = 101;
        sep_id_ = 102;
        pad_id_ = 0;
        unk_id_ = 100;
    }

    bool load_vocab(const std::string& vocab_path) {
        std::ifstream file(vocab_path);
        if (!file) {
            return false;
        }

        token_to_id_.clear();

        std::string line;
        int64_t id = 0;
        while (std::getline(file, line)) {
            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            token_to_id_[line] = id++;
        }

        if (token_to_id_.empty()) {
            return false;
        }

        vocab_loaded_ = true;

        // Refresh special token IDs if present in vocab
        cls_id_ = get_token_id("[CLS]", cls_id_);
        sep_id_ = get_token_id("[SEP]", sep_id_);
        pad_id_ = get_token_id("[PAD]", pad_id_);
        unk_id_ = get_token_id("[UNK]", unk_id_);

        return true;
    }
    
    std::vector<int64_t> encode_unpadded(const std::string& text, size_t max_length = 512) {
        std::vector<int64_t> token_ids;
        token_ids.reserve(std::min(max_length, static_cast<size_t>(128)));
        token_ids.push_back(cls_id_); // [CLS]

        const auto words = basic_tokenize(text);
        for (const auto& word : words) {
            if (token_ids.size() >= max_length - 1) {
                break;
            }

            const auto ids = word_to_token_ids(word);
            for (const auto id : ids) {
                if (token_ids.size() >= max_length - 1) {
                    break;
                }
                token_ids.push_back(id);
            }
        }

        token_ids.push_back(sep_id_); // [SEP]
        return token_ids;
    }

    void pad_to(std::vector<int64_t>& token_ids, size_t target_length) {
        while (token_ids.size() < target_length) {
            token_ids.push_back(pad_id_);
        }
    }

    std::vector<int64_t> encode(const std::string& text, size_t max_length = 512) {
        auto token_ids = encode_unpadded(text, max_length);
        pad_to(token_ids, max_length);
        return token_ids;
    }
    
    std::vector<int64_t> create_attention_mask(const std::vector<int64_t>& token_ids) {
        std::vector<int64_t> mask;
        for (auto id : token_ids) {
            mask.push_back(id != 0 ? 1 : 0); // 1 for real tokens, 0 for padding
        }
        return mask;
    }
    
    std::vector<int64_t> create_token_type_ids(size_t length) {
        // Token type IDs: all 0s for single sequence models like all-MiniLM
        return std::vector<int64_t>(length, 0);
    }

private:
    static inline bool is_all_ascii(const std::string& text) {
        for (unsigned char ch : text) {
            if (ch & 0x80) {
                return false;
            }
        }
        return true;
    }

    static inline bool is_ascii_alnum(unsigned char ch) {
        return (ch >= 'A' && ch <= 'Z') ||
               (ch >= 'a' && ch <= 'z') ||
               (ch >= '0' && ch <= '9');
    }

    static inline char to_lower_ascii(unsigned char ch) {
        if (ch >= 'A' && ch <= 'Z') {
            return static_cast<char>(ch + ('a' - 'A'));
        }
        return static_cast<char>(ch);
    }

    std::vector<std::string> basic_tokenize(const std::string& text) const {
        const bool all_ascii = is_all_ascii(text);
#if defined(__aarch64__) && defined(__ARM_NEON)
        if (all_ascii) {
            return basic_tokenize_simd_ascii(text);
        }
        return basic_tokenize_scalar_mixed(text);
#else
        if (all_ascii) {
            return basic_tokenize_scalar_ascii(text);
        }
        return basic_tokenize_scalar_mixed(text);
#endif
    }

    std::vector<std::string> basic_tokenize_scalar_ascii(const std::string& text) const {
        std::vector<std::string> tokens;
        std::string current;
        current.reserve(text.size());

        for (unsigned char ch : text) {
            if (!is_ascii_alnum(ch)) {
                if (!current.empty()) {
                    tokens.push_back(std::move(current));
                    current.clear();
                }
                continue;
            }
            current.push_back(to_lower_ascii(ch));
        }

        if (!current.empty()) {
            tokens.push_back(std::move(current));
        }

        return tokens;
    }

    std::vector<std::string> basic_tokenize_scalar_mixed(const std::string& text) const {
        std::vector<std::string> tokens;
        std::string current;
        current.reserve(text.size());

        for (unsigned char ch : text) {
            if (ch & 0x80) {
                if (!current.empty()) {
                    tokens.push_back(std::move(current));
                    current.clear();
                }
                continue;
            }

            if (!is_ascii_alnum(ch)) {
                if (!current.empty()) {
                    tokens.push_back(std::move(current));
                    current.clear();
                }
                continue;
            }

            current.push_back(to_lower_ascii(ch));
        }

        if (!current.empty()) {
            tokens.push_back(std::move(current));
        }

        return tokens;
    }

#if defined(__aarch64__) && defined(__ARM_NEON)
    std::vector<std::string> basic_tokenize_simd_ascii(const std::string& text) const {
        std::vector<std::string> tokens;
        std::string current;
        current.reserve(text.size());

        const char* data = text.data();
        size_t length = text.size();
        size_t i = 0;

        const uint8x16_t a_upper = vdupq_n_u8('A');
        const uint8x16_t z_upper = vdupq_n_u8('Z');
        const uint8x16_t a_lower = vdupq_n_u8('a');
        const uint8x16_t z_lower = vdupq_n_u8('z');
        const uint8x16_t zero_digit = vdupq_n_u8('0');
        const uint8x16_t nine_digit = vdupq_n_u8('9');
        const uint8x16_t lower_mask = vdupq_n_u8(0x20);

        while (i + 16 <= length) {
            uint8x16_t v = vld1q_u8(reinterpret_cast<const uint8_t*>(data + i));

            uint8x16_t geA = vcgeq_u8(v, a_upper);
            uint8x16_t leZ = vcleq_u8(v, z_upper);
            uint8x16_t is_upper = vandq_u8(geA, leZ);

            uint8x16_t gea = vcgeq_u8(v, a_lower);
            uint8x16_t lez = vcleq_u8(v, z_lower);
            uint8x16_t is_lower = vandq_u8(gea, lez);

            uint8x16_t ge0 = vcgeq_u8(v, zero_digit);
            uint8x16_t le9 = vcleq_u8(v, nine_digit);
            uint8x16_t is_digit = vandq_u8(ge0, le9);

            uint8x16_t is_alnum = vorrq_u8(vorrq_u8(is_upper, is_lower), is_digit);
            const bool all_alnum = vminvq_u8(is_alnum) == 0xFF;

            if (all_alnum) {
                uint8x16_t lower = vaddq_u8(v, vandq_u8(is_upper, lower_mask));
                alignas(16) char buffer[16];
                vst1q_u8(reinterpret_cast<uint8_t*>(buffer), lower);
                current.append(buffer, 16);
            } else {
                for (size_t j = 0; j < 16; ++j) {
                    unsigned char ch = static_cast<unsigned char>(data[i + j]);
                    if (!is_ascii_alnum(ch)) {
                        if (!current.empty()) {
                            tokens.push_back(std::move(current));
                            current.clear();
                        }
                        continue;
                    }
                    current.push_back(to_lower_ascii(ch));
                }
            }

            i += 16;
        }

        for (; i < length; ++i) {
            unsigned char ch = static_cast<unsigned char>(data[i]);
            if (!is_ascii_alnum(ch)) {
                if (!current.empty()) {
                    tokens.push_back(std::move(current));
                    current.clear();
                }
                continue;
            }
            current.push_back(to_lower_ascii(ch));
        }

        if (!current.empty()) {
            tokens.push_back(std::move(current));
        }

        return tokens;
    }
#endif

    std::vector<std::string> wordpiece_tokenize(const std::string& word) const {
        if (!vocab_loaded_) {
            return {word};
        }

        if (token_to_id_.find(word) != token_to_id_.end()) {
            return {word};
        }

        std::vector<std::string> pieces;
        size_t start = 0;
        while (start < word.size()) {
            size_t end = word.size();
            std::string current_piece;
            bool found = false;

            while (start < end) {
                std::string substr = word.substr(start, end - start);
                if (start > 0) {
                    substr.insert(0, "##");
                }

                if (token_to_id_.find(substr) != token_to_id_.end()) {
                    current_piece = std::move(substr);
                    found = true;
                    break;
                }
                end--;
            }

            if (!found) {
                return {"[UNK]"};
            }

            pieces.push_back(std::move(current_piece));
            start = end;
        }

        return pieces;
    }

    std::vector<int64_t> word_to_token_ids(const std::string& word) {
        auto it = token_cache_.find(word);
        if (it != token_cache_.end()) {
            touch_cache_entry(it->second.lru_it);
            return it->second.ids;
        }

        const auto pieces = wordpiece_tokenize(word);
        std::vector<int64_t> ids;
        ids.reserve(pieces.size());
        for (const auto& piece : pieces) {
            ids.push_back(token_id_for(piece));
        }

        insert_cache_entry(word, ids);
        return ids;
    }

    int64_t token_id_for(const std::string& token) const {
        auto it = token_to_id_.find(token);
        if (it != token_to_id_.end()) {
            return it->second;
        }

        if (vocab_loaded_) {
            return unk_id_;
        }

        // Hash-based fallback when vocab is unavailable
        size_t hash = std::hash<std::string>{}(token);
        constexpr int64_t kVocabSize = 30522;
        constexpr int64_t kMinId = 1000;
        constexpr int64_t kMaxId = kVocabSize - 1;
        const int64_t range = kMaxId - kMinId + 1;
        return static_cast<int64_t>(hash % static_cast<size_t>(range)) + kMinId;
    }

    int64_t get_token_id(const std::string& token, int64_t fallback) const {
        auto it = token_to_id_.find(token);
        return it != token_to_id_.end() ? it->second : fallback;
    }

    struct CacheEntry {
        std::vector<int64_t> ids;
        std::list<std::string>::iterator lru_it;
    };

    void touch_cache_entry(std::list<std::string>::iterator it) {
        lru_list_.splice(lru_list_.begin(), lru_list_, it);
    }

    void insert_cache_entry(const std::string& word, const std::vector<int64_t>& ids) {
        if (token_cache_.size() >= token_cache_limit_ && !lru_list_.empty()) {
            const std::string& lru_key = lru_list_.back();
            token_cache_.erase(lru_key);
            lru_list_.pop_back();
        }

        lru_list_.push_front(word);
        token_cache_.emplace(word, CacheEntry{ids, lru_list_.begin()});
    }

    std::unordered_map<std::string, int64_t> token_to_id_;
    int64_t cls_id_ = 101;
    int64_t sep_id_ = 102;
    int64_t pad_id_ = 0;
    int64_t unk_id_ = 100;
    bool vocab_loaded_ = false;
    std::unordered_map<std::string, CacheEntry> token_cache_;
    std::list<std::string> lru_list_;
    std::size_t token_cache_limit_ = 4096;
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

// Mean pooling: average all token embeddings (excluding padding)
std::vector<float> mean_pooling(
    const float* embeddings,
    const std::vector<int64_t>& attention_mask,
    size_t seq_length,
    size_t hidden_dim
) {
    std::vector<float> pooled(hidden_dim, 0.0f);
    int valid_tokens = 0;
    
    for (size_t i = 0; i < seq_length; ++i) {
        if (attention_mask[i] == 1) {
            for (size_t j = 0; j < hidden_dim; ++j) {
                pooled[j] += embeddings[i * hidden_dim + j];
            }
            valid_tokens++;
        }
    }
    
    // Average
    if (valid_tokens > 0) {
        for (size_t j = 0; j < hidden_dim; ++j) {
            pooled[j] /= static_cast<float>(valid_tokens);
        }
    }
    
    return pooled;
}

// Normalize vector to unit length (L2 normalization)
void normalize_vector(std::vector<float>& vec) {
    float sum_squared = 0.0f;
    for (float val : vec) {
        sum_squared += val * val;
    }
    
    float norm = std::sqrt(sum_squared);
    if (norm > 1e-8f) {
        for (float& val : vec) {
            val /= norm;
        }
    }
}

// =============================================================================
// PIMPL IMPLEMENTATION
// =============================================================================

class ONNXEmbeddingProvider::Impl {
public:
    explicit Impl(const std::string& model_path, const std::string& config_json)
        : model_path_(model_path) {

        // Parse config
        if (!config_json.empty()) {
            try {
                config_ = nlohmann::json::parse(config_json);
            } catch (const std::exception& e) {
                LOGE("Failed to parse config JSON: %s", e.what());
            }
        }

        // Initialize ONNX Runtime
        if (!initialize_onnx_runtime()) {
            LOGE("Failed to initialize ONNX Runtime");
            return;
        }

        OrtStatus* mem_status = ort_api_->CreateCpuMemoryInfo(
            OrtArenaAllocator, OrtMemTypeDefault, &memory_info_);
        if (mem_status != nullptr) {
            const char* error_msg = ort_api_->GetErrorMessage(mem_status);
            LOGE("CreateCpuMemoryInfo failed: %s", error_msg);
            ort_api_->ReleaseStatus(mem_status);
            return;
        }

        input_ids_buf_.resize(max_seq_length_, 0);
        attention_mask_buf_.resize(max_seq_length_, 0);
        token_type_ids_buf_.resize(max_seq_length_, 0);
        input_shape_ = {1, static_cast<int64_t>(max_seq_length_)};

        // Load tokenizer vocab if provided
        std::string vocab_path;
        if (config_.contains("vocab_path")) {
            vocab_path = config_.at("vocab_path").get<std::string>();
        } else if (config_.contains("vocabPath")) {
            vocab_path = config_.at("vocabPath").get<std::string>();
        } else {
            std::filesystem::path model_file(model_path_);
            if (std::filesystem::is_directory(model_file)) {
                vocab_path = (model_file / "vocab.txt").string();
            } else {
                vocab_path = (model_file.parent_path() / "vocab.txt").string();
            }
        }

        if (vocab_path.empty() || !std::filesystem::exists(vocab_path)) {
            LOGE("Tokenizer vocab not found: %s", vocab_path.c_str());
            return;
        }

        if (!tokenizer_.load_vocab(vocab_path)) {
            LOGE("Failed to load tokenizer vocab: %s", vocab_path.c_str());
            return;
        }

        LOGI("Loaded tokenizer vocab: %s", vocab_path.c_str());

        std::string resolved_model_path = model_path;
        if (std::filesystem::is_directory(resolved_model_path)) {
            resolved_model_path = (std::filesystem::path(resolved_model_path) / "model.onnx").string();
        }

        // Load model
        if (!load_model(resolved_model_path)) {
            LOGE("Failed to load model: %s", resolved_model_path.c_str());
            return;
        }

        ready_ = true;
        LOGI("ONNX embedding provider initialized: %s", model_path.c_str());
        LOGI("  Hidden dimension: %zu", embedding_dim_);
    }

    ~Impl() {
        cleanup();
    }

    std::vector<float> embed(const std::string& text) {
        if (!ready_) {
            LOGE("Embedding provider not ready");
            return {};
        }

        std::lock_guard<std::mutex> lock(embed_mutex_);

        try {
            auto token_ids = tokenizer_.encode_unpadded(text, max_seq_length_);
            const size_t pad_length = align_up(token_ids.size(), 8);
            tokenizer_.pad_to(token_ids, pad_length);

            auto attention_mask = tokenizer_.create_attention_mask(token_ids);

            std::memcpy(input_ids_buf_.data(), token_ids.data(), pad_length * sizeof(int64_t));
            std::memcpy(attention_mask_buf_.data(), attention_mask.data(), pad_length * sizeof(int64_t));
            std::memset(token_type_ids_buf_.data(), 0, pad_length * sizeof(int64_t));

            input_shape_ = {1, static_cast<int64_t>(pad_length)};

            LOGI("Single embed: %zu real tokens, padded to %zu (max %zu)",
                 token_ids.size() - std::count(token_ids.begin(), token_ids.end(), 0),
                 pad_length, max_seq_length_);

            OrtStatusGuard status_guard(ort_api_);
            OrtValueGuard input_ids_guard(ort_api_);
            OrtValueGuard attention_mask_guard(ort_api_);
            OrtValueGuard token_type_ids_guard(ort_api_);

            // Create input_ids tensor
            status_guard.reset(ort_api_->CreateTensorWithDataAsOrtValue(
                memory_info_,
                input_ids_buf_.data(),
                pad_length * sizeof(int64_t),
                input_shape_.data(),
                input_shape_.size(),
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                input_ids_guard.ptr()
            ));
            if (status_guard.is_error()) {
                LOGE("CreateTensorWithDataAsOrtValue (input_ids) failed: %s", status_guard.error_message());
                return {};
            }

            // Create attention_mask tensor
            status_guard.reset(ort_api_->CreateTensorWithDataAsOrtValue(
                memory_info_,
                attention_mask_buf_.data(),
                pad_length * sizeof(int64_t),
                input_shape_.data(),
                input_shape_.size(),
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                attention_mask_guard.ptr()
            ));
            if (status_guard.is_error()) {
                LOGE("CreateTensorWithDataAsOrtValue (attention_mask) failed: %s", status_guard.error_message());
                return {};
            }

            // Create token_type_ids tensor
            status_guard.reset(ort_api_->CreateTensorWithDataAsOrtValue(
                memory_info_,
                token_type_ids_buf_.data(),
                pad_length * sizeof(int64_t),
                input_shape_.data(),
                input_shape_.size(),
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                token_type_ids_guard.ptr()
            ));
            if (status_guard.is_error()) {
                LOGE("CreateTensorWithDataAsOrtValue (token_type_ids) failed: %s", status_guard.error_message());
                return {};
            }
            
            // 3. Run inference
            const char* input_names[] = {"input_ids", "attention_mask", "token_type_ids"};
            const OrtValue* inputs[] = {input_ids_guard.get(), attention_mask_guard.get(), token_type_ids_guard.get()};
            const char* output_names[] = {"last_hidden_state"};
            OrtValueGuard output_guard(ort_api_);
            OrtValue* output_ptr = nullptr;
            
            status_guard.reset(ort_api_->Run(
                session_,
                nullptr,
                input_names,
                inputs,
                3,
                output_names,
                1,
                &output_ptr
            ));
            
            if (status_guard.is_error()) {
                LOGE("ONNX inference failed: %s", status_guard.error_message());
                return {};
            }
            
            // Transfer ownership to guard for automatic cleanup
            *output_guard.ptr() = output_ptr;
            
            // 4. Extract output embeddings
            float* output_data = nullptr;
            OrtStatusGuard output_status_guard(ort_api_);
            output_status_guard.reset(ort_api_->GetTensorMutableData(output_guard.get(), (void**)&output_data));
            
            if (output_status_guard.is_error()) {
                LOGE("Failed to get output tensor data: %s", output_status_guard.error_message());
                return {};
            }

            if (output_data == nullptr) {
                LOGE("Output tensor data pointer is null");
                return {};
            }

            OrtTensorTypeAndShapeInfo* shape_info = nullptr;
            OrtStatusGuard shape_status_guard(ort_api_);
            shape_status_guard.reset(ort_api_->GetTensorTypeAndShape(output_guard.get(), &shape_info));

            size_t actual_hidden_dim = embedding_dim_; // fallback
            if (!shape_status_guard.is_error() && shape_info != nullptr) {
                size_t dim_count = 0;
                ort_api_->GetDimensionsCount(shape_info, &dim_count);
                if (dim_count >= 3) {
                    std::vector<int64_t> dims(dim_count);
                    ort_api_->GetDimensions(shape_info, dims.data(), dim_count);
                    actual_hidden_dim = static_cast<size_t>(dims[2]);
                    if (actual_hidden_dim != embedding_dim_) {
                        LOGI("Model hidden dim %zu differs from configured %zu, using actual",
                             actual_hidden_dim, embedding_dim_);
                        embedding_dim_ = actual_hidden_dim;
                    }
                }
                ort_api_->ReleaseTensorTypeAndShapeInfo(shape_info);
            }

            auto pooled = mean_pooling(
                output_data,
                attention_mask,
                pad_length,
                actual_hidden_dim
            );
            
            // 6. Normalize to unit vector
            normalize_vector(pooled);
            
            // All resources automatically cleaned up by RAII guards
            LOGI("Generated embedding: dim=%zu, norm=1.0", pooled.size());
            return pooled;
            
        } catch (const std::exception& e) {
            LOGE("Embedding generation failed: %s", e.what());
            return {};
        }
    }

    std::vector<std::vector<float>> embed_batch(const std::vector<std::string>& texts) {
        if (texts.empty()) {
            return {};
        }

        // Delegate to single embed for batch_size == 1
        if (texts.size() == 1) {
            return {embed(texts[0])};
        }

        if (!ready_) {
            LOGE("Embedding provider not ready");
            return {};
        }

        std::lock_guard<std::mutex> lock(embed_mutex_);

        std::vector<std::vector<float>> all_results;
        all_results.reserve(texts.size());

        for (size_t offset = 0; offset < texts.size(); offset += kMaxSubBatchSize) {
            size_t sub_batch_size = std::min(kMaxSubBatchSize, texts.size() - offset);

            LOGI("Embedding sub-batch %zu/%zu (size=%zu)",
                 offset / kMaxSubBatchSize + 1,
                 (texts.size() + kMaxSubBatchSize - 1) / kMaxSubBatchSize,
                 sub_batch_size);

            auto sub_results = embed_sub_batch(texts, offset, sub_batch_size);
            if (sub_results.empty()) {
                LOGE("Sub-batch embedding failed at offset %zu", offset);
                return {};
            }

            for (auto& r : sub_results) {
                all_results.push_back(std::move(r));
            }
        }

        LOGI("Generated batch embeddings: count=%zu, dim=%zu", all_results.size(), embedding_dim_);
        return all_results;
    }

    size_t dimension() const noexcept {
        return embedding_dim_;
    }

    bool is_ready() const noexcept {
        return ready_;
    }

private:
    static constexpr size_t kMaxSubBatchSize = 50;

    static size_t align_up(size_t value, size_t alignment) {
        const size_t aligned = ((value + alignment - 1) / alignment) * alignment;
        return std::min(aligned, static_cast<size_t>(512));
    }

    std::vector<std::vector<float>> embed_sub_batch(
        const std::vector<std::string>& texts,
        size_t offset,
        size_t count
    ) {
        try {
            std::vector<std::vector<int64_t>> all_token_ids(count);
            size_t max_actual_len = 0;

            for (size_t i = 0; i < count; ++i) {
                all_token_ids[i] = tokenizer_.encode_unpadded(texts[offset + i], max_seq_length_);
                max_actual_len = std::max(max_actual_len, all_token_ids[i].size());
            }

            const size_t pad_length = align_up(max_actual_len, 8);

            LOGI("Sub-batch dynamic padding: max_actual=%zu, pad_length=%zu (was %zu)",
                 max_actual_len, pad_length, max_seq_length_);

            std::vector<int64_t> flat_input_ids(count * pad_length, 0);
            std::vector<int64_t> flat_attention_mask(count * pad_length, 0);
            std::vector<int64_t> flat_token_type_ids(count * pad_length, 0);

            std::vector<std::vector<int64_t>> attention_masks(count);

            for (size_t i = 0; i < count; ++i) {
                tokenizer_.pad_to(all_token_ids[i], pad_length);
                auto attn_mask = tokenizer_.create_attention_mask(all_token_ids[i]);

                std::memcpy(flat_input_ids.data() + i * pad_length,
                            all_token_ids[i].data(), pad_length * sizeof(int64_t));
                std::memcpy(flat_attention_mask.data() + i * pad_length,
                            attn_mask.data(), pad_length * sizeof(int64_t));

                attention_masks[i] = std::move(attn_mask);
            }

            std::vector<int64_t> batch_shape = {
                static_cast<int64_t>(count),
                static_cast<int64_t>(pad_length)
            };

            OrtStatusGuard status_guard(ort_api_);
            OrtValueGuard input_ids_guard(ort_api_);
            OrtValueGuard attention_mask_guard(ort_api_);
            OrtValueGuard token_type_ids_guard(ort_api_);

            status_guard.reset(ort_api_->CreateTensorWithDataAsOrtValue(
                memory_info_,
                flat_input_ids.data(),
                count * pad_length * sizeof(int64_t),
                batch_shape.data(), batch_shape.size(),
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                input_ids_guard.ptr()));
            if (status_guard.is_error()) {
                LOGE("Sub-batch: CreateTensor (input_ids) failed: %s", status_guard.error_message());
                return {};
            }

            status_guard.reset(ort_api_->CreateTensorWithDataAsOrtValue(
                memory_info_,
                flat_attention_mask.data(),
                count * pad_length * sizeof(int64_t),
                batch_shape.data(), batch_shape.size(),
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                attention_mask_guard.ptr()));
            if (status_guard.is_error()) {
                LOGE("Sub-batch: CreateTensor (attention_mask) failed: %s", status_guard.error_message());
                return {};
            }

            status_guard.reset(ort_api_->CreateTensorWithDataAsOrtValue(
                memory_info_,
                flat_token_type_ids.data(),
                count * pad_length * sizeof(int64_t),
                batch_shape.data(), batch_shape.size(),
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                token_type_ids_guard.ptr()));
            if (status_guard.is_error()) {
                LOGE("Sub-batch: CreateTensor (token_type_ids) failed: %s", status_guard.error_message());
                return {};
            }

            const char* input_names[] = {"input_ids", "attention_mask", "token_type_ids"};
            const OrtValue* inputs[] = {
                input_ids_guard.get(), attention_mask_guard.get(), token_type_ids_guard.get()
            };
            const char* output_names[] = {"last_hidden_state"};
            OrtValueGuard output_guard(ort_api_);
            OrtValue* output_ptr = nullptr;

            status_guard.reset(ort_api_->Run(
                session_, nullptr,
                input_names, inputs, 3,
                output_names, 1,
                &output_ptr));
            if (status_guard.is_error()) {
                LOGE("Sub-batch ONNX inference failed: %s", status_guard.error_message());
                return {};
            }
            *output_guard.ptr() = output_ptr;

            float* output_data = nullptr;
            OrtStatusGuard data_status(ort_api_);
            data_status.reset(ort_api_->GetTensorMutableData(output_guard.get(), (void**)&output_data));
            if (data_status.is_error() || output_data == nullptr) {
                LOGE("Sub-batch: Failed to get output tensor data");
                return {};
            }

            size_t actual_hidden_dim = embedding_dim_;
            size_t actual_seq_len = pad_length;  // Default to what we sent
            OrtTensorTypeAndShapeInfo* shape_info = nullptr;
            OrtStatusGuard shape_status(ort_api_);
            shape_status.reset(ort_api_->GetTensorTypeAndShape(output_guard.get(), &shape_info));
            if (!shape_status.is_error() && shape_info != nullptr) {
                size_t dim_count = 0;
                ort_api_->GetDimensionsCount(shape_info, &dim_count);
                if (dim_count >= 3) {
                    std::vector<int64_t> dims(dim_count);
                    ort_api_->GetDimensions(shape_info, dims.data(), dim_count);
                    actual_seq_len = static_cast<size_t>(dims[1]);
                    actual_hidden_dim = static_cast<size_t>(dims[2]);
                    if (actual_hidden_dim != embedding_dim_) {
                        LOGI("Model hidden dim %zu differs from configured %zu, using actual",
                             actual_hidden_dim, embedding_dim_);
                        embedding_dim_ = actual_hidden_dim;
                    }
                }
                ort_api_->ReleaseTensorTypeAndShapeInfo(shape_info);
            }

            std::vector<std::vector<float>> results(count);
            const size_t stride = actual_seq_len * actual_hidden_dim;

            for (size_t i = 0; i < count; ++i) {
                const float* sentence_data = output_data + i * stride;
                auto pooled = mean_pooling(
                    sentence_data, attention_masks[i],
                    actual_seq_len, actual_hidden_dim);
                normalize_vector(pooled);
                results[i] = std::move(pooled);
            }

            return results;

        } catch (const std::exception& e) {
            LOGE("Sub-batch embedding failed: %s", e.what());
            return {};
        }
    }

    bool initialize_onnx_runtime() {
        const OrtApiBase* ort_api_base = OrtGetApiBase();
        const char* ort_version = ort_api_base ? ort_api_base->GetVersionString() : "unknown";
        ort_api_ = ort_api_base ? ort_api_base->GetApi(ORT_API_VERSION) : nullptr;
        if (!ort_api_) {
            LOGE("Failed to get ONNX Runtime API (ORT_API_VERSION=%d, runtime=%s)", ORT_API_VERSION, ort_version);
            return false;
        }
        
        // Create environment
        OrtStatus* status = ort_api_->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "RAGEmbedding", &ort_env_);
        if (status != nullptr) {
            const char* error_msg = ort_api_->GetErrorMessage(status);
            LOGE("Failed to create ORT environment: %s", error_msg);
            ort_api_->ReleaseStatus(status);
            return false;
        }
        
        return true;
    }
    
    bool load_model(const std::string& model_path) {
        // Create session options with RAII guard
        OrtSessionOptionsGuard options_guard(ort_api_);
        OrtStatusGuard status_guard(ort_api_);
        
        status_guard.reset(ort_api_->CreateSessionOptions(options_guard.ptr()));
        if (status_guard.is_error()) {
            LOGE("Failed to create session options: %s", status_guard.error_message());
            return false;
        }
        
        if (options_guard.get() == nullptr) {
            LOGE("Session options is null after creation");
            return false;
        }
        
        // Configure session options with error checking
        status_guard.reset(ort_api_->SetIntraOpNumThreads(options_guard.get(), 4));
        if (status_guard.is_error()) {
            LOGE("Failed to set intra-op threads: %s", status_guard.error_message());
            return false;
        }
        
        status_guard.reset(ort_api_->SetSessionGraphOptimizationLevel(options_guard.get(), ORT_ENABLE_ALL));
        if (status_guard.is_error()) {
            LOGE("Failed to set graph optimization level: %s", status_guard.error_message());
            return false;
        }
        
        // Load model with session options
        status_guard.reset(ort_api_->CreateSession(
            ort_env_,
            model_path.c_str(),
            options_guard.get(),
            &session_
        ));
        // options_guard automatically releases session options on scope exit
        
        if (status_guard.is_error()) {
            LOGE("Failed to load model: %s", status_guard.error_message());
            return false;
        }
        
        LOGI("Model loaded successfully: %s", model_path.c_str());
        return true;
    }
    
    void cleanup() {
        if (memory_info_) {
            ort_api_->ReleaseMemoryInfo(memory_info_);
            memory_info_ = nullptr;
        }

        if (session_) {
            ort_api_->ReleaseSession(session_);
            session_ = nullptr;
        }

        if (ort_env_) {
            ort_api_->ReleaseEnv(ort_env_);
            ort_env_ = nullptr;
        }
    }

    std::string model_path_;
    nlohmann::json config_;
    SimpleTokenizer tokenizer_;

    // ONNX Runtime objects
    const OrtApi* ort_api_ = nullptr;
    OrtEnv* ort_env_ = nullptr;
    OrtSession* session_ = nullptr;
    OrtMemoryInfo* memory_info_ = nullptr;  // Cached (allocated once in constructor)

    // Pre-allocated input buffers (reused across embed() calls to avoid per-call allocs)
    std::vector<int64_t> input_ids_buf_;
    std::vector<int64_t> attention_mask_buf_;
    std::vector<int64_t> token_type_ids_buf_;
    std::vector<int64_t> input_shape_ = {1, 0};  // Updated in constructor

    bool ready_ = false;
    size_t embedding_dim_ = 384;  // all-MiniLM-L6-v2 dimension
    size_t max_seq_length_ = 512;  // all-MiniLM-L6-v2 max_position_embeddings=512
    std::mutex embed_mutex_;  // Protects pre-allocated buffers during concurrent embed() calls
};

// =============================================================================
// PUBLIC API
// =============================================================================

ONNXEmbeddingProvider::ONNXEmbeddingProvider(
    const std::string& model_path,
    const std::string& config_json
) : impl_(std::make_unique<Impl>(model_path, config_json)) {
}

ONNXEmbeddingProvider::~ONNXEmbeddingProvider() = default;

ONNXEmbeddingProvider::ONNXEmbeddingProvider(ONNXEmbeddingProvider&&) noexcept = default;
ONNXEmbeddingProvider& ONNXEmbeddingProvider::operator=(ONNXEmbeddingProvider&&) noexcept = default;

std::vector<float> ONNXEmbeddingProvider::embed(const std::string& text) {
    return impl_->embed(text);
}

std::vector<std::vector<float>> ONNXEmbeddingProvider::embed_batch(const std::vector<std::string>& texts) {
    return impl_->embed_batch(texts);
}

size_t ONNXEmbeddingProvider::dimension() const noexcept {
    return impl_->dimension();
}

bool ONNXEmbeddingProvider::is_ready() const noexcept {
    return impl_->is_ready();
}

const char* ONNXEmbeddingProvider::name() const noexcept {
    return "ONNX-Embedding";
}

} // namespace rag
} // namespace runanywhere
