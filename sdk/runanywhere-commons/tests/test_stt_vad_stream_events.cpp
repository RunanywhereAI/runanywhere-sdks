/**
 * @file test_stt_vad_stream_events.cpp
 * @brief Focused generated STT/VAD stream-event payload coverage.
 */

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "features/stt/rac_stt_stream_internal.h"
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
    std::string model_id;
};

int g_fallback_transcribe_count = 0;
size_t g_fallback_last_audio_size = 0;
std::string g_fallback_last_model_id;

template <typename T>
bool serialize(const T& message, std::vector<uint8_t>* out) {
    out->resize(message.ByteSizeLong());
    return out->empty() || message.SerializeToArray(out->data(), static_cast<int>(out->size()));
}

template <typename Predicate>
bool wait_until(Predicate&& predicate,
                std::chrono::milliseconds timeout = std::chrono::seconds(2)) {
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    while (!predicate()) {
        if (std::chrono::steady_clock::now() >= deadline) {
            return false;
        }
        std::this_thread::yield();
    }
    return true;
}

rac_result_t mock_stt_create(const char*, const char*, void** out_impl) {
    *out_impl = new MockStt();
    return RAC_SUCCESS;
}

rac_result_t mock_stt_initialize(void* impl, const char* model_id) {
    auto* mock = static_cast<MockStt*>(impl);
    mock->initialized = true;
    mock->model_id = model_id ? model_id : "";
    return RAC_SUCCESS;
}

rac_result_t mock_stt_stream(void* impl, const void* audio_data, size_t audio_size,
                             const rac_stt_options_t*, rac_stt_stream_callback_t callback,
                             void* user_data) {
    if (!impl || !audio_data || audio_size == 0 || !callback) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    ++g_fallback_transcribe_count;
    g_fallback_last_audio_size = audio_size;
    g_fallback_last_model_id = static_cast<MockStt*>(impl)->model_id;
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

    struct ReentrantComponentDestroy {
        rac_handle_t component = nullptr;
        std::atomic<bool> attempted{false};
    } reentrant_destroy{.component = stt};
    auto reentrant_destroy_callback = [](const uint8_t*, size_t, void* user_data) {
        auto* context = static_cast<ReentrantComponentDestroy*>(user_data);
        bool expected = false;
        if (context->attempted.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) {
            rac_stt_component_destroy(context->component);
        }
    };
    CHECK(rac_stt_component_transcribe_stream_proto(
              stt, audio, sizeof(audio), options_bytes.data(), options_bytes.size(),
              reentrant_destroy_callback, &reentrant_destroy) == RAC_SUCCESS,
          "reentrant component destroy is refused without deadlocking its active operation");
    CHECK(reentrant_destroy.attempted.load(std::memory_order_acquire) &&
              rac_stt_component_is_loaded(stt) == RAC_TRUE,
          "reentrant destroy leaves the component alive for explicit later teardown");

    rac_stt_component_destroy(stt);
    return 0;
}

