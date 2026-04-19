// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// RunAnywhere v2 — stable C ABI for L3 primitives.
//
// Design principles:
//   * All public types are POD — no constructors, no destructors, no vtables.
//   * All handles are opaque `typedef struct ra_*_session_t ra_*_session_t`.
//   * All callbacks take a `void* user_data` tail parameter.
//   * All strings are `const char*` UTF-8, null-terminated.
//   * All byte buffers are `const unsigned char*` + `size_t` pairs.
//   * All status returns are `ra_status_t` (int). 0 = success; non-zero =
//     defined error code. Errors are NOT thrown; callers MUST check.
//   * No symbol in this header depends on libstdc++ or libc++ — callable
//     from Swift, Kotlin (JNI), Dart (FFI), Emscripten, and plain C.

#ifndef RA_PRIMITIVES_H
#define RA_PRIMITIVES_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ra_version.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Status codes
// ---------------------------------------------------------------------------
typedef int32_t ra_status_t;

enum {
    RA_OK                         = 0,
    RA_ERR_CANCELLED              = -1,
    RA_ERR_INVALID_ARGUMENT       = -2,
    RA_ERR_MODEL_LOAD_FAILED      = -3,
    RA_ERR_MODEL_NOT_FOUND        = -4,
    RA_ERR_RUNTIME_UNAVAILABLE    = -5,
    RA_ERR_BACKEND_UNAVAILABLE    = -6,
    RA_ERR_CAPABILITY_UNSUPPORTED = -7,
    RA_ERR_OUT_OF_MEMORY          = -8,
    RA_ERR_IO                     = -9,
    RA_ERR_TIMEOUT                = -10,
    RA_ERR_ABI_MISMATCH           = -11,
    RA_ERR_INTERNAL               = -99,
};

// Returns a human-readable string for the given status code. Returns a static
// pointer valid for the lifetime of the process. Never NULL.
const char* ra_status_str(ra_status_t status);

// ---------------------------------------------------------------------------
// Primitive enumeration
// ---------------------------------------------------------------------------
typedef int32_t ra_primitive_t;

enum {
    RA_PRIMITIVE_UNKNOWN       = 0,
    RA_PRIMITIVE_GENERATE_TEXT = 1,
    RA_PRIMITIVE_TRANSCRIBE    = 2,
    RA_PRIMITIVE_SYNTHESIZE    = 3,
    RA_PRIMITIVE_DETECT_VOICE  = 4,
    RA_PRIMITIVE_EMBED         = 5,
    RA_PRIMITIVE_RERANK        = 6,
    RA_PRIMITIVE_TOKENIZE      = 7,
    RA_PRIMITIVE_WAKE_WORD     = 8,
    RA_PRIMITIVE_VLM           = 9,
};

// ---------------------------------------------------------------------------
// Model formats — the L3 router uses this together with capability to pick
// a compatible engine.
// ---------------------------------------------------------------------------
typedef int32_t ra_model_format_t;

enum {
    RA_FORMAT_UNKNOWN          = 0,
    RA_FORMAT_GGUF             = 1,   // llama.cpp
    RA_FORMAT_ONNX             = 2,   // ORT + sherpa-onnx
    RA_FORMAT_COREML           = 3,
    RA_FORMAT_MLX_SAFETENSORS  = 4,
    RA_FORMAT_EXECUTORCH_PTE   = 5,
    RA_FORMAT_WHISPERKIT       = 6,
    RA_FORMAT_OPENVINO_IR      = 7,
};

// ---------------------------------------------------------------------------
// Runtime enumeration — L1 backends that L2 engines may delegate to.
// ---------------------------------------------------------------------------
typedef int32_t ra_runtime_id_t;

