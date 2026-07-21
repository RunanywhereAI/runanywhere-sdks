/** @file vocoder_module.cpp @brief Lifecycle and proto ABI for vocoder. */

#include "vocoder_internal.h"

#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <exception>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "features/common/rac_component_lifecycle_internal.h"
#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_logger.h"
#include "rac/features/vocoder/rac_vocoder_component.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "vocoder.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

namespace {

constexpr const char* kLogCategory = "Vocoder.Component";
constexpr uint32_t kMaxBatchSize = 32;
constexpr uint32_t kMaxMelBinCount = 4096;
constexpr uint32_t kMaxFrameCount = 65536;
constexpr uint64_t kMaxMelValueCount = 8ULL * 1024ULL * 1024ULL;
constexpr uint64_t kMaxBatchFrames = 65536;

struct rac_vocoder_component {
    rac_handle_t lifecycle = nullptr;
    std::mutex mutex;
};

std::mutex& lifetime_mutex() {
    static std::mutex value;
    return value;
}

std::condition_variable& lifetime_cv() {
    static std::condition_variable value;
    return value;
}

std::unordered_map<rac_handle_t, std::shared_ptr<rac::vocoder::ComponentLifetimeEntry>>&
lifetime_registry() {
    static std::unordered_map<rac_handle_t, std::shared_ptr<rac::vocoder::ComponentLifetimeEntry>>
        value;
    return value;
}

rac::vocoder::ComponentOperationAdmittedTestHook& admitted_hook() {
    static rac::vocoder::ComponentOperationAdmittedTestHook value = nullptr;
    return value;
}

void*& admitted_hook_user_data() {
    static void* value = nullptr;
    return value;
}

thread_local rac::vocoder::ComponentOperationFrame* g_operation_frame = nullptr;

bool current_thread_has_operation(rac_handle_t handle) {
    for (auto* frame = g_operation_frame; frame; frame = frame->previous) {
        if (frame->handle == handle) {
            return true;
        }
    }
    return false;
}

bool register_lifetime(rac_handle_t component, rac_handle_t lifecycle) {
    try {
        auto entry = std::make_shared<rac::vocoder::ComponentLifetimeEntry>();
        entry->component = component;
        entry->lifecycle = lifecycle;
        std::lock_guard<std::mutex> lock(lifetime_mutex());
        return lifetime_registry().emplace(component, std::move(entry)).second;
    } catch (...) {
        return false;
    }
}

std::shared_ptr<rac::vocoder::ComponentLifetimeEntry> close_admission(rac_handle_t handle) {
    std::lock_guard<std::mutex> lock(lifetime_mutex());
    const auto it = lifetime_registry().find(handle);
    if (it == lifetime_registry().end() || !it->second->accepting_operations) {
        return nullptr;
    }
    it->second->accepting_operations = false;
    return it->second;
}

void wait_for_operations(const std::shared_ptr<rac::vocoder::ComponentLifetimeEntry>& entry) {
    std::unique_lock<std::mutex> lock(lifetime_mutex());
    lifetime_cv().wait(lock, [&] { return entry->active_operations == 0; });
}

rac_handle_t remove_lifetime(rac_handle_t handle,
                             const std::shared_ptr<rac::vocoder::ComponentLifetimeEntry>& entry) {
    std::lock_guard<std::mutex> lock(lifetime_mutex());
    const auto it = lifetime_registry().find(handle);
    if (it == lifetime_registry().end() || it->second != entry || entry->active_operations != 0) {
        return nullptr;
    }
    const rac_handle_t component = entry->component;
    lifetime_registry().erase(it);
    return component;
}

rac_result_t create_component_service(const char* model_id, void*, rac_handle_t* out_service) {
    rac_result_t rc = rac_vocoder_create(model_id, out_service);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    rc = rac_vocoder_initialize(*out_service, model_id);
    if (rc != RAC_SUCCESS) {
        rac_vocoder_destroy(*out_service);
        *out_service = nullptr;
    }
    return rc;
}

void destroy_component_service(rac_handle_t service, void*) {
    if (service) {
        (void)rac_vocoder_cleanup(service);
        rac_vocoder_destroy(service);
    }
}

rac_result_t proto_failure(rac_proto_buffer_t* out_result, rac_result_t code,
                           const char* message) noexcept {
    if (!out_result) {
        return code;
    }
    return rac_proto_buffer_set_error(out_result, code, message);
}

class LifecycleServiceRelease final {
   public:
    explicit LifecycleServiceRelease(rac_handle_t lifecycle) : lifecycle_(lifecycle) {}
    LifecycleServiceRelease(const LifecycleServiceRelease&) = delete;
    LifecycleServiceRelease& operator=(const LifecycleServiceRelease&) = delete;
    ~LifecycleServiceRelease() noexcept {
        if (lifecycle_) {
            rac_lifecycle_release_service(lifecycle_);
        }
    }

