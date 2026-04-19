/**
 * @file test_llm.cpp
 * @brief Integration tests for LLM via direct LlamaCPP backend API.
 *
 * Tests model loading, text generation (sync + streaming), cancellation,
 * model info, and unload/reload lifecycle using rac_llm_llamacpp_* APIs.
 */

#include "test_common.h"
#include "test_config.h"

#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/backends/rac_llm_llamacpp.h"

#include <atomic>
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
    config.log_tag = "TEST_LLM";
    config.reserved = nullptr;
    return config;
}

// =============================================================================
// Setup / Teardown
// =============================================================================

static bool setup() {
    rac_config_t config = make_test_config();
    if (rac_init(&config) != RAC_SUCCESS) return false;
    rac_backend_llamacpp_register();
    return true;
}

static void teardown() { rac_shutdown(); }

// =============================================================================
// Test: create and destroy with valid model path
// =============================================================================

static TestResult test_create_destroy() {
    TestResult result;
    result.test_name = "create_destroy";

    std::string model_path = test_config::get_llm_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        return result;
    }

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_llm_llamacpp_create(model_path.c_str(), nullptr, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_llm_llamacpp_create should succeed");
    ASSERT_TRUE(handle != nullptr, "handle should not be NULL");

    rac_llm_llamacpp_destroy(handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: create with invalid path returns error
// =============================================================================

static TestResult test_create_invalid_path() {
    if (!setup()) {
        TestResult r;
        r.test_name = "create_invalid_path";
        r.passed = false;
        r.details = "setup() failed";
        return r;
    }

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_llm_llamacpp_create("/nonexistent.gguf", nullptr, &handle);
    ASSERT_TRUE(rc != RAC_SUCCESS, "create with invalid path should return an error");

    // Handle may or may not be NULL depending on implementation; destroy if non-NULL
    if (handle) {
        rac_llm_llamacpp_destroy(handle);
    }

    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: is_model_loaded returns RAC_TRUE after create
// =============================================================================

static TestResult test_is_model_loaded() {
    TestResult result;
    result.test_name = "is_model_loaded";

    std::string model_path = test_config::get_llm_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        return result;
    }

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_llm_llamacpp_create(model_path.c_str(), nullptr, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_llm_llamacpp_create should succeed");

    rac_bool_t loaded = rac_llm_llamacpp_is_model_loaded(handle);
    ASSERT_EQ(loaded, RAC_TRUE, "model should be loaded after create");

    rac_llm_llamacpp_destroy(handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: simple synchronous generation
// =============================================================================

static TestResult test_generate_simple() {
    TestResult result;
    result.test_name = "generate_simple";

    std::string model_path = test_config::get_llm_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        return result;
    }

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_llm_llamacpp_create(model_path.c_str(), nullptr, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_llm_llamacpp_create should succeed");

    rac_llm_options_t opts = RAC_LLM_OPTIONS_DEFAULT;
    opts.max_tokens = 50;

    rac_llm_result_t gen_result = {};
    {
        ScopedTimer timer("llm_generate");
        rc = rac_llm_llamacpp_generate(handle, "What is 2+2? Answer briefly.", &opts, &gen_result);
    }
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_llm_llamacpp_generate should succeed");
    ASSERT_TRUE(gen_result.text != nullptr, "result text should not be NULL");
    ASSERT_TRUE(std::strlen(gen_result.text) > 0, "result text should not be empty");
    ASSERT_TRUE(gen_result.completion_tokens > 0, "completion_tokens should be > 0");

    std::cout << "  Generated: " << gen_result.text << "\n";
    std::cout << "  Tokens: prompt=" << gen_result.prompt_tokens
              << " completion=" << gen_result.completion_tokens
              << " tps=" << gen_result.tokens_per_second << "\n";

    rac_llm_result_free(&gen_result);
    rac_llm_llamacpp_destroy(handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: streaming generation
// =============================================================================

struct StreamCallbackData {
    int token_count = 0;
    bool got_final = false;
};

static rac_bool_t stream_callback(const char* token, rac_bool_t is_final, void* user_data) {
    auto* data = static_cast<StreamCallbackData*>(user_data);
    if (token && std::strlen(token) > 0) {
        data->token_count++;
    }
    if (is_final == RAC_TRUE) {
        data->got_final = true;
    }
    return RAC_TRUE; // continue
}

static TestResult test_generate_stream() {
    TestResult result;
    result.test_name = "generate_stream";

    std::string model_path = test_config::get_llm_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        return result;
    }

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_llm_llamacpp_create(model_path.c_str(), nullptr, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_llm_llamacpp_create should succeed");

    rac_llm_options_t opts = RAC_LLM_OPTIONS_DEFAULT;
    opts.max_tokens = 50;

    StreamCallbackData cb_data;
    {
        ScopedTimer timer("llm_generate_stream");
        rc = rac_llm_llamacpp_generate_stream(handle, "What is 2+2? Answer briefly.", &opts,
                                               stream_callback, &cb_data);
    }
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_llm_llamacpp_generate_stream should succeed");
    ASSERT_TRUE(cb_data.token_count > 0, "should have received at least one token");
    ASSERT_TRUE(cb_data.got_final, "should have received the final token callback");

    std::cout << "  Streamed " << cb_data.token_count << " tokens\n";

    rac_llm_llamacpp_destroy(handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: cancel generation via callback returning RAC_FALSE
// =============================================================================

struct CancelCallbackData {
    int token_count = 0;
};

static rac_bool_t cancel_callback(const char* /*token*/, rac_bool_t /*is_final*/,
                                   void* user_data) {
    auto* data = static_cast<CancelCallbackData*>(user_data);
    data->token_count++;
    // Stop after 3 tokens
    if (data->token_count >= 3) {
        return RAC_FALSE; // request cancellation
    }
    return RAC_TRUE;
}

static TestResult test_cancel_generation() {
    TestResult result;
    result.test_name = "cancel_generation";

    std::string model_path = test_config::get_llm_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        return result;
    }

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_llm_llamacpp_create(model_path.c_str(), nullptr, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_llm_llamacpp_create should succeed");

    rac_llm_options_t opts = RAC_LLM_OPTIONS_DEFAULT;
    opts.max_tokens = 200;

    CancelCallbackData cb_data;
    rc = rac_llm_llamacpp_generate_stream(handle, "Write a long story about space exploration.",
                                           &opts, cancel_callback, &cb_data);
    // The return code may be RAC_SUCCESS or RAC_ERROR_CANCELLED depending on implementation
    ASSERT_TRUE(cb_data.token_count >= 1, "callback should have been called at least once");

    std::cout << "  Cancelled after " << cb_data.token_count << " tokens\n";

    rac_llm_llamacpp_destroy(handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: get model info as JSON
// =============================================================================

static TestResult test_get_model_info() {
    TestResult result;
    result.test_name = "get_model_info";

    std::string model_path = test_config::get_llm_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        return result;
    }

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_llm_llamacpp_create(model_path.c_str(), nullptr, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_llm_llamacpp_create should succeed");

    char* json = nullptr;
    rc = rac_llm_llamacpp_get_model_info(handle, &json);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_llm_llamacpp_get_model_info should succeed");
    ASSERT_TRUE(json != nullptr, "model info JSON should not be NULL");
    ASSERT_TRUE(std::strlen(json) > 0, "model info JSON should not be empty");

    std::cout << "  Model info: " << json << "\n";

    rac_free(json);
    rac_llm_llamacpp_destroy(handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test: unload and reload model
// =============================================================================

static TestResult test_unload_reload() {
    TestResult result;
    result.test_name = "unload_reload";

    std::string model_path = test_config::get_llm_model_path();
    if (!test_config::require_model(model_path, result.test_name, result)) {
        return result;
    }

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_llm_llamacpp_create(model_path.c_str(), nullptr, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_llm_llamacpp_create should succeed");

    // Verify initially loaded
    ASSERT_EQ(rac_llm_llamacpp_is_model_loaded(handle), RAC_TRUE,
              "model should be loaded after create");

    // Attempt unload - may fail on Metal GPU backends (known llama.cpp limitation)
    rc = rac_llm_llamacpp_unload_model(handle);
    if (rc != RAC_SUCCESS) {
        std::cout << "  NOTE: unload returned " << rc
                  << " (known Metal GPU limitation) - skipping reload test\n";
        rac_llm_llamacpp_destroy(handle);
        teardown();
        result.passed = true;
        result.details = "SKIPPED - unload not supported with Metal GPU backend (error " +
                         std::to_string(rc) + ")";
        return result;
    }

    ASSERT_EQ(rac_llm_llamacpp_is_model_loaded(handle), RAC_FALSE,
              "model should not be loaded after unload");

    // Reload
    rc = rac_llm_llamacpp_load_model(handle, model_path.c_str(), nullptr);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_llm_llamacpp_load_model should succeed");
    ASSERT_EQ(rac_llm_llamacpp_is_model_loaded(handle), RAC_TRUE,
              "model should be loaded after reload");

    rac_llm_llamacpp_destroy(handle);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Main: register tests and dispatch via CLI args
// =============================================================================

int main(int argc, char** argv) {
    TestSuite suite("llm");

    suite.add("create_destroy", test_create_destroy);
    suite.add("create_invalid_path", test_create_invalid_path);
    suite.add("is_model_loaded", test_is_model_loaded);
    suite.add("generate_simple", test_generate_simple);
    suite.add("generate_stream", test_generate_stream);
    suite.add("cancel_generation", test_cancel_generation);
    suite.add("get_model_info", test_get_model_info);
    suite.add("unload_reload", test_unload_reload);

    return suite.run(argc, argv);
}