int test_stt_one_shot_fallback_endpoint_and_final_flush() {
    install_mock_stt_plugin();
    (void)rac_plugin_unregister("cpp-persistent-stream-stt");
    g_fallback_transcribe_count = 0;
    g_fallback_last_audio_size = 0;

    rac_handle_t stt = nullptr;
    CHECK(rac_stt_component_create(&stt) == RAC_SUCCESS, "fallback STT component creates");
    CHECK(rac_stt_component_load_model(stt, "fallback-stt", "fallback-stt", "Fallback STT") ==
              RAC_SUCCESS,
          "fallback STT model loads");

    std::vector<runanywhere::v1::STTStreamEvent> events;
    auto callback = [](const uint8_t* data, size_t size, void* user_data) {
        auto* out = static_cast<std::vector<runanywhere::v1::STTStreamEvent>*>(user_data);
        runanywhere::v1::STTStreamEvent event;
        if (event.ParseFromArray(data, static_cast<int>(size))) {
            out->push_back(event);
        }
    };
    CHECK(rac_stt_set_stream_proto_callback(stt, callback, &events) == RAC_SUCCESS,
          "fallback stream callback registers");

    runanywhere::v1::STTOptions options;
    options.set_language(runanywhere::v1::STT_LANGUAGE_EN);
    std::vector<uint8_t> options_bytes;
    CHECK(serialize(options, &options_bytes), "fallback STTOptions serializes");

    uint64_t session_id = 0;
    CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                     &session_id) == RAC_SUCCESS,
          "fallback stream session starts");
    std::vector<int16_t> speech(1600, 12000);  // 100 ms at 16 kHz
    for (int i = 0; i < 3; ++i) {
        CHECK(rac_stt_stream_feed_audio_proto(session_id,
                                              reinterpret_cast<const uint8_t*>(speech.data()),
                                              speech.size() * sizeof(int16_t)) == RAC_SUCCESS,
              "sub-window fallback feed succeeds");
    }
    CHECK(g_fallback_transcribe_count == 0,
          "one-shot fallback does not infer on individual 100 ms chunks");
    CHECK(rac_stt_stream_stop_proto(session_id) == RAC_SUCCESS,
          "fallback stream stop final-flushes buffered speech");
    CHECK(g_fallback_transcribe_count == 1,
          "fallback stop runs exactly one transcription for the utterance");
    CHECK(g_fallback_last_audio_size >= speech.size() * sizeof(int16_t) * 3,
          "fallback final flush contains the accumulated speech window");

    g_fallback_transcribe_count = 0;
    events.clear();
    CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                     &session_id) == RAC_SUCCESS,
          "fallback endpoint session starts");
    for (int i = 0; i < 3; ++i) {
        (void)rac_stt_stream_feed_audio_proto(session_id,
                                              reinterpret_cast<const uint8_t*>(speech.data()),
                                              speech.size() * sizeof(int16_t));
    }
    std::vector<int16_t> silence(1600, 0);
    for (int i = 0; i < 8; ++i) {
        (void)rac_stt_stream_feed_audio_proto(session_id,
                                              reinterpret_cast<const uint8_t*>(silence.data()),
                                              silence.size() * sizeof(int16_t));
    }
    CHECK(g_fallback_transcribe_count == 1,
          "one-shot fallback infers once after the speech endpoint");
    CHECK(!events.empty() && events.back().kind() == runanywhere::v1::STT_STREAM_EVENT_KIND_FINAL,
          "fallback endpoint emits a final transcript event");
    CHECK(rac_stt_stream_stop_proto(session_id) == RAC_SUCCESS,
          "endpointed fallback session stops cleanly");
    CHECK(g_fallback_transcribe_count == 1,
          "fallback stop does not duplicate an already-final utterance");

    // Endpoint timing is expressed in milliseconds, not in a fixed number of
    // 16 kHz bytes. Exercise both sides of the default so a future hard-coded
    // frame size cannot make 48 kHz end 3x early or 8 kHz fail to reach the
    // minimum-speech window.
    for (const int32_t sample_rate : {8000, 48000}) {
        runanywhere::v1::STTOptions rate_options;
        rate_options.set_language(runanywhere::v1::STT_LANGUAGE_EN);
        rate_options.set_audio_format(runanywhere::v1::AUDIO_FORMAT_PCM_S16LE);
        rate_options.set_sample_rate(sample_rate);
        std::vector<uint8_t> rate_options_bytes;
        const std::string rate_label = std::to_string(sample_rate) + " Hz";
        CHECK(serialize(rate_options, &rate_options_bytes),
              (rate_label + " STTOptions serializes").c_str());

        g_fallback_transcribe_count = 0;
        CHECK(rac_stt_stream_start_proto(stt, rate_options_bytes.data(), rate_options_bytes.size(),
                                         &session_id) == RAC_SUCCESS,
              (rate_label + " fallback session starts").c_str());
        std::vector<int16_t> rate_speech(static_cast<size_t>(sample_rate / 10), 12000);
        std::vector<int16_t> rate_silence(static_cast<size_t>(sample_rate / 10), 0);
        for (int i = 0; i < 3; ++i) {
            CHECK(rac_stt_stream_feed_audio_proto(
                      session_id, reinterpret_cast<const uint8_t*>(rate_speech.data()),
                      rate_speech.size() * sizeof(int16_t)) == RAC_SUCCESS,
                  (rate_label + " speech frame accepted").c_str());
        }
        for (int i = 0; i < 7; ++i) {
            CHECK(rac_stt_stream_feed_audio_proto(
                      session_id, reinterpret_cast<const uint8_t*>(rate_silence.data()),
                      rate_silence.size() * sizeof(int16_t)) == RAC_SUCCESS,
                  (rate_label + " pre-endpoint silence accepted").c_str());
        }
        CHECK(g_fallback_transcribe_count == 0,
              (rate_label + " does not endpoint before 800 ms silence").c_str());
        CHECK(rac_stt_stream_feed_audio_proto(session_id,
                                              reinterpret_cast<const uint8_t*>(rate_silence.data()),
                                              rate_silence.size() * sizeof(int16_t)) == RAC_SUCCESS,
              (rate_label + " endpoint silence accepted").c_str());
        CHECK(g_fallback_transcribe_count == 1,
              (rate_label + " endpoints after exactly 800 ms silence").c_str());
        CHECK(rac_stt_stream_stop_proto(session_id) == RAC_SUCCESS,
              (rate_label + " fallback session stops").c_str());
    }

    // Stop snapshots a pending fallback utterance before admitting the
    // one-shot provider call. Pause at that exact boundary and let cancel win;
    // pending audio must be dropped without entering the provider.
    struct StopFlushAdmissionProbe {
        std::mutex mutex;
        std::condition_variable cv;
        bool reached = false;
        bool release = false;
    } stop_flush_probe;
    auto stop_flush_hook = [](uint64_t, void* user_data) {
        auto* probe = static_cast<StopFlushAdmissionProbe*>(user_data);
        std::unique_lock<std::mutex> lock(probe->mutex);
        probe->reached = true;
        probe->cv.notify_all();
        probe->cv.wait(lock, [&] { return probe->release; });
    };

    g_fallback_transcribe_count = 0;
    events.clear();
    CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                     &session_id) == RAC_SUCCESS,
          "cancel-before-flush fallback session starts");
    for (int i = 0; i < 3; ++i) {
        CHECK(rac_stt_stream_feed_audio_proto(session_id,
                                              reinterpret_cast<const uint8_t*>(speech.data()),
                                              speech.size() * sizeof(int16_t)) == RAC_SUCCESS,
              "cancel-before-flush speech buffers");
    }
    rac::stt::set_stop_flush_admission_test_hook(stop_flush_hook, &stop_flush_probe);
    std::atomic<rac_result_t> stop_rc{RAC_ERROR_INTERNAL};
    std::atomic<rac_result_t> cancel_rc{RAC_ERROR_INTERNAL};
    std::thread stop_thread(
        [&] { stop_rc.store(rac_stt_stream_stop_proto(session_id), std::memory_order_release); });
    {
        std::unique_lock<std::mutex> lock(stop_flush_probe.mutex);
        CHECK(stop_flush_probe.cv.wait_for(lock, std::chrono::seconds(2),
                                           [&] { return stop_flush_probe.reached; }),
              "stop reaches fallback provider-admission boundary");
    }
    std::thread cancel_thread([&] {
        cancel_rc.store(rac_stt_stream_cancel_proto(session_id), std::memory_order_release);
    });
    CHECK(wait_until(
              [&] { return rac::stt::stream_session_cancel_requested_for_testing(session_id); }),
          "cancel wins before fallback provider admission");
    {
        std::lock_guard<std::mutex> lock(stop_flush_probe.mutex);
        stop_flush_probe.release = true;
    }
    stop_flush_probe.cv.notify_all();
    stop_thread.join();
    cancel_thread.join();
    rac::stt::set_stop_flush_admission_test_hook(nullptr, nullptr);
    CHECK(stop_rc.load(std::memory_order_acquire) == RAC_SUCCESS &&
              cancel_rc.load(std::memory_order_acquire) == RAC_SUCCESS,
          "concurrent stop and cancel both complete successfully");
    CHECK(g_fallback_transcribe_count == 0,
          "cancel drops pending fallback audio before provider admission");
    CHECK(events.empty(), "cancelled pending fallback audio emits no transcript events");

    g_fallback_transcribe_count = 0;
    for (const auto format : {runanywhere::v1::AUDIO_FORMAT_MP3, runanywhere::v1::AUDIO_FORMAT_OGG,
                              runanywhere::v1::AUDIO_FORMAT_M4A}) {
        runanywhere::v1::STTOptions compressed_options;
        compressed_options.set_audio_format(format);
        compressed_options.set_sample_rate(16000);
        std::vector<uint8_t> compressed_options_bytes;
        CHECK(serialize(compressed_options, &compressed_options_bytes),
              "compressed fallback STTOptions serializes");
        CHECK(rac_stt_stream_start_proto(stt, compressed_options_bytes.data(),
                                         compressed_options_bytes.size(),
                                         &session_id) == RAC_SUCCESS,
              "compressed fallback session starts");
        events.clear();
        const uint8_t container_bytes[] = {0x49, 0x44, 0x33, 0x04};
        CHECK(
            rac_stt_stream_feed_audio_proto(session_id, container_bytes, sizeof(container_bytes)) ==
                RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED,
            "one-shot fallback rejects container bytes with precise format error");
        CHECK(events.size() == 1 &&
                  events.front().kind() == runanywhere::v1::STT_STREAM_EVENT_KIND_ERROR &&
                  events.front().error_code() == RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED,
              "rejected container feed emits only the precise error event");
        CHECK(rac_stt_stream_stop_proto(session_id) == RAC_SUCCESS,
              "rejected compressed fallback session stops cleanly");
        CHECK(g_fallback_transcribe_count == 0,
              "rejected compressed fallback never invokes transcription");
    }

    (void)rac_stt_unset_stream_proto_callback(stt);
    rac_stt_component_destroy(stt);
    (void)rac_plugin_unregister("cpp-stream-event-stt");
    return 0;
}

