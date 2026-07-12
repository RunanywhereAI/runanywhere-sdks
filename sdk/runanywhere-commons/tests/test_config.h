#ifndef TEST_CONFIG_H
#define TEST_CONFIG_H

#include <cstdlib>
#include <string>

#include "core/internal/platform_compat.h"

#include "test_common.h"

namespace test_config {

// =============================================================================
// File Utilities
// =============================================================================

inline bool file_exists(const std::string& path) {
    struct stat st;
    return (stat(path.c_str(), &st) == 0);
}

inline bool require_real_artifacts() {
    const char* env = std::getenv("RAC_TEST_REQUIRE_MODELS");
    return env && env[0] != '\0' && std::string(env) != "0";
}

inline bool require_model(const std::string& path, const std::string& name, TestResult& result) {
    if (!file_exists(path)) {
        result.test_name = name;
        result.passed = !require_real_artifacts();
        result.details = (result.passed ? "SKIPPED" : "REQUIRED MODEL MISSING");
        result.details += " - model not found: " + path;
        return false;
    }
    return true;
}

// =============================================================================
// Environment / Path Helpers
// =============================================================================

inline std::string get_home_dir() {
    const char* home = std::getenv("HOME");
    if (home)
        return std::string(home);
    return "";
}

inline std::string get_model_dir() {
    const char* env = std::getenv("RAC_TEST_MODEL_DIR");
    if (env && env[0] != '\0')
        return std::string(env);
    return get_home_dir() + "/.local/share/runanywhere/Models";
}

// =============================================================================
// VAD
// =============================================================================

inline std::string get_vad_model_path() {
    const char* env = std::getenv("RAC_TEST_VAD_MODEL");
    if (env && env[0] != '\0')
        return std::string(env);
    return get_model_dir() + "/ONNX/silero-vad/silero_vad.onnx";
}

// =============================================================================
// STT (Whisper)
// =============================================================================

inline std::string get_stt_model_path() {
    const char* env = std::getenv("RAC_TEST_STT_MODEL");
    if (env && env[0] != '\0')
        return std::string(env);
    return get_model_dir() + "/ONNX/whisper-tiny-en";
}

// =============================================================================
// TTS (Piper / VITS)
// =============================================================================

inline std::string get_tts_model_path() {
    const char* env = std::getenv("RAC_TEST_TTS_MODEL");
    if (env && env[0] != '\0')
        return std::string(env);
    return get_model_dir() + "/ONNX/vits-piper-en_US-lessac-medium";
}

// =============================================================================
// LLM (LlamaCPP)
// =============================================================================

inline std::string get_llm_model_path() {
    const char* env = std::getenv("RAC_TEST_LLM_MODEL");
    if (env && env[0] != '\0')
        return std::string(env);
    return get_model_dir() + "/LlamaCpp/qwen3-0.6b/Qwen3-0.6B-Q8_0.gguf";
}

// =============================================================================
}  // namespace test_config

#endif  // TEST_CONFIG_H
