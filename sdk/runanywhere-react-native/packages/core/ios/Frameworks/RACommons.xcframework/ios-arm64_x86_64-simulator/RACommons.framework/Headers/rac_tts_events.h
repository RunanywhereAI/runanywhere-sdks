/**
 * @file rac_tts_events.h
 * @brief TTS-specific event types - 1:1 port of TTSEvent.swift
 *
 * Swift Source: Sources/RunAnywhere/Features/TTS/Analytics/TTSEvent.swift
 */

#ifndef RAC_TTS_EVENTS_H
#define RAC_TTS_EVENTS_H

#include <RACommons/rac_types.h>
#include <RACommons/rac_events.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// TTS EVENT TYPES
// =============================================================================

typedef enum rac_tts_event_type {
    RAC_TTS_EVENT_SYNTHESIS_STARTED = 0,
    RAC_TTS_EVENT_SYNTHESIS_CHUNK,
    RAC_TTS_EVENT_SYNTHESIS_COMPLETED,
    RAC_TTS_EVENT_SYNTHESIS_FAILED,
} rac_tts_event_type_t;

// =============================================================================
// EVENT PUBLISHING FUNCTIONS
// =============================================================================

RAC_API rac_result_t rac_tts_event_synthesis_started(const char* synthesis_id, const char* model_id,
                                                     int32_t character_count, int32_t sample_rate,
                                                     rac_inference_framework_t framework);

RAC_API rac_result_t rac_tts_event_synthesis_chunk(const char* synthesis_id, int32_t chunk_size);

RAC_API rac_result_t rac_tts_event_synthesis_completed(
    const char* synthesis_id, const char* model_id, int32_t character_count,
    double audio_duration_ms, int32_t audio_size_bytes, double processing_duration_ms,
    double characters_per_second, int32_t sample_rate, rac_inference_framework_t framework);

RAC_API rac_result_t rac_tts_event_synthesis_failed(const char* synthesis_id, const char* model_id,
                                                    rac_result_t error_code,
                                                    const char* error_message);

RAC_API const char* rac_tts_event_type_string(rac_tts_event_type_t event_type);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_EVENTS_H */
