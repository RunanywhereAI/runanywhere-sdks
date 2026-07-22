/**
 * @file rac_embeddings_llamacpp.cpp
 * @brief RunAnywhere embeddings operations backed by llama.cpp GGUF models.
 */

#include <llama.h>

#include <algorithm>
#include <chrono>
#include <climits>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <vector>

#include "core/internal/platform_compat.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/embeddings/rac_embeddings_service.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

namespace {

constexpr const char* kLogCategory = "Embeddings.LlamaCpp";
constexpr int32_t kDefaultMaxTokens = RAC_EMBEDDINGS_DEFAULT_MAX_TOKENS;
constexpr int32_t kMaxThreads = 8;

struct LlamaCppEmbeddingsHandle {
    std::mutex mutex;
    std::string model_id;
    std::string model_path;
    llama_model* model = nullptr;
    llama_context* context = nullptr;
    size_t dimension = 0;
    int32_t max_tokens = kDefaultMaxTokens;
    int32_t default_threads = 1;
};

struct LlamaBatchGuard {
    explicit LlamaBatchGuard(llama_batch value) : batch(value) {}
    ~LlamaBatchGuard() { llama_batch_free(batch); }

    LlamaBatchGuard(const LlamaBatchGuard&) = delete;
    LlamaBatchGuard& operator=(const LlamaBatchGuard&) = delete;

