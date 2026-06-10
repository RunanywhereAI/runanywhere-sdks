/**
 * @file test_stt_vad_stream_events.cpp
 * @brief Focused generated STT/VAD stream-event payload coverage.
 */

#include <cstdio>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_stream.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "stt_options.pb.h"
#include "vad_options.pb.h"
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                       \
    do {                                                                                         \
        ++test_count;                                                                            \
        if (!(cond)) {                                                                           \
            ++fail_count;                                                                        \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__, #cond); \
        } else {                                                                                 \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        }                                                                                        \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

struct MockStt {
    bool initialized{false};
};

template <typename T>
bool serialize(const T& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    return out->empty() || message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

rac_result_t mock_stt_create(const char*, const char*, void** out_impl) {
    *out_impl = new MockStt();
    return RAC_SUCCESS;
}

rac_result_t mock_stt_initialize(void* impl, const char*) {
    static_cast<MockStt*>(impl)->initialized = true;
    return RAC_SUCCESS;
}

rac_result_t mock_stt_stream(void* impl, const void* audio_data, size_t audio_size,
                             const rac_stt_options_t*, rac_stt_stream_callback_t callback,
                             void* user_data) {
    if (!impl || !audio_data || audio_size == 0 || !callback) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    callback("draft", RAC_FALSE, user_data);
    callback("final text", RAC_TRUE, user_data);
    return RAC_SUCCESS;
}

rac_result_t mock_stt_info(void*, rac_stt_info_t* out_info) {
    out_info->is_ready = RAC_TRUE;
    out_info->current_model = "stream-event-mock-stt";
    out_info->supports_streaming = RAC_TRUE;
    return RAC_SUCCESS;
}

void mock_stt_destroy(void* impl) {
    delete static_cast<MockStt*>(impl);
}

rac_stt_service_ops_t g_stt_ops{};
rac_engine_vtable_t g_stt_vtable{};
const rac_runtime_id_t k_cpu_runtime[] = {RAC_RUNTIME_CPU};

void install_mock_stt_plugin() {
    g_stt_ops = {};
    g_stt_ops.create = mock_stt_create;
    g_stt_ops.initialize = mock_stt_initialize;
    g_stt_ops.transcribe_stream = mock_stt_stream;
    g_stt_ops.get_info = mock_stt_info;
    g_stt_ops.destroy = mock_stt_destroy;

    g_stt_vtable = {};
    g_stt_vtable.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    g_stt_vtable.metadata.name = "cpp-stream-event-stt";
    g_stt_vtable.metadata.display_name = "CPP Stream Event Mock STT";
    g_stt_vtable.metadata.engine_version = "0.0.0";
    g_stt_vtable.metadata.priority = 10000;
    g_stt_vtable.metadata.runtimes = k_cpu_runtime;
    g_stt_vtable.metadata.runtimes_count = 1;
    g_stt_vtable.stt_ops = &g_stt_ops;

    (void)rac_plugin_unregister("cpp-stream-event-stt");
    CHECK(rac_plugin_register(&g_stt_vtable) == RAC_SUCCESS, "mock STT plugin registers");
}

int test_stt_stream_events() {
    install_mock_stt_plugin();

    rac_handle_t stt = nullptr;
    CHECK(rac_stt_component_create(&stt) == RAC_SUCCESS, "STT component creates");
    CHECK(rac_stt_component_load_model(stt, "mock-stt", "mock-stt", "Mock STT") == RAC_SUCCESS,
          "STT model loads");

    runanywhere::v1::STTOptions options;
    options.set_language(runanywhere::v1::STT_LANGUAGE_EN);
    std::vector<uint8_t> options_bytes;
    CHECK(serialize(options, &options_bytes), "STTOptions serializes");

    std::vector<runanywhere::v1::STTStreamEvent> events;
    auto callback = [](const uint8_t* data, size_t size, void* user_data) {
        auto* out = static_cast<std::vector<runanywhere::v1::STTStreamEvent>*>(user_data);
        runanywhere::v1::STTStreamEvent event;
        if (event.ParseFromArray(data, static_cast<int>(size))) {
            out->push_back(event);
        }
    };

    const int16_t audio[] = {0, 1, 2, 3};
    const rac_result_t rc = rac_stt_component_transcribe_stream_proto(
        stt, audio, sizeof(audio), options_bytes.data(), options_bytes.size(), callback, &events);
    CHECK(rc == RAC_SUCCESS, "STT stream proto returns success");
    CHECK(events.size() == 3, "STT stream emits started, partial, final events");
    if (events.size() == 3) {
        const std::string request_id = events[0].request_id();
        CHECK(events[0].kind() == runanywhere::v1::STT_STREAM_EVENT_KIND_STARTED,
              "STT first event is started");
        CHECK(events[1].kind() == runanywhere::v1::STT_STREAM_EVENT_KIND_PARTIAL,
              "STT second event is PARTIAL kind");
        CHECK(events[1].has_partial(), "STT second event has partial payload");
        CHECK(events[1].partial().text() == "draft", "STT second event partial text matches");
        CHECK(events[2].kind() == runanywhere::v1::STT_STREAM_EVENT_KIND_FINAL,
              "STT final event is FINAL kind");
        CHECK(events[2].has_partial(), "STT final event has partial payload");
        CHECK(events[2].partial().is_final(), "STT final event partial marked final");
        CHECK(events[2].has_final_output(), "STT final event has final output");
        CHECK(events[2].final_output().text() == "final text",
              "STT final event final output text matches");
        CHECK(events[0].seq() == 1, "STT stream first seq is 1");
        CHECK(events[1].seq() == 2, "STT stream second seq is 2");
        CHECK(events[2].seq() == 3, "STT stream third seq is 3");
        CHECK(!request_id.empty(), "STT stream request_id is non-empty");
        CHECK(events[1].request_id() == request_id, "STT stream request_id stable on second event");
        CHECK(events[2].request_id() == request_id, "STT stream request_id stable on third event");
    }

    rac_stt_component_destroy(stt);
    return 0;
}

// -----------------------------------------------------------------------------
// Persistent per-session streaming handles.
//
// Installs a mock plugin that implements the new stream_create /
// stream_feed_audio_chunk / stream_destroy vtable slots and counts each
// call. The test starts a stream session and feeds 100 audio chunks via
// rac_stt_stream_feed_audio_proto; we assert the backend was created
// exactly once and torn down exactly once — this is the whole point of
// the persistent-stream fix (previously Sherpa allocated state per chunk).
// -----------------------------------------------------------------------------

struct MockStreamState {
    int create_count = 0;
    int feed_count = 0;
    int destroy_count = 0;
    int transcribe_stream_count = 0;
    rac_handle_t last_stream = nullptr;
};

MockStreamState g_stream_state;

rac_result_t mock_persistent_stt_create(const char*, const char*, void** out_impl) {
    *out_impl = &g_stream_state;  // shared singleton for the test
    return RAC_SUCCESS;
}

rac_result_t mock_persistent_stt_initialize(void*, const char*) {
    return RAC_SUCCESS;
}

rac_result_t mock_persistent_stt_info(void*, rac_stt_info_t* out_info) {
    out_info->is_ready = RAC_TRUE;
    out_info->current_model = "persistent-stream-mock-stt";
    out_info->supports_streaming = RAC_TRUE;
    return RAC_SUCCESS;
}

rac_result_t mock_persistent_stt_transcribe_stream(void*, const void*, size_t,
                                                   const rac_stt_options_t*,
                                                   rac_stt_stream_callback_t, void*) {
    // Counted so we can assert the per-chunk fallback path was NOT taken.
    g_stream_state.transcribe_stream_count++;
    return RAC_SUCCESS;
}

rac_result_t mock_persistent_stt_stream_create(void* /*impl*/, const rac_stt_options_t* /*options*/,
                                               rac_handle_t* out_stream_handle) {
    g_stream_state.create_count++;
    // Use a sentinel non-null pointer so commons recognizes the stream
    // as valid. The mock never dereferences it.
    // NOLINTNEXTLINE(performance-no-int-to-ptr): intentional sentinel handle for mock stream
    g_stream_state.last_stream = reinterpret_cast<rac_handle_t>(static_cast<intptr_t>(0xdeadbeef));
    *out_stream_handle = g_stream_state.last_stream;
    return RAC_SUCCESS;
}

rac_result_t mock_persistent_stt_stream_feed(void* /*impl*/, rac_handle_t stream_handle,
                                             const int16_t* samples, size_t count,
                                             rac_stt_stream_callback_t callback, void* user_data) {
    (void)samples;
    (void)count;
    if (stream_handle != g_stream_state.last_stream) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    g_stream_state.feed_count++;
    if (callback) {
        callback("mock-partial", RAC_FALSE, user_data);
    }
    return RAC_SUCCESS;
}

rac_result_t mock_persistent_stt_stream_destroy(void* /*impl*/, rac_handle_t stream_handle) {
    if (stream_handle == g_stream_state.last_stream) {
        g_stream_state.destroy_count++;
    }
    return RAC_SUCCESS;
}

void mock_persistent_stt_destroy(void* /*impl*/) {
    // Pointed at the static MockStreamState above — do not delete.
}

rac_stt_service_ops_t g_persistent_stt_ops{};
rac_engine_vtable_t g_persistent_stt_vtable{};

void install_persistent_stt_plugin() {
    g_stream_state = MockStreamState{};

    g_persistent_stt_ops = {};
    g_persistent_stt_ops.create = mock_persistent_stt_create;
    g_persistent_stt_ops.initialize = mock_persistent_stt_initialize;
    g_persistent_stt_ops.transcribe_stream = mock_persistent_stt_transcribe_stream;
    g_persistent_stt_ops.get_info = mock_persistent_stt_info;
    g_persistent_stt_ops.destroy = mock_persistent_stt_destroy;
    g_persistent_stt_ops.stream_create = mock_persistent_stt_stream_create;
    g_persistent_stt_ops.stream_feed_audio_chunk = mock_persistent_stt_stream_feed;
    g_persistent_stt_ops.stream_destroy = mock_persistent_stt_stream_destroy;

    g_persistent_stt_vtable = {};
    g_persistent_stt_vtable.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    g_persistent_stt_vtable.metadata.name = "cpp-persistent-stream-stt";
    g_persistent_stt_vtable.metadata.display_name = "CPP Persistent Stream Mock STT";
    g_persistent_stt_vtable.metadata.engine_version = "0.0.0";
    g_persistent_stt_vtable.metadata.priority = 20000;  // beat the simpler mock above
    g_persistent_stt_vtable.metadata.runtimes = k_cpu_runtime;
    g_persistent_stt_vtable.metadata.runtimes_count = 1;
    g_persistent_stt_vtable.stt_ops = &g_persistent_stt_ops;

    (void)rac_plugin_unregister("cpp-persistent-stream-stt");
    CHECK(rac_plugin_register(&g_persistent_stt_vtable) == RAC_SUCCESS,
          "persistent-stream STT plugin registers");
}

int test_stt_persistent_stream_handle() {
    install_persistent_stt_plugin();
    // Keep the simpler mock (which doesn't implement stream_create) out of
    // the registry's way so rac_plugin_find consistently picks the
    // persistent plugin for this test.
    (void)rac_plugin_unregister("cpp-stream-event-stt");

    rac_handle_t stt = nullptr;
    CHECK(rac_stt_component_create(&stt) == RAC_SUCCESS, "STT component creates");
    CHECK(rac_stt_component_load_model(stt, "mock-persistent-stt", "mock-persistent-stt",
                                       "Mock Persistent STT") == RAC_SUCCESS,
          "STT model loads for persistent plugin");

    // Register a proto callback so dispatch_stt_stream_event has somewhere to go.
    auto count_callback = [](const uint8_t*, size_t, void* ud) {
        int* n = static_cast<int*>(ud);
        ++(*n);
    };
    int proto_events = 0;
    CHECK(rac_stt_set_stream_proto_callback(stt, count_callback, &proto_events) == RAC_SUCCESS,
          "stream proto callback registers");

    runanywhere::v1::STTOptions options;
    options.set_language(runanywhere::v1::STT_LANGUAGE_EN);
    std::vector<uint8_t> options_bytes;
    CHECK(serialize(options, &options_bytes), "persistent STTOptions serializes");

    uint64_t session_id = 0;
    CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                     &session_id) == RAC_SUCCESS,
          "stream session starts");
    CHECK(session_id != 0, "stream session id is non-zero");

    // Feed 100 chunks of 1ms audio at 16 kHz: 16 samples per chunk, Int16 PCM.
    const size_t kChunksToFeed = 100;
    const size_t kSamplesPerChunk = 16;
    std::vector<int16_t> chunk(kSamplesPerChunk, 0);
    for (size_t i = 0; i < kChunksToFeed; ++i) {
        rac_result_t feed_rc = rac_stt_stream_feed_audio_proto(
            session_id, reinterpret_cast<const uint8_t*>(chunk.data()),
            chunk.size() * sizeof(int16_t));
        if (feed_rc != RAC_SUCCESS) {
            std::fprintf(stderr, "  feed chunk %zu returned %d\n", i, feed_rc);
            break;
        }
    }

    CHECK(g_stream_state.create_count == 1, "stream_create invoked exactly once across 100 chunks");
    CHECK(std::cmp_equal(g_stream_state.feed_count, kChunksToFeed),
          "stream_feed_audio_chunk invoked once per chunk");
    CHECK(g_stream_state.transcribe_stream_count == 0,
          "legacy transcribe_stream fallback NOT engaged when slot is wired");
    CHECK(std::cmp_equal(proto_events, kChunksToFeed),
          "every chunk emits a partial STTStreamEvent");

    CHECK(rac_stt_stream_stop_proto(session_id) == RAC_SUCCESS, "stream session stops");
    CHECK(g_stream_state.destroy_count == 1, "stream_destroy invoked exactly once on session stop");

    (void)rac_stt_unset_stream_proto_callback(stt);
    rac_stt_component_destroy(stt);
    (void)rac_plugin_unregister("cpp-persistent-stream-stt");
    return 0;
}

