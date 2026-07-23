/**
 * @file rac_rerank_llamacpp.cpp
 * @brief RunAnywhere cross-encoder reranking backed by llama.cpp rank-pooling GGUF models.
 *
 * A reranker GGUF is a model whose context reports `LLAMA_POOLING_TYPE_RANK`: it
 * attaches a classification head that emits a single relevance score per
 * (query, document) sequence. This op formats each candidate the way the
 * reranker expects — mirroring llama.cpp's server `format_prompt_rerank`: if the
 * model ships a `rerank` chat template it is filled with the {query}/{document}
 * pair (parsing special tokens), otherwise the manual
 * `[BOS] query [EOS] [SEP] document [EOS]` layout is built from the vocab's
 * special tokens — decodes it as an isolated sequence, and reads the score from
 * `llama_get_embeddings_seq(ctx, 0)[0]`. Candidates are then sorted by
 * descending score and returned with their original indices + ranks.
 */

#include <llama.h>

#include <algorithm>
#include <chrono>
#include <climits>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

#include <dirent.h>
#include <sys/stat.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/rerank/rac_rerank_service.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

namespace {

constexpr const char* kLogCategory = "Rerank.LlamaCpp";
constexpr int32_t kDefaultMaxTokens = 512;
constexpr int32_t kMaxThreads = 8;

struct LlamaCppRerankHandle {
    std::mutex mutex;
    std::string model_id;
    std::string model_path;
    llama_model* model = nullptr;
    llama_context* context = nullptr;
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

void release_model(LlamaCppRerankHandle* handle) {
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
    handle->model_path.clear();
}

// Tokenize `text`. `add_special` is always false (BOS/EOS/SEP are added by the
// rerank formatting below); `parse_special` controls whether special/control
// tokens embedded in the text are parsed — true for chat-template prompts, false
// for raw query/document text.
rac_result_t tokenize_plain(const llama_vocab* vocabulary, const char* text, bool parse_special,
                            std::vector<llama_token>* output) {
    output->clear();
    const size_t text_length = std::strlen(text);
    if (text_length == 0) {
        return RAC_SUCCESS;
    }
    if (text_length > static_cast<size_t>(INT32_MAX)) {
        return RAC_ERROR_TEXT_TOO_LONG;
    }
    int32_t token_count = llama_tokenize(vocabulary, text, static_cast<int32_t>(text_length),
                                         nullptr, 0, false, parse_special);
    if (token_count == INT32_MIN) {
        return RAC_ERROR_TEXT_TOO_LONG;
    }
    if (token_count < 0) {
        token_count = -token_count;
    }
    if (token_count == 0) {
        return RAC_SUCCESS;
    }
    output->resize(static_cast<size_t>(token_count));
    const int32_t written = llama_tokenize(vocabulary, text, static_cast<int32_t>(text_length),
                                            output->data(), token_count, false, parse_special);
    if (written < 0 || written > token_count) {
        output->clear();
        return RAC_ERROR_INFERENCE_FAILED;
    }
    output->resize(static_cast<size_t>(written));
    return RAC_SUCCESS;
}

// In-place replace-all, used to fill {query}/{document} into a rerank chat
// template (mirrors llama.cpp's string_replace_all).
void replace_all(std::string& subject, const std::string& from, const std::string& to) {
    if (from.empty()) {
        return;
    }
    size_t pos = 0;
    while ((pos = subject.find(from, pos)) != std::string::npos) {
        subject.replace(pos, from.size(), to);
        pos += to.size();
    }
}

// Fallback token layout `[BOS] query [EOS] [SEP] doc [EOS]` for rerankers that do
// NOT ship a `rerank` chat template. Mirrors the fallback branch of llama.cpp's
// server `format_prompt_rerank`: BOS/EOS/SEP are gated on the vocab's
// add_bos/add_eos/add_sep metadata (NOT merely on token presence), and SEP
// substitutes for EOS when the vocab has no distinct EOS token. Any token that
// resolves to LLAMA_TOKEN_NULL is skipped so an invalid id can never reach the
// decode batch. The document is truncated if the combined sequence would
// overflow the context window.
std::vector<llama_token> format_rerank_fallback(const llama_vocab* vocab,
                                                const std::vector<llama_token>& query,
                                                const std::vector<llama_token>& doc,
                                                size_t max_tokens) {
    const llama_token bos = llama_vocab_bos(vocab);
    llama_token eos = llama_vocab_eos(vocab);
    if (eos == LLAMA_TOKEN_NULL) {
        eos = llama_vocab_sep(vocab);
    }
    const llama_token sep = llama_vocab_sep(vocab);

    const bool add_bos = llama_vocab_get_add_bos(vocab) && bos != LLAMA_TOKEN_NULL;
    const bool add_eos = llama_vocab_get_add_eos(vocab) && eos != LLAMA_TOKEN_NULL;
    const bool add_sep = llama_vocab_get_add_sep(vocab) && sep != LLAMA_TOKEN_NULL;

    // Fixed cost = optional BOS + query + optional EOS (after query and after
    // doc) + optional SEP. Reserve room for the document from whatever remains.
    size_t fixed = query.size();
    if (add_bos) {
        fixed += 1;
    }
    if (add_eos) {
        fixed += 2;  // one after query, one after doc
    }
    if (add_sep) {
        fixed += 1;
    }
    size_t doc_budget = doc.size();
    if (max_tokens > fixed) {
        doc_budget = std::min(doc_budget, max_tokens - fixed);
    } else {
        doc_budget = 0;
    }

    std::vector<llama_token> result;
    result.reserve(fixed + doc_budget);
    if (add_bos) {
        result.push_back(bos);
    }
    result.insert(result.end(), query.begin(), query.end());
    if (add_eos) {
        result.push_back(eos);
    }
    if (add_sep) {
        result.push_back(sep);
    }
    result.insert(result.end(), doc.begin(), doc.begin() + static_cast<std::ptrdiff_t>(doc_budget));
    if (add_eos) {
        result.push_back(eos);
    }
    return result;
}

// Template path: fill the model's `rerank` chat template with the {query}/
// {document} pair and tokenize the whole prompt WITH special tokens, matching
// the template branch of llama.cpp's server `format_prompt_rerank`. The prompt
// is capped to the context window (head-kept) so the decode batch always fits.
rac_result_t format_rerank_template(const llama_vocab* vocab, const char* rerank_template,
                                    const char* query, const char* doc, size_t max_tokens,
                                    std::vector<llama_token>* out) {
    std::string prompt(rerank_template);
    replace_all(prompt, "{query}", query != nullptr ? query : "");
    replace_all(prompt, "{document}", doc != nullptr ? doc : "");
    const rac_result_t rc = tokenize_plain(vocab, prompt.c_str(), /*parse_special=*/true, out);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    if (out->size() > max_tokens) {
        out->resize(max_tokens);
    }
    return RAC_SUCCESS;
}

rac_result_t score_sequence(LlamaCppRerankHandle* handle, const std::vector<llama_token>& tokens,
                            float* out_score) {
    if (tokens.empty()) {
        // Nothing to score — an empty document is minimally relevant.
        *out_score = -std::numeric_limits<float>::infinity();
        return RAC_SUCCESS;
    }
    if (tokens.size() > static_cast<size_t>(INT32_MAX)) {
        return RAC_ERROR_TEXT_TOO_LONG;
    }

    LlamaBatchGuard batch_guard(llama_batch_init(static_cast<int32_t>(tokens.size()), 0, 1));
    llama_batch& batch = batch_guard.batch;
    if (batch.token == nullptr || batch.pos == nullptr || batch.n_seq_id == nullptr ||
        batch.seq_id == nullptr || batch.logits == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    batch.n_tokens = static_cast<int32_t>(tokens.size());
    for (int32_t index = 0; index < batch.n_tokens; ++index) {
        batch.token[index] = tokens[static_cast<size_t>(index)];
        batch.pos[index] = index;
        batch.n_seq_id[index] = 1;
        batch.seq_id[index][0] = 0;
        batch.logits[index] = 1;
    }

    llama_memory_clear(llama_get_memory(handle->context), true);
    if (llama_decode(handle->context, batch) != 0) {
        RAC_LOG_ERROR(kLogCategory, "llama_decode failed while scoring %d tokens", batch.n_tokens);
        return RAC_ERROR_INFERENCE_FAILED;
    }

    const float* scores = llama_get_embeddings_seq(handle->context, 0);
    if (scores == nullptr) {
        return RAC_ERROR_INFERENCE_FAILED;
    }
    *out_score = scores[0];
    return RAC_SUCCESS;
}

struct ScoredCandidate {
    float score;
    uint32_t original_index;
    const char* id;
};

rac_result_t copy_result(std::vector<ScoredCandidate>& scored, const std::string& model_id,
                         uint32_t top_n, int64_t processing_time_ms, rac_rerank_result_t* output) {
    *output = {};
    output->processing_time_ms = processing_time_ms;
    output->model_id = strdup(model_id.c_str());
    if (!model_id.empty() && output->model_id == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    std::stable_sort(scored.begin(), scored.end(),
                     [](const ScoredCandidate& a, const ScoredCandidate& b) {
                         return a.score > b.score;
                     });

    size_t emit = scored.size();
    if (top_n > 0 && static_cast<size_t>(top_n) < emit) {
        emit = static_cast<size_t>(top_n);
    }
    if (emit == 0) {
        return RAC_SUCCESS;
    }

    output->items =
        static_cast<rac_rerank_scored_item_t*>(std::calloc(emit, sizeof(rac_rerank_scored_item_t)));
    if (output->items == nullptr) {
        rac_rerank_result_free(output);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    output->item_count = emit;
    for (size_t i = 0; i < emit; ++i) {
        output->items[i].score = scored[i].score;
        output->items[i].original_index = scored[i].original_index;
        output->items[i].rank = static_cast<uint32_t>(i);
        if (scored[i].id != nullptr && scored[i].id[0] != '\0') {
            output->items[i].id = strdup(scored[i].id);
            if (output->items[i].id == nullptr) {
                rac_rerank_result_free(output);
                return RAC_ERROR_OUT_OF_MEMORY;
            }
        }
    }
    return RAC_SUCCESS;
}

rac_result_t llamacpp_rerank_initialize(void* implementation, const char* model_path) {
    if (implementation == nullptr || model_path == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* handle = static_cast<LlamaCppRerankHandle*>(implementation);
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
        RAC_LOG_ERROR(kLogCategory, "failed to load reranker model: %s", resolved_path.c_str());
        return RAC_ERROR_MODEL_LOAD_FAILED;
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
    context_params.pooling_type = LLAMA_POOLING_TYPE_RANK;
    context_params.no_perf = true;

    handle->context = llama_init_from_model(handle->model, context_params);
    if (handle->context == nullptr) {
        release_model(handle);
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }
    if (llama_pooling_type(handle->context) != LLAMA_POOLING_TYPE_RANK) {
        RAC_LOG_ERROR(kLogCategory,
                      "GGUF is not a reranker (no rank-pooling classification head); use the "
                      "embeddings or LLM primitive instead");
        release_model(handle);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    handle->model_path = resolved_path;
    RAC_LOG_INFO(kLogCategory, "loaded reranker %s (max_tokens=%d)", handle->model_id.c_str(),
                 handle->max_tokens);
    return RAC_SUCCESS;
}

rac_result_t llamacpp_rerank_rerank(void* implementation, const char* query,
                                    const rac_rerank_candidate_t* candidates,
                                    size_t candidate_count, const rac_rerank_options_t* options,
                                    rac_rerank_result_t* output) {
    if (implementation == nullptr || query == nullptr || output == nullptr ||
        (candidate_count > 0 && candidates == nullptr)) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* handle = static_cast<LlamaCppRerankHandle*>(implementation);
    std::lock_guard<std::mutex> lock(handle->mutex);
    if (handle->model == nullptr || handle->context == nullptr) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }

    const auto started = std::chrono::steady_clock::now();
    const llama_vocab* vocab = llama_model_get_vocab(handle->model);
    llama_set_n_threads(handle->context, handle->default_threads, handle->default_threads);

    // Prefer the model's `rerank` chat template when present (Qwen3-Reranker and
    // other cross-encoders ship one); otherwise fall back to the manual
    // BOS/EOS/SEP layout. Mirrors llama.cpp's server `format_prompt_rerank`.
    const char* rerank_template = llama_model_chat_template(handle->model, "rerank");

    std::vector<llama_token> query_tokens;
    if (rerank_template == nullptr) {
        const rac_result_t query_rc =
            tokenize_plain(vocab, query, /*parse_special=*/false, &query_tokens);
        if (query_rc != RAC_SUCCESS) {
            return query_rc;
        }
    }

    std::vector<ScoredCandidate> scored;
    scored.reserve(candidate_count);
    for (size_t i = 0; i < candidate_count; ++i) {
        const char* text = candidates[i].text != nullptr ? candidates[i].text : "";
        std::vector<llama_token> sequence;
        if (rerank_template != nullptr) {
            const rac_result_t fmt_rc =
                format_rerank_template(vocab, rerank_template, query, text,
                                       static_cast<size_t>(handle->max_tokens), &sequence);
            if (fmt_rc != RAC_SUCCESS) {
                return fmt_rc;
            }
        } else {
            std::vector<llama_token> doc_tokens;
            const rac_result_t doc_rc =
                tokenize_plain(vocab, text, /*parse_special=*/false, &doc_tokens);
            if (doc_rc != RAC_SUCCESS) {
                return doc_rc;
            }
            sequence = format_rerank_fallback(vocab, query_tokens, doc_tokens,
                                              static_cast<size_t>(handle->max_tokens));
        }
        float score = 0.0f;
        const rac_result_t score_rc = score_sequence(handle, sequence, &score);
        if (score_rc != RAC_SUCCESS) {
            return score_rc;
        }
        scored.push_back(ScoredCandidate{score, static_cast<uint32_t>(i), candidates[i].id});
    }

    const int64_t elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
                                std::chrono::steady_clock::now() - started)
                                .count();
    const uint32_t top_n = options != nullptr ? options->top_n : 0;
    return copy_result(scored, handle->model_id, top_n, elapsed, output);
}

rac_result_t llamacpp_rerank_cleanup(void* implementation) {
    if (implementation == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* handle = static_cast<LlamaCppRerankHandle*>(implementation);
    std::lock_guard<std::mutex> lock(handle->mutex);
    release_model(handle);
    return RAC_SUCCESS;
}

void llamacpp_rerank_destroy(void* implementation) {
    auto* handle = static_cast<LlamaCppRerankHandle*>(implementation);
    if (handle == nullptr) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        release_model(handle);
    }
    delete handle;
}

rac_result_t llamacpp_rerank_create(const char* model_id, const char* /*config_json*/,
                                    void** output) {
    if (model_id == nullptr || output == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *output = nullptr;
    llama_backend_init();
    auto handle = std::make_unique<LlamaCppRerankHandle>();
    handle->model_id = model_id;
    const unsigned int hardware_threads = std::thread::hardware_concurrency();
    handle->default_threads = static_cast<int32_t>(std::clamp(
        hardware_threads == 0 ? 1U : hardware_threads, 1U, static_cast<unsigned int>(kMaxThreads)));
    *output = handle.release();
    return RAC_SUCCESS;
}

}  // namespace

extern "C" const rac_rerank_service_ops_t g_llamacpp_rerank_ops = {
    .initialize = llamacpp_rerank_initialize,
    .rerank = llamacpp_rerank_rerank,
    .cleanup = llamacpp_rerank_cleanup,
    .destroy = llamacpp_rerank_destroy,
    .create = llamacpp_rerank_create,
};