int test_stt_fallback_reload_cancels_buffered_session() {
    install_mock_stt_plugin();
    (void)rac_plugin_unregister("cpp-persistent-stream-stt");
    g_fallback_transcribe_count = 0;
    g_fallback_last_audio_size = 0;
    g_fallback_last_model_id.clear();

    rac_handle_t stt = nullptr;
    CHECK(rac_stt_component_create(&stt) == RAC_SUCCESS, "reload-test STT component creates");
    CHECK(rac_stt_component_load_model(stt, "fallback-model-a", "fallback-model-a",
                                       "Fallback Model A") == RAC_SUCCESS,
          "reload-test first fallback model loads");

    runanywhere::v1::STTOptions options;
    options.set_audio_format(runanywhere::v1::AUDIO_FORMAT_PCM_S16LE);
    options.set_sample_rate(16000);
    std::vector<uint8_t> options_bytes;
    CHECK(serialize(options, &options_bytes), "reload-test STTOptions serializes");

    uint64_t old_session_id = 0;
    CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                     &old_session_id) == RAC_SUCCESS,
          "reload-test fallback session starts on model A");
    std::vector<int16_t> speech(1600, 12000);
    for (int i = 0; i < 3; ++i) {
        CHECK(rac_stt_stream_feed_audio_proto(old_session_id,
                                              reinterpret_cast<const uint8_t*>(speech.data()),
                                              speech.size() * sizeof(int16_t)) == RAC_SUCCESS,
              "reload-test buffers model-A speech");
    }
    CHECK(g_fallback_transcribe_count == 0,
          "reload-test buffered speech has not reached model A yet");

    CHECK(rac_stt_component_load_model(stt, "fallback-model-b", "fallback-model-b",
                                       "Fallback Model B") == RAC_SUCCESS,
          "component reload cancels the buffered model-A session");
    CHECK(g_fallback_transcribe_count == 0,
          "reload cancellation never retargets model-A audio to model B");
    CHECK(rac_stt_stream_feed_audio_proto(
              old_session_id, reinterpret_cast<const uint8_t*>(speech.data()),
              speech.size() * sizeof(int16_t)) == RAC_ERROR_INVALID_ARGUMENT,
          "model reload invalidates the old fallback session id");
    CHECK(rac_stt_stream_stop_proto(old_session_id) == RAC_ERROR_INVALID_ARGUMENT,
          "old fallback session cannot flush after model reload");

    uint64_t new_session_id = 0;
    CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                     &new_session_id) == RAC_SUCCESS,
          "new fallback session starts after model reload");
    for (int i = 0; i < 3; ++i) {
        CHECK(rac_stt_stream_feed_audio_proto(new_session_id,
                                              reinterpret_cast<const uint8_t*>(speech.data()),
                                              speech.size() * sizeof(int16_t)) == RAC_SUCCESS,
              "new fallback session buffers model-B speech");
    }
    CHECK(rac_stt_stream_stop_proto(new_session_id) == RAC_SUCCESS,
          "new fallback session flushes normally");
    CHECK(g_fallback_transcribe_count == 1 && g_fallback_last_model_id == "fallback-model-b",
          "only new-session audio is transcribed by model B");

    rac_stt_component_destroy(stt);
    (void)rac_plugin_unregister("cpp-stream-event-stt");
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

struct BlockingStreamProbe {
    std::mutex mutex;
    std::condition_variable cv;
    bool block_feed = false;
    bool feed_entered = false;
    bool release_feed = false;
    bool feed_exited = false;
    bool destroy_called = false;
    bool destroy_before_feed_exit = false;
    bool emit_second_callback = false;

    void reset(bool block = false, bool emit_second = false) {
        std::lock_guard<std::mutex> lock(mutex);
        block_feed = block;
        feed_entered = false;
        release_feed = false;
        feed_exited = false;
        destroy_called = false;
        destroy_before_feed_exit = false;
        emit_second_callback = emit_second;
    }
};

BlockingStreamProbe g_blocking_stream;

struct BlockingServiceDestroyProbe {
    std::mutex mutex;
    std::condition_variable cv;
    bool block_destroy = false;
    bool destroy_entered = false;
    bool release_destroy = false;

    void reset(bool block = false) {
        std::lock_guard<std::mutex> lock(mutex);
        block_destroy = block;
        destroy_entered = false;
        release_destroy = false;
    }
};

BlockingServiceDestroyProbe g_service_destroy;

struct BlockingComponentInfoProbe {
    std::mutex mutex;
    std::condition_variable cv;
    bool block_info = false;
    bool info_entered = false;
    bool release_info = false;

    void reset(bool block = false) {
        std::lock_guard<std::mutex> lock(mutex);
        block_info = block;
        info_entered = false;
        release_info = false;
    }
};

BlockingComponentInfoProbe g_component_info;

struct BlockingLifecycleGateProbe {
    std::mutex mutex;
    std::condition_variable cv;
    bool entered = false;
    bool release = false;

    void reset() {
        std::lock_guard<std::mutex> lock(mutex);
        entered = false;
        release = false;
    }
};

BlockingLifecycleGateProbe g_lifecycle_gate;

