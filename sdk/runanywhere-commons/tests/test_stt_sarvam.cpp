/**
 * @file test_stt_sarvam.cpp
 * @brief Tests for Sarvam AI STT backend.
 *
 * Unit tests for internal utilities (WAV encoding, multipart encoding, JSON parsing).
 * Integration tests require SARVAM_API_KEY env var and a registered HTTP executor.
 */

#include "test_common.h"

#include "rac/backends/rac_stt_sarvam.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/network/rac_http_client.h"

// Access internal utilities for unit testing
#include "rac_stt_sarvam.h"

#include <cmath>
#include <cstring>
#include <condition_variable>
#include <mutex>

// Minimal platform adapter for tests
static void test_log(rac_log_level_t level, const char* category, const char* message,
                     void* /*user_data*/) {
    const char* lvl = "?";
    switch (level) {
        case RAC_LOG_TRACE: lvl = "TRACE"; break;
        case RAC_LOG_DEBUG: lvl = "DEBUG"; break;
        case RAC_LOG_INFO: lvl = "INFO"; break;
        case RAC_LOG_WARNING: lvl = "WARN"; break;
        case RAC_LOG_ERROR: lvl = "ERROR"; break;
        case RAC_LOG_FATAL: lvl = "FATAL"; break;
    }
    printf("[%s] %s: %s\n", lvl, category ? category : "", message ? message : "");
}

static rac_bool_t test_file_exists(const char*, void*) { return RAC_FALSE; }
static rac_result_t test_file_read(const char*, void**, size_t*, void*) { return RAC_ERROR_NOT_SUPPORTED; }
static rac_result_t test_file_write(const char*, const void*, size_t, void*) { return RAC_ERROR_NOT_SUPPORTED; }
static rac_result_t test_file_delete(const char*, void*) { return RAC_ERROR_NOT_SUPPORTED; }
static rac_result_t test_secure_get(const char*, char**, void*) { return RAC_ERROR_NOT_SUPPORTED; }
static rac_result_t test_secure_set(const char*, const char*, void*) { return RAC_ERROR_NOT_SUPPORTED; }
static rac_result_t test_secure_delete(const char*, void*) { return RAC_ERROR_NOT_SUPPORTED; }

static int64_t test_now_ms(void*) {
    return static_cast<int64_t>(std::time(nullptr)) * 1000;
}

static rac_result_t test_get_memory_info(rac_memory_info_t* out_info, void*) {
    if (out_info) {
        out_info->total_bytes = 8ULL * 1024 * 1024 * 1024;
        out_info->available_bytes = 4ULL * 1024 * 1024 * 1024;
        out_info->used_bytes = 4ULL * 1024 * 1024 * 1024;
    }
    return RAC_SUCCESS;
}

static void init_platform() {
    if (rac_is_initialized()) return;

    static rac_platform_adapter_t adapter = {};
    adapter.file_exists = test_file_exists;
    adapter.file_read = test_file_read;
    adapter.file_write = test_file_write;
    adapter.file_delete = test_file_delete;
    adapter.secure_get = test_secure_get;
    adapter.secure_set = test_secure_set;
    adapter.secure_delete = test_secure_delete;
    adapter.log = test_log;
    adapter.now_ms = test_now_ms;
    adapter.get_memory_info = test_get_memory_info;

    rac_config_t config = {};
    config.platform_adapter = &adapter;
    config.log_level = RAC_LOG_DEBUG;
    rac_init(&config);
}

// Generate PCM Int16 sine wave for testing
static std::vector<int16_t> generate_pcm_sine(float freq_hz, float duration_sec,
                                               int sample_rate = 16000) {
    size_t n = static_cast<size_t>(duration_sec * sample_rate);
    std::vector<int16_t> pcm(n);
    const float two_pi = 2.0f * static_cast<float>(M_PI);
    for (size_t i = 0; i < n; ++i) {
        float t = static_cast<float>(i) / static_cast<float>(sample_rate);
        pcm[i] = static_cast<int16_t>(0.5f * 32767.0f * std::sin(two_pi * freq_hz * t));
    }
    return pcm;
}

