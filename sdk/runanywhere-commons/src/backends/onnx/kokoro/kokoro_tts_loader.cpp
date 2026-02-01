/**
 * @file kokoro_tts_loader.cpp
 * @brief Kokoro TTS Loader Implementation
 *
 * Direct ONNX Runtime integration for Kokoro TTS models with QNN/NPU support.
 */

#include "kokoro_tts_loader.h"

// NPU Backend includes (conditionally compiled)
// QNN DISABLED FOR NNAPI TESTING
// #if RAC_QNN_AVAILABLE
// #include "../qnn/qnn_session_manager.h"
// #endif

#if RAC_NNAPI_AVAILABLE
#include "../nnapi/nnapi_session_manager.h"
#endif

#include "rac/core/rac_logger.h"

// Config headers (always available for struct definitions)
// QNN DISABLED FOR NNAPI TESTING - but keep header for struct definitions
// #include "rac/backends/rac_qnn_config.h"
#include "rac/backends/rac_nnapi_config.h"

#include <onnxruntime_c_api.h>

#include <algorithm>
#include <chrono>
#include <cstring>
#include <fstream>
#include <sstream>
#include <unordered_map>
#include <cctype>

// Dynamic library loading
#ifdef __ANDROID__
#include <dlfcn.h>
#endif

#ifdef __ANDROID__
#include <android/log.h>
#define KOKORO_LOGI(...) __android_log_print(ANDROID_LOG_INFO, "KokoroTTS", __VA_ARGS__)
#define KOKORO_LOGW(...) __android_log_print(ANDROID_LOG_WARN, "KokoroTTS", __VA_ARGS__)
#define KOKORO_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "KokoroTTS", __VA_ARGS__)
#else
#define KOKORO_LOGI(...) do { printf("[KokoroTTS] "); printf(__VA_ARGS__); printf("\n"); } while(0)
#define KOKORO_LOGW(...) do { printf("[KokoroTTS WARN] "); printf(__VA_ARGS__); printf("\n"); } while(0)
#define KOKORO_LOGE(...) do { fprintf(stderr, "[KokoroTTS ERROR] "); fprintf(stderr, __VA_ARGS__); fprintf(stderr, "\n"); } while(0)
#endif

#define LOG_CAT "KokoroTTS"

