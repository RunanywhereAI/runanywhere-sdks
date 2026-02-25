#ifndef TEST_CONFIG_H
#define TEST_CONFIG_H

#include <climits>
#include <cstdlib>
#include <string>
#include <sys/stat.h>

#include "test_common.h"

namespace test_config {

// =============================================================================
// File Utilities
// =============================================================================

inline bool file_exists(const std::string& path) {
    struct stat st;
    return (stat(path.c_str(), &st) == 0);
}

inline bool require_model(const std::string& path, const std::string& name,
                           TestResult& result) {
    if (!file_exists(path)) {
        result.test_name = name;
        result.passed = true; // SKIPPED counts as pass (not a failure)
        result.details = "SKIPPED - model not found: " + path;
        return false;
    }
    return true;
}

// =============================================================================
// Environment / Path Helpers
// =============================================================================

inline std::string get_home_dir() {
    const char* home = std::getenv("HOME");
    if (home) return std::string(home);
    return "";
}

inline std::string get_model_dir() {
    const char* env = std::getenv("RAC_TEST_MODEL_DIR");
    if (env && env[0] != '\0') return std::string(env);
    return get_home_dir() + "/.local/share/runanywhere/Models";
}

// =============================================================================
// VAD
// =============================================================================

inline std::string get_vad_model_path() {
    const char* env = std::getenv("RAC_TEST_VAD_MODEL");
    if (env && env[0] != '\0') return std::string(env);
    return get_model_dir() + "/ONNX/silero-vad/silero_vad.onnx";
}

// =============================================================================
// STT (Whisper)
// =============================================================================

inline std::string get_stt_model_path() {
    const char* env = std::getenv("RAC_TEST_STT_MODEL");
    if (env && env[0] != '\0') return std::string(env);
    return get_model_dir() + "/ONNX/whisper-tiny-en";
}

// =============================================================================
// TTS (Piper / VITS)
// =============================================================================

inline std::string get_tts_model_path() {
    const char* env = std::getenv("RAC_TEST_TTS_MODEL");
    if (env && env[0] != '\0') return std::string(env);
    return get_model_dir() + "/ONNX/vits-piper-en_US-lessac-medium";
}

// =============================================================================
// LLM (LlamaCPP)
// =============================================================================

inline std::string get_llm_model_path() {
    const char* env = std::getenv("RAC_TEST_LLM_MODEL");
    if (env && env[0] != '\0') return std::string(env);
    return get_model_dir() + "/LlamaCpp/qwen3-0.6b/Qwen3-0.6B-Q8_0.gguf";
}

// =============================================================================
// WakeWord (openWakeWord)
// =============================================================================

inline std::string resolve_wakeword_dir() {
    // Try both directory naming conventions used by different playground apps
    std::string dir1 = get_model_dir() + "/ONNX/openwakeword";
    std::string dir2 = get_model_dir() + "/ONNX/openwakeword-embedding";

    if (file_exists(dir1)) return dir1;
    if (file_exists(dir2)) return dir2;

    // Default to the primary name; require_model will handle the skip
    return dir1;
}

inline std::string get_wakeword_embedding_path() {
    // Check both possible directories for embedding_model.onnx
    std::string dir1 = get_model_dir() + "/ONNX/openwakeword";
    std::string dir2 = get_model_dir() + "/ONNX/openwakeword-embedding";

    std::string path1 = dir1 + "/embedding_model.onnx";
    std::string path2 = dir2 + "/embedding_model.onnx";

    if (file_exists(path1)) return path1;
    if (file_exists(path2)) return path2;

    // Return primary path as default
    return path1;
}

inline std::string get_wakeword_melspec_path() {
    // Check both possible directories for melspectrogram.onnx
    std::string dir1 = get_model_dir() + "/ONNX/openwakeword";
    std::string dir2 = get_model_dir() + "/ONNX/openwakeword-embedding";

    std::string path1 = dir1 + "/melspectrogram.onnx";
    std::string path2 = dir2 + "/melspectrogram.onnx";

    if (file_exists(path1)) return path1;
    if (file_exists(path2)) return path2;

    // Return primary path as default
    return path1;
}

inline std::string get_wakeword_model_path() {
    const char* env = std::getenv("RAC_TEST_WAKEWORD_MODEL");
    if (env && env[0] != '\0') return std::string(env);
    return get_model_dir() + "/ONNX/hey-jarvis/hey_jarvis_v0.1.onnx";
}

// =============================================================================
// Test Audio Directory
// =============================================================================

/**
 * Resolve test audio directory. Checks in order:
 * 1. RAC_TEST_AUDIO_DIR env var
 * 2. Auto-detect by walking up from CWD to find Playground/openclaw-hybrid-assistant/tests/audio/
 */
inline std::string get_test_audio_dir() {
    const char* env = std::getenv("RAC_TEST_AUDIO_DIR");
    if (env && env[0] != '\0') return std::string(env);

    // Auto-detect: walk up from current directory looking for the Playground audio dir
    // We're typically running from sdk/runanywhere-commons/build/test/tests/
    // Repo root is 5+ levels up. Try several relative paths from known structure.
    std::string suffixes[] = {
        "/Playground/openclaw-hybrid-assistant/tests/audio",
    };

    // Try walking up from CWD (up to 8 levels)
    std::string base = ".";
    for (int depth = 0; depth < 8; ++depth) {
        for (const auto& suffix : suffixes) {
            std::string candidate = base + suffix;
            if (file_exists(candidate)) {
                // Resolve to absolute path so read_wav works from any CWD
                char resolved[PATH_MAX];
                if (realpath(candidate.c_str(), resolved)) {
                    return std::string(resolved);
                }
                return candidate; // fallback to relative
            }
        }
        base += "/..";
    }

    return "";
}

/** Get full path to a test audio file. Returns empty string if audio dir not found. */
inline std::string get_test_audio_file(const std::string& filename) {
    std::string dir = get_test_audio_dir();
    if (dir.empty()) return "";
    return dir + "/" + filename;
}

/** Check if test audio directory is available with WAV files. */
inline bool has_test_audio() {
    std::string dir = get_test_audio_dir();
    if (dir.empty()) return false;
    // Check for at least one known file
    return file_exists(dir + "/hey-jarvis-real.wav");
}

/** Require a test audio file, mark as SKIPPED if not found. */
inline bool require_audio_file(const std::string& path, const std::string& test_name,
                                TestResult& result) {
    if (path.empty() || !file_exists(path)) {
        result.test_name = test_name;
        result.passed = true;
        result.details = "SKIPPED - test audio not found: " +
                         (path.empty() ? "(audio dir not configured)" : path);
        return false;
    }
    return true;
}

} // namespace test_config

#endif // TEST_CONFIG_H
