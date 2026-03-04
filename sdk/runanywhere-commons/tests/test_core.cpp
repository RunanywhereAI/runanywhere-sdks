/**
 * @file test_core.cpp
 * @brief Integration tests for runanywhere-commons core infrastructure.
 *
 * Tests core init/shutdown, error handling, logging, module registry,
 * memory allocation, and audio utilities -- WITHOUT any ML backends.
 */

#include "test_common.h"
#include "test_config.h"

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_platform_adapter.h"

#include <chrono>
#include <cmath>
#include <cstring>
#include <string>
#include <vector>

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
    config.log_tag = "TEST";
    config.reserved = nullptr;
    return config;
}

// =============================================================================
// Test: init / shutdown lifecycle
// =============================================================================

static TestResult test_init_shutdown() {
    rac_config_t config = make_test_config();

    rac_result_t rc = rac_init(&config);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_init should succeed");
    ASSERT_EQ(rac_is_initialized(), RAC_TRUE, "rac_is_initialized should be TRUE after init");

    rac_shutdown();
    ASSERT_EQ(rac_is_initialized(), RAC_FALSE, "rac_is_initialized should be FALSE after shutdown");

    return TEST_PASS();
}

// =============================================================================
// Test: double init returns error
// =============================================================================

static TestResult test_double_init() {
    rac_config_t config = make_test_config();

    rac_result_t rc = rac_init(&config);
    ASSERT_EQ(rc, RAC_SUCCESS, "first rac_init should succeed");

    rac_result_t rc2 = rac_init(&config);
    ASSERT_EQ(rc2, RAC_ERROR_ALREADY_INITIALIZED,
              "second rac_init should return RAC_ERROR_ALREADY_INITIALIZED");

    rac_shutdown();
    return TEST_PASS();
}

// =============================================================================
// Test: version info
// =============================================================================

static TestResult test_get_version() {
    rac_config_t config = make_test_config();
    rac_result_t rc = rac_init(&config);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_init should succeed");

    rac_version_t ver = rac_get_version();
    ASSERT_TRUE(ver.string != nullptr, "version string should not be NULL");
    ASSERT_TRUE(std::strlen(ver.string) > 0, "version string should not be empty");
    ASSERT_TRUE(ver.major < 100, "major version should be reasonable (< 100)");
    ASSERT_TRUE(ver.minor < 100, "minor version should be reasonable (< 100)");
    ASSERT_TRUE(ver.patch < 1000, "patch version should be reasonable (< 1000)");

    rac_shutdown();
    return TEST_PASS();
}

// =============================================================================
// Test: error messages for known codes
// =============================================================================

static TestResult test_error_message_known() {
    const char* msg_success = rac_error_message(RAC_SUCCESS);
    ASSERT_TRUE(msg_success != nullptr, "rac_error_message(RAC_SUCCESS) should not be NULL");
    ASSERT_TRUE(std::strlen(msg_success) > 0,
                "rac_error_message(RAC_SUCCESS) should not be empty");

    const char* msg_not_init = rac_error_message(RAC_ERROR_NOT_INITIALIZED);
    ASSERT_TRUE(msg_not_init != nullptr,
                "rac_error_message(RAC_ERROR_NOT_INITIALIZED) should not be NULL");
    ASSERT_TRUE(std::strlen(msg_not_init) > 0,
                "rac_error_message(RAC_ERROR_NOT_INITIALIZED) should not be empty");

    const char* msg_model = rac_error_message(RAC_ERROR_MODEL_NOT_FOUND);
    ASSERT_TRUE(msg_model != nullptr,
                "rac_error_message(RAC_ERROR_MODEL_NOT_FOUND) should not be NULL");
    ASSERT_TRUE(std::strlen(msg_model) > 0,
                "rac_error_message(RAC_ERROR_MODEL_NOT_FOUND) should not be empty");

    return TEST_PASS();
}

// =============================================================================
// Test: error message for unknown code
// =============================================================================

static TestResult test_error_message_unknown() {
    const char* msg = rac_error_message(static_cast<rac_result_t>(-9999));
    ASSERT_TRUE(msg != nullptr,
                "rac_error_message(-9999) should not be NULL (unknown code)");

    return TEST_PASS();
}

