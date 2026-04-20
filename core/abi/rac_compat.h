/* SPDX-License-Identifier: Apache-2.0
 * Copyright (c) 2026 RunAnywhere AI, Inc.
 *
 * rac_compat.h — legacy-to-new ABI bridge for frontend consumers.
 *
 * During the SDK migration window, frontend packages
 * (sdk/runanywhere-swift, sdk/runanywhere-kotlin, etc.) continue to
 * call rac_* C symbols inherited from sdk/runanywhere-commons.
 * This header maps every `rac_*` they invoke onto the new `ra_*`
 * entry points in `core/abi/*.h`, so the Swift / Kotlin / Dart source
 * does NOT need to be rewritten — only the XCFramework / .so / .dylib
 * being linked needs to change.
 *
 * The mapping is mechanical: most legacy calls have an exact 1:1 new
 * equivalent. Where the call shape differs (e.g. legacy callback-based
 * generate vs. new stream-based generate), a small inline adapter lives
 * alongside the typedef.
 *
 * Frontend migration plan references:
 *   thoughts/shared/plans/v2_rearchitecture/sdk_migration/01_swift.md
 *   thoughts/shared/plans/v2_rearchitecture/sdk_migration/02_kotlin.md
 *
 * How to use: frontends include this header instead of the legacy
 * `rac_types.h` / `rac_error.h`. The public symbols look legacy
 * (ra_* aliased to rac_*), but the backing implementation is the new
 * core.
 */

#ifndef RA_ABI_RAC_COMPAT_H
#define RA_ABI_RAC_COMPAT_H

#include "ra_primitives.h"
#include "ra_version.h"
#include "ra_plugin.h"
#include "ra_errors.h"
#include "ra_platform_adapter.h"