// =============================================================================
// Unit Tests
// =============================================================================

TestResult test_wav_encoding() {
    TestResult r;
    r.test_name = "wav_encoding";

    // 1 second of silence
    std::vector<int16_t> pcm(16000, 0);
    auto wav = rac::sarvam::encode_wav(pcm.data(), pcm.size() * sizeof(int16_t), 16000, 1, 16);

    // WAV header is 44 bytes
    ASSERT_TRUE(wav.size() == 44 + pcm.size() * sizeof(int16_t), "WAV size mismatch");

    // Check RIFF header
    ASSERT_TRUE(std::memcmp(wav.data(), "RIFF", 4) == 0, "Missing RIFF header");
    ASSERT_TRUE(std::memcmp(wav.data() + 8, "WAVE", 4) == 0, "Missing WAVE marker");
    ASSERT_TRUE(std::memcmp(wav.data() + 12, "fmt ", 4) == 0, "Missing fmt chunk");
    ASSERT_TRUE(std::memcmp(wav.data() + 36, "data", 4) == 0, "Missing data chunk");

    // Check format: PCM, mono, 16kHz, 16-bit
    uint16_t audio_fmt = 0;
    std::memcpy(&audio_fmt, wav.data() + 20, 2);
    ASSERT_EQ(audio_fmt, (uint16_t)1, "Audio format should be PCM (1)");

    uint16_t channels = 0;
    std::memcpy(&channels, wav.data() + 22, 2);
    ASSERT_EQ(channels, (uint16_t)1, "Should be mono");

    int32_t sample_rate = 0;
    std::memcpy(&sample_rate, wav.data() + 24, 4);
    ASSERT_EQ(sample_rate, 16000, "Sample rate should be 16000");

    uint16_t bits = 0;
    std::memcpy(&bits, wav.data() + 34, 2);
    ASSERT_EQ(bits, (uint16_t)16, "Bits per sample should be 16");

    // Check data size
    uint32_t data_size = 0;
    std::memcpy(&data_size, wav.data() + 40, 4);
    ASSERT_EQ(data_size, (uint32_t)(pcm.size() * sizeof(int16_t)), "Data size mismatch");

    return TEST_PASS();
}

TestResult test_multipart_encoding() {
    TestResult r;
    r.test_name = "multipart_encoding";

    std::vector<rac::sarvam::multipart_field> fields;

    // Text field
    rac::sarvam::multipart_field text_field;
    text_field.name = "language_code";
    text_field.value = "en-IN";
    fields.push_back(std::move(text_field));

    // Binary field
    rac::sarvam::multipart_field file_field;
    file_field.name = "file";
    file_field.filename = "audio.wav";
    file_field.content_type = "audio/wav";
    file_field.binary_data = {0x01, 0x02, 0x03, 0x04};
    fields.push_back(std::move(file_field));

    auto result = rac::sarvam::encode_multipart(fields);

    // Content-Type should contain boundary
    ASSERT_TRUE(result.content_type.find("multipart/form-data; boundary=") == 0,
                "Content-Type should start with multipart/form-data; boundary=");

    // Body should contain field names
    std::string body_str(result.body.begin(), result.body.end());
    ASSERT_TRUE(body_str.find("language_code") != std::string::npos,
                "Body should contain language_code field");
    ASSERT_TRUE(body_str.find("en-IN") != std::string::npos,
                "Body should contain language_code value");
    ASSERT_TRUE(body_str.find("audio.wav") != std::string::npos,
                "Body should contain filename");
    ASSERT_TRUE(body_str.find("audio/wav") != std::string::npos,
                "Body should contain content type");

    // Body should end with closing boundary
    std::string closing = "--";
    ASSERT_TRUE(body_str.find("--\r\n") != std::string::npos,
                "Body should end with closing boundary");

    return TEST_PASS();
}

