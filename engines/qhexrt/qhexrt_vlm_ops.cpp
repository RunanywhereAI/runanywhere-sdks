/**
 * @file qhexrt_vlm_ops.cpp
 * @brief VLM (RAC_PRIMITIVE_VLM) vtable over the QHexRT C ABI.
 *
 * Compiled ONLY in routable builds. Maps `rac_vlm_service_ops_t` onto
 * `qhx_generate` with an image input via the shared session helper. Only the
 * FILE_PATH image form is forwarded; QHexRT consumes encoded images by path and
 * its live raw-pixel/base64 preprocessing is deferred, so RGB_PIXELS / BASE64
 * inputs return RAC_ERROR_NOT_SUPPORTED rather than silently mis-decoding.
 */

#include <cstdint>
#include <string>

#include "qhexrt_session.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/vlm/rac_vlm_service.h"

namespace {

const char* LOG_CAT = "QHexRT";

using qhexrt_engine::Session;
using qhexrt_engine::session_close;
using qhexrt_engine::session_open;

Session* as_session(void* impl) { return static_cast<Session*>(impl); }

void fill_cfg(qhx_gen_cfg* cfg, const rac_vlm_options_t* o) {
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
    if (o->seed > 0) cfg->seed = static_cast<uint64_t>(o->seed);
    if (o->stop_sequences != nullptr && o->num_stop_sequences > 0) {
        cfg->stop_strings = o->stop_sequences;
        cfg->n_stop_strings = static_cast<int>(o->num_stop_sequences);
    }
}

// Returns false (caller -> NOT_SUPPORTED) for image forms QHexRT cannot consume.
bool fill_inputs(qhx_inputs* in, const rac_vlm_image_t* image, const char* prompt,
                 const rac_vlm_options_t* o) {
    *in = qhx_inputs{};
    in->text = prompt;
    if (o != nullptr && o->system_prompt != nullptr && o->system_prompt[0] != '\0') {
        in->system_prompt = o->system_prompt;
    }
    if (image == nullptr) {
        return true;  // text-only turn against a VLM is allowed
    }
    if (image->file_path != nullptr && image->file_path[0] != '\0') {
        in->image_path = image->file_path;
        return true;
    }
    return false;  // RGB_PIXELS / BASE64 not supported by the QHexRT C ABI
}

void fill_result(rac_vlm_result_t* out, const qhx_output& o) {
    out->text = rac_strdup(o.text != nullptr ? o.text : "");
    out->prompt_tokens = o.n_prompt;
    out->image_tokens = 0;
    out->completion_tokens = o.n_generated;
    out->total_tokens = o.n_prompt + o.n_generated;
    out->time_to_first_token_ms = static_cast<int64_t>(o.prefill_ms);
    out->image_encode_time_ms = 0;
    out->total_time_ms = static_cast<int64_t>(o.prefill_ms + o.decode_ms);
    out->tokens_per_second =
        o.decode_ms > 0.0 ? static_cast<float>(o.n_generated * 1000.0 / o.decode_ms) : 0.0f;
}

struct StreamCtx {
    rac_vlm_stream_callback_fn cb;
    void* user;
    Session* session;
    bool cancelled = false;
    std::string buf;
};

int stream_trampoline(void* user, const char* utf8, int len, int /*token_id*/, int is_final) {
    auto* c = static_cast<StreamCtx*>(user);
    if (c == nullptr || is_final != 0 || utf8 == nullptr) {
        return 1;
    }
    if (c->session != nullptr && c->session->cancel.load(std::memory_order_relaxed)) {
        c->cancelled = true;
        return 0;
    }
    if (c->cb == nullptr) {
        return 1;
    }
    c->buf.assign(utf8, static_cast<size_t>(len < 0 ? 0 : len));
    if (c->cb(c->buf.c_str(), c->user) == RAC_FALSE) {
        c->cancelled = true;
        return 0;
    }
    return 1;
}

struct StopCtx {
    Session* session;
};

int stop_trampoline(void* user, const char* /*utf8*/, int /*len*/, int /*token_id*/,
                    int /*is_final*/) {
    auto* c = static_cast<StopCtx*>(user);
    if (c != nullptr && c->session != nullptr &&
        c->session->cancel.load(std::memory_order_relaxed)) {
        return 0;
    }
    return 1;
}

// ───────────────────────────────── vtable ops ───────────────────────────────

rac_result_t qhexrt_vlm_create(const char* model_id, const char* /*config_json*/, void** out_impl) {
    if (out_impl == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_impl = nullptr;
    if (model_id == nullptr || model_id[0] == '\0') {
        return RAC_ERROR_NULL_POINTER;
    }
    RAC_LOG_INFO(LOG_CAT, "qhexrt_vlm_create: manifest=%s", model_id);
    Session* s = session_open(model_id);
    if (s == nullptr) {
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }
    *out_impl = s;
    return RAC_SUCCESS;
}

rac_result_t qhexrt_vlm_initialize(void* /*impl*/, const char* /*model_path*/,
                                   const char* /*mmproj_path*/) {
    return RAC_SUCCESS;  // model loaded in create()
}

rac_result_t qhexrt_vlm_process(void* impl, const rac_vlm_image_t* image, const char* prompt,
                                const rac_vlm_options_t* options, rac_vlm_result_t* out_result) {
    auto* c = as_session(impl);
    if (c == nullptr || c->sess == nullptr || out_result == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    try {
        c->cancel.store(false, std::memory_order_relaxed);
        qhx_inputs in;
        if (!fill_inputs(&in, image, prompt, options)) {
            return RAC_ERROR_NOT_SUPPORTED;
        }
        qhx_gen_cfg cfg;
        fill_cfg(&cfg, options);
        StopCtx stop_ctx{c};
        qhx_output out{};
        qhx_status st = qhx_generate(c->sess, &in, &cfg, stop_trampoline, &stop_ctx, &out);
        if (st != 0) {
            if (c->cancel.load(std::memory_order_relaxed)) {
                return RAC_ERROR_CANCELLED;
            }
            RAC_LOG_ERROR(LOG_CAT, "qhx_generate(vlm) failed: %s", qhx_status_str(st));
            return RAC_ERROR_GENERATION_FAILED;
        }
        fill_result(out_result, out);
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t qhexrt_vlm_process_stream(void* impl, const rac_vlm_image_t* image, const char* prompt,
                                       const rac_vlm_options_t* options,
                                       rac_vlm_stream_callback_fn callback, void* user_data) {
    auto* c = as_session(impl);
    if (c == nullptr || c->sess == nullptr) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    try {
        c->cancel.store(false, std::memory_order_relaxed);
        qhx_inputs in;
        if (!fill_inputs(&in, image, prompt, options)) {
            return RAC_ERROR_NOT_SUPPORTED;
        }
        qhx_gen_cfg cfg;
        fill_cfg(&cfg, options);
        StreamCtx ctx{callback, user_data, c, false, std::string()};
        qhx_output out{};
        qhx_status st = qhx_generate(c->sess, &in, &cfg, stream_trampoline, &ctx, &out);
        if (st != 0) {
            if (ctx.cancelled || c->cancel.load(std::memory_order_relaxed)) {
                return RAC_ERROR_CANCELLED;
            }
            RAC_LOG_ERROR(LOG_CAT, "qhx_generate(vlm stream) failed: %s", qhx_status_str(st));
            return RAC_ERROR_GENERATION_FAILED;
        }
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t qhexrt_vlm_get_info(void* impl, rac_vlm_info_t* out_info) {
    if (out_info == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* c = as_session(impl);
    out_info->is_ready = (c != nullptr && c->sess != nullptr) ? RAC_TRUE : RAC_FALSE;
    out_info->current_model = nullptr;
    out_info->context_length = 0;
    out_info->supports_streaming = RAC_TRUE;
    out_info->supports_multiple_images = RAC_FALSE;
    out_info->vision_encoder_type = nullptr;
    return RAC_SUCCESS;
}

rac_result_t qhexrt_vlm_cancel(void* impl) {
    auto* c = as_session(impl);
    if (c != nullptr) {
        c->cancel.store(true, std::memory_order_relaxed);
    }
    return RAC_SUCCESS;
}

rac_result_t qhexrt_vlm_cleanup(void* impl) {
    auto* c = as_session(impl);
    if (c != nullptr && c->sess != nullptr) {
        qhx_session_reset(c->sess);
    }
    return RAC_SUCCESS;
}

void qhexrt_vlm_destroy(void* impl) { session_close(as_session(impl)); }

}  // namespace

extern "C" const rac_vlm_service_ops_t g_qhexrt_vlm_ops = {
    /* .initialize     = */ qhexrt_vlm_initialize,
    /* .process        = */ qhexrt_vlm_process,
    /* .process_stream = */ qhexrt_vlm_process_stream,
    /* .get_info       = */ qhexrt_vlm_get_info,
    /* .cancel         = */ qhexrt_vlm_cancel,
    /* .cleanup        = */ qhexrt_vlm_cleanup,
    /* .destroy        = */ qhexrt_vlm_destroy,
    /* .create         = */ qhexrt_vlm_create,
};
