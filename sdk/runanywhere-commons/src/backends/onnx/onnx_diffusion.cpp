/**
 * @file onnx_diffusion.cpp
 * @brief ONNX Diffusion Backend Implementation
 *
 * Implements Stable Diffusion using ONNX Runtime with support for:
 * - Text-to-Image generation
 * - Image-to-Image generation
 * - Multiple execution providers (CoreML, NNAPI, CUDA, CPU)
 */

#include "onnx_diffusion.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <numeric>

#include "rac/core/rac_logger.h"

// Platform-specific Execution Provider declarations
// These are conditionally compiled based on CMake definitions

#if defined(__APPLE__) && defined(ORT_USE_COREML)
// CoreML Execution Provider for Apple Neural Engine
// Available in ONNX Runtime iOS/macOS packages by default
#ifdef __cplusplus
extern "C" {
#endif
OrtStatus* OrtSessionOptionsAppendExecutionProvider_CoreML(OrtSessionOptions* options, 
                                                           uint32_t coreml_flags);
#ifdef __cplusplus
}
#endif
#define RAC_COREML_EP_AVAILABLE 1
#else
#define RAC_COREML_EP_AVAILABLE 0
#endif // __APPLE__ && ORT_USE_COREML

#if defined(__ANDROID__) && defined(ORT_USE_NNAPI)
// NNAPI Execution Provider for Android NPU acceleration
#ifdef __cplusplus
extern "C" {
#endif
OrtStatus* OrtSessionOptionsAppendExecutionProvider_Nnapi(OrtSessionOptions* options,
                                                          uint32_t nnapi_flags);
#ifdef __cplusplus
}
#endif
#define RAC_NNAPI_EP_AVAILABLE 1
#else
#define RAC_NNAPI_EP_AVAILABLE 0
#endif // __ANDROID__ && ORT_USE_NNAPI

namespace fs = std::filesystem;

namespace runanywhere {
namespace diffusion {

// =============================================================================
// CONSTANTS
// =============================================================================

// Latent space parameters
constexpr int LATENT_CHANNELS = 4;
constexpr float VAE_SCALE_FACTOR = 0.18215f;

// CLIP text encoder parameters
constexpr int TEXT_EMBEDDING_DIM = 768;  // SD 1.x
constexpr int TEXT_EMBEDDING_DIM_XL = 2048;  // SDXL

// =============================================================================
// CONSTRUCTION / DESTRUCTION
// =============================================================================

ONNXDiffusion::ONNXDiffusion(const OrtApi* ort_api, OrtEnv* ort_env)
    : ort_api_(ort_api), ort_env_(ort_env) {
    
    // Create memory info
    if (ort_api_) {
        OrtStatus* status = ort_api_->CreateCpuMemoryInfo(
            OrtArenaAllocator, OrtMemTypeDefault, &memory_info_);
        if (status) {
            RAC_LOG_ERROR("ONNXDiffusion", "Failed to create memory info");
            ort_api_->ReleaseStatus(status);
            memory_info_ = nullptr;
        }
        
        // Get default allocator
        status = ort_api_->GetAllocatorWithDefaultOptions(&allocator_);
        if (status) {
            RAC_LOG_ERROR("ONNXDiffusion", "Failed to get allocator");
            ort_api_->ReleaseStatus(status);
        }
    }
}

ONNXDiffusion::~ONNXDiffusion() {
    unload_model();
    
    if (memory_info_) {
        ort_api_->ReleaseMemoryInfo(memory_info_);
        memory_info_ = nullptr;
    }
}

// =============================================================================
// MODEL LOADING
// =============================================================================

bool ONNXDiffusion::load_model(const std::string& model_dir, const ONNXDiffusionConfig& config) {
    std::lock_guard<std::mutex> lock(mutex_);
    
    if (model_loaded_) {
        unload_model();
    }
    
    model_dir_ = model_dir;
    config_ = config;
    
    RAC_LOG_INFO("ONNXDiffusion", "Loading model from: %s", model_dir.c_str());
    
    // Detect model variant if not specified
    if (config_.model_variant == DiffusionModelVariant::UNKNOWN) {
        config_.model_variant = detect_model_variant(model_dir);
    }
    
    // Create session options
    if (!create_session_options()) {
        RAC_LOG_ERROR("ONNXDiffusion", "Failed to create session options");
        return false;
    }
    
    // Load components
    std::string text_encoder_path = model_dir + "/text_encoder/model.onnx";
    std::string unet_path = model_dir + "/unet/model.onnx";
    std::string vae_decoder_path = model_dir + "/vae_decoder/model.onnx";
    std::string vae_encoder_path = model_dir + "/vae_encoder/model.onnx";
    
    // Check for alternative paths
    if (!fs::exists(text_encoder_path)) {
        text_encoder_path = model_dir + "/text_encoder.onnx";
    }
    if (!fs::exists(unet_path)) {
        unet_path = model_dir + "/unet.onnx";
    }
    if (!fs::exists(vae_decoder_path)) {
        vae_decoder_path = model_dir + "/vae_decoder.onnx";
    }
    
    // Load required components
    if (!load_text_encoder(text_encoder_path)) {
        RAC_LOG_ERROR("ONNXDiffusion", "Failed to load text encoder");
        free_sessions();
        return false;
    }
    
    if (!load_unet(unet_path)) {
        RAC_LOG_ERROR("ONNXDiffusion", "Failed to load UNet");
        free_sessions();
        return false;
    }
    
    if (!load_vae_decoder(vae_decoder_path)) {
        RAC_LOG_ERROR("ONNXDiffusion", "Failed to load VAE decoder");
        free_sessions();
        return false;
    }
    
    // Load optional VAE encoder for img2img
    if (fs::exists(vae_encoder_path)) {
        load_vae_encoder(vae_encoder_path);
    }
    
    // Load tokenizer
    if (!load_tokenizer(model_dir)) {
        RAC_LOG_ERROR("ONNXDiffusion", "Failed to load tokenizer");
        free_sessions();
        return false;
    }
    
    // Create scheduler
    SchedulerConfig sched_config;
    scheduler_ = Scheduler::create(config_.scheduler_type, sched_config);
    
    model_loaded_ = true;
    RAC_LOG_INFO("ONNXDiffusion", "Model loaded successfully (variant: %d)", 
                 static_cast<int>(config_.model_variant));
    
    return true;
}

bool ONNXDiffusion::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);
    
