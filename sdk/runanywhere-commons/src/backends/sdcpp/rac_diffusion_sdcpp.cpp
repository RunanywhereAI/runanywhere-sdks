/**
 * @file rac_diffusion_sdcpp.cpp
 * @brief RAC C API wrapper for the sd.cpp diffusion backend.
 *
 * Wraps the C++ SdcppDiffusionBackend class with extern "C" functions
 * that match the rac_diffusion_sdcpp.h API.
 */

#include "rac/backends/rac_diffusion_sdcpp.h"

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "sdcpp_diffusion_backend.h"

static const char* LOG_CAT = "Backend.SDCPP.API";

using runanywhere::SdcppDiffusionBackend;

extern "C" {

rac_handle_t rac_diffusion_sdcpp_create(void) {
    auto* backend = new (std::nothrow) SdcppDiffusionBackend();
    if (!backend) {
        RAC_LOG_ERROR(LOG_CAT, "Failed to allocate sd.cpp backend");
        return nullptr;
    }
    return static_cast<rac_handle_t>(backend);
}

void rac_diffusion_sdcpp_destroy(rac_handle_t handle) {
    if (!handle) return;
    auto* backend = static_cast<SdcppDiffusionBackend*>(handle);
    delete backend;
}

rac_result_t rac_diffusion_sdcpp_load_model(rac_handle_t handle, const char* model_path,
                                             const rac_diffusion_config_t* config) {
    if (!handle) return RAC_ERROR_NULL_POINTER;
    auto* backend = static_cast<SdcppDiffusionBackend*>(handle);
    return backend->load_model(model_path, config);
}

rac_result_t rac_diffusion_sdcpp_unload(rac_handle_t handle) {
    if (!handle) return RAC_ERROR_NULL_POINTER;
    auto* backend = static_cast<SdcppDiffusionBackend*>(handle);
    backend->cleanup();
    return RAC_SUCCESS;
}

rac_result_t rac_diffusion_sdcpp_generate(rac_handle_t handle,
                                           const rac_diffusion_options_t* options,
                                           rac_diffusion_result_t* out_result) {
    if (!handle) return RAC_ERROR_NULL_POINTER;
    auto* backend = static_cast<SdcppDiffusionBackend*>(handle);
    return backend->generate(options, out_result);
}

rac_result_t rac_diffusion_sdcpp_generate_with_progress(
    rac_handle_t handle, const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_callback, void* user_data,
    rac_diffusion_result_t* out_result) {
    if (!handle) return RAC_ERROR_NULL_POINTER;
    auto* backend = static_cast<SdcppDiffusionBackend*>(handle);
    return backend->generate_with_progress(options, progress_callback, user_data, out_result);
}

rac_result_t rac_diffusion_sdcpp_cancel(rac_handle_t handle) {
    if (!handle) return RAC_ERROR_NULL_POINTER;
    auto* backend = static_cast<SdcppDiffusionBackend*>(handle);
    backend->cancel();
    return RAC_SUCCESS;
}

rac_result_t rac_diffusion_sdcpp_get_info(rac_handle_t handle,
                                            rac_diffusion_info_t* out_info) {
    if (!handle || !out_info) return RAC_ERROR_NULL_POINTER;

    auto* backend = static_cast<SdcppDiffusionBackend*>(handle);
    *out_info = {};
    out_info->is_ready = backend->is_ready() ? RAC_TRUE : RAC_FALSE;
    out_info->model_variant = backend->model_variant();
    out_info->supports_text_to_image = RAC_TRUE;
    out_info->supports_image_to_image = RAC_TRUE;
    out_info->supports_inpainting = RAC_TRUE;
    out_info->safety_checker_enabled = RAC_FALSE;  // sd.cpp has no safety checker
    out_info->max_width = 2048;
    out_info->max_height = 2048;

    return RAC_SUCCESS;
}

uint32_t rac_diffusion_sdcpp_get_capabilities(rac_handle_t handle) {
    if (!handle) return 0;
    auto* backend = static_cast<SdcppDiffusionBackend*>(handle);
    return backend->capabilities();
}

}  // extern "C"
