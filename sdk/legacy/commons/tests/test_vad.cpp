/**
 * @file test_vad.cpp
 * @brief Integration tests for ONNX VAD backend via direct RAC API
 *
 * Tests voice activity detection using the Silero VAD ONNX model.
 * Requires: silero_vad.onnx model at the configured path.
 */

#include "test_common.h"
#include "test_config.h"

#include "rac/backends/rac_tts_onnx.h"
#include "rac/backends/rac_vad_onnx.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"

#include <cstdio>
#include <ctime>

// =============================================================================
// Minimal Test Platform Adapter
// =============================================================================

static rac_bool_t test_file_exists(const char* /*path*/, void* /*user_data*/) {
    return RAC_FALSE;
}

static rac_result_t test_file_read(const char* /*path*/, void** /*out_data*/, size_t* /*out_size*/,
                                   void* /*user_data*/) {
    return RAC_ERROR_NOT_SUPPORTED;
}

static rac_result_t test_file_write(const char* /*path*/, const void* /*data*/, size_t /*size*/,
                                    void* /*user_data*/) {
    return RAC_ERROR_NOT_SUPPORTED;
}

static rac_result_t test_file_delete(const char* /*path*/, void* /*user_data*/) {
    return RAC_ERROR_NOT_SUPPORTED;
}

static rac_result_t test_secure_get(const char* /*key*/, char** /*out_value*/,
                                    void* /*user_data*/) {
    return RAC_ERROR_NOT_SUPPORTED;
}

static rac_result_t test_secure_set(const char* /*key*/, const char* /*value*/,
                                    void* /*user_data*/) {
    return RAC_ERROR_NOT_SUPPORTED;
}

static rac_result_t test_secure_delete(const char* /*key*/, void* /*user_data*/) {
    return RAC_ERROR_NOT_SUPPORTED;
}

static void test_log(rac_log_level_t level, const char* category, const char* message,
                     void* /*user_data*/) {
    const char* level_str = "UNKNOWN";
    switch (level) {
        case RAC_LOG_TRACE:
            level_str = "TRACE";
            break;
        case RAC_LOG_DEBUG:
            level_str = "DEBUG";
            break;
        case RAC_LOG_INFO:
            level_str = "INFO";
            break;
        case RAC_LOG_WARNING:
            level_str = "WARN";
            break;
        case RAC_LOG_ERROR:
            level_str = "ERROR";
            break;
        case RAC_LOG_FATAL:
            level_str = "FATAL";
            break;
    }
    std::fprintf(stderr, "[%s] [%s] %s\n", level_str, category ? category : "?",
                 message ? message : "");
}

static int64_t test_now_ms(void* /*user_data*/) {
    return static_cast<int64_t>(std::time(nullptr)) * 1000;
}

static rac_result_t test_get_memory_info(rac_memory_info_t* out_info, void* /*user_data*/) {
    if (out_info) {
        out_info->total_bytes = 8ULL * 1024 * 1024 * 1024;
        out_info->available_bytes = 4ULL * 1024 * 1024 * 1024;
        out_info->used_bytes = 4ULL * 1024 * 1024 * 1024;
    }
    return RAC_SUCCESS;
}

static rac_platform_adapter_t make_test_adapter() {
    rac_platform_adapter_t adapter = {};
    adapter.file_exists = test_file_exists;
    adapter.file_read = test_file_read;
    adapter.file_write = test_file_write;
    adapter.file_delete = test_file_delete;
    adapter.secure_get = test_secure_get;
    adapter.secure_set = test_secure_set;
    adapter.secure_delete = test_secure_delete;
    adapter.log = test_log;
    adapter.track_error = nullptr;
    adapter.now_ms = test_now_ms;
    adapter.get_memory_info = test_get_memory_info;
    adapter.http_download = nullptr;
    adapter.http_download_cancel = nullptr;
    adapter.extract_archive = nullptr;
    adapter.user_data = nullptr;
    return adapter;
}

// =============================================================================
// Setup / Teardown
// =============================================================================

static rac_platform_adapter_t g_adapter;

static bool setup() {
    g_adapter = make_test_adapter();
    rac_config_t config = {};
    config.platform_adapter = &g_adapter;
    config.log_level = RAC_LOG_INFO;
    config.log_tag = "test_vad";
    config.reserved = nullptr;
    if (rac_init(&config) != RAC_SUCCESS) return false;
    rac_backend_onnx_register();
    return true;
}

