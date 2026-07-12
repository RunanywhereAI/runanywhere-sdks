#pragma once

// =============================================================================
// Model Configuration for OpenClaw Hybrid Assistant
// =============================================================================
// Simplified configuration - NO LLM, only:
// - VAD (Silero)
// - STT (Parakeet TDT-CTC 110M - NeMo CTC, ~126MB, int8 quantized)
// - TTS (Piper Lessac Medium - ~61MB, 22050Hz, natural male voice)
// =============================================================================

#include <string>
#include <cstdlib>
#include <cstring>
#include <sys/stat.h>

// Include RAC headers
#include <rac/infrastructure/model_management/rac_model_registry.h>
#include <rac/infrastructure/model_management/rac_model_paths.h>
#include <rac/infrastructure/model_management/rac_model_types.h>

namespace openclaw {

// =============================================================================
// Model IDs (NO LLM)
// =============================================================================

constexpr const char* VAD_MODEL_ID = "silero-vad";
constexpr const char* STT_MODEL_ID = "parakeet-tdt-ctc-110m-en-int8";  // Parakeet NeMo CTC (int8, ~126MB)
constexpr const char* TTS_MODEL_ID = "vits-piper-en_US-lessac-medium";  // Piper Lessac (22050Hz, ~61MB)

// Alternative models (kept for reference / fallback)
constexpr const char* STT_MODEL_ID_WHISPER = "whisper-tiny-en";
constexpr const char* TTS_MODEL_ID_KOKORO = "kokoro-en-v0_19";

// =============================================================================
// Model File Names
// =============================================================================

constexpr const char* VAD_MODEL_FILE = "silero_vad.onnx";
constexpr const char* STT_MODEL_FILE = "";  // Directory-based (Parakeet has model.int8.onnx + tokens.txt)
constexpr const char* TTS_MODEL_FILE = "en_US-lessac-medium.onnx";  // Piper model file

// =============================================================================
// Model Configuration
// =============================================================================

struct ModelConfig {
    const char* id;
    const char* name;
    const char* filename;
    rac_model_category_t category;
    rac_model_format_t format;
    rac_inference_framework_t framework;
    int64_t memory_required;
};

// Required models (NO LLM)
inline const ModelConfig REQUIRED_MODELS[] = {
    // VAD Model
    {
        .id = VAD_MODEL_ID,
        .name = "Silero VAD",
        .filename = VAD_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_AUDIO,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_SHERPA,
        .memory_required = 10 * 1024 * 1024
    },
    // STT Model (Parakeet TDT-CTC 110M - NeMo CTC, int8 quantized)
    {
        .id = STT_MODEL_ID,
        .name = "Parakeet TDT-CTC 110M EN (int8)",
        .filename = STT_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_SPEECH_RECOGNITION,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_SHERPA,
        .memory_required = 126 * 1024 * 1024  // ~126MB int8 quantized
    },
    // TTS Model (Piper Lessac Medium - VITS, 22050Hz, natural male voice)
    {
        .id = TTS_MODEL_ID,
        .name = "Piper Lessac Medium TTS",
        .filename = TTS_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_SHERPA,
        .memory_required = 65 * 1024 * 1024  // ~61MB model + espeak-ng-data
    }
};

constexpr size_t NUM_REQUIRED_MODELS = sizeof(REQUIRED_MODELS) / sizeof(REQUIRED_MODELS[0]);

// =============================================================================
// Path Resolution
// =============================================================================

inline std::string get_base_dir() {
    const char* home = getenv("HOME");
    if (!home || home[0] == '\0') {
        fprintf(stderr, "ERROR: HOME environment variable is not set\n");
        return "";
    }
    return std::string(home) + "/.local/share/runanywhere";
}

inline bool init_model_system() {
    std::string base_dir = get_base_dir();
    rac_result_t result = rac_model_paths_set_base_dir(base_dir.c_str());
    return result == RAC_SUCCESS;
}

inline const char* get_framework_subdir(rac_inference_framework_t framework) {
    switch (framework) {
        case RAC_FRAMEWORK_SHERPA:
            return "Sherpa";
        case RAC_FRAMEWORK_ONNX:
            return "ONNX";
        case RAC_FRAMEWORK_LLAMACPP:
            return "LlamaCpp";
        default:
            return "Other";
    }
}

inline std::string get_model_path(const ModelConfig& model) {
    std::string base_dir = get_base_dir();
    const char* framework_dir = get_framework_subdir(model.framework);

    std::string path = base_dir + "/Models/" + framework_dir + "/" + model.id;
    if (model.filename && model.filename[0] != '\0') {
        path += "/";
        path += model.filename;
    }
    return path;
}

// Convenience functions
inline std::string get_vad_model_path() {
    return get_model_path(REQUIRED_MODELS[0]);
}

inline std::string get_stt_model_path() {
    return get_model_path(REQUIRED_MODELS[1]);
}

inline std::string get_tts_model_path() {
    return get_model_path(REQUIRED_MODELS[2]);
}

inline std::string get_earcon_path() {
    return get_base_dir() + "/Models/ONNX/earcon/acknowledgment.wav";
}

// =============================================================================
// Model Availability
// =============================================================================

inline bool is_model_available(const ModelConfig& model) {
    std::string path = get_model_path(model);
    if (path.empty()) return false;
    struct stat st;
    if (stat(path.c_str(), &st) != 0) return false;

    // If path is a directory (model with empty filename), verify required files exist
    if (S_ISDIR(st.st_mode)) {
        // Check for at least a tokens file (common to all ONNX models)
        std::string tokens_path = path + "/tokens.txt";
        struct stat tokens_st;
        return stat(tokens_path.c_str(), &tokens_st) == 0;
    }

    return true;  // File exists
}

inline bool are_all_models_available() {
    for (size_t i = 0; i < NUM_REQUIRED_MODELS; ++i) {
        if (!is_model_available(REQUIRED_MODELS[i])) {
            return false;
        }
    }
    return true;
}

inline void print_model_status() {
    printf("Required Models (NO LLM):\n");
    for (size_t i = 0; i < NUM_REQUIRED_MODELS; ++i) {
        const ModelConfig& model = REQUIRED_MODELS[i];
        bool available = is_model_available(model);
        printf("  [%s] %s (%s)\n",
               available ? "OK" : "MISSING",
               model.name,
               model.id);
        if (!available) {
            printf("       Expected at: %s\n", get_model_path(model).c_str());
        }
    }
}

} // namespace openclaw