TestResult test_multipart_empty_fields() {
    TestResult r;
    r.test_name = "multipart_empty_fields";

    std::vector<rac::sarvam::multipart_field> fields;
    auto result = rac::sarvam::encode_multipart(fields);

    // Should still produce valid multipart with just closing boundary
    ASSERT_TRUE(!result.body.empty(), "Body should not be empty");
    ASSERT_TRUE(!result.content_type.empty(), "Content-Type should not be empty");

    return TEST_PASS();
}

TestResult test_model_string() {
    TestResult r;
    r.test_name = "model_string";

    ASSERT_TRUE(std::strcmp(rac::sarvam::model_string(RAC_STT_SARVAM_MODEL_SAARIKA_V1), "saarika:v1") == 0,
                "V1 model string mismatch");
    ASSERT_TRUE(std::strcmp(rac::sarvam::model_string(RAC_STT_SARVAM_MODEL_SAARIKA_V2), "saarika:v2") == 0,
                "V2 model string mismatch");
    ASSERT_TRUE(std::strcmp(rac::sarvam::model_string(RAC_STT_SARVAM_MODEL_SAARIKA_V2_5), "saarika:v2.5") == 0,
                "V2.5 model string mismatch");

    return TEST_PASS();
}

TestResult test_api_key_management() {
    TestResult r;
    r.test_name = "api_key_management";

    // Initially no key
    // (Note: previous tests may have set a key, so we clear it first)
    {
        std::lock_guard<std::mutex> lock(rac::sarvam::global_api_key_mutex());
        rac::sarvam::global_api_key().clear();
    }

    ASSERT_TRUE(rac_stt_sarvam_get_api_key() == nullptr, "Key should be null initially");

    // Set key
    rac_result_t result = rac_stt_sarvam_set_api_key("test-key-123");
    ASSERT_EQ(result, RAC_SUCCESS, "Setting API key should succeed");

    const char* key = rac_stt_sarvam_get_api_key();
    ASSERT_TRUE(key != nullptr, "Key should not be null after setting");
    ASSERT_TRUE(std::strcmp(key, "test-key-123") == 0, "Key value mismatch");

    // Empty key should fail
    result = rac_stt_sarvam_set_api_key("");
    ASSERT_TRUE(result != RAC_SUCCESS, "Empty key should fail");

    // Null key should fail
    result = rac_stt_sarvam_set_api_key(nullptr);
    ASSERT_TRUE(result != RAC_SUCCESS, "Null key should fail");

    return TEST_PASS();
}

TestResult test_create_without_api_key() {
    TestResult r;
    r.test_name = "create_without_api_key";

    // Clear API key
    {
        std::lock_guard<std::mutex> lock(rac::sarvam::global_api_key_mutex());
        rac::sarvam::global_api_key().clear();
    }

    rac_handle_t handle = nullptr;
    rac_result_t result = rac_stt_sarvam_create(nullptr, &handle);
    ASSERT_TRUE(result != RAC_SUCCESS, "Create should fail without API key");
    ASSERT_TRUE(handle == nullptr, "Handle should be null on failure");

    return TEST_PASS();
}

TestResult test_create_without_http_executor() {
    TestResult r;
    r.test_name = "create_without_http_executor";

    // Set API key but don't register HTTP executor
    rac_stt_sarvam_set_api_key("test-key");

    // If no HTTP executor is registered, create should fail
    if (!rac_http_has_executor()) {
        rac_handle_t handle = nullptr;
        rac_result_t result = rac_stt_sarvam_create(nullptr, &handle);
        ASSERT_TRUE(result != RAC_SUCCESS, "Create should fail without HTTP executor");
    }

    return TEST_PASS();
}

