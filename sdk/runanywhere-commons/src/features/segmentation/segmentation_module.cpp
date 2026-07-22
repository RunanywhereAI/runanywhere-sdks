/** @file segmentation_module.cpp @brief Lifecycle and proto ABI for segmentation. */

#include "segmentation_internal.h"

#include <cmath>
#include <condition_variable>
#include <cstdint>
#include <cstring>
#include <limits>
#include <memory>
#include <mutex>
#include <new>
#include <string>
#include <unordered_map>
#include <utility>

#include "features/common/rac_component_lifecycle_internal.h"
#include "features/rac_nonllm_lifecycle_bridge.h"
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_logger.h"
#include "rac/features/segmentation/rac_segmentation_component.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "segmentation.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#endif

namespace {

constexpr const char* kLogCategory = "Segmentation.Component";
constexpr uint64_t kMaxSourcePixels = 4096ULL * 4096ULL;
constexpr uint32_t kMaxSourceDimension = 4096;

struct rac_segmentation_component {
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

std::unordered_map<rac_handle_t, std::shared_ptr<rac::segmentation::ComponentLifetimeEntry>>&
lifetime_registry() {
    static std::unordered_map<rac_handle_t,
                              std::shared_ptr<rac::segmentation::ComponentLifetimeEntry>>
        value;
    return value;
}

rac::segmentation::ComponentOperationAdmittedTestHook& admitted_hook() {
    static rac::segmentation::ComponentOperationAdmittedTestHook value = nullptr;
    return value;
}

void*& admitted_hook_user_data() {
    static void* value = nullptr;
    return value;
}

thread_local rac::segmentation::ComponentOperationFrame* g_operation_frame = nullptr;

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
        auto entry = std::make_shared<rac::segmentation::ComponentLifetimeEntry>();
        entry->component = component;
        entry->lifecycle = lifecycle;
        std::lock_guard<std::mutex> lock(lifetime_mutex());
        return lifetime_registry().emplace(component, std::move(entry)).second;
    } catch (...) {
        return false;
    }
}

std::shared_ptr<rac::segmentation::ComponentLifetimeEntry> close_admission(rac_handle_t handle) {
    std::lock_guard<std::mutex> lock(lifetime_mutex());
    const auto it = lifetime_registry().find(handle);
    if (it == lifetime_registry().end() || !it->second->accepting_operations) {
        return nullptr;
    }
    it->second->accepting_operations = false;
    return it->second;
}

void wait_for_operations(const std::shared_ptr<rac::segmentation::ComponentLifetimeEntry>& entry) {
    std::unique_lock<std::mutex> lock(lifetime_mutex());
    lifetime_cv().wait(lock, [&] { return entry->active_operations == 0; });
}

rac_handle_t
remove_lifetime(rac_handle_t handle,
                const std::shared_ptr<rac::segmentation::ComponentLifetimeEntry>& entry) {
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
    rac_result_t rc = rac_segmentation_create(model_id, out_service);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    rc = rac_segmentation_initialize(*out_service, model_id);
    if (rc != RAC_SUCCESS) {
        rac_segmentation_destroy(*out_service);
        *out_service = nullptr;
    }
    return rc;
}

void destroy_component_service(rac_handle_t service, void*) {
    if (service) {
        (void)rac_segmentation_cleanup(service);
        rac_segmentation_destroy(service);
    }
}

rac_result_t protobuf_unavailable(rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
}

#if defined(RAC_HAVE_PROTOBUF)

size_t pixel_channels(runanywhere::v1::SegmentationPixelFormat format) {
    switch (format) {
        case runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGB8:
            return 3;
        case runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_RGBA8:
        case runanywhere::v1::SEGMENTATION_PIXEL_FORMAT_BGRA8:
            return 4;
        default:
            return 0;
    }
}

