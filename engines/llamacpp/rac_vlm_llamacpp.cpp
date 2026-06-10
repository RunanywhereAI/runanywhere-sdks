/**
 * @file rac_vlm_llamacpp.cpp
 * @brief RunAnywhere Commons - LlamaCPP VLM Backend Implementation
 *
 * Vision Language Model backend using llama.cpp's multimodal (mtmd) API.
 * Supports VLM architectures including Qwen2-VL, SmolVLM, LLaVA, MiniCPM-V,
 * etc.
 *
 * Updated for llama.cpp b7650+ mtmd API.
 */

#include "rac/backends/rac_vlm_llamacpp.h"

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

#include <llama.h>

#include <atomic>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// llama.cpp multimodal support (mtmd)
#include "clip.h"
#include "mtmd-helper.h"
#include "mtmd.h"

#include "llamacpp_stop_helpers.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "VLM.LlamaCPP";

// =============================================================================
// NAMED CONSTANTS
// =============================================================================

static constexpr int kDefaultMaxContextSize = 4096;
static constexpr int kDefaultBatchSize = 512;
static constexpr int kDefaultMaxTokens = 2048;

// =============================================================================
// INTERNAL BACKEND STATE
// =============================================================================

namespace {

/**
 * VLM model type for chat template selection.
 *
 * Defined before LlamaCppVLMBackend so the struct can initialise model_type
 * with the named enumerator VLMModelType::Unknown instead of a brittle
 * static_cast<VLMModelType>(0) that breaks if the enumerator order changes.
 */
enum class VLMModelType {
    Unknown,
    SmolVLM,  // SmolVLM uses "User:" / "Assistant:" format
    Qwen2VL,  // Qwen2-VL uses chatml with <|im_start|>user format
    LLaVA,    // LLaVA uses "USER:" / "ASSISTANT:" format
    Generic   // Generic chatml fallback
};

// =============================================================================
// RAII GUARDS FOR llama.cpp / mtmd C HANDLES
// =============================================================================
//
// The mtmd and llama.cpp APIs are pure C and require manual destroy calls
// paired with each init. Wrap them in unique_ptr-based guards so error-return
// paths between init and free cannot leak the (MB-scale) image bitmaps,
// tokenized chunk lists, or llama_batch tensors. Mirrors the upstream
// mtmd::bitmap_ptr / input_chunks_ptr helpers but keeps the dependency local.
struct MtmdBitmapDelete {
    void operator()(mtmd_bitmap* b) const {
        if (b)
            mtmd_bitmap_free(b);
    }
};
using MtmdBitmapPtr = std::unique_ptr<mtmd_bitmap, MtmdBitmapDelete>;

struct MtmdChunksDelete {
    void operator()(mtmd_input_chunks* c) const {
        if (c)
            mtmd_input_chunks_free(c);
    }
};
using MtmdChunksPtr = std::unique_ptr<mtmd_input_chunks, MtmdChunksDelete>;

// llama_batch is a value type (no pointer to wrap), so use a scope guard
// that runs llama_batch_free on destruction. Caller mutates `batch` in place.
struct LlamaBatchGuard {
    llama_batch batch;
    explicit LlamaBatchGuard(llama_batch b) : batch(b) {}
    ~LlamaBatchGuard() { llama_batch_free(batch); }
    LlamaBatchGuard(const LlamaBatchGuard&) = delete;
    LlamaBatchGuard& operator=(const LlamaBatchGuard&) = delete;
};

struct LlamaCppVLMBackend {
    // llama.cpp model and context
    llama_model* model = nullptr;
    llama_context* ctx = nullptr;
    llama_sampler* sampler = nullptr;

    // Multimodal context (vision projector)
    mtmd_context* mtmd_ctx = nullptr;

    // Configuration
    rac_vlm_llamacpp_config_t config = RAC_VLM_LLAMACPP_CONFIG_DEFAULT;

    // State
    bool model_loaded = false;
    std::atomic<bool> cancel_requested{false};

    // Lifecycle barrier — destroy() flips this true so future entry-point
    // calls fail fast, then spin-waits for `in_flight` to drain before
    // freeing the backend. Mirrors the voice_agent pattern at
    // sdk/runanywhere-commons/src/features/voice_agent/voice_agent.cpp:179.
    // This closes the "object with member mutex cannot be safely destroyed
    // by itself" race window between unload_model's mutex release and the
    // delete that follows.
    std::atomic<bool> is_shutting_down{false};
    std::atomic<int> in_flight{0};

    // Model info
    std::string model_path;
    std::string mmproj_path;
    int context_size = 0;
    llama_pos n_past = 0;

    // Detected model type for chat template
    VLMModelType model_type = VLMModelType::Unknown;

    // Cached sampler parameters to avoid unnecessary rebuilds.
    // Extended to cover the full rac_vlm_options_t sampling
    // surface (top_k / seed / repetition_penalty / min_p) so any call that
    // touches them invalidates the cached chain and forces a rebuild.
    float cached_temperature = -1.0f;
    float cached_top_p = -1.0f;
    int32_t cached_top_k = -1;
    int64_t cached_seed = 0;
    float cached_repetition_penalty = -1.0f;
    float cached_min_p = -1.0f;

    // Caller toggle for image-embedding emission. Stored on the
    // backend so both streaming and non-streaming paths see the same value.
    // No mtmd hook surfaces embeddings today; the flag is recorded for future
    // proto-event emission and so callers see the bool round-trip through the
    // C ABI without silent loss.
    bool emit_image_embeddings = false;

    // Thread safety
    mutable std::mutex mutex;
};

/**
 * RAII guard that increments backend->in_flight on entry and decrements on
 * scope exit. destroy() flips backend->is_shutting_down and then spins until
 * in_flight reaches zero, so any public entry point that acquires a guard
 * either runs to completion before destroy() can free the backend, or bails
 * out fast when is_shutting_down is already set.
 *
 * Mirrors voice_agent.cpp's in_flight pattern
 * (sdk/runanywhere-commons/src/features/voice_agent/voice_agent.cpp:216-218).
 */
struct InFlightGuard {
    LlamaCppVLMBackend* backend;
    explicit InFlightGuard(LlamaCppVLMBackend* b) : backend(b) {
        backend->in_flight.fetch_add(1, std::memory_order_acq_rel);
    }
    ~InFlightGuard() { backend->in_flight.fetch_sub(1, std::memory_order_acq_rel); }
    InFlightGuard(const InFlightGuard&) = delete;
    InFlightGuard& operator=(const InFlightGuard&) = delete;
};

/**
 * Get number of CPU threads to use.
 */
int get_num_threads(const int config_threads) {
    if (config_threads > 0)
        return config_threads;

    // Auto-detect based on hardware
    int threads = static_cast<int>(std::thread::hardware_concurrency());
    if (threads <= 0)
        threads = 4;
    if (threads > 8)
        threads = 8;  // Cap for mobile devices
    return threads;
}

// =============================================================================
// CHAT TEMPLATE HELPERS
// =============================================================================

std::string format_vlm_prompt_manual(const std::string& user_content, const char* effective_system,
                                     VLMModelType model_type) {
    std::string formatted;

    switch (model_type) {
        case VLMModelType::SmolVLM:
            if (effective_system) {
                formatted += "System: ";
                formatted += effective_system;
                formatted += "\n";
            }
            formatted += "User: ";
            formatted += user_content;
            formatted += "\nAssistant:";
            break;
        case VLMModelType::LLaVA:
            if (effective_system) {
                formatted += "SYSTEM: ";
                formatted += effective_system;
                formatted += "\n";
            }
            formatted += "USER: ";
            formatted += user_content;
            formatted += "\nASSISTANT:";
            break;
        case VLMModelType::Qwen2VL:
        case VLMModelType::Generic:
        case VLMModelType::Unknown:
        default:
            if (effective_system) {
                formatted = "<|im_start|>system\n";
                formatted += effective_system;
                formatted += "<|im_end|>\n";
            }
            formatted += "<|im_start|>user\n";
            formatted += user_content;
            formatted += "<|im_end|>\n<|im_start|>assistant\n";
            break;
    }

    RAC_LOG_DEBUG(LOG_CAT, "Manual-formatted prompt (%d chars): %s", (int)formatted.length(),
                  formatted.c_str());
    return formatted;
}

/**
 * Detect VLM model type from model architecture and name metadata.
 *
 * The primary signal is `general.architecture` from the GGUF metadata —
 * llama.cpp publishes canonical arch strings (`qwen2vl`, `qwen3vl`,
 * `qwen3vlmoe`, `llava`, ...) that map deterministically to a chat-template
 * family. Falling back to a bare `name.find("qwen") != npos` substring
 * misclassified future siblings (e.g. plain text-only `qwen3`) as Qwen2-VL
 * and forced unrelated arches onto the chatml manual template.
 *
 * Fallbacks (name + chat-template sniffing) only run when arch is missing
 * or unrecognized, preserving SmolVLM detection for builds whose
 * architecture is just `smollm` / `llama`.
 */
VLMModelType detect_vlm_model_type(llama_model* model) {
    if (!model)
        return VLMModelType::Generic;

    // Primary signal: general.architecture from GGUF metadata. llama.cpp
    // publishes canonical arch strings (qwen2vl, qwen3vl, qwen3vlmoe, llava
    // variants, smolvlm, ...) that map deterministically to a chat template
    // family. Avoid the bare-name substring match that caught siblings.
    char arch_buf[64] = {0};
    int32_t arch_len =
        llama_model_meta_val_str(model, "general.architecture", arch_buf, sizeof(arch_buf));
    if (arch_len > 0) {
        std::string arch(arch_buf);
        for (auto& c : arch)
            c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));

