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
    payload.has_processing_time_ms = RAC_FALSE;
    payload.success = RAC_FALSE;
    payload.has_success = RAC_FALSE;
    payload.is_streaming = RAC_FALSE;
    payload.has_is_streaming = RAC_FALSE;
    payload.is_online = RAC_FALSE;
    payload.has_is_online = RAC_FALSE;
    payload.has_voice_interrupted = RAC_FALSE;
    payload.is_probe = RAC_FALSE;
    payload.has_is_probe = RAC_FALSE;
    // Metrics use a negative "not measured" sentinel, the same convention this
    // struct already uses for battery_level and cpu_usage_percent below.
    //
    // Previously these defaulted to 0 and the serializer skipped zeros, so a
    // genuinely measured 0 (an empty generation, silence with word_count 0) was
    // indistinguishable from "never measured" and both arrived as NULL. The
    // extractors could not do better either: they read proto3 scalars, which
    // report 0 for an unset field. Those fields are now `optional` in
    // sdk_events.proto, so the extractor can tell the difference and leaves the
    // sentinel in place when the producer said nothing.
    payload.input_tokens = -1;
    payload.output_tokens = -1;
    payload.total_tokens = -1;
    payload.tokens_per_second = -1.0;
    payload.time_to_first_token_ms = -1.0;
    payload.prompt_eval_time_ms = -1.0;
    payload.generation_time_ms = -1.0;
    payload.context_length = -1;
    payload.max_tokens = -1;
    payload.audio_duration_ms = -1.0;
    payload.real_time_factor = -1.0;
    payload.word_count = -1;
    payload.confidence = -1.0;
    payload.sample_rate = -1;
    payload.character_count = -1;
    payload.characters_per_second = -1.0;
    payload.audio_size_bytes = -1;
    payload.output_duration_ms = -1.0;

    payload.battery_level = -1.0;
    payload.is_low_power_mode = RAC_FALSE;
    payload.has_is_low_power_mode = RAC_FALSE;
    payload.cpu_usage_percent = -1.0;
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
        free(static_cast<void*>(response->errors));
    }

    if (response->storage_version) {
        free((void*)response->storage_version);
    }

    memset(response, 0, sizeof(*response));
}
