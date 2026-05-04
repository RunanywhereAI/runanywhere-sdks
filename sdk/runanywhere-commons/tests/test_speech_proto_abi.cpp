/**
 * @file test_speech_proto_abi.cpp
 * @brief Generated-proto C ABI coverage for STT/TTS/VAD/VoiceAgent.
 */

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/voice_agent/rac_voice_event_abi.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
#include "stt_options.pb.h"
#include "tts_options.pb.h"
#include "vad_options.pb.h"
#include "voice_agent_service.pb.h"
#include "voice_events.pb.h"
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                    \
    do {                                                                                      \
        ++test_count;                                                                         \
        if (!(cond)) {                                                                        \
            ++fail_count;                                                                     \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__,      \
                         #cond);                                                             \
        } else {                                                                              \
            std::fprintf(stdout, "  ok:   %s\n", label);                                     \
        }                                                                                     \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

char* dup_cstr(const char* text) {
    if (!text) return nullptr;
    const size_t len = std::strlen(text);
    auto* out = static_cast<char*>(std::malloc(len + 1));
    if (!out) return nullptr;
    std::memcpy(out, text, len + 1);
    return out;
}

template <typename T>
bool serialize(const T& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    return out->empty() ||
           message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

template <typename T>
bool parse_buffer(const rac_proto_buffer_t& buffer, T* out) {
    return buffer.status == RAC_SUCCESS &&
           out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
}

struct MockStt {
    bool initialized{false};
};

struct MockTts {
    bool initialized{false};
};

struct MockVad {
    float threshold{0.1f};
    bool active{false};
    bool speech{false};
};

struct MockLlm {
    bool initialized{false};
};

rac_result_t mock_stt_create(const char*, const char*, void** out_impl) {
    *out_impl = new MockStt();
    return RAC_SUCCESS;
}

rac_result_t mock_stt_initialize(void* impl, const char*) {
    static_cast<MockStt*>(impl)->initialized = true;
    return RAC_SUCCESS;
}

rac_result_t mock_stt_transcribe(void* impl,
                                 const void* audio_data,
                                 size_t audio_size,
                                 const rac_stt_options_t*,
                                 rac_stt_result_t* out_result) {
    if (!impl || !audio_data || audio_size == 0 || !out_result) return RAC_ERROR_INVALID_ARGUMENT;
    out_result->text = dup_cstr("hello mock");
    out_result->detected_language = dup_cstr("en");
    out_result->confidence = 0.87f;
    out_result->processing_time_ms = 12;
    return out_result->text ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t mock_stt_stream(void*,
                             const void*,
                             size_t,
                             const rac_stt_options_t*,
                             rac_stt_stream_callback_t callback,
                             void* user_data) {
    callback("hello", RAC_FALSE, user_data);
    callback("hello mock", RAC_TRUE, user_data);
    return RAC_SUCCESS;
}

rac_result_t mock_stt_info(void*, rac_stt_info_t* out_info) {
    out_info->is_ready = RAC_TRUE;
    out_info->current_model = "mock-stt";
    out_info->supports_streaming = RAC_TRUE;
    return RAC_SUCCESS;
}

void mock_stt_destroy(void* impl) {
    delete static_cast<MockStt*>(impl);
}

rac_result_t mock_tts_create(const char*, const char*, void** out_impl) {
    *out_impl = new MockTts();
    return RAC_SUCCESS;
}

rac_result_t mock_tts_initialize(void* impl) {
    static_cast<MockTts*>(impl)->initialized = true;
    return RAC_SUCCESS;
}

rac_result_t mock_tts_synthesize(void* impl,
                                 const char* text,
                                 const rac_tts_options_t*,
                                 rac_tts_result_t* out_result) {
    if (!impl || !text || !out_result) return RAC_ERROR_INVALID_ARGUMENT;
    constexpr float samples[] = {0.0f, 0.25f, -0.25f, 0.0f};
    out_result->audio_size = sizeof(samples);
    out_result->audio_data = std::malloc(out_result->audio_size);
    if (!out_result->audio_data) return RAC_ERROR_OUT_OF_MEMORY;
    std::memcpy(out_result->audio_data, samples, sizeof(samples));
    out_result->audio_format = RAC_AUDIO_FORMAT_PCM;
    out_result->sample_rate = 1000;
    out_result->duration_ms = 1234;
    out_result->processing_time_ms = 7;
    return RAC_SUCCESS;
}

rac_result_t mock_tts_stream(void*,
                             const char*,
                             const rac_tts_options_t*,
                             rac_tts_stream_callback_t callback,
                             void* user_data) {
    constexpr float samples[] = {0.0f, 0.1f};
    callback(samples, sizeof(samples), user_data);
    return RAC_SUCCESS;
}

rac_result_t mock_tts_info(void*, rac_tts_info_t* out_info) {
    static const char* voices[] = {"mock-voice"};
    out_info->is_ready = RAC_TRUE;
    out_info->is_synthesizing = RAC_FALSE;
    out_info->available_voices = voices;
    out_info->num_voices = 1;
    return RAC_SUCCESS;
}

void mock_tts_destroy(void* impl) {
    delete static_cast<MockTts*>(impl);
}

rac_result_t mock_vad_create(const char*, const char*, void** out_impl) {
    *out_impl = new MockVad();
    return RAC_SUCCESS;
}

rac_result_t mock_vad_initialize(void*, const char*) {
    return RAC_SUCCESS;
}

rac_result_t mock_vad_start(void* impl) {
    static_cast<MockVad*>(impl)->active = true;
    return RAC_SUCCESS;
}

rac_result_t mock_vad_stop(void* impl) {
    static_cast<MockVad*>(impl)->active = false;
    return RAC_SUCCESS;
}

rac_result_t mock_vad_reset(void* impl) {
    static_cast<MockVad*>(impl)->speech = false;
    return RAC_SUCCESS;
}

rac_result_t mock_vad_set_threshold(void* impl, float threshold) {
    static_cast<MockVad*>(impl)->threshold = threshold;
    return RAC_SUCCESS;
}

rac_bool_t mock_vad_is_speech_active(void* impl) {
    return static_cast<MockVad*>(impl)->speech ? RAC_TRUE : RAC_FALSE;
}

rac_result_t mock_vad_process(void* impl,
                              const float* samples,
                              size_t num_samples,
                              rac_bool_t* out_is_speech) {
    auto* vad = static_cast<MockVad*>(impl);
    float sum = 0.0f;
    for (size_t i = 0; i < num_samples; ++i) sum += std::fabs(samples[i]);
    vad->speech = num_samples > 0 && (sum / static_cast<float>(num_samples)) > vad->threshold;
    *out_is_speech = vad->speech ? RAC_TRUE : RAC_FALSE;
    return RAC_SUCCESS;
}

void mock_vad_destroy(void* impl) {
    delete static_cast<MockVad*>(impl);
}

rac_result_t mock_llm_create(const char*, const char*, void** out_impl) {
    *out_impl = new MockLlm();
    return RAC_SUCCESS;
}

rac_result_t mock_llm_initialize(void* impl, const char*) {
    static_cast<MockLlm*>(impl)->initialized = true;
    return RAC_SUCCESS;
}

rac_result_t mock_llm_generate(void*,
                               const char* prompt,
                               const rac_llm_options_t*,
                               rac_llm_result_t* out_result) {
    if (!prompt || !out_result) return RAC_ERROR_INVALID_ARGUMENT;
    out_result->text = dup_cstr("assistant mock");
    out_result->prompt_tokens = 2;
    out_result->completion_tokens = 2;
    out_result->total_tokens = 4;
    out_result->total_time_ms = 9;
    return out_result->text ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

void mock_llm_destroy(void* impl) {
    delete static_cast<MockLlm*>(impl);
}

rac_stt_service_ops_t g_stt_ops{};
rac_tts_service_ops_t g_tts_ops{};
rac_vad_service_ops_t g_vad_ops{};
rac_llm_service_ops_t g_llm_ops{};
rac_engine_vtable_t g_speech_vtable{};
rac_engine_vtable_t g_llm_vtable{};
const rac_runtime_id_t k_cpu_runtime[] = {RAC_RUNTIME_CPU};

void install_mock_plugin() {
    g_stt_ops.create = mock_stt_create;
    g_stt_ops.initialize = mock_stt_initialize;
    g_stt_ops.transcribe = mock_stt_transcribe;
    g_stt_ops.transcribe_stream = mock_stt_stream;
    g_stt_ops.get_info = mock_stt_info;
    g_stt_ops.destroy = mock_stt_destroy;

    g_tts_ops.create = mock_tts_create;
    g_tts_ops.initialize = mock_tts_initialize;
    g_tts_ops.synthesize = mock_tts_synthesize;
    g_tts_ops.synthesize_stream = mock_tts_stream;
    g_tts_ops.get_info = mock_tts_info;
    g_tts_ops.destroy = mock_tts_destroy;

    g_vad_ops.create = mock_vad_create;
    g_vad_ops.initialize = mock_vad_initialize;
    g_vad_ops.start = mock_vad_start;
    g_vad_ops.stop = mock_vad_stop;
    g_vad_ops.reset = mock_vad_reset;
    g_vad_ops.set_threshold = mock_vad_set_threshold;
    g_vad_ops.is_speech_active = mock_vad_is_speech_active;
    g_vad_ops.process = mock_vad_process;
    g_vad_ops.destroy = mock_vad_destroy;

    g_llm_ops.create = mock_llm_create;
    g_llm_ops.initialize = mock_llm_initialize;
    g_llm_ops.generate = mock_llm_generate;
    g_llm_ops.destroy = mock_llm_destroy;

    g_speech_vtable = {};
    g_speech_vtable.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    g_speech_vtable.metadata.name = "onnx";
    g_speech_vtable.metadata.display_name = "CPP10A Mock Speech";
    g_speech_vtable.metadata.engine_version = "0.0.0";
    g_speech_vtable.metadata.priority = 10000;
    g_speech_vtable.metadata.runtimes = k_cpu_runtime;
    g_speech_vtable.metadata.runtimes_count = 1;
    g_speech_vtable.stt_ops = &g_stt_ops;
    g_speech_vtable.tts_ops = &g_tts_ops;
    g_speech_vtable.vad_ops = &g_vad_ops;

    g_llm_vtable = {};
    g_llm_vtable.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    g_llm_vtable.metadata.name = "llamacpp";
    g_llm_vtable.metadata.display_name = "CPP10A Mock LLM";
    g_llm_vtable.metadata.engine_version = "0.0.0";
    g_llm_vtable.metadata.priority = 10000;
    g_llm_vtable.metadata.runtimes = k_cpu_runtime;
    g_llm_vtable.metadata.runtimes_count = 1;
    g_llm_vtable.llm_ops = &g_llm_ops;

    (void)rac_plugin_unregister("llamacpp");
    (void)rac_plugin_unregister("onnx");
    CHECK(rac_plugin_register(&g_speech_vtable) == RAC_SUCCESS, "mock speech plugin registers");
    CHECK(rac_plugin_register(&g_llm_vtable) == RAC_SUCCESS, "mock LLM plugin registers");
}

bool poll_sdk_until_failure() {
    for (int i = 0; i < 24; ++i) {
        rac_proto_buffer_t event;
        rac_proto_buffer_init(&event);
        if (rac_sdk_event_poll(&event) != RAC_SUCCESS) return false;
        runanywhere::v1::SDKEvent decoded;
        const bool ok = decoded.ParseFromArray(event.data, static_cast<int>(event.size));
        rac_proto_buffer_free(&event);
        if (ok && decoded.has_failure()) return true;
    }
    return false;
}

int test_parse_failure_and_missing_component() {
    rac_sdk_event_clear_queue();
    rac_handle_t stt = nullptr;
    CHECK(rac_stt_component_create(&stt) == RAC_SUCCESS, "STT component creates");
    const int16_t audio[] = {0, 1, 2, 3};
    const uint8_t bad[] = {0xff, 0xff, 0xff};

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_stt_component_transcribe_proto(stt, audio, sizeof(audio), bad,
                                                         sizeof(bad), &out);
    CHECK(rc == RAC_ERROR_DECODING_ERROR, "STT proto parse failure returns decoding error");
    CHECK(out.status == RAC_ERROR_DECODING_ERROR, "parse failure marks output error");
    rac_proto_buffer_free(&out);

    runanywhere::v1::STTOptions options;
    std::vector<uint8_t> bytes;
    CHECK(serialize(options, &bytes), "empty STTOptions serializes");
    rac_proto_buffer_init(&out);
    rc = rac_stt_component_transcribe_proto(stt, audio, sizeof(audio),
                                            bytes.empty() ? nullptr : bytes.data(), bytes.size(),
                                            &out);
    CHECK(rc == RAC_ERROR_NOT_INITIALIZED, "missing STT lifecycle component fails");
    CHECK(out.status == RAC_ERROR_NOT_INITIALIZED, "missing STT marks output error");
    CHECK(poll_sdk_until_failure(), "missing STT publishes failure SDKEvent");
    rac_proto_buffer_free(&out);
    rac_stt_component_destroy(stt);
    return 0;
}

int test_mocked_stt() {
    rac_handle_t stt = nullptr;
    CHECK(rac_stt_component_create(&stt) == RAC_SUCCESS, "mock STT component creates");
    CHECK(rac_stt_component_load_model(stt, "mock-stt", "mock-stt", "Mock STT") == RAC_SUCCESS,
          "mock STT model loads");

    const int16_t audio[] = {0, 1, 2, 3};
    runanywhere::v1::STTOptions options;
    options.set_language(runanywhere::v1::STT_LANGUAGE_EN);
    std::vector<uint8_t> bytes;
    CHECK(serialize(options, &bytes), "STTOptions serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_stt_component_transcribe_proto(stt, audio, sizeof(audio), bytes.data(),
                                                         bytes.size(), &out);
    runanywhere::v1::STTOutput result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result), "STTOutput parses");
    CHECK(result.text() == "hello mock", "STTOutput text matches mock");
    CHECK(result.metadata().processing_time_ms() == 12, "STT metadata uses milliseconds");
    rac_proto_buffer_free(&out);

    struct Partials {
        int count{0};
        bool saw_final{false};
    } partials;
    auto partial_cb = [](const uint8_t* data, size_t size, void* user_data) {
        auto* p = static_cast<Partials*>(user_data);
        runanywhere::v1::STTPartialResult partial;
        if (partial.ParseFromArray(data, static_cast<int>(size))) {
            p->count++;
            p->saw_final = p->saw_final || partial.is_final();
        }
    };
    rc = rac_stt_component_transcribe_stream_proto(stt, audio, sizeof(audio), bytes.data(),
                                                   bytes.size(), partial_cb, &partials);
    CHECK(rc == RAC_SUCCESS && partials.count == 2 && partials.saw_final,
          "STT stream emits proto partials");
    rac_stt_component_destroy(stt);
    return 0;
}

int test_mocked_tts() {
    rac_handle_t tts = nullptr;
    CHECK(rac_tts_component_create(&tts) == RAC_SUCCESS, "mock TTS component creates");
    CHECK(rac_tts_component_load_voice(tts, "mock-tts", "mock-voice", "Mock Voice") ==
              RAC_SUCCESS,
          "mock TTS voice loads");

    int voices = 0;
    auto voice_cb = [](const uint8_t* data, size_t size, void* user_data) {
        auto* count = static_cast<int*>(user_data);
        runanywhere::v1::TTSVoiceInfo voice;
        if (voice.ParseFromArray(data, static_cast<int>(size)) && voice.id() == "mock-voice") {
            ++(*count);
        }
    };
    CHECK(rac_tts_component_list_voices_proto(tts, voice_cb, &voices) == RAC_SUCCESS &&
              voices == 1,
          "TTS voices enumerate as proto messages");

    runanywhere::v1::TTSOptions options;
    options.set_language_code("en-US");
    std::vector<uint8_t> bytes;
    CHECK(serialize(options, &bytes), "TTSOptions serializes");

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_tts_component_synthesize_proto(tts, "hello", bytes.data(), bytes.size(),
                                                         &out);
    runanywhere::v1::TTSOutput result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result), "TTSOutput parses");
    CHECK(result.duration_ms() == 1234, "TTS duration remains milliseconds");
    CHECK(result.metadata().audio_duration_ms() == 1234, "TTS metadata duration is ms");
    rac_proto_buffer_free(&out);

    int chunks = 0;
    auto chunk_cb = [](const uint8_t* data, size_t size, void* user_data) {
        auto* count = static_cast<int*>(user_data);
        runanywhere::v1::TTSOutput output;
        if (output.ParseFromArray(data, static_cast<int>(size)) && output.audio_data().size() > 0) {
            ++(*count);
        }
    };
    rc = rac_tts_component_synthesize_stream_proto(tts, "hello", bytes.data(), bytes.size(),
                                                   chunk_cb, &chunks);
    CHECK(rc == RAC_SUCCESS && chunks == 1, "TTS stream emits proto chunks");
    rac_tts_component_destroy(tts);
    return 0;
}