    free_sessions();
    tokenizer_.reset();
    scheduler_.reset();
    model_loaded_ = false;
    
    return true;
}

void ONNXDiffusion::free_sessions() {
    if (text_encoder_session_) {
        ort_api_->ReleaseSession(text_encoder_session_);
        text_encoder_session_ = nullptr;
    }
    if (unet_session_) {
        ort_api_->ReleaseSession(unet_session_);
        unet_session_ = nullptr;
    }
    if (vae_decoder_session_) {
        ort_api_->ReleaseSession(vae_decoder_session_);
        vae_decoder_session_ = nullptr;
    }
    if (vae_encoder_session_) {
        ort_api_->ReleaseSession(vae_encoder_session_);
        vae_encoder_session_ = nullptr;
    }
    if (session_options_) {
        ort_api_->ReleaseSessionOptions(session_options_);
        session_options_ = nullptr;
    }
}

bool ONNXDiffusion::create_session_options() {
    OrtStatus* status = ort_api_->CreateSessionOptions(&session_options_);
    if (!check_onnx_status(status, "CreateSessionOptions")) {
        return false;
    }
    
    // Set thread count
    int num_threads = config_.num_threads > 0 ? config_.num_threads : 4;
    status = ort_api_->SetIntraOpNumThreads(session_options_, num_threads);
    check_onnx_status(status, "SetIntraOpNumThreads");
    
    // Enable memory optimizations
    if (config_.enable_memory_pattern) {
        status = ort_api_->EnableMemPattern(session_options_);
        check_onnx_status(status, "EnableMemPattern");
    }
    
    if (config_.enable_cpu_mem_arena) {
        status = ort_api_->EnableCpuMemArena(session_options_);
        check_onnx_status(status, "EnableCpuMemArena");
    }
    
    // Set graph optimization level
    status = ort_api_->SetSessionGraphOptimizationLevel(session_options_, ORT_ENABLE_ALL);
    check_onnx_status(status, "SetSessionGraphOptimizationLevel");
    
    // Add execution provider based on config
    bool ep_added = false;
    ONNXExecutionProvider effective_ep = config_.execution_provider;
    
    // Auto-detect best provider if AUTO is selected
    if (effective_ep == ONNXExecutionProvider::AUTO) {
#if RAC_COREML_EP_AVAILABLE
        effective_ep = ONNXExecutionProvider::COREML;
        RAC_LOG_INFO("ONNXDiffusion", "Auto-selecting CoreML EP for Apple Neural Engine");
#elif RAC_NNAPI_EP_AVAILABLE
        effective_ep = ONNXExecutionProvider::NNAPI;
        RAC_LOG_INFO("ONNXDiffusion", "Auto-selecting NNAPI EP for Android NPU");
#else
        effective_ep = ONNXExecutionProvider::CPU;
        RAC_LOG_INFO("ONNXDiffusion", "Auto-selecting CPU EP (no hardware acceleration available)");
#endif
    }
    
    switch (effective_ep) {
        case ONNXExecutionProvider::COREML:
#if RAC_COREML_EP_AVAILABLE
            // Add CoreML Execution Provider for Apple Neural Engine acceleration
            {
                // CoreML flags:
                // COREML_FLAG_CREATE_MLPROGRAM (1) - Create ML Program format (iOS 15+, macOS 12+)
                // COREML_FLAG_ENABLE_ON_SUBGRAPH (2) - Enable on subgraphs
                // COREML_FLAG_ONLY_ENABLE_DEVICE_WITH_ANE (4) - Only use if ANE available
                // COREML_FLAG_ONLY_ALLOW_STATIC_INPUT_SHAPES (8) - Static shapes only
                // COREML_FLAG_REQUIRE_STATIC_INPUT_SHAPES (16) - Require static shapes
                
                uint32_t coreml_flags = 0;
                // Enable on subgraphs for better operator coverage
                coreml_flags |= 2;  // COREML_FLAG_ENABLE_ON_SUBGRAPH
                
                status = OrtSessionOptionsAppendExecutionProvider_CoreML(session_options_, coreml_flags);
                if (status == nullptr) {
                    RAC_LOG_INFO("ONNXDiffusion", "CoreML EP enabled for Neural Engine acceleration (flags=%u)", coreml_flags);
                    ep_added = true;
                } else {
                    const char* error_msg = ort_api_->GetErrorMessage(status);
                    RAC_LOG_WARNING("ONNXDiffusion", "CoreML EP not available: %s (falling back to CPU)", 
                                   error_msg ? error_msg : "unknown error");
                    ort_api_->ReleaseStatus(status);
                }
            }
#else
            RAC_LOG_WARNING("ONNXDiffusion", "CoreML EP requested but not available (ORT_USE_COREML not defined)");
#endif
            break;
            
        case ONNXExecutionProvider::NNAPI:
#if RAC_NNAPI_EP_AVAILABLE
            // Add NNAPI Execution Provider for Android NPU acceleration
            {
                // NNAPI flags:
                // NNAPI_FLAG_USE_FP16 (0x001) - Use FP16 for performance
                // NNAPI_FLAG_USE_NCHW (0x002) - Use NCHW format
                // NNAPI_FLAG_CPU_DISABLED (0x004) - Disable CPU fallback
                // NNAPI_FLAG_CPU_ONLY (0x008) - Use CPU only
                
                uint32_t nnapi_flags = 0;
                nnapi_flags |= 0x001;  // NNAPI_FLAG_USE_FP16 for performance
                
                status = OrtSessionOptionsAppendExecutionProvider_Nnapi(session_options_, nnapi_flags);
                if (status == nullptr) {
                    RAC_LOG_INFO("ONNXDiffusion", "NNAPI EP enabled for NPU acceleration (flags=%u)", nnapi_flags);
                    ep_added = true;
                } else {
                    const char* error_msg = ort_api_->GetErrorMessage(status);
                    RAC_LOG_WARNING("ONNXDiffusion", "NNAPI EP not available: %s (falling back to CPU)", 
                                   error_msg ? error_msg : "unknown error");
                    ort_api_->ReleaseStatus(status);
                }
            }
#else
            RAC_LOG_WARNING("ONNXDiffusion", "NNAPI EP requested but not available (ORT_USE_NNAPI not defined)");
#endif
            break;
            
        case ONNXExecutionProvider::CUDA:
            // CUDA execution provider - would require CUDA runtime
            RAC_LOG_WARNING("ONNXDiffusion", "CUDA EP requested but not yet implemented");
            break;
            
        case ONNXExecutionProvider::DIRECTML:
            // DirectML execution provider - Windows only
            RAC_LOG_WARNING("ONNXDiffusion", "DirectML EP requested but not yet implemented");
            break;
            
        case ONNXExecutionProvider::CPU:
        case ONNXExecutionProvider::AUTO:
        default:
            RAC_LOG_INFO("ONNXDiffusion", "Using CPU execution provider");
            ep_added = true;  // CPU is always available
            break;
    }
    
    if (!ep_added) {
        RAC_LOG_INFO("ONNXDiffusion", "Falling back to CPU execution provider");
    }
    
    return true;
}

