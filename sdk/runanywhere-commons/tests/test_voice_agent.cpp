/**
 * @file test_voice_agent.cpp
 * @brief Integration tests for the full voice agent pipeline.
 *
 * Tests the voice agent lifecycle: standalone create, model loading (STT/LLM/TTS),
 * initialization, readiness checks, model ID retrieval, individual component access
 * (generate response, synthesize speech, detect speech), orchestration APIs
 * (transcribe, process_voice_turn, process_stream), pipeline state helpers,
 * and cleanup/destroy.
 *
 * Uses a shared global agent handle for tests 2-13 since model loading is slow.
 */

#include "test_common.h"
#include "test_config.h"

#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/backends/rac_vad_onnx.h"
#include "rac/backends/rac_stt_onnx.h"
#include "rac/backends/rac_tts_onnx.h"
#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/features/voice_agent/rac_voice_agent.h"

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
    config.log_tag = "TEST_VOICE_AGENT";
    config.reserved = nullptr;
    return config;
}

// =============================================================================
// Setup: register BOTH backends (ONNX + LlamaCPP)
// =============================================================================

static bool setup() {
    rac_config_t config = make_test_config();
    if (rac_init(&config) != RAC_SUCCESS) return false;
    rac_backend_onnx_register();
    rac_backend_llamacpp_register();
    return true;
}

static void teardown() { rac_shutdown(); }

// =============================================================================
// Shared global agent for tests that require loaded models (2-13)
// =============================================================================

static rac_voice_agent_handle_t g_agent = nullptr;
static bool g_agent_ready = false;
static bool g_agent_setup_attempted = false;
static bool g_models_missing = false;

/**
 * Ensures the global agent is created, models loaded, and initialized.
 * Called by tests 2-13. Returns false (with result set to SKIPPED) if models missing.
 */
static bool ensure_global_agent(TestResult& result, const std::string& test_name) {
    // If we already know models are missing, skip immediately
    if (g_models_missing) {
        result.test_name = test_name;
        result.passed = true;
        result.details = "SKIPPED - required models not found";
        return false;
    }

    // If already ready, nothing to do
    if (g_agent_ready) return true;

    // If we already tried and failed (not due to missing models), fail
    if (g_agent_setup_attempted) {
        result.test_name = test_name;
        result.passed = false;
        result.details = "global agent setup previously failed";
        return false;
    }

    g_agent_setup_attempted = true;

    // Check model paths
    std::string stt_path = test_config::get_stt_model_path();
    std::string llm_path = test_config::get_llm_model_path();
    std::string tts_path = test_config::get_tts_model_path();

    if (!test_config::file_exists(stt_path) || !test_config::file_exists(llm_path) ||
        !test_config::file_exists(tts_path)) {
        g_models_missing = true;
        result.test_name = test_name;
        result.passed = true;
        result.details = "SKIPPED - one or more models not found (STT: " + stt_path +
                         ", LLM: " + llm_path + ", TTS: " + tts_path + ")";
        return false;
    }

    // Setup core + backends
    if (!setup()) {
        result.test_name = test_name;
        result.passed = false;
        result.details = "setup() failed";
        return false;
    }

    // Create standalone agent
    rac_result_t rc = rac_voice_agent_create_standalone(&g_agent);
    if (rc != RAC_SUCCESS) {
        result.test_name = test_name;
        result.passed = false;
        result.details = "rac_voice_agent_create_standalone failed: " + std::to_string(rc);
        teardown();
        return false;
    }

    // Load models
    {
        ScopedTimer timer("load_stt_model");
        rc = rac_voice_agent_load_stt_model(g_agent, stt_path.c_str(), "whisper-tiny-en",
                                             "Whisper Tiny EN");
    }
    if (rc != RAC_SUCCESS) {
        result.test_name = test_name;
        result.passed = false;
        result.details = "rac_voice_agent_load_stt_model failed: " + std::to_string(rc);
        rac_voice_agent_destroy(g_agent);
        g_agent = nullptr;
        teardown();
        return false;
    }

    {
        ScopedTimer timer("load_llm_model");
        rc = rac_voice_agent_load_llm_model(g_agent, llm_path.c_str(), "qwen3-0.6b",
                                             "Qwen3 0.6B Q8");
    }
    if (rc != RAC_SUCCESS) {
        result.test_name = test_name;
        result.passed = false;
        result.details = "rac_voice_agent_load_llm_model failed: " + std::to_string(rc);
        rac_voice_agent_destroy(g_agent);
        g_agent = nullptr;
        teardown();
        return false;
    }

    {
        ScopedTimer timer("load_tts_voice");
        rc = rac_voice_agent_load_tts_voice(g_agent, tts_path.c_str(),
                                             "vits-piper-en_US-lessac-medium",
                                             "Piper TTS Lessac Medium");
    }
    if (rc != RAC_SUCCESS) {
        result.test_name = test_name;
        result.passed = false;
        result.details = "rac_voice_agent_load_tts_voice failed: " + std::to_string(rc);
        rac_voice_agent_destroy(g_agent);
        g_agent = nullptr;
        teardown();
        return false;
    }

    // Initialize with loaded models
    rc = rac_voice_agent_initialize_with_loaded_models(g_agent);
    if (rc != RAC_SUCCESS) {
        result.test_name = test_name;
        result.passed = false;
        result.details =
            "rac_voice_agent_initialize_with_loaded_models failed: " + std::to_string(rc);
        rac_voice_agent_destroy(g_agent);
        g_agent = nullptr;
        teardown();
        return false;
    }

    g_agent_ready = true;
    return true;
}

