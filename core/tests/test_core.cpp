/**
 * @file test_core.cpp
 * @brief Integration tests for runanywhere-commons core infrastructure.
 *
 * Tests core init/shutdown, error handling, logging, module registry,
 * memory allocation, and audio utilities -- WITHOUT any ML backends.
 */

#include "test_common.h"
#include "test_config.h"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <exception>
#include <string>
#include <vector>

#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"

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

// Minimal no-op mandatory-slot stubs. rac_init now fail-fasts when any
// mandatory slot is NULL, so every mandatory slot must be a real (non-NULL)
// function pointer even for the lifecycle-only tests.
static rac_bool_t test_file_exists(const char* /*path*/, void* /*ctx*/) {
    return RAC_FALSE;
}
static rac_result_t test_file_read(const char* /*path*/, void** /*out_data*/, size_t* /*out_size*/,
                                   void* /*ctx*/) {
    return RAC_ERROR_FILE_NOT_FOUND;
}
static rac_result_t test_file_write(const char* /*path*/, const void* /*data*/, size_t /*size*/,
                                    void* /*ctx*/) {
    return RAC_SUCCESS;
}
static rac_result_t test_file_delete(const char* /*path*/, void* /*ctx*/) {
    return RAC_SUCCESS;
}
static rac_result_t test_secure_get(const char* /*key*/, char** /*out_value*/, void* /*ctx*/) {
    return RAC_ERROR_FILE_NOT_FOUND;
}
static rac_result_t test_secure_set(const char* /*key*/, const char* /*value*/, void* /*ctx*/) {
    return RAC_SUCCESS;
}
static rac_result_t test_secure_delete(const char* /*key*/, void* /*ctx*/) {
    return RAC_SUCCESS;
}

// Build a fully-valid happy-path adapter (correct abi_version + struct_size and
// every mandatory slot populated). Returned by value so individual tests can
// tweak a field to exercise the new rac_init validation.
static rac_platform_adapter_t make_valid_test_adapter() {
    rac_platform_adapter_t adapter = {};
    adapter.abi_version = RAC_PLATFORM_ADAPTER_ABI_VERSION;
    adapter.struct_size = static_cast<uint32_t>(sizeof(rac_platform_adapter_t));
    adapter.file_exists = test_file_exists;
    adapter.file_read = test_file_read;
    adapter.file_write = test_file_write;
    adapter.file_delete = test_file_delete;
    adapter.secure_get = test_secure_get;
    adapter.secure_set = test_secure_set;
    adapter.secure_delete = test_secure_delete;
    adapter.log = test_log_callback;
    adapter.now_ms = test_now_ms;
    return adapter;
}

// Stable storage for the happy-path adapter referenced by make_test_config().
// The adapter pointer must outlive rac_init/rac_shutdown by contract.
static const rac_platform_adapter_t test_adapter = make_valid_test_adapter();

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

static int test_auth_store(const char*, const char*, void*) {
    return 0;
}

static int test_auth_retrieve(const char*, char*, size_t, void*) {
    return RAC_ERROR_FILE_NOT_FOUND;
}

static int test_auth_delete(const char*, void*) {
    return 0;
}

static void test_device_info(rac_device_registration_info_t*, void*) {}

static const char* test_device_id(void*) {
    return "123e4567-e89b-12d3-a456-426614174000";
}

static rac_bool_t test_device_registered(void*) {
    return RAC_FALSE;
}

static void test_set_device_registered(rac_bool_t, void*) {}

static rac_result_t test_device_http(const char*, const char*, rac_bool_t,
                                     rac_device_http_response_t*, void*) {
    return RAC_SUCCESS;
}