bool ONNXDiffusion::load_text_encoder(const std::string& path) {
    if (!fs::exists(path)) {
        RAC_LOG_ERROR("ONNXDiffusion", "Text encoder not found: %s", path.c_str());
        return false;
    }
    
    OrtStatus* status = ort_api_->CreateSession(
        ort_env_, path.c_str(), session_options_, &text_encoder_session_);
    
    if (!check_onnx_status(status, "LoadTextEncoder")) {
        return false;
    }
    
    RAC_LOG_DEBUG("ONNXDiffusion", "Loaded text encoder from: %s", path.c_str());
    return true;
}

bool ONNXDiffusion::load_unet(const std::string& path) {
    RAC_LOG_INFO("ONNXDiffusion", "Loading UNet from path: %s", path.c_str());
    
    if (!fs::exists(path)) {
        RAC_LOG_ERROR("ONNXDiffusion", "UNet not found: %s", path.c_str());
        return false;
    }
    
    // Check for external data files in the same directory
    // Different ONNX models use different naming conventions:
    // - weights.pb (common in HuggingFace community models)
    // - model.onnx_data (default ONNX export convention)
    fs::path model_path(path);
    fs::path model_dir = model_path.parent_path();
    fs::path weights_pb_path = model_dir / "weights.pb";
    fs::path onnx_data_path = model_dir / "model.onnx_data";
    
    std::string model_dir_str = model_dir.string();
    
    RAC_LOG_INFO("ONNXDiffusion", "UNet model directory: %s", model_dir_str.c_str());
    
    // List directory contents for debugging
    RAC_LOG_INFO("ONNXDiffusion", "Listing files in UNet directory:");
    if (fs::exists(model_dir) && fs::is_directory(model_dir)) {
        for (const auto& entry : fs::directory_iterator(model_dir)) {
            std::string filename = entry.path().filename().string();
            auto file_size = entry.is_regular_file() ? fs::file_size(entry.path()) : 0;
            RAC_LOG_INFO("ONNXDiffusion", "  - %s (%s, %llu bytes)", 
                filename.c_str(),
                entry.is_regular_file() ? "file" : "dir",
                static_cast<unsigned long long>(file_size));
        }
    } else {
        RAC_LOG_ERROR("ONNXDiffusion", "UNet model directory does not exist or is not a directory!");
    }
    
    // Check for external data - models may use either naming convention
    bool has_weights_pb = fs::exists(weights_pb_path);
    bool has_onnx_data = fs::exists(onnx_data_path);
    bool has_external_data = has_weights_pb || has_onnx_data;
    
    RAC_LOG_INFO("ONNXDiffusion", "External weights files: weights.pb=%s, model.onnx_data=%s", 
        has_weights_pb ? "YES" : "NO", 
        has_onnx_data ? "YES" : "NO");
    
    // IMPORTANT: Create symlinks/copies to ensure ONNX Runtime can find the external data
    // regardless of what filename is embedded in the ONNX model
    // iOS sandbox may prevent symlink creation, so we try symlink first, then fall back to copy
    if (has_weights_pb && !has_onnx_data) {
        // Need to create model.onnx_data -> weights.pb
        RAC_LOG_INFO("ONNXDiffusion", "Attempting to create symlink: %s -> %s",
            onnx_data_path.string().c_str(), weights_pb_path.string().c_str());
        
        std::error_code ec;
        fs::create_symlink(weights_pb_path, onnx_data_path, ec);
        
        if (ec) {
            RAC_LOG_WARNING("ONNXDiffusion", "Symlink creation failed (error %d: %s), trying hard link",
                ec.value(), ec.message().c_str());
            
            // Try hard link as fallback
            ec.clear();
            fs::create_hard_link(weights_pb_path, onnx_data_path, ec);
            
            if (ec) {
                RAC_LOG_WARNING("ONNXDiffusion", "Hard link failed (error %d: %s), trying file copy",
                    ec.value(), ec.message().c_str());
                
                // Last resort: copy the file (this will use ~500MB more disk space)
                ec.clear();
                fs::copy_file(weights_pb_path, onnx_data_path, ec);
                
                if (ec) {
                    RAC_LOG_ERROR("ONNXDiffusion", "File copy also failed (error %d: %s). External data will NOT be found!",
                        ec.value(), ec.message().c_str());
                } else {
                    RAC_LOG_INFO("ONNXDiffusion", "Successfully copied weights.pb to model.onnx_data");
                }
            } else {
                RAC_LOG_INFO("ONNXDiffusion", "Successfully created hard link: model.onnx_data -> weights.pb");
            }
        } else {
            RAC_LOG_INFO("ONNXDiffusion", "Successfully created symlink: model.onnx_data -> weights.pb");
        }
    } else if (has_onnx_data && !has_weights_pb) {
        // Need to create weights.pb -> model.onnx_data
        RAC_LOG_INFO("ONNXDiffusion", "Attempting to create symlink: %s -> %s",
            weights_pb_path.string().c_str(), onnx_data_path.string().c_str());
        
        std::error_code ec;
        fs::create_symlink(onnx_data_path, weights_pb_path, ec);
        
        if (ec) {
            RAC_LOG_WARNING("ONNXDiffusion", "Symlink creation failed (error %d: %s), trying hard link",
                ec.value(), ec.message().c_str());
            
            ec.clear();
            fs::create_hard_link(onnx_data_path, weights_pb_path, ec);
            
            if (ec) {
                RAC_LOG_WARNING("ONNXDiffusion", "Hard link failed (error %d: %s), trying file copy",
                    ec.value(), ec.message().c_str());
                
                ec.clear();
                fs::copy_file(onnx_data_path, weights_pb_path, ec);
                
                if (ec) {
                    RAC_LOG_ERROR("ONNXDiffusion", "File copy also failed (error %d: %s). External data will NOT be found!",
                        ec.value(), ec.message().c_str());
                } else {
                    RAC_LOG_INFO("ONNXDiffusion", "Successfully copied model.onnx_data to weights.pb");
                }
            } else {
                RAC_LOG_INFO("ONNXDiffusion", "Successfully created hard link: weights.pb -> model.onnx_data");
            }
        } else {
            RAC_LOG_INFO("ONNXDiffusion", "Successfully created symlink: weights.pb -> model.onnx_data");
        }
    } else if (has_weights_pb && has_onnx_data) {
        RAC_LOG_INFO("ONNXDiffusion", "Both external data files already exist, no symlink/copy needed");
    }
    
    // Verify external data files after symlink/copy creation
    if (has_external_data) {
        bool final_weights_pb = fs::exists(weights_pb_path);
        bool final_onnx_data = fs::exists(onnx_data_path);
        RAC_LOG_INFO("ONNXDiffusion", "After symlink/copy: weights.pb=%s, model.onnx_data=%s",
            final_weights_pb ? "YES" : "NO",
            final_onnx_data ? "YES" : "NO");
        
        if (final_weights_pb && final_onnx_data) {
            // Log file sizes to verify they're correct
            std::error_code ec;
            auto weights_size = fs::file_size(weights_pb_path, ec);
            auto onnx_data_size = fs::file_size(onnx_data_path, ec);
            RAC_LOG_INFO("ONNXDiffusion", "External data sizes: weights.pb=%llu bytes, model.onnx_data=%llu bytes",
                (unsigned long long)weights_size, (unsigned long long)onnx_data_size);
        } else {
            RAC_LOG_ERROR("ONNXDiffusion", "CRITICAL: External data files are missing after symlink/copy attempt!");
        }
    }
    
    if (has_external_data) {
        RAC_LOG_INFO("ONNXDiffusion", "UNet has external data files - will use CPU EP only (CoreML EP doesn't support external data)");
        
        // CoreML EP doesn't support external data files properly
        // Create a separate session options for UNet with CPU-only execution
        OrtSessionOptions* unet_options = nullptr;
        OrtStatus* status = ort_api_->CreateSessionOptions(&unet_options);
        if (!check_onnx_status(status, "CreateUNetSessionOptions")) {
            return false;
        }
        
        // Copy basic settings from main session options
        int num_threads = config_.num_threads > 0 ? config_.num_threads : 4;
        ort_api_->SetIntraOpNumThreads(unet_options, num_threads);
        
        // IMPORTANT: Disable memory pattern and CPU memory arena for external data
        // These can cause issues with external initializers on iOS
        // Memory pattern may try to reuse memory in ways incompatible with external data
        ort_api_->DisableMemPattern(unet_options);
        RAC_LOG_INFO("ONNXDiffusion", "Disabled memory pattern for UNet (external data compatibility)");
        
        // Disable CPU memory arena to avoid memory allocation issues
        ort_api_->DisableCpuMemArena(unet_options);
        RAC_LOG_INFO("ONNXDiffusion", "Disabled CPU memory arena for UNet (external data compatibility)");
        
        // Use a more conservative optimization level for models with external data
        ort_api_->SetSessionGraphOptimizationLevel(unet_options, ORT_ENABLE_BASIC);
        RAC_LOG_INFO("ONNXDiffusion", "Set basic optimization level for UNet (external data compatibility)");
        
        // Disable environment allocators for better memory control with external data
        status = ort_api_->AddSessionConfigEntry(unet_options, 
            "session.use_env_allocators", "0");
        if (status) {
            RAC_LOG_WARNING("ONNXDiffusion", "Failed to set session.use_env_allocators: %s", 
                ort_api_->GetErrorMessage(status));
            ort_api_->ReleaseStatus(status);
        }
        
        RAC_LOG_INFO("ONNXDiffusion", "Using CPU execution provider for UNet (external data not supported by CoreML EP)");
        
        // Create session with CPU-only options
        // Note: External data paths are resolved relative to the model file location.
        // We've created symlinks for both weights.pb and model.onnx_data above to ensure
        // the external data is found regardless of which filename the model references internally.
        status = ort_api_->CreateSession(
            ort_env_, path.c_str(), unet_options, &unet_session_);
        
        ort_api_->ReleaseSessionOptions(unet_options);
        
        if (!check_onnx_status(status, "LoadUNet")) {
            return false;
        }
    } else {
        // No external data, use the main session options (may include CoreML/NNAPI EP)
        RAC_LOG_INFO("ONNXDiffusion", "UNet has NO external data file - using main session options (may include CoreML/NNAPI EP)");
        OrtStatus* status = ort_api_->CreateSession(
            ort_env_, path.c_str(), session_options_, &unet_session_);
        
        if (!check_onnx_status(status, "LoadUNet")) {
            return false;
        }
    }
    
    RAC_LOG_INFO("ONNXDiffusion", "Successfully loaded UNet from: %s (external_data=%s)", 
                  path.c_str(), has_external_data ? "YES" : "NO");
    return true;
}

