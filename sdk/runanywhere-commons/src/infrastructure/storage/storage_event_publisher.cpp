/**
 * @file storage_event_publisher.cpp
 * @brief Storage lifecycle event publishing (see storage_event_publisher.h).
 *
 * Extracted from storage_analyzer.cpp: the envelope / error / severity /
 * serialize helpers are private to this TU; only the four publish_* entry
 * points are exposed, which the analyzer calls once it has a result proto.
 */

#include "rac/infrastructure/storage/storage_event_publisher.h"

#ifdef RAC_HAVE_PROTOBUF

#include "sdk_events.pb.h"

#include <atomic>
#include <chrono>
#include <cstdio>
#include <string>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"

namespace rac::storage {
namespace {

uint64_t storage_event_time_ms() {
    using namespace std::chrono;
    return static_cast<uint64_t>(
        duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count());
}

std::string storage_event_id() {
    static std::atomic<uint64_t> counter{0};
    char id[64];
    std::snprintf(id, sizeof(id), "%llu-storage-%llu",
                  static_cast<unsigned long long>(storage_event_time_ms()),
                  static_cast<unsigned long long>(counter.fetch_add(1)));
    return id;
}

runanywhere::v1::ErrorCategory storage_error_category(rac_result_t code) {
    if (code == RAC_ERROR_INVALID_ARGUMENT || code == RAC_ERROR_NULL_POINTER ||
        code == RAC_ERROR_INVALID_INPUT || code == RAC_ERROR_DECODING_ERROR) {
        return runanywhere::v1::ERROR_CATEGORY_VALIDATION;
    }
    if (code == RAC_ERROR_MODEL_NOT_FOUND || code == RAC_ERROR_MODEL_NOT_LOADED) {
        return runanywhere::v1::ERROR_CATEGORY_MODEL;
    }
    if (code <= -180 && code >= -219) {
        return runanywhere::v1::ERROR_CATEGORY_IO;
    }
    return runanywhere::v1::ERROR_CATEGORY_INTERNAL;
}

void populate_storage_event_envelope(runanywhere::v1::SDKEvent* event,
                                     runanywhere::v1::ErrorSeverity severity) {
    if (!event) {
        return;
    }
    event->set_id(storage_event_id());
    event->set_timestamp_ms(static_cast<int64_t>(storage_event_time_ms()));
    event->set_category(runanywhere::v1::EVENT_CATEGORY_STORAGE);
    event->set_severity(severity);
    event->set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    event->set_component(runanywhere::v1::SDK_COMPONENT_UNSPECIFIED);
    event->set_source("cpp");
}

void populate_storage_error(runanywhere::v1::SDKError* error, rac_result_t code,
                            const std::string& message) {
    if (!error || code == RAC_SUCCESS) {
        return;
    }
    const int32_t c_code = static_cast<int32_t>(code);
    const int32_t abs_code = c_code < 0 ? -c_code : c_code;
    error->set_code(static_cast<runanywhere::v1::ErrorCode>(abs_code));
    error->set_category(storage_error_category(code));
    error->set_message(message.empty() ? rac_error_message(code) : message);
    error->set_c_abi_code(c_code);
    error->set_timestamp_ms(static_cast<int64_t>(storage_event_time_ms()));
    error->set_severity(runanywhere::v1::ERROR_SEVERITY_ERROR);
    error->set_component("storage");
    error->set_retryable(false);
}

runanywhere::v1::ErrorSeverity storage_event_severity(rac_result_t error_code, int warning_count) {
    if (error_code != RAC_SUCCESS) {
        return runanywhere::v1::ERROR_SEVERITY_ERROR;
    }
    if (warning_count > 0) {
        return runanywhere::v1::ERROR_SEVERITY_WARNING;
    }
    return runanywhere::v1::ERROR_SEVERITY_INFO;
}

void publish_storage_sdk_event(const runanywhere::v1::SDKEvent& event) {
    std::string bytes;
    if (!event.SerializeToString(&bytes)) {
        return;
    }
    (void)rac_sdk_event_publish_proto(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size());
}

}  // namespace

void publish_storage_info_event(const runanywhere::v1::StorageInfoResult& result,
                                rac_result_t error_code) {
    const bool failed = !result.success();
    if (failed && error_code == RAC_SUCCESS) {
        error_code = RAC_ERROR_STORAGE_ERROR;
    }
    runanywhere::v1::SDKEvent event;
    populate_storage_event_envelope(&event,
                                    storage_event_severity(error_code, result.warnings_size()));
    auto* storage = event.mutable_storage_lifecycle();
    storage->set_kind(runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_INFO_COMPLETED);
    storage->set_bytes(result.info().total_models_bytes());
    storage->mutable_info_result()->CopyFrom(result);
    if (failed) {
        storage->set_error(result.error_message());
        populate_storage_error(event.mutable_error(), error_code, result.error_message());
    }
    publish_storage_sdk_event(event);
}

void publish_storage_availability_event(const runanywhere::v1::StorageAvailabilityResult& result,
                                        rac_result_t error_code) {
    const bool failed = !result.success();
    if (failed && error_code == RAC_SUCCESS) {
        error_code = RAC_ERROR_STORAGE_ERROR;
    }
    runanywhere::v1::SDKEvent event;
    populate_storage_event_envelope(&event,
                                    storage_event_severity(error_code, result.warnings_size()));
    auto* storage = event.mutable_storage_lifecycle();
    storage->set_kind(failed ? runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_AVAILABILITY_FAILED
                             : runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_AVAILABILITY_CHECKED);
    storage->set_bytes(result.availability().available_bytes());
    storage->mutable_availability_result()->CopyFrom(result);
    if (failed) {
        storage->set_error(result.error_message());
        populate_storage_error(event.mutable_error(), error_code, result.error_message());
    }
    publish_storage_sdk_event(event);
}

void publish_storage_delete_plan_event(const runanywhere::v1::StorageDeletePlan& plan,
                                       rac_result_t error_code) {
    const bool failed = !plan.error_message().empty();
    if (failed && error_code == RAC_SUCCESS) {
        error_code = RAC_ERROR_STORAGE_ERROR;
    }
    runanywhere::v1::SDKEvent event;
    populate_storage_event_envelope(&event,
                                    storage_event_severity(error_code, plan.warnings_size()));
    auto* storage = event.mutable_storage_lifecycle();
    storage->set_kind(failed ? runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_DELETE_PLAN_FAILED
                             : runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_DELETE_PLAN_CREATED);
    storage->set_bytes(plan.reclaimable_bytes());
    storage->mutable_delete_plan()->CopyFrom(plan);
    if (failed) {
        storage->set_error(plan.error_message());
        populate_storage_error(event.mutable_error(), error_code, plan.error_message());
    }
    publish_storage_sdk_event(event);
}

void publish_storage_delete_result_event(const runanywhere::v1::StorageDeleteResult& result,
                                         rac_result_t error_code) {
    const bool failed = !result.success();
    if (failed && error_code == RAC_SUCCESS) {
        error_code = RAC_ERROR_STORAGE_ERROR;
    }
    runanywhere::v1::SDKEvent event;
    populate_storage_event_envelope(&event,
                                    storage_event_severity(error_code, result.warnings_size()));
    auto* storage = event.mutable_storage_lifecycle();
    if (result.dry_run() && result.success()) {
        storage->set_kind(runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_DELETE_DRY_RUN_COMPLETED);
    } else {
        storage->set_kind(failed ? runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_DELETE_FAILED
                                 : runanywhere::v1::STORAGE_LIFECYCLE_EVENT_KIND_DELETE_COMPLETED);
    }
    if (result.deleted_model_ids_size() == 1) {
        storage->set_model_id(result.deleted_model_ids(0));
    }
    storage->set_bytes(result.deleted_bytes());
    storage->mutable_delete_result()->CopyFrom(result);
    if (failed) {
        storage->set_error(result.error_message());
        populate_storage_error(event.mutable_error(), error_code, result.error_message());
    }
    publish_storage_sdk_event(event);
}

}  // namespace rac::storage

#endif  // RAC_HAVE_PROTOBUF
