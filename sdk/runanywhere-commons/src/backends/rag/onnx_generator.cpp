/**
 * @file onnx_generator.cpp
 * @brief ONNX Text Generator Implementation with Real Inference
 */

#include "onnx_generator.h"
#include "backends/rag/ort_guards.h"

#include "rac/core/rac_logger.h"
#include <nlohmann/json.hpp>
#include <chrono>
#include <sstream>
#include <fstream>
#include <algorithm>
#include <random>
#include <cmath>
#include <memory>
#include <vector>
#include <onnxruntime_c_api.h>

#define LOG_TAG "RAG.ONNXGenerator"
#define LOGI(...) RAC_LOG_INFO(LOG_TAG, __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR(LOG_TAG, __VA_ARGS__)

namespace runanywhere {
namespace rag {

// =============================================================================
// RAII WRAPPERS - Now using shared guards from ort_guards.h
// =============================================================================
// SIMPLE TOKENIZER FOR LLM (MVP - Word-level with vocabulary)
// =============================================================================
// Production systems should use proper tokenizers (SentencePiece, BPE, etc.)
// This is a simplified tokenizer for demonstration and initial testing

class SimpleTokenizer {
public:
    static constexpr int64_t PAD_TOKEN = 0;
    static constexpr int64_t BOS_TOKEN = 1;  // Beginning of sequence
    static constexpr int64_t EOS_TOKEN = 2;  // End of sequence
    static constexpr int64_t UNK_TOKEN = 3;  // Unknown token
    
    SimpleTokenizer() {
        // Initialize with special tokens
        vocab_["<pad>"] = PAD_TOKEN;
        vocab_["<s>"] = BOS_TOKEN;
        vocab_["</s>"] = EOS_TOKEN;
        vocab_["<unk>"] = UNK_TOKEN;
        
        // Build reverse mapping
        for (const auto& pair : vocab_) {
            reverse_vocab_[pair.second] = pair.first;
        }
    }
    
    // Load vocabulary from tokenizer.json or vocab.txt
    bool load_vocab(const std::string& tokenizer_path) {
        // Try to load from JSON first
        std::ifstream file(tokenizer_path);
        if (!file.is_open()) {
            LOGE("Failed to open tokenizer file: %s", tokenizer_path.c_str());
            return false;
        }
        
        try {
            nlohmann::json tokenizer_json;
            file >> tokenizer_json;
            
            if (tokenizer_json.contains("model") && tokenizer_json["model"].contains("vocab")) {
                auto& vocab_json = tokenizer_json["model"]["vocab"];
                for (auto& item : vocab_json.items()) {
                    vocab_[item.key()] = item.value().get<int64_t>();
                    reverse_vocab_[item.value().get<int64_t>()] = item.key();
                }
                LOGI("Loaded vocabulary: %zu tokens", vocab_.size());
                return true;
            }
        } catch (const std::exception& e) {
            LOGE("Failed to parse tokenizer JSON: %s", e.what());
        }
        
        return false;
    }
    
    // Encode text to token IDs
    std::vector<int64_t> encode(const std::string& text, bool add_bos = true) {
        std::vector<int64_t> token_ids;
        
        if (add_bos) {
            token_ids.push_back(BOS_TOKEN);
        }
        
        // Simple word tokenization
        std::istringstream stream(text);
        std::string word;
        while (stream >> word) {
            // Convert to lowercase for case-insensitive matching
            std::string lower_word = word;
            std::transform(lower_word.begin(), lower_word.end(), lower_word.begin(), ::tolower);
            
            auto it = vocab_.find(lower_word);
            if (it != vocab_.end()) {
                token_ids.push_back(it->second);
            } else {
                // Unknown token - use hash-based pseudo-ID
                int64_t pseudo_id = 1000 + (std::hash<std::string>{}(lower_word) % 30000);
                token_ids.push_back(pseudo_id);
            }
        }
        
        return token_ids;
    }
    