rac_result_t validate_request(const runanywhere::v1::SegmentationRequest& request,
                              rac_segmentation_image_t* out_image,
                              rac_segmentation_options_t* out_options) {
    if (!out_image || !out_options) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_image = {};
    *out_options = RAC_SEGMENTATION_OPTIONS_DEFAULT;
    if (!request.has_image()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    const auto& source = request.image();
    const size_t channels = pixel_channels(source.pixel_format());
    if (source.width() == 0 || source.height() == 0 || source.width() > kMaxSourceDimension ||
        source.height() > kMaxSourceDimension || channels == 0) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const uint64_t pixels = static_cast<uint64_t>(source.width()) * source.height();
    if (pixels > kMaxSourcePixels || pixels > std::numeric_limits<size_t>::max() / channels) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    const size_t expected_size = static_cast<size_t>(pixels) * channels;
    if (source.data().size() != expected_size) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    out_image->data = reinterpret_cast<const uint8_t*>(source.data().data());
    out_image->data_size = source.data().size();
    out_image->width = source.width();
    out_image->height = source.height();
    out_image->stride_bytes = static_cast<size_t>(source.width()) * channels;
    out_image->pixel_format = static_cast<rac_segmentation_pixel_format_t>(source.pixel_format());
    if (request.has_options()) {
        out_options->include_diagnostic_rgba =
            request.options().include_diagnostic_rgba() ? RAC_TRUE : RAC_FALSE;
    }
    return RAC_SUCCESS;
}

rac_result_t result_to_proto(const rac_segmentation_result_t& source, uint32_t expected_width,
                             uint32_t expected_height, bool diagnostic_requested,
                             const char* fallback_model_id,
                             runanywhere::v1::SegmentationResult* out) {
    if (!out) {
        return RAC_ERROR_NULL_POINTER;
    }
    out->Clear();
    const uint64_t pixels64 = static_cast<uint64_t>(expected_width) * expected_height;
    if (pixels64 > std::numeric_limits<size_t>::max()) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    const size_t pixels = static_cast<size_t>(pixels64);
    if (source.width != expected_width || source.height != expected_height ||
        source.class_mask_count != pixels || (pixels > 0 && !source.class_mask) ||
        source.processing_time_ms < 0) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    const size_t rgba_size = pixels * 4;
    if ((diagnostic_requested &&
         (!source.diagnostic_rgba || source.diagnostic_rgba_size != rgba_size)) ||
        (!diagnostic_requested && source.diagnostic_rgba_size != 0)) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    if (source.class_summary_count > 0 && !source.class_summaries) {
        return RAC_ERROR_ENCODING_ERROR;
    }

    std::string mask;
    try {
        mask.resize(pixels * sizeof(uint16_t));
    } catch (...) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    for (size_t i = 0; i < pixels; ++i) {
        const uint16_t value = source.class_mask[i];
        mask[i * 2] = static_cast<char>(value & 0xffU);
        mask[i * 2 + 1] = static_cast<char>((value >> 8U) & 0xffU);
    }

    uint64_t summary_pixels = 0;
    for (size_t i = 0; i < source.class_summary_count; ++i) {
        const auto& summary = source.class_summaries[i];
        if (!std::isfinite(summary.fraction) || summary.fraction < 0.0f ||
            summary.fraction > 1.0f || summary.pixel_count > pixels64 ||
            summary_pixels > pixels64 - summary.pixel_count) {
            out->Clear();
            return RAC_ERROR_ENCODING_ERROR;
        }
        summary_pixels += summary.pixel_count;
        auto* destination = out->add_class_summaries();
        destination->set_class_id(summary.class_id);
        destination->set_pixel_count(summary.pixel_count);
        destination->set_fraction(summary.fraction);
        if (summary.label) {
            destination->set_label(summary.label);
        }
    }
    if (summary_pixels != pixels64) {
        out->Clear();
        return RAC_ERROR_ENCODING_ERROR;
    }

    out->set_width(expected_width);
    out->set_height(expected_height);
    out->set_class_mask_u16_le(std::move(mask));
    if (diagnostic_requested) {
        out->set_diagnostic_rgba(source.diagnostic_rgba, source.diagnostic_rgba_size);
    }
    out->set_processing_time_ms(source.processing_time_ms);
    out->set_model_id(source.model_id ? source.model_id
                                      : (fallback_model_id ? fallback_model_id : ""));
    return RAC_SUCCESS;
}

rac_result_t segment_with_service(rac_handle_t service, const char* model_id,
                                  const uint8_t* request_bytes, size_t request_size,
                                  rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (rac_proto_bytes_validate(request_bytes, request_size) != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "SegmentationRequest bytes are invalid");
    }
    runanywhere::v1::SegmentationRequest request;
    if (!request.ParseFromArray(rac_proto_bytes_data_or_empty(request_bytes, request_size),
                                static_cast<int>(request_size))) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_DECODING_ERROR,
                                          "failed to parse SegmentationRequest");
    }

    rac_segmentation_image_t image = {};
    rac_segmentation_options_t options = RAC_SEGMENTATION_OPTIONS_DEFAULT;
    rac_result_t rc = validate_request(request, &image, &options);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_result, rc, "invalid segmentation image");
    }

    rac_segmentation_result_t raw = {};
    rc = rac_segmentation_segment(service, &image, &options, &raw);
    if (rc != RAC_SUCCESS) {
        rac_segmentation_result_free(&raw);
        return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
    }

    runanywhere::v1::SegmentationResult result;
    rc = result_to_proto(raw, image.width, image.height,
                         options.include_diagnostic_rgba == RAC_TRUE, model_id, &result);
    if (rc == RAC_SUCCESS) {
        rc = rac::proto::copy_message(result, out_result, "failed to serialize SegmentationResult");
    } else {
        (void)rac_proto_buffer_set_error(out_result, rc,
                                         "backend returned an invalid segmentation result");
    }
    rac_segmentation_result_free(&raw);
    return rc;
}

#endif  // RAC_HAVE_PROTOBUF

}  // namespace

namespace rac::segmentation {

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

}  // namespace rac::segmentation

