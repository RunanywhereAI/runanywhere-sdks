/**
 * @file onnx_diffusion.h
 * @brief ONNX Diffusion Backend - Internal C++ Implementation
 *
 * Implements Stable Diffusion using ONNX Runtime.
 * Supports SD 1.5, SD 2.x, and SDXL models.
 *
 * Components:
 * - Text Encoder (CLIP)
 * - UNet (Denoising)
 * - VAE Decoder (Latent to Image)
 * - VAE Encoder (Image to Latent, for img2img)
 * - BPE Tokenizer
 * - Noise Schedulers
 */

#ifndef RUNANYWHERE_ONNX_DIFFUSION_H
#define RUNANYWHERE_ONNX_DIFFUSION_H

#include <onnxruntime_c_api.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "bpe_tokenizer.h"
#include "diffusion_scheduler.h"

namespace runanywhere {
namespace diffusion {

// Forward declare the backend
class ONNXBackendNew;

// =============================================================================
// CONFIGURATION
// =============================================================================

/**
 * @brief ONNX Execution Provider type
 */
enum class ONNXExecutionProvider {
    AUTO,       // Auto-detect best available
    CPU,        // CPU only
    COREML,     // Apple CoreML (Neural Engine)
    NNAPI,      // Android NNAPI
    CUDA,       // NVIDIA CUDA
    DIRECTML,   // Windows DirectML
};

/**
 * @brief Diffusion model variant
 */
enum class DiffusionModelVariant {
    SD_1_5,      // Stable Diffusion 1.5 (512x512)
    SD_2_1,      // Stable Diffusion 2.1 (768x768)
    SDXL,        // Stable Diffusion XL (1024x1024)
    SDXL_TURBO,  // SDXL Turbo (4 steps, no CFG)
    SDXS,        // SDXS ultra-fast (1 step, no CFG)
    LCM,         // Latent Consistency Model (4 steps)
    UNKNOWN,
};

/**
 * @brief Configuration for ONNX Diffusion
 */
struct ONNXDiffusionConfig {
    DiffusionModelVariant model_variant = DiffusionModelVariant::SD_1_5;
    SchedulerType scheduler_type = SchedulerType::DPM_PP_2M_KARRAS;
    ONNXExecutionProvider execution_provider = ONNXExecutionProvider::AUTO;
    int num_threads = 0;              // 0 = auto
    bool enable_memory_pattern = true;
    bool enable_cpu_mem_arena = true;
    
    // Default dimensions based on variant
    int default_width() const {
        switch (model_variant) {
            case DiffusionModelVariant::SD_1_5:
            case DiffusionModelVariant::SDXS:
            case DiffusionModelVariant::LCM:
                return 512;
            case DiffusionModelVariant::SD_2_1: return 768;
            case DiffusionModelVariant::SDXL:
            case DiffusionModelVariant::SDXL_TURBO: return 1024;
            default: return 512;
        }
    }
    int default_height() const { return default_width(); }
    int default_steps() const {
        switch (model_variant) {
            case DiffusionModelVariant::SDXS: return 1;        // Ultra-fast 1-step
            case DiffusionModelVariant::SDXL_TURBO: return 4;  // Fast 4-step
            case DiffusionModelVariant::LCM: return 4;         // LCM 4-step
            default: return 20;
        }
    }
    float default_guidance_scale() const {
        switch (model_variant) {
            case DiffusionModelVariant::SDXS:
            case DiffusionModelVariant::SDXL_TURBO:
                return 0.0f;  // No CFG needed
            case DiffusionModelVariant::LCM:
                return 1.5f;  // Low CFG
            default: return 7.5f;
        }
    }
    bool requires_cfg() const {
        switch (model_variant) {
            case DiffusionModelVariant::SDXS:
            case DiffusionModelVariant::SDXL_TURBO:
                return false;  // CFG-free distilled models
            default: return true;
        }
    }
};

/**
 * @brief Generation options
 */
struct DiffusionOptions {
    std::string prompt;
    std::string negative_prompt;
    int width = 512;
    int height = 512;
    int steps = 20;
    float guidance_scale = 7.5f;
    int64_t seed = -1;  // -1 = random
    SchedulerType scheduler = SchedulerType::DPM_PP_2M_KARRAS;
    
    // Image-to-image
    std::vector<uint8_t> input_image;  // RGBA input for img2img
    float strength = 0.8f;             // Denoising strength for img2img
    
    // Inpainting
    std::vector<uint8_t> mask_image;   // Mask for inpainting
};

/**
 * @brief Progress information
 */
struct DiffusionProgress {
    float progress = 0.0f;           // 0.0 to 1.0
    int current_step = 0;
    int total_steps = 0;
    std::string stage;               // "encoding", "denoising", "decoding"
    std::vector<uint8_t> preview;    // Optional intermediate preview
    int preview_width = 0;
    int preview_height = 0;
};

/**
 * @brief Generation result
 */
struct DiffusionResult {
    bool success = false;
    std::string error_message;
    