bool ONNXDiffusion::load_vae_decoder(const std::string& path) {
    if (!fs::exists(path)) {
        RAC_LOG_ERROR("ONNXDiffusion", "VAE decoder not found: %s", path.c_str());
        return false;
    }
    
    OrtStatus* status = ort_api_->CreateSession(
        ort_env_, path.c_str(), session_options_, &vae_decoder_session_);
    
    if (!check_onnx_status(status, "LoadVAEDecoder")) {
        return false;
    }
    
    RAC_LOG_DEBUG("ONNXDiffusion", "Loaded VAE decoder from: %s", path.c_str());
    return true;
}

bool ONNXDiffusion::load_vae_encoder(const std::string& path) {
    if (!fs::exists(path)) {
        return false;  // Optional component
    }
    
    OrtStatus* status = ort_api_->CreateSession(
        ort_env_, path.c_str(), session_options_, &vae_encoder_session_);
    
    if (!check_onnx_status(status, "LoadVAEEncoder")) {
        return false;
    }
    
    RAC_LOG_DEBUG("ONNXDiffusion", "Loaded VAE encoder from: %s", path.c_str());
    return true;
}

bool ONNXDiffusion::load_tokenizer(const std::string& dir) {
    tokenizer_ = std::make_unique<BPETokenizer>();
    
    // Try loading from tokenizer subdirectory first
    std::string tokenizer_dir = dir + "/tokenizer";
    if (fs::exists(tokenizer_dir + "/vocab.json")) {
        return tokenizer_->load_from_directory(tokenizer_dir);
    }
    
    // Try loading from model root
    if (fs::exists(dir + "/vocab.json")) {
        return tokenizer_->load_from_directory(dir);
    }
    
    RAC_LOG_ERROR("ONNXDiffusion", "Tokenizer files not found in: %s", dir.c_str());
    return false;
}

