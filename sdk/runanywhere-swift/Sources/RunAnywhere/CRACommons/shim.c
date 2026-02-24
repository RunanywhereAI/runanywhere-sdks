// CRACommons shim file
// This file exists to ensure Xcode's Swift Package Manager integration
// can build this module. The actual implementation is in the binary target.
//
// Stub implementations below satisfy the linker for functions that are
// declared in headers but whose backends (RAG, LoRA) are not yet compiled
// into the release binary targets. At runtime these return
// RAC_ERROR_NOT_IMPLEMENTED so callers get a clear error instead of a crash.
//
// When the real backend binaries include these symbols the linker will
// prefer the strong definitions and these weak stubs are ignored.

#include "include/rac_types.h"
#include "include/rac_error.h"
#include "include/rac_llm_component.h"
#include "include/rac_rag_pipeline.h"
#include <stddef.h>

// =============================================================================
// LoRA stubs  (declared in rac_llm_component.h, not yet in RACommons binary)
// TODO: Remove these stubs once LoRA support is implemented in the
//       runanywhere-commons C++ library and compiled into RACommons.xcframework.
// =============================================================================

__attribute__((weak))
rac_result_t rac_llm_component_load_lora(rac_handle_t handle,
                                          const char* adapter_path,
                                          float scale) {
    (void)handle; (void)adapter_path; (void)scale;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Replace with real implementation in RACommons C++
}

__attribute__((weak))
rac_result_t rac_llm_component_remove_lora(rac_handle_t handle,
                                            const char* adapter_path) {
    (void)handle; (void)adapter_path;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Replace with real implementation in RACommons C++
}

__attribute__((weak))
rac_result_t rac_llm_component_clear_lora(rac_handle_t handle) {
    (void)handle;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Replace with real implementation in RACommons C++
}

__attribute__((weak))
rac_result_t rac_llm_component_get_lora_info(rac_handle_t handle,
                                              char** out_json) {
    (void)handle; (void)out_json;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Replace with real implementation in RACommons C++
}

// =============================================================================
// RAG stubs  (declared in rac_rag_pipeline.h, implemented in RABackendRAG
//             which is not included in remote-mode releases yet)
// TODO: Remove these stubs once RABackendRAG.xcframework is published to
//       GitHub releases and ragRemoteBinaryAvailable is set to true.
// =============================================================================

__attribute__((weak))
rac_result_t rac_rag_pipeline_create(const rac_rag_config_t* config,
                                      rac_rag_pipeline_t** out_pipeline) {
    (void)config; (void)out_pipeline;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Remove stub when RABackendRAG release binary is available
}

__attribute__((weak))
rac_result_t rac_rag_add_document(rac_rag_pipeline_t* pipeline,
                                   const char* document_text,
                                   const char* metadata_json) {
    (void)pipeline; (void)document_text; (void)metadata_json;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Remove stub when RABackendRAG release binary is available
}

__attribute__((weak))
rac_result_t rac_rag_add_documents_batch(rac_rag_pipeline_t* pipeline,
                                          const char** documents,
                                          const char** metadata_array,
                                          size_t count) {
    (void)pipeline; (void)documents; (void)metadata_array; (void)count;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Remove stub when RABackendRAG release binary is available
}

__attribute__((weak))
rac_result_t rac_rag_query(rac_rag_pipeline_t* pipeline,
                            const rac_rag_query_t* query,
                            rac_rag_result_t* out_result) {
    (void)pipeline; (void)query; (void)out_result;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Remove stub when RABackendRAG release binary is available
}

__attribute__((weak))
rac_result_t rac_rag_clear_documents(rac_rag_pipeline_t* pipeline) {
    (void)pipeline;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Remove stub when RABackendRAG release binary is available
}

__attribute__((weak))
size_t rac_rag_get_document_count(rac_rag_pipeline_t* pipeline) {
    (void)pipeline;
    return 0; // TODO: Remove stub when RABackendRAG release binary is available
}

__attribute__((weak))
rac_result_t rac_rag_get_statistics(rac_rag_pipeline_t* pipeline,
                                     char** out_stats_json) {
    (void)pipeline; (void)out_stats_json;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Remove stub when RABackendRAG release binary is available
}

__attribute__((weak))
void rac_rag_result_free(rac_rag_result_t* result) {
    (void)result;
    // TODO: Remove stub when RABackendRAG release binary is available
}

__attribute__((weak))
void rac_rag_pipeline_destroy(rac_rag_pipeline_t* pipeline) {
    (void)pipeline;
    // TODO: Remove stub when RABackendRAG release binary is available
}

// =============================================================================
// Voice Agent stubs  (declared in rac_voice_agent.h, not yet in RACommons binary)
// TODO: Remove these stubs once voice agent is implemented in RACommons C++.
// =============================================================================

#include "include/rac_voice_agent.h"

__attribute__((weak))
rac_result_t rac_voice_agent_process_voice_turn(rac_voice_agent_handle_t handle,
                                                 const void* audio_data, size_t audio_size,
                                                 rac_voice_agent_result_t* out_result) {
    (void)handle; (void)audio_data; (void)audio_size; (void)out_result;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Replace with real implementation
}

__attribute__((weak))
rac_result_t rac_voice_agent_transcribe(rac_voice_agent_handle_t handle,
                                         const void* audio_data, size_t audio_size,
                                         char** out_transcription) {
    (void)handle; (void)audio_data; (void)audio_size; (void)out_transcription;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Replace with real implementation
}

__attribute__((weak))
rac_result_t rac_voice_agent_synthesize_speech(rac_voice_agent_handle_t handle,
                                                const char* text, void** out_audio,
                                                size_t* out_audio_size) {
    (void)handle; (void)text; (void)out_audio; (void)out_audio_size;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Replace with real implementation
}

__attribute__((weak))
void rac_voice_agent_result_free(rac_voice_agent_result_t* result) {
    (void)result;
    // TODO: Replace with real implementation
}

// =============================================================================
// WhisperKit CoreML STT stubs
// TODO: Remove once implemented in RACommons C++.
// =============================================================================

#include "include/rac_stt_whisperkit_coreml.h"

__attribute__((weak))
rac_result_t rac_whisperkit_coreml_stt_set_callbacks(
    const rac_whisperkit_coreml_stt_callbacks_t* callbacks) {
    (void)callbacks;
    return RAC_ERROR_NOT_IMPLEMENTED; // TODO: Replace with real implementation
}