   private:
    rac_handle_t lifecycle_;
};

class LifecycleVocoderRelease final {
   public:
    explicit LifecycleVocoderRelease(rac::lifecycle::LifecycleVocoderRef* ref) : ref_(ref) {}
    LifecycleVocoderRelease(const LifecycleVocoderRelease&) = delete;
    LifecycleVocoderRelease& operator=(const LifecycleVocoderRelease&) = delete;
    ~LifecycleVocoderRelease() noexcept {
        if (ref_) {
            try {
                rac::lifecycle::release_lifecycle_vocoder(ref_);
            } catch (...) {
                // Destructors on an extern-C unwind path must never throw.
            }
        }
    }

   private:
    rac::lifecycle::LifecycleVocoderRef* ref_;
};

class VocoderResultRelease final {
   public:
    VocoderResultRelease() = default;
    VocoderResultRelease(const VocoderResultRelease&) = delete;
    VocoderResultRelease& operator=(const VocoderResultRelease&) = delete;
    ~VocoderResultRelease() noexcept { rac_vocoder_result_free(&value); }

    rac_vocoder_result_t value{};
};

#if !defined(RAC_HAVE_PROTOBUF)
rac_result_t protobuf_unavailable(rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}
#endif

#if defined(RAC_HAVE_PROTOBUF)

bool checked_mul_size(size_t a, size_t b, size_t* out) {
    if (!out || (a != 0 && b > std::numeric_limits<size_t>::max() / a)) {
        return false;
    }
    *out = a * b;
    return true;
}

rac_result_t request_to_input(const runanywhere::v1::VocoderRequest& request,
                              std::vector<float>* storage, rac_vocoder_input_t* out_input) {
    if (!storage || !out_input) {
        return RAC_ERROR_NULL_POINTER;
    }
    storage->clear();
    *out_input = {};
    const uint32_t batch = request.batch_size();
    const uint32_t mel_bins = request.mel_bin_count();
    const uint32_t frames = request.frame_count();
    if (batch == 0 || batch > kMaxBatchSize || mel_bins == 0 || mel_bins > kMaxMelBinCount ||
        frames == 0 || frames > kMaxFrameCount ||
        static_cast<uint64_t>(batch) * frames > kMaxBatchFrames) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    size_t value_count = 0;
    size_t batch_mels = 0;
    size_t byte_count = 0;
    if (!checked_mul_size(batch, mel_bins, &batch_mels) ||
        !checked_mul_size(batch_mels, frames, &value_count) || value_count > kMaxMelValueCount ||
        !checked_mul_size(value_count, sizeof(float), &byte_count) ||
        request.mel_spectrogram_f32_le().size() != byte_count) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    try {
        storage->resize(value_count);
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    const auto& bytes = request.mel_spectrogram_f32_le();
    for (size_t i = 0; i < value_count; ++i) {
        const auto* source = reinterpret_cast<const uint8_t*>(bytes.data()) + i * sizeof(float);
        const uint32_t bits =
            static_cast<uint32_t>(source[0]) | (static_cast<uint32_t>(source[1]) << 8U) |
            (static_cast<uint32_t>(source[2]) << 16U) | (static_cast<uint32_t>(source[3]) << 24U);
        std::memcpy(&(*storage)[i], &bits, sizeof(bits));
        if (!std::isfinite((*storage)[i])) {
            storage->clear();
            return RAC_ERROR_INVALID_ARGUMENT;
        }
    }
    out_input->mel_spectrogram = storage->data();
    out_input->value_count = value_count;
    out_input->batch_size = batch;
    out_input->mel_bin_count = mel_bins;
    out_input->frame_count = frames;
    return RAC_SUCCESS;
}

rac_result_t result_to_proto(const rac_vocoder_result_t& source, const char* fallback_model_id,
                             runanywhere::v1::VocoderResult* out) {
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
    out->Clear();
    size_t batch_channels = 0;
    size_t expected_values = 0;
    size_t byte_count = 0;
    if (source.batch_size == 0 || source.channel_count == 0 || source.sample_count == 0 ||
        source.sample_rate_hz == 0 || source.hop_length == 0 || source.processing_time_ms < 0 ||
        !checked_mul_size(source.batch_size, source.channel_count, &batch_channels) ||
        !checked_mul_size(batch_channels, source.sample_count, &expected_values) ||
        source.sample_value_count != expected_values || !source.samples ||
        !checked_mul_size(expected_values, sizeof(float), &byte_count)) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    std::string bytes;
    try {
        bytes.resize(byte_count);
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    for (size_t i = 0; i < expected_values; ++i) {
        if (!std::isfinite(source.samples[i])) {
            return RAC_ERROR_ENCODING_ERROR;
        }
        uint32_t bits = 0;
        std::memcpy(&bits, &source.samples[i], sizeof(bits));
        bytes[i * 4] = static_cast<char>(bits & 0xffU);
        bytes[i * 4 + 1] = static_cast<char>((bits >> 8U) & 0xffU);
        bytes[i * 4 + 2] = static_cast<char>((bits >> 16U) & 0xffU);
        bytes[i * 4 + 3] = static_cast<char>((bits >> 24U) & 0xffU);
    }
    out->set_samples_f32_le(std::move(bytes));
    out->set_batch_size(source.batch_size);
    out->set_channel_count(source.channel_count);
    out->set_sample_count(source.sample_count);
    out->set_sample_rate_hz(source.sample_rate_hz);
    out->set_hop_length(source.hop_length);
    out->set_processing_time_ms(source.processing_time_ms);
    out->set_model_id(source.model_id ? source.model_id
                                      : (fallback_model_id ? fallback_model_id : ""));
    return RAC_SUCCESS;
}

rac_result_t vocode_with_service(rac_handle_t service, const char* model_id,
                                 const uint8_t* request_bytes, size_t request_size,
                                 rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (rac_proto_bytes_validate(request_bytes, request_size) != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "VocoderRequest bytes are invalid");
    }
    runanywhere::v1::VocoderRequest request;
    if (!request.ParseFromArray(rac_proto_bytes_data_or_empty(request_bytes, request_size),
                                static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse VocoderRequest");
    }

    std::vector<float> input_storage;
    rac_vocoder_input_t input = {};
    rac_result_t rc = request_to_input(request, &input_storage, &input);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "invalid vocoder mel tensor");
    }

    VocoderResultRelease raw;
    rc = rac_vocoder_vocode(service, &input, &raw.value);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::VocoderResult result;
    rc = result_to_proto(raw.value, model_id, &result);
    if (rc == RAC_SUCCESS) {
        rc = rac::proto::copy_message(result, out_result, "failed to serialize VocoderResult");
    } else {
        (void)rac_proto_buffer_set_error(out_result, rc,
                                         "backend returned an invalid vocoder result");
    }
    return rc;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

namespace rac::vocoder {

ComponentOperationLease::ComponentOperationLease(rac_handle_t handle) : handle_(handle) {
    if (!handle) {
        return;
    }
    ComponentOperationAdmittedTestHook hook = nullptr;
    void* hook_user_data = nullptr;
    {
        std::lock_guard<std::mutex> lock(lifetime_mutex());
        const auto it = lifetime_registry().find(handle);
        if (it == lifetime_registry().end() ||
            (!it->second->accepting_operations && !current_thread_has_operation(handle))) {
            return;
        }
        entry_ = it->second;
        ++entry_->active_operations;
        frame_.handle = handle_;
        frame_.previous = g_operation_frame;
        g_operation_frame = &frame_;
        hook = admitted_hook();
        hook_user_data = admitted_hook_user_data();
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
        std::lock_guard<std::mutex> lock(lifetime_mutex());
        if (entry_->active_operations > 0) {
            --entry_->active_operations;
        }
        g_operation_frame = frame_.previous;
    }
    lifetime_cv().notify_all();
}

void set_component_operation_admitted_test_hook(ComponentOperationAdmittedTestHook hook,
                                                void* user_data) {
    std::lock_guard<std::mutex> lock(lifetime_mutex());
    admitted_hook() = hook;
    admitted_hook_user_data() = user_data;
}

}  // namespace rac::vocoder

extern "C" {

rac_result_t rac_vocoder_component_create(rac_handle_t* out_handle) {
    const rac_result_t rc = rac::features::create_lifecycle_component<rac_vocoder_component>(
        out_handle, RAC_RESOURCE_TYPE_VOCODER_MODEL, "Vocoder.Lifecycle", create_component_service,
        destroy_component_service, kLogCategory, "Vocoder component created");
    if (rc == RAC_SUCCESS) {
        auto* component = static_cast<rac_vocoder_component*>(*out_handle);
        if (!register_lifetime(*out_handle, component->lifecycle)) {
            rac_lifecycle_destroy(component->lifecycle);
            delete component;
            *out_handle = nullptr;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }
    return rc;
}

rac_bool_t rac_vocoder_component_is_loaded(rac_handle_t handle) {
    rac::vocoder::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_FALSE;
    }
    auto* component = static_cast<rac_vocoder_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

const char* rac_vocoder_component_get_model_id(rac_handle_t handle) {
    rac::vocoder::ComponentOperationLease lease(handle);
    if (!lease) {
        return nullptr;
    }
    auto* component = static_cast<rac_vocoder_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

rac_result_t rac_vocoder_component_load_model(rac_handle_t handle, const char* model_path,
                                              const char* model_id, const char* model_name) {
    rac::vocoder::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (!model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* component = static_cast<rac_vocoder_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    rac_handle_t service = nullptr;
    return rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);
}

rac_result_t rac_vocoder_component_unload(rac_handle_t handle) {
    rac::vocoder::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    auto* component = static_cast<rac_vocoder_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_unload(component->lifecycle);
}

rac_lifecycle_state_t rac_vocoder_component_get_state(rac_handle_t handle) {
    rac::vocoder::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_LIFECYCLE_STATE_IDLE;
    }
    auto* component = static_cast<rac_vocoder_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_state(component->lifecycle);
}

rac_result_t rac_vocoder_component_get_metrics(rac_handle_t handle,
                                               rac_lifecycle_metrics_t* out_metrics) {
    rac::vocoder::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    auto* component = static_cast<rac_vocoder_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}

void rac_vocoder_component_destroy(rac_handle_t handle) {
    if (!handle || current_thread_has_operation(handle)) {
        if (handle) {
            RAC_LOG_WARNING(kLogCategory,
                            "Vocoder component destroy refused from re-entrant operation");
        }
        return;
    }
    const auto entry = close_admission(handle);
    if (!entry) {
        return;
    }
    wait_for_operations(entry);
    auto* component = static_cast<rac_vocoder_component*>(remove_lifetime(handle, entry));
    if (!component) {
        return;
    }
    {
        std::lock_guard<std::mutex> lock(component->mutex);
        rac_lifecycle_destroy(component->lifecycle);
        component->lifecycle = nullptr;
    }
    delete component;
}

rac_result_t rac_vocoder_component_vocode_proto(rac_handle_t handle,
                                                const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                rac_proto_buffer_t* out_result) {
    try {
        rac::vocoder::ComponentOperationLease lease(handle);
        if (!lease) {
            return out_result ? rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_HANDLE,
                                                           "invalid vocoder component handle")
                              : RAC_ERROR_NULL_POINTER;
        }
#if !defined(RAC_HAVE_PROTOBUF)
        (void)request_proto_bytes;
        (void)request_proto_size;
        return protobuf_unavailable(out_result);
#else
        auto* component = static_cast<rac_vocoder_component*>(lease.component());
        // Serialize inference with component load/unload. The lifecycle service
        // pin protects the old provider during reload, but the model ID lives
        // in the lifecycle map; acquiring both under this mutex keeps provider
        // and identity from coming from different generations.
        std::lock_guard<std::mutex> component_lock(component->mutex);
        rac_handle_t service = nullptr;
        rac_result_t rc = rac_lifecycle_acquire_service(component->lifecycle, &service);
        if (rc != RAC_SUCCESS) {
            return out_result
                       ? rac_proto_buffer_set_error(out_result, rc, "Vocoder model is not loaded")
                       : RAC_ERROR_NULL_POINTER;
        }
        LifecycleServiceRelease service_release(component->lifecycle);
        const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
        return vocode_with_service(service, model_id, request_proto_bytes, request_proto_size,
                                   out_result);
#endif
    } catch (const std::bad_alloc&) {
        return proto_failure(out_result, RAC_ERROR_OUT_OF_MEMORY,
                             "out of memory while processing VocoderRequest");
    } catch (const std::exception& exception) {
        RAC_LOG_ERROR(kLogCategory, "Vocoder component proto failure: %s", exception.what());
        return proto_failure(out_result, RAC_ERROR_INTERNAL, "internal vocoder failure");
    } catch (...) {
        RAC_LOG_ERROR(kLogCategory, "Vocoder component proto failure");
        return proto_failure(out_result, RAC_ERROR_INTERNAL, "internal vocoder failure");
    }
}

rac_result_t rac_vocoder_vocode_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                rac_proto_buffer_t* out_result) {
    try {
#if !defined(RAC_HAVE_PROTOBUF)
        (void)request_proto_bytes;
        (void)request_proto_size;
        return protobuf_unavailable(out_result);
#else
        rac::lifecycle::LifecycleVocoderRef ref{};
        rac_result_t rc = rac::lifecycle::acquire_lifecycle_vocoder(&ref);
        if (rc != RAC_SUCCESS) {
            return out_result
                       ? rac_proto_buffer_set_error(out_result, rc, "Vocoder model is not loaded")
                       : RAC_ERROR_NULL_POINTER;
        }
        LifecycleVocoderRelease ref_release(&ref);
        rac_vocoder_service_t service{ref.ops, ref.impl, ref.model_id};
        return vocode_with_service(&service, ref.model_id, request_proto_bytes, request_proto_size,
                                   out_result);
#endif
    } catch (const std::bad_alloc&) {
        return proto_failure(out_result, RAC_ERROR_OUT_OF_MEMORY,
                             "out of memory while processing VocoderRequest");
    } catch (const std::exception& exception) {
        RAC_LOG_ERROR(kLogCategory, "Vocoder lifecycle proto failure: %s", exception.what());
        return proto_failure(out_result, RAC_ERROR_INTERNAL, "internal vocoder failure");
    } catch (...) {
        RAC_LOG_ERROR(kLogCategory, "Vocoder lifecycle proto failure");
        return proto_failure(out_result, RAC_ERROR_INTERNAL, "internal vocoder failure");
    }
}

}  // extern "C"
