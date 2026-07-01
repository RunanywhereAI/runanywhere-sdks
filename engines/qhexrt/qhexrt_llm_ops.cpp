/**
 * @file qhexrt_llm_ops.cpp
 * @brief LLM (RAC_PRIMITIVE_GENERATE_TEXT) vtable over the QHexRT C ABI.
 *
 * Compiled ONLY in routable builds (RAC_QHEXRT_ENGINE_AVAILABLE=1); the public
 * stub build never sees this TU (see CMakeLists.txt). Adapts the generic
 * `rac_llm_service_ops_t` onto QHexRT's `qhx_*` C ABI via the shared session
 * helper (qhexrt_session.h).
 *
 * No C++ exception may cross back into the registry / JNI: every op body wraps
 * its allocating work and coerces failures to rac_result_t.
 */

#include <cstdint>
#include <cstring>
#include <string>

#include "qhexrt_session.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"

namespace {

const char* LOG_CAT = "QHexRT";

using qhexrt_engine::Session;
using qhexrt_engine::session_close;
using qhexrt_engine::session_open;

Session* as_session(void* impl) { return static_cast<Session*>(impl); }

void fill_cfg(qhx_gen_cfg* cfg, const rac_llm_options_t* o) {
    qhx_gen_cfg_default(cfg);
    if (o == nullptr) {
        return;
    }
    if (o->max_tokens > 0) cfg->max_new_tokens = o->max_tokens;
    cfg->temperature = o->temperature;
    cfg->top_p = o->top_p;
    if (o->top_k > 0) cfg->top_k = o->top_k;
    if (o->repetition_penalty > 0.0f) cfg->repetition_penalty = o->repetition_penalty;
    cfg->min_p = o->min_p;
    if (o->seed != 0) cfg->seed = static_cast<uint64_t>(o->seed);
    if (o->stop_sequences != nullptr && o->num_stop_sequences > 0) {
        cfg->stop_strings = o->stop_sequences;
        cfg->n_stop_strings = static_cast<int>(o->num_stop_sequences);
    }
    // Grammar-constrained decoding (QHexRT owns the logit mask). The SDK carries one `grammar` string
    // (rac_llm_options_t.grammar); QHexRT's qhx_gen_cfg needs {kind, spec}. The caller encodes the kind as
    // a prefix:
    //   "json[:<spec>]"          -> a single valid JSON object
    //   "toolcall[:<names>]"     -> strict [name(args)] over an enumerated tool set
    //   "toolcall_opt[:<names>]" -> free chat OR one valid [name(args)] (a unified chat+tool path)
    // <names> is a comma-separated tool list; omit it to use QHexRT's default set. The spec pointer aliases
    // o->grammar, which outlives this synchronous qhx_generate call. (Requires the grammar-enabled
    // qhexrt_c.h staged in prebuilt/; older headers lack grammar/grammar_kind and won't compile this block.)
    if (o->grammar != nullptr && o->grammar[0] != '\0') {
        const char* g = o->grammar;
        auto spec_after = [](const char* s, size_t n) -> const char* { return (s[n] == ':') ? s + n + 1 : ""; };
        if (std::strncmp(g, "toolcall_opt", 12) == 0) {
            cfg->grammar_kind = 3;  // GrammarKind::ToolCallOptional
            cfg->grammar = spec_after(g, 12);
        } else if (std::strncmp(g, "toolcall", 8) == 0) {
            cfg->grammar_kind = 2;  // GrammarKind::ToolCall
            cfg->grammar = spec_after(g, 8);
        } else if (std::strncmp(g, "json", 4) == 0) {
            cfg->grammar_kind = 1;  // GrammarKind::JsonObject
            cfg->grammar = spec_after(g, 4);
        }
        // Unknown prefix => grammar_kind stays 0 (off): plain, unconstrained generation.
    }
}

void fill_inputs(qhx_inputs* in, const char* prompt, const rac_llm_options_t* o) {
    *in = qhx_inputs{};
    in->text = prompt;
    if (o != nullptr && o->system_prompt != nullptr && o->system_prompt[0] != '\0') {
        in->system_prompt = o->system_prompt;
    }
    // Prior conversation turns (alternating user,assistant). QHexRT's runtime
    // chat template renders {system_prompt, history, text} from the model's
    // manifest markers, so the app never hand-builds a ChatML string.
    if (o != nullptr && o->history != nullptr && o->n_history > 0) {
        in->history = o->history;
        in->n_history = o->n_history;
    }
}

// Bridge QHexRT's chunk callback (utf8/len, return 0 to cancel) onto the rac
// stream callback (NUL-terminated token, RAC_TRUE to continue).
struct StreamCtx {
    rac_llm_stream_callback_fn cb;
    void* user;
    Session* session;
    std::string buf;  // reused per chunk to NUL-terminate
};

int stream_trampoline(void* user, const char* utf8, int len, int /*token_id*/, int is_final) {
    auto* c = static_cast<StreamCtx*>(user);
    if (c == nullptr || is_final != 0 || utf8 == nullptr) {
        return 1;  // nothing to forward on the terminal call
    }
    if (c->session != nullptr && c->session->cancel.load(std::memory_order_relaxed)) {
        return 0;  // barge-in
    }
    if (c->cb == nullptr) {
        return 1;
    }
    c->buf.assign(utf8, static_cast<size_t>(len < 0 ? 0 : len));
    return c->cb(c->buf.c_str(), c->user) == RAC_FALSE ? 0 : 1;
}

void fill_result(rac_llm_result_t* out, const qhx_output& o) {
    out->text = rac_strdup(o.text != nullptr ? o.text : "");
    out->prompt_tokens = o.n_prompt;
    out->completion_tokens = o.n_generated;
    out->total_tokens = o.n_prompt + o.n_generated;
    out->time_to_first_token_ms = static_cast<int64_t>(o.prefill_ms);
    out->total_time_ms = static_cast<int64_t>(o.prefill_ms + o.decode_ms);
    out->tokens_per_second =
        o.decode_ms > 0.0 ? static_cast<float>(o.n_generated * 1000.0 / o.decode_ms) : 0.0f;
}

// ───────────────────────────────── vtable ops ───────────────────────────────

// QHexRT loads the model eagerly in create(); model_id IS the manifest path.
rac_result_t qhexrt_llm_create(const char* model_id, const char* /*config_json*/, void** out_impl) {
    if (out_impl == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    if (model_id == nullptr || model_id[0] == '\0') {
        return RAC_ERROR_NULL_POINTER;
    }
    RAC_LOG_INFO(LOG_CAT, "qhexrt_llm_create: manifest=%s", model_id);
    Session* s = session_open(model_id);
    if (s == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    *out_impl = s;
    return RAC_SUCCESS;
}

// Model is already loaded in create(); initialize is a no-op for symmetry.
rac_result_t qhexrt_llm_initialize(void* /*impl*/, const char* /*model_path*/) { return RAC_SUCCESS; }

rac_result_t qhexrt_llm_generate(void* impl, const char* prompt, const rac_llm_options_t* options,
                                 rac_llm_result_t* out_result) {
    auto* c = as_session(impl);
    if (c == nullptr || c->sess == nullptr || out_result == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    try {
        c->cancel.store(false, std::memory_order_relaxed);
        qhx_inputs in;
        fill_inputs(&in, prompt, options);
        qhx_gen_cfg cfg;
        fill_cfg(&cfg, options);
        qhx_output out{};
        qhx_status st = qhx_generate(c->sess, &in, &cfg, nullptr, nullptr, &out);
        if (st != 0) {
            RAC_LOG_ERROR(LOG_CAT, "qhx_generate failed: %s", qhx_status_str(st));
            return RAC_ERROR_GENERATION_FAILED;
        }
        fill_result(out_result, out);
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t qhexrt_llm_generate_stream(void* impl, const char* prompt,
                                        const rac_llm_options_t* options,
                                        rac_llm_stream_callback_fn callback, void* user_data) {
    auto* c = as_session(impl);
    if (c == nullptr || c->sess == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    try {
        c->cancel.store(false, std::memory_order_relaxed);
        qhx_inputs in;
        fill_inputs(&in, prompt, options);
        qhx_gen_cfg cfg;
        fill_cfg(&cfg, options);
        StreamCtx ctx{callback, user_data, c, std::string()};
        qhx_output out{};
        qhx_status st = qhx_generate(c->sess, &in, &cfg, stream_trampoline, &ctx, &out);
        if (st != 0) {
            RAC_LOG_ERROR(LOG_CAT, "qhx_generate(stream) failed: %s", qhx_status_str(st));
            return RAC_ERROR_GENERATION_FAILED;
        }
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t qhexrt_llm_get_info(void* impl, rac_llm_info_t* out_info) {
    if (out_info == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* c = as_session(impl);
    out_info->is_ready = (c != nullptr && c->sess != nullptr) ? RAC_TRUE : RAC_FALSE;
    out_info->current_model = nullptr;
    out_info->context_length = 0;
    out_info->supports_streaming = RAC_TRUE;
    return RAC_SUCCESS;
}

rac_result_t qhexrt_llm_cancel(void* impl) {
    auto* c = as_session(impl);
    if (c != nullptr) {
        c->cancel.store(true, std::memory_order_relaxed);
    }
    return RAC_SUCCESS;
}

// Drop KV / counters; keeps the service (model + session) alive.
rac_result_t qhexrt_llm_cleanup(void* impl) {
    auto* c = as_session(impl);
    if (c != nullptr && c->sess != nullptr) {
        qhx_session_reset(c->sess);
    }
    return RAC_SUCCESS;
}

void qhexrt_llm_destroy(void* impl) { session_close(as_session(impl)); }

}  // namespace

// Consumed by rac_plugin_entry_qhexrt.cpp (external linkage; visibility limited
// to the carrier library). Optional ops QHexRT does not serve (LoRA, adaptive
// context) are NULL: the registry maps NULL to RAC_ERROR_NOT_SUPPORTED.
extern "C" const rac_llm_service_ops_t g_qhexrt_llm_ops = {
    /* .initialize            = */ qhexrt_llm_initialize,
    /* .generate              = */ qhexrt_llm_generate,
    /* .generate_stream       = */ qhexrt_llm_generate_stream,
    /* .get_info              = */ qhexrt_llm_get_info,
    /* .cancel                = */ qhexrt_llm_cancel,
    /* .cleanup               = */ qhexrt_llm_cleanup,
    /* .destroy               = */ qhexrt_llm_destroy,
    /* .load_lora             = */ nullptr,
    /* .remove_lora           = */ nullptr,
    /* .clear_lora            = */ nullptr,
    /* .get_lora_info         = */ nullptr,
    /* .inject_system_prompt  = */ nullptr,
    /* .append_context        = */ nullptr,
    /* .generate_from_context = */ nullptr,
    /* .clear_context         = */ nullptr,
    /* .create                = */ qhexrt_llm_create,
};