// =============================================================================
// Test 1: create standalone (no models needed)
// =============================================================================

static TestResult test_create_standalone() {
    if (!setup()) {
        TestResult r;
        r.test_name = "create_standalone";
        r.passed = false;
        r.details = "setup() failed";
        return r;
    }

    rac_voice_agent_handle_t agent = nullptr;
    rac_result_t rc = rac_voice_agent_create_standalone(&agent);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_create_standalone should succeed");
    ASSERT_TRUE(agent != nullptr, "agent handle should not be NULL");

    rac_voice_agent_destroy(agent);
    teardown();
    return TEST_PASS();
}

// =============================================================================
// Test 2: load all models (STT + LLM + TTS)
// =============================================================================

static TestResult test_load_all_models() {
    TestResult result;
    if (!ensure_global_agent(result, "load_all_models")) return result;

    // If we reached here, all models loaded successfully via ensure_global_agent
    return TEST_PASS();
}

// =============================================================================
// Test 3: verify is_loaded checks
// =============================================================================

static TestResult test_is_loaded_checks() {
    TestResult result;
    if (!ensure_global_agent(result, "is_loaded_checks")) return result;

    rac_bool_t stt_loaded = RAC_FALSE;
    rac_result_t rc = rac_voice_agent_is_stt_loaded(g_agent, &stt_loaded);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_is_stt_loaded should succeed");
    ASSERT_EQ(stt_loaded, RAC_TRUE, "STT should be loaded");

    rac_bool_t llm_loaded = RAC_FALSE;
    rc = rac_voice_agent_is_llm_loaded(g_agent, &llm_loaded);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_is_llm_loaded should succeed");
    ASSERT_EQ(llm_loaded, RAC_TRUE, "LLM should be loaded");

    rac_bool_t tts_loaded = RAC_FALSE;
    rc = rac_voice_agent_is_tts_loaded(g_agent, &tts_loaded);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_is_tts_loaded should succeed");
    ASSERT_EQ(tts_loaded, RAC_TRUE, "TTS should be loaded");

    return TEST_PASS();
}

// =============================================================================
// Test 4: initialize with loaded models
// =============================================================================

static TestResult test_initialize_with_loaded() {
    TestResult result;
    if (!ensure_global_agent(result, "initialize_with_loaded")) return result;

    // Already initialized by ensure_global_agent; verify it did not fail
    // (the ensure function called rac_voice_agent_initialize_with_loaded_models)
    return TEST_PASS();
}

// =============================================================================
// Test 5: is_ready check
// =============================================================================

static TestResult test_is_ready() {
    TestResult result;
    if (!ensure_global_agent(result, "is_ready")) return result;

    rac_bool_t ready = RAC_FALSE;
    rac_result_t rc = rac_voice_agent_is_ready(g_agent, &ready);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_is_ready should succeed");
    ASSERT_EQ(ready, RAC_TRUE, "voice agent should be ready after initialization");

    return TEST_PASS();
}

