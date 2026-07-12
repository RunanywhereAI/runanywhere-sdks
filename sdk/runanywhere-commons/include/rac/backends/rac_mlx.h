/**
 * @file rac_mlx.h
 * @brief MLX engine callback bridge.
 *
 * The `mlx` engine is registered in commons as a normal plugin, but the model
 * execution lives in Swift through mlx-swift-lm. Hosts that link the optional
 * Swift MLX runtime call rac_mlx_set_callbacks() before registering the engine.
 */

#ifndef RAC_BACKENDS_RAC_MLX_H
#define RAC_BACKENDS_RAC_MLX_H

#include <stdint.h>

#if __has_include("rac/core/rac_error.h")
#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vlm/rac_vlm_service.h"
#else
#include "rac_embeddings_service.h"
#include "rac_error.h"
#include "rac_llm_service.h"
#include "rac_stt_service.h"
#include "rac_tts_service.h"
#include "rac_types.h"
#include "rac_vlm_service.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/**
 * MLX session kinds mirror runanywhere.v1.SDKComponent wire values from
 * idl/sdk_events.proto. Keep new values in IDL/codegen first, then reflect
 * them here for the C ABI shim.
 */
typedef int32_t rac_mlx_session_kind_t;

#define RAC_MLX_SESSION_KIND_STT 1
#define RAC_MLX_SESSION_KIND_TTS 2
#define RAC_MLX_SESSION_KIND_LLM 4
#define RAC_MLX_SESSION_KIND_VLM 5
#define RAC_MLX_SESSION_KIND_EMBEDDINGS 8

typedef rac_result_t (*rac_mlx_create_fn)(rac_mlx_session_kind_t kind, const char* model_id,
                                          rac_handle_t* out_handle, void* user_data);

typedef rac_result_t (*rac_mlx_initialize_fn)(rac_handle_t handle, const char* model_path,
                                              void* user_data);

typedef rac_result_t (*rac_mlx_llm_generate_fn)(rac_handle_t handle, const char* prompt,
                                                const rac_llm_options_t* options,
                                                rac_llm_result_t* out_result, void* user_data);

typedef rac_result_t (*rac_mlx_llm_generate_stream_fn)(rac_handle_t handle, const char* prompt,
                                                       const rac_llm_options_t* options,
                                                       rac_llm_stream_callback_fn callback,
                                                       void* callback_user_data, void* user_data);

typedef rac_result_t (*rac_mlx_vlm_process_fn)(rac_handle_t handle, const rac_vlm_image_t* image,
                                               const char* prompt, const rac_vlm_options_t* options,
                                               rac_vlm_result_t* out_result, void* user_data);

typedef rac_result_t (*rac_mlx_vlm_process_stream_fn)(rac_handle_t handle,
                                                      const rac_vlm_image_t* image,
                                                      const char* prompt,
                                                      const rac_vlm_options_t* options,
                                                      rac_vlm_stream_callback_fn callback,
                                                      void* callback_user_data, void* user_data);

typedef rac_result_t (*rac_mlx_embed_batch_fn)(rac_handle_t handle, const char* const* texts,
                                               size_t num_texts,
                                               const rac_embeddings_options_t* options,
                                               rac_embeddings_result_t* out_result,
                                               void* user_data);

typedef rac_result_t (*rac_mlx_embedding_info_fn)(rac_handle_t handle,
                                                  rac_embeddings_info_t* out_info, void* user_data);

typedef rac_result_t (*rac_mlx_stt_transcribe_fn)(rac_handle_t handle, const void* audio_data,
                                                  size_t audio_size,
                                                  const rac_stt_options_t* options,
                                                  rac_stt_result_t* out_result, void* user_data);

typedef rac_result_t (*rac_mlx_stt_transcribe_stream_fn)(rac_handle_t handle,
                                                         const void* audio_data, size_t audio_size,
                                                         const rac_stt_options_t* options,
                                                         rac_stt_stream_callback_t callback,
                                                         void* callback_user_data, void* user_data);

typedef rac_result_t (*rac_mlx_stt_info_fn)(rac_handle_t handle, rac_stt_info_t* out_info,
                                            void* user_data);

typedef rac_result_t (*rac_mlx_tts_synthesize_fn)(rac_handle_t handle, const char* text,
                                                  const rac_tts_options_t* options,
                                                  rac_tts_result_t* out_result, void* user_data);

typedef rac_result_t (*rac_mlx_tts_synthesize_stream_fn)(rac_handle_t handle, const char* text,
                                                         const rac_tts_options_t* options,
                                                         rac_tts_stream_callback_t callback,
                                                         void* callback_user_data, void* user_data);

typedef rac_result_t (*rac_mlx_tts_stop_fn)(rac_handle_t handle, void* user_data);
typedef rac_result_t (*rac_mlx_tts_info_fn)(rac_handle_t handle, rac_tts_info_t* out_info,
                                            void* user_data);

typedef rac_result_t (*rac_mlx_cancel_fn)(rac_handle_t handle, void* user_data);
typedef rac_result_t (*rac_mlx_cleanup_fn)(rac_handle_t handle, void* user_data);
typedef void (*rac_mlx_destroy_fn)(rac_handle_t handle, void* user_data);

typedef struct rac_mlx_callbacks {
    uint32_t struct_size;
    rac_mlx_create_fn create;
    rac_mlx_initialize_fn initialize;
    rac_mlx_llm_generate_fn llm_generate;
    rac_mlx_llm_generate_stream_fn llm_generate_stream;
    rac_mlx_vlm_process_fn vlm_process;
    rac_mlx_vlm_process_stream_fn vlm_process_stream;
    rac_mlx_embed_batch_fn embed_batch;
    rac_mlx_embedding_info_fn embedding_info;
    rac_mlx_stt_transcribe_fn stt_transcribe;
    rac_mlx_stt_transcribe_stream_fn stt_transcribe_stream;
    rac_mlx_stt_info_fn stt_info;
    rac_mlx_tts_synthesize_fn tts_synthesize;
    rac_mlx_tts_synthesize_stream_fn tts_synthesize_stream;
    rac_mlx_tts_stop_fn tts_stop;
    rac_mlx_tts_info_fn tts_info;
    rac_mlx_cancel_fn cancel;
    rac_mlx_cleanup_fn cleanup;
    rac_mlx_destroy_fn destroy;
    void* user_data;
} rac_mlx_callbacks_t;

RAC_API rac_result_t rac_mlx_set_callbacks(const rac_mlx_callbacks_t* callbacks);
RAC_API rac_bool_t rac_mlx_is_available(void);

RAC_API rac_result_t rac_backend_mlx_register(void);
RAC_API rac_result_t rac_backend_mlx_unregister(void);

#ifdef __cplusplus
}
#endif

#endif /* RAC_BACKENDS_RAC_MLX_H */
