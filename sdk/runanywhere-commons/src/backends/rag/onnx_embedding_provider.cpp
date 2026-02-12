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
#include <fstream>
#include <sstream>
#include <cmath>
#include <algorithm>

#define LOG_TAG "RAG.ONNXEmbedding"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)
#define LOGW(...) RAC_LOG_WARN(LOG_TAG, __VA_ARGS__)

namespace runanywhere {
namespace rag {

// =============================================================================
// SIMPLE TOKENIZER (Word-level for MVP)
// =============================================================================

class SimpleTokenizer {
public:
    SimpleTokenizer() {
        // Special tokens
        token_to_id_["[CLS]"] = 101;
        token_to_id_["[SEP]"] = 102;
        token_to_id_["[PAD]"] = 0;
        token_to_id_["[UNK]"] = 100;
        next_id_ = 1000;
    }
    
    std::vector<int64_t> encode(const std::string& text, size_t max_length = 512) {
        std::vector<int64_t> token_ids;
        token_ids.push_back(101); // [CLS]
        
        // Simple word tokenization
        std::istringstream iss(text);
        std::string word;
        
        while (iss >> word && token_ids.size() < max_length - 1) {
            // Convert to lowercase
            std::transform(word.begin(), word.end(), word.begin(), ::tolower);
            
            // Get or create token ID
            auto it = token_to_id_.find(word);
            if (it != token_to_id_.end()) {
                token_ids.push_back(it->second);
            } else {
                // Hash-based ID for unknown words (clamped to BERT vocab range)
                // BERT vocab size is 30522 (valid IDs: 0..30521)
                size_t hash = std::hash<std::string>{}(word);
                constexpr int64_t kVocabSize = 30522;
                constexpr int64_t kMinId = 1000;
                constexpr int64_t kMaxId = kVocabSize - 1;
                const int64_t range = kMaxId - kMinId + 1;
                int64_t token_id = static_cast<int64_t>(hash % static_cast<size_t>(range)) + kMinId;
                token_ids.push_back(token_id);
            }
        }
        
        token_ids.push_back(102); // [SEP]
        
        // Pad to max_length
        while (token_ids.size() < max_length) {
            token_ids.push_back(0); // [PAD]
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
    std::unordered_map<std::string, int64_t> token_to_id_;
    int64_t next_id_;
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
        
        // Load model
        if (!load_model(model_path)) {
            LOGE("Failed to load model: %s", model_path.c_str());
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
                LOGE("CreateCpuMemoryInfo failed: %s", status_guard.error_message());
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
                LOGE("CreateTensorWithDataAsOrtValue (input_ids) failed: %s", status_guard.error_message());
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
                LOGE("CreateTensorWithDataAsOrtValue (attention_mask) failed: %s", status_guard.error_message());
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
                LOGE("CreateTensorWithDataAsOrtValue (token_type_ids) failed: %s", status_guard.error_message());
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
                LOGE("ONNX inference failed: %s", status_guard.error_message());
                return std::vector<float>(embedding_dim_, 0.0f);
            }
            
            // Transfer ownership to guard for automatic cleanup
            *output_guard.ptr() = output_ptr;
            
            // 4. Extract output embeddings
            float* output_data = nullptr;
            OrtStatusGuard output_status_guard(ort_api_);
            output_status_guard.reset(ort_api_->GetTensorMutableData(output_guard.get(), (void**)&output_data));
            
            if (output_status_guard.is_error()) {
                LOGE("Failed to get output tensor data: %s", output_status_guard.error_message());
                return std::vector<float>(embedding_dim_, 0.0f);
            }
            
            if (output_data == nullptr) {
                LOGE("Output tensor data pointer is null");
                return std::vector<float>(embedding_dim_, 0.0f);
            }
            
            // 5. Mean pooling
            auto pooled = mean_pooling(
                output_data,
                attention_mask,
                max_seq_length_,
                embedding_dim_
            );
            
            // 6. Normalize to unit vector
            normalize_vector(pooled);
            
            // All resources automatically cleaned up by RAII guards
            LOGI("Generated embedding: dim=%zu, norm=1.0", pooled.size());
            return pooled;
            
        } catch (const std::exception& e) {
            LOGE("Embedding generation failed: %s", e.what());
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
        ort_api_ = OrtGetApiBase()->GetApi(ORT_API_VERSION);
        if (!ort_api_) {
            LOGE("Failed to get ONNX Runtime API");
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
    size_t max_seq_length_ = 256;  // Reduced from 512 for mobile performance
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
