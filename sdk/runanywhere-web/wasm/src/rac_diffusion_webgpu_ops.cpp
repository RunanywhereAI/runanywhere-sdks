/**
 * @file rac_diffusion_webgpu_ops.cpp
 * @brief Browser diffusion engine plugin for WASM builds.
 *
 * Mirrors CoreML/QHexRT: commons owns orchestration; this file only supplies
 * the engine vtable. WebGPU Stable Diffusion kernels are not linked yet —
 * create/initialize succeed for lifecycle wiring; generate returns
 * FEATURE_NOT_AVAILABLE until the kernel artifact lands.
 */

#include "rac/features/diffusion/rac_diffusion_service.h"

#include <cstdlib>
#include <cstring>
#include <new>

#if defined(__EMSCRIPTEN__)

namespace {

struct WebGpuDiffusionImpl {
    char* model_path = nullptr;
};

rac_result_t webgpu_diffusion_create(const char* model_id, const char*, void** out_impl) {
    if (!out_impl)
        return RAC_ERROR_NULL_POINTER;
    auto* impl = new (std::nothrow) WebGpuDiffusionImpl();
    if (!impl)
        return RAC_ERROR_OUT_OF_MEMORY;
    if (model_id && model_id[0] != '\0') {
        impl->model_path = strdup(model_id);
        if (!impl->model_path) {
            delete impl;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }
    *out_impl = impl;
    return RAC_SUCCESS;
}

rac_result_t webgpu_diffusion_initialize(void*, const char*, const rac_diffusion_config_t*) {
    return RAC_SUCCESS;
}

rac_result_t webgpu_diffusion_generate(void*, const rac_diffusion_options_t*,
                                       rac_diffusion_result_t*) {
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

rac_result_t webgpu_diffusion_generate_with_progress(void* impl,
                                                     const rac_diffusion_options_t* options,
                                                     rac_diffusion_progress_callback_fn, void*,
                                                     rac_diffusion_result_t* out_result) {
    return webgpu_diffusion_generate(impl, options, out_result);
}

rac_result_t webgpu_diffusion_get_info(void* impl, rac_diffusion_info_t* out_info) {
    if (!impl || !out_info)
        return RAC_ERROR_NULL_POINTER;
    auto* ctx = static_cast<WebGpuDiffusionImpl*>(impl);
    *out_info = {};
    out_info->is_ready = RAC_TRUE;
    out_info->current_model = ctx->model_path;
    out_info->supports_text_to_image = RAC_TRUE;
    out_info->supports_image_to_image = RAC_TRUE;
    out_info->supports_inpainting = RAC_TRUE;
    out_info->max_width = 512;
    out_info->max_height = 512;
    return RAC_SUCCESS;
}

uint32_t webgpu_diffusion_get_capabilities(void*) {
    return RAC_DIFFUSION_CAP_TEXT_TO_IMAGE | RAC_DIFFUSION_CAP_IMAGE_TO_IMAGE |
           RAC_DIFFUSION_CAP_INPAINTING;
}

rac_result_t webgpu_diffusion_cancel(void*) {
    return RAC_SUCCESS;
}

rac_result_t webgpu_diffusion_cleanup(void* impl) {
    if (!impl)
        return RAC_ERROR_NULL_POINTER;
    auto* ctx = static_cast<WebGpuDiffusionImpl*>(impl);
    free(ctx->model_path);
    ctx->model_path = nullptr;
    return RAC_SUCCESS;
}

void webgpu_diffusion_destroy(void* impl) {
    if (!impl)
        return;
    auto* ctx = static_cast<WebGpuDiffusionImpl*>(impl);
    free(ctx->model_path);
    delete ctx;
}

}  // namespace

extern "C" const rac_diffusion_service_ops_t g_webgpu_diffusion_ops = {
    .initialize = webgpu_diffusion_initialize,
    .generate = webgpu_diffusion_generate,
    .generate_with_progress = webgpu_diffusion_generate_with_progress,
    .get_info = webgpu_diffusion_get_info,
    .get_capabilities = webgpu_diffusion_get_capabilities,
    .cancel = webgpu_diffusion_cancel,
    .cleanup = webgpu_diffusion_cleanup,
    .destroy = webgpu_diffusion_destroy,
    .create = webgpu_diffusion_create,
};

#endif  // __EMSCRIPTEN__