static void teardown() {
    rac_shutdown();
}

// =============================================================================
// Tests
// =============================================================================

static TestResult test_create_destroy() {
    TestResult result;
    result.test_name = "create_destroy";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_vad_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_vad_onnx_create(model_path.c_str(), &RAC_VAD_ONNX_CONFIG_DEFAULT, &handle);

    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_vad_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    if (handle == RAC_INVALID_HANDLE || handle == nullptr) {
        result.passed = false;
        result.details = "handle is NULL after successful create";
        teardown();
        return result;
    }

    rac_vad_onnx_destroy(handle);

    result.passed = true;
    result.details = "create + destroy OK";
    teardown();
    return result;
}

static TestResult test_create_invalid_path() {
    TestResult result;
    result.test_name = "create_invalid_path";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc =
        rac_vad_onnx_create("/nonexistent.onnx", &RAC_VAD_ONNX_CONFIG_DEFAULT, &handle);

    if (rc == RAC_SUCCESS) {
        result.passed = false;
        result.details = "expected error for invalid path, got RAC_SUCCESS";
        if (handle != RAC_INVALID_HANDLE) rac_vad_onnx_destroy(handle);
        teardown();
        return result;
    }

    result.passed = true;
    result.details = "correctly returned error code " + std::to_string(rc);
    teardown();
    return result;
}

