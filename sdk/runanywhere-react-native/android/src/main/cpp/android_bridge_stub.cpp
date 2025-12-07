/**
 * android_bridge_stub.cpp
 *
 * Stub implementation of the runanywhere_bridge API for Android.
 * This provides the ra_* C API by directly interfacing with librunanywhere_llamacpp.so
 * without requiring librunanywhere_bridge.so (which has ONNX binary compatibility issues).
 *
 * This stub only supports the LlamaCpp backend for text generation.
 * STT/TTS/VAD features require the full bridge with ONNX support.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <dlfcn.h>
#include <android/log.h>

// Include the bridge API header to get the function signatures
#include "runanywhere_bridge.h"

#define LOG_TAG "RunAnywhereBridgeStub"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

// Global state
static const char* g_last_error = nullptr;
static bool g_llamacpp_registered = false;

// Forward declaration of LlamaCpp registration function
namespace runanywhere {
    void register_llamacpp_backend();
}

// ============================================================================
// Backend Lifecycle - Stub Implementation
// ============================================================================

const char** ra_get_available_backends(int* count) {
    static const char* backends[] = { "llamacpp" };

    // Register LlamaCpp backend on first call
    if (!g_llamacpp_registered) {
        LOGI("Registering LlamaCpp backend...");
        try {
            runanywhere::register_llamacpp_backend();
            g_llamacpp_registered = true;
            LOGI("LlamaCpp backend registered successfully");
        } catch (...) {
            LOGE("Failed to register LlamaCpp backend");
        }
    }

    if (count) *count = 1;
    return backends;
}

ra_backend_handle ra_create_backend(const char* backend_name) {
    LOGI("ra_create_backend called with: %s", backend_name);

    if (!backend_name || strcmp(backend_name, "llamacpp") != 0) {
        g_last_error = "Only 'llamacpp' backend is supported on Android (ONNX support requires compatible binaries)";
        LOGW("%s", g_last_error);
        return nullptr;
    }

    // Ensure backend is registered
    if (!g_llamacpp_registered) {
        ra_get_available_backends(nullptr);
    }

    // TODO: Create actual backend instance through LlamaCpp API
    // For now, return a placeholder handle
    // The actual implementation would call into the registered LlamaCpp backend factory

    g_last_error = "LlamaCpp backend creation not yet implemented in stub";
    LOGW("%s", g_last_error);
    return nullptr;
}

ra_result_code ra_initialize(ra_backend_handle handle, const char* config_json) {
    if (!handle) {
        g_last_error = "Invalid handle";
        return RA_ERROR_INVALID_ARGUMENT;
    }

    // TODO: Initialize the backend
    return RA_ERROR_NOT_IMPLEMENTED;
}

bool ra_is_initialized(ra_backend_handle handle) {
    return handle != nullptr;
}

void ra_destroy(ra_backend_handle handle) {
    // TODO: Cleanup backend resources
}

char* ra_get_backend_info(ra_backend_handle handle) {
    if (!handle) return nullptr;

    const char* info = "{\"backend\":\"llamacpp\",\"status\":\"stub\"}";
    char* result = (char*)malloc(strlen(info) + 1);
    if (result) strcpy(result, info);
    return result;
}

bool ra_supports_capability(ra_backend_handle handle, ra_capability_type capability) {
    if (!handle) return false;

    // LlamaCpp only supports text generation
    return capability == RA_CAP_TEXT_GENERATION;
}

int ra_get_capabilities(ra_backend_handle handle, ra_capability_type* capabilities, int max_count) {
    if (!handle || !capabilities || max_count < 1) return 0;

    capabilities[0] = RA_CAP_TEXT_GENERATION;
    return 1;
}

ra_device_type ra_get_device(ra_backend_handle handle) {
    return RA_DEVICE_CPU;
}

size_t ra_get_memory_usage(ra_backend_handle handle) {
    return 0;
}

// ============================================================================
// Text Generation - Stub Implementation
// ============================================================================

ra_result_code ra_text_load_model(ra_backend_handle handle, const char* model_path, const char* config_json) {
    LOGI("ra_text_load_model called with: %s", model_path);
    g_last_error = "Text model loading not yet implemented in Android stub";
    return RA_ERROR_NOT_IMPLEMENTED;
}

bool ra_text_is_model_loaded(ra_backend_handle handle) {
    return false;
}

ra_result_code ra_text_unload_model(ra_backend_handle handle) {
    return RA_SUCCESS;
}

ra_result_code ra_text_generate(
    ra_backend_handle handle,
    const char* prompt,
    const char* system_prompt,
    int max_tokens,
    float temperature,
    char** result_json
) {
    g_last_error = "Text generation not yet implemented in Android stub";
    return RA_ERROR_NOT_IMPLEMENTED;
}

ra_result_code ra_text_generate_stream(
    ra_backend_handle handle,
    const char* prompt,
    const char* system_prompt,
    int max_tokens,
    float temperature,
    ra_text_stream_callback callback,
    void* user_data
) {
    g_last_error = "Streaming text generation not yet implemented in Android stub";
    return RA_ERROR_NOT_IMPLEMENTED;
}

void ra_text_cancel(ra_backend_handle handle) {
    // No-op
}

// ============================================================================
// Embeddings - Not Supported in Stub
// ============================================================================

ra_result_code ra_embed_load_model(ra_backend_handle handle, const char* model_path, const char* config_json) {
    g_last_error = "Embeddings not supported in Android stub (requires ONNX)";
    return RA_ERROR_NOT_SUPPORTED;
}

bool ra_embed_is_model_loaded(ra_backend_handle handle) { return false; }
ra_result_code ra_embed_unload_model(ra_backend_handle handle) { return RA_SUCCESS; }

ra_result_code ra_embed_text(ra_backend_handle handle, const char* text, float** embedding, int* dimensions) {
    g_last_error = "Embeddings not supported in Android stub";
    return RA_ERROR_NOT_SUPPORTED;
}

ra_result_code ra_embed_batch(ra_backend_handle handle, const char** texts, int num_texts, float*** embeddings, int* dimensions) {
    g_last_error = "Embeddings not supported in Android stub";
    return RA_ERROR_NOT_SUPPORTED;
}

int ra_embed_get_dimensions(ra_backend_handle handle) { return 0; }
void ra_free_embedding(float* embedding) { if (embedding) free(embedding); }
void ra_free_embeddings(float** embeddings, int count) {
    if (embeddings) {
        for (int i = 0; i < count; i++) {
            if (embeddings[i]) free(embeddings[i]);
        }
        free(embeddings);
    }
}

// ============================================================================
// STT - Not Supported in Stub
// ============================================================================

ra_result_code ra_stt_load_model(ra_backend_handle handle, const char* model_path, const char* model_type, const char* config_json) {
    g_last_error = "STT not supported in Android stub (requires ONNX + Sherpa)";
    return RA_ERROR_NOT_SUPPORTED;
}

bool ra_stt_is_model_loaded(ra_backend_handle handle) { return false; }
ra_result_code ra_stt_unload_model(ra_backend_handle handle) { return RA_SUCCESS; }

ra_result_code ra_stt_transcribe(ra_backend_handle handle, const float* audio_samples, size_t num_samples,
                                  int sample_rate, const char* language, char** result_json) {
    g_last_error = "STT not supported in Android stub";
    return RA_ERROR_NOT_SUPPORTED;
}

bool ra_stt_supports_streaming(ra_backend_handle handle) { return false; }
ra_stream_handle ra_stt_create_stream(ra_backend_handle handle, const char* config_json) { return nullptr; }
ra_result_code ra_stt_feed_audio(ra_backend_handle handle, ra_stream_handle stream, const float* samples,
                                  size_t num_samples, int sample_rate) { return RA_ERROR_NOT_SUPPORTED; }
bool ra_stt_is_ready(ra_backend_handle handle, ra_stream_handle stream) { return false; }
ra_result_code ra_stt_decode(ra_backend_handle handle, ra_stream_handle stream, char** result_json) { return RA_ERROR_NOT_SUPPORTED; }
bool ra_stt_is_endpoint(ra_backend_handle handle, ra_stream_handle stream) { return false; }
void ra_stt_input_finished(ra_backend_handle handle, ra_stream_handle stream) {}
void ra_stt_reset_stream(ra_backend_handle handle, ra_stream_handle stream) {}
void ra_stt_destroy_stream(ra_backend_handle handle, ra_stream_handle stream) {}
void ra_stt_cancel(ra_backend_handle handle) {}

// ============================================================================
// TTS - Not Supported in Stub
// ============================================================================

ra_result_code ra_tts_load_model(ra_backend_handle handle, const char* model_path, const char* model_type, const char* config_json) {
    g_last_error = "TTS not supported in Android stub (requires ONNX + Sherpa)";
    return RA_ERROR_NOT_SUPPORTED;
}

bool ra_tts_is_model_loaded(ra_backend_handle handle) { return false; }
ra_result_code ra_tts_unload_model(ra_backend_handle handle) { return RA_SUCCESS; }

ra_result_code ra_tts_synthesize(ra_backend_handle handle, const char* text, const char* voice_id,
                                  float speed_rate, float pitch_shift, float** audio_samples,
                                  size_t* num_samples, int* sample_rate) {
    g_last_error = "TTS not supported in Android stub";
    return RA_ERROR_NOT_SUPPORTED;
}

ra_result_code ra_tts_synthesize_stream(ra_backend_handle handle, const char* text, const char* voice_id,
                                         float speed_rate, float pitch_shift, ra_tts_stream_callback callback, void* user_data) {
    return RA_ERROR_NOT_SUPPORTED;
}

bool ra_tts_supports_streaming(ra_backend_handle handle) { return false; }
char* ra_tts_get_voices(ra_backend_handle handle) { return nullptr; }
void ra_tts_cancel(ra_backend_handle handle) {}
void ra_free_audio(float* audio_samples) { if (audio_samples) free(audio_samples); }

// ============================================================================
// VAD - Not Supported in Stub
// ============================================================================

ra_result_code ra_vad_load_model(ra_backend_handle handle, const char* model_path, const char* config_json) {
    g_last_error = "VAD not supported in Android stub (requires ONNX)";
    return RA_ERROR_NOT_SUPPORTED;
}

bool ra_vad_is_model_loaded(ra_backend_handle handle) { return false; }
ra_result_code ra_vad_unload_model(ra_backend_handle handle) { return RA_SUCCESS; }

ra_result_code ra_vad_process(ra_backend_handle handle, const float* samples, size_t num_samples,
                               int sample_rate, bool* is_speech, float* probability) {
    if (is_speech) *is_speech = false;
    if (probability) *probability = 0.0f;
    return RA_ERROR_NOT_SUPPORTED;
}

ra_result_code ra_vad_detect_segments(ra_backend_handle handle, const float* samples, size_t num_samples,
                                       int sample_rate, char** result_json) {
    return RA_ERROR_NOT_SUPPORTED;
}

ra_stream_handle ra_vad_create_stream(ra_backend_handle handle, const char* config_json) { return nullptr; }
ra_result_code ra_vad_feed_stream(ra_backend_handle handle, ra_stream_handle stream, const float* samples,
                                   size_t num_samples, int sample_rate, bool* is_speech, float* probability) {
    return RA_ERROR_NOT_SUPPORTED;
}
void ra_vad_destroy_stream(ra_backend_handle handle, ra_stream_handle stream) {}
void ra_vad_reset(ra_backend_handle handle) {}

// ============================================================================
// Diarization - Not Supported in Stub
// ============================================================================

ra_result_code ra_diarize_load_model(ra_backend_handle handle, const char* model_path, const char* config_json) {
    g_last_error = "Diarization not supported in Android stub";
    return RA_ERROR_NOT_SUPPORTED;
}

bool ra_diarize_is_model_loaded(ra_backend_handle handle) { return false; }
ra_result_code ra_diarize_unload_model(ra_backend_handle handle) { return RA_SUCCESS; }

ra_result_code ra_diarize(ra_backend_handle handle, const float* samples, size_t num_samples,
                           int sample_rate, int min_speakers, int max_speakers, char** result_json) {
    return RA_ERROR_NOT_SUPPORTED;
}

void ra_diarize_cancel(ra_backend_handle handle) {}

// ============================================================================
// Utility Functions
// ============================================================================

void ra_free_string(char* str) {
    if (str) free(str);
}

const char* ra_get_last_error(void) {
    return g_last_error ? g_last_error : "";
}

const char* ra_get_version(void) {
    return "0.0.1-android-stub";
}

ra_result_code ra_extract_archive(const char* archive_path, const char* dest_dir) {
    g_last_error = "Archive extraction not implemented in Android stub";
    return RA_ERROR_NOT_IMPLEMENTED;
}
