/**
 * @file onnx_embedding_provider.cpp
 * @brief ONNX embedding provider implementation
 */

#include "onnx_embedding_provider.h"
#include "backends/rag/ort_guards.h"
#include "rac/core/rac_logger.h"
#include "../onnx/onnx_backend.h"

#include <nlohmann/json.hpp>
#include <onnxruntime_c_api.h>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <cmath>
#include <algorithm>
#include <cctype>
#include <unordered_map>
#include <list>

#if defined(__aarch64__) && defined(__ARM_NEON)
#include <arm_neon.h>
#endif

static const char* LOG_TAG = "RAG.ONNXEmbedding";

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
    
    std::vector<int64_t> encode(const std::string& text, size_t max_length = 512) {
        std::vector<int64_t> token_ids;
        token_ids.reserve(max_length);
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
        
        // Pad to max_length
        while (token_ids.size() < max_length) {
            token_ids.push_back(pad_id_); // [PAD]
        }
        
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
                RAC_LOG_ERROR(LOG_TAG,"Failed to parse config JSON: %s", e.what());
            }
        }

        // Initialize ONNX Runtime
        if (!initialize_onnx_runtime()) {
            RAC_LOG_ERROR(LOG_TAG,"Failed to initialize ONNX Runtime");
            return;
        }
        
        // Load tokenizer vocab if provided
        std::string vocab_path;
        if (config_.contains("vocab_path")) {
            vocab_path = config_.at("vocab_path").get<std::string>();
        } else if (config_.contains("vocabPath")) {
            vocab_path = config_.at("vocabPath").get<std::string>();
        } else {
            std::filesystem::path model_file(model_path_);
            vocab_path = (model_file.parent_path() / "vocab.txt").string();
        }

        if (vocab_path.empty() || !std::filesystem::exists(vocab_path)) {
            RAC_LOG_ERROR(LOG_TAG,"Tokenizer vocab not found: %s", vocab_path.c_str());
            return;
        }

        if (!tokenizer_.load_vocab(vocab_path)) {
            RAC_LOG_ERROR(LOG_TAG,"Failed to load tokenizer vocab: %s", vocab_path.c_str());
            return;
        }

        RAC_LOG_INFO(LOG_TAG,"Loaded tokenizer vocab: %s", vocab_path.c_str());

        // Load model
        if (!load_model(model_path)) {
            RAC_LOG_ERROR(LOG_TAG,"Failed to load model: %s", model_path.c_str());
            return;
        }
        
        ready_ = true;
        RAC_LOG_INFO(LOG_TAG,"ONNX embedding provider initialized: %s", model_path.c_str());
        RAC_LOG_INFO(LOG_TAG,"  Hidden dimension: %zu", embedding_dim_);
    }

    ~Impl() {
        cleanup();
    }

    std::vector<float> embed(const std::string& text) {
        if (!ready_) {
            RAC_LOG_ERROR(LOG_TAG,"Embedding provider not ready");
            return std::vector<float>(embedding_dim_, 0.0f);
        }

        try {
            // 1. Tokenize input
            auto token_ids = tokenizer_.encode(text, max_seq_length_);
            auto attention_mask = tokenizer_.create_attention_mask(token_ids);
            auto token_type_ids = tokenizer_.create_token_type_ids(max_seq_length_);
            
            // 2. Prepare ONNX inputs
            std::vector<int64_t> input_shape = {1, static_cast<int64_t>(max_seq_length_)};
            size_t input_tensor_size = max_seq_length_;
            
            // Create RAII guards for automatic resource management
            OrtStatusGuard status_guard(ort_api_);
            OrtMemoryInfoGuard memory_info_guard(ort_api_);
            OrtValueGuard input_ids_guard(ort_api_);
            OrtValueGuard attention_mask_guard(ort_api_);
            OrtValueGuard token_type_ids_guard(ort_api_);
            
            // Create memory info
            status_guard.reset(ort_api_->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, memory_info_guard.ptr()));
            if (status_guard.is_error()) {
                RAC_LOG_ERROR(LOG_TAG,"CreateCpuMemoryInfo failed: %s", status_guard.error_message());
                return std::vector<float>(embedding_dim_, 0.0f);
            }
            
            // Create input_ids tensor
            status_guard.reset(ort_api_->CreateTensorWithDataAsOrtValue(
                memory_info_guard.get(),
                token_ids.data(),
                input_tensor_size * sizeof(int64_t),
                input_shape.data(),
                input_shape.size(),
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                input_ids_guard.ptr()
            ));
            if (status_guard.is_error()) {
                RAC_LOG_ERROR(LOG_TAG,"CreateTensorWithDataAsOrtValue (input_ids) failed: %s", status_guard.error_message());
                return std::vector<float>(embedding_dim_, 0.0f);
            }
            
            // Create attention_mask tensor
            status_guard.reset(ort_api_->CreateTensorWithDataAsOrtValue(
                memory_info_guard.get(),
                attention_mask.data(),
                input_tensor_size * sizeof(int64_t),
                input_shape.data(),
                input_shape.size(),
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                attention_mask_guard.ptr()
            ));
            if (status_guard.is_error()) {
                RAC_LOG_ERROR(LOG_TAG,"CreateTensorWithDataAsOrtValue (attention_mask) failed: %s", status_guard.error_message());
                return std::vector<float>(embedding_dim_, 0.0f);
            }
            
            // Create token_type_ids tensor
            status_guard.reset(ort_api_->CreateTensorWithDataAsOrtValue(
                memory_info_guard.get(),
                token_type_ids.data(),
                input_tensor_size * sizeof(int64_t),
                input_shape.data(),
                input_shape.size(),
                ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                token_type_ids_guard.ptr()
            ));
            if (status_guard.is_error()) {
                RAC_LOG_ERROR(LOG_TAG,"CreateTensorWithDataAsOrtValue (token_type_ids) failed: %s", status_guard.error_message());
                return std::vector<float>(embedding_dim_, 0.0f);
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
                RAC_LOG_ERROR(LOG_TAG,"ONNX inference failed: %s", status_guard.error_message());
                return std::vector<float>(embedding_dim_, 0.0f);
            }
            
            // Transfer ownership to guard for automatic cleanup
            *output_guard.ptr() = output_ptr;
            
            // 4. Extract output embeddings
            float* output_data = nullptr;
            OrtStatusGuard output_status_guard(ort_api_);
            output_status_guard.reset(ort_api_->GetTensorMutableData(output_guard.get(), (void**)&output_data));
            
            if (output_status_guard.is_error()) {
                RAC_LOG_ERROR(LOG_TAG,"Failed to get output tensor data: %s", output_status_guard.error_message());
                return std::vector<float>(embedding_dim_, 0.0f);
            }
            
            if (output_data == nullptr) {
                RAC_LOG_ERROR(LOG_TAG,"Output tensor data pointer is null");
                return std::vector<float>(embedding_dim_, 0.0f);
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
                        RAC_LOG_INFO(LOG_TAG,"Model hidden dim %zu differs from configured %zu, using actual",
                             actual_hidden_dim, embedding_dim_);
                        embedding_dim_ = actual_hidden_dim;
                    }
                }
                ort_api_->ReleaseTensorTypeAndShapeInfo(shape_info);
            }

            // 5. Mean pooling
            auto pooled = mean_pooling(
                output_data,
                attention_mask,
                max_seq_length_,
                actual_hidden_dim
            );
            
            // 6. Normalize to unit vector
            normalize_vector(pooled);
            
            // All resources automatically cleaned up by RAII guards
            RAC_LOG_INFO(LOG_TAG,"Generated embedding: dim=%zu, norm=1.0", pooled.size());
            return pooled;
            
        } catch (const std::exception& e) {
            RAC_LOG_ERROR(LOG_TAG,"Embedding generation failed: %s", e.what());
            return std::vector<float>(embedding_dim_, 0.0f);
        }
    }

    size_t dimension() const noexcept {
        return embedding_dim_;
    }

    bool is_ready() const noexcept {
        return ready_;
    }