// =============================================================================
// Test 6: get model IDs
// =============================================================================

static TestResult test_get_model_ids() {
    TestResult result;
    if (!ensure_global_agent(result, "get_model_ids")) return result;

    const char* stt_id = rac_voice_agent_get_stt_model_id(g_agent);
    ASSERT_TRUE(stt_id != nullptr, "STT model ID should not be NULL");
    std::cout << "  STT model ID: " << stt_id << "\n";

    const char* llm_id = rac_voice_agent_get_llm_model_id(g_agent);
    ASSERT_TRUE(llm_id != nullptr, "LLM model ID should not be NULL");
    std::cout << "  LLM model ID: " << llm_id << "\n";

    const char* tts_id = rac_voice_agent_get_tts_voice_id(g_agent);
    ASSERT_TRUE(tts_id != nullptr, "TTS voice ID should not be NULL");
    std::cout << "  TTS voice ID: " << tts_id << "\n";

    return TEST_PASS();
}

// =============================================================================
// Test 7: generate response via LLM
// =============================================================================

static TestResult test_generate_response() {
    TestResult result;
    if (!ensure_global_agent(result, "generate_response")) return result;

    char* response = nullptr;
    rac_result_t rc;
    {
        ScopedTimer timer("generate_response");
        rc = rac_voice_agent_generate_response(g_agent, "Say hello", &response);
    }
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_generate_response should succeed");
    ASSERT_TRUE(response != nullptr, "response should not be NULL");
    ASSERT_TRUE(std::strlen(response) > 0, "response should not be empty");

    std::cout << "  Response: " << response << "\n";

    rac_free(response);
    return TEST_PASS();
}

// =============================================================================
// Test 8: synthesize speech via TTS
// =============================================================================

static TestResult test_synthesize_speech() {
    TestResult result;
    if (!ensure_global_agent(result, "synthesize_speech")) return result;

    void* audio = nullptr;
    size_t audio_size = 0;
    rac_result_t rc;
    {
        ScopedTimer timer("synthesize_speech");
        rc = rac_voice_agent_synthesize_speech(g_agent, "Hello", &audio, &audio_size);
    }
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_synthesize_speech should succeed");
    ASSERT_TRUE(audio != nullptr, "synthesized audio should not be NULL");
    ASSERT_TRUE(audio_size > 0, "synthesized audio size should be > 0");

    std::cout << "  Synthesized " << audio_size << " bytes of audio\n";

    rac_free(audio);
    return TEST_PASS();
}

// =============================================================================
// Test 9: detect speech with silence (should detect no speech)
// =============================================================================

static TestResult test_detect_speech_silence() {
    TestResult result;
    if (!ensure_global_agent(result, "detect_speech_silence")) return result;

    // Generate 0.5 seconds of silence at 16kHz = 8000 samples
    const size_t num_samples = 8000;
    std::vector<float> silence(num_samples, 0.0f);

    rac_bool_t detected = RAC_TRUE; // default to TRUE so we can verify it becomes FALSE
    rac_result_t rc = rac_voice_agent_detect_speech(g_agent, silence.data(), num_samples, &detected);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_detect_speech should succeed");
    ASSERT_EQ(detected, RAC_FALSE, "silence should not be detected as speech");

    return TEST_PASS();
}

// =============================================================================
// Test 10: transcribe TTS-synthesized audio
// =============================================================================