int test_mocked_vad_and_activity() {
    rac_sdk_event_clear_queue();
    rac_handle_t vad = nullptr;
    CHECK(rac_vad_component_create(&vad) == RAC_SUCCESS, "mock VAD component creates");
    CHECK(rac_vad_component_load_model(vad, "mock-vad", "mock-vad", "Mock VAD") == RAC_SUCCESS,
          "mock VAD model loads");

    runanywhere::v1::VADOptions options;
    options.set_threshold(0.1f);
    std::vector<uint8_t> bytes;
    CHECK(serialize(options, &bytes), "VADOptions serializes");
    const float speech[] = {0.3f, 0.4f, 0.5f, 0.6f};
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_vad_component_process_proto(vad, speech, 4, bytes.data(), bytes.size(),
                                                      &out);
    runanywhere::v1::VADResult result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result), "VADResult parses");
    CHECK(result.is_speech(), "mock VAD detects speech");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_vad_component_get_statistics_proto(vad, &out);
    runanywhere::v1::VADStatistics stats;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &stats), "VADStatistics parses");
    rac_proto_buffer_free(&out);

    bool saw_vad_event = false;
    for (int i = 0; i < 12; ++i) {
        rac_proto_buffer_t event;
        rac_proto_buffer_init(&event);
        if (rac_sdk_event_poll(&event) != RAC_SUCCESS) break;
        runanywhere::v1::SDKEvent decoded;
        if (decoded.ParseFromArray(event.data, static_cast<int>(event.size)) &&
            decoded.has_voice_pipeline() && decoded.voice_pipeline().has_vad()) {
            saw_vad_event = true;
        }
        rac_proto_buffer_free(&event);
    }
    CHECK(saw_vad_event, "VAD process publishes canonical SDKEvent VoiceEvent bytes");
    rac_vad_component_destroy(vad);

    rac_handle_t energy_vad = nullptr;
    CHECK(rac_vad_component_create(&energy_vad) == RAC_SUCCESS, "energy VAD component creates");
    runanywhere::v1::VADConfiguration config;
    config.set_sample_rate(16000);
    config.set_frame_length_ms(100);
    config.set_threshold(0.01f);
    std::vector<uint8_t> config_bytes;
    CHECK(serialize(config, &config_bytes), "VADConfiguration serializes");
    CHECK(rac_vad_component_configure_proto(energy_vad, config_bytes.data(),
                                            config_bytes.size()) == RAC_SUCCESS,
          "VAD configure proto succeeds");
    int activity_count = 0;
    auto activity_cb = [](const uint8_t* data, size_t size, void* user_data) {
        auto* count = static_cast<int*>(user_data);
        runanywhere::v1::SpeechActivityEvent event;
        if (event.ParseFromArray(data, static_cast<int>(size)) &&
            event.event_type() ==
                runanywhere::v1::SPEECH_ACTIVITY_KIND_SPEECH_STARTED) {
            ++(*count);
        }
    };
    CHECK(rac_vad_component_set_activity_proto_callback(energy_vad, activity_cb,
                                                        &activity_count) == RAC_SUCCESS,
          "VAD activity proto callback registers");
    CHECK(rac_vad_component_initialize(energy_vad) == RAC_SUCCESS, "energy VAD initializes");
    std::vector<float> silence(1600, 0.0f);
    rac_bool_t is_speech = RAC_FALSE;
    for (int i = 0; i < 20; ++i) {
        (void)rac_vad_component_process(energy_vad, silence.data(), silence.size(), &is_speech);
    }
    std::vector<float> loud(1600, 0.5f);
    (void)rac_vad_component_process(energy_vad, loud.data(), loud.size(), &is_speech);
    CHECK(activity_count >= 1, "VAD activity callback emits SpeechActivityEvent bytes");
    rac_vad_component_destroy(energy_vad);
    return 0;
}

