/**
 * @file qhexrt_diffusion_ops.cpp
 * @brief Inpainting adapter from RAC_PRIMITIVE_DIFFUSION to the QHexRT C ABI.
 *
 * QHexRT's LaMa family accepts an encoded image plus a mask path and returns raw
 * RGB8. The SDK diffusion carrier uses encoded image/mask bytes and raw RGBA
 * output, so this adapter materializes both encoded inputs in the writable model
 * directory for the duration of one request and performs the RGB-to-RGBA copy. Image
 * decoding, resizing, mask preparation, and output conversion are host work;
 * only the manifest's QNN context graph is eligible for HNPU execution.
 */

#include "qhexrt_session.h"

#include <unistd.h>

#include <cerrno>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/features/diffusion/rac_diffusion_service.h"

namespace {

constexpr const char* kLogCat = "QHexRT";
constexpr size_t kMaxEncodedImageBytes = 128U * 1024U * 1024U;

using qhexrt_engine::Session;
using qhexrt_engine::session_close;
using qhexrt_engine::session_open;

Session* as_session(void* impl) {
    return static_cast<Session*>(impl);
}

bool is_supported_encoded_image(const uint8_t* data, size_t size) {
    static const uint8_t kPng[] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
    const bool png =
        data != nullptr && size >= sizeof(kPng) && std::memcmp(data, kPng, sizeof(kPng)) == 0;
    const bool jpeg =
        data != nullptr && size >= 3 && data[0] == 0xff && data[1] == 0xd8 && data[2] == 0xff;
    return png || jpeg;
}

class ScopedEncodedFile {
   public:
    ~ScopedEncodedFile() {
        if (!path_.empty())
            std::remove(path_.c_str());
    }

    bool write(const std::string& directory, const char* stem, const uint8_t* data, size_t size) {
        if (directory.empty() || data == nullptr || size == 0)
            return false;
        std::string pattern = directory + "/.qhexrt-" + stem + "-XXXXXX";
        std::vector<char> writable(pattern.begin(), pattern.end());
        writable.push_back('\0');
        int fd = mkstemp(writable.data());
        if (fd < 0)
            return false;
        path_ = writable.data();
        size_t written = 0;
        while (written < size) {
            const ssize_t rc = ::write(fd, data + written, size - written);
            if (rc > 0) {
                written += static_cast<size_t>(rc);
                continue;
            }
            if (rc < 0 && errno == EINTR)
                continue;
            ::close(fd);
            return false;
        }
        if (::close(fd) != 0)
            return false;
        return true;
    }

    const char* path() const { return path_.c_str(); }

   private:
    std::string path_;
};

struct CancelCtx {
    Session* session;
    uint64_t request_id;
    bool cancelled = false;
};

int should_cancel_trampoline(void* user) {
    auto* ctx = static_cast<CancelCtx*>(user);
    return ctx != nullptr && ctx->session != nullptr &&
                   ctx->session->diffusion_requests.is_cancelled(ctx->request_id)
               ? 1
               : 0;
}

int cancel_trampoline(void* user, const char*, int, int, int) {
    auto* ctx = static_cast<CancelCtx*>(user);
    if (ctx != nullptr && ctx->session != nullptr &&
        ctx->session->diffusion_requests.is_cancelled(ctx->request_id)) {
        ctx->cancelled = true;
        return 0;
    }
    return 1;
}

class DiffusionRequestScope {
   public:
    explicit DiffusionRequestScope(Session* session)
        : session_(session), id_(session != nullptr ? session->diffusion_requests.begin() : 0) {}
    ~DiffusionRequestScope() {
        if (session_ != nullptr)
            session_->diffusion_requests.finish(id_);
    }

    uint64_t id() const { return id_; }
    bool cancelled() const {
        return session_ != nullptr && session_->diffusion_requests.is_cancelled(id_);
    }