        RAC_LOG_DEBUG(LOG_CAT, "Model architecture from metadata: %s", arch.c_str());

        // Match any Qwen-VL variant: qwen2vl, qwen3vl, qwen3vlmoe, qwen35vl, ...
        if (arch.find("qwenvl") != std::string::npos || arch.find("qwen2vl") != std::string::npos ||
            arch.find("qwen3vl") != std::string::npos ||
            arch.find("qwen35vl") != std::string::npos) {
            RAC_LOG_DEBUG(LOG_CAT, "Detected Qwen-VL model type from architecture");
            return VLMModelType::Qwen2VL;
        }
        if (arch.find("llava") != std::string::npos) {
            RAC_LOG_DEBUG(LOG_CAT, "Detected LLaVA model type from architecture");
            return VLMModelType::LLaVA;
        }
        if (arch.find("smolvlm") != std::string::npos) {
            RAC_LOG_DEBUG(LOG_CAT, "Detected SmolVLM model type from architecture");
            return VLMModelType::SmolVLM;
        }
    }

    // Fallback: model name metadata when architecture is missing or generic
    // (SmolVLM is often shipped as a `smollm` / `llama` arch with the VLM
    // identity encoded only in the name).
    char name_buf[256] = {0};
    int32_t len = llama_model_meta_val_str(model, "general.name", name_buf, sizeof(name_buf));
    if (len <= 0) {
        len = llama_model_meta_val_str(model, "general.basename", name_buf, sizeof(name_buf));
    }

    if (len > 0) {
        std::string name(name_buf);
        for (auto& c : name)
            c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));

        RAC_LOG_DEBUG(LOG_CAT, "Model name from metadata: %s", name.c_str());

        if (name.find("smolvlm") != std::string::npos || name.find("smol") != std::string::npos) {
            RAC_LOG_DEBUG(LOG_CAT, "Detected SmolVLM model type from name");
            return VLMModelType::SmolVLM;
        }
        if (name.find("llava") != std::string::npos) {
            RAC_LOG_DEBUG(LOG_CAT, "Detected LLaVA model type from name");
            return VLMModelType::LLaVA;
        }
    }

    // Final fallback: chat-template sniffing for SmolVLM-style models that
    // expose neither a VLM arch nor a SmolVLM name.
    const char* chat_template = llama_model_chat_template(model, nullptr);
    if (chat_template) {
        std::string tmpl(chat_template);
        if (tmpl.find("User:") != std::string::npos &&
            tmpl.find("Assistant:") != std::string::npos) {
            RAC_LOG_DEBUG(LOG_CAT, "Detected SmolVLM model type from chat template");
            return VLMModelType::SmolVLM;
        }
    }

    RAC_LOG_DEBUG(LOG_CAT, "Using generic chat template");
    return VLMModelType::Generic;
}

/**
 * Apply a caller-supplied custom chat template by substituting the
 * `{system}` / `{image}` / `{prompt}` placeholders documented on
 * `rac_vlm_chat_template_t`. Returns an empty string if the template has no
 * usable template_str.
 *
 * The substitution is intentionally simple (single-pass find/replace) — this
 * mirrors the contract documented on rac_vlm_chat_template_t.template_str.
 */
std::string apply_custom_chat_template(const rac_vlm_chat_template_t* custom_template,
                                       const std::string& user_prompt, const char* image_marker,
                                       bool has_image, const char* effective_system) {
    if (!custom_template || !custom_template->template_str ||
        custom_template->template_str[0] == '\0') {
        return {};
    }

    std::string out(custom_template->template_str);

    // Resolve {system} — caller's explicit value wins; otherwise use the
    // template's default_system_prompt; otherwise empty.
    const char* system_value = effective_system ? effective_system
                                                : (custom_template->default_system_prompt
                                                       ? custom_template->default_system_prompt
                                                       : "");

    auto replace_placeholder = [](std::string& dst, const std::string& needle,
                                  const std::string& value) {
        size_t pos = dst.find(needle);
        while (pos != std::string::npos) {
            dst.replace(pos, needle.size(), value);
            pos = dst.find(needle, pos + value.size());
        }
    };

    replace_placeholder(out, "{system}", system_value ? std::string(system_value) : std::string());
    replace_placeholder(out, "{image}", has_image ? std::string(image_marker) : std::string());
    replace_placeholder(out, "{prompt}", user_prompt);

    RAC_LOG_DEBUG(LOG_CAT, "Custom-template-formatted prompt (%d chars): %s", (int)out.length(),
                  out.c_str());
    return out;
}

/**
 * Format prompt using model's built-in chat template via
 * llama_chat_apply_template. Falls back to manual formatting if template
 * application fails.
 *
 * When system_prompt is provided, it is prepended as a system message.
 * For models that expect a system message (e.g. Qwen2-VL), a default is
 * injected based on the detected model_type when no explicit prompt is given.
 */