#ifdef __cplusplus
extern "C" {
#endif

/* --- Status codes (names unchanged) -------------------------------------
 *
 * Legacy commons used the same names. rac_status_t is a typedef over
 * int32_t just like ra_status_t, and every RAC_* constant's numeric
 * value matches the corresponding RA_* constant.
 */

typedef ra_status_t rac_status_t;

#define RAC_OK                         RA_OK
#define RAC_ERR_CANCELLED              RA_ERR_CANCELLED
#define RAC_ERR_INVALID_ARGUMENT       RA_ERR_INVALID_ARGUMENT
#define RAC_ERR_MODEL_LOAD_FAILED      RA_ERR_MODEL_LOAD_FAILED
#define RAC_ERR_MODEL_NOT_FOUND        RA_ERR_MODEL_NOT_FOUND
#define RAC_ERR_RUNTIME_UNAVAILABLE    RA_ERR_RUNTIME_UNAVAILABLE
#define RAC_ERR_BACKEND_UNAVAILABLE    RA_ERR_BACKEND_UNAVAILABLE
#define RAC_ERR_CAPABILITY_UNSUPPORTED RA_ERR_CAPABILITY_UNSUPPORTED
#define RAC_ERR_OUT_OF_MEMORY          RA_ERR_OUT_OF_MEMORY
#define RAC_ERR_IO                     RA_ERR_IO
#define RAC_ERR_TIMEOUT                RA_ERR_TIMEOUT
#define RAC_ERR_ABI_MISMATCH           RA_ERR_ABI_MISMATCH
#define RAC_ERR_INTERNAL               RA_ERR_INTERNAL

#define rac_status_string ra_status_str
#define rac_error_string  ra_status_str

/* --- Primitive enum (names unchanged) ----------------------------------- */

typedef ra_primitive_t rac_primitive_t;
#define RAC_PRIMITIVE_UNKNOWN       RA_PRIMITIVE_UNKNOWN
#define RAC_PRIMITIVE_GENERATE_TEXT RA_PRIMITIVE_GENERATE_TEXT
#define RAC_PRIMITIVE_TRANSCRIBE    RA_PRIMITIVE_TRANSCRIBE
#define RAC_PRIMITIVE_SYNTHESIZE    RA_PRIMITIVE_SYNTHESIZE
#define RAC_PRIMITIVE_DETECT_VOICE  RA_PRIMITIVE_DETECT_VOICE
#define RAC_PRIMITIVE_EMBED         RA_PRIMITIVE_EMBED
#define RAC_PRIMITIVE_RERANK        RA_PRIMITIVE_RERANK
#define RAC_PRIMITIVE_TOKENIZE      RA_PRIMITIVE_TOKENIZE
#define RAC_PRIMITIVE_WAKE_WORD     RA_PRIMITIVE_WAKE_WORD
#define RAC_PRIMITIVE_VLM           RA_PRIMITIVE_VLM

/* --- Model formats (names unchanged) ------------------------------------ */

typedef ra_model_format_t rac_model_format_t;
#define RAC_FORMAT_UNKNOWN          RA_FORMAT_UNKNOWN
#define RAC_FORMAT_GGUF             RA_FORMAT_GGUF
#define RAC_FORMAT_ONNX             RA_FORMAT_ONNX
#define RAC_FORMAT_COREML           RA_FORMAT_COREML
#define RAC_FORMAT_MLX_SAFETENSORS  RA_FORMAT_MLX_SAFETENSORS
#define RAC_FORMAT_EXECUTORCH_PTE   RA_FORMAT_EXECUTORCH_PTE
#define RAC_FORMAT_WHISPERKIT       RA_FORMAT_WHISPERKIT
#define RAC_FORMAT_OPENVINO_IR      RA_FORMAT_OPENVINO_IR

/* --- Session handles (typedef aliases) ---------------------------------- */

typedef ra_llm_session_t   rac_llm_session_t;
typedef ra_stt_session_t   rac_stt_session_t;
typedef ra_tts_session_t   rac_tts_session_t;
typedef ra_vad_session_t   rac_vad_session_t;
typedef ra_embed_session_t rac_embed_session_t;
typedef ra_ww_session_t    rac_ww_session_t;

/* --- Shared structs ----------------------------------------------------- */

typedef ra_model_spec_t       rac_model_spec_t;
typedef ra_session_config_t   rac_session_config_t;
typedef ra_token_output_t     rac_token_output_t;
typedef ra_transcript_chunk_t rac_transcript_chunk_t;
typedef ra_vad_event_t        rac_vad_event_t;
typedef ra_prompt_t           rac_prompt_t;

typedef ra_token_callback_t      rac_token_callback_t;
typedef ra_transcript_callback_t rac_transcript_callback_t;
typedef ra_vad_callback_t        rac_vad_callback_t;
typedef ra_error_callback_t      rac_error_callback_t;
typedef ra_audio_callback_t      rac_audio_callback_t;

/* --- LLM -------------------------------------------------------------- */

#define rac_llm_create    ra_llm_create
#define rac_llm_destroy   ra_llm_destroy
#define rac_llm_generate  ra_llm_generate
#define rac_llm_cancel    ra_llm_cancel
#define rac_llm_reset     ra_llm_reset

/* --- STT -------------------------------------------------------------- */

#define rac_stt_create       ra_stt_create
#define rac_stt_destroy      ra_stt_destroy
#define rac_stt_feed_audio   ra_stt_feed_audio
#define rac_stt_flush        ra_stt_flush
#define rac_stt_set_callback ra_stt_set_callback

/* --- TTS -------------------------------------------------------------- */

#define rac_tts_create     ra_tts_create
#define rac_tts_destroy    ra_tts_destroy
#define rac_tts_synthesize ra_tts_synthesize
#define rac_tts_cancel     ra_tts_cancel

/* --- VAD -------------------------------------------------------------- */

#define rac_vad_create       ra_vad_create
#define rac_vad_destroy      ra_vad_destroy
#define rac_vad_feed_audio   ra_vad_feed_audio
#define rac_vad_set_callback ra_vad_set_callback

/* --- Embeddings ------------------------------------------------------- */

#define rac_embed_create  ra_embed_create
#define rac_embed_destroy ra_embed_destroy
#define rac_embed_text    ra_embed_text
#define rac_embed_dims    ra_embed_dims

/* --- Wake word -------------------------------------------------------- */

#define rac_ww_create     ra_ww_create
#define rac_ww_destroy    ra_ww_destroy
#define rac_ww_feed_audio ra_ww_feed_audio

/* --- Version / ABI ---------------------------------------------------- */

#define rac_abi_version        ra_abi_version
#define rac_plugin_api_version ra_plugin_api_version
#define rac_build_info         ra_build_info

/* --- Platform adapter --------------------------------------------------- */
typedef ra_platform_adapter_t          rac_platform_adapter_t;
typedef ra_log_level_t                 rac_log_level_t;
typedef ra_memory_info_t               rac_memory_info_t;
typedef ra_http_progress_callback_fn   rac_http_progress_callback_fn;
typedef ra_http_complete_callback_fn   rac_http_complete_callback_fn;
typedef ra_extract_progress_callback_fn rac_extract_progress_callback_fn;

#define RAC_LOG_LEVEL_TRACE RA_LOG_LEVEL_TRACE
#define RAC_LOG_LEVEL_DEBUG RA_LOG_LEVEL_DEBUG
#define RAC_LOG_LEVEL_INFO  RA_LOG_LEVEL_INFO
#define RAC_LOG_LEVEL_WARN  RA_LOG_LEVEL_WARN
#define RAC_LOG_LEVEL_ERROR RA_LOG_LEVEL_ERROR
#define RAC_LOG_LEVEL_FATAL RA_LOG_LEVEL_FATAL

#define rac_set_platform_adapter    ra_set_platform_adapter
#define rac_get_platform_adapter    ra_get_platform_adapter
#define rac_log                     ra_log
#define rac_get_current_time_ms     ra_get_current_time_ms
#define rac_http_download           ra_http_download
#define rac_http_download_cancel    ra_http_download_cancel
#define rac_extract_archive         ra_extract_archive_via_adapter

/* --- Gaps not yet bridged --------------------------------------------
 *
 * These legacy-only entry points are still only available from
 * sdk/runanywhere-commons:
 *
 *   rac_llm_tool_calling_*           → port to ra_llm_tool_calling
 *   rac_llm_structured_output_*      → port to ra_llm_structured_output
 *   rac_llm_load_lora / remove_lora  → port to ra_llm_lora_*
 *   rac_voice_agent_*                → solutions/voice-agent wrapper
 *   rac_server_*                     → port to ra_server (OpenAI HTTP server)
 *   rac_download_*                   → use core::net::HttpClient (already real)
 *   rac_extract_*                    → TODO: port rac_extraction.h
 *   rac_file_manager_*               → TODO: port rac_file_manager.h
 *   rac_telemetry_*                  → use core::net::TelemetryManager (already real)
 *   rac_http_*                       → use core::net::HttpClient (already real)
 *   rac_device_*                     → partial via core::router::HardwareProfile
 *
 * Each blocking gap is tracked in
 * thoughts/shared/plans/v2_rearchitecture/feature_parity_audit.md and
 * closed incrementally. A frontend may #include "rac_compat_legacy.h"
 * (future follow-up) for transitional wrappers to the legacy commons
 * while the remaining gaps close.
 */

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* RA_ABI_RAC_COMPAT_H */
