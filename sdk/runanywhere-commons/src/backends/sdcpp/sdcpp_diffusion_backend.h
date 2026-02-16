/**
 * @file sdcpp_diffusion_backend.h
 * @brief Internal C++ wrapper around stable-diffusion.cpp
 *
 * This class manages the sd.cpp context lifecycle and provides a clean
 * C++ interface that the RAC API wrapper and vtable can use.
 *
 * Architecture: This is the lowest layer that directly calls stable-diffusion.cpp.
 * It is wrapped by rac_diffusion_sdcpp.cpp (C API) which is wrapped by
 * rac_backend_sdcpp_register.cpp (vtable + service registry).
 */

#ifndef SDCPP_DIFFUSION_BACKEND_H
#define SDCPP_DIFFUSION_BACKEND_H

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>

#include "rac/features/diffusion/rac_diffusion_types.h"

// Forward declare sd.cpp context type
typedef struct sd_ctx_t sd_ctx_t;

namespace runanywhere {

/**
 * Progress callback context for sd.cpp step callback.
 */
struct SdcppProgressContext {
    rac_diffusion_progress_callback_fn callback;
    void* user_data;
    int total_steps;
    std::atomic<bool>* cancel_flag;
};

class SdcppDiffusionBackend {
   public:
    SdcppDiffusionBackend();
    ~SdcppDiffusionBackend();

    // Non-copyable
    SdcppDiffusionBackend(const SdcppDiffusionBackend&) = delete;
    SdcppDiffusionBackend& operator=(const SdcppDiffusionBackend&) = delete;

    /**
     * Load a diffusion model.
     * @param model_path Path to .safetensors, .gguf, or .ckpt file.
     * @param config Diffusion configuration.
     * @return RAC_SUCCESS or error code.
     */
    rac_result_t load_model(const char* model_path, const rac_diffusion_config_t* config);

    /**
     * Generate an image (text-to-image).
     * @param options Generation options.
     * @param out_result Output result with RGBA data.
     * @return RAC_SUCCESS or error code.
     */
    rac_result_t generate(const rac_diffusion_options_t* options,
                          rac_diffusion_result_t* out_result);

    /**
     * Generate with progress reporting.
     */
    rac_result_t generate_with_progress(const rac_diffusion_options_t* options,
                                        rac_diffusion_progress_callback_fn progress_callback,
                                        void* user_data, rac_diffusion_result_t* out_result);

    /** Cancel ongoing generation. */
    void cancel();

    /** Unload model and free resources. */
    void cleanup();

    /** Check if a model is loaded and ready. */
    bool is_ready() const;

    /** Get current model path. */
    const std::string& model_path() const { return model_path_; }

    /** Get model variant. */
    rac_diffusion_model_variant_t model_variant() const { return model_variant_; }

    /** Get supported capabilities. */
    uint32_t capabilities() const;

   private:
    /**
     * Internal generation implementation shared by generate() and generate_with_progress().
     */
    rac_result_t generate_internal(const rac_diffusion_options_t* options,
                                   rac_diffusion_progress_callback_fn progress_callback,
                                   void* user_data, rac_diffusion_result_t* out_result);

    /**
     * Convert sd.cpp raw RGB output to RGBA format.
     * sd.cpp outputs RGB (3 channels), our API expects RGBA (4 channels).
     */
    static uint8_t* convert_rgb_to_rgba(const uint8_t* rgb_data, int width, int height,
                                        size_t* out_size);

    sd_ctx_t* ctx_ = nullptr;
    std::string model_path_;
    rac_diffusion_model_variant_t model_variant_ = RAC_DIFFUSION_MODEL_SD_1_5;
    bool reduce_memory_ = false;
    std::atomic<bool> cancel_requested_{false};
    mutable std::mutex mutex_;
};

}  // namespace runanywhere

#endif /* SDCPP_DIFFUSION_BACKEND_H */