    // Decode token IDs to text
    std::string decode(const std::vector<int64_t>& token_ids, bool skip_special = true) {
        std::ostringstream result;
        
        for (size_t i = 0; i < token_ids.size(); ++i) {
            int64_t token_id = token_ids[i];
            
            // Skip special tokens if requested
            if (skip_special && (token_id == PAD_TOKEN || token_id == BOS_TOKEN || token_id == EOS_TOKEN)) {
                continue;
            }
            
            auto it = reverse_vocab_.find(token_id);
            if (it != reverse_vocab_.end()) {
                if (i > 0 && !skip_special) result << " ";
                result << it->second;
            } else {
                // Unknown token - show as [UNK_####]
                if (i > 0) result << " ";
                result << "[UNK_" << token_id << "]";
            }
        }
        
        return result.str();
    }
    
private:
    std::unordered_map<std::string, int64_t> vocab_;
    std::unordered_map<int64_t, std::string> reverse_vocab_;
};

// =============================================================================
// PIMPL IMPLEMENTATION
// =============================================================================

class ONNXGenerator::Impl {
public:
    std::string model_path;
    std::string generator_name = "ONNX-Generator";
    bool ready = false;
    
    // ONNX Runtime objects
    OrtEnv* ort_env = nullptr;
    OrtSession* session = nullptr;
    OrtMemoryInfo* memory_info = nullptr;
    const OrtApi* cached_api = nullptr;  // Cache API pointer for efficiency
    
    // Tokenizer
    std::unique_ptr<SimpleTokenizer> tokenizer;
    
    // Model configuration (const after initialization)
    size_t num_layers = 22;  // TinyLlama has 22 transformer layers
    size_t num_heads = 4;
    size_t head_dim = 64;
    size_t vocab_size = 32000;
    
    // Pre-calculate cache dimensions for efficiency
    size_t kv_cache_size_per_layer = 0;
    
    // Generation parameters
    int max_context_length = 2048;
    std::string tokenizer_path;
    
    bool initialize(const std::string& path, const std::string& config_json) {
        model_path = path;
        
        // Parse config if provided
        nlohmann::json config;
        if (!config_json.empty()) {
            try {
                config = nlohmann::json::parse(config_json);
                
                // Extract configuration
                if (config.contains("max_context_length")) {
                    max_context_length = config["max_context_length"].get<int>();
                }
                if (config.contains("tokenizer_path")) {
                    tokenizer_path = config["tokenizer_path"].get<std::string>();
                }
            } catch (const std::exception& e) {
                LOGE("Failed to parse config JSON: %s", e.what());
                config = nlohmann::json::object();
            }
        }
        
        // Create tokenizer
        tokenizer = std::make_unique<SimpleTokenizer>();
        
        // Load vocabulary if tokenizer path provided
        if (!tokenizer_path.empty()) {
            if (!tokenizer->load_vocab(tokenizer_path)) {
                LOGE("Failed to load tokenizer from %s", tokenizer_path.c_str());
                LOGI("Using default word-level tokenizer");
            }
        } else {
            LOGI("No tokenizer path provided, using default word-level tokenizer");
        }
        
        // Initialize ONNX Runtime directly
        cached_api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
        if (!cached_api) {
            LOGE("Failed to get ONNX Runtime API");
            return false;
        }
        
        // Create ORT environment (exception-safe with RAII)
        OrtStatusGuard status_guard(cached_api);
        status_guard.reset(cached_api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "RAG_ONNX_Generator", &ort_env));
        if (status_guard.is_error() || !ort_env) {
            LOGE("Failed to create ONNX Runtime environment: %s", status_guard.error_message());
            return false;
        }
        
        // Calculate KV-cache size per layer
        kv_cache_size_per_layer = num_heads * head_dim;
        
        // Create session options (will auto-release on scope exit)
        OrtSessionOptions* session_options = nullptr;
        status_guard.reset(cached_api->CreateSessionOptions(&session_options));
        if (status_guard.is_error()) {
            LOGE("Failed to create session options: %s", status_guard.error_message());
            return false;
        }
        
        // Ensure session options are cleaned up (scope guard pattern)
        struct SessionOptionsGuard {
            const OrtApi* api;
            OrtSessionOptions* opts;
            ~SessionOptionsGuard() { 
                if (opts && api) api->ReleaseSessionOptions(opts); 
            }
        } options_guard{cached_api, session_options};
        
        // Configure session for performance (ignore return status - best effort)
        cached_api->SetIntraOpNumThreads(session_options, 4);
        cached_api->SetSessionGraphOptimizationLevel(session_options, ORT_ENABLE_ALL);
        
