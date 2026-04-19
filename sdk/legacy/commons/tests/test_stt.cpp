/**
 * @file test_stt.cpp
 * @brief Integration tests for ONNX STT backend via direct RAC API
 *
 * Tests speech-to-text using the Sherpa-ONNX Whisper model.
 * Requires: whisper-tiny-en model directory at the configured path.
 */

#include "test_common.h"
#include "test_config.h"

#include "rac/backends/rac_stt_onnx.h"
#include "rac/backends/rac_tts_onnx.h"
#include "rac/backends/rac_vad_onnx.h"  // for rac_backend_onnx_register()
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
    config.log_tag = "test_stt";
    config.reserved = nullptr;
    if (rac_init(&config) != RAC_SUCCESS) return false;
    rac_backend_onnx_register();
    return true;
}

static void teardown() {
    rac_shutdown();
}

// =============================================================================
// Helper: check if text is empty or whitespace
// =============================================================================

static bool is_empty_or_whitespace(const char* text) {
    if (text == nullptr) return true;
    while (*text) {
        if (*text != ' ' && *text != '\t' && *text != '\n' && *text != '\r') return false;
        ++text;
    }
    return true;
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

    std::string model_path = test_config::get_stt_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_stt_onnx_create(model_path.c_str(), &RAC_STT_ONNX_CONFIG_DEFAULT, &handle);

    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    if (handle == RAC_INVALID_HANDLE || handle == nullptr) {
        result.passed = false;
        result.details = "handle is NULL after successful create";
        teardown();
        return result;
    }

    rac_stt_onnx_destroy(handle);

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
        rac_stt_onnx_create("/nonexistent", &RAC_STT_ONNX_CONFIG_DEFAULT, &handle);

    if (rc == RAC_SUCCESS) {
        result.passed = false;
        result.details = "expected error for invalid path, got RAC_SUCCESS";
        if (handle != RAC_INVALID_HANDLE) rac_stt_onnx_destroy(handle);
        teardown();
        return result;
    }

    result.passed = true;
    result.details = "correctly returned error code " + std::to_string(rc);
    teardown();
    return result;
}

