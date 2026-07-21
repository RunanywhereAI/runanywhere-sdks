/**
 * @file diarization_module.cpp
 * @brief Lifecycle-owned speaker-diarization component and offline proto ABI.
 */

#include "diarization_internal.h"

#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>
#include <vector>

#include "features/common/rac_component_lifecycle_internal.h"
#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_logger.h"
#include "rac/features/diarization/rac_diarization_component.h"
#include "rac/features/diarization/rac_diarization_stream.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "foundation/rac_proto_marshal_internal.h"
#endif

namespace {

constexpr const char* kLogCategory = "Diarization.Component";

struct rac_diarization_component {
    rac_handle_t lifecycle = nullptr;
    std::mutex mutex;
};

std::mutex& component_lifetime_mutex() {
    static std::mutex mutex;
    return mutex;
}

std::condition_variable& component_lifetime_cv() {
    static std::condition_variable cv;
    return cv;
}

std::unordered_map<rac_handle_t, std::shared_ptr<rac::diarization::ComponentLifetimeEntry>>&
component_lifetime_registry() {
    static std::unordered_map<rac_handle_t,
                              std::shared_ptr<rac::diarization::ComponentLifetimeEntry>>
        registry;
    return registry;
}

rac::diarization::ComponentOperationAdmittedTestHook& component_operation_admitted_test_hook() {
    static rac::diarization::ComponentOperationAdmittedTestHook hook = nullptr;
    return hook;
}

void*& component_operation_admitted_test_user_data() {
    static void* user_data = nullptr;
    return user_data;
}

thread_local rac::diarization::ComponentOperationFrame* g_component_operation_frame = nullptr;

class StreamTeardownGuard {
   public:
    explicit StreamTeardownGuard(rac_handle_t handle)
        : handle_(handle), result_(rac::diarization::begin_stream_component_teardown(handle)) {}

    ~StreamTeardownGuard() {
        if (result_ == RAC_SUCCESS) {
            rac::diarization::end_stream_component_teardown(handle_);
        }
    }

    rac_result_t result() const { return result_; }

   private:
    rac_handle_t handle_;
    rac_result_t result_;
};

rac_result_t create_component_service(const char* model_id, void*, rac_handle_t* out_service) {
    rac_result_t rc = rac_diarization_create(model_id, out_service);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    rc = rac_diarization_initialize(*out_service, model_id);
    if (rc != RAC_SUCCESS) {
        rac_diarization_destroy(*out_service);
        *out_service = nullptr;
    }
    return rc;
}

void destroy_component_service(rac_handle_t service, void*) {
    if (!service) {
        return;
    }
    (void)rac_diarization_cleanup(service);
    rac_diarization_destroy(service);
}

#if defined(RAC_HAVE_PROTOBUF)

rac_result_t diarize_with_service(rac_handle_t service, const char* model_id,
                                  const uint8_t* request_bytes, size_t request_size,
                                  rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    const rac_result_t bytes_rc = rac_proto_bytes_validate(request_bytes, request_size);
    if (bytes_rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "DiarizationRequest bytes are invalid");
    }

    runanywhere::v1::DiarizationRequest request;
    if (!request.ParseFromArray(rac_proto_bytes_data_or_empty(request_bytes, request_size),
                                static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse DiarizationRequest");
    }

    rac_diarization_options_t options = RAC_DIARIZATION_OPTIONS_DEFAULT;
    runanywhere::v1::DiarizationAudioEncoding encoding =
        runanywhere::v1::DIARIZATION_AUDIO_ENCODING_PCM_F32_LE;
    rac_result_t rc = rac::diarization::options_from_proto(
        request.has_options() ? &request.options() : nullptr, &options, &encoding);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "invalid DiarizationOptions");
    }

    std::vector<float> samples;
    rc = rac::diarization::decode_audio(
        reinterpret_cast<const uint8_t*>(request.audio_data().data()), request.audio_data().size(),
        encoding, options.channel_count, true, &samples);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "invalid diarization PCM audio");
    }

    rac_diarization_result_t raw = {};
    rc = rac_diarization_diarize(service, samples.data(), samples.size(), &options, &raw);
    if (rc != RAC_SUCCESS) {
        rac_diarization_result_free(&raw);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::DiarizationResult result;
    rc = rac::diarization::result_to_proto(raw, model_id, &result);
    if (rc == RAC_SUCCESS) {
        rc = rac::proto::copy_message(result, out_result, "failed to serialize DiarizationResult");
    } else {
        (void)rac_proto_buffer_set_error(out_result, rc,
                                         "backend returned an invalid diarization result");
    }
    rac_diarization_result_free(&raw);
    return rc;
}