rac_result_t mock_persistent_stt_create(const char*, const char*, void** out_impl) {
    *out_impl = &g_stream_state;  // shared singleton for the test
    return RAC_SUCCESS;
}

rac_result_t mock_persistent_stt_initialize(void*, const char*) {
    return RAC_SUCCESS;
}

rac_result_t mock_persistent_stt_info(void*, rac_stt_info_t* out_info) {
    {
        std::unique_lock<std::mutex> lock(g_component_info.mutex);
        g_component_info.info_entered = true;
        g_component_info.cv.notify_all();
        if (g_component_info.block_info) {
            g_component_info.cv.wait(lock, [] { return g_component_info.release_info; });
        }
    }
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
    bool emit_second = false;
    {
        std::unique_lock<std::mutex> lock(g_blocking_stream.mutex);
        g_blocking_stream.feed_entered = true;
        g_blocking_stream.cv.notify_all();
        if (g_blocking_stream.block_feed) {
            g_blocking_stream.cv.wait(lock, [] { return g_blocking_stream.release_feed; });
        }
        emit_second = g_blocking_stream.emit_second_callback;
    }
    g_stream_state.feed_count++;
    if (callback) {
        callback("mock-partial", RAC_FALSE, user_data);
        if (emit_second) {
            callback("late-partial", RAC_FALSE, user_data);
        }
    }
    {
        std::lock_guard<std::mutex> lock(g_blocking_stream.mutex);
        g_blocking_stream.feed_exited = true;
        g_blocking_stream.cv.notify_all();
    }
    return RAC_SUCCESS;
}

rac_result_t mock_persistent_stt_stream_destroy(void* /*impl*/, rac_handle_t stream_handle) {
    {
        std::lock_guard<std::mutex> lock(g_blocking_stream.mutex);
        g_blocking_stream.destroy_called = true;
        g_blocking_stream.destroy_before_feed_exit = !g_blocking_stream.feed_exited;
        g_blocking_stream.cv.notify_all();
    }
    if (stream_handle == g_stream_state.last_stream) {
        g_stream_state.destroy_count++;
    }
    return RAC_SUCCESS;
}

void mock_persistent_stt_destroy(void* /*impl*/) {
    // Pointed at the static MockStreamState above — do not delete.
    std::unique_lock<std::mutex> lock(g_service_destroy.mutex);
    g_service_destroy.destroy_entered = true;
    g_service_destroy.cv.notify_all();
    if (g_service_destroy.block_destroy) {
        g_service_destroy.cv.wait(lock, [] { return g_service_destroy.release_destroy; });
    }
}

rac_stt_service_ops_t g_persistent_stt_ops{};
rac_engine_vtable_t g_persistent_stt_vtable{};

void install_persistent_stt_plugin() {
    g_stream_state = MockStreamState{};
    g_blocking_stream.reset();
    g_service_destroy.reset();
    g_component_info.reset();

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

    // Non-PCM bytes are rejected before the persistent backend is created or
    // any session accounting begins. OGG/M4A previously fell through to PCM.
    runanywhere::v1::STTOptions compressed_options;
    compressed_options.set_audio_format(runanywhere::v1::AUDIO_FORMAT_M4A);
    std::vector<uint8_t> compressed_options_bytes;
    CHECK(serialize(compressed_options, &compressed_options_bytes),
          "persistent compressed STTOptions serializes");
    uint64_t compressed_session_id = 0;
    CHECK(rac_stt_stream_start_proto(stt, compressed_options_bytes.data(),
                                     compressed_options_bytes.size(),
                                     &compressed_session_id) == RAC_SUCCESS,
          "persistent compressed stream session starts");
    const uint8_t fake_m4a[] = {0x00, 0x00, 0x00, 0x18, 'f', 't', 'y', 'p'};
    const int events_before_rejection = proto_events;
    CHECK(rac_stt_stream_feed_audio_proto(compressed_session_id, fake_m4a, sizeof(fake_m4a)) ==
              RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED,
          "persistent stream rejects non-PCM before backend creation");
    CHECK(g_stream_state.create_count == 0 && g_stream_state.feed_count == 0,
          "rejected persistent input never reaches backend stream slots");
    CHECK(proto_events == events_before_rejection + 1,
          "rejected persistent input emits only its error callback");
    CHECK(rac_stt_stream_stop_proto(compressed_session_id) == RAC_SUCCESS,
          "rejected persistent session stops without completion work");

    // Feed 100 chunks of 1ms audio at 16 kHz: 16 samples per chunk, Int16 PCM.
    const size_t kChunksToFeed = 100;
    const size_t kSamplesPerChunk = 16;
    const int pcm_events_before = proto_events;
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
    CHECK(std::cmp_equal(proto_events - pcm_events_before, kChunksToFeed),
          "every chunk emits a partial STTStreamEvent");

    CHECK(rac_stt_stream_stop_proto(session_id) == RAC_SUCCESS, "stream session stops");
    CHECK(g_stream_state.destroy_count == 1, "stream_destroy invoked exactly once on session stop");

    (void)rac_stt_unset_stream_proto_callback(stt);
    rac_stt_component_destroy(stt);
    (void)rac_plugin_unregister("cpp-persistent-stream-stt");
    return 0;
}