    std::vector<uint8_t> image_data;  // RGBA image
    int width = 0;
    int height = 0;
    int64_t seed_used = 0;
    
    double inference_time_ms = 0.0;
    bool safety_triggered = false;
};

// Callback types
using ProgressCallback = std::function<bool(const DiffusionProgress&)>;

// =============================================================================
// ONNX DIFFUSION CLASS
// =============================================================================

/**
 * @brief ONNX-based Stable Diffusion implementation
 */
class ONNXDiffusion {
   public:
    /**
     * @brief Constructor
     * @param ort_api ONNX Runtime API (from ONNXBackendNew)
     * @param ort_env ONNX Runtime Environment (from ONNXBackendNew)
     */
    ONNXDiffusion(const OrtApi* ort_api, OrtEnv* ort_env);
    ~ONNXDiffusion();

    /**
     * @brief Check if ready for generation
     */
    bool is_ready() const { return model_loaded_; }

    /**
     * @brief Load diffusion model from directory
     * @param model_dir Directory containing ONNX models and tokenizer
     * @param config Configuration options
     * @return true if loaded successfully
     */
    bool load_model(const std::string& model_dir, const ONNXDiffusionConfig& config = {});

    /**
     * @brief Unload model and free resources
     */
    bool unload_model();

    /**
     * @brief Check if model is loaded
     */
    bool is_model_loaded() const { return model_loaded_; }

    /**
     * @brief Get model variant
     */
    DiffusionModelVariant get_model_variant() const { return config_.model_variant; }

    /**
     * @brief Generate image from text prompt
     * @param options Generation options
     * @return Generation result
     */
    DiffusionResult generate(const DiffusionOptions& options);

    /**
     * @brief Generate image with progress callback
     * @param options Generation options
     * @param progress_callback Callback for progress updates (return false to cancel)
     * @return Generation result
     */
    DiffusionResult generate(const DiffusionOptions& options, 
                            ProgressCallback progress_callback);

    /**
     * @brief Cancel ongoing generation
     */
    void cancel();

    /**
     * @brief Get supported capabilities
     * @return Bitmask of capabilities (text2img, img2img, inpainting)
     */
    uint32_t get_capabilities() const;

    /**
     * @brief Get maximum supported dimensions
     */
    void get_max_dimensions(int* max_width, int* max_height) const;

   private:
    // ONNX Runtime
    const OrtApi* ort_api_;
    OrtEnv* ort_env_;
    OrtSessionOptions* session_options_ = nullptr;
    
    // Model sessions
    OrtSession* text_encoder_session_ = nullptr;
    OrtSession* unet_session_ = nullptr;
    OrtSession* vae_decoder_session_ = nullptr;
    OrtSession* vae_encoder_session_ = nullptr;  // Optional, for img2img
    
    // Tokenizer and scheduler
    std::unique_ptr<BPETokenizer> tokenizer_;
    std::unique_ptr<Scheduler> scheduler_;
    
    // Configuration
    ONNXDiffusionConfig config_;
    std::string model_dir_;
    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};
    
    // Memory allocator
    OrtMemoryInfo* memory_info_ = nullptr;
    OrtAllocator* allocator_ = nullptr;
    
    mutable std::mutex mutex_;

    // Internal methods
    bool create_session_options();
    bool load_text_encoder(const std::string& path);
    bool load_unet(const std::string& path);
    bool load_vae_decoder(const std::string& path);
    bool load_vae_encoder(const std::string& path);
    bool load_tokenizer(const std::string& dir);
    DiffusionModelVariant detect_model_variant(const std::string& model_dir);
    
    // Inference steps
    std::vector<float> encode_prompt(const std::string& prompt);
    std::vector<float> encode_image(const std::vector<uint8_t>& image, int width, int height);
    std::vector<float> run_unet_step(const std::vector<float>& latents,
                                     const std::vector<float>& text_embeddings,
                                     float timestep,
                                     int latent_h, int latent_w);
    std::vector<uint8_t> decode_latents(const std::vector<float>& latents, 
                                        int latent_height, int latent_width);
    
    // Classifier-free guidance
    std::vector<float> apply_guidance(const std::vector<float>& noise_pred_uncond,
                                      const std::vector<float>& noise_pred_text,
                                      float guidance_scale);
    
    // Utility
    void free_sessions();
    bool check_onnx_status(OrtStatus* status, const char* operation);
    
    // Verify external data files are accessible before generation
    bool verify_external_data_accessible(std::string& error_message);
};

}  // namespace diffusion
}  // namespace runanywhere

#endif  // RUNANYWHERE_ONNX_DIFFUSION_H
