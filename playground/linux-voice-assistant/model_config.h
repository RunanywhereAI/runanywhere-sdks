#pragma once

// =============================================================================
// Model Configuration for Linux Voice Assistant
// =============================================================================
// Pre-configured model IDs and paths for the Raspberry Pi 5 voice assistant.
// Models are hardcoded - no runtime selection. This ensures predictable behavior.
//
// Model Storage Structure:
//   ~/.local/share/runanywhere/Models/
//   ├── ONNX/
//   │   ├── silero-vad/silero_vad.onnx
//   │   ├── whisper-tiny-en/
//   │   └── vits-piper-en_US-lessac-medium/
//   └── LlamaCpp/
//       └── qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf
// =============================================================================

#include <string>
#include <cstdlib>
#include <cstring>
#include <sys/stat.h>

// Include RAC headers
#include <rac/infrastructure/model_management/rac_model_registry.h>
#include <rac/infrastructure/model_management/rac_model_paths.h>
#include <rac/infrastructure/model_management/rac_model_types.h>

namespace runanywhere {

// =============================================================================
// Pre-configured Model IDs (hardcoded - no runtime selection)
// =============================================================================

constexpr const char* VAD_MODEL_ID = "silero-vad";
constexpr const char* STT_MODEL_ID = "whisper-tiny-en";
constexpr const char* LLM_MODEL_ID = "qwen2.5-0.5b-instruct-q4";
constexpr const char* TTS_MODEL_ID = "vits-piper-en_US-lessac-medium";

// Wake word models (optional - enabled via command line)
constexpr const char* WAKEWORD_MODEL_ID = "hey-jarvis";
constexpr const char* WAKEWORD_EMBEDDING_ID = "openwakeword-embedding";

// =============================================================================
// Model File Names
// =============================================================================

constexpr const char* VAD_MODEL_FILE = "silero_vad.onnx";
// STT uses directory path (backend scans for encoder/decoder/tokens files)
constexpr const char* STT_MODEL_FILE = "";
constexpr const char* LLM_MODEL_FILE = "qwen2.5-0.5b-instruct-q4_k_m.gguf";
constexpr const char* TTS_MODEL_FILE = "en_US-lessac-medium.onnx";

// Wake word model files
constexpr const char* WAKEWORD_MODEL_FILE = "hey_jarvis_v0.1.onnx";
constexpr const char* WAKEWORD_EMBEDDING_FILE = "embedding_model.onnx";

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
    int64_t memory_required;  // bytes
    int32_t context_length;   // for LLMs only
};

// Pre-configured models for the voice assistant (required)
inline const ModelConfig REQUIRED_MODELS[] = {
    // VAD Model
    {
        .id = VAD_MODEL_ID,
        .name = "Silero VAD",
        .filename = VAD_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_AUDIO,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_ONNX,
        .memory_required = 10 * 1024 * 1024,  // ~10MB
        .context_length = 0
    },
    // STT Model
    {
        .id = STT_MODEL_ID,
        .name = "Whisper Tiny English",
        .filename = STT_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_SPEECH_RECOGNITION,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_ONNX,
        .memory_required = 150 * 1024 * 1024,  // ~150MB
        .context_length = 0
    },
    // LLM Model
    {
        .id = LLM_MODEL_ID,
        .name = "Qwen2.5 0.5B Instruct Q4",
        .filename = LLM_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_LANGUAGE,
        .format = RAC_MODEL_FORMAT_GGUF,
        .framework = RAC_FRAMEWORK_LLAMACPP,
        .memory_required = 500 * 1024 * 1024,  // ~500MB
        .context_length = 4096
    },
    // TTS Model
    {
        .id = TTS_MODEL_ID,
        .name = "VITS Piper English US (Lessac)",
        .filename = TTS_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_ONNX,
        .memory_required = 50 * 1024 * 1024,  // ~50MB
        .context_length = 0
    }
};

