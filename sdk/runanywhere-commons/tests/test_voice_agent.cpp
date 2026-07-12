/**
 * @file test_voice_agent.cpp
 * @brief Real-inference voice-agent integration tests.
 *
 * Drives the commons-owned voice pipeline with real backends:
 *   Piper TTS fixture -> STT -> LLM -> TTS
 *
 * This test intentionally uses the public C component/proto entry points that
 * platform SDKs call, so a pass here becomes the native source-of-truth signal
 * for wrapper replay tests.
 */

#include "rac_tts_sherpa.h"  // engines/sherpa direct TTS fixture generation
#include "test_common.h"
#include "test_config.h"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/plugin/rac_plugin_entry_onnx.h"
#include "rac/plugin/rac_plugin_entry_sherpa.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "voice_agent_service.pb.h"
#endif

namespace {

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
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

static rac_bool_t test_file_exists(const char* /*path*/, void* /*user_data*/) {
    return RAC_FALSE;
}

static rac_result_t test_file_read(const char* /*path*/, void** /*out_data*/, size_t* /*out_size*/,
                                   void* /*user_data*/) {
    return RAC_ERROR_FILE_NOT_FOUND;
}

static rac_result_t test_file_write(const char* /*path*/, const void* /*data*/, size_t /*size*/,
                                    void* /*user_data*/) {
    return RAC_SUCCESS;
}

static rac_result_t test_file_delete(const char* /*path*/, void* /*user_data*/) {
    return RAC_SUCCESS;
}

static rac_result_t test_secure_get(const char* /*key*/, char** /*out_value*/,
                                    void* /*user_data*/) {
    return RAC_ERROR_FILE_NOT_FOUND;
}

static rac_result_t test_secure_set(const char* /*key*/, const char* /*value*/,
                                    void* /*user_data*/) {
    return RAC_SUCCESS;
}

static rac_result_t test_secure_delete(const char* /*key*/, void* /*user_data*/) {
    return RAC_SUCCESS;
}

static rac_result_t test_get_memory_info(rac_memory_info_t* out_info, void* /*user_data*/) {
    if (!out_info)
        return RAC_ERROR_INVALID_ARGUMENT;
    out_info->total_bytes = 8ULL * 1024 * 1024 * 1024;
    out_info->available_bytes = 4ULL * 1024 * 1024 * 1024;
    out_info->used_bytes = out_info->total_bytes - out_info->available_bytes;
    return RAC_SUCCESS;
}

static rac_platform_adapter_t make_test_adapter() {
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
    adapter.log = test_log;
    adapter.now_ms = test_now_ms;
    adapter.get_memory_info = test_get_memory_info;
    return adapter;
}

static bool setup() {
    static rac_platform_adapter_t adapter = make_test_adapter();
    rac_config_t config = {};
    config.platform_adapter = &adapter;
    config.log_level = RAC_LOG_INFO;
    config.log_tag = "test_voice_agent";
    if (rac_init(&config) != RAC_SUCCESS)
        return false;
    if (rac_backend_onnx_register() != RAC_SUCCESS)
        return false;
    if (rac_backend_sherpa_register() != RAC_SUCCESS)
        return false;
    if (rac_backend_llamacpp_register() != RAC_SUCCESS)
        return false;
    return true;
}

static void teardown() {
    rac_shutdown();
}

static std::vector<int16_t> float_pcm_to_int16(const float* samples, size_t count) {
    std::vector<int16_t> out(count);
    for (size_t i = 0; i < count; ++i) {
        float clamped = std::max(-1.0f, std::min(1.0f, samples[i]));
        out[i] = static_cast<int16_t>(clamped * 32767.0f);
    }
    return out;
}

static bool synthesize_fixture_audio(const std::string& tts_model_path,
                                     std::vector<int16_t>* out_audio) {
    rac_handle_t tts = nullptr;
    rac_tts_sherpa_config_t cfg = RAC_TTS_SHERPA_CONFIG_DEFAULT;
    rac_result_t rc = rac_tts_sherpa_create(tts_model_path.c_str(), &cfg, &tts);
    if (rc != RAC_SUCCESS)
        return false;

    rac_tts_result_t result = {};
    rc = rac_tts_sherpa_synthesize(tts, "RunAnywhere runs models on device.", nullptr, &result);
    if (rc != RAC_SUCCESS || !result.audio_data || result.audio_size == 0) {
        rac_tts_sherpa_destroy(tts);
        return false;
    }

    const auto* float_samples = static_cast<const float*>(result.audio_data);
    const size_t sample_count = result.audio_size / sizeof(float);
    std::vector<float> resampled =
        resample_linear(float_samples, sample_count, result.sample_rate, 16000);
    *out_audio = float_pcm_to_int16(resampled.data(), resampled.size());

    rac_free(result.audio_data);
    rac_tts_sherpa_destroy(tts);
    return !out_audio->empty();
}

static TestResult test_full_voice_turn_real_models() {
    TestResult result;
    result.test_name = "full_voice_turn_real_models";

#if !defined(RAC_HAVE_PROTOBUF)
    result.passed = !test_config::require_real_artifacts();
    result.details = result.passed ? "SKIPPED - protobuf support is not available"
                                   : "protobuf support is required for real voice-agent E2E";
    return result;
#else
    const std::string stt_model = test_config::get_stt_model_path();
    const std::string tts_model = test_config::get_tts_model_path();
    const std::string llm_model = test_config::get_llm_model_path();
    if (!test_config::require_model(stt_model, result.test_name, result))
        return result;
    if (!test_config::require_model(tts_model, result.test_name, result))
        return result;
    if (!test_config::require_model(llm_model, result.test_name, result))
        return result;

    if (!setup()) {
        result.passed = false;
        result.details = "setup() failed";
        return result;
    }

    std::vector<int16_t> turn_audio;
    if (!synthesize_fixture_audio(tts_model, &turn_audio)) {
        result.passed = false;
        result.details = "failed to synthesize fixture audio";
        teardown();
        return result;
    }

    rac_voice_agent_handle_t agent = nullptr;
    rac_result_t rc = rac_voice_agent_create_standalone(&agent);
    if (rc != RAC_SUCCESS || !agent) {
        result.passed = false;
        result.details = "rac_voice_agent_create_standalone failed: " + std::to_string(rc);
        teardown();
        return result;
    }

    rac_voice_agent_config_t config = RAC_VOICE_AGENT_CONFIG_DEFAULT;
    config.stt_config.model_path = stt_model.c_str();
    config.stt_config.model_id = "sherpa-onnx-whisper-tiny.en";
    config.stt_config.model_name = "Sherpa Whisper Tiny EN";
    config.llm_config.model_path = llm_model.c_str();
    config.llm_config.model_id = "qwen3-0.6b-q8_0";
    config.llm_config.model_name = "Qwen3 0.6B Q8_0";
    config.tts_config.voice_path = tts_model.c_str();
    config.tts_config.voice_id = "vits-piper-en_US-lessac-medium";
    config.tts_config.voice_name = "Piper Lessac Medium";

    rc = rac_voice_agent_initialize(agent, &config);
    if (rc != RAC_SUCCESS) {
        result.passed = false;
        result.details = "rac_voice_agent_initialize failed: " + std::to_string(rc);
        rac_voice_agent_destroy(agent);
        teardown();
        return result;
    }

    rac_bool_t ready = RAC_FALSE;
    rc = rac_voice_agent_is_ready(agent, &ready);
    if (rc != RAC_SUCCESS || ready != RAC_TRUE) {
        result.passed = false;
        result.details = "voice agent did not report ready";
        rac_voice_agent_destroy(agent);
        teardown();
        return result;
    }

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rc = rac_voice_agent_process_voice_turn_proto(agent, turn_audio.data(),
                                                  turn_audio.size() * sizeof(int16_t), &out);
    runanywhere::v1::VoiceAgentResult parsed;
    const bool parsed_ok =
        out.status == RAC_SUCCESS && parsed.ParseFromArray(out.data, static_cast<int>(out.size));
    if (rc != RAC_SUCCESS || !parsed_ok) {
        result.passed = false;
        result.details = "voice turn failed: rc=" + std::to_string(rc) +
                         ", proto_status=" + std::to_string(out.status);
        rac_proto_buffer_free(&out);
        rac_voice_agent_destroy(agent);
        teardown();
        return result;
    }

    const bool transcript_ok =
        parsed.has_transcription() &&
        (contains_ci(parsed.transcription(), "runanywhere") ||
         contains_ci(parsed.transcription(), "models") || contains_ci(parsed.transcription(), "device"));
    const bool response_ok = parsed.has_assistant_response() && !parsed.assistant_response().empty();
    const bool audio_ok = !parsed.synthesized_audio().empty();
    const bool final_state_ok = parsed.has_final_state() && parsed.final_state().ready();

    if (!transcript_ok || !response_ok || !audio_ok || !final_state_ok) {
        result.passed = false;
        result.details = "voice turn missing expected evidence: transcription=\"" +
                         parsed.transcription() + "\", response_bytes=" +
                         std::to_string(parsed.assistant_response().size()) + ", audio_bytes=" +
                         std::to_string(parsed.synthesized_audio().size());
    } else {
        result.passed = true;
        result.details = "transcription=\"" + parsed.transcription() + "\", response_bytes=" +
                         std::to_string(parsed.assistant_response().size()) + ", audio_bytes=" +
                         std::to_string(parsed.synthesized_audio().size()) + ", total_ms=" +
                         std::to_string(parsed.total_time_ms());
    }

    rac_proto_buffer_free(&out);
    rac_voice_agent_destroy(agent);
    teardown();
    return result;
#endif
}

}  // namespace

int main(int argc, char** argv) {
    TestSuite suite("voice_agent");
    suite.add("full_voice_turn_real_models", test_full_voice_turn_real_models);
    return suite.run(argc, argv);
}