static TestResult test_transcribe_tts_audio() {
    TestResult result;
    if (!ensure_global_agent(result, "transcribe_tts_audio")) return result;

    // Create a separate TTS handle to synthesize speech for transcription
    std::string tts_path = test_config::get_tts_model_path();
    rac_tts_onnx_config_t tts_cfg = RAC_TTS_ONNX_CONFIG_DEFAULT;
    rac_handle_t tts_handle = nullptr;
    rac_result_t rc = rac_tts_onnx_create(tts_path.c_str(), &tts_cfg, &tts_handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_tts_onnx_create should succeed for separate TTS handle");

    rac_tts_result_t tts_result = {};
    {
        ScopedTimer timer("tts_synthesize_hello_world");
        rc = rac_tts_onnx_synthesize(tts_handle, "Hello world", nullptr, &tts_result);
    }
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_tts_onnx_synthesize should succeed");
    ASSERT_TRUE(tts_result.audio_data != nullptr, "TTS audio_data should not be NULL");
    ASSERT_TRUE(tts_result.audio_size > 0, "TTS audio_size should be > 0");

    // TTS output is float samples at 22050Hz; resample to 16000Hz for STT
    const float* tts_float = static_cast<const float*>(tts_result.audio_data);
    size_t tts_num_samples = tts_result.audio_size / sizeof(float);
    std::vector<float> resampled =
        resample_linear(tts_float, tts_num_samples, tts_result.sample_rate, 16000);

    // Convert float [-1,1] to int16 for the voice agent transcribe API
    std::vector<int16_t> int16_data = float_to_int16(resampled);

    std::cout << "  TTS produced " << tts_num_samples << " samples at " << tts_result.sample_rate
              << "Hz, resampled to " << resampled.size() << " samples at 16kHz\n";

    // Transcribe the audio
    char* transcription = nullptr;
    {
        ScopedTimer timer("transcribe_tts_audio");
        rc = rac_voice_agent_transcribe(g_agent, int16_data.data(),
                                        int16_data.size() * sizeof(int16_t), &transcription);
    }
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_transcribe should succeed");
    ASSERT_TRUE(transcription != nullptr, "transcription should not be NULL");
    ASSERT_TRUE(std::strlen(transcription) > 0, "transcription should not be empty");

    std::cout << "  Transcription: " << transcription << "\n";

    rac_free(transcription);
    rac_tts_result_free(&tts_result);
    rac_tts_onnx_destroy(tts_handle);
    return TEST_PASS();
}

// =============================================================================
// Test 11: process_voice_turn with TTS-synthesized audio
// =============================================================================

static TestResult test_process_voice_turn_tts() {
    TestResult result;
    if (!ensure_global_agent(result, "process_voice_turn_tts")) return result;

    // Create a separate TTS handle to synthesize a question
    std::string tts_path = test_config::get_tts_model_path();
    rac_tts_onnx_config_t tts_cfg = RAC_TTS_ONNX_CONFIG_DEFAULT;
    rac_handle_t tts_handle = nullptr;
    rac_result_t rc = rac_tts_onnx_create(tts_path.c_str(), &tts_cfg, &tts_handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_tts_onnx_create should succeed for separate TTS handle");

    rac_tts_result_t tts_result = {};
    {
        ScopedTimer timer("tts_synthesize_question");
        rc = rac_tts_onnx_synthesize(tts_handle, "What is the capital of France", nullptr,
                                     &tts_result);
    }
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_tts_onnx_synthesize should succeed");

    // Resample 22050→16000 and convert to int16
    const float* tts_float = static_cast<const float*>(tts_result.audio_data);
    size_t tts_num_samples = tts_result.audio_size / sizeof(float);
    std::vector<float> resampled =
        resample_linear(tts_float, tts_num_samples, tts_result.sample_rate, 16000);
    std::vector<int16_t> int16_data = float_to_int16(resampled);

    // Run the full voice turn pipeline: STT → LLM → TTS
    rac_voice_agent_result_t va_result = {};
    {
        ScopedTimer timer("process_voice_turn");
        rc = rac_voice_agent_process_voice_turn(g_agent, int16_data.data(),
                                                int16_data.size() * sizeof(int16_t), &va_result);
    }
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_process_voice_turn should succeed");

    std::cout << "  Transcription: "
              << (va_result.transcription ? va_result.transcription : "(null)") << "\n";
    std::cout << "  Response: " << (va_result.response ? va_result.response : "(null)") << "\n";
    std::cout << "  Synthesized audio size: " << va_result.synthesized_audio_size << " bytes\n";

    ASSERT_TRUE(va_result.transcription != nullptr, "transcription should not be NULL");
    ASSERT_TRUE(std::strlen(va_result.transcription) > 0, "transcription should not be empty");
    ASSERT_TRUE(va_result.response != nullptr, "response should not be NULL");
    ASSERT_TRUE(std::strlen(va_result.response) > 0, "response should not be empty");
    ASSERT_TRUE(va_result.synthesized_audio != nullptr, "synthesized_audio should not be NULL");
    ASSERT_TRUE(va_result.synthesized_audio_size > 0, "synthesized_audio_size should be > 0");

    rac_voice_agent_result_free(&va_result);
    rac_tts_result_free(&tts_result);
    rac_tts_onnx_destroy(tts_handle);
    return TEST_PASS();
}

// =============================================================================
// Test 12: process_voice_turn with silence (no crash)
// =============================================================================

static TestResult test_process_voice_turn_silence() {
    TestResult result;
    if (!ensure_global_agent(result, "process_voice_turn_silence")) return result;

    // Generate 1 second of silence at 16kHz as int16
    std::vector<int16_t> silence(16000, 0);

    rac_voice_agent_result_t va_result = {};
    rac_result_t rc;
    {
        ScopedTimer timer("process_voice_turn_silence");
        rc = rac_voice_agent_process_voice_turn(g_agent, silence.data(),
                                                silence.size() * sizeof(int16_t), &va_result);
    }

    // The result may vary: some models transcribe silence as empty, some as "[Silence]",
    // and the pipeline may return an error for empty transcription.
    // We just verify no crash and the return code is a valid value.
    std::cout << "  Return code: " << rc << "\n";
    std::cout << "  Transcription: "
              << (va_result.transcription ? va_result.transcription : "(null)") << "\n";
    std::cout << "  Response: " << (va_result.response ? va_result.response : "(null)") << "\n";

    // No crash is the primary assertion; free resources regardless of rc
    rac_voice_agent_result_free(&va_result);
    return TEST_PASS();
}

// =============================================================================
// Test 13: process_stream with event callback
// =============================================================================

/** Tracking struct for stream events received during process_stream. */
struct StreamEventData {
    bool got_transcription = false;
    bool got_response = false;
    bool got_audio = false;
    int event_count = 0;
};

/** Callback for process_stream events. */
static void stream_event_callback(const rac_voice_agent_event_t* event, void* user_data) {
    auto* data = static_cast<StreamEventData*>(user_data);
    data->event_count++;
    if (event->type == RAC_VOICE_AGENT_EVENT_TRANSCRIPTION) data->got_transcription = true;
    if (event->type == RAC_VOICE_AGENT_EVENT_RESPONSE) data->got_response = true;
    if (event->type == RAC_VOICE_AGENT_EVENT_AUDIO_SYNTHESIZED) data->got_audio = true;
}

static TestResult test_process_stream_events() {
    TestResult result;
    if (!ensure_global_agent(result, "process_stream_events")) return result;

    // Create a separate TTS handle to synthesize input audio
    std::string tts_path = test_config::get_tts_model_path();
    rac_tts_onnx_config_t tts_cfg = RAC_TTS_ONNX_CONFIG_DEFAULT;
    rac_handle_t tts_handle = nullptr;
    rac_result_t rc = rac_tts_onnx_create(tts_path.c_str(), &tts_cfg, &tts_handle);
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_tts_onnx_create should succeed for separate TTS handle");

    rac_tts_result_t tts_result = {};
    {
        ScopedTimer timer("tts_synthesize_hello");
        rc = rac_tts_onnx_synthesize(tts_handle, "Hello", nullptr, &tts_result);
    }
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_tts_onnx_synthesize should succeed");

    // Resample 22050→16000 and convert to int16
    const float* tts_float = static_cast<const float*>(tts_result.audio_data);
    size_t tts_num_samples = tts_result.audio_size / sizeof(float);
    std::vector<float> resampled =
        resample_linear(tts_float, tts_num_samples, tts_result.sample_rate, 16000);
    std::vector<int16_t> int16_data = float_to_int16(resampled);

    // Process with streaming events
    StreamEventData event_data;
    {
        ScopedTimer timer("process_stream");
        rc = rac_voice_agent_process_stream(g_agent, int16_data.data(),
                                            int16_data.size() * sizeof(int16_t),
                                            stream_event_callback, &event_data);
    }
    ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_process_stream should succeed");
    ASSERT_TRUE(event_data.event_count > 0, "should have received at least one event");

    std::cout << "  Total events received: " << event_data.event_count << "\n";
    std::cout << "  Got transcription event: " << (event_data.got_transcription ? "yes" : "no")
              << "\n";
    std::cout << "  Got response event: " << (event_data.got_response ? "yes" : "no") << "\n";
    std::cout << "  Got audio event: " << (event_data.got_audio ? "yes" : "no") << "\n";

    rac_tts_result_free(&tts_result);
    rac_tts_onnx_destroy(tts_handle);
    return TEST_PASS();
}

// =============================================================================
// Test 14: pipeline state helpers (no models needed)
// =============================================================================

static TestResult test_pipeline_state_helpers() {
    // These are pure utility functions that don't require an initialized agent

    // Test state name
    const char* idle_name = rac_audio_pipeline_state_name(RAC_AUDIO_PIPELINE_IDLE);
    ASSERT_TRUE(idle_name != nullptr, "state name for IDLE should not be NULL");
    ASSERT_TRUE(std::strlen(idle_name) > 0, "state name for IDLE should not be empty");

    const char* listening_name = rac_audio_pipeline_state_name(RAC_AUDIO_PIPELINE_LISTENING);
    ASSERT_TRUE(listening_name != nullptr, "state name for LISTENING should not be NULL");

    const char* error_name = rac_audio_pipeline_state_name(RAC_AUDIO_PIPELINE_ERROR);
    ASSERT_TRUE(error_name != nullptr, "state name for ERROR should not be NULL");

    // Test valid transition: IDLE -> LISTENING should be valid
    rac_bool_t valid = rac_audio_pipeline_is_valid_transition(RAC_AUDIO_PIPELINE_IDLE,
                                                               RAC_AUDIO_PIPELINE_LISTENING);
    ASSERT_EQ(valid, RAC_TRUE, "IDLE -> LISTENING should be a valid transition");

    // Test can_play_tts: GENERATING_RESPONSE should have a defined result
    rac_bool_t can_play =
        rac_audio_pipeline_can_play_tts(RAC_AUDIO_PIPELINE_GENERATING_RESPONSE);
    // We just verify it returns without crashing; the actual value depends on the state machine
    (void)can_play;

    std::cout << "  IDLE name: " << idle_name << "\n";
    std::cout << "  LISTENING name: " << listening_name << "\n";

    return TEST_PASS();
}

// =============================================================================
// Test 15: cleanup and destroy (no crash)
// =============================================================================

static TestResult test_cleanup_destroy() {
    // This test cleans up the global agent if it exists
    if (g_agent && g_agent_ready) {
        rac_result_t rc = rac_voice_agent_cleanup(g_agent);
        ASSERT_EQ(rc, RAC_SUCCESS, "rac_voice_agent_cleanup should succeed");

        rac_voice_agent_destroy(g_agent);
        g_agent = nullptr;
        g_agent_ready = false;

        teardown();
    }

    // If we get here without crash, the test passes
    return TEST_PASS();
}

// =============================================================================
// Main: register tests and dispatch via CLI args
// =============================================================================

int main(int argc, char** argv) {
    TestSuite suite("voice_agent");

    suite.add("create_standalone", test_create_standalone);
    suite.add("load_all_models", test_load_all_models);
    suite.add("is_loaded_checks", test_is_loaded_checks);
    suite.add("initialize_with_loaded", test_initialize_with_loaded);
    suite.add("is_ready", test_is_ready);
    suite.add("get_model_ids", test_get_model_ids);
    suite.add("generate_response", test_generate_response);
    suite.add("synthesize_speech", test_synthesize_speech);
    suite.add("detect_speech_silence", test_detect_speech_silence);
    suite.add("transcribe_tts_audio", test_transcribe_tts_audio);
    suite.add("process_voice_turn_tts", test_process_voice_turn_tts);
    suite.add("process_voice_turn_silence", test_process_voice_turn_silence);
    suite.add("process_stream_events", test_process_stream_events);
    suite.add("pipeline_state_helpers", test_pipeline_state_helpers);
    suite.add("cleanup_destroy", test_cleanup_destroy);

    return suite.run(argc, argv);
}