std::string format_vlm_prompt_with_template(llama_model* model, const std::string& user_prompt,
                                            const char* image_marker, bool has_image,
                                            const char* system_prompt, VLMModelType model_type,
                                            const rac_vlm_chat_template_t* custom_template) {
    // Build user content with image marker if present
    std::string user_content;
    if (has_image) {
        user_content = std::string(image_marker) + user_prompt;
    } else {
        user_content = user_prompt;
    }

    // Resolve system prompt: use explicit value, or inject a default for Qwen2-VL
    const char* effective_system =
        (system_prompt && system_prompt[0] != '\0') ? system_prompt : nullptr;
    if (!effective_system && model_type == VLMModelType::Qwen2VL) {
        effective_system = "You are a helpful assistant.";
    }

    // Caller-supplied custom chat template overrides the model/family default.
    // Resolved only when the caller picked RAC_VLM_MODEL_FAMILY_CUSTOM (i.e.
    // VLMModelType::Generic was returned by resolve_effective_model_type for the
    // CUSTOM family). We accept any non-NULL custom_template though, because a
    // caller might want to override even when keeping the detected family.
    if (custom_template) {
        std::string applied = apply_custom_chat_template(custom_template, user_prompt, image_marker,
                                                         has_image, effective_system);
        if (!applied.empty()) {
            return applied;
        }
    }

#ifdef __EMSCRIPTEN__
    // llama.cpp's chat-template formatter can surface uncaught C++ exceptions
    // through Emscripten as opaque `CppException` values. Web uses the same
    // deterministic model-family formatter that the fallback path uses so the
    // browser receives typed RACommons errors instead of escaped native throws.
    return format_vlm_prompt_manual(user_content, effective_system, model_type);
#endif

    // Get the model's chat template
    const char* tmpl = llama_model_chat_template(model, nullptr);

    // Try to use llama_chat_apply_template
    if (tmpl) {
        RAC_LOG_DEBUG(LOG_CAT, "Using model chat template: %.80s...", tmpl);

        if (effective_system) {
            int32_t size = 0;
            try {
                llama_chat_message messages[2];
                messages[0].role = "system";
                messages[0].content = effective_system;
                messages[1].role = "user";
                messages[1].content = user_content.c_str();

                size = llama_chat_apply_template(tmpl, messages, 2, true, nullptr, 0);
                if (size > 0) {
                    std::vector<char> buf(size + 1);
                    int32_t result =
                        llama_chat_apply_template(tmpl, messages, 2, true, buf.data(), buf.size());
                    if (result > 0) {
                        std::string formatted(buf.data(), result);
                        RAC_LOG_DEBUG(LOG_CAT,
                                      "Template-formatted prompt with system (%d chars): %s",
                                      (int)formatted.length(), formatted.c_str());
                        return formatted;
                    }
                }
            } catch (const std::exception& ex) {
                RAC_LOG_WARNING(LOG_CAT, "llama_chat_apply_template with system threw: %s",
                                ex.what());
            } catch (...) {
                RAC_LOG_WARNING(LOG_CAT, "llama_chat_apply_template with system threw");
            }
            if (effective_system) {
                RAC_LOG_WARNING(LOG_CAT,
                                "Template with system failed (size=%d); falling back to manual to "
                                "preserve explicit system prompt",
                                size);
            } else {
                RAC_LOG_WARNING(LOG_CAT,
                                "llama_chat_apply_template with system failed "
                                "(size=%d), trying without",
                                size);
            }
            // If the caller passed an explicit system prompt, skip user-only
            // template to avoid silently dropping it -- go straight to manual.
            if (effective_system) {
                goto manual_fallback;
            }
        }

        {
            int32_t size = 0;
            try {
                llama_chat_message messages[1];
                messages[0].role = "user";
                messages[0].content = user_content.c_str();

                size = llama_chat_apply_template(tmpl, messages, 1, true, nullptr, 0);
                if (size > 0) {
                    std::vector<char> buf(size + 1);
                    int32_t result =
                        llama_chat_apply_template(tmpl, messages, 1, true, buf.data(), buf.size());
                    if (result > 0) {
                        std::string formatted(buf.data(), result);
                        RAC_LOG_DEBUG(LOG_CAT, "Template-formatted prompt (%d chars): %s",
                                      (int)formatted.length(), formatted.c_str());
                        return formatted;
                    }
                }
            } catch (const std::exception& ex) {
                RAC_LOG_WARNING(LOG_CAT, "llama_chat_apply_template threw: %s", ex.what());
            } catch (...) {
                RAC_LOG_WARNING(LOG_CAT, "llama_chat_apply_template threw");
            }
            RAC_LOG_WARNING(LOG_CAT,
                            "llama_chat_apply_template failed (size=%d), falling back to manual",
                            size);
        }
    } else {
        RAC_LOG_DEBUG(LOG_CAT, "No chat template in model, using manual formatting");
    }

manual_fallback:
    return format_vlm_prompt_manual(user_content, effective_system, model_type);
}

/**
 * Get the image marker string. Uses the default marker from mtmd.
 */
const char* get_image_marker() {
    return mtmd_default_marker();
}

/**
 * Configure the sampler chain with the given generation parameters.
 * Only rebuilds the sampler when parameters actually change, avoiding
 * unnecessary heap allocations on every inference call.
 *
 * Honors the full sampling surface of rac_vlm_options_t
 * (top_k / seed / repetition_penalty / min_p), mirroring the LLM backend's
 * build_sampler_chain() in engines/llamacpp/llamacpp_backend.cpp. Zero/default
 * values fall back to the historical engine constants so callers that left them
 * at defaults continue to see identical behavior.
 */
void configure_sampler(LlamaCppVLMBackend* backend, const rac_vlm_options_t* options) {
    // Defaults match the historical hard-coded VLM behavior so callers that
    // didn't set these fields don't see a behavioral regression.
    float temperature = 0.7f;
    float top_p = 0.9f;
    int32_t top_k = 0;  // 0 = no top_k sampler in chain
    int64_t seed = LLAMA_DEFAULT_SEED;
    float repetition_penalty = 1.3f;  // pre-IDL engine default
    float min_p = 0.1f;               // pre-IDL engine default

    if (options) {
        if (options->temperature >= 0.0f) {
            temperature = options->temperature;
        }
        if (options->top_p > 0.0f && options->top_p <= 1.0f) {
            top_p = options->top_p;
        }
        if (options->top_k > 0) {
            top_k = options->top_k;
        }
        if (options->seed != 0) {
            // Negative seed signals "fresh random per call" — feed it straight to
            // llama_sampler_init_dist, which interprets uint32_t LLAMA_DEFAULT_SEED
            // for "auto". Cast preserves the caller's bit pattern.
            seed = options->seed;
        }
        if (options->repetition_penalty > 0.0f) {
            repetition_penalty = options->repetition_penalty;
        }
        if (options->min_p > 0.0f) {
            min_p = options->min_p;
        }
    }

    // Skip rebuild if params haven't changed and sampler already exists
    if (backend->sampler && backend->cached_temperature == temperature &&
        backend->cached_top_p == top_p && backend->cached_top_k == top_k &&
        backend->cached_seed == seed && backend->cached_repetition_penalty == repetition_penalty &&
        backend->cached_min_p == min_p) {
        return;
    }

    // Free existing sampler
    if (backend->sampler) {
        llama_sampler_free(backend->sampler);
        backend->sampler = nullptr;
    }

    // Build new sampler chain.
    // Order follows llama.cpp common_sampler_init: penalties → DRY → top_k →
    // top_p → min_p → temp → dist. Penalties and DRY must be applied to raw
    // logits before temperature softens them.
    llama_sampler_chain_params sampler_params = llama_sampler_chain_default_params();
    sampler_params.no_perf = true;  // Disable perf tracking (consistent with LLM backend)
    backend->sampler = llama_sampler_chain_init(sampler_params);

    if (temperature > 0.0f) {
        // Token-level repetition penalty + frequency/presence penalties.
        // Repetition penalty is caller-controlled now; freq/pres
        // stay at the pre-IDL engine defaults until callers request a knob.
        llama_sampler_chain_add(backend->sampler,
                                llama_sampler_init_penalties(256, repetition_penalty, 0.1f, 0.1f));

        // DRY sampler: catches n-gram (sequence) repetition like "gó gó gó" where
        // individual tokens may alternate. Multiplier=0.8, base=1.75,
        // allowed_length=2, last_n=256.
        const llama_vocab* vocab = llama_model_get_vocab(backend->model);
        static const char* dry_breakers[] = {"\n", ":", "\"", "*"};
        llama_sampler_chain_add(
            backend->sampler, llama_sampler_init_dry(vocab, llama_model_n_ctx_train(backend->model),
                                                     0.8f, 1.75f, 2, 256, dry_breakers, 4));

        // top_k only when caller requested it; mirrors LLM backend's
        // build_sampler_chain() in engines/llamacpp/llamacpp_backend.cpp.
        if (top_k > 0) {
            llama_sampler_chain_add(backend->sampler, llama_sampler_init_top_k(top_k));
        }

        llama_sampler_chain_add(backend->sampler, llama_sampler_init_top_p(top_p, 1));
        llama_sampler_chain_add(backend->sampler, llama_sampler_init_min_p(min_p, 1));
        llama_sampler_chain_add(backend->sampler, llama_sampler_init_temp(temperature));
        // Seed: negative means "pick a fresh random seed". llama.cpp expects a
        // uint32_t — LLAMA_DEFAULT_SEED stands in for "engine-picked random".
        const uint32_t dist_seed = (seed < 0) ? LLAMA_DEFAULT_SEED : static_cast<uint32_t>(seed);
        llama_sampler_chain_add(backend->sampler, llama_sampler_init_dist(dist_seed));
    } else {
        llama_sampler_chain_add(backend->sampler, llama_sampler_init_greedy());
    }

    // Cache the params for next comparison
    backend->cached_temperature = temperature;
    backend->cached_top_p = top_p;
    backend->cached_top_k = top_k;
    backend->cached_seed = seed;
    backend->cached_repetition_penalty = repetition_penalty;
    backend->cached_min_p = min_p;

    RAC_LOG_INFO(LOG_CAT,
                 "[v3] Sampler: temp=%.2f top_p=%.2f top_k=%d seed=%lld "
                 "repeat=%.2f min_p=%.2f DRY=0.8 + repeat_guard=4",
                 temperature, top_p, top_k, static_cast<long long>(seed), repetition_penalty,
                 min_p);
}