// Optional wake word models
inline const ModelConfig WAKEWORD_MODELS[] = {
    // Wake Word Detection Model (openWakeWord)
    {
        .id = WAKEWORD_MODEL_ID,
        .name = "Hey Jarvis Wake Word",
        .filename = WAKEWORD_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_AUDIO,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_ONNX,
        .memory_required = 5 * 1024 * 1024,  // ~5MB
        .context_length = 0
    },
    // openWakeWord Embedding Model (shared backbone)
    {
        .id = WAKEWORD_EMBEDDING_ID,
        .name = "openWakeWord Embedding",
        .filename = WAKEWORD_EMBEDDING_FILE,
        .category = RAC_MODEL_CATEGORY_AUDIO,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_ONNX,
        .memory_required = 15 * 1024 * 1024,  // ~15MB
        .context_length = 0
    }
};

constexpr size_t NUM_REQUIRED_MODELS = sizeof(REQUIRED_MODELS) / sizeof(REQUIRED_MODELS[0]);
constexpr size_t NUM_WAKEWORD_MODELS = sizeof(WAKEWORD_MODELS) / sizeof(WAKEWORD_MODELS[0]);

// Backward compatibility alias
inline const ModelConfig* MODELS = REQUIRED_MODELS;
constexpr size_t NUM_MODELS = NUM_REQUIRED_MODELS;

// =============================================================================
// Model System Initialization
// =============================================================================

// Get the base directory for model storage
inline std::string get_base_dir() {
    const char* home = getenv("HOME");
    if (!home) {
        home = "/tmp";
    }
    return std::string(home) + "/.local/share/runanywhere";
}

// Initialize the model path system
inline bool init_model_system() {
    std::string base_dir = get_base_dir();
    rac_result_t result = rac_model_paths_set_base_dir(base_dir.c_str());
    return result == RAC_SUCCESS;
}

// =============================================================================
// Model Path Resolution
// =============================================================================

// Get the framework subdirectory name
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

// Get the full path to a model file (or directory if filename is empty)
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

// Convenience functions for each model type
inline std::string get_vad_model_path() {
    return get_model_path(REQUIRED_MODELS[0]);  // VAD is first
}

inline std::string get_stt_model_path() {
    return get_model_path(REQUIRED_MODELS[1]);  // STT is second
}

inline std::string get_llm_model_path() {
    return get_model_path(REQUIRED_MODELS[2]);  // LLM is third
}

inline std::string get_tts_model_path() {
    return get_model_path(REQUIRED_MODELS[3]);  // TTS is fourth
}

// Wake word model paths (optional)
inline std::string get_wakeword_model_path() {
    return get_model_path(WAKEWORD_MODELS[0]);
}

inline std::string get_wakeword_embedding_path() {
    return get_model_path(WAKEWORD_MODELS[1]);
}

// =============================================================================
// Model Registration (optional - for metadata tracking)
// =============================================================================

// Register all pre-configured models with the registry
inline bool register_models(rac_model_registry_handle_t registry) {
    for (size_t i = 0; i < NUM_MODELS; ++i) {
        const ModelConfig& cfg = MODELS[i];

        rac_model_info_t* model = rac_model_info_alloc();
        if (!model) {
            return false;
        }

        model->id = strdup(cfg.id);
        model->name = strdup(cfg.name);
        model->category = cfg.category;
        model->format = cfg.format;
        model->framework = cfg.framework;
        model->memory_required = cfg.memory_required;
        model->context_length = cfg.context_length;

        // Set the local path
        std::string path = get_model_path(cfg);
        model->local_path = strdup(path.c_str());

        rac_result_t result = rac_model_registry_save(registry, model);
        rac_model_info_free(model);

        if (result != RAC_SUCCESS) {
            return false;
        }
    }

    return true;
}

// =============================================================================
// Model Availability Check
// =============================================================================

// Check if a model file or directory exists
inline bool is_model_available(const ModelConfig& model) {
    std::string path = get_model_path(model);
    struct stat st;
    return stat(path.c_str(), &st) == 0;
}

// Check if all required models are available
inline bool are_all_models_available() {
    for (size_t i = 0; i < NUM_REQUIRED_MODELS; ++i) {
        if (!is_model_available(REQUIRED_MODELS[i])) {
            return false;
        }
    }
    return true;
}

// Check if wake word models are available
inline bool are_wakeword_models_available() {
    for (size_t i = 0; i < NUM_WAKEWORD_MODELS; ++i) {
        if (!is_model_available(WAKEWORD_MODELS[i])) {
            return false;
        }
    }
    return true;
}

// Print model status
inline void print_model_status(bool include_wakeword = false) {
    printf("Required Models:\n");
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

} // namespace runanywhere