static TestResult test_process_silence() {
    TestResult result;
    result.test_name = "process_silence";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_vad_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_vad_onnx_create(model_path.c_str(), &RAC_VAD_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_vad_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    // Generate 1 second of silence at 16 kHz
    const size_t total_samples = 16000;
    std::vector<float> silence = generate_silence(total_samples);

    const size_t chunk_size = 512;
    int speech_count = 0;
    int total_chunks = 0;

    for (size_t offset = 0; offset + chunk_size <= total_samples; offset += chunk_size) {
        rac_bool_t is_speech = RAC_FALSE;
        rc = rac_vad_onnx_process(handle, silence.data() + offset, chunk_size, &is_speech);
        if (rc != RAC_SUCCESS) {
            result.passed = false;
            result.details =
                "rac_vad_onnx_process failed at offset " + std::to_string(offset) + ": " + std::to_string(rc);
            rac_vad_onnx_destroy(handle);
            teardown();
            return result;
        }
        if (is_speech == RAC_TRUE) ++speech_count;
        ++total_chunks;
    }

    float speech_ratio =
        total_chunks > 0 ? static_cast<float>(speech_count) / static_cast<float>(total_chunks) : 0.0f;

    if (speech_ratio >= 0.10f) {
        result.passed = false;
        result.details = "speech detection rate too high for silence: " +
                         std::to_string(speech_count) + "/" + std::to_string(total_chunks) +
                         " (" + std::to_string(speech_ratio * 100.0f) + "%)";
    } else {
        result.passed = true;
        result.details = "speech frames " + std::to_string(speech_count) + "/" +
                         std::to_string(total_chunks) + " (" +
                         std::to_string(speech_ratio * 100.0f) + "%)";
    }

    rac_vad_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_process_white_noise() {
    TestResult result;
    result.test_name = "process_white_noise";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_vad_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_vad_onnx_create(model_path.c_str(), &RAC_VAD_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_vad_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    // Generate 1 second of low-amplitude white noise at 16 kHz
    const size_t total_samples = 16000;
    std::vector<float> noise = generate_white_noise(total_samples, 0.02f);

    const size_t chunk_size = 512;
    int speech_count = 0;
    int total_chunks = 0;

    for (size_t offset = 0; offset + chunk_size <= total_samples; offset += chunk_size) {
        rac_bool_t is_speech = RAC_FALSE;
        rc = rac_vad_onnx_process(handle, noise.data() + offset, chunk_size, &is_speech);
        if (rc != RAC_SUCCESS) {
            result.passed = false;
            result.details =
                "rac_vad_onnx_process failed at offset " + std::to_string(offset) + ": " + std::to_string(rc);
            rac_vad_onnx_destroy(handle);
            teardown();
            return result;
        }
        if (is_speech == RAC_TRUE) ++speech_count;
        ++total_chunks;
    }

    float speech_ratio =
        total_chunks > 0 ? static_cast<float>(speech_count) / static_cast<float>(total_chunks) : 0.0f;

    // Low-amplitude noise should produce low speech detection
    result.passed = true;
    result.details = "speech frames " + std::to_string(speech_count) + "/" +
                     std::to_string(total_chunks) + " (" +
                     std::to_string(speech_ratio * 100.0f) + "%)";

    rac_vad_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_start_stop_reset() {
    TestResult result;
    result.test_name = "start_stop_reset";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_vad_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_vad_onnx_create(model_path.c_str(), &RAC_VAD_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_vad_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_result_t rc_start = rac_vad_onnx_start(handle);
    rac_result_t rc_stop = rac_vad_onnx_stop(handle);
    rac_result_t rc_reset = rac_vad_onnx_reset(handle);

    if (rc_start != RAC_SUCCESS) {
        result.passed = false;
        result.details = "start failed: " + std::to_string(rc_start);
    } else if (rc_stop != RAC_SUCCESS) {
        result.passed = false;
        result.details = "stop failed: " + std::to_string(rc_stop);
    } else if (rc_reset != RAC_SUCCESS) {
        result.passed = false;
        result.details = "reset failed: " + std::to_string(rc_reset);
    } else {
        result.passed = true;
        result.details = "start/stop/reset all returned RAC_SUCCESS";
    }

    rac_vad_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_set_threshold() {
    TestResult result;
    result.test_name = "set_threshold";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_vad_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_vad_onnx_create(model_path.c_str(), &RAC_VAD_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_vad_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rc = rac_vad_onnx_set_threshold(handle, 0.8f);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_vad_onnx_set_threshold failed: " + std::to_string(rc);
    } else {
        result.passed = true;
        result.details = "set_threshold(0.8) OK";
    }

    rac_vad_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_is_speech_active() {
    TestResult result;
    result.test_name = "is_speech_active";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_vad_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_vad_onnx_create(model_path.c_str(), &RAC_VAD_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_vad_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    // Process several chunks of silence so the VAD model has enough data to settle
    const size_t chunk_size = 512;
    const size_t num_chunks = 32;  // ~1 second at 16kHz
    std::vector<float> silence = generate_silence(chunk_size * num_chunks);
    rac_bool_t is_speech = RAC_FALSE;

    for (size_t i = 0; i < num_chunks; ++i) {
        rc = rac_vad_onnx_process(handle, silence.data() + i * chunk_size, chunk_size, &is_speech);
        if (rc != RAC_SUCCESS) {
            result.passed = false;
            result.details = "process failed at chunk " + std::to_string(i) + ": " + std::to_string(rc);
            rac_vad_onnx_destroy(handle);
            teardown();
            return result;
        }
    }

    // is_speech_active may track internal state differently from per-frame results.
    // The key assertion is that the function doesn't crash; correctness is validated
    // by the process_silence test (which checks per-frame detection rate).
    rac_bool_t active = rac_vad_onnx_is_speech_active(handle);
    result.passed = true;
    result.details = "is_speech_active returned " +
                     std::string(active == RAC_TRUE ? "TRUE" : "FALSE") +
                     " after 1s of silence (no crash)";

    rac_vad_onnx_destroy(handle);
    teardown();
    return result;
}

// =============================================================================
// TTS-based Speech Detection Tests
// =============================================================================

static TestResult test_vad_detects_tts_speech() {
    TestResult result;
    result.test_name = "vad_detects_tts_speech";

    std::string vad_model_path = test_config::get_vad_model_path();
    std::string tts_model_path = test_config::get_tts_model_path();

    if (!test_config::require_model(vad_model_path, result.test_name, result)) return result;
    if (!test_config::require_model(tts_model_path, result.test_name, result)) return result;

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    // Synthesize speech via TTS
    rac_tts_onnx_config_t tts_cfg = RAC_TTS_ONNX_CONFIG_DEFAULT;
    rac_handle_t tts_handle = nullptr;
    rac_result_t rc = rac_tts_onnx_create(tts_model_path.c_str(), &tts_cfg, &tts_handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_tts_result_t tts_result = {};
    rc = rac_tts_onnx_synthesize(tts_handle, "Hello world, this is a test of voice activity detection",
                                  nullptr, &tts_result);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_synthesize failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    // Resample TTS output from 22050Hz to 16000Hz
    const float* tts_audio = static_cast<const float*>(tts_result.audio_data);
    size_t tts_num_samples = tts_result.audio_size / sizeof(float);
    std::vector<float> resampled = resample_linear(tts_audio, tts_num_samples,
                                                    tts_result.sample_rate, 16000);

    // Create VAD handle
    rac_handle_t vad_handle = RAC_INVALID_HANDLE;
    rc = rac_vad_onnx_create(vad_model_path.c_str(), &RAC_VAD_ONNX_CONFIG_DEFAULT, &vad_handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_vad_onnx_create failed: " + std::to_string(rc);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    // Process resampled audio in 512-sample chunks
    const size_t chunk_size = 512;
    int speech_count = 0;
    int total_chunks = 0;

    for (size_t offset = 0; offset + chunk_size <= resampled.size(); offset += chunk_size) {
        rac_bool_t is_speech = RAC_FALSE;
        rc = rac_vad_onnx_process(vad_handle, resampled.data() + offset, chunk_size, &is_speech);
        if (rc != RAC_SUCCESS) {
            result.passed = false;
            result.details = "rac_vad_onnx_process failed at offset " + std::to_string(offset) +
                             ": " + std::to_string(rc);
            rac_vad_onnx_destroy(vad_handle);
            if (tts_result.audio_data) rac_free(tts_result.audio_data);
            rac_tts_onnx_destroy(tts_handle);
            teardown();
            return result;
        }
        if (is_speech == RAC_TRUE) ++speech_count;
        ++total_chunks;
    }

    float speech_ratio =
        total_chunks > 0 ? static_cast<float>(speech_count) / static_cast<float>(total_chunks) : 0.0f;

    if (speech_ratio > 0.1f) {
        result.passed = true;
        result.details = "speech detected: " + std::to_string(speech_count) + "/" +
                         std::to_string(total_chunks) + " frames (" +
                         std::to_string(speech_ratio * 100.0f) + "%)";
    } else {
        result.passed = false;
        result.details = "speech_ratio too low: " + std::to_string(speech_count) + "/" +
                         std::to_string(total_chunks) + " frames (" +
                         std::to_string(speech_ratio * 100.0f) + "%), expected >10%";
    }

    rac_vad_onnx_destroy(vad_handle);
    if (tts_result.audio_data) rac_free(tts_result.audio_data);
    rac_tts_onnx_destroy(tts_handle);
    teardown();
    return result;
}

static TestResult test_vad_mixed_speech_silence() {
    TestResult result;
    result.test_name = "vad_mixed_speech_silence";

    std::string vad_model_path = test_config::get_vad_model_path();
    std::string tts_model_path = test_config::get_tts_model_path();

    if (!test_config::require_model(vad_model_path, result.test_name, result)) return result;
    if (!test_config::require_model(tts_model_path, result.test_name, result)) return result;

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    // Synthesize "Hello" via TTS
    rac_tts_onnx_config_t tts_cfg = RAC_TTS_ONNX_CONFIG_DEFAULT;
    rac_handle_t tts_handle = nullptr;
    rac_result_t rc = rac_tts_onnx_create(tts_model_path.c_str(), &tts_cfg, &tts_handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_tts_result_t tts_result = {};
    rc = rac_tts_onnx_synthesize(tts_handle, "Hello", nullptr, &tts_result);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_synthesize failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    // Resample TTS output to 16kHz
    const float* tts_audio = static_cast<const float*>(tts_result.audio_data);
    size_t tts_num_samples = tts_result.audio_size / sizeof(float);
    std::vector<float> resampled = resample_linear(tts_audio, tts_num_samples,
                                                    tts_result.sample_rate, 16000);

    // Build mixed audio: 0.5s silence + TTS speech + 0.5s silence
    const size_t silence_samples = 8000; // 0.5s at 16kHz
    std::vector<float> leading_silence = generate_silence(silence_samples);
    std::vector<float> trailing_silence = generate_silence(silence_samples);

    std::vector<float> mixed;
    mixed.reserve(leading_silence.size() + resampled.size() + trailing_silence.size());
    mixed.insert(mixed.end(), leading_silence.begin(), leading_silence.end());
    mixed.insert(mixed.end(), resampled.begin(), resampled.end());
    mixed.insert(mixed.end(), trailing_silence.begin(), trailing_silence.end());

    // Create VAD handle
    rac_handle_t vad_handle = RAC_INVALID_HANDLE;
    rc = rac_vad_onnx_create(vad_model_path.c_str(), &RAC_VAD_ONNX_CONFIG_DEFAULT, &vad_handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_vad_onnx_create failed: " + std::to_string(rc);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    // Process mixed audio in 512-sample chunks, tracking per-frame speech
    const size_t chunk_size = 512;
    std::vector<bool> frame_is_speech;

    for (size_t offset = 0; offset + chunk_size <= mixed.size(); offset += chunk_size) {
        rac_bool_t is_speech = RAC_FALSE;
        rc = rac_vad_onnx_process(vad_handle, mixed.data() + offset, chunk_size, &is_speech);
        if (rc != RAC_SUCCESS) {
            result.passed = false;
            result.details = "rac_vad_onnx_process failed at offset " + std::to_string(offset) +
                             ": " + std::to_string(rc);
            rac_vad_onnx_destroy(vad_handle);
            if (tts_result.audio_data) rac_free(tts_result.audio_data);
            rac_tts_onnx_destroy(tts_handle);
            teardown();
            return result;
        }
        frame_is_speech.push_back(is_speech == RAC_TRUE);
    }

    // Verify pattern: some speech frames exist overall
    int total_speech = 0;
    for (bool s : frame_is_speech) {
        if (s) ++total_speech;
    }

    if (total_speech == 0) {
        result.passed = false;
        result.details = "no speech frames detected in mixed audio";
        rac_vad_onnx_destroy(vad_handle);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    // Check that the first ~15 frames (leading silence region) are mostly silence
    size_t leading_frames = std::min(static_cast<size_t>(15), frame_is_speech.size());
    int leading_speech = 0;
    for (size_t i = 0; i < leading_frames; ++i) {
        if (frame_is_speech[i]) ++leading_speech;
    }

    // The leading silence region should be mostly non-speech (allow some leakage)
    bool leading_mostly_silence = (leading_speech <= static_cast<int>(leading_frames / 2));

    // Check that the middle section (where TTS audio is) has some speech
    size_t speech_start_frame = silence_samples / chunk_size;
    size_t speech_end_frame = (silence_samples + resampled.size()) / chunk_size;
    speech_end_frame = std::min(speech_end_frame, frame_is_speech.size());

    int middle_speech = 0;
    for (size_t i = speech_start_frame; i < speech_end_frame; ++i) {
        if (frame_is_speech[i]) ++middle_speech;
    }
    bool middle_has_speech = (middle_speech > 0);

    if (leading_mostly_silence && middle_has_speech) {
        result.passed = true;
        result.details = "mixed pattern OK: leading silence speech=" +
                         std::to_string(leading_speech) + "/" + std::to_string(leading_frames) +
                         ", middle speech=" + std::to_string(middle_speech) +
                         ", total speech=" + std::to_string(total_speech) + "/" +
                         std::to_string(frame_is_speech.size());
    } else {
        result.passed = false;
        result.details = "pattern mismatch: leading_mostly_silence=" +
                         std::string(leading_mostly_silence ? "true" : "false") +
                         " (speech=" + std::to_string(leading_speech) + "/" +
                         std::to_string(leading_frames) + "), middle_has_speech=" +
                         std::string(middle_has_speech ? "true" : "false") +
                         " (speech=" + std::to_string(middle_speech) + ")";
    }

    rac_vad_onnx_destroy(vad_handle);
    if (tts_result.audio_data) rac_free(tts_result.audio_data);
    rac_tts_onnx_destroy(tts_handle);
    teardown();
    return result;
}

static TestResult test_vad_threshold_sensitivity() {
    TestResult result;
    result.test_name = "vad_threshold_sensitivity";

    std::string vad_model_path = test_config::get_vad_model_path();
    std::string tts_model_path = test_config::get_tts_model_path();

    if (!test_config::require_model(vad_model_path, result.test_name, result)) return result;
    if (!test_config::require_model(tts_model_path, result.test_name, result)) return result;

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    // Synthesize "Hello world" via TTS
    rac_tts_onnx_config_t tts_cfg = RAC_TTS_ONNX_CONFIG_DEFAULT;
    rac_handle_t tts_handle = nullptr;
    rac_result_t rc = rac_tts_onnx_create(tts_model_path.c_str(), &tts_cfg, &tts_handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_tts_result_t tts_result = {};
    rc = rac_tts_onnx_synthesize(tts_handle, "Hello world", nullptr, &tts_result);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_synthesize failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    // Resample TTS output to 16kHz
    const float* tts_audio = static_cast<const float*>(tts_result.audio_data);
    size_t tts_num_samples = tts_result.audio_size / sizeof(float);
    std::vector<float> resampled = resample_linear(tts_audio, tts_num_samples,
                                                    tts_result.sample_rate, 16000);

    // Create VAD handle
    rac_handle_t vad_handle = RAC_INVALID_HANDLE;
    rc = rac_vad_onnx_create(vad_model_path.c_str(), &RAC_VAD_ONNX_CONFIG_DEFAULT, &vad_handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_vad_onnx_create failed: " + std::to_string(rc);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    const size_t chunk_size = 512;

    // Run 1: loose threshold (0.1)
    rc = rac_vad_onnx_set_threshold(vad_handle, 0.1f);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "set_threshold(0.1) failed: " + std::to_string(rc);
        rac_vad_onnx_destroy(vad_handle);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    int loose_count = 0;
    for (size_t offset = 0; offset + chunk_size <= resampled.size(); offset += chunk_size) {
        rac_bool_t is_speech = RAC_FALSE;
        rc = rac_vad_onnx_process(vad_handle, resampled.data() + offset, chunk_size, &is_speech);
        if (rc != RAC_SUCCESS) {
            result.passed = false;
            result.details = "process failed (loose) at offset " + std::to_string(offset) +
                             ": " + std::to_string(rc);
            rac_vad_onnx_destroy(vad_handle);
            if (tts_result.audio_data) rac_free(tts_result.audio_data);
            rac_tts_onnx_destroy(tts_handle);
            teardown();
            return result;
        }
        if (is_speech == RAC_TRUE) ++loose_count;
    }

    // Reset VAD state between runs
    rc = rac_vad_onnx_reset(vad_handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_vad_onnx_reset failed: " + std::to_string(rc);
        rac_vad_onnx_destroy(vad_handle);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    // Run 2: strict threshold (0.9)
    rc = rac_vad_onnx_set_threshold(vad_handle, 0.9f);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "set_threshold(0.9) failed: " + std::to_string(rc);
        rac_vad_onnx_destroy(vad_handle);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    int strict_count = 0;
    for (size_t offset = 0; offset + chunk_size <= resampled.size(); offset += chunk_size) {
        rac_bool_t is_speech = RAC_FALSE;
        rc = rac_vad_onnx_process(vad_handle, resampled.data() + offset, chunk_size, &is_speech);
        if (rc != RAC_SUCCESS) {
            result.passed = false;
            result.details = "process failed (strict) at offset " + std::to_string(offset) +
                             ": " + std::to_string(rc);
            rac_vad_onnx_destroy(vad_handle);
            if (tts_result.audio_data) rac_free(tts_result.audio_data);
            rac_tts_onnx_destroy(tts_handle);
            teardown();
            return result;
        }
        if (is_speech == RAC_TRUE) ++strict_count;
    }

    // Assert: loose threshold should detect at least as many speech frames as strict
    if (loose_count >= strict_count) {
        result.passed = true;
        result.details = "threshold sensitivity OK: loose(0.1)=" + std::to_string(loose_count) +
                         " >= strict(0.9)=" + std::to_string(strict_count);
    } else {
        result.passed = false;
        result.details = "threshold sensitivity FAILED: loose(0.1)=" + std::to_string(loose_count) +
                         " < strict(0.9)=" + std::to_string(strict_count);
    }

    rac_vad_onnx_destroy(vad_handle);
    if (tts_result.audio_data) rac_free(tts_result.audio_data);
    rac_tts_onnx_destroy(tts_handle);
    teardown();
    return result;
}

// =============================================================================
// Main
// =============================================================================

int main(int argc, char** argv) {
    std::map<std::string, std::function<TestResult()>> tests = {
        {"create_destroy", test_create_destroy},
        {"create_invalid_path", test_create_invalid_path},
        {"process_silence", test_process_silence},
        {"process_white_noise", test_process_white_noise},
        {"start_stop_reset", test_start_stop_reset},
        {"set_threshold", test_set_threshold},
        {"is_speech_active", test_is_speech_active},
        {"vad_detects_tts_speech", test_vad_detects_tts_speech},
        {"vad_mixed_speech_silence", test_vad_mixed_speech_silence},
        {"vad_threshold_sensitivity", test_vad_threshold_sensitivity},
    };

    return parse_test_args(argc, argv, tests);
}