#endif

rac_result_t protobuf_unavailable(rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}

}  // namespace

namespace rac::diarization {

bool register_component_lifetime(rac_handle_t component_handle, rac_handle_t lifecycle_handle) {
    if (!component_handle || !lifecycle_handle) {
        return false;
    }
    try {
        auto entry = std::make_shared<ComponentLifetimeEntry>();
        entry->component = component_handle;
        entry->lifecycle = lifecycle_handle;
        std::lock_guard<std::mutex> lock(component_lifetime_mutex());
        return component_lifetime_registry().emplace(component_handle, std::move(entry)).second;
    } catch (...) {
        return false;
    }
}

bool current_thread_has_component_operation(rac_handle_t handle) {
    for (ComponentOperationFrame* frame = g_component_operation_frame; frame;
         frame = frame->previous) {
        if (frame->handle == handle) {
            return true;
        }
    }
    return false;
}

ComponentOperationLease::ComponentOperationLease(rac_handle_t handle) : handle_(handle) {
    if (!handle) {
        return;
    }
    ComponentOperationAdmittedTestHook hook = nullptr;
    void* hook_user_data = nullptr;
    {
        std::lock_guard<std::mutex> lock(component_lifetime_mutex());
        const auto it = component_lifetime_registry().find(handle);
        if (it == component_lifetime_registry().end() ||
            (!it->second->accepting_operations &&
             !current_thread_has_component_operation(handle))) {
            return;
        }
        entry_ = it->second;
        ++entry_->active_operations;
        frame_.handle = handle_;
        frame_.previous = g_component_operation_frame;
        g_component_operation_frame = &frame_;
        hook = component_operation_admitted_test_hook();
        hook_user_data = component_operation_admitted_test_user_data();
    }
    if (hook) {
        hook(handle, hook_user_data);
    }
}

ComponentOperationLease::~ComponentOperationLease() {
    if (!entry_) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(component_lifetime_mutex());
        if (entry_->active_operations > 0) {
            --entry_->active_operations;
        }
        g_component_operation_frame = frame_.previous;
    }
    component_lifetime_cv().notify_all();
}

std::shared_ptr<ComponentLifetimeEntry> close_component_admission(rac_handle_t handle) {
    std::lock_guard<std::mutex> lock(component_lifetime_mutex());
    const auto it = component_lifetime_registry().find(handle);
    if (it == component_lifetime_registry().end() || !it->second->accepting_operations) {
        return nullptr;
    }
    it->second->accepting_operations = false;
    return it->second;
}

void reopen_component_admission(rac_handle_t handle,
                                const std::shared_ptr<ComponentLifetimeEntry>& entry) {
    std::lock_guard<std::mutex> lock(component_lifetime_mutex());
    const auto it = component_lifetime_registry().find(handle);
    if (it != component_lifetime_registry().end() && it->second == entry) {
        entry->accepting_operations = true;
    }
}

void wait_for_component_operations(const std::shared_ptr<ComponentLifetimeEntry>& entry) {
    std::unique_lock<std::mutex> lock(component_lifetime_mutex());
    component_lifetime_cv().wait(lock, [&] { return entry->active_operations == 0; });
}

