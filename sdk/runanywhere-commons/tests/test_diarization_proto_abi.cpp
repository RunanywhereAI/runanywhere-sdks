/**
 * @file test_diarization_proto_abi.cpp
 * @brief Diarization proto, lifecycle, persistent-stream, and concurrency ABI tests.
 */

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <future>
#include <limits>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>

#if defined(RAC_HAVE_PROTOBUF)
#include "diarization.pb.h"
#include "model_types.pb.h"
#endif
#include "features/diarization/diarization_internal.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/features/diarization/rac_diarization.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_primitive.h"

namespace {

#if defined(RAC_HAVE_PROTOBUF)

using namespace std::chrono_literals;

int g_checks = 0;
int g_failures = 0;

#define CHECK(condition, label)                                                      \
    do {                                                                             \
        ++g_checks;                                                                  \
        if (condition) {                                                             \
            std::fprintf(stdout, "  ok:   %s\n", label);                             \
        } else {                                                                     \
            ++g_failures;                                                            \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__); \
        }                                                                            \
    } while (0)

struct FakeBackend {
    int unused = 0;
};

std::mutex g_options_mutex;
rac_diarization_options_t g_last_options = RAC_DIARIZATION_OPTIONS_DEFAULT;
size_t g_last_sample_count = 0;
std::atomic<bool> g_emit_invalid_result{false};
std::atomic<int> g_partial_stream_create_calls{0};

struct FakeStream {
    FakeBackend* backend = nullptr;
    std::vector<float> samples;
    rac_diarization_stream_callback_t last_callback = nullptr;
    void* last_user_data = nullptr;
};

std::mutex g_destroy_mutex;
std::condition_variable g_destroy_cv;
bool g_block_destroy = false;
bool g_destroy_entered = false;
bool g_release_destroy = false;

void emit_snapshot(FakeStream* stream, rac_diarization_stream_callback_t callback, void* user_data,
                   int64_t processing_time_ms = 2) {
    char speaker[] = "speaker_0";
    rac_diarization_segment_t segment = {
        .start_ms = 0,
        .end_ms = static_cast<int64_t>(stream->samples.size()),
        .speaker_index = 0,
        .speaker_id = speaker,
    };
    rac_diarization_result_t result = {
        .segments = &segment,
        .segment_count = 1,
        .speaker_count = 1,
        .audio_duration_ms = static_cast<int64_t>(stream->samples.size()),
        .processing_time_ms = processing_time_ms,
        .model_id = nullptr,
    };
    callback(&result, user_data);
}

rac_result_t fake_initialize(void*, const char*) {
    return RAC_SUCCESS;
}

