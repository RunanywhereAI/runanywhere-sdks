/**
 * @file rac_modality_proto_abi.h
 * @brief Optional generated-proto modality ABI declarations.
 *
 * Swift resolves these symbols with dlsym so older RACommons binaries can
 * report an explicit unsupported-symbol error instead of hard-linking.
 */

#ifndef RAC_MODALITY_PROTO_ABI_H
#define RAC_MODALITY_PROTO_ABI_H

#include <stddef.h>
#include <stdint.h>

#include "rac_error.h"
#include "rac_lora_registry.h"
#include "rac_proto_buffer.h"
#include "rac_types.h"
#include "rac_voice_agent.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*rac_modality_proto_callback_fn)(const uint8_t* data,
                                               size_t size,
                                               void* user_data);

typedef rac_bool_t (*rac_modality_proto_control_callback_fn)(const uint8_t* data,
                                                             size_t size,
                                                             void* user_data);

// LLM service proto ABI.
RAC_API rac_result_t rac_llm_generate_proto(const uint8_t* request_bytes,
                                            size_t request_size,
                                            rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_llm_generate_stream_proto(
    const uint8_t* request_bytes,
    size_t request_size,
    rac_modality_proto_callback_fn callback,
    void* user_data);
RAC_API rac_result_t rac_llm_cancel_proto(rac_proto_buffer_t* out_event);

// STT component proto ABI.
RAC_API rac_result_t rac_stt_component_transcribe_proto(
    rac_handle_t handle,
    const void* audio_data,
    size_t audio_size,
    const uint8_t* options_bytes,
    size_t options_size,
    rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_stt_component_transcribe_stream_proto(
    rac_handle_t handle,
    const void* audio_data,
    size_t audio_size,
    const uint8_t* options_bytes,
    size_t options_size,
    rac_modality_proto_callback_fn callback,
    void* user_data);

// TTS component proto ABI.
RAC_API rac_result_t rac_tts_component_list_voices_proto(
    rac_handle_t handle,
    rac_modality_proto_callback_fn callback,
    void* user_data);
RAC_API rac_result_t rac_tts_component_synthesize_proto(
    rac_handle_t handle,
    const char* text,
    const uint8_t* options_bytes,
    size_t options_size,
    rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_tts_component_synthesize_stream_proto(
    rac_handle_t handle,
    const char* text,
    const uint8_t* options_bytes,
    size_t options_size,
    rac_modality_proto_callback_fn callback,
    void* user_data);

// VAD component proto ABI.
RAC_API rac_result_t rac_vad_component_configure_proto(
    rac_handle_t handle,
    const uint8_t* config_bytes,
    size_t config_size);
RAC_API rac_result_t rac_vad_component_process_proto(
    rac_handle_t handle,
    const float* samples,
    size_t num_samples,
    const uint8_t* options_bytes,
    size_t options_size,
    rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_vad_component_get_statistics_proto(
    rac_handle_t handle,
    rac_proto_buffer_t* out_statistics);
RAC_API rac_result_t rac_vad_component_set_activity_proto_callback(
    rac_handle_t handle,
    rac_modality_proto_callback_fn callback,
    void* user_data);

// Voice-agent proto ABI.
RAC_API rac_result_t rac_voice_agent_initialize_proto(
    rac_voice_agent_handle_t handle,
    const uint8_t* config_bytes,
    size_t config_size,
    rac_proto_buffer_t* out_component_states);
RAC_API rac_result_t rac_voice_agent_component_states_proto(
    rac_voice_agent_handle_t handle,
    rac_proto_buffer_t* out_component_states);
RAC_API rac_result_t rac_voice_agent_process_voice_turn_proto(
    rac_voice_agent_handle_t handle,
    const void* audio_data,
    size_t audio_size,
    rac_proto_buffer_t* out_result);

// VLM proto ABI.
RAC_API rac_result_t rac_vlm_process_proto(rac_handle_t handle,
                                           const uint8_t* image_bytes,
                                           size_t image_size,
                                           const uint8_t* options_bytes,
                                           size_t options_size,
                                           rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_vlm_process_stream_proto(
    rac_handle_t handle,
    const uint8_t* image_bytes,
    size_t image_size,
    const uint8_t* options_bytes,
    size_t options_size,
    rac_modality_proto_control_callback_fn callback,
    void* user_data,
    rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_vlm_cancel_proto(rac_handle_t handle);

// Embeddings proto ABI.
RAC_API rac_result_t rac_embeddings_embed_batch_proto(
    rac_handle_t handle,
    const uint8_t* request_bytes,
    size_t request_size,
    rac_proto_buffer_t* out_result);

// RAG proto ABI.
RAC_API rac_result_t rac_rag_session_create_proto(const uint8_t* config_bytes,
                                                  size_t config_size,
                                                  rac_handle_t* out_session);
RAC_API void rac_rag_session_destroy_proto(rac_handle_t session);
RAC_API rac_result_t rac_rag_ingest_proto(rac_handle_t session,
                                          const uint8_t* document_bytes,
                                          size_t document_size,
                                          rac_proto_buffer_t* out_statistics);
RAC_API rac_result_t rac_rag_query_proto(rac_handle_t session,
                                         const uint8_t* query_bytes,
                                         size_t query_size,
                                         rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_rag_clear_proto(rac_handle_t session,
                                         rac_proto_buffer_t* out_statistics);
RAC_API rac_result_t rac_rag_stats_proto(rac_handle_t session,
                                         rac_proto_buffer_t* out_statistics);

// LoRA proto ABI.
RAC_API rac_result_t rac_lora_register_proto(
    rac_lora_registry_handle_t registry,
    const uint8_t* entry_bytes,
    size_t entry_size,
    rac_proto_buffer_t* out_entry);
RAC_API rac_result_t rac_lora_compatibility_proto(
    rac_handle_t llm_component,
    const uint8_t* config_bytes,
    size_t config_size,
    rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_lora_load_proto(rac_handle_t llm_component,
                                         const uint8_t* config_bytes,
                                         size_t config_size,
                                         rac_proto_buffer_t* out_info);
RAC_API rac_result_t rac_lora_remove_proto(rac_handle_t llm_component,
                                           const uint8_t* config_bytes,
                                           size_t config_size,
                                           rac_proto_buffer_t* out_info);
RAC_API rac_result_t rac_lora_clear_proto(rac_handle_t llm_component,
                                          rac_proto_buffer_t* out_info);

// Diffusion proto ABI.
RAC_API rac_result_t rac_diffusion_generate_proto(
    rac_handle_t handle,
    const uint8_t* options_bytes,
    size_t options_size,
    rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_diffusion_generate_with_progress_proto(
    rac_handle_t handle,
    const uint8_t* options_bytes,
    size_t options_size,
    rac_modality_proto_control_callback_fn callback,
    void* user_data,
    rac_proto_buffer_t* out_result);
RAC_API rac_result_t rac_diffusion_cancel_proto(rac_handle_t handle);

#ifdef __cplusplus
}
#endif

#endif /* RAC_MODALITY_PROTO_ABI_H */
