/**
 * @file telemetry_types.cpp
 * @brief Implementation of telemetry type utilities
 */

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/telemetry/rac_telemetry_types.h"

rac_telemetry_payload_t rac_telemetry_payload_default(void) {
    rac_telemetry_payload_t payload = {};
    payload.success = RAC_FALSE;
    payload.has_success = RAC_FALSE;
    payload.is_streaming = RAC_FALSE;
    payload.has_is_streaming = RAC_FALSE;
    payload.is_online = RAC_FALSE;
    payload.has_is_online = RAC_FALSE;
    return payload;
}

void rac_telemetry_payload_free(rac_telemetry_payload_t* payload) {
    if (!payload)
        return;

    // Note: We don't free strings here because they're typically
    // either static or owned by the caller. The manager handles
    // string allocation/deallocation for queued events.

    // Reset to default
    *payload = rac_telemetry_payload_default();
}

void rac_telemetry_batch_response_free(rac_telemetry_batch_response_t* response) {
    if (!response)
        return;

    if (response->errors) {
        for (size_t i = 0; i < response->errors_count; i++) {
            free((void*)response->errors[i]);
        }
        free(response->errors);
    }

    if (response->storage_version) {
        free((void*)response->storage_version);
    }

    memset(response, 0, sizeof(*response));
}