extern "C" {

rac_result_t rac_segmentation_component_create(rac_handle_t* out_handle) {
    const rac_result_t rc = rac::features::create_lifecycle_component<rac_segmentation_component>(
        out_handle, RAC_RESOURCE_TYPE_SEGMENTATION_MODEL, "Segmentation.Lifecycle",
        create_component_service, destroy_component_service, kLogCategory,
        "Segmentation component created");
    if (rc == RAC_SUCCESS) {
        auto* component = static_cast<rac_segmentation_component*>(*out_handle);
        if (!register_lifetime(*out_handle, component->lifecycle)) {
            rac_lifecycle_destroy(component->lifecycle);
            delete component;
            *out_handle = nullptr;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }
    return rc;
}

rac_bool_t rac_segmentation_component_is_loaded(rac_handle_t handle) {
    rac::segmentation::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_FALSE;
    }
    auto* component = static_cast<rac_segmentation_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_is_loaded(component->lifecycle);
}

const char* rac_segmentation_component_get_model_id(rac_handle_t handle) {
    rac::segmentation::ComponentOperationLease lease(handle);
    if (!lease) {
        return nullptr;
    }
    auto* component = static_cast<rac_segmentation_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_model_id(component->lifecycle);
}

rac_result_t rac_segmentation_component_load_model(rac_handle_t handle, const char* model_path,
                                                   const char* model_id, const char* model_name) {
    rac::segmentation::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    if (!model_path) {
        return RAC_ERROR_NULL_POINTER;
    }
    auto* component = static_cast<rac_segmentation_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    rac_handle_t service = nullptr;
    return rac_lifecycle_load(component->lifecycle, model_path, model_id, model_name, &service);
}

rac_result_t rac_segmentation_component_unload(rac_handle_t handle) {
    rac::segmentation::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    auto* component = static_cast<rac_segmentation_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_unload(component->lifecycle);
}

rac_lifecycle_state_t rac_segmentation_component_get_state(rac_handle_t handle) {
    rac::segmentation::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_LIFECYCLE_STATE_IDLE;
    }
    auto* component = static_cast<rac_segmentation_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_state(component->lifecycle);
}

rac_result_t rac_segmentation_component_get_metrics(rac_handle_t handle,
                                                    rac_lifecycle_metrics_t* out_metrics) {
    rac::segmentation::ComponentOperationLease lease(handle);
    if (!lease) {
        return RAC_ERROR_INVALID_HANDLE;
    }
    auto* component = static_cast<rac_segmentation_component*>(lease.component());
    std::lock_guard<std::mutex> lock(component->mutex);
    return rac_lifecycle_get_metrics(component->lifecycle, out_metrics);
}

void rac_segmentation_component_destroy(rac_handle_t handle) {
    if (!handle || current_thread_has_operation(handle)) {
        if (handle) {
            RAC_LOG_WARNING(kLogCategory,
                            "Segmentation component destroy refused from re-entrant operation");
        }
        return;
    }
    const auto entry = close_admission(handle);
    if (!entry) {
        return;
    }
    wait_for_operations(entry);
    auto* component = static_cast<rac_segmentation_component*>(remove_lifetime(handle, entry));
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

rac_result_t rac_segmentation_component_segment_proto(rac_handle_t handle,
                                                      const uint8_t* request_proto_bytes,
                                                      size_t request_proto_size,
                                                      rac_proto_buffer_t* out_result) {
    rac::segmentation::ComponentOperationLease lease(handle);
    if (!lease) {
        return out_result ? rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_HANDLE,
                                                       "invalid segmentation component handle")
                          : RAC_ERROR_NULL_POINTER;
    }
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return protobuf_unavailable(out_result);
#else
    auto* component = static_cast<rac_segmentation_component*>(lease.component());
    rac_handle_t service = nullptr;
    rac_result_t rc = rac_lifecycle_acquire_service(component->lifecycle, &service);
    if (rc != RAC_SUCCESS) {
        return out_result
                   ? rac_proto_buffer_set_error(out_result, rc, "Segmentation model is not loaded")
                   : RAC_ERROR_NULL_POINTER;
    }
    const char* model_id = rac_lifecycle_get_model_id(component->lifecycle);
    rc = segment_with_service(service, model_id, request_proto_bytes, request_proto_size,
                              out_result);
    rac_lifecycle_release_service(component->lifecycle);
    return rc;
#endif
}

rac_result_t rac_segmentation_segment_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                      size_t request_proto_size,
                                                      rac_proto_buffer_t* out_result) {
#if !defined(RAC_HAVE_PROTOBUF)
    (void)request_proto_bytes;
    (void)request_proto_size;
    return protobuf_unavailable(out_result);
#else
    rac::lifecycle::LifecycleSegmentationRef ref;
    rac_result_t rc = rac::lifecycle::acquire_lifecycle_segmentation(&ref);
    if (rc != RAC_SUCCESS) {
        return out_result
                   ? rac_proto_buffer_set_error(out_result, rc, "Segmentation model is not loaded")
                   : RAC_ERROR_NULL_POINTER;
    }
    rac_segmentation_service_t service{ref.ops, ref.impl, ref.model_id};
    rc = segment_with_service(&service, ref.model_id, request_proto_bytes, request_proto_size,
                              out_result);
    rac::lifecycle::release_lifecycle_segmentation(&ref);
    return rc;
#endif
}

}  // extern "C"
