/**
 * @file rac_diffusion_onnx.cpp
 * @brief RAC API wrapper for ONNX Diffusion Backend
 *
 * Bridges the C API to the internal C++ ONNXDiffusion implementation.
 */

#include "rac/backends/rac_diffusion_onnx.h"

#include <cstring>
#include <filesystem>
#include <memory>

#include "onnx_backend.h"
#include "onnx_diffusion.h"
#include "rac/core/rac_logger.h"
#include "rac/features/diffusion/rac_diffusion_tokenizer.h"

namespace fs = std::filesystem;

// =============================================================================
// INTERNAL HANDLE STRUCTURE
// =============================================================================

struct rac_diffusion_onnx_handle_impl {
    std::unique_ptr<runanywhere::ONNXBackendNew> backend;
    std::unique_ptr<runanywhere::diffusion::ONNXDiffusion> diffusion;
    std::string model_path;
};

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

static runanywhere::diffusion::ONNXExecutionProvider 
convert_ep(rac_diffusion_onnx_ep_t ep) {
    switch (ep) {
        case RAC_DIFFUSION_ONNX_EP_CPU:
            return runanywhere::diffusion::ONNXExecutionProvider::CPU;
        case RAC_DIFFUSION_ONNX_EP_COREML:
            return runanywhere::diffusion::ONNXExecutionProvider::COREML;
        case RAC_DIFFUSION_ONNX_EP_NNAPI:
            return runanywhere::diffusion::ONNXExecutionProvider::NNAPI;
        case RAC_DIFFUSION_ONNX_EP_CUDA:
            return runanywhere::diffusion::ONNXExecutionProvider::CUDA;
        case RAC_DIFFUSION_ONNX_EP_DIRECTML:
            return runanywhere::diffusion::ONNXExecutionProvider::DIRECTML;
        default:
            return runanywhere::diffusion::ONNXExecutionProvider::AUTO;
    }
}

static runanywhere::diffusion::DiffusionModelVariant 
convert_variant(rac_diffusion_model_variant_t variant) {
    switch (variant) {
        case RAC_DIFFUSION_MODEL_SD_1_5:
            return runanywhere::diffusion::DiffusionModelVariant::SD_1_5;
        case RAC_DIFFUSION_MODEL_SD_2_1:
            return runanywhere::diffusion::DiffusionModelVariant::SD_2_1;
        case RAC_DIFFUSION_MODEL_SDXL:
            return runanywhere::diffusion::DiffusionModelVariant::SDXL;
        case RAC_DIFFUSION_MODEL_SDXL_TURBO:
            return runanywhere::diffusion::DiffusionModelVariant::SDXL_TURBO;
        case RAC_DIFFUSION_MODEL_SDXS:
            return runanywhere::diffusion::DiffusionModelVariant::SDXS;
        case RAC_DIFFUSION_MODEL_LCM:
            return runanywhere::diffusion::DiffusionModelVariant::LCM;
        default:
            return runanywhere::diffusion::DiffusionModelVariant::SD_1_5;
    }
}

static runanywhere::diffusion::SchedulerType 
convert_scheduler(rac_diffusion_scheduler_t scheduler) {
    switch (scheduler) {
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M_KARRAS:
            return runanywhere::diffusion::SchedulerType::DPM_PP_2M_KARRAS;
        case RAC_DIFFUSION_SCHEDULER_DPM_PP_2M:
            return runanywhere::diffusion::SchedulerType::DPM_PP_2M;
        case RAC_DIFFUSION_SCHEDULER_DDIM:
            return runanywhere::diffusion::SchedulerType::DDIM;
        case RAC_DIFFUSION_SCHEDULER_EULER:
            return runanywhere::diffusion::SchedulerType::EULER;
        case RAC_DIFFUSION_SCHEDULER_EULER_ANCESTRAL:
            return runanywhere::diffusion::SchedulerType::EULER_ANCESTRAL;
        case RAC_DIFFUSION_SCHEDULER_PNDM:
            return runanywhere::diffusion::SchedulerType::PNDM;
        case RAC_DIFFUSION_SCHEDULER_LMS:
            return runanywhere::diffusion::SchedulerType::LMS;
        default:
            return runanywhere::diffusion::SchedulerType::DPM_PP_2M_KARRAS;
    }
}

