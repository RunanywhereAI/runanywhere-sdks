/**
 * @file rac_decision_llamacpp.cpp
 * @brief RunAnywhere joint decision scoring backed by llama.cpp.
 *
 * A decision GGUF is a model whose architecture attaches a joint decision head:
 * one forward pass over a prompt that carries the whole request (state + every
 * question + every option) scores all options at once, and the per-option
 * scores come back as rows of the embeddings output. This op:
 *
 *   1. renders the model's bundled decision template (read from the GGUF),
 *   2. tags each token with its decision span (question / option / none),
 *   3. encodes once and reads one score per option,
 *   4. turns scores into probabilities + choice/noul/score + confidence.
 *
 * The span construction lives in decision_prompt.h so it can be tested without
 * a real model file.
 */

#include <llama.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <map>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

#include "core/internal/platform_compat.h"
#include <sys/stat.h>

#include "decision_prompt.h"
#include "d1_decision.h"
#include "llamacpp_logging.h"

#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/decision/rac_decision_service.h"

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

namespace {

constexpr const char* kLogCategory = "Decision.LlamaCpp";
constexpr int32_t kMaxThreads = 8;
constexpr int32_t kDefaultContext = 8192;
// The GGUF metadata key under which a decision model ships its template.
constexpr const char* kDecisionTemplateName = "systemone";

struct LlamaCppDecisionHandle {
    std::mutex mutex;
    std::string model_id;
    std::string model_path;
    llama_model* model = nullptr;
    llama_context* context = nullptr;
    int32_t max_tokens = kDefaultContext;
    int32_t default_threads = 1;
    // Per-question calibration read from clef.decision.temperature.* at load:
    // key "<type>" or "<type>.<bucket>", value the divisor for that question's
    // softmax. Empty when the GGUF carries no such keys (the model's scores
    // are then used as-is, which is the trained 1.0 case).
    std::map<std::string, float> temperatures;
    // Prompt-wording version the checkpoint declares
    // (clef.decision.prompt_format_version); 0 when the GGUF states none. A
    // request pinning a different version is refused rather than scored with
    // wording the caller did not expect.
    uint32_t prompt_format_version = 0;
    rac_llamacpp_d1_kind d1_kind = rac_llamacpp_d1_kind::none;
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

void release_model(LlamaCppDecisionHandle* handle) {
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
    handle->temperatures.clear();
    handle->prompt_format_version = 0;
    handle->d1_kind = rac_llamacpp_d1_kind::none;
    handle->model_path.clear();
}

// Reads the per-question calibration from the GGUF, as the reference does:
// "<arch>.decision.temperature.<type>" or
// "<arch>.decision.temperature.<type>.<bucket>", a positive divisor used for
// that question kind's softmax. A GGUF without these keys takes the trained
// 1.0. A key that is present but not a positive number is a broken model file
// and fails the load rather than silently changing every probability.
rac_result_t load_temperatures(LlamaCppDecisionHandle* handle) {
    handle->temperatures.clear();
    char arch[64] = {0};
    if (llama_model_meta_val_str(handle->model, "general.architecture", arch, sizeof(arch)) < 0) {
        return RAC_SUCCESS;
    }
    const std::string prefix = std::string(arch) + ".decision.temperature.";
    const int32_t meta_count = llama_model_meta_count(handle->model);
    for (int32_t i = 0; i < meta_count; ++i) {
        char key[256];
        char value[64];
        if (llama_model_meta_key_by_index(handle->model, i, key, sizeof(key)) < 0 ||
            !std::string(key).starts_with(prefix)) {
            continue;
        }
        if (llama_model_meta_val_str_by_index(handle->model, i, value, sizeof(value)) < 0) {
            continue;
        }
        const float temperature = std::strtof(value, nullptr);
        if (temperature <= 0.0f) {
            RAC_LOG_ERROR(kLogCategory, "invalid decision temperature: %s = %s", key, value);
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        handle->temperatures[std::string(key).substr(prefix.size())] = temperature;
    }
    return RAC_SUCCESS;
}

// Reads the prompt-wording version the checkpoint declares
// (<arch>.decision.prompt_format_version). A GGUF that states none is the clef
// lineage, whose served wording the contract fixes at version 3; a conversion
// that changes the template states its own version here. A stated 0 or a
// non-numeric value is a broken model file and fails the load.
rac_result_t load_prompt_format_version(LlamaCppDecisionHandle* handle) {
    handle->prompt_format_version = rac_decision_default_prompt_format_version();
    char arch[64] = {0};
    if (llama_model_meta_val_str(handle->model, "general.architecture", arch, sizeof(arch)) < 0) {
        return RAC_SUCCESS;
    }
    const std::string key = std::string(arch) + ".decision.prompt_format_version";
    char value[32] = {0};
    if (llama_model_meta_val_str(handle->model, key.c_str(), value, sizeof(value)) < 0) {
        return RAC_SUCCESS;
    }
    const unsigned long parsed = std::strtoul(value, nullptr, 10);
    if (parsed == 0 || parsed > UINT32_MAX) {
        RAC_LOG_ERROR(kLogCategory, "invalid decision prompt format version: %s = %s",
                      key.c_str(), value);
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }
    handle->prompt_format_version = static_cast<uint32_t>(parsed);
    return RAC_SUCCESS;
}

// The per-request override wins; otherwise the model's own calibration for
// this question kind, first with the option-count bucket then without; 1.0
// when the GGUF carries no entry. The buckets are the ones the calibration
// was fitted over.
float temperature_for(const LlamaCppDecisionHandle* handle, rac_decision_question_type_t type,
                      size_t option_count, const rac_decision_options_t* options) {
    if (options != nullptr && options->temperature > 0.0f) {
        return options->temperature;
    }
    const std::string type_name = runanywhere::decision_prompt::question_type_name(type);
    const char* bucket = option_count <= 2 ? "2"
                         : option_count <= 5 ? "3_5"
                         : option_count <= 10 ? "6_10"
                                              : "11";
    const auto& temperatures = handle->temperatures;
    const auto bucketed = temperatures.find(type_name + "." + bucket);
    if (bucketed != temperatures.end()) {
        return bucketed->second;
    }
    const auto plain = temperatures.find(type_name);
    if (plain != temperatures.end()) {
        return plain->second;
    }
    return 1.0f;
}

// Probability of each option from the raw option scores and a temperature.
std::vector<float> scores_to_probabilities(const float* scores, size_t count, float temperature) {
    std::vector<float> probs(count, 0.0f);
    if (count == 0) {
        return probs;
    }
    const float temp = temperature > 0.0f ? temperature : 1.0f;
    float score_max = scores[0];
    for (size_t i = 1; i < count; ++i) {
        score_max = std::max(score_max, scores[i]);
    }
    double sum = 0.0;
    for (size_t i = 0; i < count; ++i) {
        probs[i] = static_cast<float>(std::exp(static_cast<double>(scores[i] - score_max) / temp));
        sum += probs[i];
    }
    if (sum > 0.0) {
        for (float& p : probs) {
            p = static_cast<float>(p / sum);
        }
    }
    return probs;
}

// Spread of the distribution over a uniform one; 0 when flat, 1 when certain.
float choice_confidence(const std::vector<float>& probs) {
    if (probs.size() < 2) {
        return 1.0f;
    }
    const float uniform = 1.0f / static_cast<float>(probs.size());
    const float p_max = *std::max_element(probs.begin(), probs.end());
    return std::max(0.0f, (p_max - uniform) / (1.0f - uniform));
}

// Mean distance to the mode relative to a uniform distribution around its center.
float score_confidence(const std::vector<float>& probs) {
    if (probs.size() < 2) {
        return 1.0f;
    }
    const size_t n = probs.size();
    const size_t mode = static_cast<size_t>(
        std::max_element(probs.begin(), probs.end()) - probs.begin());
    double dist = 0.0;
    double dist_uniform = 0.0;
    for (size_t i = 0; i < n; ++i) {
        dist += probs[i] * std::fabs(static_cast<double>(i) - static_cast<double>(mode));
        dist_uniform += std::fabs(static_cast<double>(i) - (n - 1) / 2.0) / n;
    }
    if (dist_uniform <= 0.0) {
        return 1.0f;
    }
    return std::max(0.0f, static_cast<float>(1.0 - dist / dist_uniform));
}

#if defined(RAC_LLAMACPP_HAS_CLEF_SPAN)
rac_result_t encode_tagged(LlamaCppDecisionHandle* handle,
                           const runanywhere::decision_prompt::TaggedPrompt& prompt,
                           int32_t* out_tokens) {
    if (prompt.tokens.empty()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (prompt.tokens.size() > static_cast<size_t>(INT32_MAX)) {
        return RAC_ERROR_TEXT_TOO_LONG;
    }

    LlamaBatchGuard batch_guard(llama_batch_init(static_cast<int32_t>(prompt.tokens.size()), 0, 1));
    llama_batch& batch = batch_guard.batch;
    if (batch.token == nullptr || batch.pos == nullptr || batch.n_seq_id == nullptr ||
        batch.seq_id == nullptr || batch.logits == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    batch.n_tokens = static_cast<int32_t>(prompt.tokens.size());
    for (int32_t index = 0; index < batch.n_tokens; ++index) {
        batch.token[index] = prompt.tokens[static_cast<size_t>(index)];
        batch.pos[index] = index;
        batch.n_seq_id[index] = 1;
        batch.seq_id[index][0] = 0;
        batch.logits[index] = 1;
        // The span tags are what the joint head reads to pool the right token
        // runs into one score per option.
        if (!llama_batch_set_decision_order(&batch, index,
                                            static_cast<llama_decision_order>(
                                                prompt.order[static_cast<size_t>(index)]))) {
            return RAC_ERROR_INVALID_ARGUMENT;
        }
    }

    llama_memory_clear(llama_get_memory(handle->context), true);
    // The decision backbone is evaluated without past-state reuse, so it runs
    // through the encoder path.
    if (llama_encode(handle->context, batch) != 0) {
        RAC_LOG_ERROR(kLogCategory, "llama_encode failed for %d tokens", batch.n_tokens);
        return RAC_ERROR_INFERENCE_FAILED;
    }
    *out_tokens = batch.n_tokens;
    return RAC_SUCCESS;
}
#endif

rac_result_t llamacpp_decision_initialize(void* implementation, const char* model_path) {
    if (implementation == nullptr || model_path == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* handle = static_cast<LlamaCppDecisionHandle*>(implementation);
    std::lock_guard<std::mutex> lock(handle->mutex);
    release_model(handle);

    const std::string resolved_path = resolve_gguf_path(model_path);
    if (resolved_path.empty()) {
        RAC_LOG_ERROR(kLogCategory, "no GGUF file found at model path");
        return RAC_ERROR_MODEL_NOT_FOUND;
    }

    llama_model_params model_params = llama_model_default_params();
#if defined(__EMSCRIPTEN__) || defined(__ANDROID__)
    model_params.load_mode = LLAMA_LOAD_MODE_NONE;
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
        RAC_LOG_ERROR(kLogCategory, "failed to load decision model: %s", resolved_path.c_str());
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Refuse models that do not carry the decision template: without it the
    // prompt layout is unknown and the head would be fed spans it was not
    // trained on.
    if (llama_model_chat_template(handle->model, kDecisionTemplateName) == nullptr) {
        RAC_LOG_ERROR(kLogCategory,
                      "GGUF has no decision template ('%s'); not a decision model",
                      kDecisionTemplateName);
        release_model(handle);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    const rac_result_t temperature_rc = load_temperatures(handle);
    if (temperature_rc != RAC_SUCCESS) {
        release_model(handle);
        return temperature_rc;
    }

    const rac_result_t version_rc = load_prompt_format_version(handle);
    if (version_rc != RAC_SUCCESS) {
        release_model(handle);
        return version_rc;
    }
    handle->d1_kind = rac_llamacpp_d1_kind_of(handle->model);

    const int32_t training_context = llama_model_n_ctx_train(handle->model);
    handle->max_tokens =
        training_context > 0 ? std::min(training_context, kDefaultContext) : kDefaultContext;
    llama_context_params context_params = llama_context_default_params();
    context_params.n_ctx = static_cast<uint32_t>(handle->max_tokens);
    context_params.n_batch = static_cast<uint32_t>(handle->max_tokens);
    context_params.n_ubatch = static_cast<uint32_t>(handle->max_tokens);
    if (handle->d1_kind == rac_llamacpp_d1_kind::omni ||
        handle->d1_kind == rac_llamacpp_d1_kind::gliner) {
        context_params.n_batch = 512;
        context_params.n_ubatch = 512;
    }
    context_params.n_seq_max = 1;
    context_params.n_threads = handle->default_threads;
    context_params.n_threads_batch = handle->default_threads;
    context_params.embeddings = handle->d1_kind != rac_llamacpp_d1_kind::lfm2;
    context_params.pooling_type = LLAMA_POOLING_TYPE_NONE;
    context_params.no_perf = true;

    handle->context = llama_init_from_model(handle->model, context_params);
    if (handle->context == nullptr) {
        release_model(handle);
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    handle->model_path = resolved_path;
    RAC_LOG_INFO(kLogCategory, "loaded decision model %s (max_tokens=%d)",
                 handle->model_id.c_str(), handle->max_tokens);
    return RAC_SUCCESS;
}

rac_result_t llamacpp_decision_decide(void* implementation, const char* state,
                                      const rac_decision_question_t* questions,
                                      size_t question_count,
                                      const rac_decision_options_t* options,
                                      rac_decision_result_t* output) {
    if (implementation == nullptr || state == nullptr || output == nullptr ||
        (question_count > 0 && questions == nullptr)) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* handle = static_cast<LlamaCppDecisionHandle*>(implementation);
    std::lock_guard<std::mutex> lock(handle->mutex);
    if (handle->model == nullptr || handle->context == nullptr) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }
    *output = {};
    if (question_count == 0) {
        return RAC_SUCCESS;
    }

    // A pinned request must match the wording this checkpoint serves. Both the
    // wording and the probabilities derived from it are model-versioned, so a
    // silent mismatch would hand back scores the caller cannot interpret.
    if (options != nullptr && options->prompt_format_version != 0 &&
        handle->prompt_format_version != options->prompt_format_version) {
        RAC_LOG_ERROR(kLogCategory,
                      "request pins prompt format %u, model serves %u",
                      options->prompt_format_version, handle->prompt_format_version);
        return RAC_ERROR_NOT_SUPPORTED;
    }

    const auto started = std::chrono::steady_clock::now();
#if defined(RAC_LLAMACPP_HAS_D1)
    if (handle->d1_kind != rac_llamacpp_d1_kind::none) {
        const rac_result_t rc = rac_llamacpp_d1_decide(
            handle->model, handle->context, handle->d1_kind, state, questions, question_count,
            options, output, handle->model_id.c_str());
        if (rc == RAC_SUCCESS) {
            output->prompt_format_version = handle->prompt_format_version;
        }
        return rc;
    }
#endif
#if !defined(RAC_LLAMACPP_HAS_CLEF_SPAN)
    (void)started;
    return RAC_ERROR_NOT_SUPPORTED;
#else
    const llama_vocab* vocab = llama_model_get_vocab(handle->model);
    llama_set_n_threads(handle->context, handle->default_threads, handle->default_threads);

    const char* template_src = llama_model_chat_template(handle->model, kDecisionTemplateName);
    if (template_src == nullptr) {
        return RAC_ERROR_NOT_SUPPORTED;
    }

    runanywhere::decision_prompt::TaggedPrompt prompt;
    try {
        prompt = runanywhere::decision_prompt::build(template_src, vocab, state, questions,
                                                     question_count);
    } catch (const std::invalid_argument& error) {
        // Backend-facing detail goes to the log; the caller gets a plain code.
        RAC_LOG_ERROR(kLogCategory, "decision prompt rejected: %s", error.what());
        return RAC_ERROR_INVALID_ARGUMENT;
    } catch (const std::exception& error) {
        RAC_LOG_ERROR(kLogCategory, "decision prompt failed: %s", error.what());
        return RAC_ERROR_INFERENCE_FAILED;
    }

    if (prompt.tokens.size() > static_cast<size_t>(handle->max_tokens)) {
        RAC_LOG_ERROR(kLogCategory, "decision prompt (%zu tokens) exceeds context (%d)",
                      prompt.tokens.size(), handle->max_tokens);
        return RAC_ERROR_TEXT_TOO_LONG;
    }

    int32_t n_tokens = 0;
    const rac_result_t encode_rc = encode_tagged(handle, prompt, &n_tokens);
    if (encode_rc != RAC_SUCCESS) {
        return encode_rc;
    }

    // One row per option, in request order; the score is the row's first column.
    output->answers = static_cast<rac_decision_answer_t*>(
        std::calloc(question_count, sizeof(rac_decision_answer_t)));
    if (output->answers == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    output->answer_count = question_count;

    size_t option_cursor = 0;
    for (size_t i = 0; i < question_count; ++i) {
        const auto& question = questions[i];
        auto& answer = output->answers[i];
        answer.id = question.id != nullptr ? strdup(question.id) : strdup("");
        answer.type = question.type;
        answer.probability_count = question.option_count;
        answer.probabilities = static_cast<float*>(
            std::calloc(question.option_count > 0 ? question.option_count : 1, sizeof(float)));
        if (answer.id == nullptr || answer.probabilities == nullptr) {
            rac_decision_result_free(output);
            return RAC_ERROR_OUT_OF_MEMORY;
        }

        if (question.option_count == 0 || option_cursor >= prompt.option_count) {
            // No options to score; leave the answer empty rather than guessing.
            option_cursor += question.option_count;
            continue;
        }

        std::vector<float> raw(question.option_count, 0.0f);
        bool ok = true;
        for (size_t j = 0; j < question.option_count; ++j) {
            const float* embedding =
                llama_get_embeddings_ith(handle->context, static_cast<int32_t>(option_cursor + j));
            if (embedding == nullptr || !std::isfinite(embedding[0])) {
                ok = false;
                break;
            }
            // The joint head returns one score per rendered option, in the
            // model's canonical order; place it on the request option index.
            raw[static_cast<size_t>(prompt.option_request_index[option_cursor + j])] =
                embedding[0];
        }
        option_cursor += question.option_count;
        if (!ok) {
            RAC_LOG_ERROR(kLogCategory, "joint head returned no usable score for question %s",
                          answer.id);
            rac_decision_result_free(output);
            return RAC_ERROR_INFERENCE_FAILED;
        }

        const float temperature =
            temperature_for(handle, question.type, question.option_count, options);
        const std::vector<float> probs = scores_to_probabilities(raw.data(), raw.size(), temperature);
        std::memcpy(answer.probabilities, probs.data(), probs.size() * sizeof(float));

        switch (question.type) {
            case RAC_DECISION_QUESTION_CHOICE: {
                const size_t best = static_cast<size_t>(
                    std::max_element(probs.begin(), probs.end()) - probs.begin());
                answer.choice = strdup(question.options[best].key != nullptr
                                           ? question.options[best].key
                                           : "");
                if (answer.choice == nullptr) {
                    rac_decision_result_free(output);
                    return RAC_ERROR_OUT_OF_MEMORY;
                }
                answer.confidence = choice_confidence(probs);
                break;
            }
            case RAC_DECISION_QUESTION_NOUL: {
                // The probability mass on the "true" option; when the request
                // did not name it, the first option is the affirmative one.
                const size_t n = probs.size();
                size_t true_index = 0;
                for (size_t j = 0; j < n; ++j) {
                    if (question.options[j].key != nullptr &&
                        std::strcmp(question.options[j].key, "true") == 0) {
                        true_index = j;
                        break;
                    }
                }
                answer.noul = probs[true_index];
                answer.confidence = choice_confidence(probs);
                break;
            }
            case RAC_DECISION_QUESTION_SCORE: {
                double expected = 0.0;
                for (size_t j = 0; j < probs.size(); ++j) {
                    expected += static_cast<double>(j) * probs[j];
                }
                answer.score = static_cast<float>(expected);
                answer.confidence = score_confidence(probs);
                break;
            }
            default:
                break;
        }
    }

    output->processing_time_ms =
        std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() -
                                                              started)
            .count();
    output->model_id = strdup(handle->model_id.c_str());
    output->input_tokens = n_tokens;
    output->prompt_format_version = handle->prompt_format_version;
    if (output->model_id == nullptr) {
        rac_decision_result_free(output);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
#endif
}

rac_result_t llamacpp_decision_cleanup(void* implementation) {
    if (implementation == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* handle = static_cast<LlamaCppDecisionHandle*>(implementation);
    std::lock_guard<std::mutex> lock(handle->mutex);
    release_model(handle);
    return RAC_SUCCESS;
}

void llamacpp_decision_destroy(void* implementation) {
    auto* handle = static_cast<LlamaCppDecisionHandle*>(implementation);
    if (handle == nullptr) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        release_model(handle);
    }
    delete handle;
}

rac_result_t llamacpp_decision_create(const char* model_id, const char* /*config_json*/,
                                      void** output) {
    if (model_id == nullptr || output == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *output = nullptr;
    runanywhere::llamacpp_internal::ensure_llamacpp_ggml_log_routed();
    llama_backend_init();
    auto handle = std::make_unique<LlamaCppDecisionHandle>();
    handle->model_id = model_id;
    const unsigned int hardware_threads = std::thread::hardware_concurrency();
    handle->default_threads = static_cast<int32_t>(std::clamp(
        hardware_threads == 0 ? 1U : hardware_threads, 1U, static_cast<unsigned int>(kMaxThreads)));
    *output = handle.release();
    return RAC_SUCCESS;
}

}  // namespace

extern "C" RAC_LLAMACPP_API const rac_decision_service_ops_t g_llamacpp_decision_ops = {
    .initialize = llamacpp_decision_initialize,
    .decide = llamacpp_decision_decide,
    .cleanup = llamacpp_decision_cleanup,
    .destroy = llamacpp_decision_destroy,
    .create = llamacpp_decision_create,
};