struct VoiceCapture {
    std::vector<runanywhere::v1::VoiceEvent> events;
};

void voice_callback(const uint8_t* data, size_t size, void* user_data) {
    auto* capture = static_cast<VoiceCapture*>(user_data);
    runanywhere::v1::VoiceEvent event;
    if (event.ParseFromArray(data, static_cast<int>(size))) {
        capture->events.push_back(event);
    }
}

bool saw_turn_kind(const VoiceCapture& capture,
                   runanywhere::v1::TurnLifecycleEventKind kind) {
    for (const auto& event : capture.events) {
        if (event.has_turn_lifecycle() && event.turn_lifecycle().kind() == kind) {
            return true;
        }
    }
    return false;
}

int test_voice_agent_proto_sequence_and_component_failure() {
    rac_voice_agent_handle_t missing = nullptr;
    CHECK(rac_voice_agent_create_standalone(&missing) == RAC_SUCCESS,
          "missing-component voice agent creates");
    VoiceCapture missing_capture;
    CHECK(rac_voice_agent_set_proto_callback(missing, voice_callback, &missing_capture) ==
              RAC_SUCCESS,
          "missing-agent proto callback registers");
    CHECK(rac_voice_agent_initialize(missing, nullptr) == RAC_SUCCESS,
          "missing-agent initializes VAD only");
    const int16_t audio[] = {0, 1, 2, 3};
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_voice_agent_process_voice_turn_proto(missing, audio, sizeof(audio), &out);
    CHECK(rc == RAC_ERROR_NOT_INITIALIZED, "voice agent reports missing STT component");
    bool saw_stt_failure = false;
    for (const auto& event : missing_capture.events) {
        if (event.has_session_error() && event.session_error().has_failed_component() &&
            event.session_error().failed_component() == "stt") {
            saw_stt_failure = true;
        }
    }
    CHECK(saw_stt_failure, "voice agent emits component failure VoiceEvent");
    rac_proto_buffer_free(&out);
    rac_voice_agent_destroy(missing);

    rac_voice_agent_handle_t agent = nullptr;
    CHECK(rac_voice_agent_create_standalone(&agent) == RAC_SUCCESS, "voice agent creates");
    VoiceCapture capture;
    CHECK(rac_voice_agent_set_proto_callback(agent, voice_callback, &capture) == RAC_SUCCESS,
          "voice-agent proto callback registers");
    CHECK(rac_voice_agent_load_stt_model(agent, "mock-stt", "mock-stt", "Mock STT") ==
              RAC_SUCCESS,
          "voice-agent STT loads");
    CHECK(rac_voice_agent_load_llm_model(agent, "mock-llm", "mock-llm", "Mock LLM") ==
              RAC_SUCCESS,
          "voice-agent LLM loads");
    CHECK(rac_voice_agent_load_tts_voice(agent, "mock-tts", "mock-voice", "Mock Voice") ==
              RAC_SUCCESS,
          "voice-agent TTS loads");
    CHECK(rac_voice_agent_initialize_with_loaded_models(agent) == RAC_SUCCESS,
          "voice-agent initializes with loaded models");

    rac_proto_buffer_init(&out);
    rc = rac_voice_agent_component_states_proto(agent, &out);
    runanywhere::v1::VoiceAgentComponentStates states;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &states), "voice component states parse");
    CHECK(states.ready(), "voice component states report ready");
    rac_proto_buffer_free(&out);

    rac_proto_buffer_init(&out);
    rc = rac_voice_agent_process_voice_turn_proto(agent, audio, sizeof(audio), &out);
    runanywhere::v1::VoiceAgentResult result;
    CHECK(rc == RAC_SUCCESS && parse_buffer(out, &result), "VoiceAgentResult parses");
    CHECK(result.transcription() == "hello mock", "voice turn transcription matches");
    CHECK(result.assistant_response() == "assistant mock", "voice turn response matches");
    CHECK(result.has_final_state() && result.final_state().ready(),
          "voice turn final state is ready");
    CHECK(saw_turn_kind(capture, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_STARTED),
          "voice turn emits started event");
    CHECK(saw_turn_kind(capture,
                        runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL),
          "voice turn emits transcription final event");
    CHECK(saw_turn_kind(capture, runanywhere::v1::TURN_LIFECYCLE_EVENT_KIND_COMPLETED),
          "voice turn emits completed event");
    rac_proto_buffer_free(&out);
    rac_voice_agent_destroy(agent);
    return 0;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_speech_proto_abi\n");
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: speech proto ABI tests (no protobuf)\n");
    return 0;
#else
    install_mock_plugin();
    test_parse_failure_and_missing_component();
    test_mocked_stt();
    test_mocked_tts();
    test_mocked_vad_and_activity();
    test_voice_agent_proto_sequence_and_component_failure();
    rac_plugin_unregister("llamacpp");
    rac_plugin_unregister("onnx");
    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