private:
    bool initialize_onnx_runtime() {
        const OrtApiBase* ort_api_base = OrtGetApiBase();
        const char* ort_version = ort_api_base ? ort_api_base->GetVersionString() : "unknown";
        ort_api_ = ort_api_base ? ort_api_base->GetApi(ORT_API_VERSION) : nullptr;
        if (!ort_api_) {
            RAC_LOG_ERROR(LOG_TAG,"Failed to get ONNX Runtime API (ORT_API_VERSION=%d, runtime=%s)", ORT_API_VERSION, ort_version);
            return false;
        }
        
        // Create environment
        OrtStatus* status = ort_api_->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "RAGEmbedding", &ort_env_);
        if (status != nullptr) {
            const char* error_msg = ort_api_->GetErrorMessage(status);
            RAC_LOG_ERROR(LOG_TAG,"Failed to create ORT environment: %s", error_msg);
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
            RAC_LOG_ERROR(LOG_TAG,"Failed to create session options: %s", status_guard.error_message());
            return false;
        }
        
        if (options_guard.get() == nullptr) {
            RAC_LOG_ERROR(LOG_TAG,"Session options is null after creation");
            return false;
        }
        
        // Configure session options with error checking
        status_guard.reset(ort_api_->SetIntraOpNumThreads(options_guard.get(), 4));
        if (status_guard.is_error()) {
            RAC_LOG_ERROR(LOG_TAG,"Failed to set intra-op threads: %s", status_guard.error_message());
            return false;
        }
        
        status_guard.reset(ort_api_->SetSessionGraphOptimizationLevel(options_guard.get(), ORT_ENABLE_ALL));
        if (status_guard.is_error()) {
            RAC_LOG_ERROR(LOG_TAG,"Failed to set graph optimization level: %s", status_guard.error_message());
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
            RAC_LOG_ERROR(LOG_TAG,"Failed to load model: %s", status_guard.error_message());
            return false;
        }
        
        RAC_LOG_INFO(LOG_TAG,"Model loaded successfully: %s", model_path.c_str());
        return true;
    }
    
    void cleanup() {
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
    
    bool ready_ = false;
    size_t embedding_dim_ = 384;  // all-MiniLM-L6-v2 dimension
    size_t max_seq_length_ = 512;  // all-MiniLM-L6-v2 max_position_embeddings=512
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

size_t ONNXEmbeddingProvider::dimension() const noexcept {
    return impl_->dimension();
}

bool ONNXEmbeddingProvider::is_ready() const noexcept {
    return impl_->is_ready();
}

const char* ONNXEmbeddingProvider::name() const noexcept {
    return "ONNX-Embedding";
}

// =============================================================================
// FACTORY FUNCTION
// =============================================================================

std::unique_ptr<IEmbeddingProvider> create_onnx_embedding_provider(
    const std::string& model_path,
    const std::string& config_json
) {
    return std::make_unique<ONNXEmbeddingProvider>(model_path, config_json);
}

} // namespace rag
} // namespace runanywhere