int test_stt_persistent_stream_termination_races() {
    install_persistent_stt_plugin();
    (void)rac_plugin_unregister("cpp-stream-event-stt");

    rac_handle_t stt = nullptr;
    CHECK(rac_stt_component_create(&stt) == RAC_SUCCESS, "race-test STT component creates");
    CHECK(rac_stt_component_load_model(stt, "mock-persistent-race-stt", "mock-persistent-race-stt",
                                       "Mock Persistent Race STT") == RAC_SUCCESS,
          "race-test STT model loads");

    runanywhere::v1::STTOptions options;
    options.set_audio_format(runanywhere::v1::AUDIO_FORMAT_PCM_S16LE);
    options.set_sample_rate(16000);
    std::vector<uint8_t> options_bytes;
    CHECK(serialize(options, &options_bytes), "race-test STTOptions serializes");
    const std::vector<int16_t> chunk(160, 1200);

    struct CountingCallback {
        std::atomic<int> events{0};
    } counting;
    auto count_callback = [](const uint8_t*, size_t, void* user_data) {
        static_cast<CountingCallback*>(user_data)->events.fetch_add(1, std::memory_order_acq_rel);
    };
    CHECK(rac_stt_set_stream_proto_callback(stt, count_callback, &counting) == RAC_SUCCESS,
          "race-test callback registers");

    const auto run_external_termination = [&](bool cancel) {
        // Cancellation is fail-closed for new events, but it deliberately
        // drains an already accepted provider feed rather than claiming to
        // interrupt backend execution. Stop has the same provider-lifetime
        // requirement while preserving callbacks from that accepted feed.
        g_blocking_stream.reset(/*block=*/true, /*emit_second=*/false);
        counting.events.store(0, std::memory_order_release);
        uint64_t session_id = 0;
        CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                         &session_id) == RAC_SUCCESS,
              cancel ? "cancel-race session starts" : "stop-race session starts");

        std::atomic<rac_result_t> feed_rc{RAC_ERROR_INTERNAL};
        std::thread feed_thread([&] {
            feed_rc.store(rac_stt_stream_feed_audio_proto(
                              session_id, reinterpret_cast<const uint8_t*>(chunk.data()),
                              chunk.size() * sizeof(int16_t)),
                          std::memory_order_release);
        });
        {
            std::unique_lock<std::mutex> lock(g_blocking_stream.mutex);
            CHECK(g_blocking_stream.cv.wait_for(lock, std::chrono::seconds(2),
                                                [] { return g_blocking_stream.feed_entered; }),
                  cancel ? "cancel-race provider feed blocks" : "stop-race provider feed blocks");
        }

        const int destroys_before = g_stream_state.destroy_count;
        std::atomic<bool> termination_returned{false};
        std::atomic<rac_result_t> termination_rc{RAC_ERROR_INTERNAL};
        std::thread termination_thread([&] {
            termination_rc.store(cancel ? rac_stt_stream_cancel_proto(session_id)
                                        : rac_stt_stream_stop_proto(session_id),
                                 std::memory_order_release);
            termination_returned.store(true, std::memory_order_release);
        });
        CHECK(wait_until([&] {
                  return rac::stt::stream_session_termination_started_for_testing(session_id);
              }),
              cancel ? "cancel-race termination enters before feed release"
                     : "stop-race termination enters before feed release");
        CHECK(!termination_returned.load(std::memory_order_acquire),
              cancel ? "cancel waits for the in-flight provider feed"
                     : "stop waits for the in-flight provider feed");
        {
            std::lock_guard<std::mutex> lock(g_blocking_stream.mutex);
            CHECK(!g_blocking_stream.destroy_called,
                  cancel ? "cancel does not destroy a live provider handle"
                         : "stop does not destroy a live provider handle");
            g_blocking_stream.release_feed = true;
        }
        g_blocking_stream.cv.notify_all();
        feed_thread.join();
        termination_thread.join();

        CHECK(feed_rc.load(std::memory_order_acquire) == RAC_SUCCESS,
              "accepted in-flight provider feed completes");
        CHECK(termination_rc.load(std::memory_order_acquire) == RAC_SUCCESS,
              cancel ? "cancel-race termination succeeds" : "stop-race termination succeeds");
        {
            std::lock_guard<std::mutex> lock(g_blocking_stream.mutex);
            CHECK(g_blocking_stream.destroy_called && !g_blocking_stream.destroy_before_feed_exit,
                  "provider handle is destroyed only after feed exit");
        }
        CHECK(g_stream_state.destroy_count == destroys_before + 1,
              "provider handle is destroyed exactly once");
        CHECK(counting.events.load(std::memory_order_acquire) == (cancel ? 0 : 1),
              cancel ? "cancel drops provider callbacks while draining"
                     : "stop drains provider callbacks before returning");
        const int events_after_return = counting.events.load(std::memory_order_acquire);
        CHECK(rac_stt_stream_feed_audio_proto(
                  session_id, reinterpret_cast<const uint8_t*>(chunk.data()),
                  chunk.size() * sizeof(int16_t)) == RAC_ERROR_INVALID_ARGUMENT,
              "closed session rejects later feeds");
        CHECK(counting.events.load(std::memory_order_acquire) == events_after_return,
              "no events are emitted after termination returns");
    };

    run_external_termination(/*cancel=*/false);
    run_external_termination(/*cancel=*/true);

    struct ReentrantCallback {
        std::atomic<int> events{0};
        std::atomic<rac_result_t> termination_rc{RAC_ERROR_INTERNAL};
        uint64_t session_id = 0;
        bool cancel = false;
    } reentrant;
    auto reentrant_callback = [](const uint8_t*, size_t, void* user_data) {
        auto* context = static_cast<ReentrantCallback*>(user_data);
        const int event_number = context->events.fetch_add(1, std::memory_order_acq_rel) + 1;
        if (event_number == 1) {
            context->termination_rc.store(context->cancel
                                              ? rac_stt_stream_cancel_proto(context->session_id)
                                              : rac_stt_stream_stop_proto(context->session_id),
                                          std::memory_order_release);
        }
    };

    const auto run_reentrant_termination = [&](bool cancel) {
        g_blocking_stream.reset(/*block=*/false, /*emit_second=*/true);
        reentrant.events.store(0, std::memory_order_release);
        reentrant.termination_rc.store(RAC_ERROR_INTERNAL, std::memory_order_release);
        reentrant.cancel = cancel;
        CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                         &reentrant.session_id) == RAC_SUCCESS,
              cancel ? "reentrant-cancel session starts" : "reentrant-stop session starts");
        CHECK(rac_stt_set_stream_proto_callback(stt, reentrant_callback, &reentrant) == RAC_SUCCESS,
              "reentrant termination callback registers");
        const int destroys_before = g_stream_state.destroy_count;
        CHECK(rac_stt_stream_feed_audio_proto(reentrant.session_id,
                                              reinterpret_cast<const uint8_t*>(chunk.data()),
                                              chunk.size() * sizeof(int16_t)) == RAC_SUCCESS,
              cancel ? "reentrant cancel does not deadlock provider feed"
                     : "reentrant stop does not deadlock provider feed");
        CHECK(reentrant.termination_rc.load(std::memory_order_acquire) == RAC_SUCCESS,
              "reentrant termination call succeeds");
        CHECK(reentrant.events.load(std::memory_order_acquire) == 1,
              "reentrant termination suppresses later provider callbacks");
        CHECK(g_stream_state.destroy_count == destroys_before + 1,
              "deferred reentrant cleanup destroys provider exactly once");
        {
            std::lock_guard<std::mutex> lock(g_blocking_stream.mutex);
            CHECK(!g_blocking_stream.destroy_before_feed_exit,
                  "reentrant cleanup waits until provider feed exits");
        }
        const int events_after_return = reentrant.events.load(std::memory_order_acquire);
        CHECK(rac_stt_stream_feed_audio_proto(
                  reentrant.session_id, reinterpret_cast<const uint8_t*>(chunk.data()),
                  chunk.size() * sizeof(int16_t)) == RAC_ERROR_INVALID_ARGUMENT,
              "reentrantly closed session rejects later feeds");
        CHECK(reentrant.events.load(std::memory_order_acquire) == events_after_return,
              "reentrant termination emits no event after return");
    };

    run_reentrant_termination(/*cancel=*/false);
    run_reentrant_termination(/*cancel=*/true);

    struct ReentrantLifecycleCallback {
        rac_handle_t component = nullptr;
        std::atomic<int> events{0};
        std::atomic<rac_result_t> unload_rc{RAC_ERROR_INTERNAL};
    } lifecycle_callback{.component = stt};
    auto reentrant_unload_callback = [](const uint8_t*, size_t, void* user_data) {
        auto* context = static_cast<ReentrantLifecycleCallback*>(user_data);
        const int event_number = context->events.fetch_add(1, std::memory_order_acq_rel) + 1;
        if (event_number == 1) {
            context->unload_rc.store(rac_stt_component_unload(context->component),
                                     std::memory_order_release);
        }
    };
    g_blocking_stream.reset(/*block=*/false, /*emit_second=*/true);
    uint64_t lifecycle_session_id = 0;
    CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                     &lifecycle_session_id) == RAC_SUCCESS,
          "reentrant-lifecycle session starts");
    CHECK(rac_stt_set_stream_proto_callback(stt, reentrant_unload_callback, &lifecycle_callback) ==
              RAC_SUCCESS,
          "reentrant-lifecycle callback registers");
    CHECK(rac_stt_stream_feed_audio_proto(lifecycle_session_id,
                                          reinterpret_cast<const uint8_t*>(chunk.data()),
                                          chunk.size() * sizeof(int16_t)) == RAC_SUCCESS,
          "reentrant lifecycle request does not deadlock provider callback");
    CHECK(lifecycle_callback.unload_rc.load(std::memory_order_acquire) == RAC_ERROR_SERVICE_BUSY,
          "reentrant unload is refused before it can wait for its own stream");
    CHECK(lifecycle_callback.events.load(std::memory_order_acquire) == 2,
          "refused reentrant unload leaves the active stream intact");
    CHECK(rac_stt_stream_cancel_proto(lifecycle_session_id) == RAC_SUCCESS,
          "reentrant-lifecycle session cancels externally after callback return");

    struct SelfQuiesceCallback {
        rac_handle_t component = nullptr;
        std::atomic<int> events{0};
        std::atomic<bool> quiesce_returned{false};
    } self_quiesce{.component = stt};
    auto self_quiesce_callback = [](const uint8_t*, size_t, void* user_data) {
        auto* context = static_cast<SelfQuiesceCallback*>(user_data);
        context->events.fetch_add(1, std::memory_order_acq_rel);
        (void)rac_stt_unset_stream_proto_callback(context->component);
        rac_stt_proto_quiesce();
        context->quiesce_returned.store(true, std::memory_order_release);
    };
    g_blocking_stream.reset(/*block=*/false, /*emit_second=*/false);
    uint64_t self_quiesce_session_id = 0;
    CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                     &self_quiesce_session_id) == RAC_SUCCESS,
          "self-quiesce session starts");
    CHECK(rac_stt_set_stream_proto_callback(stt, self_quiesce_callback, &self_quiesce) ==
              RAC_SUCCESS,
          "self-quiesce callback registers");
    CHECK(rac_stt_stream_feed_audio_proto(self_quiesce_session_id,
                                          reinterpret_cast<const uint8_t*>(chunk.data()),
                                          chunk.size() * sizeof(int16_t)) == RAC_SUCCESS,
          "callback self-unset and quiesce returns without deadlock");
    CHECK(self_quiesce.events.load(std::memory_order_acquire) == 1 &&
              self_quiesce.quiesce_returned.load(std::memory_order_acquire),
          "reentrant quiesce waits other dispatches and returns on its own frame");
    CHECK(rac_stt_stream_cancel_proto(self_quiesce_session_id) == RAC_SUCCESS,
          "self-quiesce session cancels after callback return");

    (void)rac_stt_unset_stream_proto_callback(stt);
    rac_stt_component_destroy(stt);
    (void)rac_plugin_unregister("cpp-persistent-stream-stt");
    return 0;
}