        // Create memory info for CPU
        status_guard.reset(cached_api->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info));
        if (status_guard.is_error()) {
            LOGE("Failed to create memory info: %s", status_guard.error_message());
            return false;
        }
        
        // Load model and create session
        LOGI("Loading ONNX model: %s", model_path.c_str());
        status_guard.reset(cached_api->CreateSession(ort_env, model_path.c_str(), session_options, &session));
        if (status_guard.is_error()) {
            LOGE("Failed to create ONNX session: %s", status_guard.error_message());
            return false;
        }
        
        LOGI("ONNX generator initialized successfully");
        LOGI("  Model: %s", model_path.c_str());
        LOGI("  Max context: %d tokens", max_context_length);
        
        ready = true;
        return true;
    }
    
    ~Impl() {
        cleanup();
    }
    
    void cleanup() noexcept {
        if (cached_api) {
            if (session) {
                cached_api->ReleaseSession(session);
                session = nullptr;
            }
            if (memory_info) {
                cached_api->ReleaseMemoryInfo(memory_info);
                memory_info = nullptr;
            }
            if (ort_env) {
                cached_api->ReleaseEnv(ort_env);
                ort_env = nullptr;
            }
        }
        cached_api = nullptr;
    }
    
    // Sample next token using temperature and top-p sampling
    int64_t sample_token(const std::vector<float>& logits, float temperature, float top_p) const {
        if (logits.empty()) {
            return SimpleTokenizer::EOS_TOKEN;
        }
        
        // Work with a copy for modifications
        std::vector<float> probs;
        probs.reserve(logits.size());
        
        // Apply temperature and softmax in one pass
        float max_logit = *std::max_element(logits.begin(), logits.end());
        float sum = 0.0f;
        
        if (temperature > 0.0f && temperature != 1.0f) {
            for (const float logit : logits) {
                const float prob = std::exp((logit - max_logit) / temperature);
                probs.push_back(prob);
                sum += prob;
            }
        } else {
            for (const float logit : logits) {
                const float prob = std::exp(logit - max_logit);
                probs.push_back(prob);
                sum += prob;
            }
        }
        
        // Normalize
        const float inv_sum = 1.0f / sum;
        for (float& prob : probs) {
            prob *= inv_sum;
        }
        
        // Top-p (nucleus) sampling
        if (top_p < 1.0f && top_p > 0.0f) {
            // Create indices and sort by probability (descending)
            std::vector<std::pair<float, size_t>> prob_indices;
            prob_indices.reserve(probs.size());
            for (size_t i = 0; i < probs.size(); ++i) {
                prob_indices.emplace_back(probs[i], i);
            }
            std::sort(prob_indices.begin(), prob_indices.end(), 
                     [](const auto& a, const auto& b) { return a.first > b.first; });
            
            // Find cutoff index
            float cumsum = 0.0f;
            size_t cutoff = 0;
            for (size_t i = 0; i < prob_indices.size(); ++i) {
                cumsum += prob_indices[i].first;
                cutoff = i + 1;
                if (cumsum >= top_p) break;
            }
            
            // Zero out probabilities below cutoff
            std::fill(probs.begin(), probs.end(), 0.0f);
            sum = 0.0f;
            for (size_t i = 0; i < cutoff; ++i) {
                const size_t idx = prob_indices[i].second;
                probs[idx] = prob_indices[i].first;
                sum += prob_indices[i].first;
            }
            
            // Renormalize
            const float inv_sum = 1.0f / sum;
            for (float& prob : probs) {
                prob *= inv_sum;
            }
        }
        
        // Sample from distribution (thread-safe local static)
        static thread_local std::mt19937 gen{std::random_device{}()};
        std::discrete_distribution<> dist(probs.begin(), probs.end());
        
        return static_cast<int64_t>(dist(gen));
    }
    