rac_handle_t remove_component_lifetime(rac_handle_t handle,
                                       const std::shared_ptr<ComponentLifetimeEntry>& entry) {
    std::lock_guard<std::mutex> lock(component_lifetime_mutex());
    const auto it = component_lifetime_registry().find(handle);
    if (it == component_lifetime_registry().end() || it->second != entry ||
        entry->active_operations != 0) {
        return nullptr;
    }
    const rac_handle_t component = entry->component;
    component_lifetime_registry().erase(it);
    return component;
}

void set_component_operation_admitted_test_hook(ComponentOperationAdmittedTestHook hook,
                                                void* user_data) {
    std::lock_guard<std::mutex> lock(component_lifetime_mutex());
    component_operation_admitted_test_hook() = hook;
    component_operation_admitted_test_user_data() = user_data;
}

#if defined(RAC_HAVE_PROTOBUF)

rac_result_t options_from_proto(const runanywhere::v1::DiarizationOptions* proto,
                                rac_diarization_options_t* out_options,
                                runanywhere::v1::DiarizationAudioEncoding* out_encoding) {
    if (!out_options || !out_encoding) {
        return RAC_ERROR_NULL_POINTER;
    }

    *out_options = RAC_DIARIZATION_OPTIONS_DEFAULT;
    *out_encoding = runanywhere::v1::DIARIZATION_AUDIO_ENCODING_PCM_F32_LE;
    if (proto) {
        if (proto->has_sample_rate_hz()) {
            out_options->sample_rate_hz = proto->sample_rate_hz();
        }
        if (proto->has_channel_count()) {
            out_options->channel_count = proto->channel_count();
        }
        if (proto->has_threshold()) {
            out_options->threshold = proto->threshold();
        }
        out_options->minimum_duration_ms = proto->minimum_duration_ms();
        out_options->merge_gap_ms = proto->merge_gap_ms();
        if (proto->has_encoding()) {
            *out_encoding = proto->encoding();
        }
    }

    if (out_options->sample_rate_hz < 8000 || out_options->sample_rate_hz > 48000 ||
        out_options->channel_count < 1 || !std::isfinite(out_options->threshold) ||
        out_options->threshold < 0.0f || out_options->threshold > 1.0f ||
        out_options->minimum_duration_ms < 0 || out_options->merge_gap_ms < 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    // Phase 1 intentionally exposes only the model's canonical mono input.
    // Never downmix implicitly at the ABI boundary.
    if (out_options->channel_count != 1) {
        return RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED;
    }
    if (*out_encoding != runanywhere::v1::DIARIZATION_AUDIO_ENCODING_PCM_F32_LE &&
        *out_encoding != runanywhere::v1::DIARIZATION_AUDIO_ENCODING_PCM_S16_LE) {
        return RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED;
    }
    return RAC_SUCCESS;
}

rac_result_t decode_audio(const uint8_t* bytes, size_t size,
                          runanywhere::v1::DiarizationAudioEncoding encoding, int32_t channel_count,
                          bool require_nonempty, std::vector<float>* out_samples) {
    if (!out_samples) {
        return RAC_ERROR_NULL_POINTER;
    }
    out_samples->clear();
    if (size > 0 && !bytes) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (require_nonempty && size == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    if (channel_count != 1) {
        return RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED;
    }

    size_t sample_width = 0;
    switch (encoding) {
        case runanywhere::v1::DIARIZATION_AUDIO_ENCODING_PCM_F32_LE:
            sample_width = sizeof(float);
            break;
        case runanywhere::v1::DIARIZATION_AUDIO_ENCODING_PCM_S16_LE:
            sample_width = sizeof(int16_t);
            break;
        default:
            return RAC_ERROR_AUDIO_FORMAT_NOT_SUPPORTED;
    }
    if (size % (sample_width * static_cast<size_t>(channel_count)) != 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const size_t count = size / sample_width;
    try {
        out_samples->resize(count);
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    for (size_t i = 0; i < count; ++i) {
        const uint8_t* p = bytes + i * sample_width;
        if (encoding == runanywhere::v1::DIARIZATION_AUDIO_ENCODING_PCM_S16_LE) {
            const uint16_t raw = static_cast<uint16_t>(p[0]) | (static_cast<uint16_t>(p[1]) << 8U);
            const int16_t sample = static_cast<int16_t>(raw);
            (*out_samples)[i] = static_cast<float>(sample) / 32768.0f;
        } else {
            const uint32_t raw = static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8U) |
                                 (static_cast<uint32_t>(p[2]) << 16U) |
                                 (static_cast<uint32_t>(p[3]) << 24U);
            float sample = 0.0f;
            std::memcpy(&sample, &raw, sizeof(sample));
            if (!std::isfinite(sample)) {
                out_samples->clear();
                return RAC_ERROR_INVALID_ARGUMENT;
            }
            (*out_samples)[i] = sample;
        }
    }
    return RAC_SUCCESS;
}

rac_result_t result_to_proto(const rac_diarization_result_t& result, const char* fallback_model_id,
                             runanywhere::v1::DiarizationResult* out_proto) {
    if (!out_proto) {
        return RAC_ERROR_NULL_POINTER;
    }
    out_proto->Clear();
    if ((result.segment_count > 0 && !result.segments) || result.speaker_count < 0 ||
        (result.segment_count > 0 && result.speaker_count == 0) || result.audio_duration_ms < 0 ||
        result.processing_time_ms < 0) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    for (size_t i = 0; i < result.segment_count; ++i) {
        const auto& source = result.segments[i];
        if (source.start_ms < 0 || source.end_ms < source.start_ms || source.speaker_index < 0 ||
            source.speaker_index >= result.speaker_count) {
            out_proto->Clear();
            return RAC_ERROR_ENCODING_ERROR;
        }
        auto* segment = out_proto->add_segments();
        segment->set_start_ms(source.start_ms);
        segment->set_end_ms(source.end_ms);
        segment->set_speaker_index(source.speaker_index);
        if (source.speaker_id) {
            segment->set_speaker_id(source.speaker_id);
        }
    }
    out_proto->set_speaker_count(result.speaker_count);
    out_proto->set_audio_duration_ms(result.audio_duration_ms);
    out_proto->set_processing_time_ms(result.processing_time_ms);
    out_proto->set_model_id(result.model_id ? result.model_id
                                            : (fallback_model_id ? fallback_model_id : ""));
    return RAC_SUCCESS;
}

#endif

}  // namespace rac::diarization

extern "C" {

rac_result_t rac_diarization_component_create(rac_handle_t* out_handle) {
    const rac_result_t rc = rac::features::create_lifecycle_component<rac_diarization_component>(
        out_handle, RAC_RESOURCE_TYPE_DIARIZATION_MODEL, "Diarization.Lifecycle",
        create_component_service, destroy_component_service, kLogCategory,
        "Diarization component created");
    if (rc == RAC_SUCCESS) {
        auto* component = static_cast<rac_diarization_component*>(*out_handle);
        if (!rac::diarization::register_component_lifetime(*out_handle, component->lifecycle)) {
            rac_lifecycle_destroy(component->lifecycle);
            delete component;
            *out_handle = nullptr;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        rac::diarization::register_stream_component(*out_handle, component->lifecycle);
    }
    return rc;
}

rac_bool_t rac_diarization_component_is_loaded(rac_handle_t handle) {
    rac::diarization::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_FALSE;
    }
    auto* component = static_cast<rac_diarization_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

const char* rac_diarization_component_get_model_id(rac_handle_t handle) {
    rac::diarization::ComponentOperationLease lease(handle);
    if (!lease) {
        return nullptr;
    }
    auto* component = static_cast<rac_diarization_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

rac_result_t rac_diarization_component_load_model(rac_handle_t handle, const char* model_path,
                                                  const char* model_id, const char* model_name) {
    rac::diarization::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (!model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    StreamTeardownGuard streams(handle);
    if (streams.result() != RAC_SUCCESS) {
        return streams.result();
    }
    auto* component = static_cast<rac_diarization_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    rac_handle_t service = nullptr;
    return rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);
}

rac_result_t rac_diarization_component_unload(rac_handle_t handle) {
    rac::diarization::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    StreamTeardownGuard streams(handle);
    if (streams.result() != RAC_SUCCESS) {
        return streams.result();
    }
    auto* component = static_cast<rac_diarization_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_unload(component->lifecycle);
}

rac_lifecycle_state_t rac_diarization_component_get_state(rac_handle_t handle) {
    rac::diarization::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_LIFECYCLE_STATE_IDLE;
    }
    auto* component = static_cast<rac_diarization_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_state(component->lifecycle);
}

rac_result_t rac_diarization_component_get_metrics(rac_handle_t handle,
                                                   rac_lifecycle_metrics_t* out_metrics) {
    rac::diarization::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    auto* component = static_cast<rac_diarization_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}

void rac_diarization_component_destroy(rac_handle_t handle) {
    if (!handle) {
        return;
    }
    if (rac::diarization::current_thread_has_component_operation(handle)) {
        RAC_LOG_WARNING(kLogCategory,
                        "Diarization component destroy refused from a re-entrant operation");
        return;
    }
    const auto lifetime_entry = rac::diarization::close_component_admission(handle);
    if (!lifetime_entry) {
        return;
    }
    rac::diarization::wait_for_component_operations(lifetime_entry);
    const rac_result_t stream_rc = rac::diarization::begin_stream_component_teardown(handle);
    if (stream_rc != RAC_SUCCESS) {
        rac::diarization::reopen_component_admission(handle, lifetime_entry);
        RAC_LOG_WARNING(kLogCategory, "Diarization component destroy refused during callback");
        return;
    }
    auto* component = static_cast<rac_diarization_component*>(
        rac::diarization::remove_component_lifetime(handle, lifetime_entry));
    if (!component) {
        rac::diarization::end_stream_component_teardown(handle);
        rac::diarization::reopen_component_admission(handle, lifetime_entry);
        return;
    }
    {
        std::lock_guard<std::mutex> lock(component->mutex);
        rac_lifecycle_destroy(component->lifecycle);
        component->lifecycle = nullptr;
    }
    (void)rac_diarization_unset_stream_proto_callback(handle);
    rac_diarization_proto_quiesce();
    rac::diarization::unregister_stream_component(handle);
    delete component;
}

rac_result_t rac_diarization_component_diarize_proto(rac_handle_t handle,
                                                     const uint8_t* request_proto_bytes,
                                                     size_t request_proto_size,
                                                     rac_proto_buffer_t* out_result) {
    rac::diarization::ComponentOperationLease lease(handle);
    if (!lease) {
        return out_result ? rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_HANDLE,
                                                       "invalid diarization component handle")
                          : RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return protobuf_unavailable(out_result);
#else
    auto* component = static_cast<rac_diarization_component*>(lease.component());
    rac_handle_t service = nullptr;
    rac_result_t rc = rac_lifecycle_acquire_service(component->lifecycle, &service);
    if (rc != RAC_SUCCESS) {
        return out_result ? rac_proto_buffer_set_error(out_result, rc,
                                                       "Diarization lifecycle model is not loaded")
                          : RAC_ERROR_NULL_POINTER;
    }
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    rc = diarize_with_service(service, model_id, request_proto_bytes, request_proto_size,
                              out_result);
    rac_lifecycle_release_service(component->lifecycle);
    return rc;
#endif
}

rac_result_t rac_diarization_diarize_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                     size_t request_proto_size,
                                                     rac_proto_buffer_t* out_result) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return protobuf_unavailable(out_result);
#else
    rac::lifecycle::LifecycleDiarizationRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_diarization(&ref);
    if (rc != RAC_SUCCESS) {
        return out_result ? rac_proto_buffer_set_error(out_result, rc,
                                                       "Diarization lifecycle model is not loaded")
                          : RAC_ERROR_NULL_POINTER;
    }
    rac_diarization_service_t service{ref.ops, ref.impl, ref.model_id};
    rc = diarize_with_service(&service, ref.model_id, request_proto_bytes, request_proto_size,
                              out_result);
    rac::lifecycle::release_lifecycle_diarization(&ref);
    return rc;
#endif
}

}  // extern "C"
