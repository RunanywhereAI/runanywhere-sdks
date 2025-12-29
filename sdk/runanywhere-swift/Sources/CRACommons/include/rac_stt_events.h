/**
 * @file rac_stt_events.h
 * @brief STT-specific event types - 1:1 port of STTEvent.swift
 *
 * Swift Source: Sources/RunAnywhere/Features/STT/Analytics/STTEvent.swift
 */

#ifndef RAC_STT_EVENTS_H
#define RAC_STT_EVENTS_H

#include "rac_types.h"
#include "rac_events.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// STT EVENT TYPES
// =============================================================================

typedef enum rac_stt_event_type {
    RAC_STT_EVENT_TRANSCRIPTION_STARTED = 0,
    RAC_STT_EVENT_PARTIAL_TRANSCRIPT,
    RAC_STT_EVENT_FINAL_TRANSCRIPT,
    RAC_STT_EVENT_TRANSCRIPTION_COMPLETED,
    RAC_STT_EVENT_TRANSCRIPTION_FAILED,
    RAC_STT_EVENT_LANGUAGE_DETECTED,
} rac_stt_event_type_t;

// =============================================================================
// EVENT PUBLISHING FUNCTIONS
// =============================================================================

RAC_API rac_result_t rac_stt_event_transcription_started(
    const char* transcription_id, const char* model_id, double audio_length_ms,
    int32_t audio_size_bytes, const char* language, rac_bool_t is_streaming,
    rac_inference_framework_t framework);

RAC_API rac_result_t rac_stt_event_partial_transcript(const char* text, int32_t word_count);

RAC_API rac_result_t rac_stt_event_final_transcript(const char* text, float confidence);

RAC_API rac_result_t rac_stt_event_transcription_completed(
    const char* transcription_id, const char* model_id, const char* text, float confidence,
    double duration_ms, double audio_length_ms, int32_t word_count, double real_time_factor,
    const char* language, rac_bool_t is_streaming, rac_inference_framework_t framework);

RAC_API rac_result_t rac_stt_event_transcription_failed(const char* transcription_id,
                                                        const char* model_id,
                                                        rac_result_t error_code,
                                                        const char* error_message);

RAC_API rac_result_t rac_stt_event_language_detected(const char* language, float confidence);

RAC_API const char* rac_stt_event_type_string(rac_stt_event_type_t event_type);

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_EVENTS_H */