    GenerationResult generate_text(
        const std::string& prompt,
        const GenerationOptions& options
    ) {
        GenerationResult result;
        result.success = false;
        
        if (!ready || !cached_api || !session) {
            LOGE("Generator not ready");
            result.text = "";
            result.stop_reason = "error";
            return result;
        }
        
        try {
            auto start_time = std::chrono::high_resolution_clock::now();
            
            LOGI("Generating text with ONNX Runtime (KV-cache enabled):");
            LOGI("  Prompt length: %zu chars", prompt.length());
            LOGI("  Max tokens: %d", options.max_tokens);
            LOGI("  Temperature: %.2f", options.temperature);
            LOGI("  Top-p: %.2f", options.top_p);
            
            // ========================================================================
            // STEP 1: Tokenization
            // ========================================================================
            
            std::vector<int64_t> input_ids = tokenizer->encode(prompt, true);
            const size_t original_length = input_ids.size();
            
            if (input_ids.empty()) {
                input_ids.push_back(SimpleTokenizer::BOS_TOKEN);
            }
            
            LOGI("Tokenized to %zu tokens", input_ids.size());
            
            // ========================================================================
            // STEP 2: Initialize KV-cache state with pre-allocated capacity
            // ========================================================================
            
            // KV-cache: stores past key/value pairs for each transformer layer
            // Shape: [batch_size, num_heads, past_seq_len, head_dim]
            std::vector<std::vector<float>> past_keys(num_layers);
            std::vector<std::vector<float>> past_values(num_layers);
            
            // Pre-allocate expected capacity to avoid reallocations
            const size_t estimated_total_len = input_ids.size() + options.max_tokens;
            const size_t estimated_cache_size = kv_cache_size_per_layer * estimated_total_len;
            for (size_t i = 0; i < num_layers; ++i) {
                past_keys[i].reserve(estimated_cache_size);
                past_values[i].reserve(estimated_cache_size);
            }
            
            size_t past_seq_len = 0;  // Initially empty
            
            // ========================================================================
            // STEP 3: Autoregressive Generation Loop with KV-cache
            // ========================================================================
            
            int tokens_generated = 0;
            bool finished = false;
            std::string stop_reason_str = "length";
            
            for (int step = 0; step < options.max_tokens && !finished; ++step) {
                const bool is_first_step = (step == 0);
                const size_t current_seq_len = is_first_step ? input_ids.size() : 1;
                
                // Prepare input tensors
                std::vector<OrtValue*> input_tensors;
                std::vector<const char*> input_names;
                OrtStatus* status = nullptr;
                
                // 1. input_ids: [batch_size, sequence_length]
                std::vector<int64_t> current_input_ids;
                if (is_first_step) {
                    current_input_ids = input_ids;  // Full sequence on first step
                } else {
                    current_input_ids = {input_ids.back()};  // Only last token
                }
                
                std::vector<int64_t> input_ids_shape = {1, static_cast<int64_t>(current_input_ids.size())};
                OrtValue* input_ids_tensor = nullptr;
                status = cached_api->CreateTensorWithDataAsOrtValue(
                    memory_info,
                    current_input_ids.data(),
                    current_input_ids.size() * sizeof(int64_t),
                    input_ids_shape.data(),
                    input_ids_shape.size(),
                    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                    &input_ids_tensor
                );
                if (status != nullptr) {
                    LOGE("Failed to create input_ids tensor: %s", cached_api->GetErrorMessage(status));
                    cached_api->ReleaseStatus(status);
                    result.success = false;
                    result.stop_reason = "error";
                    return result;
                }
                if (input_ids_tensor == nullptr) {
                    LOGE("input_ids_tensor is null after creation");
                    result.success = false;
                    result.stop_reason = "error";
                    return result;
                }
                input_tensors.push_back(input_ids_tensor);
                input_names.push_back("input_ids");
                
                // 2. attention_mask: [batch_size, past_seq_len + current_seq_len]
                const size_t total_seq_len = past_seq_len + current_seq_len;
                std::vector<int64_t> attention_mask(total_seq_len, 1);
                std::vector<int64_t> attention_mask_shape = {1, static_cast<int64_t>(total_seq_len)};
                
                OrtValue* attention_mask_tensor = nullptr;
                status = cached_api->CreateTensorWithDataAsOrtValue(
                    memory_info,
                    attention_mask.data(),
                    attention_mask.size() * sizeof(int64_t),
                    attention_mask_shape.data(),
                    attention_mask_shape.size(),
                    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                    &attention_mask_tensor
                );
                if (status != nullptr) {
                    LOGE("Failed to create attention_mask tensor: %s", cached_api->GetErrorMessage(status));
                    cached_api->ReleaseStatus(status);
                    result.success = false;
                    result.stop_reason = "error";
                    return result;
                }
                if (attention_mask_tensor == nullptr) {
                    LOGE("attention_mask_tensor is null after creation");
                    result.success = false;
                    result.stop_reason = "error";
                    return result;
                }
                input_tensors.push_back(attention_mask_tensor);
                input_names.push_back("attention_mask");
                
                // 3. position_ids: [batch_size, current_seq_len]
                std::vector<int64_t> position_ids(current_seq_len);
                for (size_t i = 0; i < current_seq_len; ++i) {
                    position_ids[i] = past_seq_len + i;
                }
                std::vector<int64_t> position_ids_shape = {1, static_cast<int64_t>(current_seq_len)};
                
                OrtValue* position_ids_tensor = nullptr;
                status = cached_api->CreateTensorWithDataAsOrtValue(
                    memory_info,
                    position_ids.data(),
                    position_ids.size() * sizeof(int64_t),
                    position_ids_shape.data(),
                    position_ids_shape.size(),
                    ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,
                    &position_ids_tensor
                );
                if (status != nullptr) {
                    LOGE("Failed to create position_ids tensor: %s", cached_api->GetErrorMessage(status));
                    cached_api->ReleaseStatus(status);
                    result.success = false;
                    result.stop_reason = "error";
                    return result;
                }
                if (position_ids_tensor == nullptr) {
                    LOGE("position_ids_tensor is null after creation");
                    result.success = false;
                    result.stop_reason = "error";
                    return result;
                }
                input_tensors.push_back(position_ids_tensor);
                input_names.push_back("position_ids");
                
                // 4. past_key_values: [batch_size, num_heads, past_seq_len, head_dim]
                std::vector<std::string> kv_names;
                kv_names.reserve(num_layers * 2);  // Reserve space to prevent reallocation (2 per layer: key + value)
                for (size_t layer = 0; layer < num_layers; ++layer) {
                    // past_key
                    std::vector<int64_t> kv_shape = {1, static_cast<int64_t>(num_heads), 
                                                     static_cast<int64_t>(past_seq_len), 
                                                     static_cast<int64_t>(head_dim)};
                    
                    OrtValue* past_key_tensor = nullptr;
                    if (past_seq_len == 0) {
                        // First step: create empty tensors
                        std::vector<float> empty;
                        status = cached_api->CreateTensorWithDataAsOrtValue(
                            memory_info,
                            empty.data(),
                            0,
                            kv_shape.data(),
                            kv_shape.size(),
                            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
                            &past_key_tensor
                        );
                        if (status != nullptr) {
                            LOGE("Failed to create empty past_key tensor: %s", cached_api->GetErrorMessage(status));
                            cached_api->ReleaseStatus(status);
                            result.success = false;
                            result.stop_reason = "error";
                            return result;
                        }
                    } else {
                        status = cached_api->CreateTensorWithDataAsOrtValue(
                            memory_info,
                            past_keys[layer].data(),
                            past_keys[layer].size() * sizeof(float),
                            kv_shape.data(),
                            kv_shape.size(),
                            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
                            &past_key_tensor
                        );
                        if (status != nullptr) {
                            LOGE("Failed to create past_key tensor: %s", cached_api->GetErrorMessage(status));
                            cached_api->ReleaseStatus(status);
                            result.success = false;
                            result.stop_reason = "error";
                            return result;
                        }
                    }
                    if (past_key_tensor == nullptr) {
                        LOGE("past_key_tensor is null after creation");
                        result.success = false;
                        result.stop_reason = "error";
                        return result;
                    }
                    input_tensors.push_back(past_key_tensor);
                    kv_names.push_back("past_key_values." + std::to_string(layer) + ".key");
                    input_names.push_back(kv_names.back().c_str());
                    
                    // past_value
                    OrtValue* past_value_tensor = nullptr;
                    if (past_seq_len == 0) {
                        std::vector<float> empty;
                        status = cached_api->CreateTensorWithDataAsOrtValue(
                            memory_info,
                            empty.data(),
                            0,
                            kv_shape.data(),
                            kv_shape.size(),
                            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
                            &past_value_tensor
                        );
                        if (status != nullptr) {
                            LOGE("Failed to create empty past_value tensor: %s", cached_api->GetErrorMessage(status));
                            cached_api->ReleaseStatus(status);
                            result.success = false;
                            result.stop_reason = "error";
                            return result;
                        }
                    } else {
                        status = cached_api->CreateTensorWithDataAsOrtValue(
                            memory_info,
                            past_values[layer].data(),
                            past_values[layer].size() * sizeof(float),
                            kv_shape.data(),
                            kv_shape.size(),
                            ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
                            &past_value_tensor
                        );
                        if (status != nullptr) {
                            LOGE("Failed to create past_value tensor: %s", cached_api->GetErrorMessage(status));
                            cached_api->ReleaseStatus(status);
                            result.success = false;
                            result.stop_reason = "error";
                            return result;
                        }
                    }
                    if (past_value_tensor == nullptr) {
                        LOGE("past_value_tensor is null after creation");
                        result.success = false;
                        result.stop_reason = "error";
                        return result;
                    }
                    input_tensors.push_back(past_value_tensor);
                    kv_names.push_back("past_key_values." + std::to_string(layer) + ".value");
                    input_names.push_back(kv_names.back().c_str());
                }
                
                // Prepare output names
                std::vector<const char*> output_names = {"logits"};
                std::vector<std::string> present_kv_names;
                present_kv_names.reserve(num_layers * 2);  // Reserve space to prevent reallocation (2 per layer: key + value)
                for (size_t layer = 0; layer < num_layers; ++layer) {
                    present_kv_names.push_back("present." + std::to_string(layer) + ".key");
                    output_names.push_back(present_kv_names.back().c_str());
                    present_kv_names.push_back("present." + std::to_string(layer) + ".value");
                    output_names.push_back(present_kv_names.back().c_str());
                }
                
                // Run inference
                std::vector<OrtValue*> output_tensors(output_names.size(), nullptr);
                status = cached_api->Run(
                    session,
                    nullptr,
                    input_names.data(),
                    input_tensors.data(),
                    input_tensors.size(),
                    output_names.data(),
                    output_names.size(),
                    output_tensors.data()
                );
                
                // Clean up input tensors
                for (auto* tensor : input_tensors) {
                    if (tensor) cached_api->ReleaseValue(tensor);
                }
                
                if (status != nullptr || output_tensors[0] == nullptr) {
                    if (status) {
                        LOGE("Inference failed: %s", cached_api->GetErrorMessage(status));
                        cached_api->ReleaseStatus(status);
                    }
                    for (auto* tensor : output_tensors) {
                        if (tensor) cached_api->ReleaseValue(tensor);
                    }
                    break;
                }
                
                // Extract logits
                float* logits_data = nullptr;
                status = cached_api->GetTensorMutableData(output_tensors[0], (void**)&logits_data);
                if (status != nullptr || logits_data == nullptr) {
                    if (status) {
                        LOGE("Failed to get logits data: %s", cached_api->GetErrorMessage(status));
                        cached_api->ReleaseStatus(status);
                    }
                    for (auto* tensor : output_tensors) {
                        if (tensor) cached_api->ReleaseValue(tensor);
                    }
                    break;
                }

                const size_t logits_offset = (current_seq_len - 1) * vocab_size;
                std::vector<float> last_token_logits(
                    logits_data + logits_offset,
                    logits_data + logits_offset + vocab_size
                );
                
                // Sample next token
                int64_t next_token = sample_token(last_token_logits, options.temperature, options.top_p);
                input_ids.push_back(next_token);
                tokens_generated++;
                
                // Update KV-cache from present outputs
                size_t output_idx = 1;
                for (size_t layer = 0; layer < num_layers; ++layer) {
                    // present.key
                    float* present_key_data = nullptr;
                    cached_api->GetTensorMutableData(output_tensors[output_idx++], (void**)&present_key_data);
                    
                    OrtTensorTypeAndShapeInfo* key_shape_info = nullptr;
                    cached_api->GetTensorTypeAndShape(output_tensors[output_idx - 1], &key_shape_info);
                    size_t key_size = 0;
                    cached_api->GetTensorShapeElementCount(key_shape_info, &key_size);
                    cached_api->ReleaseTensorTypeAndShapeInfo(key_shape_info);
                    
                    past_keys[layer].assign(present_key_data, present_key_data + key_size);
                    
                    // present.value
                    float* present_value_data = nullptr;
                    cached_api->GetTensorMutableData(output_tensors[output_idx++], (void**)&present_value_data);
                    
                    OrtTensorTypeAndShapeInfo* value_shape_info = nullptr;
                    cached_api->GetTensorTypeAndShape(output_tensors[output_idx - 1], &value_shape_info);
                    size_t value_size = 0;
                    cached_api->GetTensorShapeElementCount(value_shape_info, &value_size);
                    cached_api->ReleaseTensorTypeAndShapeInfo(value_shape_info);
                    
                    past_values[layer].assign(present_value_data, present_value_data + value_size);
                }
                
                // Update past sequence length
                past_seq_len += current_seq_len;
                
                // Clean up output tensors
                for (auto* tensor : output_tensors) {
                    if (tensor) cached_api->ReleaseValue(tensor);
                }
                
                // Check for stop conditions
                if (next_token == SimpleTokenizer::EOS_TOKEN || 
                    next_token == SimpleTokenizer::PAD_TOKEN) {
                    finished = true;
                    stop_reason_str = "stop";
                    break;
                }
                
                // Check stop sequences
                for (const auto& stop_seq : options.stop_sequences) {
                    std::string current_text = tokenizer->decode(
                        std::vector<int64_t>(input_ids.begin() + original_length, input_ids.end()),
                        false
                    );
                    if (current_text.find(stop_seq) != std::string::npos) {
                        finished = true;
                        stop_reason_str = "stop_sequence";
                        break;
                    }
                }
                
                if (finished) break;
            }
            
            // ========================================================================
            // STEP 4: Detokenization
            // ========================================================================
            
            std::vector<int64_t> generated_tokens(input_ids.begin() + original_length, input_ids.end());
            std::string generated_text = tokenizer->decode(generated_tokens, true);
            
            result.text = generated_text;
            result.success = true;
            result.tokens_generated = tokens_generated;
            result.finished = finished;
            result.stop_reason = stop_reason_str;
            
            auto end_time = std::chrono::high_resolution_clock::now();
            auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);
            result.inference_time_ms = static_cast<double>(duration.count());
            
            // Calculate tokens per second, avoiding division by zero
            double tokens_per_sec = 0.0;
            if (result.inference_time_ms > 0.0) {
                tokens_per_sec = tokens_generated / (result.inference_time_ms / 1000.0);
            }
            
            LOGI("Generated %d tokens in %.2f ms (%.1f tokens/sec)", 
                 tokens_generated, result.inference_time_ms, tokens_per_sec);
            return result;
            
        } catch (const std::exception& e) {
            LOGE("Generation failed: %s", e.what());
            result.text = "";
            result.stop_reason = "error";
            result.success = false;
            return result;
        }
    }
    
    const char* get_name() const noexcept {
        return generator_name.c_str();
    }
    
    int get_context_size() const noexcept {
        return max_context_length;
    }
};

// =============================================================================
// PUBLIC API
// =============================================================================

ONNXGenerator::ONNXGenerator(
    const std::string& model_path,
    const std::string& config_json
) : impl_(std::make_unique<Impl>()) {
    if (!impl_->initialize(model_path, config_json)) {
        throw std::runtime_error("Failed to initialize ONNX generator");
    }
}

ONNXGenerator::~ONNXGenerator() = default;

GenerationResult ONNXGenerator::generate(
    const std::string& prompt,
    const GenerationOptions& options
) {
    return impl_->generate_text(prompt, options);
}

bool ONNXGenerator::is_ready() const noexcept {
    return impl_ && impl_->ready;
}

const char* ONNXGenerator::name() const noexcept {
    return impl_ ? impl_->get_name() : "ONNX-Generator";
}

int ONNXGenerator::context_size() const noexcept {
    return impl_ ? impl_->get_context_size() : 2048;
}

// =============================================================================
// FACTORY FUNCTION
// =============================================================================

std::unique_ptr<ITextGenerator> create_onnx_generator(
    const std::string& model_path,
    const std::string& config_json
) {
    return std::make_unique<ONNXGenerator>(model_path, config_json);
}

} // namespace rag
} // namespace runanywhere
