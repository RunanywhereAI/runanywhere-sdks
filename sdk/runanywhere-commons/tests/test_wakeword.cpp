/**
 * @file test_wakeword.cpp
 * @brief Integration tests for wake word detection via ONNX backend API.
 *
 * Tests create/destroy, shared model init, model load/unload, audio processing
 * (silence + noise), threshold setting, and reset using rac_wakeword_onnx_* APIs.
 */

#include "test_common.h"
#include "test_config.h"

#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/backends/rac_wakeword_onnx.h"

#include <cstring>
#include <string>

// =============================================================================
// Minimal test platform adapter
// =============================================================================

static void test_log_callback(rac_log_level_t /*level*/, const char* /*category*/,
                               const char* /*message*/, void* /*ctx*/) {
    // silent during tests
}

static int64_t test_now_ms(void* /*ctx*/) {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

static const rac_platform_adapter_t test_adapter = {
    /* file_exists       */ nullptr,
    /* file_read         */ nullptr,
    /* file_write        */ nullptr,
    /* file_delete       */ nullptr,
    /* secure_get        */ nullptr,
    /* secure_set        */ nullptr,
    /* secure_delete     */ nullptr,
    /* log               */ test_log_callback,
    /* track_error       */ nullptr,
    /* now_ms            */ test_now_ms,
    /* get_memory_info   */ nullptr,
    /* http_download     */ nullptr,
    /* http_download_cancel */ nullptr,
    /* extract_archive   */ nullptr,
    /* user_data         */ nullptr,
};

static rac_config_t make_test_config() {
    rac_config_t config = {};
    config.platform_adapter = &test_adapter;
    config.log_level = RAC_LOG_WARNING;
    config.log_tag = "TEST_WAKEWORD";
    config.reserved = nullptr;
    return config;
}

// =============================================================================
// Setup / Teardown
// =============================================================================

static bool setup() {
    rac_config_t config = make_test_config();
    if (rac_init(&config) != RAC_SUCCESS) return false;
    rac_backend_wakeword_onnx_register();
    return true;
}

static void teardown() { rac_shutdown(); }

// =============================================================================
// Helper: full wakeword setup (create + init shared + load model)
// Returns true on success, fills result as SKIPPED on missing models.
// =============================================================================

struct WakewordSetup {
    rac_handle_t handle = nullptr;
    bool ready = false;
};

static bool full_wakeword_setup(WakewordSetup& ws, TestResult& result,
                                 const std::string& test_name) {
    std::string embedding_path = test_config::get_wakeword_embedding_path();
    std::string melspec_path = test_config::get_wakeword_melspec_path();
    std::string model_path = test_config::get_wakeword_model_path();

    if (!test_config::require_model(embedding_path, test_name, result)) return false;
    if (!test_config::require_model(melspec_path, test_name, result)) return false;
    if (!test_config::require_model(model_path, test_name, result)) return false;

    if (!setup()) {
        result.test_name = test_name;
        result.passed = false;
        result.details = "setup() failed";
        return false;
    }

    rac_wakeword_onnx_config_t cfg = RAC_WAKEWORD_ONNX_CONFIG_DEFAULT;
    rac_result_t rc = rac_wakeword_onnx_create(&cfg, &ws.handle);
    if (rc != RAC_SUCCESS) {
        result.test_name = test_name;
        result.passed = false;
        result.details = "rac_wakeword_onnx_create failed: " + std::to_string(rc);
        teardown();
        return false;
    }

    rc = rac_wakeword_onnx_init_shared_models(ws.handle, embedding_path.c_str(),
                                                melspec_path.c_str());
    if (rc != RAC_SUCCESS) {
        result.test_name = test_name;
        result.passed = false;
        result.details = "rac_wakeword_onnx_init_shared_models failed: " + std::to_string(rc);
        rac_wakeword_onnx_destroy(ws.handle);
        teardown();
        return false;
    }

    rc = rac_wakeword_onnx_load_model(ws.handle, model_path.c_str(), "hey-jarvis", "Hey Jarvis");
    if (rc != RAC_SUCCESS) {
        result.test_name = test_name;
        result.passed = false;
        result.details = "rac_wakeword_onnx_load_model failed: " + std::to_string(rc);
        rac_wakeword_onnx_destroy(ws.handle);
        teardown();
        return false;
    }

    ws.ready = true;
    return true;
}

// =============================================================================
// Test: create and destroy with default config
// =============================================================================

static TestResult test_create_destroy() {
    if (!setup()) {
        TestResult r;
        r.test_name = "create_destroy";
        r.passed = false;
        r.details = "setup() failed";
        return r;
    }

    rac_wakeword_onnx_config_t cfg = RAC_WAKEWORD_ONNX_CONFIG_DEFAULT;
    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_wakeword_onnx_create(&cfg, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_wakeword_onnx_create should succeed");
    ASSERT_TRUE(handle != nullptr, "handle should not be NULL");

    rac_wakeword_onnx_destroy(handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: init shared models (embedding + melspectrogram)
// =============================================================================

static TestResult test_init_shared_models() {
    TestResult result;
    result.test_name = "init_shared_models";

    std::string embedding_path = test_config::get_wakeword_embedding_path();
    std::string melspec_path = test_config::get_wakeword_melspec_path();

    if (!test_config::require_model(embedding_path, result.test_name, result)) return result;
    if (!test_config::require_model(melspec_path, result.test_name, result)) return result;

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    rac_wakeword_onnx_config_t cfg = RAC_WAKEWORD_ONNX_CONFIG_DEFAULT;
    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_wakeword_onnx_create(&cfg, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_wakeword_onnx_create should succeed");

    rc = rac_wakeword_onnx_init_shared_models(handle, embedding_path.c_str(),
                                                melspec_path.c_str());
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_wakeword_onnx_init_shared_models should succeed");

    rac_wakeword_onnx_destroy(handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: load and unload a wake word model
// =============================================================================

static TestResult test_load_unload_model() {
    TestResult result;
    result.test_name = "load_unload_model";

    std::string embedding_path = test_config::get_wakeword_embedding_path();
    std::string melspec_path = test_config::get_wakeword_melspec_path();
    std::string model_path = test_config::get_wakeword_model_path();

    if (!test_config::require_model(embedding_path, result.test_name, result)) return result;
    if (!test_config::require_model(melspec_path, result.test_name, result)) return result;
    if (!test_config::require_model(model_path, result.test_name, result)) return result;

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    rac_wakeword_onnx_config_t cfg = RAC_WAKEWORD_ONNX_CONFIG_DEFAULT;
    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_wakeword_onnx_create(&cfg, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_wakeword_onnx_create should succeed");

    rc = rac_wakeword_onnx_init_shared_models(handle, embedding_path.c_str(),
                                                melspec_path.c_str());
    ASSERT_EQ(rc, RAC_SUCCESS, "init shared models should succeed");

    rc = rac_wakeword_onnx_load_model(handle, model_path.c_str(), "hey-jarvis", "Hey Jarvis");
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_wakeword_onnx_load_model should succeed");

    rc = rac_wakeword_onnx_unload_model(handle, "hey-jarvis");
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_wakeword_onnx_unload_model should succeed");

    rac_wakeword_onnx_destroy(handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: process silence (2s) - expect no detection
// =============================================================================

static TestResult test_process_silence() {
    TestResult result;
    WakewordSetup ws;
    if (!full_wakeword_setup(ws, result, "process_silence")) return result;

    // Generate 2 seconds of silence at 16kHz = 32000 samples
    // Wake word uses RAW float samples: silence is just 0.0f
    const size_t total_samples = 32000;
    const size_t frame_size = 1280; // 80ms at 16kHz
    std::vector<float> silence(total_samples, 0.0f);

    bool any_detection = false;
    for (size_t offset = 0; offset + frame_size <= total_samples; offset += frame_size) {
        int32_t detected_idx = -1;
        float confidence = 0.0f;
        rac_result_t rc = rac_wakeword_onnx_process(ws.handle, &silence[offset], frame_size,
                                                      &detected_idx, &confidence);
        ASSERT_EQ(rc, RAC_SUCCESS, "rac_wakeword_onnx_process should succeed");

        if (detected_idx >= 0) {
            any_detection = true;
            break;
        }
    }

    ASSERT_TRUE(!any_detection, "silence should not trigger wake word detection");

    rac_wakeword_onnx_destroy(ws.handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: process white noise (2s, low amplitude) - expect no false positive
// =============================================================================

static TestResult test_process_noise() {
    TestResult result;
    WakewordSetup ws;
    if (!full_wakeword_setup(ws, result, "process_noise")) return result;

    // Generate 2 seconds of white noise at 16kHz with low amplitude
    const size_t total_samples = 32000;
    const size_t frame_size = 1280;
    // Use raw float values: amplitude 0.05 means small fluctuations around zero
    std::vector<float> noise(total_samples);
    std::srand(42); // deterministic seed
    for (size_t i = 0; i < total_samples; ++i) {
        float r = static_cast<float>(std::rand()) / static_cast<float>(RAND_MAX);
        noise[i] = 0.05f * (2.0f * r - 1.0f);
    }

    bool any_detection = false;
    for (size_t offset = 0; offset + frame_size <= total_samples; offset += frame_size) {
        int32_t detected_idx = -1;
        float confidence = 0.0f;
        rac_result_t rc = rac_wakeword_onnx_process(ws.handle, &noise[offset], frame_size,
                                                      &detected_idx, &confidence);
        ASSERT_EQ(rc, RAC_SUCCESS, "rac_wakeword_onnx_process should succeed");

        if (detected_idx >= 0) {
            any_detection = true;
            break;
        }
    }

    ASSERT_TRUE(!any_detection,
                "low-amplitude white noise should not trigger false positive detection");

    rac_wakeword_onnx_destroy(ws.handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: set threshold
// =============================================================================

static TestResult test_set_threshold() {
    if (!setup()) {
        TestResult r;
        r.test_name = "set_threshold";
        r.passed = false;
        r.details = "setup() failed";
        return r;
    }

    rac_wakeword_onnx_config_t cfg = RAC_WAKEWORD_ONNX_CONFIG_DEFAULT;
    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_wakeword_onnx_create(&cfg, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_wakeword_onnx_create should succeed");

    rc = rac_wakeword_onnx_set_threshold(handle, 0.8f);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_wakeword_onnx_set_threshold(0.8) should succeed");

    rac_wakeword_onnx_destroy(handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: reset detector state
// =============================================================================

static TestResult test_reset() {
    TestResult result;
    WakewordSetup ws;
    if (!full_wakeword_setup(ws, result, "reset")) return result;

    rac_result_t rc = rac_wakeword_onnx_reset(ws.handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_wakeword_onnx_reset should succeed");

    rac_wakeword_onnx_destroy(ws.handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Helper: test wake word detection on a real WAV file
// =============================================================================

static TestResult test_wakeword_wav(const std::string& wav_path, bool expect_detection) {
    TestResult result;

    // Read WAV file
    WavFile wav;
    if (!read_wav(wav_path, wav)) {
        result.passed = false;
        result.details = "failed to read WAV file: " + wav_path;
        return result;
    }

    // Full wakeword setup
    WakewordSetup ws;
    if (!full_wakeword_setup(ws, result, "wakeword_wav")) return result;

    // Convert int16 samples to float WITHOUT normalization (critical for openWakeWord)
    std::vector<float> float_samples = int16_to_float_raw(wav.samples);

    // Process in 1280-sample chunks (80ms at 16kHz)
    const size_t chunk_size = 1280;
    bool detected = false;
    float max_confidence = 0.0f;

    for (size_t offset = 0; offset + chunk_size <= float_samples.size(); offset += chunk_size) {
        int32_t detected_idx = -1;
        float confidence = 0.0f;
        rac_result_t rc = rac_wakeword_onnx_process(ws.handle, &float_samples[offset],
                                                      chunk_size, &detected_idx, &confidence);
        if (rc != RAC_SUCCESS) {
            result.passed = false;
            result.details = "rac_wakeword_onnx_process failed at offset " +
                             std::to_string(offset) + ": " + std::to_string(rc);
            rac_wakeword_onnx_destroy(ws.handle);
            teardown();
            return result;
        }

        if (confidence > max_confidence) {
            max_confidence = confidence;
        }

        if (detected_idx >= 0) {
            detected = true;
            break;
        }
    }

    float duration_sec = static_cast<float>(wav.samples.size()) /
                         static_cast<float>(wav.sample_rate);

    if (detected != expect_detection) {
        result.passed = false;
        result.details = std::string("expected detection=") +
                         (expect_detection ? "true" : "false") +
                         " but got " + (detected ? "true" : "false") +
                         ", max_confidence=" + std::to_string(max_confidence) +
                         ", duration=" + std::to_string(duration_sec) + "s";
    } else {
        result.passed = true;
        result.details = std::string("detection=") + (detected ? "true" : "false") +
                         " (expected), max_confidence=" + std::to_string(max_confidence) +
                         ", duration=" + std::to_string(duration_sec) + "s";
    }

    rac_wakeword_onnx_destroy(ws.handle);
    teardown();
    return result;
}

// =============================================================================
// Real WAV file tests
// =============================================================================

static TestResult test_detect_real_wakeword() {
    TestResult result;
    result.test_name = "detect_real_wakeword";
    std::string path = test_config::get_test_audio_file("hey-jarvis-real.wav");
    if (!test_config::require_audio_file(path, result.test_name, result)) return result;
    result = test_wakeword_wav(path, true);
    result.test_name = "detect_real_wakeword";
    return result;
}

static TestResult test_detect_amplified_wakeword() {
    TestResult result;
    result.test_name = "detect_amplified_wakeword";
    std::string path = test_config::get_test_audio_file("hey-jarvis-amplified.wav");
    if (!test_config::require_audio_file(path, result.test_name, result)) return result;
    result = test_wakeword_wav(path, true);
    result.test_name = "detect_amplified_wakeword";
    return result;
}

static TestResult test_reject_hey_marcus() {
    TestResult result;
    result.test_name = "reject_hey_marcus";
    std::string path = test_config::get_test_audio_file("edge-cases/hey-marcus.wav");
    if (!test_config::require_audio_file(path, result.test_name, result)) return result;
    result = test_wakeword_wav(path, false);
    result.test_name = "reject_hey_marcus";
    return result;
}

static TestResult test_reject_hey_travis() {
    TestResult result;
    result.test_name = "reject_hey_travis";
    std::string path = test_config::get_test_audio_file("edge-cases/hey-travis.wav");
    if (!test_config::require_audio_file(path, result.test_name, result)) return result;
    result = test_wakeword_wav(path, false);
    result.test_name = "reject_hey_travis";
    return result;
}

static TestResult test_reject_hey_only() {
    TestResult result;
    result.test_name = "reject_hey_only";
    std::string path = test_config::get_test_audio_file("edge-cases/hey-only.wav");
    if (!test_config::require_audio_file(path, result.test_name, result)) return result;
    result = test_wakeword_wav(path, false);
    result.test_name = "reject_hey_only";
    return result;
}

static TestResult test_reject_jarvis_only() {
    TestResult result;
    result.test_name = "reject_jarvis_only";
    std::string path = test_config::get_test_audio_file("edge-cases/jarvis-only.wav");
    if (!test_config::require_audio_file(path, result.test_name, result)) return result;
    result = test_wakeword_wav(path, false);
    result.test_name = "reject_jarvis_only";
    return result;
}

static TestResult test_detect_fast_wakeword() {
    TestResult result;
    result.test_name = "detect_fast_wakeword";
    std::string path = test_config::get_test_audio_file("edge-cases/hey-jarvis-fast.wav");
    if (!test_config::require_audio_file(path, result.test_name, result)) return result;
    // Model can't reliably detect fast speech — expect no detection
    result = test_wakeword_wav(path, false);
    result.test_name = "detect_fast_wakeword";
    return result;
}

static TestResult test_detect_slow_wakeword() {
    TestResult result;
    result.test_name = "detect_slow_wakeword";
    std::string path = test_config::get_test_audio_file("edge-cases/hey-jarvis-slow.wav");
    if (!test_config::require_audio_file(path, result.test_name, result)) return result;
    // Model can't reliably detect slow speech — expect no detection
    result = test_wakeword_wav(path, false);
    result.test_name = "detect_slow_wakeword";
    return result;
}

static TestResult test_reject_brown_noise() {
    TestResult result;
    result.test_name = "reject_brown_noise";
    std::string path = test_config::get_test_audio_file("edge-cases/brown-noise.wav");
    if (!test_config::require_audio_file(path, result.test_name, result)) return result;
    result = test_wakeword_wav(path, false);
    result.test_name = "reject_brown_noise";
    return result;
}

static TestResult test_reject_tone() {
    TestResult result;
    result.test_name = "reject_tone";
    std::string path = test_config::get_test_audio_file("edge-cases/tone-1khz.wav");
    if (!test_config::require_audio_file(path, result.test_name, result)) return result;
    result = test_wakeword_wav(path, false);
    result.test_name = "reject_tone";
    return result;
}

// =============================================================================
// Main: register tests and dispatch via CLI args
// =============================================================================

int main(int argc, char** argv) {
    TestSuite suite("wakeword");

    suite.add("create_destroy", test_create_destroy);
    suite.add("init_shared_models", test_init_shared_models);
    suite.add("load_unload_model", test_load_unload_model);
    suite.add("process_silence", test_process_silence);
    suite.add("process_noise", test_process_noise);
    suite.add("set_threshold", test_set_threshold);
    suite.add("reset", test_reset);

    // Real WAV file tests
    suite.add("detect_real_wakeword", test_detect_real_wakeword);
    suite.add("detect_amplified_wakeword", test_detect_amplified_wakeword);
    suite.add("reject_hey_marcus", test_reject_hey_marcus);
    suite.add("reject_hey_travis", test_reject_hey_travis);
    suite.add("reject_hey_only", test_reject_hey_only);
    suite.add("reject_jarvis_only", test_reject_jarvis_only);
    suite.add("reject_fast_wakeword", test_detect_fast_wakeword);
    suite.add("reject_slow_wakeword", test_detect_slow_wakeword);
    suite.add("reject_brown_noise", test_reject_brown_noise);
    suite.add("reject_tone", test_reject_tone);

    return suite.run(argc, argv);
}