/**
 * Resolve the effective VLM model type from options override or auto-detected
 * default.
 */
static VLMModelType resolve_effective_model_type(VLMModelType detected,
                                                 const rac_vlm_options_t* options) {
    if (options && options->model_family != RAC_VLM_MODEL_FAMILY_AUTO) {
        switch (options->model_family) {
            case RAC_VLM_MODEL_FAMILY_QWEN2_VL:
                return VLMModelType::Qwen2VL;
            case RAC_VLM_MODEL_FAMILY_SMOLVLM:
                return VLMModelType::SmolVLM;
            case RAC_VLM_MODEL_FAMILY_LLAVA:
                return VLMModelType::LLaVA;
            default:
                return VLMModelType::Generic;
        }
    }
    return detected;
}

/**
 * Prepare the VLM context for generation: reset state, configure sampler,
 * build prompt, load image (if provided), tokenize, and evaluate.
 * After success, the backend is ready for token sampling (n_past is set).
 *
 * Shared between rac_vlm_llamacpp_process() and
 * rac_vlm_llamacpp_process_stream() to eliminate code duplication (~100 lines
 * of identical prompt prep logic).
 */
rac_result_t prepare_vlm_context(LlamaCppVLMBackend* backend, const rac_vlm_image_t* image,
                                 const char* prompt, const rac_vlm_options_t* options) {
    backend->cancel_requested = false;
    // Surface emit_image_embeddings on the backend so both
    // process() and process_stream() see the same caller toggle. No mtmd hook
    // exposes raw image embeddings today; recording it here keeps the C ABI
    // round-trip lossless and prepares the contract for future event surfaces.
    backend->emit_image_embeddings = (options && options->emit_image_embeddings == RAC_TRUE);
    if (backend->emit_image_embeddings) {
        // Logged at debug to make the no-op explicit until the mtmd path lands a
        // real producer — callers that flipped the toggle still see proof their
        // request was observed end-to-end.
        RAC_LOG_DEBUG(LOG_CAT,
                      "emit_image_embeddings=true requested; no producer wired "
                      "today, flag tracked for future event surfaces");
    }
    configure_sampler(backend, options);
    RAC_LOG_INFO(LOG_CAT, "[v3-prep] start image=%d format=%d width=%u height=%u data=%zu",
                 image ? 1 : 0, image ? static_cast<int>(image->format) : -1,
                 image ? image->width : 0, image ? image->height : 0, image ? image->data_size : 0);

    // Clear KV cache before each new request
    llama_memory_t mem = llama_get_memory(backend->ctx);
    if (mem) {
        llama_memory_clear(mem, true);
    }
    backend->n_past = 0;

    // Resolve effective model type: options override > auto-detected at load time
    VLMModelType effective_model_type = resolve_effective_model_type(backend->model_type, options);
    const char* system_prompt =
        (options && options->system_prompt) ? options->system_prompt : nullptr;

    // Build prompt with image handling.
    // image_marker_override (rac_vlm_options_t) takes precedence; otherwise use
    // the marker from custom_chat_template when supplied; fall back to the
    // backend default marker (mtmd / "<image>").
    std::string full_prompt;
    bool has_image = false;
    const char* image_marker = get_image_marker();
    if (options) {
        if (options->image_marker_override && options->image_marker_override[0] != '\0') {
            image_marker = options->image_marker_override;
        } else if (options->custom_chat_template && options->custom_chat_template->image_marker &&
                   options->custom_chat_template->image_marker[0] != '\0') {
            image_marker = options->custom_chat_template->image_marker;
        }
    }

    MtmdBitmapPtr bitmap;

    if (image && backend->mtmd_ctx) {
        if (image->format == RAC_VLM_IMAGE_FORMAT_FILE_PATH && image->file_path) {
            RAC_LOG_INFO(LOG_CAT, "[v3-prep] loading image from file path");
            bitmap.reset(mtmd_helper_bitmap_init_from_file(backend->mtmd_ctx, image->file_path));
        } else if (image->format == RAC_VLM_IMAGE_FORMAT_RGB_PIXELS && image->pixel_data) {
            RAC_LOG_INFO(LOG_CAT, "[v3-prep] loading raw RGB bitmap");
            bitmap.reset(mtmd_bitmap_init(image->width, image->height, image->pixel_data));
        } else if (image->format == RAC_VLM_IMAGE_FORMAT_BASE64) {
            // Base64 decode is not wired through mtmd yet. Returning an explicit
            // error is strictly better than silently dropping the image and
            // generating a text-only answer the caller will read as visual
            // analysis.
            RAC_LOG_ERROR(LOG_CAT,
                          "Base64 image format not supported by llama.cpp VLM "
                          "backend; decode to RGB pixels or supply a file path");
            return RAC_ERROR_INVALID_INPUT;
        }

        has_image = (bitmap != nullptr);
        RAC_LOG_INFO(LOG_CAT, "[v3-prep] bitmap ready=%d", has_image ? 1 : 0);
        if (!has_image) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to load image");
            return RAC_ERROR_INVALID_INPUT;
        }
    }

    const rac_vlm_chat_template_t* custom_chat_template =
        (options && options->custom_chat_template) ? options->custom_chat_template : nullptr;

    RAC_LOG_INFO(LOG_CAT, "[v3-prep] formatting prompt");
    full_prompt =
        format_vlm_prompt_with_template(backend->model, prompt, image_marker, has_image,
                                        system_prompt, effective_model_type, custom_chat_template);

    RAC_LOG_INFO(LOG_CAT, "[v3-prep] Prompt ready (chars=%d, img=%d, type=%d)",
                 (int)full_prompt.length(), has_image ? 1 : 0, (int)effective_model_type);

    // Tokenize and evaluate with MTMD if image present
    if (backend->mtmd_ctx && bitmap) {
        MtmdChunksPtr chunks(mtmd_input_chunks_init());

        mtmd_input_text text;
        text.text = full_prompt.c_str();
        text.add_special = true;
        text.parse_special = true;

        const mtmd_bitmap* bitmaps[] = {bitmap.get()};
        RAC_LOG_INFO(LOG_CAT, "[v3-prep] tokenizing image/text chunks");
        int32_t tokenize_result =
            mtmd_tokenize(backend->mtmd_ctx, chunks.get(), &text, bitmaps, 1);

        if (tokenize_result != 0) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to tokenize prompt with image: %d", tokenize_result);
            return RAC_ERROR_PROCESSING_FAILED;
        }

        llama_pos new_n_past = 0;
        RAC_LOG_INFO(LOG_CAT, "[v3-prep] evaluating image/text chunks");
        int32_t eval_result = mtmd_helper_eval_chunks(
            backend->mtmd_ctx, backend->ctx, chunks.get(), 0, 0,
            backend->config.batch_size > 0 ? backend->config.batch_size : kDefaultBatchSize, true,
            &new_n_past);
        RAC_LOG_INFO(LOG_CAT, "[v3-prep] image/text chunks evaluated rc=%d n_past=%d", eval_result,
                     (int)new_n_past);

        if (eval_result != 0) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to evaluate chunks: %d", eval_result);
            char detail[128];
            snprintf(detail, sizeof(detail),
                     "VLM prepare failed: mtmd_helper_eval_chunks returned %d "
                     "(image/text decode error)",
                     eval_result);
            rac_error_set_details(detail);
            return RAC_ERROR_PROCESSING_FAILED;
        }

        backend->n_past = new_n_past;
    } else {
        // Text-only mode - still apply chat template for consistent formatting
        full_prompt = format_vlm_prompt_with_template(backend->model, prompt, image_marker, false,
                                                      system_prompt, effective_model_type,
                                                      custom_chat_template);

        const llama_vocab* vocab = llama_model_get_vocab(backend->model);
        std::vector<llama_token> tokens(full_prompt.size() + 16);
        int n_tokens = llama_tokenize(vocab, full_prompt.c_str(), full_prompt.size(), tokens.data(),
                                      tokens.size(), true, true);
        if (n_tokens < 0) {
            tokens.resize(-n_tokens);
            n_tokens = llama_tokenize(vocab, full_prompt.c_str(), full_prompt.size(), tokens.data(),
                                      tokens.size(), true, true);
        }
        tokens.resize(n_tokens);

        LlamaBatchGuard batch_guard(llama_batch_init(n_tokens, 0, 1));
        llama_batch& batch = batch_guard.batch;
        for (int i = 0; i < n_tokens; i++) {
            batch.token[i] = tokens[i];
            batch.pos[i] = i;
            batch.n_seq_id[i] = 1;
            batch.seq_id[i][0] = 0;
            batch.logits[i] = (i == n_tokens - 1);
        }
        batch.n_tokens = n_tokens;

        if (llama_decode(backend->ctx, batch) != 0) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to decode prompt");
            rac_error_set_details(
                "VLM prepare failed: llama_decode returned non-zero while "
                "evaluating text-only prompt batch");
            return RAC_ERROR_PROCESSING_FAILED;
        }

        backend->n_past = n_tokens;
    }

    return RAC_SUCCESS;
}