TestResult test_transcribe_null_args() {
    TestResult r;
    r.test_name = "transcribe_null_args";

    // Null handle
    rac_stt_result_t result = {};
    int16_t dummy = 0;
    rac_result_t rc = rac_stt_sarvam_transcribe(nullptr, &dummy, 2, nullptr, &result);
    ASSERT_TRUE(rc != RAC_SUCCESS, "Null handle should fail");

    // Null audio
    rc = rac_stt_sarvam_transcribe((rac_handle_t)0x1, nullptr, 0, nullptr, &result);
    ASSERT_TRUE(rc != RAC_SUCCESS, "Null audio should fail");

    // Null result
    rc = rac_stt_sarvam_transcribe((rac_handle_t)0x1, &dummy, 2, nullptr, nullptr);
    ASSERT_TRUE(rc != RAC_SUCCESS, "Null result should fail");

    return TEST_PASS();
}

TestResult test_backend_registration() {
    TestResult r;
    r.test_name = "backend_registration";

    init_platform();

    rac_result_t rc = rac_backend_sarvam_register();
    ASSERT_EQ(rc, RAC_SUCCESS, "Registration should succeed");

    // Double registration should return already registered
    rc = rac_backend_sarvam_register();
    ASSERT_EQ(rc, RAC_ERROR_MODULE_ALREADY_REGISTERED, "Double registration should return error");

    // Module should be discoverable
    const rac_module_info_t* modules = nullptr;
    size_t count = 0;
    rc = rac_modules_for_capability(RAC_CAPABILITY_STT, &modules, &count);
    ASSERT_EQ(rc, RAC_SUCCESS, "Module query should succeed");

    bool found = false;
    for (size_t i = 0; i < count; ++i) {
        if (modules[i].id && std::strcmp(modules[i].id, "sarvam") == 0) {
            found = true;
            break;
        }
    }
    ASSERT_TRUE(found, "Sarvam module should be listed for STT capability");

    // Unregister
    rc = rac_backend_sarvam_unregister();
    ASSERT_EQ(rc, RAC_SUCCESS, "Unregistration should succeed");

    return TEST_PASS();
}

TestResult test_wav_encoding_various_sizes() {
    TestResult r;
    r.test_name = "wav_encoding_various_sizes";

    // Test different audio durations
    size_t sizes[] = {0, 160, 1600, 16000, 32000};

    for (size_t pcm_samples : sizes) {
        std::vector<int16_t> pcm(pcm_samples, 0);
        size_t pcm_bytes = pcm.size() * sizeof(int16_t);
        auto wav = rac::sarvam::encode_wav(pcm.data(), pcm_bytes, 16000, 1, 16);

        ASSERT_EQ(wav.size(), 44 + pcm_bytes,
                  "WAV size mismatch for " + std::to_string(pcm_samples) + " samples");
    }

    return TEST_PASS();
}

TestResult test_multipart_binary_integrity() {
    TestResult r;
    r.test_name = "multipart_binary_integrity";

    // Create binary data with all byte values 0-255
    std::vector<uint8_t> binary(256);
    for (int i = 0; i < 256; ++i) binary[i] = static_cast<uint8_t>(i);

    std::vector<rac::sarvam::multipart_field> fields;
    rac::sarvam::multipart_field f;
    f.name = "file";
    f.filename = "test.bin";
    f.content_type = "application/octet-stream";
    f.binary_data = binary;
    fields.push_back(std::move(f));

    auto result = rac::sarvam::encode_multipart(fields);

    // The binary data should appear intact in the body
    // Find the binary data after the headers
    std::string body_str(result.body.begin(), result.body.end());
    std::string header_end = "\r\n\r\n";
    auto pos = body_str.find(header_end);
    ASSERT_TRUE(pos != std::string::npos, "Should find header end");

    // After header, binary data should be present
    size_t data_start = pos + header_end.size();
    ASSERT_TRUE(data_start + 256 <= result.body.size(), "Body should contain all binary data");

    for (int i = 0; i < 256; ++i) {
        ASSERT_EQ(result.body[data_start + i], (uint8_t)i,
                  "Binary byte " + std::to_string(i) + " corrupted");
    }

    return TEST_PASS();
}