// =============================================================================
// Test: error classification helpers
// =============================================================================

static TestResult test_error_classification() {
    // -100 to -999 are commons errors
    ASSERT_EQ(rac_error_is_commons_error(static_cast<rac_result_t>(-100)), RAC_TRUE,
              "-100 should be a commons error");
    ASSERT_EQ(rac_error_is_commons_error(static_cast<rac_result_t>(-999)), RAC_TRUE,
              "-999 should be a commons error");
    ASSERT_EQ(rac_error_is_commons_error(static_cast<rac_result_t>(0)), RAC_FALSE,
              "0 (success) should not be a commons error");

    // RAC_ERROR_CANCELLED is expected
    ASSERT_EQ(rac_error_is_expected(RAC_ERROR_CANCELLED), RAC_TRUE,
              "RAC_ERROR_CANCELLED should be an expected error");

    return TEST_PASS();
}

// =============================================================================
// Test: error details (set / get / clear)
// =============================================================================

static TestResult test_error_details() {
    rac_error_set_details("test detail");
    const char* detail = rac_error_get_details();
    ASSERT_TRUE(detail != nullptr, "rac_error_get_details should return non-NULL after set");
    ASSERT_TRUE(std::strcmp(detail, "test detail") == 0,
                "rac_error_get_details should return 'test detail'");

    rac_error_clear_details();
    const char* cleared = rac_error_get_details();
    ASSERT_TRUE(cleared == nullptr,
                "rac_error_get_details should return NULL after clear");

    return TEST_PASS();
}

// =============================================================================
// Test: logger level management
// =============================================================================

static TestResult test_logger_levels() {
    rac_result_t rc = rac_logger_init(RAC_LOG_DEBUG);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_logger_init should succeed");
    ASSERT_EQ(rac_logger_get_min_level(), RAC_LOG_DEBUG,
              "min level should be DEBUG after init");

    rac_logger_set_min_level(RAC_LOG_WARNING);
    ASSERT_EQ(rac_logger_get_min_level(), RAC_LOG_WARNING,
              "min level should be WARNING after set");

    rac_logger_shutdown();
    return TEST_PASS();
}

// =============================================================================
// Test: logger macros do not crash
// =============================================================================

static TestResult test_logger_no_crash() {
    rac_result_t rc = rac_logger_init(RAC_LOG_DEBUG);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_logger_init should succeed");

    // Suppress stderr output during this test
    rac_logger_set_stderr_always(RAC_FALSE);
    rac_logger_set_stderr_fallback(RAC_FALSE);

    RAC_LOG_INFO("TEST", "test message %d", 42);
    RAC_LOG_ERROR("TEST", "error");
    RAC_LOG_DEBUG("TEST", "debug");

    rac_logger_shutdown();

    // If we reach here, no crash occurred.
    return TEST_PASS();
}

// =============================================================================
// Test: module register / list / unregister
// =============================================================================

static TestResult test_module_register() {
    rac_config_t config = make_test_config();
    rac_result_t rc = rac_init(&config);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_init should succeed");

    // Prepare module info
    rac_capability_t caps[] = {RAC_CAPABILITY_STT};
    rac_module_info_t mod = {};
    mod.id = "test-module";
    mod.name = "Test";
    mod.version = "1.0";
    mod.description = "A test module";
    mod.capabilities = caps;
    mod.num_capabilities = 1;

    rc = rac_module_register(&mod);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_module_register should succeed");

    // List modules
    const rac_module_info_t* modules = nullptr;
    size_t count = 0;
    rc = rac_module_list(&modules, &count);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_module_list should succeed");
    ASSERT_TRUE(count > 0, "module count should be > 0 after register");

    // Verify our module is in the list
    bool found = false;
    for (size_t i = 0; i < count; ++i) {
        if (modules[i].id && std::strcmp(modules[i].id, "test-module") == 0) {
            found = true;
            break;
        }
    }
    ASSERT_TRUE(found, "registered module 'test-module' should appear in module list");

    // Unregister
    rc = rac_module_unregister("test-module");
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_module_unregister should succeed");

    rac_shutdown();
    return TEST_PASS();
}

