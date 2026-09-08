/**
 * @file rac_llamacpp_logging.cpp
 * @brief Routes ggml/llama.cpp's log sink through commons; see
 *        llamacpp_logging.h and rac_llamacpp_set_log_callback() in
 *        rac/backends/rac_llm_llamacpp.h for the contract.
 */

#include "llamacpp_logging.h"

#include "rac/backends/rac_llm_llamacpp.h"

#include <llama.h>

#include <mutex>
#include <string>

#include "rac/core/rac_logger.h"

namespace {

static const char* LOG_CAT = "LLM.LlamaCpp.GGML";

std::mutex g_log_mutex;
rac_llamacpp_log_callback_fn g_user_callback = nullptr;
void* g_user_data = nullptr;
// Carries the last real (non-CONT) level forward so a ggml continuation line
// — GGML_LOG_LEVEL_CONT, used to keep printing a multi-line message — reaches
// the caller's callback tagged with the severity of the message it belongs
// to, not as its own unclassified line.
ggml_log_level g_last_real_level = GGML_LOG_LEVEL_INFO;

rac_log_level_t rac_level_from_ggml(ggml_log_level level) {
    switch (level) {
        case GGML_LOG_LEVEL_DEBUG:
            return RAC_LOG_DEBUG;
        case GGML_LOG_LEVEL_INFO:
            return RAC_LOG_INFO;
        case GGML_LOG_LEVEL_WARN:
            return RAC_LOG_WARNING;
        case GGML_LOG_LEVEL_ERROR:
            return RAC_LOG_ERROR;
        case GGML_LOG_LEVEL_NONE:
        case GGML_LOG_LEVEL_CONT:
        default:
            // Callers only reach here for GGML_LOG_LEVEL_NONE (ggml never
            // logs at NONE itself; it's a sentinel) — CONT is resolved to
            // g_last_real_level before this is called.
            return RAC_LOG_DEBUG;
    }
}

// Single ggml_log_set() sink (via llama_log_set(), which forwards to
// ggml_log_set() internally — see llama-impl.cpp) for the whole process.
// Either forwards verbatim to a caller-installed callback (accurate level per
// line, CONT resolved, so the caller can gate on its own quiet/verbose
// setting) or falls back to the routing this engine always had: ERROR/WARN
// forwarded, INFO downgraded to RAC_LOG_DEBUG, and DEBUG/CONT dropped
// entirely. That fallback shape is preserved byte-for-byte so installing this
// shared sink is not itself a behavior change for a caller that never touches
// rac_llamacpp_set_log_callback().
void ggml_log_trampoline(ggml_log_level level, const char* text, void* /*data*/) {
    std::string msg(text ? text : "");
    while (!msg.empty() && (msg.back() == '\n' || msg.back() == '\r')) {
        msg.pop_back();
    }
    if (msg.empty()) {
        return;
    }

    rac_llamacpp_log_callback_fn user_callback;
    void* user_data;
    ggml_log_level effective_level;
    {
        std::lock_guard<std::mutex> lock(g_log_mutex);
        if (level != GGML_LOG_LEVEL_CONT) {
            g_last_real_level = level;
        }
        effective_level = (level == GGML_LOG_LEVEL_CONT) ? g_last_real_level : level;
        user_callback = g_user_callback;
        user_data = g_user_data;
    }

    if (user_callback) {
        user_callback(rac_level_from_ggml(effective_level), msg.c_str(), user_data);
        return;
    }

    // Default routing this engine has always had (previously a private
    // llama_log_set() callback local to llamacpp_backend.cpp): DEBUG/NONE/CONT
    // dropped, INFO downgraded to RAC_LOG_DEBUG, WARN/ERROR forwarded as-is.
    if (effective_level == GGML_LOG_LEVEL_ERROR) {
        RAC_LOG_ERROR(LOG_CAT, "%s", msg.c_str());
    } else if (effective_level == GGML_LOG_LEVEL_WARN) {
        RAC_LOG_WARNING(LOG_CAT, "%s", msg.c_str());
    } else if (effective_level == GGML_LOG_LEVEL_INFO) {
        RAC_LOG_DEBUG(LOG_CAT, "%s", msg.c_str());
    }
}

}  // namespace

namespace runanywhere::llamacpp_internal {

void ensure_llamacpp_ggml_log_routed() {
    static std::once_flag routed_once;
    std::call_once(routed_once, []() { llama_log_set(ggml_log_trampoline, nullptr); });
}

}  // namespace runanywhere::llamacpp_internal

extern "C" void rac_llamacpp_set_log_callback(rac_llamacpp_log_callback_fn callback,
                                              void* user_data) {
    runanywhere::llamacpp_internal::ensure_llamacpp_ggml_log_routed();
    std::lock_guard<std::mutex> lock(g_log_mutex);
    g_user_callback = callback;
    g_user_data = callback ? user_data : nullptr;
}
