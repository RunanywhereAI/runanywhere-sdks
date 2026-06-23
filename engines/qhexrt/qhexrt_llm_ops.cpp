/**
 * @file qhexrt_llm_ops.cpp
 * @brief LLM (RAC_PRIMITIVE_GENERATE_TEXT) vtable over the QHexRT C ABI.
 *
 * Compiled ONLY in linked builds (RAC_QHEXRT_ENGINE_AVAILABLE=1); the public
 * stub build never sees this TU (see CMakeLists.txt). It adapts the generic
 * `rac_llm_service_ops_t` contract onto QHexRT's `qhx_*` C ABI
 * (qhexrt/qhexrt_c.h, supplied by the prebuilt archive under QHEXRT_ROOT).
 *
 * Ownership / lifetime:
 *   - One process-wide qhx_runtime, refcounted across impls (QHexRT documents
 *     the runtime as one-per-process; burst clock pinned on create).
 *   - One qhx_model + qhx_session per impl. Sessions are NOT thread-safe, so a
 *     single impl must not be driven concurrently — the SDK owns one impl per
 *     logical model handle.
 *
 * No C++ exception may cross back into the registry / JNI: every op body wraps
 * its allocating work and coerces failures to rac_result_t, matching the
 * noexcept contract the plugin registry relies on.
 */

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>

#include "qhexrt/qhexrt_c.h"  // private ABI header, from QHEXRT_ROOT/include

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_service.h"

namespace {

const char* LOG_CAT = "QHexRT";

// ─────────────────────────── process-wide runtime ───────────────────────────
std::mutex g_rt_mutex;
qhx_runtime* g_rt = nullptr;
std::size_t g_rt_refs = 0;

qhx_runtime* runtime_acquire() {
    std::lock_guard<std::mutex> lock(g_rt_mutex);
    if (g_rt == nullptr) {
        g_rt = qhx_runtime_create(nullptr, nullptr);  // default libQnnHtp.so / libQnnSystem.so
        if (g_rt == nullptr) {
            RAC_LOG_ERROR(LOG_CAT, "qhx_runtime_create failed (QNN libs unavailable?)");
            return nullptr;
        }
        char arch[32] = {0};
        qhx_runtime_device(g_rt, arch, sizeof(arch), nullptr, nullptr);
        RAC_LOG_INFO(LOG_CAT, "QHexRT runtime up (arch=%s, %s)", arch, qhx_version());
    }
    ++g_rt_refs;
    return g_rt;
}

void runtime_release() {
    std::lock_guard<std::mutex> lock(g_rt_mutex);
    if (g_rt_refs == 0) {
        return;
    }
    if (--g_rt_refs == 0) {
        qhx_runtime_free(g_rt);
        g_rt = nullptr;
    }
}

// ─────────────────────────────── per-impl state ─────────────────────────────
struct QhxImpl {
    qhx_model* model = nullptr;
    qhx_session* sess = nullptr;
    std::atomic<bool> cancel{false};
};

QhxImpl* as_impl(void* impl) { return static_cast<QhxImpl*>(impl); }

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
}

void fill_inputs(qhx_inputs* in, const char* prompt, const rac_llm_options_t* o) {
    *in = qhx_inputs{};
    in->text = prompt;
    if (o != nullptr && o->system_prompt != nullptr && o->system_prompt[0] != '\0') {
        in->system_prompt = o->system_prompt;
    }
}

// Bridge QHexRT's chunk callback (utf8/len, return 0 to cancel) onto the rac
// stream callback (NUL-terminated token, RAC_TRUE to continue).
struct StreamCtx {
    rac_llm_stream_callback_fn cb;
    void* user;
    QhxImpl* impl;
    std::string buf;  // reused per chunk to NUL-terminate
};