// Verify backend struct size hasn't grown unexpectedly (catches accidental
// large member additions that might hurt cache locality).
static_assert(sizeof(LlamaCppVLMBackend) <= 512,
              "LlamaCppVLMBackend grew unexpectedly — review member layout");

/**
 * Collect caller-supplied stop sequences from rac_vlm_options_t.
 *
 * Mirrors the LLM backend's handling — empty strings are dropped, NULL entries
 * are skipped. Returns an empty vector when options is NULL, num is 0, or every
 * entry was dropped.
 */
std::vector<std::string> collect_stop_sequences(const rac_vlm_options_t* options) {
    std::vector<std::string> result;
    if (!options || !options->stop_sequences || options->num_stop_sequences == 0) {
        return result;
    }
    result.reserve(options->num_stop_sequences);
    for (size_t i = 0; i < options->num_stop_sequences; ++i) {
        const char* seq = options->stop_sequences[i];
        if (seq && seq[0] != '\0') {
            result.emplace_back(seq);
        }
    }
    return result;
}

// The window-scanning stop helpers (find_first_stop_sequence / max_stop_length)
// were identical to the LLM backend's; they now live in
// engines/llamacpp/llamacpp_stop_helpers.h and are shared by both paths.
using runanywhere::llamacpp_internal::find_first_stop_sequence;
using runanywhere::llamacpp_internal::max_stop_length;

}  // namespace

// =============================================================================
// LIFECYCLE MANAGEMENT
// =============================================================================

