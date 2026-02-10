/**
 * @file diffusion_model_registry.cpp
 * @brief Diffusion Model Registry Implementation
 *
 * Contains built-in model definitions and the extensible registry implementation.
 * This is the shared C++ layer used by all SDKs.
 */

#include "rac/features/diffusion/rac_diffusion_model_registry.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_error.h"

#include <mutex>
#include <vector>
#include <string>
#include <cstring>
#include <cstdlib>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

namespace {

const char* LOG_CAT = "DiffusionModelRegistry";

// =============================================================================
// BUILT-IN MODEL DEFINITIONS (CoreML only for now - iOS/macOS)
// =============================================================================

// SD 1.5 CoreML (iOS/macOS - uses Apple Neural Engine)
static const rac_diffusion_model_def_t MODEL_SD15_COREML = {
    .model_id = "stable-diffusion-v1-5-coreml",
    .display_name = "Stable Diffusion 1.5",
    .description = "Apple-optimized SD 1.5 for iOS/macOS. Uses Neural Engine for fast generation.",
    .variant = RAC_DIFFUSION_MODEL_SD_1_5,
    .backend = RAC_DIFFUSION_BACKEND_COREML,
    .platforms = RAC_DIFFUSION_PLATFORM_IOS | RAC_DIFFUSION_PLATFORM_MACOS,
    .hardware = RAC_DIFFUSION_HW_ANE | RAC_DIFFUSION_HW_GPU | RAC_DIFFUSION_HW_CPU,
    .defaults = {
        .width = 512,
        .height = 512,
        .steps = 20,
        .guidance_scale = 7.5f,
        .scheduler = RAC_DIFFUSION_SCHEDULER_DPM_PP_2M,
        .requires_cfg = RAC_TRUE
    },
    .download = {
        .base_url = "https://huggingface.co/apple/coreml-stable-diffusion-v1-5-palettized",
        .onnx_path = nullptr,
        .coreml_path = "split_einsum_v2_compiled",
        .size_bytes = 1200000000ULL,
        .checksum = nullptr
    },
    .tokenizer = {
        .source = RAC_DIFFUSION_TOKENIZER_SD_1_5,
        .custom_url = nullptr
    },
    .is_recommended = RAC_TRUE,
    .supports_img2img = RAC_TRUE,
    .supports_inpainting = RAC_FALSE
};

// SD 2.1 CoreML (iOS/macOS)
static const rac_diffusion_model_def_t MODEL_SD21_COREML = {
    .model_id = "stable-diffusion-v2-1-coreml",
    .display_name = "Stable Diffusion 2.1",
    .description = "Apple-optimized SD 2.1 for iOS/macOS. Higher resolution (768x768).",
    .variant = RAC_DIFFUSION_MODEL_SD_2_1,
    .backend = RAC_DIFFUSION_BACKEND_COREML,
    .platforms = RAC_DIFFUSION_PLATFORM_IOS | RAC_DIFFUSION_PLATFORM_MACOS,
    .hardware = RAC_DIFFUSION_HW_ANE | RAC_DIFFUSION_HW_GPU | RAC_DIFFUSION_HW_CPU,
    .defaults = {
        .width = 768,
        .height = 768,
        .steps = 20,
        .guidance_scale = 7.5f,
        .scheduler = RAC_DIFFUSION_SCHEDULER_DPM_PP_2M,
        .requires_cfg = RAC_TRUE
    },
    .download = {
        .base_url = "https://huggingface.co/apple/coreml-stable-diffusion-2-1-base-palettized",
        .onnx_path = nullptr,
        .coreml_path = "split_einsum_v2_compiled",
        .size_bytes = 1500000000ULL,
        .checksum = nullptr
    },
    .tokenizer = {
        .source = RAC_DIFFUSION_TOKENIZER_SD_2_X,
        .custom_url = nullptr
    },
    .is_recommended = RAC_FALSE,
    .supports_img2img = RAC_TRUE,
    .supports_inpainting = RAC_FALSE
};

// All built-in models (CoreML only)
static const rac_diffusion_model_def_t* BUILTIN_MODELS[] = {
    &MODEL_SD15_COREML,
    &MODEL_SD21_COREML,
};

static const size_t BUILTIN_MODEL_COUNT = sizeof(BUILTIN_MODELS) / sizeof(BUILTIN_MODELS[0]);

// =============================================================================
// REGISTRY STATE
// =============================================================================

struct RegistryState {
    std::mutex mutex;
    std::vector<rac_diffusion_model_strategy_t> strategies;
    bool initialized = false;
};

RegistryState& get_state() {
    static RegistryState state;
    return state;
}

// =============================================================================
// PLATFORM DETECTION
// =============================================================================

uint32_t detect_current_platform() {
#if defined(__APPLE__)
    #if TARGET_OS_IOS || TARGET_OS_SIMULATOR
        return RAC_DIFFUSION_PLATFORM_IOS;
    #else
        return RAC_DIFFUSION_PLATFORM_MACOS;
    #endif
#elif defined(__ANDROID__)
    return RAC_DIFFUSION_PLATFORM_ANDROID;
#elif defined(_WIN32) || defined(_WIN64)
    return RAC_DIFFUSION_PLATFORM_WINDOWS;
#elif defined(__linux__)
    return RAC_DIFFUSION_PLATFORM_LINUX;
#else
    return RAC_DIFFUSION_PLATFORM_LINUX;  // Default to Linux
#endif
}

// =============================================================================
// BUILT-IN STRATEGY IMPLEMENTATION
// =============================================================================

static rac_bool_t builtin_can_handle(const char* model_id, void* /*user_data*/) {
    if (!model_id) return RAC_FALSE;
    
    for (size_t i = 0; i < BUILTIN_MODEL_COUNT; i++) {
        if (std::strcmp(model_id, BUILTIN_MODELS[i]->model_id) == 0) {
            return RAC_TRUE;
        }
    }
    return RAC_FALSE;
}

static rac_result_t builtin_get_model_def(const char* model_id,
                                           rac_diffusion_model_def_t* out_def,
                                           void* /*user_data*/) {
    if (!model_id || !out_def) return RAC_ERROR_INVALID_ARGUMENT;
    
    for (size_t i = 0; i < BUILTIN_MODEL_COUNT; i++) {
        if (std::strcmp(model_id, BUILTIN_MODELS[i]->model_id) == 0) {
            *out_def = *BUILTIN_MODELS[i];
            return RAC_SUCCESS;
        }
    }
    return RAC_ERROR_NOT_FOUND;
}

static rac_result_t builtin_list_models(rac_diffusion_model_def_t** out_models,
                                         size_t* out_count,
                                         void* /*user_data*/) {
    if (!out_models || !out_count) return RAC_ERROR_INVALID_ARGUMENT;
    
    uint32_t current_platform = detect_current_platform();
    
    // Count available models for this platform
    size_t count = 0;
    for (size_t i = 0; i < BUILTIN_MODEL_COUNT; i++) {
        if (BUILTIN_MODELS[i]->platforms & current_platform) {
            count++;
        }
    }
    
    // Handle empty result (no models for this platform)
    if (count == 0) {
        *out_models = nullptr;
        *out_count = 0;
        return RAC_SUCCESS;
    }

    // Allocate output array
    auto* models = static_cast<rac_diffusion_model_def_t*>(
        std::malloc(count * sizeof(rac_diffusion_model_def_t)));
    if (!models) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    
    // Copy available models
    size_t idx = 0;
    for (size_t i = 0; i < BUILTIN_MODEL_COUNT; i++) {
        if (BUILTIN_MODELS[i]->platforms & current_platform) {
            models[idx++] = *BUILTIN_MODELS[i];
        }
    }
    
    *out_models = models;
    *out_count = count;
    return RAC_SUCCESS;
}

static rac_diffusion_backend_t builtin_select_backend(const rac_diffusion_model_def_t* model,
                                                       void* /*user_data*/) {
    // Diffusion is Apple CoreML-only; no ONNX diffusion.
    if (!model) {
#if defined(__APPLE__)
        return RAC_DIFFUSION_BACKEND_COREML;
#else
        return RAC_DIFFUSION_BACKEND_COREML;  // Unused on non-Apple (diffusion not built)
#endif
    }
    if (model->backend != RAC_DIFFUSION_BACKEND_AUTO) {
        return model->backend;
    }
#if defined(__APPLE__)
    if (model->download.coreml_path != nullptr) {
        return RAC_DIFFUSION_BACKEND_COREML;
    }
#endif
    return RAC_DIFFUSION_BACKEND_COREML;
}

static rac_diffusion_model_strategy_t BUILTIN_STRATEGY = {
    .name = "BuiltIn",
    .can_handle = builtin_can_handle,
    .get_model_def = builtin_get_model_def,
    .list_models = builtin_list_models,
    .select_backend = builtin_select_backend,
    .load_model = nullptr,  // Use default loading
    .user_data = nullptr
};

}  // anonymous namespace