// =============================================================================
// Integration test (requires SARVAM_API_KEY env var + HTTP executor)
// =============================================================================

// Mock HTTP executor for testing without real network
static struct {
    std::string last_url;
    std::string last_content_type;
    std::vector<uint8_t> last_body;
    std::string mock_response;
    int mock_status = 200;
} g_mock_http;

static void mock_http_executor(const rac_http_request_t* request, rac_http_callback_t callback,
                                void* user_data) {
    // Capture request
    if (request->url) g_mock_http.last_url = request->url;
    for (size_t i = 0; i < request->header_count; ++i) {
        if (request->headers[i].key && std::strcmp(request->headers[i].key, "Content-Type") == 0) {
            g_mock_http.last_content_type = request->headers[i].value;
        }
    }
    if (request->body && request->body_length > 0) {
        g_mock_http.last_body.assign(
            reinterpret_cast<const uint8_t*>(request->body),
            reinterpret_cast<const uint8_t*>(request->body) + request->body_length);
    }

    // Return mock response
    rac_http_response_t response = {};
    response.status_code = g_mock_http.mock_status;
    if (g_mock_http.mock_status == 200) {
        response.body = strdup(g_mock_http.mock_response.c_str());
        response.body_length = g_mock_http.mock_response.size();
    } else {
        response.error_message = strdup("Mock error");
    }

    callback(&response, user_data);

    free(response.body);
    free(response.error_message);
}

TestResult test_transcribe_with_mock_http() {
    TestResult r;
    r.test_name = "transcribe_with_mock_http";

    init_platform();

    // Register mock HTTP executor
    rac_http_set_executor(mock_http_executor);

    // Set mock response
    g_mock_http.mock_response = R"({"transcript":"hello world","language_code":"en-IN"})";
    g_mock_http.mock_status = 200;

    // Set API key and create service
    rac_stt_sarvam_set_api_key("test-key-for-mock");

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_stt_sarvam_create(nullptr, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "Create should succeed");

    // Generate 1 second of audio
    auto pcm = generate_pcm_sine(440.0f, 1.0f);
    rac_stt_result_t result = {};
    rc = rac_stt_sarvam_transcribe(handle, pcm.data(), pcm.size() * sizeof(int16_t),
                                    nullptr, &result);
    ASSERT_EQ(rc, RAC_SUCCESS, "Transcribe should succeed");
    ASSERT_TRUE(result.text != nullptr, "Result text should not be null");
    ASSERT_TRUE(std::strcmp(result.text, "hello world") == 0, "Transcript mismatch");
    ASSERT_TRUE(result.detected_language != nullptr, "Language should be detected");
    ASSERT_TRUE(std::strcmp(result.detected_language, "en-IN") == 0, "Language mismatch");

    // Verify the request was sent correctly
    ASSERT_TRUE(g_mock_http.last_url == "https://api.sarvam.ai/speech-to-text",
                "URL mismatch");
    ASSERT_TRUE(g_mock_http.last_content_type.find("multipart/form-data") != std::string::npos,
                "Content-Type should be multipart");

    // Verify body contains WAV data (starts with RIFF after multipart headers)
    std::string body_str(g_mock_http.last_body.begin(), g_mock_http.last_body.end());
    ASSERT_TRUE(body_str.find("RIFF") != std::string::npos, "Body should contain WAV data");
    ASSERT_TRUE(body_str.find("saarika:v2.5") != std::string::npos, "Body should contain model");
    ASSERT_TRUE(body_str.find("en-IN") != std::string::npos, "Body should contain language");

    rac_stt_result_free(&result);
    rac_stt_sarvam_destroy(handle);

    return TEST_PASS();
}