enum {
    RA_RUNTIME_SELF_CONTAINED = 0,  // Engine has its own kernels (llama.cpp)
    RA_RUNTIME_ORT            = 1,
    RA_RUNTIME_EXECUTORCH     = 2,
    RA_RUNTIME_MLX            = 3,
    RA_RUNTIME_COREML         = 4,
    RA_RUNTIME_METAL          = 5,
    RA_RUNTIME_CUDA           = 6,
    RA_RUNTIME_VULKAN         = 7,
    RA_RUNTIME_CPU            = 8,
};

// ---------------------------------------------------------------------------
// Opaque handles — frontends never inspect these.
// ---------------------------------------------------------------------------
typedef struct ra_engine_s     ra_engine_t;
typedef struct ra_session_s    ra_session_t;      // Generic session handle
typedef struct ra_stt_session_s ra_stt_session_t;
typedef struct ra_tts_session_s ra_tts_session_t;
typedef struct ra_vad_session_s ra_vad_session_t;
typedef struct ra_llm_session_s ra_llm_session_t;
typedef struct ra_ww_session_s  ra_ww_session_t;
typedef struct ra_embed_session_s ra_embed_session_t;

// ---------------------------------------------------------------------------
// Shared structs
// ---------------------------------------------------------------------------
typedef struct {
    const char*       model_id;
    const char*       model_path;      // Absolute path on disk
    ra_model_format_t format;
    ra_runtime_id_t   preferred_runtime;
} ra_model_spec_t;

typedef struct {
    int32_t n_gpu_layers;    // -1 = all layers on GPU, 0 = CPU-only
    int32_t n_threads;       // 0 = auto
    int32_t context_size;    // 0 = engine default
    bool    use_mmap;
    bool    use_mlock;
} ra_session_config_t;

typedef struct {
    const char* text;
    bool        is_final;
    int32_t     token_kind;  // 1=answer, 2=thought, 3=tool_call
} ra_token_output_t;

typedef struct {
    const char* text;
    bool        is_partial;
    float       confidence;
    int64_t     audio_start_us;
    int64_t     audio_end_us;
} ra_transcript_chunk_t;

typedef int32_t ra_vad_event_type_t;
enum {
    RA_VAD_EVENT_UNKNOWN        = 0,
    RA_VAD_EVENT_VOICE_START    = 1,
    RA_VAD_EVENT_VOICE_END_OF_UTTERANCE = 2,
    RA_VAD_EVENT_BARGE_IN       = 3,
    RA_VAD_EVENT_SILENCE        = 4,
};

typedef struct {
    ra_vad_event_type_t type;
    int64_t             frame_offset_us;
    float               energy;
} ra_vad_event_t;

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------
typedef void (*ra_token_callback_t)(const ra_token_output_t* token, void* user_data);
typedef void (*ra_transcript_callback_t)(const ra_transcript_chunk_t* chunk, void* user_data);
typedef void (*ra_audio_callback_t)(const float* pcm, int32_t num_samples,
                                     int32_t sample_rate, void* user_data);
typedef void (*ra_vad_callback_t)(const ra_vad_event_t* event, void* user_data);
typedef void (*ra_error_callback_t)(ra_status_t code, const char* message, void* user_data);

// ---------------------------------------------------------------------------
// L3: generate_text
// ---------------------------------------------------------------------------
typedef struct {
    const char* text;
    int32_t     conversation_id;   // -1 for stateless
} ra_prompt_t;

ra_status_t ra_llm_create(const ra_model_spec_t*     spec,
                          const ra_session_config_t* cfg,
                          ra_llm_session_t**         out_session);

void        ra_llm_destroy(ra_llm_session_t* session);

// Starts generation asynchronously. The callback fires for every token until
// is_final=true. Returns immediately. To block, use ra_llm_generate_sync.
ra_status_t ra_llm_generate(ra_llm_session_t*   session,
                            const ra_prompt_t*  prompt,
                            ra_token_callback_t on_token,
                            ra_error_callback_t on_error,
                            void*               user_data);

// Cancels an in-flight generation. Thread-safe. The callback will fire
// is_final=true after cancellation. Cancellation does NOT clear the KV cache.
ra_status_t ra_llm_cancel(ra_llm_session_t* session);