static TestResult test_shutdown_clears_all_commons_lifetime_state() {
    ASSERT_EQ(rac_set_platform_adapter(&test_adapter), RAC_SUCCESS,
              "direct platform adapter registration should succeed");
    ASSERT_EQ(rac_state_initialize(RAC_ENV_PRODUCTION, "state-secret", "https://api.runanywhere.ai",
                                   "123e4567-e89b-12d3-a456-426614174000"),
              RAC_SUCCESS, "runtime state should initialize");

    rac_sdk_config_t sdk_config = {};
    sdk_config.environment = RAC_ENV_PRODUCTION;
    sdk_config.api_key = "sdk-secret-key-1234567890";
    sdk_config.base_url = "https://api.runanywhere.ai";
    sdk_config.device_id = "123e4567-e89b-12d3-a456-426614174000";
    sdk_config.platform = "test";
    sdk_config.sdk_version = "0.20.0";
    ASSERT_EQ(rac_sdk_init(&sdk_config), RAC_VALIDATION_OK,
              "copied SDK configuration should initialize");

    rac_secure_storage_t storage = {};
    storage.store = test_auth_store;
    storage.retrieve = test_auth_retrieve;
    storage.delete_key = test_auth_delete;
    rac_auth_init(&storage);

    rac_device_callbacks_t device_callbacks = {};
    device_callbacks.get_device_info = test_device_info;
    device_callbacks.get_device_id = test_device_id;
    device_callbacks.is_registered = test_device_registered;
    device_callbacks.set_registered = test_set_device_registered;
    device_callbacks.http_post = test_device_http;
    ASSERT_EQ(rac_device_manager_set_callbacks(&device_callbacks), RAC_SUCCESS,
              "device callbacks should install");

    // This lifetime intentionally used rac_set_platform_adapter directly and
    // never called rac_init. rac_shutdown must still own every state layer.
    rac_shutdown();

    ASSERT_TRUE(rac_get_platform_adapter() == nullptr,
                "shutdown must release the borrowed platform adapter");
    ASSERT_TRUE(!rac_state_is_initialized(), "shutdown must clear runtime state");
    ASSERT_TRUE(!rac_sdk_is_initialized(), "shutdown must clear copied SDK configuration");
    ASSERT_EQ(rac_auth_load_stored_tokens(), RAC_ERROR_NOT_SUPPORTED,
              "shutdown must detach auth storage callbacks");
    ASSERT_EQ(rac_device_manager_register_if_needed(RAC_ENV_PRODUCTION, nullptr),
              RAC_ERROR_NOT_INITIALIZED, "shutdown must clear device callbacks");
    return TEST_PASS();
}

struct ShutdownTelemetryCapture {
    int request_count = 0;
    std::string last_body;
};

static void capture_shutdown_telemetry(void* user_data, const char* /*endpoint*/,
                                       const char* json_body, size_t json_length,
                                       rac_bool_t /*requires_auth*/) {
    auto* capture = static_cast<ShutdownTelemetryCapture*>(user_data);
    if (capture == nullptr)
        return;
    capture->request_count += 1;
    capture->last_body.assign(json_body ? json_body : "", json_body ? json_length : 0);
}

static rac_telemetry_manager_t* make_shutdown_telemetry_manager(ShutdownTelemetryCapture* capture) {
    auto* manager =
        rac_telemetry_manager_create(RAC_ENV_PRODUCTION, "shutdown-device", "test", "0.20.0");
    if (manager != nullptr) {
        rac_telemetry_manager_set_http_callback(manager, capture_shutdown_telemetry, capture);
        rac_events_set_telemetry_sink(manager);
    }
    return manager;
}