rac_result_t fake_diarize(void* impl, const float*, size_t sample_count,
                          const rac_diarization_options_t* options,
                          rac_diarization_result_t* out_result) {
    if (!impl || !options || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    {
        std::lock_guard<std::mutex> lock(g_options_mutex);
        g_last_options = *options;
        g_last_sample_count = sample_count;
    }
    auto* segments =
        static_cast<rac_diarization_segment_t*>(std::calloc(2, sizeof(rac_diarization_segment_t)));
    if (!segments) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    segments[0] = {
        .start_ms = 0, .end_ms = 300, .speaker_index = 0, .speaker_id = ::strdup("speaker_0")};
    segments[1] = {.start_ms = 250,
                   .end_ms = 500,
                   .speaker_index = g_emit_invalid_result.load(std::memory_order_relaxed) ? 2 : 1,
                   .speaker_id = ::strdup("speaker_1")};
    if (!segments[0].speaker_id || !segments[1].speaker_id) {
        std::free(segments[0].speaker_id);
        std::free(segments[1].speaker_id);
        std::free(segments);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    *out_result = {
        .segments = segments,
        .segment_count = 2,
        .speaker_count = 2,
        .audio_duration_ms = 500,
        .processing_time_ms = 7,
        .model_id = ::strdup("fake-diarizer"),
    };
    return out_result->model_id ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t fake_stream_create(void* impl, const rac_diarization_options_t*,
                                rac_handle_t* out_stream) {
    auto* stream = new (std::nothrow) FakeStream();
    if (!stream) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    stream->backend = static_cast<FakeBackend*>(impl);
    *out_stream = stream;
    return RAC_SUCCESS;
}

rac_result_t fake_stream_feed(void*, rac_handle_t stream_handle, const float* samples,
                              size_t sample_count, rac_diarization_stream_callback_t callback,
                              void* user_data) {
    auto* stream = static_cast<FakeStream*>(stream_handle);
    if (sample_count > 0) {
        stream->samples.insert(stream->samples.end(), samples, samples + sample_count);
    }
    stream->last_callback = callback;
    stream->last_user_data = user_data;
    emit_snapshot(stream, callback, user_data);
    if (sample_count == 0) {
        // A provider is allowed to refine more than once while flushing, but
        // Commons must expose exactly one terminal FINAL event carrying the
        // last refinement, not the first.
        emit_snapshot(stream, callback, user_data, 99);
    }
    return RAC_SUCCESS;
}

rac_result_t fake_stream_destroy(void*, rac_handle_t stream_handle) {
    auto* stream = static_cast<FakeStream*>(stream_handle);
    {
        std::unique_lock<std::mutex> lock(g_destroy_mutex);
        if (g_block_destroy) {
            g_destroy_entered = true;
            g_destroy_cv.notify_all();
            g_destroy_cv.wait(lock, [] { return g_release_destroy; });
        }
    }
    // Adversarial provider behavior during destroy: the Commons cancellation
    // gate must suppress this late callback before user_data can be released.
    if (stream->last_callback) {
        emit_snapshot(stream, stream->last_callback, stream->last_user_data);
    }
    delete stream;
    return RAC_SUCCESS;
}

rac_result_t fake_cleanup(void*) {
    return RAC_SUCCESS;
}
void fake_destroy(void* impl) {
    delete static_cast<FakeBackend*>(impl);
}

rac_result_t fake_create(const char*, const char*, void** out_impl) {
    auto* backend = new (std::nothrow) FakeBackend();
    if (!backend) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    *out_impl = backend;
    return RAC_SUCCESS;
}

rac_result_t partial_stream_create(void*, const rac_diarization_options_t*,
                                   rac_handle_t* out_stream) {
    g_partial_stream_create_calls.fetch_add(1, std::memory_order_relaxed);
    *out_stream = new (std::nothrow) int(1);
    return *out_stream ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t null_stream_create(void*, const rac_diarization_options_t*, rac_handle_t* out_stream) {
    *out_stream = nullptr;
    return RAC_SUCCESS;
}

const rac_diarization_service_ops_t kDiarizationOps = {
    .initialize = fake_initialize,
    .diarize = fake_diarize,
    .stream_create = fake_stream_create,
    .stream_feed_audio_chunk = fake_stream_feed,
    .stream_destroy = fake_stream_destroy,
    .cleanup = fake_cleanup,
    .destroy = fake_destroy,
    .create = fake_create,
};

rac_engine_vtable_t make_fake_vtable() {
    rac_engine_vtable_t vtable{};
    vtable.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    vtable.metadata.name = "fake-diarization";
    vtable.metadata.display_name = "Fake Diarization";
    vtable.metadata.engine_version = "1";
    vtable.metadata.priority = 1000;
    vtable.diarization_ops = &kDiarizationOps;
    return vtable;
}

std::string f32le(float value) {
    uint32_t bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));
    std::string bytes(sizeof(bits), '\0');
    bytes[0] = static_cast<char>(bits & 0xffU);
    bytes[1] = static_cast<char>((bits >> 8U) & 0xffU);
    bytes[2] = static_cast<char>((bits >> 16U) & 0xffU);
    bytes[3] = static_cast<char>((bits >> 24U) & 0xffU);
    return bytes;
}

struct EventCollector {
    std::mutex mutex;
    std::condition_variable cv;
    std::vector<runanywhere::v1::DiarizationStreamEvent> events;
    bool block_updates = false;
    bool update_entered = false;
    bool release_update = false;
};

void collect_event(const uint8_t* bytes, size_t size, void* user_data) {
    auto* collector = static_cast<EventCollector*>(user_data);
    runanywhere::v1::DiarizationStreamEvent event;
    if (!event.ParseFromArray(bytes, static_cast<int>(size))) {
        return;
    }
    std::unique_lock<std::mutex> lock(collector->mutex);
    collector->events.push_back(event);
    if (collector->block_updates &&
        event.kind() == runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_UPDATE) {
        collector->update_entered = true;
        collector->cv.notify_all();
        collector->cv.wait(lock, [&] { return collector->release_update; });
    }
}

size_t event_count(EventCollector* collector) {
    std::lock_guard<std::mutex> lock(collector->mutex);
    return collector->events.size();
}

struct OperationGate {
    std::mutex mutex;
    std::condition_variable cv;
    bool entered = false;
    bool release = false;
};

struct ReentrantQuiesceBarrier {
    std::mutex mutex;
    std::condition_variable cv;
    rac_handle_t component = nullptr;
    int entered = 0;
    int completed = 0;
};

void quiesce_from_two_callbacks(const uint8_t* bytes, size_t size, void* user_data) {
    auto* barrier = static_cast<ReentrantQuiesceBarrier*>(user_data);
    runanywhere::v1::DiarizationStreamEvent event;
    if (!barrier || !event.ParseFromArray(bytes, static_cast<int>(size)) ||
        event.kind() != runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_UPDATE) {
        return;
    }
    {
        std::unique_lock<std::mutex> lock(barrier->mutex);
        ++barrier->entered;
        barrier->cv.notify_all();
        barrier->cv.wait(lock, [&] { return barrier->entered == 2; });
    }
    (void)rac_diarization_unset_stream_proto_callback(barrier->component);
    rac_diarization_proto_quiesce();
    {
        std::lock_guard<std::mutex> lock(barrier->mutex);
        ++barrier->completed;
    }
    barrier->cv.notify_all();
}

void block_admitted_component_operation(rac_handle_t, void* user_data) {
    auto* gate = static_cast<OperationGate*>(user_data);
    std::unique_lock<std::mutex> lock(gate->mutex);
    gate->entered = true;
    gate->cv.notify_all();
    gate->cv.wait(lock, [&] { return gate->release; });
}

bool wait_for_operation_gate(OperationGate* gate) {
    std::unique_lock<std::mutex> lock(gate->mutex);
    return gate->cv.wait_for(lock, 2s, [&] { return gate->entered; });
}

void release_operation_gate(OperationGate* gate) {
    {
        std::lock_guard<std::mutex> lock(gate->mutex);
        gate->release = true;
    }
    gate->cv.notify_all();
}

bool wait_for_component_admission_to_close(rac_handle_t component) {
    const auto deadline = std::chrono::steady_clock::now() + 2s;
    while (std::chrono::steady_clock::now() < deadline) {
        rac_lifecycle_metrics_t metrics{};
        if (rac_diarization_component_get_metrics(component, &metrics) ==
            RAC_ERROR_INVALID_HANDLE) {
            return true;
        }
        std::this_thread::yield();
    }
    return false;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_diarization_proto_abi\n");

#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: diarization proto ABI tests (no protobuf)\n");
    return 0;
#else

    rac_plugin_unregister("fake-diarization");
    rac_engine_vtable_t vtable = make_fake_vtable();
    CHECK(rac_plugin_register(&vtable) == RAC_SUCCESS, "dedicated diarization plugin registers");
    CHECK(rac_plugin_find(RAC_PRIMITIVE_DIARIZE) == &vtable,
          "diarization routes only through DIARIZE");
    CHECK(rac_plugin_find(RAC_PRIMITIVE_TRANSCRIBE) != &vtable,
          "diarization is not routed through STT");
    CHECK(rac_plugin_find(RAC_PRIMITIVE_DETECT_VOICE) != &vtable,
          "diarization is not routed through VAD");
    CHECK(vtable.segmentation_ops == nullptr, "segmentation placeholder remains unavailable");

    // Streaming is an all-or-none provider capability. Reject a partial group
    // before invoking create, otherwise a returned handle could have no
    // destroy path. Also reject the malformed SUCCESS + NULL contract.
    rac_diarization_service_ops_t partial_ops{};
    partial_ops.stream_create = partial_stream_create;
    rac_diarization_service_t partial_service{&partial_ops, nullptr, "partial"};
    rac_handle_t rejected_stream = reinterpret_cast<rac_handle_t>(uintptr_t{1});
    g_partial_stream_create_calls.store(0, std::memory_order_relaxed);
    CHECK(rac_diarization_stream_create(&partial_service, nullptr, &rejected_stream) ==
                  RAC_ERROR_NOT_SUPPORTED &&
              rejected_stream == nullptr &&
              g_partial_stream_create_calls.load(std::memory_order_relaxed) == 0,
          "partial stream op group is rejected before allocating a handle");

    rac_diarization_service_ops_t null_create_ops = kDiarizationOps;
    null_create_ops.stream_create = null_stream_create;
    rac_diarization_service_t null_create_service{&null_create_ops, nullptr, "null-create"};
    CHECK(rac_diarization_stream_create(&null_create_service, nullptr, &rejected_stream) ==
                  RAC_ERROR_INVALID_STATE &&
              rejected_stream == nullptr,
          "stream create rejects provider SUCCESS with a null handle");

    rac_model_category_t category = RAC_MODEL_CATEGORY_UNKNOWN;
    CHECK(rac_model_category_from_proto(10, &category) == RAC_SUCCESS &&
              category == RAC_MODEL_CATEGORY_SPEAKER_DIARIZATION,
          "speaker-diarization category mapping is first class");
    CHECK(rac_model_category_from_proto(11, &category) == RAC_SUCCESS &&
              category == RAC_MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
          "semantic-segmentation category mapping is first class");

    // Exercise the canonical registry-owned lifecycle path, including the
    // handle-less diarization ABI used by platform SDKs.
    rac_model_lifecycle_reset();
    rac_model_registry_handle_t registry = nullptr;
    CHECK(rac_model_registry_create(&registry) == RAC_SUCCESS && registry,
          "canonical lifecycle registry creates");
    if (registry) {
        const auto model_path =
            std::filesystem::temp_directory_path() /
            ("runanywhere-diarization-lifecycle-" +
             std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()) + ".onnx");
        std::ofstream(model_path, std::ios::binary).put('\0');

        runanywhere::v1::ModelInfo model;
        model.set_id("lifecycle.diarization");
        model.set_name("Lifecycle diarization");
        model.set_category(runanywhere::v1::MODEL_CATEGORY_SPEAKER_DIARIZATION);
        model.set_format(runanywhere::v1::MODEL_FORMAT_ONNX);
        model.set_local_path(model_path.string());
        model.set_is_downloaded(true);
        model.set_is_available(true);
        std::string model_bytes;
        CHECK(model.SerializeToString(&model_bytes) &&
                  rac_model_registry_register_proto(
                      registry, reinterpret_cast<const uint8_t*>(model_bytes.data()),
                      model_bytes.size()) == RAC_SUCCESS,
              "canonical lifecycle diarization model registers");

        runanywhere::v1::ModelLoadRequest load_request;
        load_request.set_model_id(model.id());
        std::string load_bytes;
        (void)load_request.SerializeToString(&load_bytes);
        rac_proto_buffer_t lifecycle_output{};
        const rac_result_t load_rc = rac_model_lifecycle_load_proto(
            registry, reinterpret_cast<const uint8_t*>(load_bytes.data()), load_bytes.size(),
            &lifecycle_output);
        runanywhere::v1::ModelLoadResult load_result;
        CHECK(load_rc == RAC_SUCCESS &&
                  load_result.ParseFromArray(lifecycle_output.data,
                                             static_cast<int>(lifecycle_output.size)) &&
                  load_result.success() && load_result.model_id() == model.id(),
              "canonical lifecycle loads the diarization model");
        rac_proto_buffer_free(&lifecycle_output);

        runanywhere::v1::DiarizationRequest lifecycle_request;
        lifecycle_request.set_audio_data(f32le(0.25f) + f32le(-0.25f));
        std::string lifecycle_request_bytes;
        (void)lifecycle_request.SerializeToString(&lifecycle_request_bytes);
        const rac_result_t diarize_rc = rac_diarization_diarize_lifecycle_proto(
            reinterpret_cast<const uint8_t*>(lifecycle_request_bytes.data()),
            lifecycle_request_bytes.size(), &lifecycle_output);
        runanywhere::v1::DiarizationResult lifecycle_result;
        CHECK(diarize_rc == RAC_SUCCESS &&
                  lifecycle_result.ParseFromArray(lifecycle_output.data,
                                                  static_cast<int>(lifecycle_output.size)) &&
                  lifecycle_result.model_id() == "fake-diarizer" &&
                  lifecycle_result.segments_size() == 2,
              "handle-less lifecycle diarization dispatches to the loaded backend");
        rac_proto_buffer_free(&lifecycle_output);

        runanywhere::v1::CurrentModelRequest current_request;
        current_request.set_category(runanywhere::v1::MODEL_CATEGORY_SPEAKER_DIARIZATION);
        current_request.set_include_model_metadata(true);
        std::string current_bytes;
        (void)current_request.SerializeToString(&current_bytes);
        const rac_result_t current_rc = rac_model_lifecycle_current_model_proto(
            reinterpret_cast<const uint8_t*>(current_bytes.data()), current_bytes.size(),
            &lifecycle_output);
        runanywhere::v1::CurrentModelResult current_result;
        CHECK(current_rc == RAC_SUCCESS &&
                  current_result.ParseFromArray(lifecycle_output.data,
                                                static_cast<int>(lifecycle_output.size)) &&
                  current_result.found() && current_result.model_id() == model.id() &&
                  current_result.category() == runanywhere::v1::MODEL_CATEGORY_SPEAKER_DIARIZATION,
              "current-model query reports the loaded diarization model");
        rac_proto_buffer_free(&lifecycle_output);

        runanywhere::v1::ModelUnloadRequest unload_request;
        unload_request.set_model_id(model.id());
        std::string unload_bytes;
        (void)unload_request.SerializeToString(&unload_bytes);
        const rac_result_t unload_rc =
            rac_model_lifecycle_unload_proto(reinterpret_cast<const uint8_t*>(unload_bytes.data()),
                                             unload_bytes.size(), &lifecycle_output);
        runanywhere::v1::ModelUnloadResult unload_result;
        CHECK(unload_rc == RAC_SUCCESS &&
                  unload_result.ParseFromArray(lifecycle_output.data,
                                               static_cast<int>(lifecycle_output.size)) &&
                  unload_result.success() && unload_result.unloaded_model_ids_size() == 1 &&
                  unload_result.unloaded_model_ids(0) == model.id(),
              "canonical lifecycle unloads the diarization model");
        rac_proto_buffer_free(&lifecycle_output);

        rac_model_registry_destroy(registry);
        std::error_code ignored;
        std::filesystem::remove(model_path, ignored);
    }
    rac_model_lifecycle_reset();

    rac_handle_t component = nullptr;
    CHECK(rac_diarization_component_create(&component) == RAC_SUCCESS && component,
          "component creates");
    CHECK(rac_diarization_component_load_model(component, "fake-model", "fake-model",
                                               "Fake model") == RAC_SUCCESS,
          "component lifecycle loads dedicated service");

    // Omitted nonzero-default scalars must retain their C defaults.
    runanywhere::v1::DiarizationRequest request;
    request.set_audio_data(f32le(0.25f) + f32le(-0.25f));
    request.mutable_options();
    std::string request_bytes;
    (void)request.SerializeToString(&request_bytes);
    rac_proto_buffer_t output{};
    CHECK(rac_diarization_component_diarize_proto(
              component, reinterpret_cast<const uint8_t*>(request_bytes.data()),
              request_bytes.size(), &output) == RAC_SUCCESS,
          "offline proto request succeeds with omitted defaults");
    runanywhere::v1::DiarizationResult offline;
    CHECK(offline.ParseFromArray(output.data, static_cast<int>(output.size)) &&
              offline.segments_size() == 2 && offline.speaker_count() == 2,
          "offline result preserves overlapping speaker segments");
    rac_proto_buffer_free(&output);
    {
        std::lock_guard<std::mutex> lock(g_options_mutex);
        CHECK(g_last_options.threshold == 0.5f && g_last_options.sample_rate_hz == 16000 &&
                  g_last_options.channel_count == 1 && g_last_sample_count == 2,
              "omitted scalar options retain canonical defaults");
    }

    // Presence-aware scalar fields distinguish an explicit zero from omission.
    request.mutable_options()->set_threshold(0.0f);
    (void)request.SerializeToString(&request_bytes);
    CHECK(rac_diarization_component_diarize_proto(
              component, reinterpret_cast<const uint8_t*>(request_bytes.data()),
              request_bytes.size(), &output) == RAC_SUCCESS,
          "explicit zero threshold succeeds");
    rac_proto_buffer_free(&output);
    {
        std::lock_guard<std::mutex> lock(g_options_mutex);
        CHECK(g_last_options.threshold == 0.0f,
              "explicit zero threshold is not replaced by the default");
    }

    request.Clear();
    request.set_audio_data(std::string(3, '\0'));
    (void)request.SerializeToString(&request_bytes);
    CHECK(rac_diarization_component_diarize_proto(
              component, reinterpret_cast<const uint8_t*>(request_bytes.data()),
              request_bytes.size(), &output) == RAC_ERROR_INVALID_ARGUMENT,
          "partial F32 frame is rejected");
    rac_proto_buffer_free(&output);

    request.Clear();
    request.set_audio_data(std::string(1, '\0'));
    request.mutable_options()->set_encoding(runanywhere::v1::DIARIZATION_AUDIO_ENCODING_PCM_S16_LE);
    (void)request.SerializeToString(&request_bytes);
    CHECK(rac_diarization_component_diarize_proto(
              component, reinterpret_cast<const uint8_t*>(request_bytes.data()),
              request_bytes.size(), &output) == RAC_ERROR_INVALID_ARGUMENT,
          "partial S16 frame is rejected");
    rac_proto_buffer_free(&output);

    request.Clear();
    request.set_audio_data(f32le(std::numeric_limits<float>::quiet_NaN()));
    (void)request.SerializeToString(&request_bytes);
    CHECK(rac_diarization_component_diarize_proto(
              component, reinterpret_cast<const uint8_t*>(request_bytes.data()),
              request_bytes.size(), &output) == RAC_ERROR_INVALID_ARGUMENT,
          "non-finite F32 audio is rejected");
    rac_proto_buffer_free(&output);

    request.Clear();
    request.set_audio_data(f32le(0.1f) + f32le(0.2f));
    request.mutable_options()->set_channel_count(2);
    (void)request.SerializeToString(&request_bytes);
    CHECK(rac_diarization_component_diarize_proto(
              component, reinterpret_cast<const uint8_t*>(request_bytes.data()),
              request_bytes.size(), &output) == RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED,
          "non-mono input is rejected instead of implicitly downmixed");
    rac_proto_buffer_free(&output);

    request.Clear();
    request.set_audio_data(f32le(0.1f));
    (void)request.SerializeToString(&request_bytes);
    g_emit_invalid_result.store(true, std::memory_order_relaxed);
    CHECK(rac_diarization_component_diarize_proto(
              component, reinterpret_cast<const uint8_t*>(request_bytes.data()),
              request_bytes.size(), &output) == RAC_ERROR_ENCODING_ERROR,
          "out-of-range backend speaker index is rejected");
    g_emit_invalid_result.store(false, std::memory_order_relaxed);
    rac_proto_buffer_free(&output);

    EventCollector collector;
    CHECK(rac_diarization_set_stream_proto_callback(component, collect_event, &collector) ==
              RAC_SUCCESS,
          "stream callback registers");
    uint64_t session = 0;
    CHECK(rac_diarization_stream_start_proto(component, nullptr, 0, &session) == RAC_SUCCESS &&
              session != 0,
          "persistent stream starts and pins the service");
    const std::string chunk = f32le(0.1f) + f32le(0.2f);
    CHECK(rac_diarization_stream_feed_audio_proto(
              session, reinterpret_cast<const uint8_t*>(chunk.data()), chunk.size()) == RAC_SUCCESS,
          "stream accepts canonical PCM chunk");
    CHECK(rac_diarization_stream_stop_proto(session) == RAC_SUCCESS,
          "stream stop flushes and destroys provider session");
    {
        std::lock_guard<std::mutex> lock(collector.mutex);
        CHECK(collector.events.size() == 3, "started/update/final emitted exactly once");
        CHECK(collector.events[0].seq() == 0 && collector.events[1].seq() == 1 &&
                  collector.events[2].seq() == 2,
              "stream sequence is monotonic and session-local");
        CHECK(collector.events[1].kind() == runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_UPDATE &&
                  collector.events[2].kind() ==
                      runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_FINAL &&
                  collector.events[1].result().segments_size() == 1 &&
                  collector.events[2].result().segments_size() == 1 &&
                  collector.events[2].result().processing_time_ms() == 99,
              "one final carries the provider's last flush refinement");
    }

    uint64_t error_session = 0;
    CHECK(rac_diarization_stream_start_proto(component, nullptr, 0, &error_session) == RAC_SUCCESS,
          "error-path stream starts");
    const std::string malformed_chunk(3, '\0');
    CHECK(rac_diarization_stream_feed_audio_proto(
              error_session, reinterpret_cast<const uint8_t*>(malformed_chunk.data()),
              malformed_chunk.size()) == RAC_ERROR_INVALID_ARGUMENT,
          "malformed stream chunk returns its C ABI error");
    {
        std::lock_guard<std::mutex> lock(collector.mutex);
        const auto& error = collector.events.back();
        CHECK(error.kind() == runanywhere::v1::DIARIZATION_STREAM_EVENT_KIND_ERROR &&
                  error.has_error() && error.error().c_abi_code() == RAC_ERROR_INVALID_ARGUMENT,
              "malformed stream chunk emits a session-scoped ERROR event");
    }
    CHECK(rac_diarization_stream_cancel_proto(error_session) == RAC_SUCCESS,
          "error-path stream remains explicitly cancellable");

    // Cancellation closes the event gate before provider destroy, including
    // an adversarial callback made from stream_destroy itself.
    uint64_t cancelled = 0;
    CHECK(rac_diarization_stream_start_proto(component, nullptr, 0, &cancelled) == RAC_SUCCESS,
          "second stream starts");
    const size_t before_cancel = event_count(&collector);
    CHECK(rac_diarization_stream_cancel_proto(cancelled) == RAC_SUCCESS,
          "stream cancellation succeeds");
    CHECK(event_count(&collector) == before_cancel,
          "cancel suppresses final and late provider callbacks");

    // unset + quiesce must wait for a callback already admitted elsewhere.
    EventCollector blocking;
    blocking.block_updates = true;
    CHECK(rac_diarization_set_stream_proto_callback(component, collect_event, &blocking) ==
              RAC_SUCCESS,
          "blocking callback registers");
    uint64_t blocked_session = 0;
    CHECK(rac_diarization_stream_start_proto(component, nullptr, 0, &blocked_session) ==
              RAC_SUCCESS,
          "quiescence test stream starts");
    std::atomic<rac_result_t> blocked_feed_result{RAC_ERROR_INTERNAL};
    std::atomic<bool> blocked_feed_returned{false};
    std::thread feed_thread([&] {
        blocked_feed_result.store(
            rac_diarization_stream_feed_audio_proto(
                blocked_session, reinterpret_cast<const uint8_t*>(chunk.data()), chunk.size()),
            std::memory_order_release);
        blocked_feed_returned.store(true, std::memory_order_release);
    });
    {
        std::unique_lock<std::mutex> lock(blocking.mutex);
        CHECK(blocking.cv.wait_for(lock, 2s, [&] { return blocking.update_entered; }),
              "callback entered on feed thread");
    }
    CHECK(!blocked_feed_returned.load(std::memory_order_acquire),
          "feed does not return before callbacks caused by it quiesce");
    CHECK(rac_diarization_stream_feed_audio_proto(blocked_session,
                                                  reinterpret_cast<const uint8_t*>(chunk.data()),
                                                  chunk.size()) == RAC_ERROR_SERVICE_BUSY,
          "concurrent feed is rejected before entering the backend stream");
    auto quiesce = std::async(std::launch::async, [&] {
        (void)rac_diarization_unset_stream_proto_callback(component);
        rac_diarization_proto_quiesce();
    });
    CHECK(quiesce.wait_for(50ms) == std::future_status::timeout,
          "quiesce waits for admitted callback");
    {
        std::lock_guard<std::mutex> lock(blocking.mutex);
        blocking.release_update = true;
    }
    blocking.cv.notify_all();
    feed_thread.join();
    CHECK(blocked_feed_result.load(std::memory_order_acquire) == RAC_SUCCESS,
          "serialized feed succeeds after its callback returns");
    CHECK(quiesce.wait_for(2s) == std::future_status::ready,
          "quiesce completes after callback returns");
    quiesce.get();
    CHECK(rac_diarization_stream_cancel_proto(blocked_session) == RAC_SUCCESS,
          "quiescence test session cancels");

    // Two callbacks can independently use the canonical unset + quiesce
    // teardown sequence. Epoch ordering must prevent a mutual wait cycle.
    ReentrantQuiesceBarrier reentrant_barrier;
    reentrant_barrier.component = component;
    CHECK(rac_diarization_set_stream_proto_callback(component, quiesce_from_two_callbacks,
                                                    &reentrant_barrier) == RAC_SUCCESS,
          "two-session reentrant quiesce callback registers");
    uint64_t reentrant_session_a = 0;
    uint64_t reentrant_session_b = 0;
    CHECK(rac_diarization_stream_start_proto(component, nullptr, 0, &reentrant_session_a) ==
                  RAC_SUCCESS &&
              rac_diarization_stream_start_proto(component, nullptr, 0, &reentrant_session_b) ==
                  RAC_SUCCESS,
          "two reentrant-quiesce sessions start");
    auto reentrant_feed_a = std::async(std::launch::async, [&] {
        return rac_diarization_stream_feed_audio_proto(
            reentrant_session_a, reinterpret_cast<const uint8_t*>(chunk.data()), chunk.size());
    });
    auto reentrant_feed_b = std::async(std::launch::async, [&] {
        return rac_diarization_stream_feed_audio_proto(
            reentrant_session_b, reinterpret_cast<const uint8_t*>(chunk.data()), chunk.size());
    });
    {
        std::unique_lock<std::mutex> lock(reentrant_barrier.mutex);
        CHECK(reentrant_barrier.cv.wait_for(lock, 2s,
                                            [&] { return reentrant_barrier.completed == 2; }),
              "two reentrant callback quiesce calls complete without deadlock");
    }
    CHECK(reentrant_feed_a.wait_for(2s) == std::future_status::ready &&
              reentrant_feed_a.get() == RAC_SUCCESS &&
              reentrant_feed_b.wait_for(2s) == std::future_status::ready &&
              reentrant_feed_b.get() == RAC_SUCCESS,
          "both feeds return after the reentrant quiesce barrier");
    CHECK(rac_diarization_stream_cancel_proto(reentrant_session_a) == RAC_SUCCESS &&
              rac_diarization_stream_cancel_proto(reentrant_session_b) == RAC_SUCCESS,
          "reentrant quiesce sessions cancel cleanly");

    // Lifecycle mutation cancels every session first and cannot destroy the
    // pinned service until provider stream destruction has completed.
    CHECK(rac_diarization_set_stream_proto_callback(component, collect_event, &collector) ==
              RAC_SUCCESS,
          "callback re-registers after quiescence");
    uint64_t pinned_session = 0;
    CHECK(rac_diarization_stream_start_proto(component, nullptr, 0, &pinned_session) == RAC_SUCCESS,
          "pinning test stream starts");
    {
        std::lock_guard<std::mutex> lock(g_destroy_mutex);
        g_block_destroy = true;
        g_destroy_entered = false;
        g_release_destroy = false;
    }
    auto unload =
        std::async(std::launch::async, [&] { return rac_diarization_component_unload(component); });
    {
        std::unique_lock<std::mutex> lock(g_destroy_mutex);
        CHECK(g_destroy_cv.wait_for(lock, 2s, [] { return g_destroy_entered; }),
              "unload enters provider stream teardown");
    }
    CHECK(unload.wait_for(50ms) == std::future_status::timeout,
          "unload waits while the stream-owned service pin is live");
    {
        std::lock_guard<std::mutex> lock(g_destroy_mutex);
        g_release_destroy = true;
        g_block_destroy = false;
    }
    g_destroy_cv.notify_all();
    CHECK(unload.wait_for(2s) == std::future_status::ready && unload.get() == RAC_SUCCESS,
          "unload completes after stream teardown releases its pin");

    rac_diarization_component_destroy(component);

    // A stream start owns a component-operation lease before it copies the
    // lifecycle handle. Destroy closes admission and must wait until backend
    // creation/publication and the lease release complete.
    rac_handle_t start_race_component = nullptr;
    CHECK(rac_diarization_component_create(&start_race_component) == RAC_SUCCESS,
          "start/destroy race component creates");
    CHECK(rac_diarization_component_load_model(start_race_component, "start-race", "start-race",
                                               "Start race") == RAC_SUCCESS,
          "start/destroy race model loads");
    OperationGate start_gate;
    rac::diarization::set_component_operation_admitted_test_hook(block_admitted_component_operation,
                                                                 &start_gate);
    uint64_t start_race_session = 0;
    auto blocked_start = std::async(std::launch::async, [&] {
        return rac_diarization_stream_start_proto(start_race_component, nullptr, 0,
                                                  &start_race_session);
    });
    CHECK(wait_for_operation_gate(&start_gate), "stream start pauses after lifetime admission");
    rac::diarization::set_component_operation_admitted_test_hook(nullptr, nullptr);
    auto start_race_destroy = std::async(
        std::launch::async, [&] { rac_diarization_component_destroy(start_race_component); });
    CHECK(wait_for_component_admission_to_close(start_race_component),
          "destroy closes new component-operation admission");
    CHECK(start_race_destroy.wait_for(50ms) == std::future_status::timeout,
          "destroy waits for the admitted stream-start lease");
    release_operation_gate(&start_gate);
    CHECK(blocked_start.wait_for(2s) == std::future_status::ready &&
              blocked_start.get() == RAC_SUCCESS && start_race_session != 0,
          "admitted stream start safely publishes before destroy proceeds");
    CHECK(start_race_destroy.wait_for(2s) == std::future_status::ready,
          "destroy completes after stream-start lease release");
    start_race_destroy.get();

    // The same lifetime registry covers offline proto work, not only streams.
    rac_handle_t offline_race_component = nullptr;
    CHECK(rac_diarization_component_create(&offline_race_component) == RAC_SUCCESS,
          "offline/destroy race component creates");
    CHECK(rac_diarization_component_load_model(offline_race_component, "offline-race",
                                               "offline-race", "Offline race") == RAC_SUCCESS,
          "offline/destroy race model loads");
    OperationGate offline_gate;
    rac::diarization::set_component_operation_admitted_test_hook(block_admitted_component_operation,
                                                                 &offline_gate);
    rac_proto_buffer_t offline_race_output{};
    auto blocked_offline = std::async(std::launch::async, [&] {
        return rac_diarization_component_diarize_proto(
            offline_race_component, reinterpret_cast<const uint8_t*>(request_bytes.data()),
            request_bytes.size(), &offline_race_output);
    });
    CHECK(wait_for_operation_gate(&offline_gate), "offline call pauses after lifetime admission");
    rac::diarization::set_component_operation_admitted_test_hook(nullptr, nullptr);
    auto offline_race_destroy = std::async(
        std::launch::async, [&] { rac_diarization_component_destroy(offline_race_component); });
    CHECK(wait_for_component_admission_to_close(offline_race_component),
          "offline-race destroy closes new admission");
    CHECK(offline_race_destroy.wait_for(50ms) == std::future_status::timeout,
          "destroy waits for admitted offline operation");
    release_operation_gate(&offline_gate);
    CHECK(blocked_offline.wait_for(2s) == std::future_status::ready &&
              blocked_offline.get() == RAC_SUCCESS,
          "admitted offline operation completes without lifecycle UAF");
    rac_proto_buffer_free(&offline_race_output);
    CHECK(offline_race_destroy.wait_for(2s) == std::future_status::ready,
          "destroy completes after offline lease release");
    offline_race_destroy.get();

    // Getter calls also lease the component before touching its mutex or
    // lifecycle; use is_loaded so no borrowed pointer escapes the call.
    rac_handle_t getter_race_component = nullptr;
    CHECK(rac_diarization_component_create(&getter_race_component) == RAC_SUCCESS,
          "getter/destroy race component creates");
    CHECK(rac_diarization_component_load_model(getter_race_component, "getter-race", "getter-race",
                                               "Getter race") == RAC_SUCCESS,
          "getter/destroy race model loads");
    OperationGate getter_gate;
    rac::diarization::set_component_operation_admitted_test_hook(block_admitted_component_operation,
                                                                 &getter_gate);
    auto blocked_getter = std::async(std::launch::async, [&] {
        return rac_diarization_component_is_loaded(getter_race_component);
    });
    CHECK(wait_for_operation_gate(&getter_gate), "getter pauses after lifetime admission");
    rac::diarization::set_component_operation_admitted_test_hook(nullptr, nullptr);
    auto getter_race_destroy = std::async(
        std::launch::async, [&] { rac_diarization_component_destroy(getter_race_component); });
    CHECK(wait_for_component_admission_to_close(getter_race_component),
          "getter-race destroy closes new admission");
    CHECK(getter_race_destroy.wait_for(50ms) == std::future_status::timeout,
          "destroy waits for admitted getter");
    release_operation_gate(&getter_gate);
    CHECK(blocked_getter.wait_for(2s) == std::future_status::ready &&
              blocked_getter.get() == RAC_TRUE,
          "admitted getter completes without touching freed state");
    CHECK(getter_race_destroy.wait_for(2s) == std::future_status::ready,
          "destroy completes after getter lease release");
    getter_race_destroy.get();

    CHECK(rac_plugin_unregister("fake-diarization") == RAC_SUCCESS,
          "fake plugin unregisters cleanly");

    std::fprintf(stdout, "\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
#endif
}