// Clears the KV cache — starts a fresh conversation.
ra_status_t ra_llm_reset(ra_llm_session_t* session);

// ---------------------------------------------------------------------------
// L3: transcribe
// ---------------------------------------------------------------------------
ra_status_t ra_stt_create(const ra_model_spec_t*     spec,
                          const ra_session_config_t* cfg,
                          ra_stt_session_t**         out_session);

void        ra_stt_destroy(ra_stt_session_t* session);

ra_status_t ra_stt_feed_audio(ra_stt_session_t* session,
                              const float*      pcm_f32,
                              int32_t           num_samples,
                              int32_t           sample_rate_hz);

ra_status_t ra_stt_flush(ra_stt_session_t* session);   // End of utterance

ra_status_t ra_stt_set_callback(ra_stt_session_t*         session,
                                ra_transcript_callback_t  on_chunk,
                                void*                     user_data);

// ---------------------------------------------------------------------------
// L3: synthesize
// ---------------------------------------------------------------------------
ra_status_t ra_tts_create(const ra_model_spec_t*     spec,
                          const ra_session_config_t* cfg,
                          ra_tts_session_t**         out_session);

void        ra_tts_destroy(ra_tts_session_t* session);

// Synthesizes `text` into PCM samples written into `out_pcm` (caller-owned).
// `max_samples` is the capacity of out_pcm; `written_samples` receives the
// actual number of samples written. Returns RA_ERR_OUT_OF_MEMORY if
// max_samples is insufficient; caller retries with a larger buffer.
ra_status_t ra_tts_synthesize(ra_tts_session_t* session,
                              const char*       text,
                              float*            out_pcm,
                              int32_t           max_samples,
                              int32_t*          written_samples,
                              int32_t*          sample_rate_hz);

ra_status_t ra_tts_cancel(ra_tts_session_t* session);

// ---------------------------------------------------------------------------
// L3: detect_voice (VAD)
// ---------------------------------------------------------------------------
ra_status_t ra_vad_create(const ra_model_spec_t*     spec,
                          const ra_session_config_t* cfg,
                          ra_vad_session_t**         out_session);

void        ra_vad_destroy(ra_vad_session_t* session);

// Feeds PCM audio. Events (voice_start/eou/barge_in/silence) are emitted via
// the callback registered with ra_vad_set_callback.
ra_status_t ra_vad_feed_audio(ra_vad_session_t* session,
                              const float*      pcm_f32,
                              int32_t           num_samples,
                              int32_t           sample_rate_hz);

ra_status_t ra_vad_set_callback(ra_vad_session_t* session,
                                ra_vad_callback_t on_event,
                                void*             user_data);

// ---------------------------------------------------------------------------
// L3: embed
// ---------------------------------------------------------------------------
ra_status_t ra_embed_create(const ra_model_spec_t*     spec,
                            const ra_session_config_t* cfg,
                            ra_embed_session_t**       out_session);

void        ra_embed_destroy(ra_embed_session_t* session);

// `out_vec` must be at least `dims` floats.
ra_status_t ra_embed_text(ra_embed_session_t* session,
                          const char*         text,
                          float*              out_vec,
                          int32_t             dims);

int32_t     ra_embed_dims(ra_embed_session_t* session);

// ---------------------------------------------------------------------------
// L3: wake_word
// ---------------------------------------------------------------------------
ra_status_t ra_ww_create(const ra_model_spec_t*     spec,
                         const char*                keyword,
                         float                      threshold,
                         ra_ww_session_t**          out_session);

void        ra_ww_destroy(ra_ww_session_t* session);

// Returns RA_OK with *detected = true on trigger, *detected = false otherwise.
// Non-blocking; run continuously on the mic stream.
ra_status_t ra_ww_feed_audio(ra_ww_session_t* session,
                             const float*     pcm_f32,
                             int32_t          num_samples,
                             int32_t          sample_rate_hz,
                             bool*            detected);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_PRIMITIVES_H