// =============================================================================
// API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_diffusion_onnx_create(
    const char* model_path,
    const rac_diffusion_onnx_config_t* config,
    rac_handle_t* out_handle) {
    
    if (!model_path || !out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    
    *out_handle = nullptr;
    
    try {
        auto handle = std::make_unique<rac_diffusion_onnx_handle_impl>();
        handle->model_path = model_path;
        
        // Initialize ONNX Runtime backend
        handle->backend = std::make_unique<runanywhere::ONNXBackendNew>();
        if (!handle->backend->initialize()) {
            RAC_LOG_ERROR("rac_diffusion_onnx", "Failed to initialize ONNX backend");
            return RAC_ERROR_INITIALIZATION_FAILED;
        }
        
        // Create diffusion instance
        handle->diffusion = std::make_unique<runanywhere::diffusion::ONNXDiffusion>(
            handle->backend->get_ort_api(),
            handle->backend->get_ort_env()
        );
        
        // Build configuration
        runanywhere::diffusion::ONNXDiffusionConfig diff_config;
        if (config) {
            diff_config.model_variant = convert_variant(config->model_variant);
            diff_config.scheduler_type = convert_scheduler(config->scheduler);
            diff_config.execution_provider = convert_ep(config->execution_provider);
            diff_config.num_threads = config->num_threads;
            diff_config.enable_memory_pattern = config->enable_memory_pattern == RAC_TRUE;
            diff_config.enable_cpu_mem_arena = config->enable_cpu_mem_arena == RAC_TRUE;
        }
        
        // Ensure tokenizer files (auto-download if missing)
        rac_diffusion_tokenizer_config_t tokenizer_config = RAC_DIFFUSION_TOKENIZER_CONFIG_DEFAULT;
        tokenizer_config.source =
            rac_diffusion_tokenizer_default_for_variant(
                config ? config->model_variant : RAC_DIFFUSION_MODEL_SD_1_5);

        rac_result_t tokenizer_result =
            rac_diffusion_tokenizer_ensure_files(model_path, &tokenizer_config);
        if (tokenizer_result != RAC_SUCCESS) {
            RAC_LOG_ERROR("rac_diffusion_onnx", "Tokenizer ensure failed: %d", tokenizer_result);
            return tokenizer_result;
        }

        // Load model
        if (!handle->diffusion->load_model(model_path, diff_config)) {
            RAC_LOG_ERROR("rac_diffusion_onnx", "Failed to load model from: %s", model_path);
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        
        *out_handle = handle.release();
        return RAC_SUCCESS;
        
    } catch (const std::exception& e) {
        RAC_LOG_ERROR("rac_diffusion_onnx", "Exception in create: %s", e.what());
        return RAC_ERROR_UNKNOWN;
    }
}

rac_result_t rac_diffusion_onnx_generate(
    rac_handle_t handle,
    const rac_diffusion_options_t* options,
    rac_diffusion_result_t* out_result) {
    
    return rac_diffusion_onnx_generate_with_progress(handle, options, nullptr, nullptr, out_result);
}

rac_result_t rac_diffusion_onnx_generate_with_progress(
    rac_handle_t handle,
    const rac_diffusion_options_t* options,
    rac_diffusion_progress_callback_fn progress_callback,
    void* user_data,
    rac_diffusion_result_t* out_result) {
    
    if (!handle || !options || !out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    
    auto* impl = static_cast<rac_diffusion_onnx_handle_impl*>(handle);
    if (!impl->diffusion || !impl->diffusion->is_ready()) {
        return RAC_ERROR_NOT_INITIALIZED;
    }
    
    try {
        // Build internal options
        runanywhere::diffusion::DiffusionOptions diff_opts;
        if (options->prompt) {
            diff_opts.prompt = options->prompt;
        }
        if (options->negative_prompt) {
            diff_opts.negative_prompt = options->negative_prompt;
        }
        diff_opts.width = options->width > 0 ? options->width : 512;
        diff_opts.height = options->height > 0 ? options->height : 512;
        diff_opts.steps = options->steps > 0 ? options->steps : 20;
        diff_opts.guidance_scale = options->guidance_scale > 0 ? options->guidance_scale : 7.5f;
        diff_opts.seed = options->seed;
        diff_opts.scheduler = convert_scheduler(options->scheduler);
        
        // Copy input image if provided (for img2img)
        if (options->input_image_data && options->input_image_size > 0) {
            diff_opts.input_image.assign(
                options->input_image_data, 
                options->input_image_data + options->input_image_size);
            diff_opts.strength = options->denoise_strength > 0 ? options->denoise_strength : 0.8f;
        }
        
        // Progress callback wrapper
        runanywhere::diffusion::ProgressCallback cpp_callback = nullptr;
        if (progress_callback) {
            cpp_callback = [progress_callback, user_data](
                const runanywhere::diffusion::DiffusionProgress& prog) -> bool {
                
                rac_diffusion_progress_t rac_prog = {};
                rac_prog.progress = prog.progress;
                rac_prog.current_step = prog.current_step;
                rac_prog.total_steps = prog.total_steps;
                rac_prog.stage = prog.stage.c_str();
                
                if (!prog.preview.empty()) {
                    rac_prog.intermediate_image_data = prog.preview.data();
                    rac_prog.intermediate_image_size = prog.preview.size();
                    rac_prog.intermediate_image_width = prog.preview_width;
                    rac_prog.intermediate_image_height = prog.preview_height;
                }
                
                return progress_callback(&rac_prog, user_data) == RAC_TRUE;
            };
        }
        
        // Generate
        auto result = impl->diffusion->generate(diff_opts, cpp_callback);
        
        // Fill output
        memset(out_result, 0, sizeof(rac_diffusion_result_t));
        
        if (result.success) {
            // Allocate and copy image data
            out_result->image_data = static_cast<uint8_t*>(malloc(result.image_data.size()));
            if (out_result->image_data) {
                memcpy(out_result->image_data, result.image_data.data(), result.image_data.size());
                out_result->image_size = result.image_data.size();
            }
            out_result->width = result.width;
            out_result->height = result.height;
            out_result->seed_used = result.seed_used;
            out_result->generation_time_ms = static_cast<int64_t>(result.inference_time_ms);
            out_result->safety_flagged = result.safety_triggered ? RAC_TRUE : RAC_FALSE;
            out_result->error_code = RAC_SUCCESS;
            return RAC_SUCCESS;
        } else {
            RAC_LOG_ERROR("rac_diffusion_onnx", "Generation failed: %s", 
                         result.error_message.c_str());
            if (result.error_message == "Cancelled") {
                return RAC_ERROR_CANCELLED;
            }
            return RAC_ERROR_INFERENCE_FAILED;
        }
        
    } catch (const std::exception& e) {
        RAC_LOG_ERROR("rac_diffusion_onnx", "Exception in generate: %s", e.what());
        return RAC_ERROR_UNKNOWN;
    }
}

rac_result_t rac_diffusion_onnx_cancel(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    
    auto* impl = static_cast<rac_diffusion_onnx_handle_impl*>(handle);
    if (impl->diffusion) {
        impl->diffusion->cancel();
    }
    
    return RAC_SUCCESS;
}

rac_result_t rac_diffusion_onnx_get_info(
    rac_handle_t handle,
    rac_diffusion_info_t* out_info) {
    
    if (!handle || !out_info) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    
    auto* impl = static_cast<rac_diffusion_onnx_handle_impl*>(handle);
    if (!impl->diffusion) {
        return RAC_ERROR_NOT_INITIALIZED;
    }
    
    memset(out_info, 0, sizeof(rac_diffusion_info_t));
    out_info->is_ready = impl->diffusion->is_ready() ? RAC_TRUE : RAC_FALSE;
    
    auto variant = impl->diffusion->get_model_variant();
    switch (variant) {
        case runanywhere::diffusion::DiffusionModelVariant::SD_1_5:
            out_info->model_variant = RAC_DIFFUSION_MODEL_SD_1_5;
            break;
        case runanywhere::diffusion::DiffusionModelVariant::SD_2_1:
            out_info->model_variant = RAC_DIFFUSION_MODEL_SD_2_1;
            break;
        case runanywhere::diffusion::DiffusionModelVariant::SDXL:
            out_info->model_variant = RAC_DIFFUSION_MODEL_SDXL;
            break;
        case runanywhere::diffusion::DiffusionModelVariant::SDXL_TURBO:
            out_info->model_variant = RAC_DIFFUSION_MODEL_SDXL_TURBO;
            break;
        case runanywhere::diffusion::DiffusionModelVariant::SDXS:
            out_info->model_variant = RAC_DIFFUSION_MODEL_SDXS;
            break;
        case runanywhere::diffusion::DiffusionModelVariant::LCM:
            out_info->model_variant = RAC_DIFFUSION_MODEL_LCM;
            break;
        default:
            out_info->model_variant = RAC_DIFFUSION_MODEL_SD_1_5;
            break;
    }
    
    uint32_t caps = impl->diffusion->get_capabilities();
    out_info->supports_text_to_image = (caps & (1 << 0)) ? RAC_TRUE : RAC_FALSE;
    out_info->supports_image_to_image = (caps & (1 << 1)) ? RAC_TRUE : RAC_FALSE;
    out_info->supports_inpainting = (caps & (1 << 2)) ? RAC_TRUE : RAC_FALSE;
    out_info->safety_checker_enabled = RAC_FALSE;  // ONNX backend doesn't have safety checker yet
    impl->diffusion->get_max_dimensions(&out_info->max_width, &out_info->max_height);
    
    return RAC_SUCCESS;
}

uint32_t rac_diffusion_onnx_get_capabilities(rac_handle_t handle) {
    if (!handle) {
        return 0;
    }
    
    auto* impl = static_cast<rac_diffusion_onnx_handle_impl*>(handle);
    if (!impl->diffusion) {
        return 0;
    }
    
    return impl->diffusion->get_capabilities();
}

rac_bool_t rac_diffusion_onnx_is_ready(rac_handle_t handle) {
    if (!handle) {
        return RAC_FALSE;
    }
    
    auto* impl = static_cast<rac_diffusion_onnx_handle_impl*>(handle);
    return (impl->diffusion && impl->diffusion->is_ready()) ? RAC_TRUE : RAC_FALSE;
}

void rac_diffusion_onnx_result_free(rac_diffusion_result_t* result) {
    if (result) {
        if (result->image_data) {
            free(result->image_data);
            result->image_data = nullptr;
        }
        result->image_size = 0;
    }
}

void rac_diffusion_onnx_destroy(rac_handle_t handle) {
    if (handle) {
        auto* impl = static_cast<rac_diffusion_onnx_handle_impl*>(handle);
        delete impl;
    }
}

rac_bool_t rac_diffusion_onnx_is_valid_model(const char* model_path) {
    if (!model_path) {
        return RAC_FALSE;
    }
    
    // Check for required ONNX files
    fs::path dir(model_path);
    
    // Check for subdirectory structure
    bool has_text_encoder = fs::exists(dir / "text_encoder" / "model.onnx") ||
                           fs::exists(dir / "text_encoder.onnx");
    bool has_unet = fs::exists(dir / "unet" / "model.onnx") ||
                   fs::exists(dir / "unet.onnx");
    bool has_vae = fs::exists(dir / "vae_decoder" / "model.onnx") ||
                  fs::exists(dir / "vae_decoder.onnx");
    
    return (has_text_encoder && has_unet && has_vae) ? RAC_TRUE : RAC_FALSE;
}

int rac_diffusion_onnx_get_required_files(
    rac_diffusion_model_variant_t model_variant,
    const char** out_files,
    int max_files) {
    
    (void)model_variant;  // Same files for all variants
    
    static const char* required_files[] = {
        "text_encoder/model.onnx",
        "unet/model.onnx",
        "vae_decoder/model.onnx",
        "tokenizer/vocab.json",
        "tokenizer/merges.txt"
    };
    
    int num_files = sizeof(required_files) / sizeof(required_files[0]);
    int copy_count = (max_files < num_files) ? max_files : num_files;
    
    if (out_files) {
        for (int i = 0; i < copy_count; ++i) {
            out_files[i] = required_files[i];
        }
    }
    
    return num_files;
}

}  // extern "C"