int stream_trampoline(void* user, const char* utf8, int len, int /*token_id*/, int is_final) {
    auto* c = static_cast<StreamCtx*>(user);
    if (c == nullptr || is_final != 0 || utf8 == nullptr) {
        return 1;  // nothing to forward on the terminal call
    }
    if (c->impl != nullptr && c->impl->cancel.load(std::memory_order_relaxed)) {
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
rac_result_t qhexrt_create(const char* model_id, const char* /*config_json*/, void** out_impl) {
    if (out_impl == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    if (model_id == nullptr || model_id[0] == '\0') {
        return RAC_ERROR_NULL_POINTER;
    }
    RAC_LOG_INFO(LOG_CAT, "qhexrt_create: manifest=%s", model_id);

    qhx_runtime* rt = runtime_acquire();
    if (rt == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }

    QhxImpl* impl = nullptr;
    try {
        impl = new QhxImpl();
    } catch (...) {
        runtime_release();
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    impl->model = qhx_model_load(rt, model_id, nullptr);
    if (impl->model == nullptr) {
        RAC_LOG_ERROR(LOG_CAT, "qhx_model_load failed: %s", model_id);
        delete impl;
        runtime_release();
        return RAC_ERROR_GENERATION_FAILED;
    }
    impl->sess = qhx_session_create(impl->model);
    if (impl->sess == nullptr) {
        qhx_model_free(impl->model);
        delete impl;
        runtime_release();
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    *out_impl = impl;
    return RAC_SUCCESS;
}

// Model is already loaded in create(); initialize is a no-op for symmetry.
rac_result_t qhexrt_initialize(void* /*impl*/, const char* /*model_path*/) { return RAC_SUCCESS; }

rac_result_t qhexrt_generate(void* impl, const char* prompt, const rac_llm_options_t* options,
                             rac_llm_result_t* out_result) {
    auto* c = as_impl(impl);
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

rac_result_t qhexrt_generate_stream(void* impl, const char* prompt,
                                    const rac_llm_options_t* options,
                                    rac_llm_stream_callback_fn callback, void* user_data) {
    auto* c = as_impl(impl);
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

rac_result_t qhexrt_get_info(void* impl, rac_llm_info_t* out_info) {
    if (out_info == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* c = as_impl(impl);
    out_info->is_ready = (c != nullptr && c->sess != nullptr) ? RAC_TRUE : RAC_FALSE;
    out_info->current_model = nullptr;
    out_info->context_length = 0;
    out_info->supports_streaming = RAC_TRUE;
    return RAC_SUCCESS;
}

rac_result_t qhexrt_cancel(void* impl) {
    auto* c = as_impl(impl);
    if (c != nullptr) {
        c->cancel.store(true, std::memory_order_relaxed);
    }
    return RAC_SUCCESS;
}

// Drop KV / counters; keeps the service (model + session) alive.
rac_result_t qhexrt_cleanup(void* impl) {
    auto* c = as_impl(impl);
    if (c != nullptr && c->sess != nullptr) {
        qhx_session_reset(c->sess);
    }
    return RAC_SUCCESS;
}

void qhexrt_destroy(void* impl) {
    auto* c = as_impl(impl);
    if (c == nullptr) {
        return;
    }
    if (c->sess != nullptr) {
        qhx_session_free(c->sess);
    }
    if (c->model != nullptr) {
        qhx_model_free(c->model);
    }
    delete c;
    runtime_release();
}

}  // namespace

// Consumed by rac_plugin_entry_qhexrt.cpp (external linkage; visibility limited
// to the carrier library by the plugin target's hidden-by-default visibility).
// Optional ops QHexRT does not serve (LoRA, adaptive-context) are NULL: the
// registry maps NULL to RAC_ERROR_NOT_SUPPORTED.
extern "C" const rac_llm_service_ops_t g_qhexrt_llm_ops = {
    /* .initialize            = */ qhexrt_initialize,
    /* .generate              = */ qhexrt_generate,
    /* .generate_stream       = */ qhexrt_generate_stream,
    /* .get_info              = */ qhexrt_get_info,
    /* .cancel                = */ qhexrt_cancel,
    /* .cleanup               = */ qhexrt_cleanup,
    /* .destroy               = */ qhexrt_destroy,
    /* .load_lora             = */ nullptr,
    /* .remove_lora           = */ nullptr,
    /* .clear_lora            = */ nullptr,
    /* .get_lora_info         = */ nullptr,
    /* .inject_system_prompt  = */ nullptr,
    /* .append_context        = */ nullptr,
    /* .generate_from_context = */ nullptr,
    /* .clear_context         = */ nullptr,
    /* .create                = */ qhexrt_create,
};