extern "C" {

rac_result_t rac_vlm_llamacpp_create(const char* model_path, const char* mmproj_path,
                                     const rac_vlm_llamacpp_config_t* config,
                                     rac_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = new (std::nothrow) LlamaCppVLMBackend();
    if (!backend) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    if (config) {
        backend->config = *config;
    }

    if (model_path) {
        backend->model_path = model_path;
    }
    if (mmproj_path) {
        backend->mmproj_path = mmproj_path;
    }

    *out_handle = backend;
    RAC_LOG_INFO(LOG_CAT, "Created VLM backend");
    return RAC_SUCCESS;
}

rac_result_t rac_vlm_llamacpp_load_model(rac_handle_t handle, const char* model_path,
                                         const char* mmproj_path,
                                         const rac_vlm_llamacpp_config_t* config) {
    if (!handle || !model_path) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    if (backend->is_shutting_down.load(std::memory_order_acquire)) {
        return RAC_ERROR_INVALID_STATE;
    }
    InFlightGuard in_flight_guard(backend);
    std::lock_guard<std::mutex> lock(backend->mutex);

    // Update config if provided
    if (config) {
        backend->config = *config;
    }

    RAC_LOG_INFO(LOG_CAT, "Loading VLM model: %s", model_path);
    if (mmproj_path) {
        RAC_LOG_INFO(LOG_CAT, "With vision projector: %s", mmproj_path);
    }

    // Initialize llama backend
    llama_backend_init();

    // Load model
    int gpu_layers = backend->config.gpu_layers;

#if defined(TARGET_OS_SIMULATOR) && TARGET_OS_SIMULATOR
    // iOS Simulator: Metal GPU allocation via MTLSimDevice crashes
    // in ggml_metal_buffer_set_tensor / _xpc_shmem_create for the mmproj
    // clip tensors. Force CPU execution on simulator (mirrors the LLM
    // backend's TARGET_OS_SIMULATOR guard in load_model(),
    // engines/llamacpp/llamacpp_backend.cpp). Physical iOS devices
    // still use Metal.
    if (gpu_layers != 0) {
        RAC_LOG_INFO(LOG_CAT,
                     "iOS Simulator detected: forcing VLM n_gpu_layers=0 + use_gpu_vision=0 "
                     "(Metal on MTLSimDevice crashes during mmproj load)");
        gpu_layers = 0;
        backend->config.use_gpu_vision = 0;
    }
#endif

    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = gpu_layers;

    backend->model = llama_model_load_from_file(model_path, model_params);
    if (!backend->model) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to load model: %s", model_path);
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Detect model type early — M-RoPE models (Qwen2-VL) produce NaN logits on
    // WebGPU due to shader precision limitations in the rotary position encoding.
    // The upstream WebGPU RoPE shader does contain M-RoPE handling, but f16
    // accumulation overflow causes all 151k+ logits to become NaN.
    //
    // Force CPU execution for these models by reloading with n_gpu_layers=0.
    // NOTE: default gpu_layers is -1 (all layers), so we check != 0 not > 0.
    //
    // PERFORMANCE: CPU fallback runs at ~1 tok/s in single-threaded WASM, which
    // is significantly slower than WebGPU-accelerated models like LFM2-VL (~15-20
    // tok/s). This is a correctness-over-speed trade-off until the WebGPU backend
    // resolves the M-RoPE precision issue.
    // TODO: re-test Qwen2-VL on WebGPU after future llama.cpp upgrades — the
    // Vulkan fp16 FA fix (b8168) and related precision work may eventually land
    // in the WebGPU backend as well.
    backend->model_type = detect_vlm_model_type(backend->model);
    bool force_cpu = false;

    if (backend->model_type == VLMModelType::Qwen2VL && gpu_layers != 0) {
        RAC_LOG_WARNING(LOG_CAT,
                        "Qwen2-VL uses M-RoPE which is incompatible with WebGPU "
                        "(gpu_layers=%d) — reloading with n_gpu_layers=0 for CPU execution",
                        gpu_layers);
        llama_model_free(backend->model);
        backend->model = nullptr;

        model_params.n_gpu_layers = 0;
        backend->model = llama_model_load_from_file(model_path, model_params);
        if (!backend->model) {
            RAC_LOG_ERROR(LOG_CAT, "Failed to reload model for CPU: %s", model_path);
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        force_cpu = true;
        gpu_layers = 0;
    }

    // Determine context size
    int ctx_size = backend->config.context_size;
    if (ctx_size <= 0) {
        ctx_size = llama_model_n_ctx_train(backend->model);
        if (ctx_size > kDefaultMaxContextSize)
            ctx_size = kDefaultMaxContextSize;  // Cap for mobile
    }
    backend->context_size = ctx_size;

    // Create context
    int n_threads = get_num_threads(backend->config.num_threads);
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = ctx_size;
    ctx_params.n_batch =
        backend->config.batch_size > 0 ? backend->config.batch_size : kDefaultBatchSize;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;

    backend->ctx = llama_init_from_model(backend->model, ctx_params);
    if (!backend->ctx) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to create context");
        llama_model_free(backend->model);
        backend->model = nullptr;
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Initialize sampler with default parameters
    // Sampler is reconfigured per-request in process()/process_stream() to
    // respect user options
    configure_sampler(backend, nullptr);

    // VLM contract (rac_vlm_service.h:44-47): mmproj_path is REQUIRED for
    // llama.cpp. Silently falling back to text-only on a missing/failed vision
    // projector previously let lifecycle/get_info report VLM ready while
    // inference dropped images — violating the readiness contract Swift's
    // public VLM API relies on. Fail the load cleanly so callers can either
    // supply a projector or route the request through the LLM path instead.
    if (!mmproj_path || !mmproj_path[0]) {
        RAC_LOG_ERROR(LOG_CAT,
                      "VLM load requires mmproj_path; refusing to load as VLM "
                      "without a vision projector");
        llama_sampler_free(backend->sampler);
        backend->sampler = nullptr;
        llama_free(backend->ctx);
        backend->ctx = nullptr;
        llama_model_free(backend->model);
        backend->model = nullptr;
        return RAC_ERROR_INVALID_INPUT;
    }

    mtmd_context_params mparams = mtmd_context_params_default();
    // Force CPU for vision encoder too when model requires CPU (M-RoPE)
#ifdef __EMSCRIPTEN__
    if (backend->config.use_gpu_vision && !force_cpu) {
        RAC_LOG_WARNING(LOG_CAT,
                        "Web VLM vision encoder is forced to CPU; WebGPU CLIP image encoding "
                        "is not stable in current llama.cpp/mtmd builds");
    }
    mparams.use_gpu = false;
    mparams.n_threads = 1;
#else
    mparams.use_gpu = force_cpu ? false : backend->config.use_gpu_vision;
    mparams.n_threads = n_threads;
#endif
    mparams.print_timings = false;
    mparams.warmup = true;

    backend->mtmd_ctx = mtmd_init_from_file(mmproj_path, backend->model, mparams);
    if (!backend->mtmd_ctx) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to load vision projector: %s", mmproj_path);
        llama_sampler_free(backend->sampler);
        backend->sampler = nullptr;
        llama_free(backend->ctx);
        backend->ctx = nullptr;
        llama_model_free(backend->model);
        backend->model = nullptr;
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }
    RAC_LOG_INFO(LOG_CAT, "Vision projector loaded successfully%s",
                 force_cpu ? " (CPU mode for M-RoPE compat)" : "");
    backend->mmproj_path = mmproj_path;

    backend->model_path = model_path;
    backend->model_loaded = true;
    backend->n_past = 0;

    RAC_LOG_INFO(LOG_CAT,
                 "VLM model loaded (ctx=%d, threads=%d, gpu_layers=%d%s) "
                 "[build:v4-cpu-mrope]",
                 ctx_size, n_threads, gpu_layers, force_cpu ? ", forced-cpu" : "");
    return RAC_SUCCESS;
}

namespace {
/// Tear down all llama.cpp / mtmd handles owned by the backend. Caller must
/// hold backend->mutex. Extracted so destroy() can reuse the body without
/// re-entering the public API surface (which now fails fast when
/// is_shutting_down is set).
void unload_model_locked(LlamaCppVLMBackend* backend) {
    if (backend->mtmd_ctx) {
        mtmd_free(backend->mtmd_ctx);
        backend->mtmd_ctx = nullptr;
    }

    if (backend->sampler) {
        llama_sampler_free(backend->sampler);
        backend->sampler = nullptr;
    }

    if (backend->ctx) {
        llama_free(backend->ctx);
        backend->ctx = nullptr;
    }

    if (backend->model) {
        llama_model_free(backend->model);
        backend->model = nullptr;
    }

    backend->model_loaded = false;
    backend->n_past = 0;
    RAC_LOG_INFO(LOG_CAT, "VLM model unloaded");
}
}  // namespace

rac_result_t rac_vlm_llamacpp_unload_model(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    if (backend->is_shutting_down.load(std::memory_order_acquire)) {
        return RAC_ERROR_INVALID_STATE;
    }
    InFlightGuard in_flight_guard(backend);
    std::lock_guard<std::mutex> lock(backend->mutex);

    unload_model_locked(backend);
    return RAC_SUCCESS;
}

rac_bool_t rac_vlm_llamacpp_is_model_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;
    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    return backend->model_loaded ? RAC_TRUE : RAC_FALSE;
}

void rac_vlm_llamacpp_destroy(rac_handle_t handle) {
    if (!handle)
        return;

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);

    // Signal shutdown and cancel any in-flight inference so streaming loops
    // wake up. Future public-API entries on this handle fail fast on the
    // is_shutting_down check (mirrors voice_agent.cpp:179).
    backend->is_shutting_down.store(true, std::memory_order_release);
    backend->cancel_requested.store(true, std::memory_order_release);

    // Spin-wait for any in-flight op (process / process_stream / load /
    // unload / get_model_info) to drain before freeing. Sleep 1ms between
    // polls rather than yield-spinning so a multi-second LLM call holding
    // the counter doesn't burn 100% CPU or starve QoS-scheduled threads.
    while (backend->in_flight.load(std::memory_order_acquire) > 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    // Tear down handles under the mutex; safe because no new public call
    // can acquire the mutex once is_shutting_down is set and in_flight
    // has drained.
    {
        std::lock_guard<std::mutex> lock(backend->mutex);
        unload_model_locked(backend);
    }

    delete backend;
    RAC_LOG_INFO(LOG_CAT, "VLM backend destroyed");
}

// =============================================================================
// INFERENCE
// =============================================================================