   private:
    Session* session_;
    uint64_t id_;
};

rac_result_t copy_rgba(const qhx_output& source, rac_diffusion_result_t* result) {
    if (source.image == nullptr || source.img_w <= 0 || source.img_h <= 0 ||
        (source.img_c != 1 && source.img_c != 3 && source.img_c != 4)) {
        return RAC_ERROR_GENERATION_FAILED;
    }
    const size_t pixels = static_cast<size_t>(source.img_w) * static_cast<size_t>(source.img_h);
    if (pixels > SIZE_MAX / 4)
        return RAC_ERROR_OUT_OF_MEMORY;
    const size_t bytes = pixels * 4;
    auto* rgba = static_cast<uint8_t*>(std::malloc(bytes));
    if (rgba == nullptr)
        return RAC_ERROR_OUT_OF_MEMORY;
    for (size_t i = 0; i < pixels; ++i) {
        if (source.img_c == 1) {
            rgba[i * 4] = source.image[i];
            rgba[i * 4 + 1] = source.image[i];
            rgba[i * 4 + 2] = source.image[i];
        } else {
            rgba[i * 4] = source.image[i * source.img_c];
            rgba[i * 4 + 1] = source.image[i * source.img_c + 1];
            rgba[i * 4 + 2] = source.image[i * source.img_c + 2];
        }
        rgba[i * 4 + 3] = source.img_c == 4 ? source.image[i * 4 + 3] : 255;
    }
    result->image_data = rgba;
    result->image_size = bytes;
    result->width = source.img_w;
    result->height = source.img_h;
    return RAC_SUCCESS;
}

rac_result_t qhexrt_diffusion_create(const char* model_id, const char*, void** out_impl) {
    if (out_impl == nullptr)
        return RAC_ERROR_NULL_POINTER;
    *out_impl = nullptr;
    if (model_id == nullptr || model_id[0] == '\0')
        return RAC_ERROR_INVALID_ARGUMENT;
    Session* session = session_open(model_id);
    if (session == nullptr)
        return RAC_ERROR_BACKEND_INIT_FAILED;
    *out_impl = session;
    return RAC_SUCCESS;
}

rac_result_t qhexrt_diffusion_initialize(void*, const char*, const rac_diffusion_config_t*) {
    return RAC_SUCCESS;
}

rac_result_t qhexrt_diffusion_generate(void* impl, const rac_diffusion_options_t* options,
                                       rac_diffusion_result_t* out_result) {
    auto* session = as_session(impl);
    if (session == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    if (options == nullptr || out_result == nullptr)
        return RAC_ERROR_NULL_POINTER;
    // QHexRT output aliases session-owned buffers, so hold the operation lock
    // through validation, generation, and the complete RGB-to-RGBA copy.
    std::lock_guard<std::mutex> operation_lock(session->operation_mutex);
    if (session->sess == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    DiffusionRequestScope request(session);
    *out_result = {};
    if (options->mode != RAC_DIFFUSION_MODE_INPAINTING)
        return RAC_ERROR_NOT_SUPPORTED;
    if ((options->width > 0 && options->width != 512) ||
        (options->height > 0 && options->height != 512)) {
        return RAC_ERROR_NOT_SUPPORTED;
    }
    if (options->input_image_size > kMaxEncodedImageBytes ||
        options->mask_size > kMaxEncodedImageBytes) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (!is_supported_encoded_image(options->input_image_data, options->input_image_size) ||
        !is_supported_encoded_image(options->mask_data, options->mask_size)) {
        RAC_LOG_ERROR(kLogCat, "QHexRT inpaint requires encoded PNG/JPEG image and mask bytes");
        return RAC_ERROR_NOT_SUPPORTED;
    }

    ScopedEncodedFile input_file;
    ScopedEncodedFile mask_file;
    if (!input_file.write(session->scratch_dir, "input", options->input_image_data,
                          options->input_image_size) ||
        !mask_file.write(session->scratch_dir, "mask", options->mask_data, options->mask_size)) {
        RAC_LOG_ERROR(kLogCat, "Could not materialize the QHexRT inpaint inputs under %s",
                      session->scratch_dir.c_str());
        return RAC_ERROR_FILE_WRITE_FAILED;
    }
    if (request.cancelled())
        return RAC_ERROR_CANCELLED;

    qhx_session_reset(session->sess);
    if (request.cancelled())
        return RAC_ERROR_CANCELLED;

    qhx_inputs inputs{};
    inputs.text = options->prompt;
    // LaMa's QHexRT host-op consumes image_path/mask_path. The C ABI's in-memory
    // image carrier is used by VLM preprocessing and does not populate that path.
    inputs.image_path = input_file.path();
    inputs.mask_path = mask_file.path();
    qhx_gen_cfg cfg;
    qhx_gen_cfg_default(&cfg);

    CancelCtx cancel_ctx{session, request.id()};
    qhx_generate_options generate_options;
    qhx_generate_options_default(&generate_options);
    generate_options.should_cancel = should_cancel_trampoline;
    generate_options.should_cancel_user = &cancel_ctx;
    qhx_output output{};
    const qhx_status status = qhx_generate_ex(session->sess, &inputs, &cfg, &generate_options,
                                              cancel_trampoline, &cancel_ctx, &output);
    if (cancel_ctx.cancelled || request.cancelled()) {
        RAC_LOG_INFO(kLogCat, "Diffusion request %llu cancelled during generation",
                     static_cast<unsigned long long>(request.id()));
        return RAC_ERROR_CANCELLED;
    }
    if (status != 0) {
        RAC_LOG_ERROR(kLogCat, "qhx_generate_ex(inpaint) failed: %s", qhx_status_str(status));
        return RAC_ERROR_GENERATION_FAILED;
    }
    rac_result_t rc = copy_rgba(output, out_result);
    if (rc != RAC_SUCCESS)
        return rc;
    out_result->seed_used = options->seed;
    out_result->generation_time_ms =
        static_cast<int64_t>(std::llround(output.prefill_ms + output.decode_ms));
    out_result->safety_flagged = RAC_FALSE;
    out_result->error_code = RAC_SUCCESS;
    return RAC_SUCCESS;
}

rac_result_t
qhexrt_diffusion_generate_with_progress(void* impl, const rac_diffusion_options_t* options,
                                        rac_diffusion_progress_callback_fn progress_callback,
                                        void* user_data, rac_diffusion_result_t* out_result) {
    if (progress_callback != nullptr) {
        const rac_diffusion_progress_t started = {
            .progress = 0.0f,
            .current_step = 0,
            .total_steps = 1,
            .stage = "Inpainting",
        };
        if (progress_callback(&started, user_data) != RAC_TRUE)
            return RAC_ERROR_CANCELLED;
    }
    const rac_result_t rc = qhexrt_diffusion_generate(impl, options, out_result);
    if (rc == RAC_SUCCESS && progress_callback != nullptr) {
        const rac_diffusion_progress_t completed = {
            .progress = 1.0f,
            .current_step = 1,
            .total_steps = 1,
            .stage = "Complete",
        };
        (void)progress_callback(&completed, user_data);
    }
    return rc;
}

rac_result_t qhexrt_diffusion_get_info(void* impl, rac_diffusion_info_t* out_info) {
    auto* session = as_session(impl);
    if (session == nullptr || out_info == nullptr)
        return RAC_ERROR_NULL_POINTER;
    std::lock_guard<std::mutex> operation_lock(session->operation_mutex);
    *out_info = {};
    out_info->is_ready = session->sess != nullptr ? RAC_TRUE : RAC_FALSE;
    out_info->current_model = session->model_ref.c_str();
    out_info->supports_inpainting = RAC_TRUE;
    out_info->max_width = 512;
    out_info->max_height = 512;
    return RAC_SUCCESS;
}

uint32_t qhexrt_diffusion_get_capabilities(void*) {
    return RAC_DIFFUSION_CAP_INPAINTING;
}

rac_result_t qhexrt_diffusion_cancel(void* impl) {
    auto* session = as_session(impl);
    if (session == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    const uint64_t request_id =
        session->diffusion_requests.active_id.load(std::memory_order_acquire);
    session->diffusion_requests.cancel_active();
    RAC_LOG_INFO(kLogCat, "Diffusion cancel routed to request %llu",
                 static_cast<unsigned long long>(request_id));
    return RAC_SUCCESS;
}

rac_result_t qhexrt_diffusion_cleanup(void* impl) {
    auto* session = as_session(impl);
    if (session == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    std::lock_guard<std::mutex> operation_lock(session->operation_mutex);
    if (session->sess == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    qhx_session_reset(session->sess);
    return RAC_SUCCESS;
}

void qhexrt_diffusion_destroy(void* impl) {
    session_close(as_session(impl));
}

}  // namespace

extern "C" const rac_diffusion_service_ops_t g_qhexrt_diffusion_ops = {
    .initialize = qhexrt_diffusion_initialize,
    .generate = qhexrt_diffusion_generate,
    .generate_with_progress = qhexrt_diffusion_generate_with_progress,
    .get_info = qhexrt_diffusion_get_info,
    .get_capabilities = qhexrt_diffusion_get_capabilities,
    .cancel = qhexrt_diffusion_cancel,
    .cleanup = qhexrt_diffusion_cleanup,
    .destroy = qhexrt_diffusion_destroy,
    .create = qhexrt_diffusion_create,
};