int test_vad_activity_stream_event() {
    rac_handle_t vad = nullptr;
    CHECK(rac_vad_component_create(&vad) == RAC_SUCCESS, "VAD component creates");

    runanywhere::v1::VADConfiguration config;
    config.set_sample_rate(16000);
    config.set_frame_length_ms(100);
    config.set_threshold(0.01f);
    std::vector<uint8_t> config_bytes;
    CHECK(serialize(config, &config_bytes), "VADConfiguration serializes");
    CHECK(rac_vad_component_configure_proto(vad, config_bytes.data(), config_bytes.size()) ==
              RAC_SUCCESS,
          "VAD configure proto succeeds");

    std::vector<runanywhere::v1::VADStreamEvent> events;
    auto callback = [](const uint8_t* data, size_t size, void* user_data) {
        auto* out = static_cast<std::vector<runanywhere::v1::VADStreamEvent>*>(user_data);
        runanywhere::v1::VADStreamEvent event;
        if (event.ParseFromArray(data, static_cast<int>(size))) {
            out->push_back(event);
        }
    };
    CHECK(rac_vad_component_set_activity_proto_callback(vad, callback, &events) == RAC_SUCCESS,
          "VAD stream-event activity callback registers");
    CHECK(rac_vad_component_initialize(vad) == RAC_SUCCESS, "VAD initializes");

    std::vector<float> silence(1600, 0.0f);
    std::vector<float> loud(1600, 0.5f);
    rac_bool_t is_speech = RAC_FALSE;
    for (int i = 0; i < 20; ++i) {
        (void)rac_vad_component_process(vad, silence.data(), silence.size(), &is_speech);
    }
    (void)rac_vad_component_process(vad, loud.data(), loud.size(), &is_speech);

    bool saw_started = false;
    for (const auto& event : events) {
        saw_started = saw_started ||
                      (event.kind() == runanywhere::v1::VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY &&
                       event.has_activity() &&
                       event.activity().event_type() ==
                           runanywhere::v1::SPEECH_ACTIVITY_KIND_SPEECH_STARTED &&
                       event.seq() > 0 && event.timestamp_us() > 0 && !event.request_id().empty());
    }
    CHECK(saw_started, "VAD activity callback emits generated VADStreamEvent");

    rac_vad_component_destroy(vad);
    return 0;
}

#endif

}  // namespace

int main() {
#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: STT/VAD stream event tests (no protobuf)\n");
    return 0;
#else
    try {
        test_stt_stream_events();
        test_stt_persistent_stream_handle();
        test_vad_activity_stream_event();
        if (fail_count != 0) {
            std::fprintf(stderr, "FAILED: %d/%d checks failed\n", fail_count, test_count);
            return 1;
        }
        std::fprintf(stdout, "PASS: %d checks\n", test_count);
        return 0;
    } catch (const std::exception& e) {
        std::fprintf(stderr, "FATAL: %s\n", e.what());
        return 1;
    } catch (...) {
        return 1;
    }
#endif
}
