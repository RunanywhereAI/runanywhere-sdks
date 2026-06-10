/**
 * @file storage_event_publisher.h
 * @brief Storage lifecycle event publishing.
 *
 * Emits a STORAGE-category SDKEvent for each storage operation outcome (info,
 * availability, delete-plan, delete-result). Split out of storage_analyzer.cpp
 * so the analysis logic (usage / availability / delete-plan computation) is
 * decoupled from the event-stream side effect: the analyzer computes a result
 * proto, then hands it here to be published. Proto-gated — with
 * RAC_HAVE_PROTOBUF off there are no SDKEvents to emit and this header is empty.
 */

#ifndef RAC_STORAGE_EVENT_PUBLISHER_H
#define RAC_STORAGE_EVENT_PUBLISHER_H

#ifdef RAC_HAVE_PROTOBUF

#include "rac/core/rac_types.h"

#include "storage_types.pb.h"

namespace rac::storage {

/// Publish a STORAGE_LIFECYCLE_EVENT_KIND_INFO_COMPLETED event for a storage
/// info result. @p error_code is folded into the event severity + error block.
void publish_storage_info_event(const runanywhere::v1::StorageInfoResult& result,
                                rac_result_t error_code);

/// Publish an availability-checked / availability-failed event.
void publish_storage_availability_event(const runanywhere::v1::StorageAvailabilityResult& result,
                                        rac_result_t error_code);

/// Publish a delete-plan-created / delete-plan-failed event.
void publish_storage_delete_plan_event(const runanywhere::v1::StorageDeletePlan& plan,
                                       rac_result_t error_code);

/// Publish a delete-completed / delete-dry-run / delete-failed event.
void publish_storage_delete_result_event(const runanywhere::v1::StorageDeleteResult& result,
                                         rac_result_t error_code);

}  // namespace rac::storage

#endif  // RAC_HAVE_PROTOBUF

#endif  // RAC_STORAGE_EVENT_PUBLISHER_H
