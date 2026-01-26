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
//   │   └── vits-piper-en-us/
//   └── LlamaCpp/
//       └── qwen2.5-0.5b-instruct-q4/qwen2.5-0.5b-instruct-q4_k_m.gguf
// =============================================================================

#include <string>
#include <cstdlib>

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
constexpr const char* TTS_MODEL_ID = "vits-piper-en-us";

// =============================================================================
// Model File Names
// =============================================================================

constexpr const char* VAD_MODEL_FILE = "silero_vad.onnx";
constexpr const char* STT_MODEL_FILE = "whisper-tiny.en-encoder.onnx";
constexpr const char* LLM_MODEL_FILE = "qwen2.5-0.5b-instruct-q4_k_m.gguf";
constexpr const char* TTS_MODEL_FILE = "en_US-amy-medium.onnx";

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

// Pre-configured models for the voice assistant
inline const ModelConfig MODELS[] = {
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
        .name = "VITS Piper English US (Amy)",
        .filename = TTS_MODEL_FILE,
        .category = RAC_MODEL_CATEGORY_SPEECH_SYNTHESIS,
        .format = RAC_MODEL_FORMAT_ONNX,
        .framework = RAC_FRAMEWORK_ONNX,
        .memory_required = 50 * 1024 * 1024,  // ~50MB
        .context_length = 0
    }
};

constexpr size_t NUM_MODELS = sizeof(MODELS) / sizeof(MODELS[0]);

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
    return result == RAC_RESULT_SUCCESS;
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

// Get the full path to a model file
inline std::string get_model_path(const ModelConfig& model) {
    std::string base_dir = get_base_dir();
    const char* framework_dir = get_framework_subdir(model.framework);

    return base_dir + "/Models/" + framework_dir + "/" + model.id + "/" + model.filename;
}

// Convenience functions for each model type
inline std::string get_vad_model_path() {
    return get_model_path(MODELS[0]);  // VAD is first
}

inline std::string get_stt_model_path() {
    return get_model_path(MODELS[1]);  // STT is second
}

inline std::string get_llm_model_path() {
    return get_model_path(MODELS[2]);  // LLM is third
}

inline std::string get_tts_model_path() {
    return get_model_path(MODELS[3]);  // TTS is fourth
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

        if (result != RAC_RESULT_SUCCESS) {
            return false;
        }
    }

    return true;
}

// =============================================================================
// Model Availability Check
// =============================================================================

// Check if a model file exists
inline bool is_model_available(const ModelConfig& model) {
    std::string path = get_model_path(model);
    FILE* f = fopen(path.c_str(), "r");
    if (f) {
        fclose(f);
        return true;
    }
    return false;
}

// Check if all required models are available
inline bool are_all_models_available() {
    for (size_t i = 0; i < NUM_MODELS; ++i) {
        if (!is_model_available(MODELS[i])) {
            return false;
        }
    }
    return true;
}

// Print model status
inline void print_model_status() {
    printf("Model Status:\n");
    for (size_t i = 0; i < NUM_MODELS; ++i) {
        const ModelConfig& model = MODELS[i];
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

} // namespace runanywhere