TestResult test_transcribe_api_error() {
    TestResult r;
    r.test_name = "transcribe_api_error";

    init_platform();
    rac_http_set_executor(mock_http_executor);

    g_mock_http.mock_status = 401;
    g_mock_http.mock_response = "";

    rac_stt_sarvam_set_api_key("bad-key");

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_stt_sarvam_create(nullptr, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "Create should succeed");

    auto pcm = generate_pcm_sine(440.0f, 0.5f);
    rac_stt_result_t result = {};
    rc = rac_stt_sarvam_transcribe(handle, pcm.data(), pcm.size() * sizeof(int16_t),
                                    nullptr, &result);
    ASSERT_TRUE(rc != RAC_SUCCESS, "Transcribe should fail with 401");

    rac_stt_sarvam_destroy(handle);

    return TEST_PASS();
}

TestResult test_transcribe_audio_too_long() {
    TestResult r;
    r.test_name = "transcribe_audio_too_long";

    init_platform();
    rac_http_set_executor(mock_http_executor);
    rac_stt_sarvam_set_api_key("test-key");

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_stt_sarvam_create(nullptr, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "Create should succeed");

    // 3 minutes of audio (exceeds 2 min limit)
    auto pcm = generate_pcm_sine(440.0f, 180.0f);
    rac_stt_result_t result = {};
    rc = rac_stt_sarvam_transcribe(handle, pcm.data(), pcm.size() * sizeof(int16_t),
                                    nullptr, &result);
    ASSERT_TRUE(rc != RAC_SUCCESS, "Should fail for audio exceeding 2 minutes");

    rac_stt_sarvam_destroy(handle);

    return TEST_PASS();
}

// =============================================================================
// Real API integration test (requires SARVAM_API_KEY env + libcurl)
// =============================================================================

#ifdef RAC_TEST_HAS_CURL
#include <curl/curl.h>

// Simple curl-based HTTP executor for real API testing
static size_t curl_write_cb(void* data, size_t size, size_t nmemb, void* userp) {
    auto* buf = static_cast<std::string*>(userp);
    buf->append(static_cast<char*>(data), size * nmemb);
    return size * nmemb;
}

static void curl_http_executor(const rac_http_request_t* request, rac_http_callback_t callback,
                                void* user_data) {
    CURL* curl = curl_easy_init();
    if (!curl) {
        rac_http_response_t resp = {};
        resp.status_code = 0;
        resp.error_message = strdup("Failed to init curl");
        callback(&resp, user_data);
        free(resp.error_message);
        return;
    }

    std::string response_body;
    curl_easy_setopt(curl, CURLOPT_URL, request->url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_write_cb);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response_body);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, (long)request->timeout_ms);

    // Set headers
    struct curl_slist* headers = nullptr;
    for (size_t i = 0; i < request->header_count; ++i) {
        std::string h = std::string(request->headers[i].key) + ": " + request->headers[i].value;
        headers = curl_slist_append(headers, h.c_str());
    }
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    // POST with binary body
    if (request->method == RAC_HTTP_POST && request->body && request->body_length > 0) {
        curl_easy_setopt(curl, CURLOPT_POST, 1L);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, request->body);
        curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)request->body_length);
    }

    CURLcode res = curl_easy_perform(curl);

    rac_http_response_t resp = {};
    if (res == CURLE_OK) {
        long http_code = 0;
        curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
        resp.status_code = (int32_t)http_code;
        resp.body = strdup(response_body.c_str());
        resp.body_length = response_body.size();
    } else {
        resp.status_code = 0;
        resp.error_message = strdup(curl_easy_strerror(res));
    }

    callback(&resp, user_data);

    free(resp.body);
    free(resp.error_message);
    curl_slist_free_all(headers);
    curl_easy_cleanup(curl);
}