DiffusionModelVariant ONNXDiffusion::detect_model_variant(const std::string& model_dir) {
    // Try to detect from model files or config
    std::string config_path = model_dir + "/model_index.json";
    
    if (fs::exists(config_path)) {
        std::ifstream file(config_path);
        // Parse and detect variant...
    }
    
    // Default to SD 1.5
    return DiffusionModelVariant::SD_1_5;
}

// =============================================================================
// GENERATION
// =============================================================================

DiffusionResult ONNXDiffusion::generate(const DiffusionOptions& options) {
    return generate(options, nullptr);
}

DiffusionResult ONNXDiffusion::generate(const DiffusionOptions& options, 
                                        ProgressCallback progress_callback) {
    DiffusionResult result;
    auto start_time = std::chrono::high_resolution_clock::now();
    
    if (!model_loaded_) {
        result.error_message = "Model not loaded";
        return result;
    }
    
    // Verify external data files are accessible before starting generation
    // This prevents crashes during UNet inference if the weights file becomes inaccessible
    std::string external_data_error;
    if (!verify_external_data_accessible(external_data_error)) {
        result.error_message = external_data_error;
        return result;
    }
    
    cancel_requested_ = false;
    
    // Validate dimensions
    int width = options.width > 0 ? options.width : config_.default_width();
    int height = options.height > 0 ? options.height : config_.default_height();
    int steps = options.steps > 0 ? options.steps : config_.default_steps();
    
    // Ensure dimensions are multiples of 8
    width = (width / 8) * 8;
    height = (height / 8) * 8;
    
    int latent_height = height / 8;
    int latent_width = width / 8;
    
    RAC_LOG_INFO("ONNXDiffusion", "Generating %dx%d image with %d steps", 
                 width, height, steps);
    
    // Report progress: encoding
    if (progress_callback) {
        DiffusionProgress prog;
        prog.progress = 0.0f;
        prog.current_step = 0;
        prog.total_steps = steps;
        prog.stage = "encoding";
        if (!progress_callback(prog)) {
            result.error_message = "Cancelled";
            return result;
        }
    }
    
    // 1. Encode text prompts
    std::vector<float> text_embeddings = encode_prompt(options.prompt);
    if (text_embeddings.empty()) {
        result.error_message = "Failed to encode prompt";
        return result;
    }
    
    // Encode negative prompt for classifier-free guidance
    std::vector<float> uncond_embeddings = encode_prompt(
        options.negative_prompt.empty() ? "" : options.negative_prompt);
    
    if (cancel_requested_) {
        result.error_message = "Cancelled";
        return result;
    }
    
    // 2. Initialize latents
    std::vector<float> latents = generate_random_latents(
        1, LATENT_CHANNELS, latent_height, latent_width, options.seed);
    
    // Get actual seed used
    result.seed_used = options.seed >= 0 ? options.seed : 
        std::chrono::high_resolution_clock::now().time_since_epoch().count();
    
    // 3. Set up scheduler
    scheduler_->set_timesteps(steps);
    const auto& timesteps = scheduler_->get_timesteps();
    
    // Scale initial noise by init_noise_sigma
    float init_sigma = scheduler_->get_init_noise_sigma();
    latents = vector_mul(latents, init_sigma);
    
    // 4. Denoising loop
    for (int i = 0; i < steps; ++i) {
        if (cancel_requested_) {
            result.error_message = "Cancelled";
            return result;
        }
        
        float t = timesteps[i];
        
        // Report progress
        if (progress_callback) {
            DiffusionProgress prog;
            prog.progress = static_cast<float>(i) / steps;
            prog.current_step = i;
            prog.total_steps = steps;
            prog.stage = "denoising";
            if (!progress_callback(prog)) {
                result.error_message = "Cancelled";
                return result;
            }
        }
        
        // Scale model input
        std::vector<float> latent_input = scheduler_->scale_model_input(latents, t);
        
        // Run UNet for unconditional prediction
        std::vector<float> noise_pred_uncond = run_unet_step(
            latent_input, uncond_embeddings, t);
        
        // Check if UNet inference failed (returns empty vector on error)
        if (noise_pred_uncond.empty()) {
            RAC_LOG_ERROR("ONNXDiffusion", "UNet unconditional prediction failed at step %d", i);
            result.error_message = "UNet inference failed - external data file may be inaccessible";
            return result;
        }
        
        // Run UNet for conditional prediction
        std::vector<float> noise_pred_text = run_unet_step(
            latent_input, text_embeddings, t);
        
        // Check if UNet inference failed
        if (noise_pred_text.empty()) {
            RAC_LOG_ERROR("ONNXDiffusion", "UNet conditional prediction failed at step %d", i);
            result.error_message = "UNet inference failed - external data file may be inaccessible";
            return result;
        }
        
        // Apply classifier-free guidance
        std::vector<float> noise_pred = apply_guidance(
            noise_pred_uncond, noise_pred_text, options.guidance_scale);
        
        // Scheduler step
        latents = scheduler_->step(noise_pred, t, latents);
    }
    
    if (cancel_requested_) {
        result.error_message = "Cancelled";
        return result;
    }
    
    // 5. Decode latents to image
    if (progress_callback) {
        DiffusionProgress prog;
        prog.progress = 0.95f;
        prog.current_step = steps;
        prog.total_steps = steps;
        prog.stage = "decoding";
        progress_callback(prog);
    }
    
    // Scale latents before VAE
    latents = vector_mul(latents, 1.0f / VAE_SCALE_FACTOR);
    
    result.image_data = decode_latents(latents, latent_height, latent_width);
    if (result.image_data.empty()) {
        result.error_message = "Failed to decode image";
        return result;
    }
    
    result.width = width;
    result.height = height;
    result.success = true;
    
    auto end_time = std::chrono::high_resolution_clock::now();
    result.inference_time_ms = std::chrono::duration<double, std::milli>(
        end_time - start_time).count();
    
    // Final progress
    if (progress_callback) {
        DiffusionProgress prog;
        prog.progress = 1.0f;
        prog.current_step = steps;
        prog.total_steps = steps;
        prog.stage = "complete";
        progress_callback(prog);
    }
    
    RAC_LOG_INFO("ONNXDiffusion", "Generation complete in %.2f ms", 
                 result.inference_time_ms);
    
    return result;
}

