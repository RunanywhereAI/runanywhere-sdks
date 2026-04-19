/**
 * @file rac_vad_events.h
 * @brief VAD-specific event types - 1:1 port of VADEvent.swift
 *
 * Swift Source: Sources/RunAnywhere/Features/VAD/Analytics/VADEvent.swift
 */

#ifndef RAC_VAD_EVENTS_H
#define RAC_VAD_EVENTS_H

#include "rac_types.h"
#include "rac_events.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// VAD EVENT TYPES
// =============================================================================

typedef enum rac_vad_event_type {
    RAC_VAD_EVENT_INITIALIZED = 0,
    RAC_VAD_EVENT_INITIALIZATION_FAILED,
    RAC_VAD_EVENT_CLEANED_UP,
    RAC_VAD_EVENT_STARTED,
    RAC_VAD_EVENT_STOPPED,
    RAC_VAD_EVENT_SPEECH_STARTED,
    RAC_VAD_EVENT_SPEECH_ENDED,
    RAC_VAD_EVENT_PAUSED,
    RAC_VAD_EVENT_RESUMED,
    RAC_VAD_EVENT_MODEL_LOAD_STARTED,
    RAC_VAD_EVENT_MODEL_LOAD_COMPLETED,
    RAC_VAD_EVENT_MODEL_LOAD_FAILED,
    RAC_VAD_EVENT_MODEL_UNLOADED,
} rac_vad_event_type_t;

// =============================================================================
// EVENT PUBLISHING FUNCTIONS
// =============================================================================

RAC_API rac_result_t rac_vad_event_initialized(rac_inference_framework_t framework);

RAC_API rac_result_t rac_vad_event_initialization_failed(rac_result_t error_code,
                                                         const char* error_message,
                                                         rac_inference_framework_t framework);

RAC_API rac_result_t rac_vad_event_cleaned_up(void);
RAC_API rac_result_t rac_vad_event_started(void);
RAC_API rac_result_t rac_vad_event_stopped(void);
RAC_API rac_result_t rac_vad_event_speech_started(void);
RAC_API rac_result_t rac_vad_event_speech_ended(double duration_ms);
RAC_API rac_result_t rac_vad_event_paused(void);
RAC_API rac_result_t rac_vad_event_resumed(void);

RAC_API rac_result_t rac_vad_event_model_load_started(const char* model_id,
                                                      int64_t model_size_bytes,
                                                      rac_inference_framework_t framework);

RAC_API rac_result_t rac_vad_event_model_load_completed(const char* model_id, double duration_ms,
                                                        int64_t model_size_bytes,
                                                        rac_inference_framework_t framework);

RAC_API rac_result_t rac_vad_event_model_load_failed(const char* model_id, rac_result_t error_code,
                                                     const char* error_message,
                                                     rac_inference_framework_t framework);

RAC_API rac_result_t rac_vad_event_model_unloaded(const char* model_id);

RAC_API const char* rac_vad_event_type_string(rac_vad_event_type_t event_type);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_EVENTS_H */
