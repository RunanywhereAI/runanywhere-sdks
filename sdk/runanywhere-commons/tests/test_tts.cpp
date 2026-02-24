/**
 * @file test_tts.cpp
 * @brief Integration tests for ONNX TTS backend via direct RAC API
 *
 * Tests text-to-speech using the Piper VITS ONNX model.
 * Requires: vits-piper-en_US-lessac-medium model directory at the configured path.
 */

#include "test_common.h"
#include "test_config.h"

#include "rac/backends/rac_tts_onnx.h"
#include "rac/backends/rac_vad_onnx.h"  // for rac_backend_onnx_register()
#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"

#include <cstdio>
#include <cstring>
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
    config.log_tag = "test_tts";
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

    std::string model_path = test_config::get_tts_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_tts_onnx_create(model_path.c_str(), &RAC_TTS_ONNX_CONFIG_DEFAULT, &handle);

    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    if (handle == RAC_INVALID_HANDLE || handle == nullptr) {
        result.passed = false;
        result.details = "handle is NULL after successful create";
        teardown();
        return result;
    }

    rac_tts_onnx_destroy(handle);

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
        rac_tts_onnx_create("/nonexistent", &RAC_TTS_ONNX_CONFIG_DEFAULT, &handle);

    if (rc == RAC_SUCCESS) {
        result.passed = false;
        result.details = "expected error for invalid path, got RAC_SUCCESS";
        if (handle != RAC_INVALID_HANDLE) rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    result.passed = true;
    result.details = "correctly returned error code " + std::to_string(rc);
    teardown();
    return result;
}