static TestResult test_shutdown_flushes_terminal_telemetry_before_lifetime_clear() {
    constexpr const char* kAuthResponse =
        R"({"access_token":"shutdown-access","refresh_token":"shutdown-refresh","device_id":"shutdown-device","user_id":"shutdown-user","organization_id":"shutdown-org","token_type":"bearer","expires_in":3600})";

    ShutdownTelemetryCapture state_capture;
    rac_auth_init(nullptr);
    ASSERT_EQ(rac_auth_handle_authenticate_response(kAuthResponse), RAC_SUCCESS,
              "state lifetime must be authenticated before terminal flush");
    auto* state_manager = make_shutdown_telemetry_manager(&state_capture);
    ASSERT_TRUE(state_manager != nullptr, "state lifetime telemetry manager should initialize");
    ASSERT_EQ(rac_state_initialize(RAC_ENV_PRODUCTION, "api-key", "https://example.invalid",
                                   "shutdown-device"),
              RAC_SUCCESS, "state lifetime should initialize");

    rac_shutdown();
    rac_events_set_telemetry_sink(nullptr);
    rac_telemetry_manager_destroy(state_manager);

    ASSERT_EQ(state_capture.request_count, 1,
              "state shutdown must flush exactly one terminal telemetry batch");
    ASSERT_TRUE(!state_capture.last_body.empty(),
                "state shutdown terminal telemetry batch must carry a body");

    ShutdownTelemetryCapture core_capture;
    rac_auth_init(nullptr);
    ASSERT_EQ(rac_auth_handle_authenticate_response(kAuthResponse), RAC_SUCCESS,
              "core-only lifetime must be authenticated before terminal flush");
    auto* core_manager = make_shutdown_telemetry_manager(&core_capture);
    ASSERT_TRUE(core_manager != nullptr, "core lifetime telemetry manager should initialize");
    rac_config_t config = make_test_config();
    ASSERT_EQ(rac_init(&config), RAC_SUCCESS, "core-only lifetime should initialize");

    rac_shutdown();
    rac_events_set_telemetry_sink(nullptr);
    rac_telemetry_manager_destroy(core_manager);

    ASSERT_EQ(core_capture.request_count, 1,
              "core-only shutdown must flush exactly one terminal telemetry batch");
    ASSERT_TRUE(!core_capture.last_body.empty(),
                "core-only shutdown terminal telemetry batch must carry a body");
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
// Test: platform adapter ABI / mandatory-slot validation in rac_init
// =============================================================================

static TestResult test_init_wrong_abi_version() {
    rac_platform_adapter_t adapter = make_valid_test_adapter();
    adapter.abi_version = RAC_PLATFORM_ADAPTER_ABI_VERSION + 1;  // mismatch

    rac_config_t config = {};
    config.platform_adapter = &adapter;
    config.log_level = RAC_LOG_WARNING;
    config.log_tag = "TEST";

    rac_result_t rc = rac_init(&config);
    ASSERT_EQ(rc, RAC_ERROR_ABI_VERSION_MISMATCH,
              "rac_init should reject a wrong abi_version with RAC_ERROR_ABI_VERSION_MISMATCH");
    ASSERT_EQ(rac_is_initialized(), RAC_FALSE, "rac_init must not initialize on ABI mismatch");
    return TEST_PASS();
}

static TestResult test_init_wrong_struct_size() {
    rac_platform_adapter_t adapter = make_valid_test_adapter();
    adapter.struct_size = static_cast<uint32_t>(sizeof(rac_platform_adapter_t)) - 4;  // mismatch

    rac_config_t config = {};
    config.platform_adapter = &adapter;
    config.log_level = RAC_LOG_WARNING;
    config.log_tag = "TEST";

    rac_result_t rc = rac_init(&config);
    ASSERT_EQ(rc, RAC_ERROR_ABI_VERSION_MISMATCH,
              "rac_init should reject a wrong struct_size with RAC_ERROR_ABI_VERSION_MISMATCH");
    ASSERT_EQ(rac_is_initialized(), RAC_FALSE,
              "rac_init must not initialize on struct_size mismatch");
    return TEST_PASS();
}

static TestResult test_init_missing_mandatory_slot() {
    rac_platform_adapter_t adapter = make_valid_test_adapter();
    adapter.now_ms = nullptr;  // drop a mandatory slot

    rac_config_t config = {};
    config.platform_adapter = &adapter;
    config.log_level = RAC_LOG_WARNING;
    config.log_tag = "TEST";

    rac_result_t rc = rac_init(&config);
    ASSERT_EQ(rc, RAC_ERROR_ADAPTER_NOT_SET,
              "rac_init should reject a NULL mandatory slot with RAC_ERROR_ADAPTER_NOT_SET");
    ASSERT_EQ(rac_is_initialized(), RAC_FALSE,
              "rac_init must not initialize when a mandatory slot is NULL");
    return TEST_PASS();
}

static TestResult test_init_valid_adapter_succeeds() {
    rac_platform_adapter_t adapter = make_valid_test_adapter();

    rac_config_t config = {};
    config.platform_adapter = &adapter;
    config.log_level = RAC_LOG_WARNING;
    config.log_tag = "TEST";

    rac_result_t rc = rac_init(&config);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_init should succeed with a fully-valid adapter");
    ASSERT_EQ(rac_is_initialized(), RAC_TRUE, "rac_is_initialized should be TRUE after init");

    rac_shutdown();
    ASSERT_EQ(rac_is_initialized(), RAC_FALSE, "rac_is_initialized should be FALSE after shutdown");
    return TEST_PASS();
}

// =============================================================================
// Test: error messages for known codes
// =============================================================================

static TestResult test_error_message_known() {
    const char* msg_success = rac_error_message(RAC_SUCCESS);
    ASSERT_TRUE(msg_success != nullptr, "rac_error_message(RAC_SUCCESS) should not be NULL");
    ASSERT_TRUE(std::strlen(msg_success) > 0, "rac_error_message(RAC_SUCCESS) should not be empty");

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
    ASSERT_TRUE(msg != nullptr, "rac_error_message(-9999) should not be NULL (unknown code)");

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
    ASSERT_TRUE(cleared == nullptr, "rac_error_get_details should return NULL after clear");

    return TEST_PASS();
}

// =============================================================================
// Test: logger level management
// =============================================================================

static TestResult test_logger_levels() {
    rac_result_t rc = rac_logger_init(RAC_LOG_DEBUG);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_logger_init should succeed");
    ASSERT_EQ(rac_logger_get_min_level(), RAC_LOG_DEBUG, "min level should be DEBUG after init");

    rac_logger_set_min_level(RAC_LOG_WARNING);
    ASSERT_EQ(rac_logger_get_min_level(), RAC_LOG_WARNING, "min level should be WARNING after set");

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
// Test: rac_alloc / rac_free / rac_strdup
// =============================================================================

static TestResult test_alloc_free() {
    void* ptr = rac_alloc(100);
    ASSERT_TRUE(ptr != nullptr, "rac_alloc(100) should return non-NULL");
    rac_free(ptr);

    char* dup = rac_strdup("hello");
    ASSERT_TRUE(dup != nullptr, "rac_strdup(\"hello\") should return non-NULL");
    ASSERT_TRUE(std::strcmp(dup, "hello") == 0, "rac_strdup result should match original string");
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
    try {
        TestSuite suite("core");

        suite.add("init_shutdown", test_init_shutdown);
        suite.add("shutdown_clears_all_commons_lifetime_state",
                  test_shutdown_clears_all_commons_lifetime_state);
        suite.add("shutdown_flushes_terminal_telemetry_before_lifetime_clear",
                  test_shutdown_flushes_terminal_telemetry_before_lifetime_clear);
        suite.add("double_init", test_double_init);
        suite.add("get_version", test_get_version);
        suite.add("init_wrong_abi_version", test_init_wrong_abi_version);
        suite.add("init_wrong_struct_size", test_init_wrong_struct_size);
        suite.add("init_missing_mandatory_slot", test_init_missing_mandatory_slot);
        suite.add("init_valid_adapter_succeeds", test_init_valid_adapter_succeeds);
        suite.add("error_message_known", test_error_message_known);
        suite.add("error_message_unknown", test_error_message_unknown);
        suite.add("error_classification", test_error_classification);
        suite.add("error_details", test_error_details);
        suite.add("logger_levels", test_logger_levels);
        suite.add("logger_no_crash", test_logger_no_crash);
        suite.add("alloc_free", test_alloc_free);
        suite.add("audio_float32_to_wav", test_audio_float32_to_wav);
        suite.add("audio_int16_to_wav", test_audio_int16_to_wav);

        return suite.run(argc, argv);
    } catch (const std::exception& e) {
        std::fprintf(stderr, "FATAL: %s\n", e.what());
        return 1;
    } catch (...) {
        return 1;
    }
}
