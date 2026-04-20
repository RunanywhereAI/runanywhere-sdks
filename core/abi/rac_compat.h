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

/* --- Top-level init / logger / validators ----------------------------- */
#include "ra_core_init.h"
typedef ra_init_config_t rac_config_t;
#define rac_init                    ra_init
#define rac_shutdown                ra_shutdown
#define rac_is_initialized          ra_is_initialized
#define rac_logger_init(lvl)        (ra_logger_set_min_level(lvl), RA_OK)
#define rac_logger_shutdown()       ((void)0)
#define rac_logger_set_min_level    ra_logger_set_min_level
#define rac_logger_get_min_level    ra_logger_get_min_level
#define rac_logger_set_stderr_fallback ra_logger_set_stderr_fallback
#define rac_logger_log              ra_logger_log
#define rac_validate_api_key        ra_validate_api_key
#define rac_validate_base_url       ra_validate_base_url

/* --- SDK state / auth --------------------------------------------------- */
#include "ra_state.h"
typedef ra_environment_t             rac_environment_t;
typedef ra_auth_data_t               rac_auth_data_t;
typedef ra_auth_changed_callback_t   rac_auth_changed_callback_t;
typedef ra_state_persist_callback_t  rac_state_persist_callback_t;
typedef ra_state_load_callback_t     rac_state_load_callback_t;

#define RAC_ENVIRONMENT_DEVELOPMENT RA_ENVIRONMENT_DEVELOPMENT
#define RAC_ENVIRONMENT_STAGING     RA_ENVIRONMENT_STAGING
#define RAC_ENVIRONMENT_PRODUCTION  RA_ENVIRONMENT_PRODUCTION

#define rac_state_initialize              ra_state_initialize
#define rac_state_is_initialized          ra_state_is_initialized
#define rac_state_reset                   ra_state_reset
#define rac_state_shutdown                ra_state_shutdown
#define rac_state_get_environment         ra_state_get_environment
#define rac_state_get_base_url            ra_state_get_base_url
#define rac_state_get_api_key             ra_state_get_api_key
#define rac_state_get_device_id           ra_state_get_device_id
#define rac_state_set_auth                ra_state_set_auth
#define rac_state_get_access_token        ra_state_get_access_token
#define rac_state_get_refresh_token       ra_state_get_refresh_token
#define rac_state_is_authenticated        ra_state_is_authenticated
#define rac_state_token_needs_refresh     ra_state_token_needs_refresh
#define rac_state_get_token_expires_at    ra_state_get_token_expires_at
#define rac_state_get_user_id             ra_state_get_user_id
#define rac_state_get_organization_id     ra_state_get_organization_id
#define rac_state_clear_auth              ra_state_clear_auth
#define rac_state_set_device_registered   ra_state_set_device_registered
#define rac_state_is_device_registered    ra_state_is_device_registered
#define rac_state_on_auth_changed         ra_state_on_auth_changed
#define rac_state_set_persistence_callbacks ra_state_set_persistence_callbacks

/* --- Phase A extensions -------------------------------------------------
 *
 * Every legacy `rac_*` capability is now bridged onto a `ra_*` C ABI:
 *
 *   rac_llm_tool_calling_*       → ra_tool_call_* (ra_tool.h)
 *   rac_llm_structured_output_*  → ra_structured_output_* (ra_structured.h)
 *   rac_image_*                  → ra_image_* (ra_image.h)
 *   rac_vlm_*                    → ra_vlm_* (ra_vlm.h)
 *   rac_diffusion_*              → ra_diffusion_* (ra_diffusion.h)
 *   rac_download_manager_*       → ra_download_manager_* (ra_download.h)
 *   rac_file_manager_*           → ra_file_* (ra_file.h)
 *   rac_storage_analyzer_*       → ra_storage_* (ra_storage.h)
 *   rac_extract_*                → ra_extract_* (ra_extract.h)
 *   rac_device_manager_*         → ra_device_manager_* (ra_device.h)
 *   rac_telemetry_*              → ra_telemetry_* (ra_telemetry.h)
 *   rac_event_*, rac_analytics_* → ra_event_* (ra_event.h)
 *   rac_http_*                   → ra_http_* (ra_http.h)
 *   rac_platform_llm_*           → ra_platform_llm_* (ra_platform_llm.h)
 *   rac_benchmark_*              → ra_benchmark_* (ra_benchmark.h)
 *   rac_server_*                 → ra_server_* (ra_server.h, gated by RA_BUILD_SERVER)
 */
#include "ra_tool.h"
#include "ra_structured.h"
#include "ra_image.h"
#include "ra_vlm.h"
#include "ra_diffusion.h"
#include "ra_download.h"
#include "ra_file.h"
#include "ra_storage.h"
#include "ra_extract.h"
#include "ra_device.h"
#include "ra_telemetry.h"
#include "ra_event.h"
#include "ra_http.h"
#include "ra_platform_llm.h"
#include "ra_benchmark.h"
#include "ra_server.h"