rac_result_t rac_vlm_llamacpp_process(rac_handle_t handle, const rac_vlm_image_t* image,
                                      const char* prompt, const rac_vlm_options_t* options,
                                      rac_vlm_result_t* out_result) {
    if (!handle || !prompt || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    if (backend->is_shutting_down.load(std::memory_order_acquire)) {
        return RAC_ERROR_INVALID_STATE;
    }
    InFlightGuard in_flight_guard(backend);
    std::lock_guard<std::mutex> lock(backend->mutex);

    if (!backend->model_loaded) {
        RAC_LOG_ERROR(LOG_CAT, "No model loaded");
        return RAC_ERROR_MODEL_NOT_LOADED;
    }

    // Shared context preparation: reset, configure sampler, build prompt,
    // evaluate
    rac_result_t prep_result = prepare_vlm_context(backend, image, prompt, options);
    if (prep_result != RAC_SUCCESS) {
        return prep_result;
    }

    // Generate response (batch mode — accumulate all tokens)
    const int max_tokens =
        (options && options->max_tokens > 0) ? options->max_tokens : kDefaultMaxTokens;
    std::string response;
    response.reserve(kDefaultMaxTokens);  // Typical VLM responses are a few hundred tokens
    int tokens_generated = 0;

    LlamaBatchGuard batch_guard(llama_batch_init(1, 0, 1));
    llama_batch& batch = batch_guard.batch;
    const llama_vocab* const vocab = llama_model_get_vocab(backend->model);

    // Runtime repetition guard: track last token and consecutive repeat count.
    // If the same token appears too many times in a row, the model is stuck and
    // we force-stop to avoid emitting garbage like "gó gó gó gó ...".
    llama_token prev_token = -1;
    int repeat_run = 0;
    constexpr int MAX_CONSECUTIVE_REPEATS = 4;

    // Caller-supplied stop sequences (mirrors LLM backend's run_decode_loop in
    // engines/llamacpp/llamacpp_backend.cpp). Empty when no caller stops are
    // provided so the scan is short-circuited to a single emptiness check.
    const std::vector<std::string> user_stops = collect_stop_sequences(options);
    const size_t user_stop_max_len = max_stop_length(user_stops);

    // Surface decode failure to the caller instead of returning RAC_SUCCESS
    // with a truncated response. Mirrors the streaming path below.
    bool decode_failed = false;

    for (int i = 0; i < max_tokens && !backend->cancel_requested; i++) {
        // Diagnostic: on first token, inspect logits for NaN/corruption
#ifdef RAC_VLM_ENABLE_DIAGNOSTICS
        if (i == 0) {
            float* logits = llama_get_logits(backend->ctx);
            int n_vocab = llama_vocab_n_tokens(vocab);
            if (logits && n_vocab > 0) {
                float max_logit = logits[0];
                int max_idx = 0;
                int nan_count = 0;
                int inf_count = 0;
                for (int v = 0; v < n_vocab; v++) {
                    if (logits[v] != logits[v])
                        nan_count++;  // NaN check
                    if (logits[v] > 1e30f || logits[v] < -1e30f)
                        inf_count++;
                    if (logits[v] > max_logit) {
                        max_logit = logits[v];
                        max_idx = v;
                    }
                }
                RAC_LOG_DEBUG(LOG_CAT,
                              "[v3-diag] Logits: n_vocab=%d, max_logit=%.4f at token "
                              "%d, NaN=%d, Inf=%d",
                              n_vocab, max_logit, max_idx, nan_count, inf_count);
                // Log top 5 logits
                float top5_val[5] = {-1e30f, -1e30f, -1e30f, -1e30f, -1e30f};
                int top5_idx[5] = {0, 0, 0, 0, 0};
                for (int v = 0; v < n_vocab; v++) {
                    if (logits[v] != logits[v])
                        continue;  // skip NaN
                    for (int k = 0; k < 5; k++) {
                        if (logits[v] > top5_val[k]) {
                            for (int j = 4; j > k; j--) {
                                top5_val[j] = top5_val[j - 1];
                                top5_idx[j] = top5_idx[j - 1];
                            }
                            top5_val[k] = logits[v];
                            top5_idx[k] = v;
                            break;
                        }
                    }
                }
                RAC_LOG_DEBUG(LOG_CAT,
                              "[v3-diag] Top5: [%d]=%.2f [%d]=%.2f [%d]=%.2f [%d]=%.2f [%d]=%.2f",
                              top5_idx[0], top5_val[0], top5_idx[1], top5_val[1], top5_idx[2],
                              top5_val[2], top5_idx[3], top5_val[3], top5_idx[4], top5_val[4]);
            }
        }
#endif

        llama_token token = llama_sampler_sample(backend->sampler, backend->ctx, -1);
        llama_sampler_accept(backend->sampler, token);

        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        // Detect stuck generation: same token repeated consecutively
        if (token == prev_token) {
            repeat_run++;
            if (repeat_run >= MAX_CONSECUTIVE_REPEATS) {
                RAC_LOG_WARNING(LOG_CAT, "Repetition guard: token %d repeated %d times, stopping",
                                token, repeat_run + 1);
                break;
            }
        } else {
            repeat_run = 0;
        }
        prev_token = token;

        char buf[256];
        int len = llama_token_to_piece(vocab, token, buf, sizeof(buf) - 1, 0, true);
        if (len > 0) {
            response.append(buf, len);
        }
        tokens_generated++;

        // Stop-sequence detection: scan only the tail of the accumulated response
        // bounded by the longest caller stop length so the check stays O(maxlen)
        // per token instead of O(|response|).
        if (!user_stops.empty()) {
            const size_t scan_window = user_stop_max_len * 2;
            const size_t scan_start =
                response.size() > scan_window ? response.size() - scan_window : 0;
            const size_t local_pos =
                find_first_stop_sequence(response.substr(scan_start), user_stops);
            if (local_pos != std::string::npos) {
                // Trim the response at the first match (preserves text before stop).
                const size_t cut = scan_start + local_pos;
                response.resize(cut);
                RAC_LOG_INFO(LOG_CAT, "Caller stop sequence matched at offset %zu, halting", cut);
                break;
            }
        }

        // Prepare next token
        batch.token[0] = token;
        batch.pos[0] = backend->n_past++;
        batch.n_seq_id[0] = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0] = true;
        batch.n_tokens = 1;

        if (llama_decode(backend->ctx, batch) != 0) {
            RAC_LOG_ERROR(LOG_CAT, "llama_decode failed during VLM process");
            rac_error_set_details(
                "VLM generation failed: llama_decode returned non-zero "
                "(mid-stream decode error in non-streaming process())");
            decode_failed = true;
            break;
        }
    }

    if (decode_failed) {
        return RAC_ERROR_INFERENCE_FAILED;
    }

    // Fill result
    out_result->text = strdup(response.c_str());
    if (!out_result->text) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to allocate result text");
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    out_result->completion_tokens = tokens_generated;
    out_result->prompt_tokens = backend->n_past - tokens_generated;
    out_result->total_tokens = backend->n_past;

    RAC_LOG_INFO(LOG_CAT, "Generated %d tokens", tokens_generated);
    return RAC_SUCCESS;
}