// =============================================================================
// PUBLIC API IMPLEMENTATION
// =============================================================================

extern "C" {

void rac_diffusion_model_registry_init(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    
    if (state.initialized) {
        RAC_LOG_DEBUG(LOG_CAT, "Registry already initialized");
        return;
    }
    
    // Register built-in strategy
    state.strategies.push_back(BUILTIN_STRATEGY);
    state.initialized = true;
    
    RAC_LOG_INFO(LOG_CAT, "Diffusion model registry initialized with %zu built-in models", 
                 BUILTIN_MODEL_COUNT);
    
    // Log available models for current platform
    uint32_t platform = detect_current_platform();
    const char* platform_name = "Unknown";
#if defined(__APPLE__)
    #if TARGET_OS_IOS || TARGET_OS_SIMULATOR
        platform_name = "iOS";
    #else
        platform_name = "macOS";
    #endif
#elif defined(__ANDROID__)
    platform_name = "Android";
#elif defined(_WIN32)
    platform_name = "Windows";
#else
    platform_name = "Linux";
#endif
    
    RAC_LOG_INFO(LOG_CAT, "Current platform: %s (0x%x)", platform_name, platform);
}

void rac_diffusion_model_registry_cleanup(void) {
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    
    state.strategies.clear();
    state.initialized = false;
    
    RAC_LOG_INFO(LOG_CAT, "Diffusion model registry cleaned up");
}

rac_result_t rac_diffusion_model_registry_register(const rac_diffusion_model_strategy_t* strategy) {
    if (!strategy || !strategy->name) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    
    // Check for duplicate
    for (const auto& s : state.strategies) {
        if (std::strcmp(s.name, strategy->name) == 0) {
            RAC_LOG_WARNING(LOG_CAT, "Strategy '%s' already registered", strategy->name);
            return RAC_ERROR_SERVICE_ALREADY_REGISTERED;
        }
    }
    
    state.strategies.push_back(*strategy);
    RAC_LOG_INFO(LOG_CAT, "Registered diffusion model strategy: %s", strategy->name);
    
    return RAC_SUCCESS;
}

rac_result_t rac_diffusion_model_registry_unregister(const char* name) {
    if (!name) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    
    for (auto it = state.strategies.begin(); it != state.strategies.end(); ++it) {
        if (std::strcmp(it->name, name) == 0) {
            state.strategies.erase(it);
            RAC_LOG_INFO(LOG_CAT, "Unregistered diffusion model strategy: %s", name);
            return RAC_SUCCESS;
        }
    }
    
    return RAC_ERROR_NOT_FOUND;
}

rac_result_t rac_diffusion_model_registry_get(const char* model_id,
                                               rac_diffusion_model_def_t* out_def) {
    if (!model_id || !out_def) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    
    // Try each strategy
    for (const auto& strategy : state.strategies) {
        if (strategy.can_handle && strategy.can_handle(model_id, strategy.user_data)) {
            if (strategy.get_model_def) {
                rac_result_t result = strategy.get_model_def(model_id, out_def, strategy.user_data);
                if (result == RAC_SUCCESS) {
                    return RAC_SUCCESS;
                }
            }
        }
    }
    
    RAC_LOG_WARNING(LOG_CAT, "Model not found: %s", model_id);
    return RAC_ERROR_NOT_FOUND;
}

rac_result_t rac_diffusion_model_registry_list(rac_diffusion_model_def_t** out_models,
                                                size_t* out_count) {
    if (!out_models || !out_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    
    // Collect all models from all strategies
    std::vector<rac_diffusion_model_def_t> all_models;
    
    for (const auto& strategy : state.strategies) {
        if (strategy.list_models) {
            rac_diffusion_model_def_t* models = nullptr;
            size_t count = 0;
            
            if (strategy.list_models(&models, &count, strategy.user_data) == RAC_SUCCESS && models) {
                for (size_t i = 0; i < count; i++) {
                    all_models.push_back(models[i]);
                }
                std::free(models);
            }
        }
    }
    
    if (all_models.empty()) {
        *out_models = nullptr;
        *out_count = 0;
        return RAC_SUCCESS;
    }
    
    // Allocate output
    auto* result = static_cast<rac_diffusion_model_def_t*>(
        std::malloc(all_models.size() * sizeof(rac_diffusion_model_def_t)));
    if (!result) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    
    for (size_t i = 0; i < all_models.size(); i++) {
        result[i] = all_models[i];
    }
    
    *out_models = result;
    *out_count = all_models.size();
    return RAC_SUCCESS;
}

rac_diffusion_backend_t rac_diffusion_model_registry_select_backend(const char* model_id) {
    rac_diffusion_model_def_t model_def;
    
    if (rac_diffusion_model_registry_get(model_id, &model_def) != RAC_SUCCESS) {
        RAC_LOG_DEBUG(LOG_CAT, "Model '%s' not found, using CoreML (Apple only)", 
                      model_id ? model_id : "(null)");
        return RAC_DIFFUSION_BACKEND_COREML;
    }
    
    auto& state = get_state();
    std::lock_guard<std::mutex> lock(state.mutex);
    
    // Find strategy that handles this model and use its backend selection
    for (const auto& strategy : state.strategies) {
        if (strategy.can_handle && strategy.can_handle(model_id, strategy.user_data)) {
            if (strategy.select_backend) {
                rac_diffusion_backend_t backend = strategy.select_backend(&model_def, strategy.user_data);
                RAC_LOG_DEBUG(LOG_CAT, "Selected backend %d for model '%s'", backend, model_id);
                return backend;
            }
        }
    }
    
    // Return model's preferred backend
    return model_def.backend;
}

rac_bool_t rac_diffusion_model_registry_is_available(const char* model_id) {
    rac_diffusion_model_def_t model_def;
    if (rac_diffusion_model_registry_get(model_id, &model_def) != RAC_SUCCESS) {
        return RAC_FALSE;
    }
    
    // Check platform availability
    uint32_t current_platform = detect_current_platform();
    return (model_def.platforms & current_platform) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_diffusion_model_registry_get_recommended(rac_diffusion_model_def_t* out_def) {
    if (!out_def) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    
    rac_diffusion_model_def_t* models = nullptr;
    size_t count = 0;
    
    rac_result_t result = rac_diffusion_model_registry_list(&models, &count);
    if (result != RAC_SUCCESS || !models || count == 0) {
        return RAC_ERROR_NOT_FOUND;
    }
    
    // Find first recommended model
    for (size_t i = 0; i < count; i++) {
        if (models[i].is_recommended) {
            *out_def = models[i];
            std::free(models);
            return RAC_SUCCESS;
        }
    }
    
    // No recommended model found, return first available
    *out_def = models[0];
    std::free(models);
    return RAC_SUCCESS;
}

uint32_t rac_diffusion_model_registry_get_current_platform(void) {
    return detect_current_platform();
}

rac_bool_t rac_diffusion_model_requires_cfg(rac_diffusion_model_variant_t variant) {
    // These models don't need classifier-free guidance
    switch (variant) {
        case RAC_DIFFUSION_MODEL_SDXS:
        case RAC_DIFFUSION_MODEL_SDXL_TURBO:
            return RAC_FALSE;
        
        // Standard models need CFG
        case RAC_DIFFUSION_MODEL_SD_1_5:
        case RAC_DIFFUSION_MODEL_SD_2_1:
        case RAC_DIFFUSION_MODEL_SDXL:
        case RAC_DIFFUSION_MODEL_LCM:
        default:
            return RAC_TRUE;
    }
}

}  // extern "C"