void ONNXDiffusion::cancel() {
    cancel_requested_ = true;
}

// =============================================================================
// INFERENCE STEPS
// =============================================================================

std::vector<float> ONNXDiffusion::encode_prompt(const std::string& prompt) {
    if (!tokenizer_ || !text_encoder_session_) {
        return {};
    }
    
    // Tokenize
    std::vector<int32_t> tokens = tokenizer_->encode(prompt);
    
    // Create input tensor
    std::vector<int64_t> input_shape = {1, static_cast<int64_t>(tokens.size())};
    
    OrtValue* input_tensor = nullptr;
    OrtStatus* status = ort_api_->CreateTensorWithDataAsOrtValue(
        memory_info_,
        tokens.data(),
        tokens.size() * sizeof(int32_t),
        input_shape.data(),
        input_shape.size(),
        ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32,
        &input_tensor);
    
    if (!check_onnx_status(status, "CreateInputTensor")) {
        return {};
    }
    
    // Run inference
    const char* input_names[] = {"input_ids"};
    const char* output_names[] = {"last_hidden_state"};
    OrtValue* output_tensor = nullptr;
    
    status = ort_api_->Run(
        text_encoder_session_,
        nullptr,  // run options
        input_names, &input_tensor, 1,
        output_names, 1, &output_tensor);
    
    ort_api_->ReleaseValue(input_tensor);
    
    if (!check_onnx_status(status, "RunTextEncoder")) {
        return {};
    }
    
    // Extract output
    float* output_data = nullptr;
    status = ort_api_->GetTensorMutableData(output_tensor, (void**)&output_data);
    
    if (!check_onnx_status(status, "GetTensorData")) {
        ort_api_->ReleaseValue(output_tensor);
        return {};
    }
    
    // Get output shape
    OrtTensorTypeAndShapeInfo* shape_info;
    ort_api_->GetTensorTypeAndShape(output_tensor, &shape_info);
    
    size_t num_dims;
    ort_api_->GetDimensionsCount(shape_info, &num_dims);
    
    std::vector<int64_t> output_shape(num_dims);
    ort_api_->GetDimensions(shape_info, output_shape.data(), num_dims);
    
    size_t total_elements = 1;
    for (size_t i = 0; i < num_dims; ++i) {
        total_elements *= output_shape[i];
    }
    
    std::vector<float> result(output_data, output_data + total_elements);
    
    ort_api_->ReleaseTensorTypeAndShapeInfo(shape_info);
    ort_api_->ReleaseValue(output_tensor);
    
    return result;
}