static TestResult test_transcribe_silence() {
    TestResult result;
    result.test_name = "transcribe_silence";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_stt_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_stt_onnx_create(model_path.c_str(), &RAC_STT_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    // Generate 2 seconds of silence at 16 kHz
    const size_t num_samples = 32000;
    std::vector<float> silence = generate_silence(num_samples);

    rac_stt_result_t stt_result = {};
    {
        ScopedTimer timer("transcribe_silence");
        rc = rac_stt_onnx_transcribe(handle, silence.data(), num_samples, nullptr, &stt_result);
    }

    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_transcribe failed: " + std::to_string(rc);
        rac_stt_onnx_destroy(handle);
        teardown();
        return result;
    }

    // For silence, the transcription should be empty or whitespace
    if (!is_empty_or_whitespace(stt_result.text)) {
        // Not a hard failure - models may hallucinate on silence
        result.details = "transcription of silence: \"" +
                         std::string(stt_result.text ? stt_result.text : "(null)") +
                         "\" (non-empty, but not a failure)";
    } else {
        result.details = "transcription of silence is empty/whitespace as expected";
    }

    result.passed = true;

    // Free allocated text
    if (stt_result.text) rac_free(stt_result.text);
    if (stt_result.detected_language) rac_free(stt_result.detected_language);

    rac_stt_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_transcribe_sine() {
    TestResult result;
    result.test_name = "transcribe_sine";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_stt_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_stt_onnx_create(model_path.c_str(), &RAC_STT_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    // Generate 1 second of 440 Hz sine wave at 16 kHz
    std::vector<float> sine = generate_sine_wave(440.0f, 1.0f, 16000, 0.5f);

    rac_stt_result_t stt_result = {};
    {
        ScopedTimer timer("transcribe_sine");
        rc = rac_stt_onnx_transcribe(handle, sine.data(), sine.size(), nullptr, &stt_result);
    }

    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_transcribe failed on sine wave: " + std::to_string(rc);
        rac_stt_onnx_destroy(handle);
        teardown();
        return result;
    }

    // Sine wave isn't speech - the text can be anything, we just verify no crash
    result.passed = true;
    result.details = "transcription of sine: \"" +
                     std::string(stt_result.text ? stt_result.text : "(null)") + "\"";

    if (stt_result.text) rac_free(stt_result.text);
    if (stt_result.detected_language) rac_free(stt_result.detected_language);

    rac_stt_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_supports_streaming() {
    TestResult result;
    result.test_name = "supports_streaming";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_stt_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_stt_onnx_create(model_path.c_str(), &RAC_STT_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_bool_t streaming = rac_stt_onnx_supports_streaming(handle);

    result.passed = true;
    result.details = "supports_streaming = " + std::string(streaming == RAC_TRUE ? "true" : "false");

    rac_stt_onnx_destroy(handle);
    teardown();
    return result;
}

static TestResult test_streaming_workflow() {
    TestResult result;
    result.test_name = "streaming_workflow";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string model_path = test_config::get_stt_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t rc = rac_stt_onnx_create(model_path.c_str(), &RAC_STT_ONNX_CONFIG_DEFAULT, &handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_create failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_bool_t streaming = rac_stt_onnx_supports_streaming(handle);
    if (streaming != RAC_TRUE) {
        result.passed = true;
        result.details = "SKIPPED - model does not support streaming";
        rac_stt_onnx_destroy(handle);
        teardown();
        return result;
    }

    // Create stream
    rac_handle_t stream = RAC_INVALID_HANDLE;
    rc = rac_stt_onnx_create_stream(handle, &stream);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "create_stream failed: " + std::to_string(rc);
        rac_stt_onnx_destroy(handle);
        teardown();
        return result;
    }

    // Feed 1 second of silence in 4800-sample chunks
    const size_t total_samples = 16000;
    const size_t chunk_size = 4800;
    std::vector<float> silence = generate_silence(total_samples);

    for (size_t offset = 0; offset + chunk_size <= total_samples; offset += chunk_size) {
        rc = rac_stt_onnx_feed_audio(handle, stream, silence.data() + offset, chunk_size);
        if (rc != RAC_SUCCESS) {
            result.passed = false;
            result.details =
                "feed_audio failed at offset " + std::to_string(offset) + ": " + std::to_string(rc);
            rac_stt_onnx_destroy_stream(handle, stream);
            rac_stt_onnx_destroy(handle);
            teardown();
            return result;
        }
    }

    // Check if stream is ready and try decoding
    rac_bool_t is_ready = rac_stt_onnx_stream_is_ready(handle, stream);
    (void)is_ready; // May or may not be ready, just check no crash

    char* decoded_text = nullptr;
    rc = rac_stt_onnx_decode_stream(handle, stream, &decoded_text);
    // Decode may or may not succeed depending on model state - both are acceptable
    if (rc == RAC_SUCCESS && decoded_text != nullptr) {
        rac_free(decoded_text);
    }

    // Signal input finished
    rac_stt_onnx_input_finished(handle, stream);

    // Destroy stream
    rac_stt_onnx_destroy_stream(handle, stream);

    result.passed = true;
    result.details = "streaming workflow completed without crash";

    rac_stt_onnx_destroy(handle);
    teardown();
    return result;
}

// =============================================================================
// TTS→STT Round-Trip Tests
// =============================================================================

static TestResult test_transcribe_tts_hello() {
    TestResult result;
    result.test_name = "transcribe_tts_hello";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string tts_model_path = test_config::get_tts_model_path();
    std::string stt_model_path = test_config::get_stt_model_path();

    if (!test_config::require_model(tts_model_path, result.test_name, result)) {
        teardown();
        return result;
    }
    if (!test_config::require_model(stt_model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    // Create TTS handle and synthesize "Hello world"
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

    // Resample from TTS sample rate (22050) to STT sample rate (16000)
    const float* tts_audio = static_cast<const float*>(tts_result.audio_data);
    size_t num_tts_samples = tts_result.audio_size / sizeof(float);
    std::vector<float> resampled =
        resample_linear(tts_audio, num_tts_samples, tts_result.sample_rate, 16000);

    rac_tts_onnx_destroy(tts_handle);

    // Create STT handle and transcribe
    rac_handle_t stt_handle = RAC_INVALID_HANDLE;
    rc = rac_stt_onnx_create(stt_model_path.c_str(), &RAC_STT_ONNX_CONFIG_DEFAULT, &stt_handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_create failed: " + std::to_string(rc);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        teardown();
        return result;
    }

    rac_stt_result_t stt_result = {};
    {
        ScopedTimer timer("transcribe_tts_hello");
        rc = rac_stt_onnx_transcribe(stt_handle, resampled.data(), resampled.size(), nullptr,
                                     &stt_result);
    }

    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_transcribe failed: " + std::to_string(rc);
        rac_stt_onnx_destroy(stt_handle);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        teardown();
        return result;
    }

    std::string transcript = stt_result.text ? stt_result.text : "";
    std::fprintf(stdout, "[DEBUG] transcribe_tts_hello transcript: \"%s\"\n", transcript.c_str());

    // Accept "hello" or "world" — tiny whisper on TTS speech may mishear
    // individual words but should recognize at least one keyword
    if (!contains_ci(transcript, "hello") && !contains_ci(transcript, "world")) {
        result.passed = false;
        result.details =
            "transcript does not contain 'hello' or 'world': \"" + transcript + "\"";
    } else {
        result.passed = true;
        result.details = "transcript contains expected keyword: \"" + transcript + "\"";
    }

    if (stt_result.text) rac_free(stt_result.text);
    if (stt_result.detected_language) rac_free(stt_result.detected_language);
    if (tts_result.audio_data) rac_free(tts_result.audio_data);

    rac_stt_onnx_destroy(stt_handle);
    teardown();
    return result;
}

static TestResult test_transcribe_tts_numbers() {
    TestResult result;
    result.test_name = "transcribe_tts_numbers";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string tts_model_path = test_config::get_tts_model_path();
    std::string stt_model_path = test_config::get_stt_model_path();

    if (!test_config::require_model(tts_model_path, result.test_name, result)) {
        teardown();
        return result;
    }
    if (!test_config::require_model(stt_model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    // Create TTS handle and synthesize "one two three four five"
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
    rc = rac_tts_onnx_synthesize(tts_handle, "one two three four five", nullptr, &tts_result);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_synthesize failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    // Resample from TTS sample rate (22050) to STT sample rate (16000)
    const float* tts_audio = static_cast<const float*>(tts_result.audio_data);
    size_t num_tts_samples = tts_result.audio_size / sizeof(float);
    std::vector<float> resampled =
        resample_linear(tts_audio, num_tts_samples, tts_result.sample_rate, 16000);

    rac_tts_onnx_destroy(tts_handle);

    // Create STT handle and transcribe
    rac_handle_t stt_handle = RAC_INVALID_HANDLE;
    rc = rac_stt_onnx_create(stt_model_path.c_str(), &RAC_STT_ONNX_CONFIG_DEFAULT, &stt_handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_create failed: " + std::to_string(rc);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        teardown();
        return result;
    }

    rac_stt_result_t stt_result = {};
    {
        ScopedTimer timer("transcribe_tts_numbers");
        rc = rac_stt_onnx_transcribe(stt_handle, resampled.data(), resampled.size(), nullptr,
                                     &stt_result);
    }

    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_transcribe failed: " + std::to_string(rc);
        rac_stt_onnx_destroy(stt_handle);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        teardown();
        return result;
    }

    std::string transcript = stt_result.text ? stt_result.text : "";
    std::fprintf(stdout, "[DEBUG] transcribe_tts_numbers transcript: \"%s\"\n",
                 transcript.c_str());

    // Pass if at least one number word or digit is found in the transcript
    // (STT may output "1, 2, 3" instead of "one, two, three")
    const char* keywords[] = {"one", "two", "three", "four", "five",
                               "1", "2", "3", "4", "5"};
    bool found_any = false;
    for (const char* kw : keywords) {
        if (contains_ci(transcript, kw)) {
            found_any = true;
            break;
        }
    }

    if (!found_any) {
        result.passed = false;
        result.details =
            "transcript does not contain any number word or digit: \"" + transcript + "\"";
    } else {
        result.passed = true;
        result.details = "transcript contains number(s): \"" + transcript + "\"";
    }

    if (stt_result.text) rac_free(stt_result.text);
    if (stt_result.detected_language) rac_free(stt_result.detected_language);
    if (tts_result.audio_data) rac_free(tts_result.audio_data);

    rac_stt_onnx_destroy(stt_handle);
    teardown();
    return result;
}

static TestResult test_transcribe_tts_sentence() {
    TestResult result;
    result.test_name = "transcribe_tts_sentence";

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::string tts_model_path = test_config::get_tts_model_path();
    std::string stt_model_path = test_config::get_stt_model_path();

    if (!test_config::require_model(tts_model_path, result.test_name, result)) {
        teardown();
        return result;
    }
    if (!test_config::require_model(stt_model_path, result.test_name, result)) {
        teardown();
        return result;
    }

    // Create TTS handle and synthesize "The weather is sunny today"
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
    rc = rac_tts_onnx_synthesize(tts_handle, "The weather is sunny today", nullptr, &tts_result);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_tts_onnx_synthesize failed: " + std::to_string(rc);
        rac_tts_onnx_destroy(tts_handle);
        teardown();
        return result;
    }

    // Resample from TTS sample rate (22050) to STT sample rate (16000)
    const float* tts_audio = static_cast<const float*>(tts_result.audio_data);
    size_t num_tts_samples = tts_result.audio_size / sizeof(float);
    std::vector<float> resampled =
        resample_linear(tts_audio, num_tts_samples, tts_result.sample_rate, 16000);

    rac_tts_onnx_destroy(tts_handle);

    // Create STT handle and transcribe
    rac_handle_t stt_handle = RAC_INVALID_HANDLE;
    rc = rac_stt_onnx_create(stt_model_path.c_str(), &RAC_STT_ONNX_CONFIG_DEFAULT, &stt_handle);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_create failed: " + std::to_string(rc);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        teardown();
        return result;
    }

    rac_stt_result_t stt_result = {};
    {
        ScopedTimer timer("transcribe_tts_sentence");
        rc = rac_stt_onnx_transcribe(stt_handle, resampled.data(), resampled.size(), nullptr,
                                     &stt_result);
    }

    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_stt_onnx_transcribe failed: " + std::to_string(rc);
        rac_stt_onnx_destroy(stt_handle);
        if (tts_result.audio_data) rac_free(tts_result.audio_data);
        teardown();
        return result;
    }

    std::string transcript = stt_result.text ? stt_result.text : "";
    std::fprintf(stdout, "[DEBUG] transcribe_tts_sentence transcript: \"%s\"\n",
                 transcript.c_str());

    // Pass if transcript contains "weather" or "sunny"
    bool found = contains_ci(transcript, "weather") || contains_ci(transcript, "sunny");

    if (!found) {
        result.passed = false;
        result.details =
            "transcript does not contain 'weather' or 'sunny': \"" + transcript + "\"";
    } else {
        result.passed = true;
        result.details =
            "transcript contains 'weather' or 'sunny': \"" + transcript + "\"";
    }

    if (stt_result.text) rac_free(stt_result.text);
    if (stt_result.detected_language) rac_free(stt_result.detected_language);
    if (tts_result.audio_data) rac_free(tts_result.audio_data);

    rac_stt_onnx_destroy(stt_handle);
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
        {"transcribe_silence", test_transcribe_silence},
        {"transcribe_sine", test_transcribe_sine},
        {"supports_streaming", test_supports_streaming},
        {"streaming_workflow", test_streaming_workflow},
        {"transcribe_tts_hello", test_transcribe_tts_hello},
        {"transcribe_tts_numbers", test_transcribe_tts_numbers},
        {"transcribe_tts_sentence", test_transcribe_tts_sentence},
    };

    return parse_test_args(argc, argv, tests);
}
