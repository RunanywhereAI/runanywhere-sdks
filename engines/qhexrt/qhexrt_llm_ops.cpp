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

// End-of-turn marker for a templated family. The runtime's EOS-token-id stop
// can miss the templated turn terminator (the bundles carry no chat template,
// so its detokenizer doesn't always map the turn-end token back to a stop),
// which lets generation run to the token cap emitting post-turn padding. A
// stop *string* halts decoding deterministically at the turn boundary (and
// trims the marker from the output). Empty => no marker (pass-through family).
std::string family_stop_marker(const std::string& pre) {
    if (pre == "qwen2" || pre == "qwen3" || pre == "lfm") {
        return "<|im_end|>";
    }
    if (pre == "gemma") {
        return "<end_of_turn>";
    }
    return {};
}

void fill_cfg(qhx_gen_cfg* cfg, Session* c, const rac_llm_options_t* o) {
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

    // Merge the templated family's end-of-turn marker with any caller stops, and
    // keep them alive on the session for the qhx_generate call.
    if (c != nullptr) {
        c->stop_storage.clear();
        c->stop_ptrs.clear();
        const std::string marker = family_stop_marker(c->tokenizer_pre);
        if (!marker.empty()) {
            c->stop_storage.push_back(marker);
        }
        for (int i = 0; o->stop_sequences != nullptr && i < o->num_stop_sequences; ++i) {
            if (o->stop_sequences[i] != nullptr) {
                c->stop_storage.emplace_back(o->stop_sequences[i]);
            }
        }
        if (!c->stop_storage.empty()) {
            c->stop_ptrs.reserve(c->stop_storage.size());
            for (const auto& s : c->stop_storage) {
                c->stop_ptrs.push_back(s.c_str());
            }
            cfg->stop_strings = c->stop_ptrs.data();
            cfg->n_stop_strings = static_cast<int>(c->stop_ptrs.size());
        }
    } else if (o->stop_sequences != nullptr && o->num_stop_sequences > 0) {
        cfg->stop_strings = o->stop_sequences;
        cfg->n_stop_strings = static_cast<int>(o->num_stop_sequences);
    }
}

// Wrap the user prompt in the model family's chat template. QHexRT bundles ship
// no chat template and the raw-decode host plans (qwen3_generate, lfm_generate,
// …) feed `qhx_inputs.text` to the tokenizer verbatim while ignoring
// `system_prompt`. Without turn markers a conversational prompt never forms —
// the model just continues the text and loops ("hi bro" → endless rambling). We
// therefore build the turn structure here, keyed on the manifest's
// `tokenizer_pre`, and fold the system prompt in (which is also the only way a
// caller-supplied system prompt actually reaches these models).
std::string build_chat_prompt(const std::string& pre, const char* user_c, const char* sys_c) {
    const std::string user = (user_c != nullptr) ? user_c : "";
    const std::string sys =
        (sys_c != nullptr && sys_c[0] != '\0') ? sys_c : "You are a helpful assistant.";

    // ChatML — Qwen2/Qwen3, DeepSeek-R1-Distill-Qwen, and LFM2 all share it.
    if (pre == "qwen2" || pre == "qwen3" || pre == "lfm") {
        return "<|im_start|>system\n" + sys + "<|im_end|>\n" + "<|im_start|>user\n" + user +
               "<|im_end|>\n" + "<|im_start|>assistant\n";
    }
    // Gemma turn format has no system role; fold the system text into the user turn.
    if (pre == "gemma") {
        const std::string u = sys.empty() ? user : (sys + "\n\n" + user);
        return "<start_of_turn>user\n" + u + "<end_of_turn>\n<start_of_turn>model\n";
    }
    // Unknown family ("default", etc.): pass the prompt through unchanged so we
    // never regress a model whose chat template we have not validated.
    return user;
}

void fill_inputs(qhx_inputs* in, Session* c, const char* prompt, const rac_llm_options_t* o) {
    *in = qhx_inputs{};
    const char* sys = (o != nullptr) ? o->system_prompt : nullptr;
    if (c != nullptr && !c->tokenizer_pre.empty()) {
        c->prompt_scratch = build_chat_prompt(c->tokenizer_pre, prompt, sys);
        in->text = c->prompt_scratch.c_str();
        // System prompt is folded into the templated text above; do not also
        // pass it as a separate (runtime-ignored) turn.
    } else {
        in->text = prompt;
        if (sys != nullptr && sys[0] != '\0') {
            in->system_prompt = sys;
        }
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
        fill_inputs(&in, c, prompt, options);
        qhx_gen_cfg cfg;
        fill_cfg(&cfg, c, options);
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
        fill_inputs(&in, c, prompt, options);
        qhx_gen_cfg cfg;
        fill_cfg(&cfg, c, options);
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