std::vector<float> ONNXDiffusion::run_unet_step(const std::vector<float>& latents,
                                                const std::vector<float>& text_embeddings,
                                                float timestep) {
    if (!unet_session_) {
        return {};
    }
    
    // Determine latent dimensions from size
    // Assuming batch=1, channels=4
    size_t latent_size = latents.size();
    int latent_hw = static_cast<int>(std::sqrt(latent_size / LATENT_CHANNELS));
    
    // Create input tensors
    std::vector<int64_t> sample_shape = {1, LATENT_CHANNELS, latent_hw, latent_hw};
    std::vector<int64_t> timestep_shape = {1};
    std::vector<int64_t> encoder_shape = {1, BPETokenizer::MAX_SEQUENCE_LENGTH, TEXT_EMBEDDING_DIM};
    
    OrtValue* sample_tensor = nullptr;
    OrtValue* timestep_tensor = nullptr;
    OrtValue* encoder_tensor = nullptr;
    
    // Sample tensor
    OrtStatus* status = ort_api_->CreateTensorWithDataAsOrtValue(
        memory_info_,
        const_cast<float*>(latents.data()),
        latents.size() * sizeof(float),
        sample_shape.data(),
        sample_shape.size(),
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &sample_tensor);
    
    if (!check_onnx_status(status, "CreateSampleTensor")) {
        return {};
    }
    
    // Timestep tensor
    std::vector<float> timestep_data = {timestep};
    status = ort_api_->CreateTensorWithDataAsOrtValue(
        memory_info_,
        timestep_data.data(),
        sizeof(float),
        timestep_shape.data(),
        timestep_shape.size(),
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &timestep_tensor);
    
    if (!check_onnx_status(status, "CreateTimestepTensor")) {
        ort_api_->ReleaseValue(sample_tensor);
        return {};
    }
    
    // Encoder hidden states tensor
    status = ort_api_->CreateTensorWithDataAsOrtValue(
        memory_info_,
        const_cast<float*>(text_embeddings.data()),
        text_embeddings.size() * sizeof(float),
        encoder_shape.data(),
        encoder_shape.size(),
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &encoder_tensor);
    
    if (!check_onnx_status(status, "CreateEncoderTensor")) {
        ort_api_->ReleaseValue(sample_tensor);
        ort_api_->ReleaseValue(timestep_tensor);
        return {};
    }
    
    // Run inference
    const char* input_names[] = {"sample", "timestep", "encoder_hidden_states"};
    const char* output_names[] = {"out_sample"};
    OrtValue* input_tensors[] = {sample_tensor, timestep_tensor, encoder_tensor};
    OrtValue* output_tensor = nullptr;
    
    // Note: External data paths are resolved by ONNX Runtime relative to the model file location.
    // We've created symlinks for both weights.pb and model.onnx_data during model loading
    // to ensure the external data is found regardless of which filename the model references internally.
    status = ort_api_->Run(
        unet_session_,
        nullptr,
        input_names, input_tensors, 3,
        output_names, 1, &output_tensor);
    
    ort_api_->ReleaseValue(sample_tensor);
    ort_api_->ReleaseValue(timestep_tensor);
    ort_api_->ReleaseValue(encoder_tensor);
    
    if (!check_onnx_status(status, "RunUNet")) {
        return {};
    }
    
    // Extract output
    float* output_data = nullptr;
    status = ort_api_->GetTensorMutableData(output_tensor, (void**)&output_data);
    
    if (!check_onnx_status(status, "GetUNetOutput")) {
        ort_api_->ReleaseValue(output_tensor);
        return {};
    }
    
    std::vector<float> result(output_data, output_data + latents.size());
    ort_api_->ReleaseValue(output_tensor);
    
    return result;
}

std::vector<uint8_t> ONNXDiffusion::decode_latents(const std::vector<float>& latents,
                                                    int latent_height, int latent_width) {
    if (!vae_decoder_session_) {
        return {};
    }
    
    // Create input tensor
    std::vector<int64_t> latent_shape = {1, LATENT_CHANNELS, latent_height, latent_width};
    
    OrtValue* input_tensor = nullptr;
    OrtStatus* status = ort_api_->CreateTensorWithDataAsOrtValue(
        memory_info_,
        const_cast<float*>(latents.data()),
        latents.size() * sizeof(float),
        latent_shape.data(),
        latent_shape.size(),
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &input_tensor);
    
    if (!check_onnx_status(status, "CreateLatentTensor")) {
        return {};
    }
    
    // Run decoder
    const char* input_names[] = {"latent_sample"};
    const char* output_names[] = {"sample"};
    OrtValue* output_tensor = nullptr;
    
    status = ort_api_->Run(
        vae_decoder_session_,
        nullptr,
        input_names, &input_tensor, 1,
        output_names, 1, &output_tensor);
    
    ort_api_->ReleaseValue(input_tensor);
    
    if (!check_onnx_status(status, "RunVAEDecoder")) {
        return {};
    }
    
    // Extract output
    float* output_data = nullptr;
    status = ort_api_->GetTensorMutableData(output_tensor, (void**)&output_data);
    
    if (!check_onnx_status(status, "GetVAEOutput")) {
        ort_api_->ReleaseValue(output_tensor);
        return {};
    }
    
    // Get output shape
    OrtTensorTypeAndShapeInfo* shape_info;
    ort_api_->GetTensorTypeAndShape(output_tensor, &shape_info);
    
    size_t num_dims;
    ort_api_->GetDimensionsCount(shape_info, &num_dims);
    
    std::vector<int64_t> output_shape(num_dims);
    ort_api_->GetDimensions(shape_info, output_shape.data(), num_dims);
    
    // Expected shape: [1, 3, height, width]
    int out_height = static_cast<int>(output_shape[2]);
    int out_width = static_cast<int>(output_shape[3]);
    
    // Convert from [-1, 1] float to [0, 255] RGBA uint8
    std::vector<uint8_t> image_rgba(out_height * out_width * 4);
    
    for (int y = 0; y < out_height; ++y) {
        for (int x = 0; x < out_width; ++x) {
            int pixel_idx = y * out_width + x;
            int rgba_idx = pixel_idx * 4;
            
            // VAE output is in CHW format (channels, height, width)
            for (int c = 0; c < 3; ++c) {
                int chw_idx = c * out_height * out_width + y * out_width + x;
                float val = output_data[chw_idx];
                
                // Convert from [-1, 1] to [0, 255]
                val = (val + 1.0f) * 0.5f;
                val = std::clamp(val, 0.0f, 1.0f);
                image_rgba[rgba_idx + c] = static_cast<uint8_t>(val * 255.0f);
            }
            image_rgba[rgba_idx + 3] = 255;  // Alpha
        }
    }
    
    ort_api_->ReleaseTensorTypeAndShapeInfo(shape_info);
    ort_api_->ReleaseValue(output_tensor);
    
    return image_rgba;
}