// =============================================================================
// Test: rac_alloc / rac_free / rac_strdup
// =============================================================================

static TestResult test_alloc_free() {
    void* ptr = rac_alloc(100);
    ASSERT_TRUE(ptr != nullptr, "rac_alloc(100) should return non-NULL");
    rac_free(ptr);

    char* dup = rac_strdup("hello");
    ASSERT_TRUE(dup != nullptr, "rac_strdup(\"hello\") should return non-NULL");
    ASSERT_TRUE(std::strcmp(dup, "hello") == 0,
                "rac_strdup result should match original string");
    rac_free(dup);

    return TEST_PASS();
}

// =============================================================================
// Test: float32 PCM -> WAV conversion
// =============================================================================

static TestResult test_audio_float32_to_wav() {
    // Generate 0.1s sine wave at 16 kHz = 1600 samples
    const int32_t sample_rate = 16000;
    const size_t num_samples = 1600;
    std::vector<float> samples(num_samples);
    const double freq = 440.0;  // A4
    for (size_t i = 0; i < num_samples; ++i) {
        samples[i] =
            static_cast<float>(std::sin(2.0 * M_PI * freq * static_cast<double>(i) / sample_rate));
    }

    void* wav_data = nullptr;
    size_t wav_size = 0;
    rac_result_t rc = rac_audio_float32_to_wav(samples.data(), num_samples * sizeof(float),
                                                sample_rate, &wav_data, &wav_size);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_audio_float32_to_wav should succeed");
    ASSERT_TRUE(wav_data != nullptr, "wav_data should not be NULL");
    ASSERT_TRUE(wav_size > 44, "wav_size should be > 44 (WAV header)");

    rac_free(wav_data);

    // Verify header size constant
    size_t hdr = rac_audio_wav_header_size();
    ASSERT_EQ(static_cast<int>(hdr), 44, "WAV header size should be 44");

    return TEST_PASS();
}

// =============================================================================
// Test: int16 PCM -> WAV conversion
// =============================================================================

static TestResult test_audio_int16_to_wav() {
    // Generate 0.1s sine wave as int16 at 16 kHz = 1600 samples
    const int32_t sample_rate = 16000;
    const size_t num_samples = 1600;
    std::vector<int16_t> samples(num_samples);
    const double freq = 440.0;
    for (size_t i = 0; i < num_samples; ++i) {
        double val = std::sin(2.0 * M_PI * freq * static_cast<double>(i) / sample_rate);
        samples[i] = static_cast<int16_t>(val * 32767.0);
    }

    void* wav_data = nullptr;
    size_t wav_size = 0;
    rac_result_t rc = rac_audio_int16_to_wav(samples.data(), num_samples * sizeof(int16_t),
                                              sample_rate, &wav_data, &wav_size);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_audio_int16_to_wav should succeed");
    ASSERT_TRUE(wav_data != nullptr, "wav_data should not be NULL");
    ASSERT_TRUE(wav_size > 44, "wav_size should be > 44 (WAV header)");

    rac_free(wav_data);
    return TEST_PASS();
}

// =============================================================================
// Main: register tests and dispatch via CLI args
// =============================================================================

int main(int argc, char** argv) {
    TestSuite suite("core");

    suite.add("init_shutdown", test_init_shutdown);
    suite.add("double_init", test_double_init);
    suite.add("get_version", test_get_version);
    suite.add("error_message_known", test_error_message_known);
    suite.add("error_message_unknown", test_error_message_unknown);
    suite.add("error_classification", test_error_classification);
    suite.add("error_details", test_error_details);
    suite.add("logger_levels", test_logger_levels);
    suite.add("logger_no_crash", test_logger_no_crash);
    suite.add("module_register", test_module_register);
    suite.add("alloc_free", test_alloc_free);
    suite.add("audio_float32_to_wav", test_audio_float32_to_wav);
    suite.add("audio_int16_to_wav", test_audio_int16_to_wav);

    return suite.run(argc, argv);
}