    llama_batch batch;
};

std::string resolve_gguf_path(const char* model_path) {
    if (model_path == nullptr || model_path[0] == '\0') {
        return {};
    }

    std::string resolved(model_path);
    struct stat path_stat{};
    if (stat(model_path, &path_stat) != 0 || !S_ISDIR(path_stat.st_mode)) {
        return resolved;
    }

    DIR* directory = opendir(model_path);
    if (directory == nullptr) {
        return {};
    }
    while (const dirent* entry = readdir(directory)) {
        const std::string filename(entry->d_name);
        if (filename.size() > 5 && filename.ends_with(".gguf")) {
            resolved = std::string(model_path) + "/" + filename;
            closedir(directory);
            return resolved;
        }
    }
    closedir(directory);
    return {};
}

void release_model(LlamaCppEmbeddingsHandle* handle) {
    if (handle == nullptr) {
        return;
    }
    if (handle->context != nullptr) {
        llama_free(handle->context);
        handle->context = nullptr;
    }
    if (handle->model != nullptr) {
        llama_model_free(handle->model);
        handle->model = nullptr;
    }
    handle->dimension = 0;
    handle->model_path.clear();
}

void normalize_l2(std::vector<float>* values) {
    double sum_squares = 0.0;
    for (const float value : *values) {
        sum_squares += static_cast<double>(value) * static_cast<double>(value);
    }
    if (sum_squares <= 0.0) {
        return;
    }
    const float inverse_norm = static_cast<float>(1.0 / std::sqrt(sum_squares));
    for (float& value : *values) {
        value *= inverse_norm;
    }
}

enum llama_pooling_type llama_pooling_from_rac(int32_t pooling) {
    switch (pooling) {
        case RAC_EMBEDDINGS_POOLING_MEAN:
            return LLAMA_POOLING_TYPE_MEAN;
        case RAC_EMBEDDINGS_POOLING_CLS:
            return LLAMA_POOLING_TYPE_CLS;
        case RAC_EMBEDDINGS_POOLING_LAST:
            return LLAMA_POOLING_TYPE_LAST;
        default:
            return LLAMA_POOLING_TYPE_UNSPECIFIED;
    }
}

rac_result_t tokenize(const llama_vocab* vocabulary, const char* text,
                      std::vector<llama_token>* output) {
    const size_t text_length = std::strlen(text);
    if (text_length > static_cast<size_t>(INT32_MAX)) {
        return RAC_ERROR_TEXT_TOO_LONG;
    }
    int32_t token_count =
        llama_tokenize(vocabulary, text, static_cast<int32_t>(text_length), nullptr, 0, true, true);
    if (token_count == INT32_MIN) {
        return RAC_ERROR_TEXT_TOO_LONG;
    }
    if (token_count < 0) {
        token_count = -token_count;
    }
    if (token_count <= 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    output->resize(static_cast<size_t>(token_count));
    const int32_t written = llama_tokenize(vocabulary, text, static_cast<int32_t>(text_length),
                                           output->data(), token_count, true, true);
    if (written <= 0 || written > token_count) {
        output->clear();
        return RAC_ERROR_INFERENCE_FAILED;
    }
    output->resize(static_cast<size_t>(written));
    return RAC_SUCCESS;
}

rac_result_t decode_token_window(LlamaCppEmbeddingsHandle* handle,
                                 const std::vector<llama_token>& tokens, size_t offset,
                                 size_t count, const rac_embeddings_options_t* options,
                                 std::vector<float>* output) {
    if (count == 0 || count > static_cast<size_t>(INT32_MAX)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    LlamaBatchGuard batch_guard(llama_batch_init(static_cast<int32_t>(count), 0, 1));
    llama_batch& batch = batch_guard.batch;
    if (batch.token == nullptr || batch.pos == nullptr || batch.n_seq_id == nullptr ||
        batch.seq_id == nullptr || batch.logits == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    batch.n_tokens = static_cast<int32_t>(count);
    for (int32_t index = 0; index < batch.n_tokens; ++index) {
        batch.token[index] = tokens[offset + static_cast<size_t>(index)];
        batch.pos[index] = index;
        batch.n_seq_id[index] = 1;
        batch.seq_id[index][0] = 0;
        batch.logits[index] = 1;
    }

    llama_memory_clear(llama_get_memory(handle->context), true);
    if (llama_decode(handle->context, batch) != 0) {
        RAC_LOG_ERROR(kLogCategory, "llama_decode failed while embedding %d tokens",
                      batch.n_tokens);
        return RAC_ERROR_INFERENCE_FAILED;
    }

    const int32_t requested_pooling = options != nullptr ? options->pooling : -1;
    if (requested_pooling < -1 ||
        requested_pooling > static_cast<int32_t>(RAC_EMBEDDINGS_POOLING_LAST)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const enum llama_pooling_type pooling = llama_pooling_type(handle->context);
    if (pooling == LLAMA_POOLING_TYPE_RANK) {
        RAC_LOG_ERROR(
            kLogCategory,
            "reranker GGUF requested through embeddings; reranking requires its own primitive");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    // llama.cpp fixes native sequence pooling when the context is created.
    // Never report success for an explicit per-call override that this context
    // cannot honor; callers must receive a hard capability boundary instead of
    // a vector produced with silently different semantics.
    if (pooling != LLAMA_POOLING_TYPE_NONE && requested_pooling >= 0 &&
        llama_pooling_from_rac(requested_pooling) != pooling) {
        RAC_LOG_ERROR(kLogCategory,
                      "requested pooling=%d cannot override native llama.cpp pooling=%d",
                      requested_pooling, static_cast<int>(pooling));
        return RAC_ERROR_NOT_SUPPORTED;
    }

    output->assign(handle->dimension, 0.0f);
    if (pooling == LLAMA_POOLING_TYPE_NONE) {
        const rac_embeddings_pooling_t manual_pooling =
            requested_pooling >= 0 ? static_cast<rac_embeddings_pooling_t>(requested_pooling)
                                   : RAC_EMBEDDINGS_POOLING_MEAN;
        if (manual_pooling == RAC_EMBEDDINGS_POOLING_CLS ||
            manual_pooling == RAC_EMBEDDINGS_POOLING_LAST) {
            const int32_t index =
                manual_pooling == RAC_EMBEDDINGS_POOLING_CLS ? 0 : static_cast<int32_t>(count) - 1;
            const float* embedding = llama_get_embeddings_ith(handle->context, index);
            if (embedding == nullptr) {
                return RAC_ERROR_INFERENCE_FAILED;
            }
            std::copy_n(embedding, handle->dimension, output->data());
        } else {
            for (int32_t index = 0; index < static_cast<int32_t>(count); ++index) {
                const float* embedding = llama_get_embeddings_ith(handle->context, index);
                if (embedding == nullptr) {
                    return RAC_ERROR_INFERENCE_FAILED;
                }
                for (size_t dimension = 0; dimension < handle->dimension; ++dimension) {
                    (*output)[dimension] += embedding[dimension];
                }
            }
            const float inverse_count = 1.0f / static_cast<float>(count);
            for (float& value : *output) {
                value *= inverse_count;
            }
        }
    } else {
        const float* embedding = llama_get_embeddings_seq(handle->context, 0);
        if (embedding == nullptr) {
            return RAC_ERROR_INFERENCE_FAILED;
        }
        std::copy_n(embedding, handle->dimension, output->data());
    }

    return RAC_SUCCESS;
}

rac_result_t compute_embedding(LlamaCppEmbeddingsHandle* handle, const char* text,
                               const rac_embeddings_options_t* options, std::vector<float>* output,
                               int32_t* output_tokens) {
    if (handle == nullptr || text == nullptr || output == nullptr || output_tokens == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (handle->model == nullptr || handle->context == nullptr || handle->dimension == 0) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    const int32_t requested_threads = options != nullptr ? options->n_threads : 0;
    if (requested_threads < 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    const int32_t threads =
        requested_threads > 0 ? std::min(requested_threads, kMaxThreads) : handle->default_threads;
    llama_set_n_threads(handle->context, threads, threads);

    std::vector<llama_token> tokens;
    const rac_result_t token_rc = tokenize(llama_model_get_vocab(handle->model), text, &tokens);
    if (token_rc != RAC_SUCCESS) {
        return token_rc;
    }

    const int32_t truncate_policy = options != nullptr ? options->truncate : -1;
    if (truncate_policy < -1 || truncate_policy > 1) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    const size_t window_size = static_cast<size_t>(handle->max_tokens);
    if (tokens.size() > window_size && truncate_policy == 0) {
        return RAC_ERROR_TEXT_TOO_LONG;
    }

    const bool truncate = tokens.size() > window_size && truncate_policy == 1;
    const size_t processed_tokens = truncate ? window_size : tokens.size();
    const size_t window_count = (processed_tokens + window_size - 1) / window_size;
    output->assign(handle->dimension, 0.0f);
    for (size_t window = 0; window < window_count; ++window) {
        const size_t offset = window * window_size;
        const size_t count = std::min(window_size, processed_tokens - offset);
        std::vector<float> window_embedding;
        const rac_result_t decode_rc =
            decode_token_window(handle, tokens, offset, count, options, &window_embedding);
        if (decode_rc != RAC_SUCCESS) {
            return decode_rc;
        }
        for (size_t dimension = 0; dimension < handle->dimension; ++dimension) {
            (*output)[dimension] += window_embedding[dimension];
        }
    }
    if (window_count > 1) {
        const float inverse_windows = 1.0f / static_cast<float>(window_count);
        for (float& value : *output) {
            value *= inverse_windows;
        }
    }

    const int32_t requested_normalize = options != nullptr ? options->normalize : -1;
    if (requested_normalize < -1 ||
        requested_normalize > static_cast<int32_t>(RAC_EMBEDDINGS_NORMALIZE_L2)) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (requested_normalize < 0 ||
        requested_normalize == static_cast<int32_t>(RAC_EMBEDDINGS_NORMALIZE_L2)) {
        normalize_l2(output);
    }
    *output_tokens = static_cast<int32_t>(processed_tokens);
    return RAC_SUCCESS;
}

rac_result_t copy_results(const std::vector<std::vector<float>>& embeddings, int32_t total_tokens,
                          int64_t processing_time_ms, rac_embeddings_result_t* output) {
    *output = {};
    output->num_embeddings = embeddings.size();
    output->dimension = embeddings.empty() ? 0 : embeddings.front().size();
    output->processing_time_ms = processing_time_ms;
    output->total_tokens = total_tokens;
    if (embeddings.empty()) {
        return RAC_SUCCESS;
    }

    output->embeddings = static_cast<rac_embedding_vector_t*>(
        std::calloc(embeddings.size(), sizeof(rac_embedding_vector_t)));
    if (output->embeddings == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    for (size_t index = 0; index < embeddings.size(); ++index) {
        const std::vector<float>& embedding = embeddings[index];
        output->embeddings[index].dimension = embedding.size();
        output->embeddings[index].data =
            static_cast<float*>(std::malloc(embedding.size() * sizeof(float)));
        if (output->embeddings[index].data == nullptr) {
            rac_embeddings_result_free(output);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        std::memcpy(output->embeddings[index].data, embedding.data(),
                    embedding.size() * sizeof(float));
    }
    return RAC_SUCCESS;
}

rac_result_t llamacpp_embeddings_initialize(void* implementation, const char* model_path) {
    if (implementation == nullptr || model_path == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* handle = static_cast<LlamaCppEmbeddingsHandle*>(implementation);
    std::lock_guard<std::mutex> lock(handle->mutex);
    release_model(handle);

    const std::string resolved_path = resolve_gguf_path(model_path);
    if (resolved_path.empty()) {
        RAC_LOG_ERROR(kLogCategory, "no GGUF file found at model path");
        return RAC_ERROR_MODEL_NOT_FOUND;
    }

    llama_model_params model_params = llama_model_default_params();
#if defined(__EMSCRIPTEN__) || defined(__ANDROID__)
    model_params.use_mmap = false;
#endif
#if defined(GGML_USE_METAL) || defined(GGML_USE_CUDA) || defined(GGML_USE_VULKAN) || \
    defined(GGML_USE_WEBGPU)
    model_params.n_gpu_layers = -1;
#else
    model_params.n_gpu_layers = 0;
#endif
#if defined(__APPLE__) && TARGET_OS_SIMULATOR
    model_params.n_gpu_layers = 0;
#endif

    handle->model = llama_model_load_from_file(resolved_path.c_str(), model_params);
    if (handle->model == nullptr) {
        RAC_LOG_ERROR(kLogCategory, "failed to load embedding model: %s", resolved_path.c_str());
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }
    if (llama_model_has_encoder(handle->model) && llama_model_has_decoder(handle->model)) {
        release_model(handle);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    const int32_t training_context = llama_model_n_ctx_train(handle->model);
    handle->max_tokens =
        training_context > 0 ? std::min(training_context, kDefaultMaxTokens) : kDefaultMaxTokens;
    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = static_cast<uint32_t>(handle->max_tokens);
    context_params.n_batch = static_cast<uint32_t>(handle->max_tokens);
    context_params.n_ubatch = static_cast<uint32_t>(handle->max_tokens);
    context_params.n_seq_max = 1;
    context_params.n_threads = handle->default_threads;
    context_params.n_threads_batch = handle->default_threads;
    context_params.embeddings = true;
    context_params.pooling_type = LLAMA_POOLING_TYPE_UNSPECIFIED;
    context_params.attention_type = LLAMA_ATTENTION_TYPE_UNSPECIFIED;
    context_params.no_perf = true;

    handle->context = llama_init_from_model(handle->model, context_params);
    if (handle->context == nullptr) {
        release_model(handle);
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }
    if (llama_pooling_type(handle->context) == LLAMA_POOLING_TYPE_RANK) {
        RAC_LOG_ERROR(kLogCategory, "rank-pooling GGUF is a reranker, not an embedding model");
        release_model(handle);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    const int32_t dimension = llama_model_n_embd_out(handle->model);
    if (dimension <= 0) {
        release_model(handle);
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
    handle->dimension = static_cast<size_t>(dimension);
    handle->model_path = resolved_path;
    RAC_LOG_INFO(kLogCategory, "loaded %s (dimension=%zu, max_tokens=%d)", handle->model_id.c_str(),
                 handle->dimension, handle->max_tokens);
    return RAC_SUCCESS;
}

rac_result_t llamacpp_embeddings_embed(void* implementation, const char* text,
                                       const rac_embeddings_options_t* options,
                                       rac_embeddings_result_t* output) {
    if (implementation == nullptr || text == nullptr || output == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* handle = static_cast<LlamaCppEmbeddingsHandle*>(implementation);
    std::lock_guard<std::mutex> lock(handle->mutex);
    const auto started = std::chrono::steady_clock::now();
    std::vector<float> embedding;
    int32_t token_count = 0;
    const rac_result_t result = compute_embedding(handle, text, options, &embedding, &token_count);
    if (result != RAC_SUCCESS) {
        return result;
    }
    const int64_t elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - started)
                                .count();
    std::vector<std::vector<float>> embeddings;
    embeddings.push_back(std::move(embedding));
    return copy_results(embeddings, token_count, elapsed, output);
}

rac_result_t llamacpp_embeddings_embed_batch(void* implementation, const char* const* texts,
                                             size_t num_texts,
                                             const rac_embeddings_options_t* options,
                                             rac_embeddings_result_t* output) {
    if (implementation == nullptr || texts == nullptr || output == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* handle = static_cast<LlamaCppEmbeddingsHandle*>(implementation);
    std::lock_guard<std::mutex> lock(handle->mutex);
    const auto started = std::chrono::steady_clock::now();
    const int32_t requested_batch_size = options != nullptr ? options->batch_size : 0;
    if (requested_batch_size < 0 || requested_batch_size > RAC_EMBEDDINGS_MAX_BATCH_SIZE) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    const size_t batch_size = requested_batch_size > 0 ? static_cast<size_t>(requested_batch_size)
                                                       : std::max<size_t>(num_texts, 1);
    std::vector<std::vector<float>> embeddings;
    embeddings.reserve(num_texts);
    int32_t total_tokens = 0;
    for (size_t batch_begin = 0; batch_begin < num_texts; batch_begin += batch_size) {
        const size_t batch_end = std::min(num_texts, batch_begin + batch_size);
        for (size_t index = batch_begin; index < batch_end; ++index) {
            if (texts[index] == nullptr) {
                return RAC_ERROR_NULL_POINTER;
            }
            std::vector<float> embedding;
            int32_t token_count = 0;
            const rac_result_t result =
                compute_embedding(handle, texts[index], options, &embedding, &token_count);
            if (result != RAC_SUCCESS) {
                return result;
            }
            if (token_count > INT32_MAX - total_tokens) {
                return RAC_ERROR_TEXT_TOO_LONG;
            }
            total_tokens += token_count;
            embeddings.push_back(std::move(embedding));
        }
    }
    const int64_t elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - started)
                                .count();
    return copy_results(embeddings, total_tokens, elapsed, output);
}

rac_result_t llamacpp_embeddings_get_info(void* implementation, rac_embeddings_info_t* output) {
    if (implementation == nullptr || output == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* handle = static_cast<LlamaCppEmbeddingsHandle*>(implementation);
    std::lock_guard<std::mutex> lock(handle->mutex);
    output->is_ready = handle->context != nullptr ? RAC_TRUE : RAC_FALSE;
    output->current_model = handle->model_id.c_str();
    output->dimension = handle->dimension;
    output->max_tokens = handle->max_tokens;
    return RAC_SUCCESS;
}

rac_result_t llamacpp_embeddings_cleanup(void* implementation) {
    if (implementation == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* handle = static_cast<LlamaCppEmbeddingsHandle*>(implementation);
    std::lock_guard<std::mutex> lock(handle->mutex);
    release_model(handle);
    return RAC_SUCCESS;
}

void llamacpp_embeddings_destroy(void* implementation) {
    auto* handle = static_cast<LlamaCppEmbeddingsHandle*>(implementation);
    if (handle == nullptr) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        release_model(handle);
    }
    delete handle;
}

rac_result_t llamacpp_embeddings_create(const char* model_id, const char* /*config_json*/,
                                        void** output) {
    if (model_id == nullptr || output == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *output = nullptr;
    llama_backend_init();
    auto handle = std::make_unique<LlamaCppEmbeddingsHandle>();
    handle->model_id = model_id;
    const unsigned int hardware_threads = std::thread::hardware_concurrency();
    handle->default_threads = static_cast<int32_t>(std::clamp(
        hardware_threads == 0 ? 1U : hardware_threads, 1U, static_cast<unsigned int>(kMaxThreads)));
    *output = handle.release();
    return RAC_SUCCESS;
}

}  // namespace

extern "C" const rac_embeddings_service_ops_t g_llamacpp_embeddings_ops = {
    .initialize = llamacpp_embeddings_initialize,
    .embed = llamacpp_embeddings_embed,
    .embed_batch = llamacpp_embeddings_embed_batch,
    .get_info = llamacpp_embeddings_get_info,
    .cleanup = llamacpp_embeddings_cleanup,
    .destroy = llamacpp_embeddings_destroy,
    .create = llamacpp_embeddings_create,
};