std::vector<float> ONNXDiffusion::apply_guidance(const std::vector<float>& noise_pred_uncond,
                                                  const std::vector<float>& noise_pred_text,
                                                  float guidance_scale) {
    // CFG: noise_pred = noise_pred_uncond + guidance_scale * (noise_pred_text - noise_pred_uncond)
    std::vector<float> result(noise_pred_uncond.size());
    
    for (size_t i = 0; i < result.size(); ++i) {
        result[i] = noise_pred_uncond[i] + 
                   guidance_scale * (noise_pred_text[i] - noise_pred_uncond[i]);
    }
    
    return result;
}

// =============================================================================
// CAPABILITIES
// =============================================================================

uint32_t ONNXDiffusion::get_capabilities() const {
    uint32_t caps = 0;
    
    // Text-to-image is always supported
    caps |= (1 << 0);  // RAC_DIFFUSION_CAP_TEXT_TO_IMAGE
    
    // Image-to-image requires VAE encoder
    if (vae_encoder_session_) {
        caps |= (1 << 1);  // RAC_DIFFUSION_CAP_IMAGE_TO_IMAGE
    }
    
    return caps;
}

void ONNXDiffusion::get_max_dimensions(int* max_width, int* max_height) const {
    switch (config_.model_variant) {
        case DiffusionModelVariant::SDXL:
        case DiffusionModelVariant::SDXL_TURBO:
            *max_width = 1024;
            *max_height = 1024;
            break;
        case DiffusionModelVariant::SD_2_1:
            *max_width = 768;
            *max_height = 768;
            break;
        default:
            *max_width = 512;
            *max_height = 512;
            break;
    }
}

// =============================================================================
// UTILITY
// =============================================================================

bool ONNXDiffusion::check_onnx_status(OrtStatus* status, const char* operation) {
    if (status != nullptr) {
        const char* msg = ort_api_->GetErrorMessage(status);
        RAC_LOG_ERROR("ONNXDiffusion", "%s failed: %s", operation, msg);
        ort_api_->ReleaseStatus(status);
        return false;
    }
    return true;
}

bool ONNXDiffusion::verify_external_data_accessible(std::string& error_message) {
    // Check if UNet has external data files and verify they're accessible
    fs::path unet_dir = fs::path(model_dir_) / "unet";
    fs::path weights_pb_path = unet_dir / "weights.pb";
    fs::path onnx_data_path = unet_dir / "model.onnx_data";
    
    bool has_weights_pb = fs::exists(weights_pb_path);
    bool has_onnx_data = fs::exists(onnx_data_path);
    
    RAC_LOG_DEBUG("ONNXDiffusion", "Pre-generation check: model_dir=%s, weights.pb=%s, model.onnx_data=%s",
        model_dir_.c_str(), has_weights_pb ? "YES" : "NO", has_onnx_data ? "YES" : "NO");
    
    // If neither external data file exists, that's fine (no external data)
    if (!has_weights_pb && !has_onnx_data) {
        return true;
    }
    
    // Verify the external data file(s) are actually readable
    std::vector<fs::path> files_to_check;
    if (has_weights_pb) files_to_check.push_back(weights_pb_path);
    if (has_onnx_data) files_to_check.push_back(onnx_data_path);
    
    for (const auto& file_path : files_to_check) {
        // Try to open the file to verify it's readable
        std::ifstream test_file(file_path, std::ios::binary);
        if (!test_file.is_open()) {
            error_message = "External data file exists but cannot be opened: " + file_path.string();
            RAC_LOG_ERROR("ONNXDiffusion", "Cannot open external data file for reading: %s", file_path.c_str());
            return false;
        }
        
        // Try to read a few bytes to verify the file is actually accessible
        char buffer[16];
        test_file.read(buffer, sizeof(buffer));
        if (test_file.gcount() == 0) {
            error_message = "External data file exists but is empty or unreadable: " + file_path.string();
            RAC_LOG_ERROR("ONNXDiffusion", "External data file is empty or unreadable: %s", file_path.c_str());
            return false;
        }
        
        // Log success and file size
        std::error_code ec;
        auto file_size = fs::file_size(file_path, ec);
        RAC_LOG_INFO("ONNXDiffusion", "Verified external data file is accessible: %s (%llu bytes)", 
            file_path.c_str(), static_cast<unsigned long long>(file_size));
    }
    
    return true;
}

}  // namespace diffusion
}  // namespace runanywhere