TestResult test_real_api_transcribe() {
    TestResult r;
    r.test_name = "real_api_transcribe";

    const char* api_key = std::getenv("SARVAM_API_KEY");
    const char* audio_path = std::getenv("SARVAM_TEST_AUDIO");

    if (!api_key || !audio_path) {
        r.passed = true;
        r.details = "Skipped (set SARVAM_API_KEY and SARVAM_TEST_AUDIO env vars)";
        return r;
    }

    init_platform();

    // Register real curl executor
    curl_global_init(CURL_GLOBAL_DEFAULT);
    rac_http_set_executor(curl_http_executor);

    rac_stt_sarvam_set_api_key(api_key);

    // Read raw PCM file
    std::ifstream file(audio_path, std::ios::binary | std::ios::ate);
    ASSERT_TRUE(file.is_open(), "Failed to open audio file");

    size_t file_size = file.tellg();
    file.seekg(0);
    std::vector<uint8_t> pcm_data(file_size);
    file.read(reinterpret_cast<char*>(pcm_data.data()), file_size);
    file.close();

    ASSERT_TRUE(file_size > 0, "Audio file is empty");

    printf("Audio file: %s (%zu bytes, ~%.1fs)\n", audio_path, file_size,
           (float)file_size / (16000.0f * 2));

    // Create service with Hindi-IN language (adjust as needed)
    rac_stt_sarvam_config_t config = RAC_STT_SARVAM_CONFIG_DEFAULT;
    config.language_code = "hi-IN";
    config.timeout_ms = 30000;

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_stt_sarvam_create(&config, &handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "Create should succeed");

    // Transcribe
    rac_stt_result_t result = {};
    rc = rac_stt_sarvam_transcribe(handle, pcm_data.data(), pcm_data.size(), nullptr, &result);

    printf("Result code: %d\n", rc);
    if (rc == RAC_SUCCESS && result.text) {
        printf("Transcript: %s\n", result.text);
        printf("Language: %s\n", result.detected_language ? result.detected_language : "N/A");
        printf("Processing time: %lld ms\n", (long long)result.processing_time_ms);
    }

    ASSERT_EQ(rc, RAC_SUCCESS, "Transcribe should succeed");
    ASSERT_TRUE(result.text != nullptr, "Result text should not be null");
    ASSERT_TRUE(strlen(result.text) > 0, "Transcript should not be empty");

    rac_stt_result_free(&result);
    rac_stt_sarvam_destroy(handle);
    curl_global_cleanup();

    return TEST_PASS();
}
#endif // RAC_TEST_HAS_CURL

// =============================================================================
// Main
// =============================================================================

int main(int argc, char** argv) {
    TestSuite suite("sarvam_stt");

    // Unit tests (no network needed)
    suite.add("wav_encoding", test_wav_encoding);
    suite.add("wav_encoding_various_sizes", test_wav_encoding_various_sizes);
    suite.add("multipart_encoding", test_multipart_encoding);
    suite.add("multipart_empty_fields", test_multipart_empty_fields);
    suite.add("multipart_binary_integrity", test_multipart_binary_integrity);
    suite.add("model_string", test_model_string);
    suite.add("api_key_management", test_api_key_management);
    suite.add("create_without_api_key", test_create_without_api_key);
    suite.add("create_without_http_executor", test_create_without_http_executor);
    suite.add("transcribe_null_args", test_transcribe_null_args);
    suite.add("backend_registration", test_backend_registration);

    // Integration tests (mock HTTP)
    suite.add("transcribe_with_mock_http", test_transcribe_with_mock_http);
    suite.add("transcribe_api_error", test_transcribe_api_error);
    suite.add("transcribe_audio_too_long", test_transcribe_audio_too_long);

#ifdef RAC_TEST_HAS_CURL
    // Real API test (requires env vars)
    suite.add("real_api_transcribe", test_real_api_transcribe);
#endif

    return suite.run(argc, argv);
}
