/**
 * @file rac_sdk_emit.h
 * @brief Internal SDK-originated event emit helpers (C++).
 *
 * Classification (see docs/CPP_PROTO_OWNERSHIP.md): `internal`.
 *
 * Declarations for the rac::events::emit_* helpers implemented in
 * core/events.cpp. Each builds a canonical runanywhere.v1.SDKEvent proto payload
 * and publishes it through the destination router (sdk_event_publish.h), so the
 * event reaches the public proto stream and/or telemetry per its destination.
 *
 * Used by the JNI bridge (Kotlin-originated events) and feature layers. NOT part
 * of any public SDK surface.
 */

#ifndef RAC_SDK_EMIT_H
#define RAC_SDK_EMIT_H

#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#ifdef __cplusplus

namespace rac::events {

// LLM generation lifecycle.
void emit_llm_generation_started(const char* generation_id, const char* model_id, bool is_streaming,
                                 rac_inference_framework_t framework, float temperature,
                                 int32_t max_tokens, int32_t context_length);
void emit_llm_generation_completed(const char* generation_id, const char* model_id,
                                   int32_t input_tokens, int32_t output_tokens, double duration_ms,
                                   double tokens_per_second, bool is_streaming,
                                   double time_to_first_token_ms,
                                   rac_inference_framework_t framework, float temperature,
                                   int32_t max_tokens, int32_t context_length);
void emit_llm_generation_failed(const char* generation_id, const char* model_id,
                                rac_result_t error_code, const char* error_message);
void emit_llm_first_token(const char* generation_id, const char* model_id,
                          double time_to_first_token_ms, rac_inference_framework_t framework);
void emit_llm_streaming_update(const char* generation_id, int32_t tokens_generated);

// LLM model load lifecycle.
void emit_llm_model_load_completed(const char* model_id, const char* model_name, double duration_ms,
                                   rac_inference_framework_t framework);
void emit_llm_model_load_failed(const char* model_id, const char* model_name, double duration_ms,
                                rac_inference_framework_t framework, rac_result_t error_code,
                                const char* error_message);
void emit_llm_model_unloaded(const char* model_id);

// STT transcription lifecycle.
void emit_stt_transcription_started(const char* transcription_id, const char* model_id,
                                    double audio_length_ms, int32_t audio_size_bytes,
                                    const char* language, bool is_streaming, int32_t sample_rate,
                                    rac_inference_framework_t framework);
void emit_stt_transcription_completed(const char* transcription_id, const char* model_id,
                                      const char* text, float confidence, double duration_ms,
                                      double audio_length_ms, int32_t audio_size_bytes,
                                      int32_t word_count, double real_time_factor,
                                      const char* language, int32_t sample_rate,
                                      rac_inference_framework_t framework);
void emit_stt_transcription_failed(const char* transcription_id, const char* model_id,
                                   rac_result_t error_code, const char* error_message);

// TTS synthesis lifecycle.
void emit_tts_synthesis_started(const char* synthesis_id, const char* model_id,
                                int32_t character_count, int32_t sample_rate,
                                rac_inference_framework_t framework);
void emit_tts_synthesis_completed(const char* synthesis_id, const char* model_id,
                                  int32_t character_count, double audio_duration_ms,
                                  int32_t audio_size_bytes, double processing_duration_ms,
                                  double characters_per_second, int32_t sample_rate,
                                  rac_inference_framework_t framework);
void emit_tts_synthesis_failed(const char* synthesis_id, const char* model_id,
                               rac_result_t error_code, const char* error_message);

// VAD.
void emit_vad_started();
void emit_vad_stopped();
void emit_vad_speech_started(float energy_level);
void emit_vad_speech_ended(double speech_duration_ms, float energy_level);

// SDK lifecycle.
void emit_sdk_init_started();
void emit_sdk_init_completed(double duration_ms);
void emit_sdk_init_failed(rac_result_t error_code, const char* error_message);
void emit_sdk_models_loaded(int32_t count, double duration_ms);

// Model download / extraction / deletion.
void emit_model_download_started(const char* model_id, int64_t total_bytes,
                                 const char* archive_type);
void emit_model_download_progress(const char* model_id, double progress, int64_t bytes_downloaded,
                                  int64_t total_bytes);
void emit_model_download_completed(const char* model_id, int64_t size_bytes, double duration_ms,
                                   const char* archive_type);
void emit_model_download_failed(const char* model_id, rac_result_t error_code,
                                const char* error_message);
void emit_model_download_cancelled(const char* model_id);
void emit_model_extraction_started(const char* model_id, const char* archive_type);
void emit_model_extraction_progress(const char* model_id, double progress);
void emit_model_extraction_completed(const char* model_id, int64_t size_bytes, double duration_ms);
void emit_model_extraction_failed(const char* model_id, rac_result_t error_code,
                                  const char* error_message);
void emit_model_deleted(const char* model_id, int64_t size_bytes);

// Storage.
void emit_storage_cache_cleared(int64_t freed_bytes);
void emit_storage_cache_clear_failed(rac_result_t error_code, const char* error_message);
void emit_storage_temp_cleaned(int64_t freed_bytes);

// Device.
void emit_device_registered(const char* device_id);
void emit_device_registration_failed(rac_result_t error_code, const char* error_message);

// Network.
void emit_network_connectivity_changed(bool is_online);

// SDK error.
void emit_sdk_error(rac_result_t error_code, const char* error_message, const char* operation,
                    const char* context);

}  // namespace rac::events

#endif  // __cplusplus

#endif  // RAC_SDK_EMIT_H