rac_result_t rac_vlm_llamacpp_process_stream(rac_handle_t handle, const rac_vlm_image_t* image,
                                             const char* prompt, const rac_vlm_options_t* options,
                                             rac_vlm_llamacpp_stream_callback_fn callback,
                                             void* user_data) {
    if (!handle || !prompt || !callback) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    if (backend->is_shutting_down.load(std::memory_order_acquire)) {
        return RAC_ERROR_INVALID_STATE;
    }
    InFlightGuard in_flight_guard(backend);
    std::lock_guard<std::mutex> lock(backend->mutex);

    if (!backend->model_loaded) {
        RAC_LOG_ERROR(LOG_CAT, "No model loaded");
        return RAC_ERROR_MODEL_NOT_LOADED;
    }

    // Shared context preparation: reset, configure sampler, build prompt,
    // evaluate
    rac_result_t prep_result = prepare_vlm_context(backend, image, prompt, options);
    if (prep_result != RAC_SUCCESS) {
        return prep_result;
    }

    // Generate response (streaming mode — callback per token)
    const int max_tokens =
        (options && options->max_tokens > 0) ? options->max_tokens : kDefaultMaxTokens;

    LlamaBatchGuard batch_guard(llama_batch_init(1, 0, 1));
    llama_batch& batch = batch_guard.batch;
    const llama_vocab* const vocab = llama_model_get_vocab(backend->model);

    // Runtime repetition guard (same as non-streaming path)
    llama_token prev_token = -1;
    int repeat_run = 0;
    constexpr int MAX_CONSECUTIVE_REPEATS = 4;

    // The VLM stream ABI documents `is_final` as the terminal marker callers
    // wait on to flush UI / accumulated text (rac_vlm_llamacpp.h:139-148).
    // Several normal exit paths (max_tokens exhaustion, empty-EOG token,
    // callback-requested stop) used to fall through to RAC_SUCCESS without
    // ever emitting that marker, leaving direct engine-API consumers stuck.
    // Track whether a terminal callback was already sent (repetition guard
    // and the non-empty-EOG branch already emit one) so we can guarantee
    // exactly one is_final=true event before returning success.
    bool terminal_emitted = false;
    // Track decode failure so we surface it as an error instead of silently
    // returning RAC_SUCCESS after emitting the terminal callback.
    bool decode_failed = false;

    // Caller-supplied stop sequences: track a rolling tail so a stop sequence
    // can span multiple token pieces (mirrors run_decode_loop in
    // engines/llamacpp/llamacpp_backend.cpp). Empty when no stops were
    // supplied so per-token cost is just an emptiness check.
    const std::vector<std::string> user_stops = collect_stop_sequences(options);
    const size_t user_stop_max_len = max_stop_length(user_stops);
    std::string stop_window;
    if (user_stop_max_len > 0) {
        stop_window.reserve(user_stop_max_len * 2);
    }

    for (int i = 0; i < max_tokens && !backend->cancel_requested; i++) {
        llama_token token = llama_sampler_sample(backend->sampler, backend->ctx, -1);
        llama_sampler_accept(backend->sampler, token);

        bool is_eog = llama_vocab_is_eog(vocab, token);

        // Detect stuck generation
        if (!is_eog) {
            if (token == prev_token) {
                repeat_run++;
                if (repeat_run >= MAX_CONSECUTIVE_REPEATS) {
                    RAC_LOG_WARNING(LOG_CAT,
                                    "Repetition guard: token %d repeated %d times, stopping", token,
                                    repeat_run + 1);
                    callback("", RAC_TRUE, user_data);
                    terminal_emitted = true;
                    break;
                }
            } else {
                repeat_run = 0;
            }
            prev_token = token;
        }

        char buf[256];
        int len = llama_token_to_piece(vocab, token, buf, sizeof(buf) - 1, 0, true);
        if (len > 0) {
            buf[len] = '\0';
            const rac_bool_t final_flag = is_eog ? RAC_TRUE : RAC_FALSE;

            if (user_stops.empty()) {
                // No caller stops -> emit immediately; saves a copy per token in the
                // common case (no caller-supplied stop sequence).
                const rac_bool_t cb_rc = callback(buf, final_flag, user_data);
                if (final_flag == RAC_TRUE) {
                    terminal_emitted = true;
                }
                if (cb_rc == RAC_FALSE) {
                    break;  // Callback requested stop
                }
            } else {
                // Defer emission: a stop sequence can span multiple token pieces, so
                // hold back the trailing `user_stop_max_len` bytes until we know
                // they're not part of a stop. When a stop is found, emit only the
                // bytes BEFORE the match — never leaking the stop prefix to the
                // callback. Mirrors the LLM backend's stop_window pattern in
                // run_decode_loop (engines/llamacpp/llamacpp_backend.cpp).
                stop_window.append(buf, len);

                const size_t found_pos = find_first_stop_sequence(stop_window, user_stops);
                if (found_pos != std::string::npos) {
                    RAC_LOG_INFO(LOG_CAT, "Caller stop sequence matched, halting stream");
                    if (found_pos > 0) {
                        // Emit the part before the stop as a normal (non-final) chunk so
                        // the caller's accumulator captures it, then send the terminal
                        // marker. NUL-terminate via a temporary buffer.
                        const std::string safe_prefix = stop_window.substr(0, found_pos);
                        callback(safe_prefix.c_str(), RAC_FALSE, user_data);
                    }
                    callback("", RAC_TRUE, user_data);
                    terminal_emitted = true;
                    break;
                }

                // No stop match yet — flush everything that cannot possibly become
                // part of a stop sequence (i.e. bytes older than user_stop_max_len
                // from the end of stop_window). Keep the trailing user_stop_max_len
                // bytes in stop_window for the next iteration.
                if (final_flag == RAC_TRUE) {
                    // EOG: flush the whole remaining window and signal terminal.
                    if (!stop_window.empty()) {
                        callback(stop_window.c_str(), RAC_TRUE, user_data);
                    } else {
                        callback("", RAC_TRUE, user_data);
                    }
                    terminal_emitted = true;
                    stop_window.clear();
                } else if (stop_window.size() > user_stop_max_len) {
                    const size_t safe_len = stop_window.size() - user_stop_max_len;
                    const std::string safe_chunk = stop_window.substr(0, safe_len);
                    stop_window.erase(0, safe_len);
                    const rac_bool_t cb_rc = callback(safe_chunk.c_str(), RAC_FALSE, user_data);
                    if (cb_rc == RAC_FALSE) {
                        break;  // Callback requested stop
                    }
                }
            }
        }

        if (is_eog) {
            break;
        }

        // Prepare next token
        batch.token[0] = token;
        batch.pos[0] = backend->n_past++;
        batch.n_seq_id[0] = 1;
        batch.seq_id[0][0] = 0;
        batch.logits[0] = true;
        batch.n_tokens = 1;

        if (llama_decode(backend->ctx, batch) != 0) {
            RAC_LOG_ERROR(LOG_CAT, "llama_decode failed during VLM streaming");
            rac_error_set_details(
                "VLM generation failed: llama_decode returned non-zero "
                "(mid-stream decode error in streaming process_stream())");
            decode_failed = true;
            break;
        }
    }

    // Guarantee the terminal marker on every successful exit path so direct
    // engine-API callers can rely on is_final=true to close the stream. When
    // caller stops were active and no stop hit, flush whatever's left in the
    // stop_window so the user sees the full response.
    if (!terminal_emitted) {
        if (!user_stops.empty() && !stop_window.empty() && !decode_failed) {
            callback(stop_window.c_str(), RAC_TRUE, user_data);
        } else {
            callback("", RAC_TRUE, user_data);
        }
        terminal_emitted = true;
    }

    return decode_failed ? RAC_ERROR_INFERENCE_FAILED : RAC_SUCCESS;
}

void rac_vlm_llamacpp_cancel(rac_handle_t handle) {
    if (!handle)
        return;
    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    backend->cancel_requested = true;
}

rac_result_t rac_vlm_llamacpp_get_model_info(rac_handle_t handle, char** out_json) {
    if (!handle || !out_json) {
        return RAC_ERROR_NULL_POINTER;
    }

    auto* backend = static_cast<LlamaCppVLMBackend*>(handle);
    if (backend->is_shutting_down.load(std::memory_order_acquire)) {
        return RAC_ERROR_INVALID_STATE;
    }
    InFlightGuard in_flight_guard(backend);
    std::lock_guard<std::mutex> lock(backend->mutex);

    if (!backend->model_loaded) {
        return RAC_ERROR_MODEL_NOT_LOADED;
    }

    // Build simple JSON info
    char buffer[1024];
    snprintf(buffer, sizeof(buffer),
             "{\"context_size\":%d,\"model_path\":\"%s\",\"has_vision\":%s}", backend->context_size,
             backend->model_path.c_str(), backend->mtmd_ctx ? "true" : "false");

    *out_json = strdup(buffer);
    if (!*out_json) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
}

}  // extern "C"