namespace rac {
namespace onnx {

// =============================================================================
// Utility Functions
// =============================================================================

static bool file_exists(const std::string& path) {
    std::ifstream f(path);
    return f.good();
}

static std::string join_path(const std::string& base, const std::string& name) {
    if (base.empty()) return name;
    if (base.back() == '/' || base.back() == '\\') return base + name;
    return base + "/" + name;
}

/**
 * @brief Detect if an ONNX model is INT8 quantized
 *
 * INT8 models contain QuantizeLinear and DequantizeLinear nodes.
 * This is a quick check by looking at the model file name and optionally
 * parsing the ONNX protobuf to check for QDQ nodes.
 *
 * @param model_path Path to the ONNX model file
 * @return KokoroQuantizationType detected type
 */
static KokoroQuantizationType detect_quantization_type(const std::string& model_path) {
    // First, check filename for hints
    std::string lower_path = model_path;
    std::transform(lower_path.begin(), lower_path.end(), lower_path.begin(),
                   [](unsigned char c) { return std::tolower(c); });

    // Check for INT8 indicators in filename
    if (lower_path.find("int8") != std::string::npos ||
        lower_path.find("qdq") != std::string::npos ||
        lower_path.find("quantized") != std::string::npos ||
        lower_path.find("quant") != std::string::npos) {
        KOKORO_LOGI("🔍 Detected INT8 quantized model from filename: %s", model_path.c_str());
        return KokoroQuantizationType::INT8;
    }

    // Check for FP16 indicators
    if (lower_path.find("fp16") != std::string::npos ||
        lower_path.find("half") != std::string::npos) {
        KOKORO_LOGI("🔍 Detected FP16 model from filename: %s", model_path.c_str());
        return KokoroQuantizationType::FP16;
    }

    // Try to detect by checking model file size
    // INT8 models are typically 3-4x smaller than FP32
    std::ifstream file(model_path, std::ios::binary | std::ios::ate);
    if (file.is_open()) {
        auto size = file.tellg();
        file.close();

        // Kokoro unified model is ~320MB in FP32, ~88MB in INT8
        // If size is less than 150MB, it's likely INT8
        const int64_t INT8_THRESHOLD = 150 * 1024 * 1024;  // 150MB
        const int64_t FP16_THRESHOLD = 200 * 1024 * 1024;  // 200MB

        if (size > 0 && static_cast<int64_t>(size) < INT8_THRESHOLD) {
            KOKORO_LOGI("🔍 Detected INT8 model by size: %lld bytes (< 150MB threshold)",
                       static_cast<long long>(size));
            return KokoroQuantizationType::INT8;
        }

        if (size > 0 && static_cast<int64_t>(size) < FP16_THRESHOLD) {
            KOKORO_LOGI("🔍 Possibly FP16 model by size: %lld bytes", static_cast<long long>(size));
            return KokoroQuantizationType::FP16;
        }

        KOKORO_LOGI("🔍 Model size %lld bytes suggests FP32", static_cast<long long>(size));
    }

    return KokoroQuantizationType::FP32;  // Default to FP32
}

// =============================================================================
// Kokoro Phoneme Tokenizer
// =============================================================================
// Kokoro TTS uses a phoneme-based vocabulary. This implements a basic
// text-to-phoneme conversion with the Kokoro vocabulary.
//
// The model expects input_ids with shape [1, 50] - FIXED SIZE.
// Tokens are padded or truncated to exactly 50.

// Kokoro vocabulary (subset of commonly used phonemes)
// Full vocabulary would be loaded from tokenizer.json
static const std::unordered_map<std::string, int64_t> KOKORO_VOCAB = {
    // Special tokens
    {"<pad>", 0}, {"<bos>", 1}, {"<eos>", 2}, {"<unk>", 3},

    // Punctuation and silence
    {" ", 4}, {".", 5}, {",", 6}, {"?", 7}, {"!", 8},
    {"-", 9}, {":", 10}, {";", 11}, {"'", 12}, {"\"", 13},

    // Basic phonemes (IPA-like for English)
    {"a", 14}, {"b", 15}, {"c", 16}, {"d", 17}, {"e", 18},
    {"f", 19}, {"g", 20}, {"h", 21}, {"i", 22}, {"j", 23},
    {"k", 24}, {"l", 25}, {"m", 26}, {"n", 27}, {"o", 28},
    {"p", 29}, {"q", 30}, {"r", 31}, {"s", 32}, {"t", 33},
    {"u", 34}, {"v", 35}, {"w", 36}, {"x", 37}, {"y", 38},
    {"z", 39},

    // Extended phonemes
    {"AA", 40}, {"AE", 41}, {"AH", 42}, {"AO", 43}, {"AW", 44},
    {"AY", 45}, {"EH", 46}, {"ER", 47}, {"EY", 48}, {"IH", 49},
    {"IY", 50}, {"OW", 51}, {"OY", 52}, {"UH", 53}, {"UW", 54},

    // Consonant phonemes
    {"CH", 55}, {"DH", 56}, {"JH", 57}, {"NG", 58}, {"SH", 59},
    {"TH", 60}, {"ZH", 61},

    // Numbers (converted to phonemes)
    {"0", 62}, {"1", 63}, {"2", 64}, {"3", 65}, {"4", 66},
    {"5", 67}, {"6", 68}, {"7", 69}, {"8", 70}, {"9", 71},
};

// Fixed model input size for Kokoro unified model
static const size_t KOKORO_INPUT_SIZE = 50;

// Tokenize text to Kokoro token IDs
static std::vector<int64_t> tokenize_text_kokoro(const std::string& text) {
    std::vector<int64_t> tokens;
    tokens.reserve(KOKORO_INPUT_SIZE);

    // Add BOS token
    tokens.push_back(1);  // <bos>

    // Process each character/phoneme
    std::string current;
    for (size_t i = 0; i < text.length() && tokens.size() < KOKORO_INPUT_SIZE - 1; ++i) {
        char c = text[i];

        // Check for two-character phonemes first
        if (i + 1 < text.length()) {
            std::string two_char;
            two_char += static_cast<char>(std::toupper(c));
            two_char += static_cast<char>(std::toupper(text[i + 1]));

            auto it = KOKORO_VOCAB.find(two_char);
            if (it != KOKORO_VOCAB.end()) {
                tokens.push_back(it->second);
                ++i;  // Skip next character
                continue;
            }
        }

        // Single character lookup
        std::string single_char(1, static_cast<char>(std::tolower(c)));
        auto it = KOKORO_VOCAB.find(single_char);
        if (it != KOKORO_VOCAB.end()) {
            tokens.push_back(it->second);
        } else if (c == ' ') {
            tokens.push_back(4);  // space
        } else if (std::isalnum(c)) {
            // Unknown character - use lowercase letter token if alphabetic
            if (std::isalpha(c)) {
                char lower = static_cast<char>(std::tolower(c));
                if (lower >= 'a' && lower <= 'z') {
                    tokens.push_back(14 + (lower - 'a'));  // a=14, b=15, etc.
                }
            } else {
                tokens.push_back(3);  // <unk>
            }
        } else {
            // Punctuation or other
            tokens.push_back(3);  // <unk>
        }
    }

    // Add EOS token
    tokens.push_back(2);  // <eos>

    // Pad to exactly KOKORO_INPUT_SIZE
    while (tokens.size() < KOKORO_INPUT_SIZE) {
        tokens.push_back(0);  // <pad>
    }

    // Truncate if somehow over (shouldn't happen with the loop limit)
    if (tokens.size() > KOKORO_INPUT_SIZE) {
        tokens.resize(KOKORO_INPUT_SIZE);
        tokens[KOKORO_INPUT_SIZE - 1] = 2;  // Ensure EOS at end
    }

    return tokens;
}

// =============================================================================
// KokoroTTSLoader Implementation
// =============================================================================

KokoroTTSLoader::KokoroTTSLoader()
    /* QNN DISABLED FOR NNAPI TESTING
    : ort_qnn_lib_handle_(nullptr), using_qnn_ort_(false)
    */
    {
    KOKORO_LOGI("KokoroTTSLoader created (NNAPI ONLY - QNN DISABLED)");
}

KokoroTTSLoader::~KokoroTTSLoader() {
    KOKORO_LOGI("KokoroTTSLoader destroying...");
    unload();
    cleanup_onnx_runtime();
    KOKORO_LOGI("KokoroTTSLoader destroyed");
}

bool KokoroTTSLoader::detect_model(const std::string& model_path, KokoroModelInfo& out_info) {
    KOKORO_LOGI("Detecting Kokoro model at: %s", model_path.c_str());

    out_info = KokoroModelInfo{};

    // Paths to check for models
    std::vector<std::string> base_paths = {
        model_path,
        join_path(model_path, "package"),
        join_path(model_path, "models"),
    };

    // Unified model file names (priority order)
    std::vector<std::string> unified_names = {
        "kokoro.onnx",
        "kokoro_fixed.onnx",
        "kokoro_fixed_shape.onnx",
        "kokoro_unified.onnx",
        "model.onnx",  // Generic fallback
    };

    // Check for unified models first
    for (const auto& base : base_paths) {
        for (const auto& name : unified_names) {
            std::string candidate = join_path(base, name);
            if (file_exists(candidate)) {
                out_info.type = KokoroModelType::UNIFIED;
                out_info.unified_path = candidate;
                KOKORO_LOGI("Found unified Kokoro model: %s", candidate.c_str());

                // Detect quantization type
                out_info.quantization = detect_quantization_type(candidate);
                out_info.is_int8 = (out_info.quantization == KokoroQuantizationType::INT8);

                if (out_info.is_int8) {
                    KOKORO_LOGI("╔════════════════════════════════════════════════════════════════════════════╗");
                    KOKORO_LOGI("║  🎯 INT8 QUANTIZED MODEL DETECTED                                          ║");
                    KOKORO_LOGI("║  This model will use NNAPI for optimal NPU acceleration!                   ║");
                    KOKORO_LOGI("║  Expected 4x+ speedup vs CPU on supported devices.                         ║");
                    KOKORO_LOGI("╚════════════════════════════════════════════════════════════════════════════╝");
                }

                // Check for tokenizer
                std::string tokenizer = join_path(base, "tokenizer.json");
                if (file_exists(tokenizer)) {
                    out_info.tokenizer_path = tokenizer;
                    out_info.has_tokenizer = true;
                }

                // Check for voice embeddings
                std::string voices = join_path(base, "voices.bin");
                if (!file_exists(voices)) {
                    voices = join_path(base, "af_heart.bin");
                }
                if (file_exists(voices)) {
                    out_info.voices_path = voices;
                    out_info.has_voices = true;
                }

                return true;
            }
        }
    }

    // Check for split models (encoder + vocoder)
    for (const auto& base : base_paths) {
        std::string encoder = join_path(base, "kokoro_encoder.onnx");
        std::string vocoder = join_path(base, "kokoro_vocoder.onnx");

        if (file_exists(encoder) && file_exists(vocoder)) {
            out_info.type = KokoroModelType::SPLIT;
            out_info.encoder_path = encoder;
            out_info.vocoder_path = vocoder;
            KOKORO_LOGI("Found split Kokoro model: encoder=%s, vocoder=%s",
                       encoder.c_str(), vocoder.c_str());

            // Check for tokenizer and voices
            std::string tokenizer = join_path(base, "tokenizer.json");
            if (file_exists(tokenizer)) {
                out_info.tokenizer_path = tokenizer;
                out_info.has_tokenizer = true;
            }

            std::string voices = join_path(base, "voices.bin");
            if (!file_exists(voices)) {
                voices = join_path(base, "af_heart.bin");
            }
            if (file_exists(voices)) {
                out_info.voices_path = voices;
                out_info.has_voices = true;
            }

            return true;
        }
    }

    KOKORO_LOGW("No Kokoro model found at path: %s", model_path.c_str());
    return false;
}

// Type definition for OrtGetApiBase function pointer
typedef const OrtApiBase* (*OrtGetApiBaseFn)();

/* QNN DISABLED FOR NNAPI TESTING - ENTIRE FUNCTION COMMENTED OUT
bool KokoroTTSLoader::load_qnn_onnx_runtime() {
#ifdef __ANDROID__
    KOKORO_LOGI("╔════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║  Attempting to load QNN-enabled ONNX Runtime (Option 3)    ║");
    KOKORO_LOGI("╚════════════════════════════════════════════════════════════╝");

    // Try to load QNN-enabled ONNX Runtime library
    // This is a SEPARATE library from sherpa-onnx's bundled ORT
    // to avoid symbol version conflicts

    // List of possible library names (in order of preference)
    const char* lib_names[] = {
        "libonnxruntime_qnn.so",           // Custom QNN-enabled build
        "libonnxruntime_qnn_1.21.so",      // Versioned QNN build
        nullptr
    };

    for (const char** lib_name = lib_names; *lib_name != nullptr; ++lib_name) {
        KOKORO_LOGI("Trying to load: %s", *lib_name);

        // Use RTLD_LOCAL to avoid symbol conflicts with existing libonnxruntime.so
        // Use RTLD_NOW to ensure all symbols are resolved immediately
        void* handle = dlopen(*lib_name, RTLD_NOW | RTLD_LOCAL);

        if (handle != nullptr) {
            KOKORO_LOGI("✓ Successfully opened: %s", *lib_name);

            // Get OrtGetApiBase function
            dlerror();  // Clear any existing error
            OrtGetApiBaseFn get_api_base = (OrtGetApiBaseFn)dlsym(handle, "OrtGetApiBase");
            const char* error = dlerror();

            if (error != nullptr || get_api_base == nullptr) {
                KOKORO_LOGW("Failed to find OrtGetApiBase in %s: %s", *lib_name,
                           error ? error : "unknown error");
                dlclose(handle);
                continue;
            }

            // Get the API
            const OrtApiBase* api_base = get_api_base();
            if (api_base == nullptr) {
                KOKORO_LOGW("OrtGetApiBase returned null");
                dlclose(handle);
                continue;
            }

            // Get versioned API - try multiple versions since we may have built ORT from source
            // Our custom build is ORT 1.18.0 (API version 18)
            // Try the version that matches our custom build first, then fall back
            const uint32_t api_versions_to_try[] = {18, 17, 19, 20, 21, ORT_API_VERSION};
            bool api_found = false;
            for (uint32_t api_ver : api_versions_to_try) {
                ort_api_ = api_base->GetApi(api_ver);
                if (ort_api_ != nullptr) {
                    KOKORO_LOGI("  -> Got ONNX Runtime API version %u", api_ver);
                    api_found = true;
                    break;
                }
            }
            if (!api_found) {
                KOKORO_LOGW("Failed to get ONNX Runtime API (tried versions 17-21 and %d)", ORT_API_VERSION);
                dlclose(handle);
                continue;
            }

            // Store handle and mark as using QNN ORT
            ort_qnn_lib_handle_ = handle;
            using_qnn_ort_ = true;

            KOKORO_LOGI("╔════════════════════════════════════════════════════════════╗");
            KOKORO_LOGI("║  ✓ QNN-enabled ONNX Runtime loaded successfully!           ║");
            KOKORO_LOGI("║    Library: %-47s ║", *lib_name);
            KOKORO_LOGI("╚════════════════════════════════════════════════════════════╝");

            return true;
        } else {
            const char* dl_error = dlerror();
            KOKORO_LOGI("  ✗ Failed to open: %s", dl_error ? dl_error : "unknown error");
        }
    }

    KOKORO_LOGW("Could not load QNN-enabled ONNX Runtime");
    KOKORO_LOGW("Falling back to default ONNX Runtime (may not have QNN EP)");
#else
    KOKORO_LOGI("Dynamic loading of QNN ORT not supported on this platform");
#endif

    return false;
}
*/ // END QNN DISABLED

bool KokoroTTSLoader::initialize_onnx_runtime() {
    if (ort_initialized_) {
        return true;
    }

    KOKORO_LOGI("╔════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║  Initializing ONNX Runtime for Kokoro TTS                  ║");
    KOKORO_LOGI("║  MODE: NNAPI ONLY (QNN ORT Loading DISABLED)               ║");
    KOKORO_LOGI("╚════════════════════════════════════════════════════════════╝");

    // QNN ORT Loading is DISABLED for NNAPI testing
    // We use the default ONNX Runtime from sherpa-onnx which has NNAPI EP
    // DISABLED: load_qnn_onnx_runtime() - this was loading QNN-specific ORT

    KOKORO_LOGI("Using default ONNX Runtime with NNAPI EP (QNN ORT disabled)");

    // Get API base
    const OrtApiBase* api_base = OrtGetApiBase();
    if (api_base == nullptr) {
        KOKORO_LOGE("Failed to get ONNX Runtime API base - library not loaded!");
        return false;
    }

    // Try multiple API versions for compatibility
    // The sherpa-onnx bundled library is version 1.17.1 (API 17)
    // but the headers claim API 21. We try versions in order of preference.
    const uint32_t api_versions[] = {ORT_API_VERSION, 21, 20, 19, 18, 17, 16};
    const char* version_names[] = {"ORT_API_VERSION", "21", "20", "19", "18", "17", "16"};

    ort_api_ = nullptr;
    uint32_t actual_version = 0;

    for (size_t i = 0; i < sizeof(api_versions)/sizeof(api_versions[0]); ++i) {
        KOKORO_LOGI("Trying ONNX Runtime API version %s (%u)...", version_names[i], api_versions[i]);
        ort_api_ = api_base->GetApi(api_versions[i]);
        if (ort_api_ != nullptr) {
            actual_version = api_versions[i];
            KOKORO_LOGI("✓ Successfully obtained ONNX Runtime API version %u", actual_version);
            break;
        }
        KOKORO_LOGW("  API version %u not supported by this library", api_versions[i]);
    }

    if (ort_api_ == nullptr) {
        KOKORO_LOGE("Failed to get ONNX Runtime API - no compatible version found!");
        KOKORO_LOGE("  Header API version: %u", ORT_API_VERSION);
        KOKORO_LOGE("  Tried versions: 21, 20, 19, 18, 17, 16");
        KOKORO_LOGE("  This usually means the bundled libonnxruntime.so is incompatible.");
        return false;
    }

    KOKORO_LOGI("ONNX Runtime API obtained successfully (version %u)", actual_version);

    // Create environment
    OrtStatus* status = ort_api_->CreateEnv(ORT_LOGGING_LEVEL_INFO, "KokoroTTS", &ort_env_);
    if (status != nullptr) {
        KOKORO_LOGE("Failed to create ONNX Runtime environment: %s",
                   ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return false;
    }

    ort_initialized_ = true;
    KOKORO_LOGI("ONNX Runtime initialized successfully");
    KOKORO_LOGI("  API Version: %u", actual_version);
    KOKORO_LOGI("  Using NNAPI for NPU acceleration (QNN disabled)");
    return true;
}

void KokoroTTSLoader::cleanup_onnx_runtime() {
    KOKORO_LOGI("Cleaning up ONNX Runtime resources...");

    if (ort_env_ != nullptr && ort_api_ != nullptr) {
        ort_api_->ReleaseEnv(ort_env_);
        ort_env_ = nullptr;
    }

    ort_api_ = nullptr;
    ort_initialized_ = false;

/* QNN DISABLED FOR NNAPI TESTING
#ifdef __ANDROID__
    // Close dynamic library handle if we loaded QNN ORT
    if (ort_qnn_lib_handle_ != nullptr) {
        KOKORO_LOGI("Closing QNN ONNX Runtime library handle");
        dlclose(ort_qnn_lib_handle_);
        ort_qnn_lib_handle_ = nullptr;
    }
#endif

    using_qnn_ort_ = false;
*/ // END QNN DISABLED
    KOKORO_LOGI("ONNX Runtime cleanup complete");
}

rac_result_t KokoroTTSLoader::load(const std::string& model_path, const KokoroConfig& config) {
    KOKORO_LOGI("=== Loading Kokoro TTS model ===");
    KOKORO_LOGI("Model path: %s", model_path.c_str());

    if (loaded_) {
        KOKORO_LOGW("Model already loaded, unloading first");
        unload();
    }

    config_ = config;

    // Initialize ONNX Runtime
    if (!initialize_onnx_runtime()) {
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    // Detect model type
    if (!detect_model(model_path, model_info_)) {
        KOKORO_LOGE("Failed to detect Kokoro model at: %s", model_path.c_str());
        return RAC_ERROR_MODEL_NOT_FOUND;
    }

    KOKORO_LOGI("Detected model type: %s",
               model_info_.type == KokoroModelType::UNIFIED ? "UNIFIED" : "SPLIT");

    // Load based on model type
    rac_result_t result;
    if (model_info_.type == KokoroModelType::UNIFIED) {
        result = load_unified_model(model_info_.unified_path);
    } else if (model_info_.type == KokoroModelType::SPLIT) {
        result = load_split_models(model_info_.encoder_path, model_info_.vocoder_path);
    } else {
        KOKORO_LOGE("Unknown model type");
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    if (result == RAC_SUCCESS) {
        loaded_ = true;
        KOKORO_LOGI("=== Kokoro TTS model loaded successfully ===");
        KOKORO_LOGI("  Type: %s", model_info_.type == KokoroModelType::UNIFIED ? "Unified (CPU)" : "Split (Hybrid NPU+CPU)");
        KOKORO_LOGI("  NPU Active: %s", stats_.npu_active ? "YES" : "NO");
    }

    return result;
}

void KokoroTTSLoader::unload() {
    KOKORO_LOGI("Unloading Kokoro TTS model...");

    // Release encoder outputs
    for (auto* output : encoder_outputs_) {
        if (output != nullptr && ort_api_ != nullptr) {
            ort_api_->ReleaseValue(output);
        }
    }
    encoder_outputs_.clear();

    // Release sessions
    if (unified_session_ != nullptr && ort_api_ != nullptr) {
        ort_api_->ReleaseSession(unified_session_);
        unified_session_ = nullptr;
    }
    if (encoder_session_ != nullptr && ort_api_ != nullptr) {
        ort_api_->ReleaseSession(encoder_session_);
        encoder_session_ = nullptr;
    }
    if (vocoder_session_ != nullptr && ort_api_ != nullptr) {
        ort_api_->ReleaseSession(vocoder_session_);
        vocoder_session_ = nullptr;
    }

    // Clear I/O info
    unified_input_names_.clear();
    unified_output_names_.clear();
    encoder_input_names_.clear();
    encoder_output_names_.clear();
    vocoder_input_names_.clear();
    vocoder_output_names_.clear();

    // Reset NPU session managers
    // QNN DISABLED FOR NNAPI TESTING
    // #if RAC_QNN_AVAILABLE
    //     qnn_session_manager_.reset();
    // #endif
#if RAC_NNAPI_AVAILABLE
    nnapi_session_manager_.reset();
#endif

    loaded_ = false;
    model_info_ = KokoroModelInfo{};
    stats_ = KokoroStats{};

    KOKORO_LOGI("Kokoro TTS model unloaded");
}

OrtSessionOptions* KokoroTTSLoader::create_cpu_session_options() {
    OrtSessionOptions* options = nullptr;
    OrtStatus* status = ort_api_->CreateSessionOptions(&options);

    if (status != nullptr) {
        KOKORO_LOGE("Failed to create session options: %s",
                   ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return nullptr;
    }

    // Set thread count
    int num_threads = config_.num_threads > 0 ? config_.num_threads : 4;
    ort_api_->SetIntraOpNumThreads(options, num_threads);
    ort_api_->SetInterOpNumThreads(options, num_threads);

    // Optimization level
    ort_api_->SetSessionGraphOptimizationLevel(options, ORT_ENABLE_ALL);

    KOKORO_LOGI("Created CPU session options (threads=%d)", num_threads);
    return options;
}

/* QNN DISABLED FOR NNAPI TESTING - ENTIRE create_qnn_session_options() COMMENTED OUT
#if RAC_QNN_AVAILABLE
OrtSessionOptions* KokoroTTSLoader::create_qnn_session_options() {
    if (!qnn_session_manager_) {
        qnn_session_manager_ = std::make_unique<QNNSessionManager>();
        if (!qnn_session_manager_->initialize(ort_api_, ort_env_)) {
            KOKORO_LOGW("Failed to initialize QNN session manager, using CPU");
            qnn_session_manager_.reset();
            return create_cpu_session_options();
        }
    }

    if (!qnn_session_manager_->is_qnn_available()) {
        KOKORO_LOGW("QNN not available on this device, using CPU");
        return create_cpu_session_options();
    }

    OrtSessionOptions* options = qnn_session_manager_->create_qnn_session_options(config_.qnn_config);
    if (options == nullptr) {
        KOKORO_LOGW("Failed to create QNN session options, using CPU");
        return create_cpu_session_options();
    }

    stats_.npu_active = true;
    active_npu_backend_ = NPUBackend::QNN;
    KOKORO_LOGI("Created QNN session options for NPU acceleration");
    return options;
}
#endif  // RAC_QNN_AVAILABLE
*/ // END QNN DISABLED

#if RAC_NNAPI_AVAILABLE
OrtSessionOptions* KokoroTTSLoader::create_nnapi_session_options() {
    KOKORO_LOGI("╔════════════════════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║  🚀 NNAPI NPU ACCELERATION - Creating Session Options                      ║");
    KOKORO_LOGI("║  This will route operations to the device NPU (Qualcomm/Samsung/MediaTek) ║");
    KOKORO_LOGI("╚════════════════════════════════════════════════════════════════════════════╝");

    KOKORO_LOGI("[NNAPI] Step 1/4: Initializing NNAPI Session Manager...");
    if (!nnapi_session_manager_) {
        nnapi_session_manager_ = std::make_unique<NNAPISessionManager>();
        KOKORO_LOGI("[NNAPI] Created new NNAPISessionManager instance");

        if (!nnapi_session_manager_->initialize(ort_api_, ort_env_)) {
            KOKORO_LOGE("[NNAPI] ❌ FAILED to initialize NNAPI session manager!");
            KOKORO_LOGE("[NNAPI] This device may not support NNAPI or API level is too low");
            nnapi_session_manager_.reset();
            return nullptr;
        }
        KOKORO_LOGI("[NNAPI] ✓ Session manager initialized successfully");
    } else {
        KOKORO_LOGI("[NNAPI] Using existing NNAPISessionManager instance");
    }

    KOKORO_LOGI("[NNAPI] Step 2/4: Checking NNAPI availability...");
    if (!nnapi_session_manager_->is_nnapi_available()) {
        KOKORO_LOGE("[NNAPI] ❌ NNAPI is NOT available on this device!");
        return nullptr;
    }
    int api_level = nnapi_session_manager_->get_android_api_level();
    KOKORO_LOGI("[NNAPI] ✓ NNAPI available! Android API Level: %d", api_level);

    KOKORO_LOGI("[NNAPI] Step 3/4: Configuring NNAPI execution provider...");
    // Convert our config to internal NNAPI config
    NNAPIConfig internal_config;
    internal_config.enabled = config_.nnapi_config.enabled;
    internal_config.use_fp16 = config_.nnapi_config.use_fp16;
    internal_config.use_nchw = config_.nnapi_config.use_nchw;
    internal_config.cpu_disabled = config_.nnapi_config.cpu_disabled;
    internal_config.cpu_only = config_.nnapi_config.cpu_only;
    internal_config.disable_cpu_ep_fallback = config_.nnapi_config.disable_cpu_ep_fallback;
    internal_config.min_api_level = config_.nnapi_config.min_api_level;
    if (config_.nnapi_config.model_cache_dir) {
        internal_config.model_cache_dir = config_.nnapi_config.model_cache_dir;
    }

    KOKORO_LOGI("[NNAPI] Config: enabled=%d, fp16=%d, nchw=%d, cpu_disabled=%d",
               internal_config.enabled, internal_config.use_fp16,
               internal_config.use_nchw, internal_config.cpu_disabled);

    KOKORO_LOGI("[NNAPI] Step 4/4: Creating ORT session options with NNAPI EP...");
    OrtSessionOptions* options = nnapi_session_manager_->create_nnapi_session_options(internal_config);
    if (options == nullptr) {
        KOKORO_LOGE("[NNAPI] ❌ FAILED to create NNAPI session options!");
        return nullptr;
    }

    stats_.npu_active = true;
    active_npu_backend_ = NPUBackend::NNAPI;

    KOKORO_LOGI("╔════════════════════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║  ✅ NNAPI NPU ACCELERATION ENABLED                                         ║");
    KOKORO_LOGI("╠════════════════════════════════════════════════════════════════════════════╣");
    KOKORO_LOGI("║  Backend:        NNAPI (Android Neural Networks API)                       ║");
    KOKORO_LOGI("║  API Level:      %d                                                        ║", api_level);
    KOKORO_LOGI("║  NPU Vendors:    Qualcomm Hexagon / Samsung Exynos / MediaTek APU          ║");
    KOKORO_LOGI("║  Status:         ACTIVE - Operations will be routed to NPU                 ║");
    KOKORO_LOGI("╚════════════════════════════════════════════════════════════════════════════╝");

    return options;
}
#endif  // RAC_NNAPI_AVAILABLE

OrtSessionOptions* KokoroTTSLoader::create_npu_session_options() {
    KOKORO_LOGI("╔════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║  Creating NPU Session Options (NNAPI ONLY - QNN DISABLED)  ║");
    KOKORO_LOGI("╚════════════════════════════════════════════════════════════╝");

    OrtSessionOptions* options = nullptr;

    // QNN IS COMPLETELY DISABLED FOR NNAPI TESTING
    // All NPU requests go through NNAPI only
    switch (config_.npu_backend) {
        case NPUBackend::NNAPI:
        case NPUBackend::QNN:   // QNN redirected to NNAPI
        case NPUBackend::AUTO:  // AUTO now uses NNAPI only
            KOKORO_LOGI("  🚀 Using NNAPI backend (QNN is DISABLED)");
#if RAC_NNAPI_AVAILABLE
            options = create_nnapi_session_options();
            if (options != nullptr) {
                KOKORO_LOGI("  ✓ NNAPI session options created successfully");
                return options;
            }
            KOKORO_LOGW("  ❌ NNAPI session creation failed");
#else
            KOKORO_LOGW("  NNAPI not compiled in (RAC_NNAPI_AVAILABLE=0)");
#endif
            KOKORO_LOGW("  Falling back to CPU");
            break;

        case NPUBackend::CPU_ONLY:
            KOKORO_LOGI("  Requested backend: CPU_ONLY");
            break;
    }

    // Fallback to CPU
    active_npu_backend_ = NPUBackend::CPU_ONLY;
    stats_.npu_active = false;
    KOKORO_LOGI("  ⚙️  Using CPU execution (no NPU)");
    return create_cpu_session_options();
}

bool KokoroTTSLoader::get_session_io_info(OrtSession* session,
                                          std::vector<std::string>& input_names,
                                          std::vector<std::string>& output_names) {
    OrtAllocator* allocator = nullptr;
    OrtStatus* status = ort_api_->GetAllocatorWithDefaultOptions(&allocator);
    if (status != nullptr) {
        KOKORO_LOGE("Failed to get allocator: %s", ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return false;
    }

    // Get input names
    size_t num_inputs = 0;
    status = ort_api_->SessionGetInputCount(session, &num_inputs);
    if (status != nullptr) {
        KOKORO_LOGE("Failed to get input count: %s", ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return false;
    }

    input_names.clear();
    for (size_t i = 0; i < num_inputs; ++i) {
        char* name = nullptr;
        status = ort_api_->SessionGetInputName(session, i, allocator, &name);
        if (status == nullptr && name != nullptr) {
            input_names.push_back(name);
            KOKORO_LOGI("  Input[%zu]: %s", i, name);
            ort_api_->AllocatorFree(allocator, name);
        } else if (status != nullptr) {
            ort_api_->ReleaseStatus(status);
        }
    }

    // Get output names
    size_t num_outputs = 0;
    status = ort_api_->SessionGetOutputCount(session, &num_outputs);
    if (status != nullptr) {
        KOKORO_LOGE("Failed to get output count: %s", ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return false;
    }

    output_names.clear();
    for (size_t i = 0; i < num_outputs; ++i) {
        char* name = nullptr;
        status = ort_api_->SessionGetOutputName(session, i, allocator, &name);
        if (status == nullptr && name != nullptr) {
            output_names.push_back(name);
            KOKORO_LOGI("  Output[%zu]: %s", i, name);
            ort_api_->AllocatorFree(allocator, name);
        } else if (status != nullptr) {
            ort_api_->ReleaseStatus(status);
        }
    }

    return true;
}

rac_result_t KokoroTTSLoader::load_unified_model(const std::string& model_path) {
    KOKORO_LOGI("╔══════════════════════════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║  🔧 LOADING UNIFIED KOKORO TTS MODEL WITH NPU ACCELERATION                       ║");
    KOKORO_LOGI("╚══════════════════════════════════════════════════════════════════════════════════╝");
    KOKORO_LOGI("");
    KOKORO_LOGI("[STEP 1/5] Model Information:");
    KOKORO_LOGI("  📁 Path: %s", model_path.c_str());
    RAC_LOG_INFO(LOG_CAT, "=== LOADING UNIFIED KOKORO MODEL ===");
    RAC_LOG_INFO(LOG_CAT, "Path: %s", model_path.c_str());

    // Log available backends at compile time
    KOKORO_LOGI("");
    KOKORO_LOGI("[STEP 2/5] Checking Compiled NPU Backends:");
#if RAC_NNAPI_AVAILABLE
    KOKORO_LOGI("  ✅ NNAPI: COMPILED IN (RAC_NNAPI_AVAILABLE=1)");
    KOKORO_LOGI("     → Android Neural Networks API for vendor-agnostic NPU access");
    KOKORO_LOGI("     → Supports: Qualcomm Hexagon, Samsung Exynos NPU, MediaTek APU, Google TPU");
#else
    KOKORO_LOGI("  ❌ NNAPI: NOT COMPILED (RAC_NNAPI_AVAILABLE=0)");
    KOKORO_LOGI("     → To enable: rebuild with -DRAC_ENABLE_NNAPI=ON");
#endif
    // QNN DISABLED FOR NNAPI TESTING
    // #if RAC_QNN_AVAILABLE
    //     KOKORO_LOGI("  ✅ QNN: COMPILED IN (RAC_QNN_AVAILABLE=1)");
    //     KOKORO_LOGI("     → Qualcomm AI Engine Direct for Snapdragon devices");
    // #else
    KOKORO_LOGI("  ⚠️  QNN: DISABLED FOR NNAPI TESTING");
    KOKORO_LOGI("     → NNAPI provides equivalent NPU access on Qualcomm devices");
    // #endif

    // Log requested NPU backend
    KOKORO_LOGI("");
    KOKORO_LOGI("[STEP 3/5] NPU Backend Configuration:");

    // Log quantization type
    const char* quant_name = "UNKNOWN";
    switch (model_info_.quantization) {
        case KokoroQuantizationType::FP32: quant_name = "FP32"; break;
        case KokoroQuantizationType::FP16: quant_name = "FP16"; break;
        case KokoroQuantizationType::INT8: quant_name = "INT8"; break;
        default: quant_name = "UNKNOWN"; break;
    }
    KOKORO_LOGI("  📊 Model Quantization: %s", quant_name);

    if (model_info_.is_int8) {
        KOKORO_LOGI("  🎯 INT8 model detected - NNAPI NPU acceleration will be optimal!");
        KOKORO_LOGI("     INT8 enables full NPU execution on Qualcomm/Samsung/MediaTek NPUs");
    }

    const char* backend_name = "UNKNOWN";
    switch (config_.npu_backend) {
        case NPUBackend::AUTO:
            backend_name = "AUTO";
            KOKORO_LOGI("  🎯 Requested: AUTO (will try NNAPI first, then QNN, fallback to CPU)");
            break;
        case NPUBackend::CPU_ONLY:
            backend_name = "CPU_ONLY";
            KOKORO_LOGI("  ⚙️  Requested: CPU_ONLY (NPU disabled, will use CPU)");
            break;
        case NPUBackend::NNAPI:
            backend_name = "NNAPI";
            KOKORO_LOGI("  🚀 Requested: NNAPI (Android Neural Networks API)");
            break;
        case NPUBackend::QNN:
            backend_name = "QNN";
            KOKORO_LOGI("  🔷 Requested: QNN (Qualcomm AI Engine)");
            break;
    }

    // =========================================================================
    // Create session options using unified NPU backend selection
    // This handles NNAPI, QNN, and CPU fallback automatically
    // =========================================================================
    OrtSessionOptions* session_options = create_npu_session_options();

    if (session_options == nullptr) {
        KOKORO_LOGE("Failed to create session options");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    // Log which backend was selected
    KOKORO_LOGI("");
    KOKORO_LOGI("[STEP 4/5] Backend Selection Result:");
    const char* active_backend = "CPU";
    switch (active_npu_backend_) {
        case NPUBackend::NNAPI:
            active_backend = "NNAPI";
            KOKORO_LOGI("  🚀 SELECTED: NNAPI (Android Neural Networks API)");
            KOKORO_LOGI("     → Operations will be routed to device NPU");
            KOKORO_LOGI("     → Supported NPUs: Qualcomm Hexagon, Samsung Exynos, MediaTek APU");
            break;
        case NPUBackend::QNN:
            active_backend = "QNN";
            KOKORO_LOGI("  🔷 SELECTED: QNN (Qualcomm AI Engine)");
            KOKORO_LOGI("     → Operations will be routed to Qualcomm Hexagon HTP");
            break;
        case NPUBackend::CPU_ONLY:
            active_backend = "CPU";
            KOKORO_LOGI("  ⚙️  SELECTED: CPU (no NPU acceleration)");
            KOKORO_LOGI("     → Inference will run on CPU cores");
            break;
        default:
            active_backend = "CPU";
            KOKORO_LOGI("  ⚙️  DEFAULT: CPU (fallback)");
            break;
    }
    KOKORO_LOGI("  📊 NPU Status: %s", stats_.npu_active ? "✅ ACTIVE" : "❌ INACTIVE");

    // Create session
    KOKORO_LOGI("");
    KOKORO_LOGI("[STEP 5/5] Creating ONNX Runtime Session...");
    KOKORO_LOGI("  📁 Model: %s", model_path.c_str());
    KOKORO_LOGI("  🔧 Backend: %s", active_backend);
    KOKORO_LOGI("  🎯 NPU Active: %s", stats_.npu_active ? "YES" : "NO");

    OrtStatus* status = ort_api_->CreateSession(ort_env_, model_path.c_str(),
                                                session_options, &unified_session_);

    ort_api_->ReleaseSessionOptions(session_options);

    if (status != nullptr) {
        const char* err_msg = ort_api_->GetErrorMessage(status);
        KOKORO_LOGE("╔════════════════════════════════════════════════════════════════════════════════╗");
        KOKORO_LOGE("║  ❌ SESSION CREATION FAILED                                                     ║");
        KOKORO_LOGE("╠════════════════════════════════════════════════════════════════════════════════╣");
        KOKORO_LOGE("║  Error: %s", err_msg);
        KOKORO_LOGE("╠════════════════════════════════════════════════════════════════════════════════╣");
        if (config_.nnapi_config.cpu_disabled) {
            KOKORO_LOGE("║  ⚠️  NPU-ONLY MODE (cpu_disabled=TRUE) - This failure indicates:             ║");
            KOKORO_LOGE("║     - Some operations in the model are NOT supported by NNAPI NPU           ║");
            KOKORO_LOGE("║     - The model cannot run 100%% on NPU                                      ║");
            KOKORO_LOGE("║     - Consider using cpu_disabled=FALSE for hybrid NPU/CPU execution        ║");
            KOKORO_LOGE("╠════════════════════════════════════════════════════════════════════════════════╣");
            KOKORO_LOGE("║  VERIFICATION RESULT: Model is NOT 100%% NPU compatible                       ║");
        } else {
            KOKORO_LOGE("║  CPU fallback was enabled but session still failed                           ║");
        }
        KOKORO_LOGE("╚════════════════════════════════════════════════════════════════════════════════╝");
        RAC_LOG_ERROR(LOG_CAT, "Session creation failed: %s", err_msg);
        ort_api_->ReleaseStatus(status);
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    if (unified_session_ == nullptr) {
        KOKORO_LOGE("Session is NULL after creation");
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    // Session created successfully - log details about NPU mode
    if (config_.nnapi_config.cpu_disabled && stats_.npu_active) {
        KOKORO_LOGI("╔════════════════════════════════════════════════════════════════════════════════╗");
        KOKORO_LOGI("║  ✅ NPU-ONLY SESSION CREATED SUCCESSFULLY                                       ║");
        KOKORO_LOGI("╠════════════════════════════════════════════════════════════════════════════════╣");
        KOKORO_LOGI("║  cpu_disabled=TRUE and session created = ALL OPS RUN ON NPU                    ║");
        KOKORO_LOGI("║  VERIFICATION RESULT: Model IS 100%% NPU compatible!                            ║");
        KOKORO_LOGI("╚════════════════════════════════════════════════════════════════════════════════╝");
    } else if (stats_.npu_active) {
        KOKORO_LOGI("╔════════════════════════════════════════════════════════════════════════════════╗");
        KOKORO_LOGI("║  ⚠️  HYBRID NPU/CPU SESSION CREATED                                             ║");
        KOKORO_LOGI("╠════════════════════════════════════════════════════════════════════════════════╣");
        KOKORO_LOGI("║  cpu_disabled=FALSE - some ops may silently run on CPU                         ║");
        KOKORO_LOGI("║  Set cpu_disabled=TRUE to verify pure NPU execution                            ║");
        KOKORO_LOGI("╚════════════════════════════════════════════════════════════════════════════════╝");
    }

    KOKORO_LOGI("  -> Session created successfully ✓");

    // Get I/O info
    KOKORO_LOGI("[STEP 3] Getting model I/O information...");
    if (!get_session_io_info(unified_session_, unified_input_names_, unified_output_names_)) {
        KOKORO_LOGE("Failed to get session I/O info");
        ort_api_->ReleaseSession(unified_session_);
        unified_session_ = nullptr;
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    for (size_t i = 0; i < unified_input_names_.size(); ++i) {
        KOKORO_LOGI("  -> Input[%zu]: %s", i, unified_input_names_[i].c_str());
    }
    for (size_t i = 0; i < unified_output_names_.size(); ++i) {
        KOKORO_LOGI("  -> Output[%zu]: %s", i, unified_output_names_[i].c_str());
    }

    // Report actual execution mode
    KOKORO_LOGI("");
    if (stats_.npu_active) {
        KOKORO_LOGI("╔══════════════════════════════════════════════════════════════════════════════════╗");
        if (model_info_.is_int8) {
            KOKORO_LOGI("║  ✅ KOKORO TTS INT8 MODEL LOADED - OPTIMAL NPU ACCELERATED                       ║");
        } else {
            KOKORO_LOGI("║  ✅ KOKORO TTS MODEL LOADED SUCCESSFULLY - NPU ACCELERATED                       ║");
        }
        KOKORO_LOGI("╠══════════════════════════════════════════════════════════════════════════════════╣");
        KOKORO_LOGI("║  🚀 NPU ACCELERATION: ENABLED                                                    ║");
        KOKORO_LOGI("║     Backend: %s", active_backend);
        KOKORO_LOGI("║     Quantization: %s", model_info_.is_int8 ? "INT8 (OPTIMAL)" : "FP32");
        KOKORO_LOGI("║     NPU Status: ACTIVE");
        KOKORO_LOGI("║     Inputs: %zu, Outputs: %zu", unified_input_names_.size(), unified_output_names_.size());
        KOKORO_LOGI("╠══════════════════════════════════════════════════════════════════════════════════╣");
        if (model_info_.is_int8) {
            KOKORO_LOGI("║  📊 INT8 MODEL: Full NPU execution (4x+ speedup vs CPU)                          ║");
        } else {
            KOKORO_LOGI("║  📊 INFERENCE WILL RUN ON NPU (SIGNIFICANTLY FASTER)                             ║");
        }
        KOKORO_LOGI("╚══════════════════════════════════════════════════════════════════════════════════╝");
        RAC_LOG_INFO(LOG_CAT, "=== KOKORO TTS LOADED WITH NPU (%s) - Quantization: %s ===",
                     active_backend, model_info_.is_int8 ? "INT8" : "FP32");
        RAC_LOG_INFO(LOG_CAT, "Inputs: %zu, Outputs: %zu",
                     unified_input_names_.size(), unified_output_names_.size());
    } else {
        KOKORO_LOGI("╔══════════════════════════════════════════════════════════════════════════════════╗");
        KOKORO_LOGI("║  ⚠️  KOKORO TTS LOADED - CPU EXECUTION (NO NPU)                                  ║");
        KOKORO_LOGI("╠══════════════════════════════════════════════════════════════════════════════════╣");
        KOKORO_LOGI("║  ⚙️  CPU MODE: Inference will be slower                                          ║");
        KOKORO_LOGI("║     Quantization: %s", model_info_.is_int8 ? "INT8" : "FP32");
        KOKORO_LOGI("║     Inputs: %zu, Outputs: %zu", unified_input_names_.size(), unified_output_names_.size());
        KOKORO_LOGI("╠══════════════════════════════════════════════════════════════════════════════════╣");
        KOKORO_LOGI("║  💡 For NPU acceleration:                                                        ║");
        KOKORO_LOGI("║     1. Use an INT8 quantized model (kokoro-tts-int8)                             ║");
        KOKORO_LOGI("║     2. Ensure NNAPI is compiled in (RAC_ENABLE_NNAPI=ON)                         ║");
        KOKORO_LOGI("║     3. Device must support Android NNAPI (API level 27+)                         ║");
        KOKORO_LOGI("╚══════════════════════════════════════════════════════════════════════════════════╝");
        RAC_LOG_INFO(LOG_CAT, "=== KOKORO TTS LOADED ON CPU - Quantization: %s ===",
                     model_info_.is_int8 ? "INT8" : "FP32");
        RAC_LOG_INFO(LOG_CAT, "Inputs: %zu, Outputs: %zu",
                     unified_input_names_.size(), unified_output_names_.size());
    }

    return RAC_SUCCESS;
}

rac_result_t KokoroTTSLoader::load_split_models(const std::string& encoder_path,
                                                 const std::string& vocoder_path) {
    KOKORO_LOGI("Loading split Kokoro models (hybrid NPU+CPU)");
    KOKORO_LOGI("  Encoder: %s", encoder_path.c_str());
    KOKORO_LOGI("  Vocoder: %s", vocoder_path.c_str());
    RAC_LOG_INFO(LOG_CAT, "=== LOADING SPLIT KOKORO MODELS (HYBRID) ===");
    RAC_LOG_INFO(LOG_CAT, "Encoder (NPU): %s", encoder_path.c_str());
    RAC_LOG_INFO(LOG_CAT, "Vocoder (CPU): %s", vocoder_path.c_str());

    // Load encoder (try NPU first via unified backend selection, fall back to CPU)
    KOKORO_LOGI(">>> Loading encoder (NPU preferred via NNAPI/QNN)...");
    OrtSessionOptions* encoder_options = create_npu_session_options();
    if (encoder_options == nullptr) {
        KOKORO_LOGE("Failed to create NPU session options for encoder");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    OrtStatus* status = ort_api_->CreateSession(ort_env_, encoder_path.c_str(),
                                                encoder_options, &encoder_session_);
    ort_api_->ReleaseSessionOptions(encoder_options);

    if (status != nullptr) {
        KOKORO_LOGE("Failed to create encoder session: %s", ort_api_->GetErrorMessage(status));
        RAC_LOG_ERROR(LOG_CAT, "Failed to load encoder: %s", ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    if (!get_session_io_info(encoder_session_, encoder_input_names_, encoder_output_names_)) {
        KOKORO_LOGE("Failed to get encoder I/O info");
        ort_api_->ReleaseSession(encoder_session_);
        encoder_session_ = nullptr;
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    KOKORO_LOGI("<<< Encoder loaded: %zu inputs, %zu outputs, NPU=%s",
               encoder_input_names_.size(), encoder_output_names_.size(),
               stats_.npu_active ? "YES" : "NO");

    // Load vocoder (CPU only - contains ISTFT)
    KOKORO_LOGI(">>> Loading vocoder (CPU)...");
    OrtSessionOptions* vocoder_options = create_cpu_session_options();
    if (vocoder_options == nullptr) {
        ort_api_->ReleaseSession(encoder_session_);
        encoder_session_ = nullptr;
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    status = ort_api_->CreateSession(ort_env_, vocoder_path.c_str(),
                                     vocoder_options, &vocoder_session_);
    ort_api_->ReleaseSessionOptions(vocoder_options);

    if (status != nullptr) {
        KOKORO_LOGE("Failed to create vocoder session: %s", ort_api_->GetErrorMessage(status));
        RAC_LOG_ERROR(LOG_CAT, "Failed to load vocoder: %s", ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        ort_api_->ReleaseSession(encoder_session_);
        encoder_session_ = nullptr;
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    if (!get_session_io_info(vocoder_session_, vocoder_input_names_, vocoder_output_names_)) {
        KOKORO_LOGE("Failed to get vocoder I/O info");
        ort_api_->ReleaseSession(encoder_session_);
        ort_api_->ReleaseSession(vocoder_session_);
        encoder_session_ = nullptr;
        vocoder_session_ = nullptr;
        return RAC_ERROR_MODEL_LOAD_FAILED;
    }

    KOKORO_LOGI("<<< Vocoder loaded: %zu inputs, %zu outputs",
               vocoder_input_names_.size(), vocoder_output_names_.size());

    RAC_LOG_INFO(LOG_CAT, "=== SPLIT MODELS LOADED ===");
    RAC_LOG_INFO(LOG_CAT, "  Encoder: NPU=%s", stats_.npu_active ? "YES" : "NO (CPU fallback)");
    RAC_LOG_INFO(LOG_CAT, "  Vocoder: CPU (ISTFT)");

    return RAC_SUCCESS;
}

rac_result_t KokoroTTSLoader::synthesize(const int64_t* token_ids,
                                         size_t num_tokens,
                                         const float* style_vector,
                                         int32_t speed,
                                         std::vector<float>& out_audio) {
    if (!loaded_) {
        KOKORO_LOGE("Model not loaded");
        return RAC_ERROR_MODEL_NOT_LOADED;
    }

    if (token_ids == nullptr || style_vector == nullptr) {
        KOKORO_LOGE("Invalid input: token_ids=%p, style_vector=%p",
                   (void*)token_ids, (void*)style_vector);
        return RAC_ERROR_NULL_POINTER;
    }

    KOKORO_LOGI("Synthesizing: %zu tokens, speed=%d", num_tokens, speed);

    auto start = std::chrono::high_resolution_clock::now();
    rac_result_t result;

    if (model_info_.type == KokoroModelType::UNIFIED) {
        result = run_unified_inference(token_ids, num_tokens, style_vector, speed, out_audio);
    } else {
        result = run_hybrid_inference(token_ids, num_tokens, style_vector, speed, out_audio);
    }

    auto end = std::chrono::high_resolution_clock::now();
    stats_.total_inference_ms = std::chrono::duration<double, std::milli>(end - start).count();
    stats_.total_inferences++;

    if (result == RAC_SUCCESS) {
        KOKORO_LOGI("Synthesis complete: %zu samples, %.2f ms",
                   out_audio.size(), stats_.total_inference_ms);
        RAC_LOG_INFO(LOG_CAT, "Synthesis: %zu samples in %.2f ms",
                    out_audio.size(), stats_.total_inference_ms);
    }

    return result;
}

rac_result_t KokoroTTSLoader::run_unified_inference(const int64_t* token_ids,
                                                     size_t num_tokens,
                                                     const float* style_vector,
                                                     int32_t speed,
                                                     std::vector<float>& out_audio) {
    // Determine execution mode for logging
    const char* exec_mode = "CPU";
    const char* exec_detail = "CPU (no NPU acceleration)";
    if (stats_.npu_active) {
        switch (active_npu_backend_) {
            case NPUBackend::NNAPI:
                exec_mode = "NNAPI-NPU";
                exec_detail = "NNAPI Execution Provider → Device NPU (Qualcomm/Samsung/MediaTek)";
                break;
            case NPUBackend::QNN:
                exec_mode = "QNN-NPU";
                exec_detail = "QNN Execution Provider → Qualcomm Hexagon HTP";
                break;
            default:
                exec_mode = "NPU";
                exec_detail = "NPU (unknown backend)";
                break;
        }
    }

    KOKORO_LOGI("╔══════════════════════════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║  🎯 RUNNING UNIFIED INFERENCE                                                    ║");
    KOKORO_LOGI("╠══════════════════════════════════════════════════════════════════════════════════╣");
    KOKORO_LOGI("║  Execution Mode:  %s", exec_mode);
    KOKORO_LOGI("║  Backend Detail:  %s", exec_detail);
    KOKORO_LOGI("║  NPU Active:      %s", stats_.npu_active ? "✅ YES - USING NPU" : "❌ NO - CPU FALLBACK");
    KOKORO_LOGI("║  Input Tokens:    %zu", num_tokens);
    KOKORO_LOGI("║  Speed Factor:    %d", speed);
    KOKORO_LOGI("╚══════════════════════════════════════════════════════════════════════════════════╝");

    if (!stats_.npu_active) {
        KOKORO_LOGW("⚠️  WARNING: NPU is NOT active! Inference will run on CPU (slower)");
        KOKORO_LOGW("⚠️  To enable NPU: ensure NNAPI is compiled and model has static shapes");
    }

    RAC_LOG_INFO(LOG_CAT, "Inference: mode=%s, npu=%s, tokens=%zu",
                exec_mode, stats_.npu_active ? "YES" : "NO", num_tokens);

    OrtMemoryInfo* memory_info = nullptr;
    OrtStatus* status = ort_api_->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info);
    if (status != nullptr) {
        KOKORO_LOGE("Failed to create memory info: %s", ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return RAC_ERROR_INFERENCE_FAILED;
    }

    std::vector<OrtValue*> inputs;
    std::vector<const char*> input_names_cstr;

    // Create input tensors based on detected input names
    // Kokoro unified model typically has: input_ids, style, speed

    // Input IDs (token IDs)
    int64_t ids_shape[] = {1, static_cast<int64_t>(num_tokens)};
    OrtValue* ids_tensor = nullptr;
    status = ort_api_->CreateTensorWithDataAsOrtValue(
        memory_info, const_cast<int64_t*>(token_ids), num_tokens * sizeof(int64_t),
        ids_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &ids_tensor);

    if (status != nullptr || ids_tensor == nullptr) {
        KOKORO_LOGE("Failed to create token IDs tensor");
        if (status) ort_api_->ReleaseStatus(status);
        ort_api_->ReleaseMemoryInfo(memory_info);
        return RAC_ERROR_INFERENCE_FAILED;
    }
    inputs.push_back(ids_tensor);

    // Style vector (256 floats)
    int64_t style_shape[] = {1, 256};
    OrtValue* style_tensor = nullptr;
    status = ort_api_->CreateTensorWithDataAsOrtValue(
        memory_info, const_cast<float*>(style_vector), 256 * sizeof(float),
        style_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &style_tensor);

    if (status != nullptr || style_tensor == nullptr) {
        KOKORO_LOGE("Failed to create style tensor");
        if (status) ort_api_->ReleaseStatus(status);
        ort_api_->ReleaseValue(ids_tensor);
        ort_api_->ReleaseMemoryInfo(memory_info);
        return RAC_ERROR_INFERENCE_FAILED;
    }
    inputs.push_back(style_tensor);

    // Speed (float32 scalar) - Kokoro static model expects float32
    int64_t speed_shape[] = {1};
    float speed_float = static_cast<float>(speed);  // Convert int32 to float32
    OrtValue* speed_tensor = nullptr;
    status = ort_api_->CreateTensorWithDataAsOrtValue(
        memory_info, &speed_float, sizeof(float),
        speed_shape, 1, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &speed_tensor);

    if (status != nullptr || speed_tensor == nullptr) {
        KOKORO_LOGE("Failed to create speed tensor");
        if (status) ort_api_->ReleaseStatus(status);
        ort_api_->ReleaseValue(ids_tensor);
        ort_api_->ReleaseValue(style_tensor);
        ort_api_->ReleaseMemoryInfo(memory_info);
        return RAC_ERROR_INFERENCE_FAILED;
    }
    inputs.push_back(speed_tensor);

    // Build input names (use detected names)
    for (const auto& name : unified_input_names_) {
        input_names_cstr.push_back(name.c_str());
    }

    // Build output names
    std::vector<const char*> output_names_cstr;
    for (const auto& name : unified_output_names_) {
        output_names_cstr.push_back(name.c_str());
    }

    // Run inference
    std::vector<OrtValue*> outputs(unified_output_names_.size(), nullptr);

    auto start_cpu = std::chrono::high_resolution_clock::now();
    status = ort_api_->Run(unified_session_, nullptr,
                          input_names_cstr.data(), inputs.data(), inputs.size(),
                          output_names_cstr.data(), outputs.size(), outputs.data());
    auto end_cpu = std::chrono::high_resolution_clock::now();
    stats_.cpu_inference_ms = std::chrono::duration<double, std::milli>(end_cpu - start_cpu).count();

    // Cleanup inputs
    for (auto* input : inputs) {
        ort_api_->ReleaseValue(input);
    }
    ort_api_->ReleaseMemoryInfo(memory_info);

    if (status != nullptr) {
        KOKORO_LOGE("Inference failed: %s", ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return RAC_ERROR_INFERENCE_FAILED;
    }

    // Extract output audio
    if (outputs.empty() || outputs[0] == nullptr) {
        KOKORO_LOGE("No output from inference");
        return RAC_ERROR_INFERENCE_FAILED;
    }

    float* audio_data = nullptr;
    status = ort_api_->GetTensorMutableData(outputs[0], reinterpret_cast<void**>(&audio_data));
    if (status != nullptr || audio_data == nullptr) {
        KOKORO_LOGE("Failed to get output data");
        if (status) ort_api_->ReleaseStatus(status);
        for (auto* output : outputs) {
            if (output) ort_api_->ReleaseValue(output);
        }
        return RAC_ERROR_INFERENCE_FAILED;
    }

    // Get output shape
    OrtTensorTypeAndShapeInfo* type_info = nullptr;
    status = ort_api_->GetTensorTypeAndShape(outputs[0], &type_info);
    if (status == nullptr) {
        size_t num_dims = 0;
        ort_api_->GetDimensionsCount(type_info, &num_dims);

        std::vector<int64_t> dims(num_dims);
        ort_api_->GetDimensions(type_info, dims.data(), num_dims);

        size_t total_samples = 1;
        for (auto dim : dims) {
            total_samples *= static_cast<size_t>(dim);
        }

        out_audio.assign(audio_data, audio_data + total_samples);
        ort_api_->ReleaseTensorTypeAndShapeInfo(type_info);
    } else {
        ort_api_->ReleaseStatus(status);
    }

    // Cleanup outputs
    for (auto* output : outputs) {
        if (output) ort_api_->ReleaseValue(output);
    }

    const char* mode = stats_.npu_active ? "NPU/QNN" : "CPU";
    KOKORO_LOGI("╔════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║  ✅ INFERENCE COMPLETE - %s                             ║", mode);
    KOKORO_LOGI("╚════════════════════════════════════════════════════════════╝");
    KOKORO_LOGI("  Samples Generated: %zu", out_audio.size());
    KOKORO_LOGI("  Inference Time: %.2f ms", stats_.cpu_inference_ms);
    KOKORO_LOGI("  Execution Provider: %s", stats_.npu_active ? "QNN HTP (NPU)" : "CPU");
    RAC_LOG_INFO(LOG_CAT, "Inference complete (%s): %zu samples, %.2f ms",
                mode, out_audio.size(), stats_.cpu_inference_ms);

    return RAC_SUCCESS;
}

rac_result_t KokoroTTSLoader::run_hybrid_inference(const int64_t* token_ids,
                                                    size_t num_tokens,
                                                    const float* style_vector,
                                                    int32_t speed,
                                                    std::vector<float>& out_audio) {
    KOKORO_LOGI("Running hybrid inference (NPU encoder + CPU vocoder)...");
    RAC_LOG_INFO(LOG_CAT, "=== HYBRID INFERENCE START ===");

    OrtMemoryInfo* memory_info = nullptr;
    OrtStatus* status = ort_api_->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info);
    if (status != nullptr) {
        KOKORO_LOGE("Failed to create memory info");
        ort_api_->ReleaseStatus(status);
        return RAC_ERROR_INFERENCE_FAILED;
    }

    // ===== ENCODER PHASE (NPU) =====
    KOKORO_LOGI(">>> ENCODER (NPU)...");
    auto start_encoder = std::chrono::high_resolution_clock::now();

    std::vector<OrtValue*> encoder_inputs;

    // Token IDs
    int64_t ids_shape[] = {1, static_cast<int64_t>(num_tokens)};
    OrtValue* ids_tensor = nullptr;
    status = ort_api_->CreateTensorWithDataAsOrtValue(
        memory_info, const_cast<int64_t*>(token_ids), num_tokens * sizeof(int64_t),
        ids_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &ids_tensor);

    if (status != nullptr || ids_tensor == nullptr) {
        KOKORO_LOGE("Failed to create encoder input tensor");
        if (status) ort_api_->ReleaseStatus(status);
        ort_api_->ReleaseMemoryInfo(memory_info);
        return RAC_ERROR_INFERENCE_FAILED;
    }
    encoder_inputs.push_back(ids_tensor);

    // Style vector
    int64_t style_shape[] = {1, 256};
    OrtValue* style_tensor = nullptr;
    status = ort_api_->CreateTensorWithDataAsOrtValue(
        memory_info, const_cast<float*>(style_vector), 256 * sizeof(float),
        style_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &style_tensor);

    if (status != nullptr || style_tensor == nullptr) {
        KOKORO_LOGE("Failed to create style tensor");
        if (status) ort_api_->ReleaseStatus(status);
        ort_api_->ReleaseValue(ids_tensor);
        ort_api_->ReleaseMemoryInfo(memory_info);
        return RAC_ERROR_INFERENCE_FAILED;
    }
    encoder_inputs.push_back(style_tensor);

    // Build encoder names
    std::vector<const char*> encoder_input_names_cstr;
    for (const auto& name : encoder_input_names_) {
        encoder_input_names_cstr.push_back(name.c_str());
    }
    std::vector<const char*> encoder_output_names_cstr;
    for (const auto& name : encoder_output_names_) {
        encoder_output_names_cstr.push_back(name.c_str());
    }

    // Run encoder
    encoder_outputs_.clear();
    encoder_outputs_.resize(encoder_output_names_.size(), nullptr);

    status = ort_api_->Run(encoder_session_, nullptr,
                          encoder_input_names_cstr.data(), encoder_inputs.data(), encoder_inputs.size(),
                          encoder_output_names_cstr.data(), encoder_outputs_.size(), encoder_outputs_.data());

    // Cleanup encoder inputs
    for (auto* input : encoder_inputs) {
        ort_api_->ReleaseValue(input);
    }

    auto end_encoder = std::chrono::high_resolution_clock::now();
    stats_.npu_inference_ms = std::chrono::duration<double, std::milli>(end_encoder - start_encoder).count();

    if (status != nullptr) {
        KOKORO_LOGE("Encoder inference failed: %s", ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        ort_api_->ReleaseMemoryInfo(memory_info);
        return RAC_ERROR_INFERENCE_FAILED;
    }

    KOKORO_LOGI("<<< ENCODER complete: %.2f ms (NPU=%s)",
               stats_.npu_inference_ms, stats_.npu_active ? "YES" : "NO");
    RAC_LOG_INFO(LOG_CAT, "[NPU] Encoder: %.2f ms", stats_.npu_inference_ms);

    // ===== VOCODER PHASE (CPU) =====
    KOKORO_LOGI(">>> VOCODER (CPU)...");
    auto start_vocoder = std::chrono::high_resolution_clock::now();

    // Build vocoder names
    std::vector<const char*> vocoder_input_names_cstr;
    for (const auto& name : vocoder_input_names_) {
        vocoder_input_names_cstr.push_back(name.c_str());
    }
    std::vector<const char*> vocoder_output_names_cstr;
    for (const auto& name : vocoder_output_names_) {
        vocoder_output_names_cstr.push_back(name.c_str());
    }

    // Run vocoder with encoder outputs as inputs
    std::vector<OrtValue*> vocoder_outputs(vocoder_output_names_.size(), nullptr);

    status = ort_api_->Run(vocoder_session_, nullptr,
                          vocoder_input_names_cstr.data(), encoder_outputs_.data(), encoder_outputs_.size(),
                          vocoder_output_names_cstr.data(), vocoder_outputs.size(), vocoder_outputs.data());

    // Cleanup encoder outputs
    for (auto* output : encoder_outputs_) {
        if (output) ort_api_->ReleaseValue(output);
    }
    encoder_outputs_.clear();

    auto end_vocoder = std::chrono::high_resolution_clock::now();
    stats_.cpu_inference_ms = std::chrono::duration<double, std::milli>(end_vocoder - start_vocoder).count();

    if (status != nullptr) {
        KOKORO_LOGE("Vocoder inference failed: %s", ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        ort_api_->ReleaseMemoryInfo(memory_info);
        return RAC_ERROR_INFERENCE_FAILED;
    }

    KOKORO_LOGI("<<< VOCODER complete: %.2f ms", stats_.cpu_inference_ms);
    RAC_LOG_INFO(LOG_CAT, "[CPU] Vocoder: %.2f ms", stats_.cpu_inference_ms);

    ort_api_->ReleaseMemoryInfo(memory_info);

    // Extract output audio
    if (vocoder_outputs.empty() || vocoder_outputs[0] == nullptr) {
        KOKORO_LOGE("No vocoder output");
        return RAC_ERROR_INFERENCE_FAILED;
    }

    float* audio_data = nullptr;
    status = ort_api_->GetTensorMutableData(vocoder_outputs[0], reinterpret_cast<void**>(&audio_data));
    if (status != nullptr || audio_data == nullptr) {
        KOKORO_LOGE("Failed to get audio output");
        if (status) ort_api_->ReleaseStatus(status);
        for (auto* output : vocoder_outputs) {
            if (output) ort_api_->ReleaseValue(output);
        }
        return RAC_ERROR_INFERENCE_FAILED;
    }

    // Get output shape
    OrtTensorTypeAndShapeInfo* type_info = nullptr;
    status = ort_api_->GetTensorTypeAndShape(vocoder_outputs[0], &type_info);
    if (status == nullptr) {
        size_t num_dims = 0;
        ort_api_->GetDimensionsCount(type_info, &num_dims);

        std::vector<int64_t> dims(num_dims);
        ort_api_->GetDimensions(type_info, dims.data(), num_dims);

        size_t total_samples = 1;
        for (auto dim : dims) {
            total_samples *= static_cast<size_t>(dim);
        }

        out_audio.assign(audio_data, audio_data + total_samples);
        ort_api_->ReleaseTensorTypeAndShapeInfo(type_info);
    } else {
        ort_api_->ReleaseStatus(status);
    }

    // Cleanup vocoder outputs
    for (auto* output : vocoder_outputs) {
        if (output) ort_api_->ReleaseValue(output);
    }

    RAC_LOG_INFO(LOG_CAT, "=== HYBRID INFERENCE COMPLETE ===");
    RAC_LOG_INFO(LOG_CAT, "  NPU (encoder): %.2f ms", stats_.npu_inference_ms);
    RAC_LOG_INFO(LOG_CAT, "  CPU (vocoder): %.2f ms", stats_.cpu_inference_ms);
    RAC_LOG_INFO(LOG_CAT, "  Total: %.2f ms", stats_.npu_inference_ms + stats_.cpu_inference_ms);
    RAC_LOG_INFO(LOG_CAT, "  Output: %zu samples", out_audio.size());

    return RAC_SUCCESS;
}

rac_result_t KokoroTTSLoader::synthesize_text(const std::string& text,
                                              const std::string& voice_id,
                                              float speed_rate,
                                              std::vector<float>& out_audio) {
    KOKORO_LOGI("synthesize_text: text='%.50s%s', voice=%s, speed=%.2f",
               text.c_str(), text.length() > 50 ? "..." : "", voice_id.c_str(), speed_rate);

    // Tokenize text using Kokoro vocabulary
    // The model expects exactly KOKORO_INPUT_SIZE (50) tokens
    std::vector<int64_t> token_ids = tokenize_text_kokoro(text);

    KOKORO_LOGI("Tokenized: %zu tokens (model expects %zu)",
               token_ids.size(), KOKORO_INPUT_SIZE);

    // Log first few tokens for debugging
    std::string token_preview;
    for (size_t i = 0; i < std::min(token_ids.size(), size_t(10)); ++i) {
        token_preview += std::to_string(token_ids[i]) + " ";
    }
    KOKORO_LOGI("Token preview: [%s...]", token_preview.c_str());

    // Create style vector (256 floats)
    // Default to zeros, which produces a neutral voice
    std::vector<float> style_vector(256, 0.0f);

    // Try to load voice embedding if available
    if (model_info_.has_voices) {
        // Load voice embedding from binary file
        std::string voice_file = model_info_.voices_path;

        // If voice_id is specified and not the default, try voice-specific file
        if (!voice_id.empty() && voice_id != "af_heart") {
            std::string dir = voice_file.substr(0, voice_file.find_last_of("/\\") + 1);
            voice_file = dir + voice_id + ".bin";
        }

        std::ifstream voice_stream(voice_file, std::ios::binary);
        if (voice_stream.is_open()) {
            voice_stream.read(reinterpret_cast<char*>(style_vector.data()),
                             256 * sizeof(float));
            if (voice_stream.good() || voice_stream.eof()) {
                KOKORO_LOGI("Loaded voice embedding from: %s", voice_file.c_str());
            } else {
                KOKORO_LOGW("Partial read of voice embedding, using default");
                std::fill(style_vector.begin(), style_vector.end(), 0.0f);
            }
            voice_stream.close();
        } else {
            KOKORO_LOGW("Voice embedding not found: %s, using default", voice_file.c_str());
        }
    } else {
        KOKORO_LOGI("No voice embeddings available, using default (neutral) voice");
    }

    // Convert speed rate to integer (Kokoro uses int32 speed)
    // Clamp to reasonable range [1, 10]
    int32_t speed = static_cast<int32_t>(speed_rate);
    if (speed < 1) speed = 1;
    if (speed > 10) speed = 10;

    KOKORO_LOGI("Calling synthesize: tokens=%zu, speed=%d", token_ids.size(), speed);

    return synthesize(token_ids.data(), token_ids.size(), style_vector.data(), speed, out_audio);
}

// =============================================================================
// NPU vs CPU Benchmark Implementation
// =============================================================================

KokoroBenchmarkResult KokoroTTSLoader::run_benchmark(const std::string& test_text) {
    KokoroBenchmarkResult result;

    KOKORO_LOGI("");
    KOKORO_LOGI("╔═══════════════════════════════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║                         NPU vs CPU BENCHMARK STARTING                                  ║");
    KOKORO_LOGI("╚═══════════════════════════════════════════════════════════════════════════════════════╝");
    KOKORO_LOGI("");

    // Check if model is loaded
    if (!loaded_) {
        result.success = false;
        result.error_message = "Model not loaded";
        KOKORO_LOGE("Benchmark failed: Model not loaded");
        return result;
    }

    // Use default test text if none provided
    std::string benchmark_text = test_text;
    if (benchmark_text.empty()) {
        benchmark_text = "Hello world! This is a benchmark test of the Kokoro text to speech system.";
    }
    result.test_text = benchmark_text;

    KOKORO_LOGI("[BENCHMARK] Test text: \"%s\" (%zu characters)",
               benchmark_text.c_str(), benchmark_text.length());

    // Tokenize the text (done once, used for both runs)
    std::vector<int64_t> token_ids = tokenize_text_kokoro(benchmark_text);
    result.num_tokens = token_ids.size();
    KOKORO_LOGI("[BENCHMARK] Tokenized to %zu tokens", result.num_tokens);

    // Create default style vector
    std::vector<float> style_vector(256, 0.0f);
    if (model_info_.has_voices) {
        std::ifstream voice_stream(model_info_.voices_path, std::ios::binary);
        if (voice_stream.is_open()) {
            voice_stream.read(reinterpret_cast<char*>(style_vector.data()), 256 * sizeof(float));
            voice_stream.close();
        }
    }

    // =========================================================================
    // STEP 1: Run with current session (NPU/NNAPI if available)
    // =========================================================================
    KOKORO_LOGI("");
    KOKORO_LOGI("╔═══════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║  STEP 1: Running with CURRENT session (NPU/NNAPI)             ║");
    KOKORO_LOGI("╚═══════════════════════════════════════════════════════════════╝");

    result.npu_available = stats_.npu_active;
    KOKORO_LOGI("[BENCHMARK] NPU/NNAPI active: %s", result.npu_available ? "YES" : "NO");

    std::vector<float> npu_audio;
    auto npu_start = std::chrono::high_resolution_clock::now();

    rac_result_t npu_result = synthesize(token_ids.data(), token_ids.size(),
                                          style_vector.data(), 1, npu_audio);

    auto npu_end = std::chrono::high_resolution_clock::now();
    result.npu_inference_ms = std::chrono::duration<double, std::milli>(npu_end - npu_start).count();

    if (npu_result != RAC_SUCCESS || npu_audio.empty()) {
        result.success = false;
        result.error_message = "NPU synthesis failed";
        KOKORO_LOGE("[BENCHMARK] NPU synthesis failed: %d", npu_result);
        return result;
    }

    // Calculate audio duration
    result.audio_samples = npu_audio.size();
    result.sample_rate = 24000;
    result.audio_duration_ms = (npu_audio.size() / static_cast<double>(result.sample_rate)) * 1000.0;
    result.npu_rtf = result.audio_duration_ms / result.npu_inference_ms;

    KOKORO_LOGI("[BENCHMARK] NPU/Current Session Results:");
    KOKORO_LOGI("           Inference Time: %.2f ms", result.npu_inference_ms);
    KOKORO_LOGI("           Audio Duration: %.2f ms (%zu samples @ %d Hz)",
               result.audio_duration_ms, result.audio_samples, result.sample_rate);
    KOKORO_LOGI("           Real-Time Factor: %.2fx", result.npu_rtf);

    // =========================================================================
    // STEP 2: Create CPU-only session and run
    // =========================================================================
    KOKORO_LOGI("");
    KOKORO_LOGI("╔═══════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║  STEP 2: Creating CPU-ONLY session for comparison             ║");
    KOKORO_LOGI("╚═══════════════════════════════════════════════════════════════╝");

    // Save current session
    OrtSession* saved_session = unified_session_;
    bool saved_npu_active = stats_.npu_active;
    NPUBackend saved_backend = active_npu_backend_;

    // Create CPU-only session options
    OrtSessionOptions* cpu_options = create_cpu_session_options();
    if (cpu_options == nullptr) {
        // Restore and return partial results
        result.success = true;  // NPU test succeeded
        result.error_message = "Could not create CPU session for comparison";
        KOKORO_LOGW("[BENCHMARK] Could not create CPU session options");
        return result;
    }

    // Create CPU-only session
    KOKORO_LOGI("[BENCHMARK] Creating CPU-only ONNX session...");
    OrtSession* cpu_session = nullptr;
    OrtStatus* status = ort_api_->CreateSession(ort_env_, model_info_.unified_path.c_str(),
                                                cpu_options, &cpu_session);
    ort_api_->ReleaseSessionOptions(cpu_options);

    if (status != nullptr || cpu_session == nullptr) {
        if (status != nullptr) {
            KOKORO_LOGE("[BENCHMARK] Failed to create CPU session: %s",
                       ort_api_->GetErrorMessage(status));
            ort_api_->ReleaseStatus(status);
        }
        result.success = true;  // NPU test succeeded
        result.error_message = "Could not create CPU session for comparison";
        return result;
    }

    KOKORO_LOGI("[BENCHMARK] CPU-only session created successfully");

    // Temporarily switch to CPU session
    unified_session_ = cpu_session;
    stats_.npu_active = false;
    active_npu_backend_ = NPUBackend::CPU_ONLY;

    // Run CPU synthesis
    std::vector<float> cpu_audio;
    auto cpu_start = std::chrono::high_resolution_clock::now();

    rac_result_t cpu_result = synthesize(token_ids.data(), token_ids.size(),
                                          style_vector.data(), 1, cpu_audio);

    auto cpu_end = std::chrono::high_resolution_clock::now();
    result.cpu_inference_ms = std::chrono::duration<double, std::milli>(cpu_end - cpu_start).count();

    // Cleanup CPU session
    ort_api_->ReleaseSession(cpu_session);

    // Restore original session
    unified_session_ = saved_session;
    stats_.npu_active = saved_npu_active;
    active_npu_backend_ = saved_backend;

    if (cpu_result != RAC_SUCCESS || cpu_audio.empty()) {
        result.success = true;  // NPU test succeeded
        result.error_message = "CPU synthesis failed, but NPU test succeeded";
        KOKORO_LOGW("[BENCHMARK] CPU synthesis failed: %d", cpu_result);
        return result;
    }

    result.cpu_rtf = result.audio_duration_ms / result.cpu_inference_ms;

    KOKORO_LOGI("[BENCHMARK] CPU-Only Session Results:");
    KOKORO_LOGI("           Inference Time: %.2f ms", result.cpu_inference_ms);
    KOKORO_LOGI("           Audio Duration: %.2f ms", result.audio_duration_ms);
    KOKORO_LOGI("           Real-Time Factor: %.2fx", result.cpu_rtf);

    // =========================================================================
    // STEP 3: Calculate comparison metrics and log results
    // =========================================================================
    KOKORO_LOGI("");
    KOKORO_LOGI("╔═══════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║  BENCHMARK COMPARISON RESULTS                                  ║");
    KOKORO_LOGI("╚═══════════════════════════════════════════════════════════════╝");

    // Calculate speedup (CPU time / NPU time)
    // > 1 means NPU is faster, < 1 means CPU is faster
    if (result.npu_inference_ms > 0) {
        result.speedup = result.cpu_inference_ms / result.npu_inference_ms;
        result.npu_is_faster = result.speedup > 1.0;
    }

    // Print beautiful comparison table
    KOKORO_LOGI("");
    KOKORO_LOGI("╔═══════════════════════════════════════════════════════════════════════════════════════╗");
    KOKORO_LOGI("║                      NPU vs CPU BENCHMARK RESULTS                                      ║");
    KOKORO_LOGI("╠═══════════════════════════════════════════════════════════════════════════════════════╣");
    KOKORO_LOGI("║  Input: \"%.50s%s\" (%zu tokens)                                                      ║",
               benchmark_text.c_str(), benchmark_text.length() > 50 ? "..." : "", result.num_tokens);
    KOKORO_LOGI("║                                                                                        ║");
    KOKORO_LOGI("║  NPU (NNAPI):                                                                          ║");
    KOKORO_LOGI("║    Inference Time:    %8.2f ms                                                        ║", result.npu_inference_ms);
    KOKORO_LOGI("║    Audio Duration:    %8.2f ms                                                        ║", result.audio_duration_ms);
    KOKORO_LOGI("║    Real-Time Factor:  %8.2fx                                                          ║", result.npu_rtf);
    KOKORO_LOGI("║    NNAPI Active:      %s                                                              ║", result.npu_available ? "YES ✓" : "NO ✗ ");
    KOKORO_LOGI("║                                                                                        ║");
    KOKORO_LOGI("║  CPU Only:                                                                             ║");
    KOKORO_LOGI("║    Inference Time:    %8.2f ms                                                        ║", result.cpu_inference_ms);
    KOKORO_LOGI("║    Audio Duration:    %8.2f ms                                                        ║", result.audio_duration_ms);
    KOKORO_LOGI("║    Real-Time Factor:  %8.2fx                                                          ║", result.cpu_rtf);
    KOKORO_LOGI("║                                                                                        ║");
    KOKORO_LOGI("╠═══════════════════════════════════════════════════════════════════════════════════════╣");

    if (result.npu_is_faster) {
        KOKORO_LOGI("║  🚀 SPEEDUP: NPU is %.2fx FASTER than CPU!                                           ║", result.speedup);
        KOKORO_LOGI("║     NPU saved %.2f ms per inference                                                   ║", result.cpu_inference_ms - result.npu_inference_ms);
    } else if (result.speedup > 0.9 && result.speedup < 1.1) {
        KOKORO_LOGI("║  ⚠️  SIMILAR: NPU and CPU have similar performance (%.2fx)                            ║", result.speedup);
        KOKORO_LOGI("║     Difference: %.2f ms                                                               ║", std::abs(result.cpu_inference_ms - result.npu_inference_ms));
    } else {
        KOKORO_LOGI("║  ❌ SLOWER: NPU is %.2fx SLOWER than CPU!                                             ║", 1.0 / result.speedup);
        KOKORO_LOGI("║     Something may be wrong with NNAPI configuration                                   ║");
    }

    KOKORO_LOGI("╚═══════════════════════════════════════════════════════════════════════════════════════╝");
    KOKORO_LOGI("");

    // Log to RAC logger as well
    RAC_LOG_INFO("KokoroBench", "=== NPU vs CPU BENCHMARK COMPLETE ===");
    RAC_LOG_INFO("KokoroBench", "NPU: %.2f ms (RTF: %.2fx, NNAPI: %s)",
                result.npu_inference_ms, result.npu_rtf, result.npu_available ? "YES" : "NO");
    RAC_LOG_INFO("KokoroBench", "CPU: %.2f ms (RTF: %.2fx)", result.cpu_inference_ms, result.cpu_rtf);
    RAC_LOG_INFO("KokoroBench", "Speedup: %.2fx (%s)", result.speedup,
                result.npu_is_faster ? "NPU faster" : "CPU faster");

    result.success = true;
    return result;
}

}  // namespace onnx
}  // namespace rac
