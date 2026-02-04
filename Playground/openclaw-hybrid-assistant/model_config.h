#pragma once

// =============================================================================
// Model Configuration for OpenClaw Hybrid Assistant
// =============================================================================
// Simplified configuration - NO LLM, only:
// - VAD (Silero)
// - STT (Whisper Tiny EN)
// - TTS (Piper Lessac)
// - Wake Word (openWakeWord - optional)
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
constexpr const char* STT_MODEL_ID = "whisper-tiny-en";
constexpr const char* TTS_MODEL_ID = "kokoro-en-v0_19";  // Kokoro TTS English (24kHz, 11 speakers)

// Piper TTS (alternative, smaller model)
constexpr const char* TTS_MODEL_ID_PIPER = "vits-piper-en_US-lessac-medium";

// Wake word models (optional)
constexpr const char* WAKEWORD_MODEL_ID = "hey-jarvis";
constexpr const char* WAKEWORD_EMBEDDING_ID = "openwakeword-embedding";

// =============================================================================
// Model File Names
// =============================================================================

constexpr const char* VAD_MODEL_FILE = "silero_vad.onnx";
constexpr const char* STT_MODEL_FILE = "";  // Directory-based
constexpr const char* TTS_MODEL_FILE = "model.onnx";  // Kokoro uses model.onnx + voices.bin
constexpr const char* TTS_VOICES_FILE = "voices.bin";  // Kokoro voice embeddings

// Piper TTS files (alternative model)
constexpr const char* TTS_MODEL_FILE_PIPER = "en_US-lessac-medium.onnx";

// Wake word model files
constexpr const char* WAKEWORD_MODEL_FILE = "hey_jarvis_v0.1.onnx";
constexpr const char* WAKEWORD_EMBEDDING_FILE = "embedding_model.onnx";
constexpr const char* WAKEWORD_MELSPEC_FILE = "melspectrogram.onnx";

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
        .framework = RAC_FRAMEWORK_ONNX,
        .memory_required = 10 * 1024 * 1024
    },
    // STT Model
    {
        .id = STT_MODEL_ID,
        .name = "Whisper Tiny English",
        .filename = STT_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_SPEECH_RECOGNITION,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_ONNX,
        .memory_required = 150 * 1024 * 1024
    },
    // TTS Model (Kokoro English - high quality, 24kHz, 11 speakers)
    {
        .id = TTS_MODEL_ID,
        .name = "Kokoro TTS English v0.19",
        .filename = TTS_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_ONNX,
        .memory_required = 340 * 1024 * 1024  // ~330MB model + ~6MB voices
    }
};

// Wake word models (optional)
inline const ModelConfig WAKEWORD_MODELS[] = {
    {
        .id = WAKEWORD_MODEL_ID,
        .name = "Hey Jarvis Wake Word",
        .filename = WAKEWORD_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_AUDIO,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_ONNX,
        .memory_required = 5 * 1024 * 1024
    },
    {
        .id = WAKEWORD_EMBEDDING_ID,
        .name = "openWakeWord Embedding",
        .filename = WAKEWORD_EMBEDDING_FILE,
        .category = RAC_MODEL_CATEGORY_AUDIO,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_ONNX,
        .memory_required = 15 * 1024 * 1024
    }
};

constexpr size_t NUM_REQUIRED_MODELS = sizeof(REQUIRED_MODELS) / sizeof(REQUIRED_MODELS[0]);
constexpr size_t NUM_WAKEWORD_MODELS = sizeof(WAKEWORD_MODELS) / sizeof(WAKEWORD_MODELS[0]);

// =============================================================================
// Path Resolution
// =============================================================================

inline std::string get_base_dir() {
    const char* home = getenv("HOME");
    if (!home) {
        home = "/tmp";
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
    if (model.filename[0] != '\0') {
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

inline std::string get_wakeword_model_path() {
    return get_model_path(WAKEWORD_MODELS[0]);
}

inline std::string get_wakeword_embedding_path() {
    return get_model_path(WAKEWORD_MODELS[1]);
}

inline std::string get_wakeword_melspec_path() {
    std::string base_dir = get_base_dir();
    return base_dir + "/Models/ONNX/" + WAKEWORD_EMBEDDING_ID + "/" + WAKEWORD_MELSPEC_FILE;
}

// =============================================================================
// Model Availability
// =============================================================================

inline bool is_model_available(const ModelConfig& model) {
    std::string path = get_model_path(model);
    struct stat st;
    return stat(path.c_str(), &st) == 0;
}

inline bool are_all_models_available() {
    for (size_t i = 0; i < NUM_REQUIRED_MODELS; ++i) {
        if (!is_model_available(REQUIRED_MODELS[i])) {
            return false;
        }
    }
    return true;
}

inline bool are_wakeword_models_available() {
    for (size_t i = 0; i < NUM_WAKEWORD_MODELS; ++i) {
        if (!is_model_available(WAKEWORD_MODELS[i])) {
            return false;
        }
    }
    return true;
}

inline void print_model_status(bool include_wakeword = false) {
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

    if (include_wakeword) {
        printf("\nWake Word Models (optional):\n");
        for (size_t i = 0; i < NUM_WAKEWORD_MODELS; ++i) {
            const ModelConfig& model = WAKEWORD_MODELS[i];
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
}

} // namespace openclaw