int test_stt_component_owns_stream_lifecycle() {
    install_persistent_stt_plugin();
    (void)rac_plugin_unregister("cpp-stream-event-stt");

    rac_handle_t stt = nullptr;
    CHECK(rac_stt_component_create(&stt) == RAC_SUCCESS, "lifecycle-test STT component creates");
    CHECK(rac_stt_component_load_model(stt, "lifecycle-model-a", "lifecycle-model-a",
                                       "Lifecycle Model A") == RAC_SUCCESS,
          "lifecycle-test first model loads");

    runanywhere::v1::STTOptions options;
    options.set_audio_format(runanywhere::v1::AUDIO_FORMAT_PCM_S16LE);
    options.set_sample_rate(16000);
    std::vector<uint8_t> options_bytes;
    CHECK(serialize(options, &options_bytes), "lifecycle-test STTOptions serializes");
    const std::vector<int16_t> chunk(160, 1200);

    const auto start_and_feed = [&](uint64_t* out_session_id, const char* start_label,
                                    const char* feed_label) {
        CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                         out_session_id) == RAC_SUCCESS,
              start_label);
        CHECK(rac_stt_stream_feed_audio_proto(*out_session_id,
                                              reinterpret_cast<const uint8_t*>(chunk.data()),
                                              chunk.size() * sizeof(int16_t)) == RAC_SUCCESS,
              feed_label);
    };

    uint64_t cleanup_session_id = 0;
    start_and_feed(&cleanup_session_id, "cleanup-test persistent session starts",
                   "cleanup-test persistent session creates provider");
    CHECK(rac_stt_component_cleanup(stt) == RAC_SUCCESS,
          "component cleanup drains and resets the persistent stream");
    CHECK(g_stream_state.destroy_count == 1,
          "component cleanup destroys the persistent provider exactly once");
    CHECK(rac_stt_stream_feed_audio_proto(
              cleanup_session_id, reinterpret_cast<const uint8_t*>(chunk.data()),
              chunk.size() * sizeof(int16_t)) == RAC_ERROR_INVALID_ARGUMENT,
          "component cleanup invalidates the prior session id");
    CHECK(rac_stt_stream_cancel_proto(cleanup_session_id) == RAC_ERROR_INVALID_ARGUMENT,
          "cleaned-up session cannot be cancelled twice");

    CHECK(rac_stt_component_load_model(stt, "lifecycle-model-b", "lifecycle-model-b",
                                       "Lifecycle Model B") == RAC_SUCCESS,
          "lifecycle-test model reloads after cleanup");
    uint64_t unload_session_id = 0;
    start_and_feed(&unload_session_id, "unload-test persistent session starts",
                   "unload-test persistent session creates provider");

    // Hold service destruction after the stream has drained. The lifecycle
    // start gate must remain closed for this entire interval, so a racing start
    // cannot escape the initial session snapshot and bind itself to whichever
    // model is loaded next.
    g_service_destroy.reset(/*block=*/true);
    std::atomic<rac_result_t> unload_rc{RAC_ERROR_INTERNAL};
    std::thread unload_thread(
        [&] { unload_rc.store(rac_stt_component_unload(stt), std::memory_order_release); });
    {
        std::unique_lock<std::mutex> lock(g_service_destroy.mutex);
        CHECK(g_service_destroy.cv.wait_for(lock, std::chrono::seconds(2),
                                            [] { return g_service_destroy.destroy_entered; }),
              "component unload reaches service destruction after stream drain");
    }
    uint64_t racing_session_id = 999;
    CHECK(rac_stt_stream_start_proto(stt, options_bytes.data(), options_bytes.size(),
                                     &racing_session_id) == RAC_ERROR_SERVICE_BUSY,
          "stream start is rejected while component unload owns the lifecycle gate");
    CHECK(racing_session_id == 0, "rejected racing start clears its session id output");
    {
        std::lock_guard<std::mutex> lock(g_service_destroy.mutex);
        g_service_destroy.release_destroy = true;
    }
    g_service_destroy.cv.notify_all();
    unload_thread.join();

    CHECK(unload_rc.load(std::memory_order_acquire) == RAC_SUCCESS,
          "component unload completes without a persistent-stream pin deadlock");
    CHECK(g_stream_state.destroy_count == 2,
          "component unload destroys its persistent provider exactly once");
    CHECK(rac_stt_stream_feed_audio_proto(
              unload_session_id, reinterpret_cast<const uint8_t*>(chunk.data()),
              chunk.size() * sizeof(int16_t)) == RAC_ERROR_INVALID_ARGUMENT,
          "component unload invalidates the prior session id");

    g_service_destroy.reset();
    CHECK(rac_stt_component_load_model(stt, "lifecycle-model-c", "lifecycle-model-c",
                                       "Lifecycle Model C") == RAC_SUCCESS,
          "lifecycle-test model reloads after unload");
    uint64_t destroy_session_id = 0;
    start_and_feed(&destroy_session_id, "destroy-test persistent session starts",
                   "destroy-test persistent session creates provider");

    std::atomic<int> stale_callback_events{0};
    auto stale_callback = [](const uint8_t*, size_t, void* user_data) {
        static_cast<std::atomic<int>*>(user_data)->fetch_add(1, std::memory_order_acq_rel);
    };
    CHECK(rac_stt_set_stream_proto_callback(stt, stale_callback, &stale_callback_events) ==
              RAC_SUCCESS,
          "destroy-race callback registers before teardown");
    g_service_destroy.reset(/*block=*/true);
    std::thread destroy_thread([&] { rac_stt_component_destroy(stt); });
    {
        std::unique_lock<std::mutex> lock(g_service_destroy.mutex);
        CHECK(g_service_destroy.cv.wait_for(lock, std::chrono::seconds(2),
                                            [] { return g_service_destroy.destroy_entered; }),
              "component destroy reaches provider cleanup with admission closed");
    }
    CHECK(rac_stt_set_stream_proto_callback(stt, stale_callback, &stale_callback_events) ==
              RAC_ERROR_SERVICE_BUSY,
          "callback registration is rejected while component destroy is in progress");
    {
        std::lock_guard<std::mutex> lock(g_service_destroy.mutex);
        g_service_destroy.release_destroy = true;
    }
    g_service_destroy.cv.notify_all();
    destroy_thread.join();

    CHECK(g_stream_state.destroy_count == 3,
          "component destroy drains and destroys its persistent provider exactly once");
    CHECK(rac_stt_stream_feed_audio_proto(
              destroy_session_id, reinterpret_cast<const uint8_t*>(chunk.data()),
              chunk.size() * sizeof(int16_t)) == RAC_ERROR_INVALID_ARGUMENT,
          "component destroy invalidates the prior session id");
    CHECK(rac_stt_stream_stop_proto(destroy_session_id) == RAC_ERROR_INVALID_ARGUMENT,
          "destroyed component session cannot be stopped twice");
    CHECK(rac_stt_set_stream_proto_callback(stt, stale_callback, &stale_callback_events) ==
              RAC_ERROR_INVALID_HANDLE,
          "destroyed component handle cannot reinsert a callback slot");

    const rac_handle_t destroyed_handle = stt;
    CHECK(!rac::stt::has_stream_callback_for_testing(destroyed_handle),
          "component destroy erases the callback for the exact retired handle key");
    rac_handle_t replacement = nullptr;
    g_service_destroy.reset();
    CHECK(rac_stt_component_create(&replacement) == RAC_SUCCESS,
          "replacement STT component creates after destroy");
    CHECK(rac_stt_component_load_model(replacement, "lifecycle-model-d", "lifecycle-model-d",
                                       "Lifecycle Model D") == RAC_SUCCESS,
          "replacement STT model loads");
    uint64_t replacement_session_id = 0;
    CHECK(rac_stt_stream_start_proto(replacement, options_bytes.data(), options_bytes.size(),
                                     &replacement_session_id) == RAC_SUCCESS,
          "replacement persistent session starts without callback registration");
    CHECK(rac_stt_stream_feed_audio_proto(replacement_session_id,
                                          reinterpret_cast<const uint8_t*>(chunk.data()),
                                          chunk.size() * sizeof(int16_t)) == RAC_SUCCESS,
          "replacement persistent session feeds without stale callback dispatch");
    CHECK(stale_callback_events.load(std::memory_order_acquire) == 0,
          "replacement component does not inherit stale callback/user_data");
    CHECK(rac_stt_stream_cancel_proto(replacement_session_id) == RAC_SUCCESS,
          "replacement persistent session cancels cleanly");
    rac_stt_component_destroy(replacement);

    // A non-stream component call holds a lifetime lease even while blocked in
    // the provider. Destroy must close admission, reject a later public call,
    // and wait until that lease returns before freeing the component.
    rac_handle_t lifetime_component = nullptr;
    CHECK(rac_stt_component_create(&lifetime_component) == RAC_SUCCESS,
          "lifetime-race STT component creates");
    CHECK(rac_stt_component_load_model(lifetime_component, "lifetime-model", "lifetime-model",
                                       "Lifetime Model") == RAC_SUCCESS,
          "lifetime-race STT model loads");
    g_component_info.reset(/*block=*/true);
    std::atomic<bool> admission_closed{false};
    auto admission_hook = [](rac_handle_t, void* user_data) {
        static_cast<std::atomic<bool>*>(user_data)->store(true, std::memory_order_release);
    };
    rac::stt::set_component_admission_closed_test_hook(admission_hook, &admission_closed);
    std::atomic<bool> info_returned{false};
    std::atomic<bool> info_supported{false};
    std::thread info_thread([&] {
        info_supported.store(rac_stt_component_supports_streaming(lifetime_component) == RAC_TRUE,
                             std::memory_order_release);
        info_returned.store(true, std::memory_order_release);
    });
    {
        std::unique_lock<std::mutex> lock(g_component_info.mutex);
        CHECK(g_component_info.cv.wait_for(lock, std::chrono::seconds(2),
                                           [] { return g_component_info.info_entered; }),
              "public component operation blocks inside provider with a lifetime lease");
    }
    std::atomic<bool> lifetime_destroy_returned{false};
    std::thread lifetime_destroy_thread([&] {
        rac_stt_component_destroy(lifetime_component);
        lifetime_destroy_returned.store(true, std::memory_order_release);
    });
    CHECK(wait_until([&] { return admission_closed.load(std::memory_order_acquire); }),
          "component destroy closes public-operation admission");
    CHECK(!info_returned.load(std::memory_order_acquire) &&
              !lifetime_destroy_returned.load(std::memory_order_acquire),
          "component destroy waits for the admitted provider operation");
    rac_stt_config_t rejected_config = RAC_STT_CONFIG_DEFAULT;
    CHECK(rac_stt_component_configure(lifetime_component, &rejected_config) ==
              RAC_ERROR_INVALID_HANDLE,
          "public component call is rejected after destroy closes admission");
    {
        std::lock_guard<std::mutex> lock(g_component_info.mutex);
        g_component_info.release_info = true;
    }
    g_component_info.cv.notify_all();
    info_thread.join();
    lifetime_destroy_thread.join();
    rac::stt::set_component_admission_closed_test_hook(nullptr, nullptr);
    CHECK(info_supported.load(std::memory_order_acquire) &&
              lifetime_destroy_returned.load(std::memory_order_acquire),
          "destroy completes only after the admitted component operation drains");

    // Pin a lifecycle operation after it has acquired the component lease but
    // before it takes the stream gate. Destroy must drain that lease before it
    // takes the same gate; taking the gates in the opposite order deadlocks.
    rac_handle_t gate_order_component = nullptr;
    CHECK(rac_stt_component_create(&gate_order_component) == RAC_SUCCESS,
          "gate-order STT component creates");
    CHECK(rac_stt_component_load_model(gate_order_component, "gate-order-model", "gate-order-model",
                                       "Gate Order Model") == RAC_SUCCESS,
          "gate-order STT model loads");
    g_lifecycle_gate.reset();
    auto lifecycle_gate_hook = [](rac_handle_t, void* user_data) {
        auto* probe = static_cast<BlockingLifecycleGateProbe*>(user_data);
        std::unique_lock<std::mutex> lock(probe->mutex);
        probe->entered = true;
        probe->cv.notify_all();
        probe->cv.wait(lock, [&] { return probe->release; });
    };
    rac::stt::set_component_lifecycle_gate_test_hook(lifecycle_gate_hook, &g_lifecycle_gate);
    std::atomic<rac_result_t> gate_order_unload_rc{RAC_ERROR_INTERNAL};
    std::thread gate_order_unload_thread([&] {
        gate_order_unload_rc.store(rac_stt_component_unload(gate_order_component),
                                   std::memory_order_release);
    });
    {
        std::unique_lock<std::mutex> lock(g_lifecycle_gate.mutex);
        CHECK(g_lifecycle_gate.cv.wait_for(lock, std::chrono::seconds(2),
                                           [] { return g_lifecycle_gate.entered; }),
              "lifecycle operation holds its lease before requesting the stream gate");
    }
    std::atomic<bool> gate_order_admission_closed{false};
    rac::stt::set_component_admission_closed_test_hook(admission_hook,
                                                       &gate_order_admission_closed);
    std::atomic<bool> gate_order_destroy_returned{false};
    std::thread gate_order_destroy_thread([&] {
        rac_stt_component_destroy(gate_order_component);
        gate_order_destroy_returned.store(true, std::memory_order_release);
    });
    CHECK(wait_until([&] { return gate_order_admission_closed.load(std::memory_order_acquire); }),
          "destroy closes admission while the lifecycle operation is admitted");
    CHECK(!gate_order_destroy_returned.load(std::memory_order_acquire),
          "destroy waits for the admitted lifecycle operation before taking its stream gate");
    {
        std::lock_guard<std::mutex> lock(g_lifecycle_gate.mutex);
        g_lifecycle_gate.release = true;
    }
    g_lifecycle_gate.cv.notify_all();
    gate_order_unload_thread.join();
    gate_order_destroy_thread.join();
    rac::stt::set_component_lifecycle_gate_test_hook(nullptr, nullptr);
    rac::stt::set_component_admission_closed_test_hook(nullptr, nullptr);
    CHECK(gate_order_unload_rc.load(std::memory_order_acquire) == RAC_SUCCESS &&
              gate_order_destroy_returned.load(std::memory_order_acquire),
          "lifecycle operation and destroy complete without a gate-order deadlock");

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
        test_stt_one_shot_fallback_endpoint_and_final_flush();
        test_stt_fallback_reload_cancels_buffered_session();
        test_stt_persistent_stream_handle();
        test_stt_persistent_stream_termination_races();
        test_stt_component_owns_stream_lifecycle();
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