/* Aliases for the most commonly-called legacy symbols. */
#define rac_tool_call_parse                ra_tool_call_parse
#define rac_tool_call_parse_with_format    ra_tool_call_parse_with_format
#define rac_tool_call_format_name          ra_tool_call_format_name
#define rac_tool_call_format_from_name     ra_tool_call_format_from_name
#define rac_tool_call_detect_format        ra_tool_call_detect_format
#define rac_tool_call_format_prompt        ra_tool_call_format_prompt
#define rac_tool_call_build_initial_prompt ra_tool_call_build_initial_prompt
#define rac_tool_call_build_followup_prompt ra_tool_call_build_followup_prompt

#define rac_structured_output_extract_json    ra_structured_output_extract_json
#define rac_structured_output_get_system_prompt ra_structured_output_get_system_prompt
#define rac_structured_output_prepare_prompt   ra_structured_output_prepare_prompt
#define rac_structured_output_validate         ra_structured_output_validate

#define rac_image_load_file        ra_image_load_file
#define rac_image_decode_bytes     ra_image_decode_bytes
#define rac_image_decode_base64    ra_image_decode_base64
#define rac_image_resize           ra_image_resize
#define rac_image_resize_max       ra_image_resize_max
#define rac_image_to_chw           ra_image_to_chw
#define rac_image_normalize        ra_image_normalize
#define rac_image_free             ra_image_free
#define rac_image_float_free       ra_image_float_free
#define rac_image_calc_resize      ra_image_calc_resize

#define rac_download_manager_create        ra_download_manager_create
#define rac_download_manager_destroy       ra_download_manager_destroy
#define rac_download_manager_start         ra_download_manager_start
#define rac_download_manager_cancel        ra_download_manager_cancel
#define rac_download_orchestrate           ra_download_orchestrate
#define rac_download_compute_destination   ra_download_compute_destination
#define rac_find_model_path_after_extraction ra_find_model_path_after_extraction
#define rac_download_requires_extraction   ra_download_requires_extraction

#define rac_extract_archive_native         ra_extract_archive_native
#define rac_detect_archive_type            ra_detect_archive_type

#define rac_file_manager_create_directory  ra_file_create_directory
#define rac_file_manager_remove_path       ra_file_remove_path
#define rac_file_manager_path_exists       ra_file_path_exists
#define rac_file_manager_app_support_dir   ra_file_app_support_dir
#define rac_file_manager_cache_dir         ra_file_cache_dir
#define rac_file_manager_models_dir        ra_file_models_dir
#define rac_file_manager_clear_cache       ra_file_clear_cache

#define rac_storage_analyzer_disk_space_for ra_storage_disk_space_for
#define rac_storage_analyzer_can_fit        ra_storage_can_fit
#define rac_storage_analyzer_list_models    ra_storage_list_models

#define rac_device_manager_set_callbacks    ra_device_manager_set_callbacks
#define rac_device_manager_register_if_needed ra_device_manager_register_if_needed
#define rac_device_manager_clear_registration ra_device_manager_clear_registration
#define rac_device_manager_is_registered    ra_device_manager_is_registered
#define rac_device_manager_get_device_id    ra_device_manager_get_device_id

#define rac_telemetry_manager_set_http_callback ra_telemetry_set_http_callback
#define rac_telemetry_manager_flush             ra_telemetry_flush
#define rac_telemetry_manager_track             ra_telemetry_track

#define rac_event_subscribe       ra_event_subscribe
#define rac_event_subscribe_all   ra_event_subscribe_all
#define rac_event_unsubscribe     ra_event_unsubscribe
#define rac_events_set_callback   ra_event_set_callback
#define rac_analytics_events_set_callback        ra_analytics_events_set_callback
#define rac_analytics_events_set_public_callback ra_analytics_events_set_public_callback

#define rac_http_set_executor   ra_http_set_executor
#define rac_http_has_executor   ra_http_has_executor
#define rac_http_execute        ra_http_execute

#define rac_platform_llm_set_callbacks ra_platform_llm_set_callbacks
#define rac_platform_llm_get_callbacks ra_platform_llm_get_callbacks
#define rac_platform_llm_is_available  ra_platform_llm_is_available
#define rac_backend_platform_register   ra_backend_platform_register
#define rac_backend_platform_unregister ra_backend_platform_unregister

#define rac_monotonic_now_ms          ra_monotonic_now_ms
#define rac_benchmark_timing_init     ra_benchmark_timing_init
#define rac_benchmark_timing_to_json  ra_benchmark_timing_to_json
#define rac_benchmark_stats_create    ra_benchmark_stats_create
#define rac_benchmark_stats_destroy   ra_benchmark_stats_destroy
#define rac_benchmark_stats_record    ra_benchmark_stats_record
#define rac_benchmark_stats_reset     ra_benchmark_stats_reset
#define rac_benchmark_stats_get_summary ra_benchmark_stats_get_summary

#define rac_server_start          ra_server_start
#define rac_server_stop           ra_server_stop
#define rac_server_is_running     ra_server_is_running
#define rac_server_get_status     ra_server_get_status
#define rac_server_set_request_callback ra_server_set_request_callback

#define rac_ww_feed_audio_s16     ra_ww_feed_audio_s16

#ifdef __cplusplus
}  /* extern "C" */
#endif

#endif  /* RA_ABI_RAC_COMPAT_H */