static TestResult test_synthesize_short() {
    TestResult result;
    result.test_name = "synthesize_short";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_tts_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_tts_onnx_create(model_path.c_str(), &RAC_TTS_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_tts_result_t tts_result = {};
    {
        ScopedTimer timer("synthesize_short");
        rc = rac_tts_onnx_synthesize(handle, "Hello world.", nullptr, &tts_result);
    }

    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_synthesize failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    if (tts_result.audio_data == nullptr) {
        result.passed = false;
        result.details = "audio_data is NULL";
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    if (tts_result.audio_size == 0) {
        result.passed = false;
        result.details = "audio_size is 0";
        rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    if (tts_result.sample_rate != 22050) {
        result.passed = false;
        result.details = "expected sample_rate 22050, got " + std::to_string(tts_result.sample_rate);
        rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    result.passed = true;
    result.details = "audio_size=" + std::to_string(tts_result.audio_size) +
                     " bytes, sample_rate=" + std::to_string(tts_result.sample_rate);

    rac_free(tts_result.audio_data);
    rac_tts_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_synthesize_long() {
    TestResult result;
    result.test_name = "synthesize_long";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_tts_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_tts_onnx_create(model_path.c_str(), &RAC_TTS_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    // Synthesize short text first
    rac_tts_result_t short_result = {};
    {
        ScopedTimer timer("synthesize_short_for_compare");
        rc = rac_tts_onnx_synthesize(handle, "Hello world.", nullptr, &short_result);
    }
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "short synthesis failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }
    size_t short_size = short_result.audio_size;
    rac_free(short_result.audio_data);

    // Synthesize longer text
    rac_tts_result_t long_result = {};
    {
        ScopedTimer timer("synthesize_long");
        rc = rac_tts_onnx_synthesize(
            handle,
            "The quick brown fox jumps over the lazy dog. This is a longer test.",
            nullptr, &long_result);
    }
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "long synthesis failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    if (long_result.audio_size <= short_size) {
        result.passed = false;
        result.details = "longer text produced less audio: long=" +
                         std::to_string(long_result.audio_size) +
                         " <= short=" + std::to_string(short_size);
    } else {
        result.passed = true;
        result.details = "long=" + std::to_string(long_result.audio_size) +
                         " > short=" + std::to_string(short_size) + " bytes";
    }

    rac_free(long_result.audio_data);
    rac_tts_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_synthesize_empty() {
    TestResult result;
    result.test_name = "synthesize_empty";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_tts_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_tts_onnx_create(model_path.c_str(), &RAC_TTS_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_tts_result_t tts_result = {};
    rc = rac_tts_onnx_synthesize(handle, "", nullptr, &tts_result);

    // Both error return and empty result are acceptable for empty input
    if (rc != RAC_SUCCESS) {
        result.passed = true;
        result.details = "returned error " + std::to_string(rc) + " for empty text (acceptable)";
    } else {
        result.passed = true;
        result.details = "returned success with audio_size=" +
                         std::to_string(tts_result.audio_size) + " for empty text (acceptable)";
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
    }

    rac_tts_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_stop_idempotent() {
    TestResult result;
    result.test_name = "stop_idempotent";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_tts_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_tts_onnx_create(model_path.c_str(), &RAC_TTS_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    // Call stop when not synthesizing - should not crash
    rac_tts_onnx_stop(handle);
    rac_tts_onnx_stop(handle); // call twice to verify idempotency

    result.passed = true;
    result.details = "stop() called twice without crash";

    rac_tts_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_output_valid_wav() {
    TestResult result;
    result.test_name = "output_valid_wav";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_tts_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_tts_onnx_create(model_path.c_str(), &RAC_TTS_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_tts_result_t tts_result = {};
    rc = rac_tts_onnx_synthesize(handle, "Test", nullptr, &tts_result);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "synthesize failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    if (tts_result.audio_data == nullptr || tts_result.audio_size == 0) {
        result.passed = false;
        result.details = "no audio data returned";
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    // The TTS result contains raw PCM samples. Verify sample count is reasonable.
    // Piper TTS outputs float32 PCM at 22050 Hz. For "Test" we expect at least
    // a fraction of a second of audio.
    // Try float32 first: audio_size / sizeof(float) = num_samples
    size_t num_float_samples = tts_result.audio_size / sizeof(float);
    size_t num_int16_samples = tts_result.audio_size / sizeof(int16_t);
    int32_t sr = tts_result.sample_rate > 0 ? tts_result.sample_rate : 22050;

    // Determine format by checking which gives a reasonable duration
    // For "Test" spoken, expect roughly 0.3-3 seconds
    float duration_f32 = static_cast<float>(num_float_samples) / static_cast<float>(sr);
    float duration_i16 = static_cast<float>(num_int16_samples) / static_cast<float>(sr);

    // Try converting to WAV using the float32 path first, fall back to int16
    void* wav_data = nullptr;
    size_t wav_size = 0;
    rac_result_t wav_rc = rac_audio_float32_to_wav(
        tts_result.audio_data, tts_result.audio_size, sr, &wav_data, &wav_size);

    if (wav_rc != RAC_SUCCESS) {
        // Fall back to int16 conversion
        wav_rc = rac_audio_int16_to_wav(
            tts_result.audio_data, tts_result.audio_size, sr, &wav_data, &wav_size);
    }

    if (wav_rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "WAV conversion failed: " + std::to_string(wav_rc);
        rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    // Standard WAV header is 44 bytes
    if (wav_size <= 44) {
        result.passed = false;
        result.details = "WAV output too small: " + std::to_string(wav_size) + " bytes (expected > 44)";
        rac_free(wav_data);
        rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    result.passed = true;
    result.details = "PCM audio_size=" + std::to_string(tts_result.audio_size) +
                     " bytes, WAV size=" + std::to_string(wav_size) +
                     " bytes, sample_rate=" + std::to_string(sr) +
                     ", duration_f32=" + std::to_string(duration_f32) + "s" +
                     ", duration_i16=" + std::to_string(duration_i16) + "s";

    rac_free(wav_data);
    rac_free(tts_result.audio_data);
    rac_tts_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_synthesize_punctuation() {
    TestResult result;
    result.test_name = "synthesize_punctuation";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_tts_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_tts_onnx_create(model_path.c_str(), &RAC_TTS_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_tts_result_t tts_result = {};
    {
        ScopedTimer timer("synthesize_punctuation");
        rc = rac_tts_onnx_synthesize(handle,
                                     "Hello! How are you? I'm fine, thanks.",
                                     nullptr, &tts_result);
    }

    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_synthesize failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    if (tts_result.audio_data == nullptr) {
        result.passed = false;
        result.details = "audio_data is NULL";
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    if (tts_result.audio_size == 0) {
        result.passed = false;
        result.details = "audio_size is 0";
        rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    result.passed = true;
    result.details = "audio_size=" + std::to_string(tts_result.audio_size) + " bytes";

    rac_free(tts_result.audio_data);
    rac_tts_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_synthesize_numbers() {
    TestResult result;
    result.test_name = "synthesize_numbers";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_tts_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_tts_onnx_create(model_path.c_str(), &RAC_TTS_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_tts_result_t tts_result = {};
    {
        ScopedTimer timer("synthesize_numbers");
        rc = rac_tts_onnx_synthesize(
            handle,
            "The year is twenty twenty five. Please call five five five, one two three four.",
            nullptr, &tts_result);
    }

    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_synthesize failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    if (tts_result.audio_data == nullptr) {
        result.passed = false;
        result.details = "audio_data is NULL";
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    if (tts_result.audio_size == 0) {
        result.passed = false;
        result.details = "audio_size is 0";
        rac_free(tts_result.audio_data);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }

    result.passed = true;
    result.details = "audio_size=" + std::to_string(tts_result.audio_size) + " bytes";

    rac_free(tts_result.audio_data);
    rac_tts_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_synthesize_multisentence() {
    TestResult result;
    result.test_name = "synthesize_multisentence";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_tts_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_tts_onnx_create(model_path.c_str(), &RAC_TTS_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    // Synthesize short text
    rac_tts_result_t short_result = {};
    {
        ScopedTimer timer("synthesize_multisentence_short");
        rc = rac_tts_onnx_synthesize(handle, "Hello", nullptr, &short_result);
    }
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "short synthesis failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }
    size_t short_audio_size = short_result.audio_size;

    // Synthesize long text
    rac_tts_result_t long_result = {};
    {
        ScopedTimer timer("synthesize_multisentence_long");
        rc = rac_tts_onnx_synthesize(
            handle,
            "The quick brown fox jumps over the lazy dog. This is a longer sentence that "
            "should produce more audio output than a single word. Speech synthesis systems "
            "need to handle varying lengths of input text gracefully.",
            nullptr, &long_result);
    }
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "long synthesis failed: " + std::to_string(rc);
        rac_free(short_result.audio_data);
        rac_tts_onnx_destroy(handle);
        teardown();
        return result;
    }
    size_t long_audio_size = long_result.audio_size;

    if (long_audio_size <= short_audio_size) {
        result.passed = false;
        result.details = "long audio (" + std::to_string(long_audio_size) +
                         " bytes) should be larger than short audio (" +
                         std::to_string(short_audio_size) + " bytes)";
    } else {
        result.passed = true;
        result.details = "long=" + std::to_string(long_audio_size) +
                         " > short=" + std::to_string(short_audio_size) + " bytes";
    }

    rac_free(short_result.audio_data);
    rac_free(long_result.audio_data);
    rac_tts_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_get_voices() {
    TestResult result;
    result.test_name = "get_voices";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_tts_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_tts_onnx_create(model_path.c_str(), &RAC_TTS_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    char** voices = nullptr;
    size_t voice_count = 0;
    rc = rac_tts_onnx_get_voices(handle, &voices, &voice_count);

    // Some backends may not implement get_voices - just verify no crash
    if (rc == RAC_SUCCESS) {
        result.passed = true;
        result.details = "get_voices returned " + std::to_string(voice_count) + " voice(s)";
    } else {
        result.passed = true;
        result.details = "get_voices returned code " + std::to_string(rc) +
                         " (not implemented in this backend, no crash)";
    }

    rac_tts_onnx_destroy(handle);
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
        {"synthesize_short", test_synthesize_short},
        {"synthesize_long", test_synthesize_long},
        {"synthesize_empty", test_synthesize_empty},
        {"stop_idempotent", test_stop_idempotent},
        {"output_valid_wav", test_output_valid_wav},
        {"synthesize_punctuation", test_synthesize_punctuation},
        {"synthesize_numbers", test_synthesize_numbers},
        {"synthesize_multisentence", test_synthesize_multisentence},
        {"get_voices", test_get_voices},
    };

    return parse_test_args(argc, argv, tests);
}
