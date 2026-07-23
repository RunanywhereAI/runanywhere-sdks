/**
 * wasm_exports.cpp
 *
 * Entry point for the RACommons WASM module.
 * Ensures all exported C API functions are linked and available to JavaScript.
 *
 * This file includes all RACommons public headers so the linker doesn't
 * strip any exported symbols from the static library.
 */

#include <emscripten/emscripten.h>

#include <cstddef>

// Core
#include "rac/core/capabilities/rac_lifecycle.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_error_proto.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/core/rac_structured_error.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"

// Infrastructure
#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_download.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_dev_config.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"
#include "rac/infrastructure/telemetry/rac_telemetry_types.h"

// Backends (conditionally compiled). llama.cpp is one engine that supports
// both LLM and VLM modalities — both headers are included when the backend
// is enabled.
#ifdef RAC_WASM_LLAMACPP
#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/backends/rac_vlm_llamacpp.h"
#endif

#ifdef RAC_WASM_ONNX
#include "rac/plugin/rac_plugin_entry_onnx.h"
#include "rac/plugin/rac_plugin_entry_sherpa.h"
#endif

// Features
#include "rac/features/diffusion/rac_diffusion.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_structured_output.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/features/lora/rac_lora_service.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/features/vad/rac_vad_types.h"
#include "rac/features/vlm/rac_vlm_component.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/features/vlm/rac_vlm_types.h"
#include "rac/features/voice_agent/rac_voice_agent.h"

// Routing — STT hybrid router (offline/online dispatch) + its proto-byte ABI,
// the cross-SDK host device-state vtable, and the named custom-filter table.
// Included so the linker keeps these commons-local exports in the WASM module
// instead of dead-stripping them (mirrors the per-feature includes above). The
// matching _rac_stt_hybrid_router_* / _rac_hybrid_* symbols are listed in
// RAC_EXPORTED_FUNCTIONS_BASE in wasm/CMakeLists.txt.
#include "rac/router/hybrid/rac_hybrid_custom_filter.h"
#include "rac/router/hybrid/rac_hybrid_device_state.h"
#include "rac/router/hybrid/rac_stt_hybrid_router.h"
#include "rac/router/hybrid/rac_stt_hybrid_router_proto.h"

// Cloud STT provider registry — backs CloudSTT.registerProvider on the Web
// facade. Included so the registry symbols survive dead-stripping on targets
// that list them in RAC_EXPORTED_FUNCTIONS_CLOUD.
#include "rac/cloud/rac_cloud_stt_provider.h"

/**
 * WASM module initialization.
 * Called when the WASM module is instantiated.
 * Sets up any Emscripten-specific state.
 */
extern "C" {

EMSCRIPTEN_KEEPALIVE
int rac_wasm_get_version_major(void) {
  rac_version_t ver = rac_get_version();
  return ver.major;
}

EMSCRIPTEN_KEEPALIVE
int rac_wasm_get_version_minor(void) {
  rac_version_t ver = rac_get_version();
  return ver.minor;
}

EMSCRIPTEN_KEEPALIVE
int rac_wasm_get_version_patch(void) {
  rac_version_t ver = rac_get_version();
  return ver.patch;
}

EMSCRIPTEN_KEEPALIVE
void rac_wasm_set_client_info(const char *sdk_binding,
                              const char *app_identifier,
                              const char *app_name,
                              const char *app_version,
                              const char *app_build,
                              const char *locale,
                              const char *timezone) {
  rac_client_info_t info{};
  info.sdk_binding = sdk_binding;
  info.app_identifier = app_identifier;
  info.app_name = app_name;
  info.app_version = app_version;
  info.app_build = app_build;
  info.locale = locale;
  info.timezone = timezone;
  rac_sdk_set_client_info(&info);
}

/**
 * Helper: Get the size of rac_platform_adapter_t for JS struct allocation.
 * JavaScript needs to know the struct size to allocate WASM memory.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_platform_adapter(void) {
  return (int)sizeof(rac_platform_adapter_t);
}

/**
 * Helper: Get the size of rac_config_t for JS struct allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_config(void) { return (int)sizeof(rac_config_t); }

/**
 * Helper: Get the size of rac_llm_options_t for JS struct allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_llm_options(void) { return (int)sizeof(rac_llm_options_t); }

/**
 * Helper: Get the size of rac_llm_result_t for JS struct allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_llm_result(void) { return (int)sizeof(rac_llm_result_t); }

/**
 * Helper: Allocate and initialize a default rac_llm_options_t.
 * Returns pointer to heap-allocated struct (caller must rac_free).
 */
EMSCRIPTEN_KEEPALIVE
rac_llm_options_t *rac_wasm_create_llm_options_default(void) {
  rac_llm_options_t *opts =
      (rac_llm_options_t *)rac_alloc(sizeof(rac_llm_options_t));
  if (opts) {
    *opts = RAC_LLM_OPTIONS_DEFAULT;
  }
  return opts;
}

/**
 * Helper: Get sizeof rac_stt_options_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_stt_options(void) { return (int)sizeof(rac_stt_options_t); }

/**
 * Helper: Get sizeof rac_stt_result_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_stt_result(void) { return (int)sizeof(rac_stt_result_t); }

/**
 * Helper: Get sizeof rac_tts_options_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_tts_options(void) { return (int)sizeof(rac_tts_options_t); }

/**
 * Helper: Get sizeof rac_tts_result_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_tts_result(void) { return (int)sizeof(rac_tts_result_t); }

/**
 * Helper: Get sizeof rac_vad_config_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_vad_config(void) { return (int)sizeof(rac_vad_config_t); }

/**
 * Helper: Get sizeof rac_voice_agent_config_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_voice_agent_config(void) {
  return (int)sizeof(rac_voice_agent_config_t);
}

/**
 * Helper: Get sizeof rac_vlm_options_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_vlm_options(void) { return (int)sizeof(rac_vlm_options_t); }

/**
 * Helper: Get sizeof rac_vlm_result_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_vlm_result(void) { return (int)sizeof(rac_vlm_result_t); }

/**
 * Helper: Get sizeof rac_vlm_image_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_vlm_image(void) { return (int)sizeof(rac_vlm_image_t); }

/**
 * Helper: Get sizeof rac_diffusion_options_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_diffusion_options(void) {
  return (int)sizeof(rac_diffusion_options_t);
}

/**
 * Helper: Get sizeof rac_diffusion_result_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_diffusion_result(void) {
  return (int)sizeof(rac_diffusion_result_t);
}

/**
 * Helper: Get sizeof rac_embeddings_options_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_embeddings_options(void) {
  return (int)sizeof(rac_embeddings_options_t);
}

/**
 * Helper: Get sizeof rac_embeddings_result_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_embeddings_result(void) {
  return (int)sizeof(rac_embeddings_result_t);
}

/**
 * Ping function for testing WASM module is loaded correctly.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_ping(void) { return 42; }

/**
 * Infer the descriptor role for a single sidecar filename
 * (model-file-role-classifier family). Thin wrapper over the commons
 * classifier rac_infer_model_file_role so the Web SDK shares the same
 * heuristic as every other SDK. `modality_proto` is a proto ModelCategory
 * value; the return value is a proto ModelFileRole value
 * (MODEL_FILE_ROLE_PRIMARY_MODEL == 1 on any failure).
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_infer_model_file_role(const char *filename, int modality_proto) {
  int role = RAC_MODEL_FILE_ROLE_PRIMARY_MODEL;
  rac_infer_model_file_role(filename, modality_proto, &role);
  return role;
}

/**
 * Map a `rac_result_t` (signed C ABI error code) to a serialized
 * `runanywhere.v1.SDKError` proto buffer via the canonical commons helper
 * `rac_result_to_proto_error`. Lets the Web SDK route the rac_result_t -> proto
 * translation through the same single source of truth as every other SDK
 * (Swift's RASDKError+Helpers.swift) instead of re-mapping in TypeScript.
 *
 * `out_proto` is a `rac_proto_buffer_t*` the JS caller allocates and frees via
 * the existing proto-buffer offset/free helpers. Returns the `rac_result_t`
 * status of the serialization.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_result_to_proto_error(int code, rac_proto_buffer_t *out_proto) {
  return (int)rac_result_to_proto_error((rac_result_t)code, out_proto);
}

// =============================================================================
// FIELD OFFSET HELPERS
//
// JavaScript must not hard-code C struct field offsets — they depend on
// alignment, padding, pointer size (wasm32 vs wasm64) and compiler flags.
// Each helper below uses the compiler's offsetof() so JS always gets the
// correct offset at runtime.
//
// Naming convention:
//   rac_wasm_offsetof_<struct>_<field>()
// =============================================================================

// ---- rac_config_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_config_log_level(void) {
  return (int)offsetof(rac_config_t, log_level);
}

// ---- rac_platform_adapter_t ----
// The JS layer
// (sdk/runanywhere-web/packages/llamacpp/src/Foundation/PlatformAdapter.ts)
// packs function-pointer fields into this struct. Every field offset is
// exposed here so the TypeScript side never hard-codes `PTR_SIZE = 4` or
// a sequential accumulator — same rule as the HTTP struct helpers below.
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_platform_adapter_abi_version(void) {
  return (int)offsetof(rac_platform_adapter_t, abi_version);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_platform_adapter_struct_size(void) {
  return (int)offsetof(rac_platform_adapter_t, struct_size);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_platform_adapter_file_exists(void) {
  return (int)offsetof(rac_platform_adapter_t, file_exists);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_platform_adapter_file_read(void) {
  return (int)offsetof(rac_platform_adapter_t, file_read);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_platform_adapter_file_write(void) {
  return (int)offsetof(rac_platform_adapter_t, file_write);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_platform_adapter_file_delete(void) {
  return (int)offsetof(rac_platform_adapter_t, file_delete);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_platform_adapter_secure_get(void) {
  return (int)offsetof(rac_platform_adapter_t, secure_get);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_platform_adapter_secure_set(void) {
  return (int)offsetof(rac_platform_adapter_t, secure_set);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_platform_adapter_secure_delete(void) {
  return (int)offsetof(rac_platform_adapter_t, secure_delete);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_platform_adapter_log(void) {
  return (int)offsetof(rac_platform_adapter_t, log);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_platform_adapter_now_ms(void) {
  return (int)offsetof(rac_platform_adapter_t, now_ms);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_platform_adapter_get_memory_info(void) {
  return (int)offsetof(rac_platform_adapter_t, get_memory_info);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_platform_adapter_http_download(void) {
  return (int)offsetof(rac_platform_adapter_t, http_download);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_platform_adapter_http_download_cancel(void) {
  return (int)offsetof(rac_platform_adapter_t, http_download_cancel);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_platform_adapter_extract_archive(void) {
  return (int)offsetof(rac_platform_adapter_t, extract_archive);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_platform_adapter_file_list_directory(void) {
  return (int)offsetof(rac_platform_adapter_t, file_list_directory);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_platform_adapter_is_non_empty_directory(void) {
  return (int)offsetof(rac_platform_adapter_t, is_non_empty_directory);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_platform_adapter_get_vendor_id(void) {
  return (int)offsetof(rac_platform_adapter_t, get_vendor_id);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_platform_adapter_user_data(void) {
  return (int)offsetof(rac_platform_adapter_t, user_data);
}

EMSCRIPTEN_KEEPALIVE int rac_wasm_sizeof_directory_entry(void) {
  return (int)sizeof(rac_directory_entry_t);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_directory_entry_name(void) {
  return (int)offsetof(rac_directory_entry_t, name);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_directory_entry_is_dir(void) {
  return (int)offsetof(rac_directory_entry_t, is_dir);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_directory_entry_size_bytes(void) {
  return (int)offsetof(rac_directory_entry_t, size_bytes);
}

// ---- rac_config_t (platform_adapter field) ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_config_platform_adapter(void) {
  return (int)offsetof(rac_config_t, platform_adapter);
}

// ---- rac_llm_options_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_llm_options_max_tokens(void) {
  return (int)offsetof(rac_llm_options_t, max_tokens);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_llm_options_temperature(void) {
  return (int)offsetof(rac_llm_options_t, temperature);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_llm_options_top_p(void) {
  return (int)offsetof(rac_llm_options_t, top_p);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_llm_options_system_prompt(void) {
  return (int)offsetof(rac_llm_options_t, system_prompt);
}

// ---- rac_llm_result_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_llm_result_text(void) {
  return (int)offsetof(rac_llm_result_t, text);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_llm_result_prompt_tokens(void) {
  return (int)offsetof(rac_llm_result_t, prompt_tokens);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_llm_result_completion_tokens(void) {
  return (int)offsetof(rac_llm_result_t, completion_tokens);
}

// ---- rac_vlm_image_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_image_format(void) {
  return (int)offsetof(rac_vlm_image_t, format);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_image_file_path(void) {
  return (int)offsetof(rac_vlm_image_t, file_path);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_image_pixel_data(void) {
  return (int)offsetof(rac_vlm_image_t, pixel_data);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_image_base64_data(void) {
  return (int)offsetof(rac_vlm_image_t, base64_data);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_image_width(void) {
  return (int)offsetof(rac_vlm_image_t, width);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_image_height(void) {
  return (int)offsetof(rac_vlm_image_t, height);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_image_data_size(void) {
  return (int)offsetof(rac_vlm_image_t, data_size);
}

// ---- rac_vlm_options_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_options_max_tokens(void) {
  return (int)offsetof(rac_vlm_options_t, max_tokens);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_options_temperature(void) {
  return (int)offsetof(rac_vlm_options_t, temperature);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_options_top_p(void) {
  return (int)offsetof(rac_vlm_options_t, top_p);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_options_streaming_enabled(void) {
  return (int)offsetof(rac_vlm_options_t, streaming_enabled);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_options_system_prompt(void) {
  return (int)offsetof(rac_vlm_options_t, system_prompt);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_options_model_family(void) {
  return (int)offsetof(rac_vlm_options_t, model_family);
}

// ---- rac_vlm_result_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_result_text(void) {
  return (int)offsetof(rac_vlm_result_t, text);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_result_prompt_tokens(void) {
  return (int)offsetof(rac_vlm_result_t, prompt_tokens);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_result_image_tokens(void) {
  return (int)offsetof(rac_vlm_result_t, image_tokens);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_result_completion_tokens(void) {
  return (int)offsetof(rac_vlm_result_t, completion_tokens);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_result_total_tokens(void) {
  return (int)offsetof(rac_vlm_result_t, total_tokens);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_vlm_result_time_to_first_token_ms(void) {
  return (int)offsetof(rac_vlm_result_t, time_to_first_token_ms);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_vlm_result_image_encode_time_ms(void) {
  return (int)offsetof(rac_vlm_result_t, image_encode_time_ms);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_result_total_time_ms(void) {
  return (int)offsetof(rac_vlm_result_t, total_time_ms);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_result_tokens_per_second(void) {
  return (int)offsetof(rac_vlm_result_t, tokens_per_second);
}

// ---- rac_embeddings_options_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_embeddings_options_normalize(void) {
  return (int)offsetof(rac_embeddings_options_t, normalize);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_embeddings_options_pooling(void) {
  return (int)offsetof(rac_embeddings_options_t, pooling);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_embeddings_options_n_threads(void) {
  return (int)offsetof(rac_embeddings_options_t, n_threads);
}

// ---- rac_embeddings_result_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_embeddings_result_embeddings(void) {
  return (int)offsetof(rac_embeddings_result_t, embeddings);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_embeddings_result_num_embeddings(void) {
  return (int)offsetof(rac_embeddings_result_t, num_embeddings);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_embeddings_result_dimension(void) {
  return (int)offsetof(rac_embeddings_result_t, dimension);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_embeddings_result_processing_time_ms(void) {
  return (int)offsetof(rac_embeddings_result_t, processing_time_ms);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_embeddings_result_total_tokens(void) {
  return (int)offsetof(rac_embeddings_result_t, total_tokens);
}

// ---- rac_embedding_vector_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_sizeof_embedding_vector(void) {
  return (int)sizeof(rac_embedding_vector_t);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_embedding_vector_data(void) {
  return (int)offsetof(rac_embedding_vector_t, data);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_embedding_vector_dimension(void) {
  return (int)offsetof(rac_embedding_vector_t, dimension);
}

// ---- rac_diffusion_options_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_prompt(void) {
  return (int)offsetof(rac_diffusion_options_t, prompt);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_diffusion_options_negative_prompt(void) {
  return (int)offsetof(rac_diffusion_options_t, negative_prompt);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_width(void) {
  return (int)offsetof(rac_diffusion_options_t, width);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_height(void) {
  return (int)offsetof(rac_diffusion_options_t, height);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_steps(void) {
  return (int)offsetof(rac_diffusion_options_t, steps);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_diffusion_options_guidance_scale(void) {
  return (int)offsetof(rac_diffusion_options_t, guidance_scale);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_seed(void) {
  return (int)offsetof(rac_diffusion_options_t, seed);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_scheduler(void) {
  return (int)offsetof(rac_diffusion_options_t, scheduler);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_mode(void) {
  return (int)offsetof(rac_diffusion_options_t, mode);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_diffusion_options_denoise_strength(void) {
  return (int)offsetof(rac_diffusion_options_t, denoise_strength);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_diffusion_options_report_intermediate_images(void) {
  return (int)offsetof(rac_diffusion_options_t, report_intermediate_images);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_diffusion_options_progress_stride(void) {
  return (int)offsetof(rac_diffusion_options_t, progress_stride);
}

// ---- rac_diffusion_result_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_result_image_data(void) {
  return (int)offsetof(rac_diffusion_result_t, image_data);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_result_image_size(void) {
  return (int)offsetof(rac_diffusion_result_t, image_size);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_result_width(void) {
  return (int)offsetof(rac_diffusion_result_t, width);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_result_height(void) {
  return (int)offsetof(rac_diffusion_result_t, height);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_result_seed_used(void) {
  return (int)offsetof(rac_diffusion_result_t, seed_used);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_diffusion_result_generation_time_ms(void) {
  return (int)offsetof(rac_diffusion_result_t, generation_time_ms);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_diffusion_result_safety_flagged(void) {
  return (int)offsetof(rac_diffusion_result_t, safety_flagged);
}

// =============================================================================
// DEVICE REGISTRATION STRUCT HELPERS
//
// The Web host installs typed JavaScript callbacks into the commons device
// manager. Expose compiler-derived layouts for every struct field the host
// touches so wasm32 padding or future C ABI changes cannot corrupt memory.
// =============================================================================

// ---- rac_device_callbacks_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_sizeof_device_callbacks(void) {
  return (int)sizeof(rac_device_callbacks_t);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_callbacks_get_device_info(void) {
  return (int)offsetof(rac_device_callbacks_t, get_device_info);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_callbacks_get_device_id(void) {
  return (int)offsetof(rac_device_callbacks_t, get_device_id);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_callbacks_is_registered(void) {
  return (int)offsetof(rac_device_callbacks_t, is_registered);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_callbacks_set_registered(void) {
  return (int)offsetof(rac_device_callbacks_t, set_registered);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_callbacks_http_post(void) {
  return (int)offsetof(rac_device_callbacks_t, http_post);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_callbacks_user_data(void) {
  return (int)offsetof(rac_device_callbacks_t, user_data);
}

// ---- rac_device_registration_info_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_sizeof_device_registration_info(void) {
  return (int)sizeof(rac_device_registration_info_t);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_device_id(void) {
  return (int)offsetof(rac_device_registration_info_t, device_id);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_device_model(void) {
  return (int)offsetof(rac_device_registration_info_t, device_model);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_device_name(void) {
  return (int)offsetof(rac_device_registration_info_t, device_name);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_platform(void) {
  return (int)offsetof(rac_device_registration_info_t, platform);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_os_version(void) {
  return (int)offsetof(rac_device_registration_info_t, os_version);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_form_factor(void) {
  return (int)offsetof(rac_device_registration_info_t, form_factor);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_architecture(void) {
  return (int)offsetof(rac_device_registration_info_t, architecture);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_chip_name(void) {
  return (int)offsetof(rac_device_registration_info_t, chip_name);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_total_memory(void) {
  return (int)offsetof(rac_device_registration_info_t, total_memory);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_available_memory(void) {
  return (int)offsetof(rac_device_registration_info_t, available_memory);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_has_neural_engine(void) {
  return (int)offsetof(rac_device_registration_info_t, has_neural_engine);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_neural_engine_cores(void) {
  return (int)offsetof(rac_device_registration_info_t, neural_engine_cores);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_gpu_family(void) {
  return (int)offsetof(rac_device_registration_info_t, gpu_family);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_battery_level(void) {
  return (int)offsetof(rac_device_registration_info_t, battery_level);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_battery_state(void) {
  return (int)offsetof(rac_device_registration_info_t, battery_state);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_is_low_power_mode(void) {
  return (int)offsetof(rac_device_registration_info_t, is_low_power_mode);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_core_count(void) {
  return (int)offsetof(rac_device_registration_info_t, core_count);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_performance_cores(void) {
  return (int)offsetof(rac_device_registration_info_t, performance_cores);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_efficiency_cores(void) {
  return (int)offsetof(rac_device_registration_info_t, efficiency_cores);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_registration_info_device_fingerprint(void) {
  return (int)offsetof(rac_device_registration_info_t, device_fingerprint);
}

// ---- rac_device_http_response_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_sizeof_device_http_response(void) {
  return (int)sizeof(rac_device_http_response_t);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_http_response_result(void) {
  return (int)offsetof(rac_device_http_response_t, result);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_http_response_status_code(void) {
  return (int)offsetof(rac_device_http_response_t, status_code);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_http_response_response_body(void) {
  return (int)offsetof(rac_device_http_response_t, response_body);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_device_http_response_error_message(void) {
  return (int)offsetof(rac_device_http_response_t, error_message);
}

// =============================================================================
// STORAGE ANALYZER CALLBACK STRUCT HELPERS
//
// The browser installs JavaScript callbacks into rac_storage_callbacks_t.
// Keep every offset compiler-derived so wasm32 padding or future field changes
// cannot corrupt the callback table.
// =============================================================================

EMSCRIPTEN_KEEPALIVE int rac_wasm_sizeof_storage_callbacks(void) {
  return (int)sizeof(rac_storage_callbacks_t);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_storage_callbacks_calculate_dir_size(void) {
  return (int)offsetof(rac_storage_callbacks_t, calculate_dir_size);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_storage_callbacks_get_file_size(void) {
  return (int)offsetof(rac_storage_callbacks_t, get_file_size);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_storage_callbacks_path_exists(void) {
  return (int)offsetof(rac_storage_callbacks_t, path_exists);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_storage_callbacks_get_available_space(void) {
  return (int)offsetof(rac_storage_callbacks_t, get_available_space);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_storage_callbacks_get_total_space(void) {
  return (int)offsetof(rac_storage_callbacks_t, get_total_space);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_storage_callbacks_delete_path(void) {
  return (int)offsetof(rac_storage_callbacks_t, delete_path);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_storage_callbacks_is_model_loaded(void) {
  return (int)offsetof(rac_storage_callbacks_t, is_model_loaded);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_storage_callbacks_unload_model(void) {
  return (int)offsetof(rac_storage_callbacks_t, unload_model);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_storage_callbacks_user_data(void) {
  return (int)offsetof(rac_storage_callbacks_t, user_data);
}

// =============================================================================
// HTTP CLIENT STRUCT HELPERS
//
// T3.13 — Web SDK migrates off hand-rolled fetch() onto the commons libcurl-
// backed C ABI. Rather than hard-coding struct layouts in TypeScript
// (which breaks on wasm32 padding / future field additions), expose
// sizeof() and offsetof() for every field the TS HTTPAdapter touches.
// =============================================================================

// ---- rac_http_request_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_sizeof_http_request(void) {
  return (int)sizeof(rac_http_request_t);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_request_method(void) {
  return (int)offsetof(rac_http_request_t, method);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_request_url(void) {
  return (int)offsetof(rac_http_request_t, url);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_request_headers(void) {
  return (int)offsetof(rac_http_request_t, headers);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_request_header_count(void) {
  return (int)offsetof(rac_http_request_t, header_count);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_request_body_bytes(void) {
  return (int)offsetof(rac_http_request_t, body_bytes);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_request_body_len(void) {
  return (int)offsetof(rac_http_request_t, body_len);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_request_timeout_ms(void) {
  return (int)offsetof(rac_http_request_t, timeout_ms);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_request_follow_redirects(void) {
  return (int)offsetof(rac_http_request_t, follow_redirects);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_http_request_expected_checksum_hex(void) {
  return (int)offsetof(rac_http_request_t, expected_checksum_hex);
}

// ---- rac_http_response_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_sizeof_http_response(void) {
  return (int)sizeof(rac_http_response_t);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_response_status(void) {
  return (int)offsetof(rac_http_response_t, status);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_response_headers(void) {
  return (int)offsetof(rac_http_response_t, headers);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_response_header_count(void) {
  return (int)offsetof(rac_http_response_t, header_count);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_response_body_bytes(void) {
  return (int)offsetof(rac_http_response_t, body_bytes);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_response_body_len(void) {
  return (int)offsetof(rac_http_response_t, body_len);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_response_redirected_url(void) {
  return (int)offsetof(rac_http_response_t, redirected_url);
}

// ---- rac_http_header_kv_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_sizeof_http_header_kv(void) {
  return (int)sizeof(rac_http_header_kv_t);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_header_kv_name(void) {
  return (int)offsetof(rac_http_header_kv_t, name);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_header_kv_value(void) {
  return (int)offsetof(rac_http_header_kv_t, value);
}

// ---- rac_http_download_request_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_sizeof_http_download_request(void) {
  return (int)sizeof(rac_http_download_request_t);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_download_request_url(void) {
  return (int)offsetof(rac_http_download_request_t, url);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_http_download_request_destination_path(void) {
  return (int)offsetof(rac_http_download_request_t, destination_path);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_http_download_request_headers(void) {
  return (int)offsetof(rac_http_download_request_t, headers);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_http_download_request_header_count(void) {
  return (int)offsetof(rac_http_download_request_t, header_count);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_http_download_request_timeout_ms(void) {
  return (int)offsetof(rac_http_download_request_t, timeout_ms);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_http_download_request_follow_redirects(void) {
  return (int)offsetof(rac_http_download_request_t, follow_redirects);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_http_download_request_resume_from_byte(void) {
  return (int)offsetof(rac_http_download_request_t, resume_from_byte);
}
EMSCRIPTEN_KEEPALIVE int
rac_wasm_offsetof_http_download_request_expected_sha256_hex(void) {
  return (int)offsetof(rac_http_download_request_t, expected_sha256_hex);
}

// ---- rac_proto_buffer_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_sizeof_proto_buffer(void) {
  return (int)sizeof(rac_proto_buffer_t);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_proto_buffer_data(void) {
  return (int)offsetof(rac_proto_buffer_t, data);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_proto_buffer_size(void) {
  return (int)offsetof(rac_proto_buffer_t, size);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_proto_buffer_status(void) {
  return (int)offsetof(rac_proto_buffer_t, status);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_proto_buffer_error_message(void) {
  return (int)offsetof(rac_proto_buffer_t, error_message);
}

// =============================================================================
// FILE MANAGER WRAPPERS (clearCache / cleanTempFiles)
//
// Web has no rac_file_callbacks_t bridge (the platform-adapter file slots are
// TS-side stubs), so these shims build the callbacks in C++ against the
// module's own filesystem (Emscripten MEMFS under the synthetic /opfs base) —
// the same pattern as build_jni_file_callbacks() in runanywhere_commons_jni.cpp.
// Path computation and the delete-recursive + recreate semantics stay in
// commons (rac_file_manager_clear_cache/clear_temp → {base}/RunAnywhere/
// Cache|Temp). std::filesystem against MEMFS is proven in this build
// (rac_http_download.cpp, download_orchestrator.cpp).
// =============================================================================

} // extern "C"

#include <filesystem>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "rac/infrastructure/file_management/rac_file_manager.h"

namespace {

namespace fs = std::filesystem;

rac_result_t wasm_fc_create_directory(const char *path, int recursive, void *) {
  if (path == nullptr || path[0] == '\0') return RAC_ERROR_INVALID_PARAMETER;
  std::error_code ec;
  if (recursive != 0) {
    fs::create_directories(path, ec);
  } else {
    fs::create_directory(path, ec);
  }
  // "Already exists" is success for both commons callers and POSIX mkdir -p.
  if (ec && !fs::exists(path)) return RAC_ERROR_FILE_WRITE_FAILED;
  return RAC_SUCCESS;
}

rac_result_t wasm_fc_delete_path(const char *path, int recursive, void *) {
  if (path == nullptr || path[0] == '\0') return RAC_ERROR_INVALID_PARAMETER;
  std::error_code ec;
  if (recursive != 0) {
    fs::remove_all(path, ec);
  } else {
    fs::remove(path, ec);
  }
  return ec ? RAC_ERROR_DELETE_FAILED : RAC_SUCCESS;
}

rac_result_t wasm_fc_list_directory(const char *path, char ***out_entries, size_t *out_count,
                                    void *) {
  if (path == nullptr || out_entries == nullptr || out_count == nullptr) {
    return RAC_ERROR_INVALID_PARAMETER;
  }
  *out_entries = nullptr;
  *out_count = 0;
  std::error_code ec;
  std::vector<std::string> names;
  for (fs::directory_iterator it(path, ec), end; !ec && it != end; it.increment(ec)) {
    names.push_back(it->path().filename().string());
  }
  if (ec) return RAC_ERROR_FILE_READ_FAILED;
  if (names.empty()) return RAC_SUCCESS;
  auto **entries = static_cast<char **>(std::malloc(names.size() * sizeof(char *)));
  if (entries == nullptr) return RAC_ERROR_OUT_OF_MEMORY;
  for (size_t i = 0; i < names.size(); ++i) {
    entries[i] = static_cast<char *>(std::malloc(names[i].size() + 1));
    if (entries[i] == nullptr) {
      for (size_t j = 0; j < i; ++j) std::free(entries[j]);
      std::free(entries);
      return RAC_ERROR_OUT_OF_MEMORY;
    }
    std::memcpy(entries[i], names[i].c_str(), names[i].size() + 1);
  }
  *out_entries = entries;
  *out_count = names.size();
  return RAC_SUCCESS;
}

void wasm_fc_free_entries(char **entries, size_t count, void *) {
  if (entries == nullptr) return;
  for (size_t i = 0; i < count; ++i) std::free(entries[i]);
  std::free(entries);
}

rac_bool_t wasm_fc_path_exists(const char *path, rac_bool_t *out_is_directory, void *) {
  if (out_is_directory != nullptr) *out_is_directory = RAC_FALSE;
  if (path == nullptr || path[0] == '\0') return RAC_FALSE;
  std::error_code ec;
  const bool exists = fs::exists(path, ec);
  if (ec || !exists) return RAC_FALSE;
  if (out_is_directory != nullptr) {
    *out_is_directory = fs::is_directory(path, ec) && !ec ? RAC_TRUE : RAC_FALSE;
  }
  return RAC_TRUE;
}

int64_t wasm_fc_get_file_size(const char *path, void *) {
  if (path == nullptr || path[0] == '\0') return -1;
  std::error_code ec;
  const auto size = fs::file_size(path, ec);
  return ec ? -1 : static_cast<int64_t>(size);
}

// The clear paths never consult disk-space; report "unknown" like the JNI
// bridge does for unsupported queries.
int64_t wasm_fc_get_available_space(void *) { return -1; }
int64_t wasm_fc_get_total_space(void *) { return -1; }

rac_file_callbacks_t make_wasm_file_callbacks() {
  rac_file_callbacks_t cb = {};
  cb.create_directory = wasm_fc_create_directory;
  cb.delete_path = wasm_fc_delete_path;
  cb.list_directory = wasm_fc_list_directory;
  cb.free_entries = wasm_fc_free_entries;
  cb.path_exists = wasm_fc_path_exists;
  cb.get_file_size = wasm_fc_get_file_size;
  cb.get_available_space = wasm_fc_get_available_space;
  cb.get_total_space = wasm_fc_get_total_space;
  cb.user_data = nullptr;
  return cb;
}

}  // namespace

extern "C" {

EMSCRIPTEN_KEEPALIVE
int rac_wasm_file_manager_clear_cache(void) {
  rac_file_callbacks_t cb = make_wasm_file_callbacks();
  return static_cast<int>(rac_file_manager_clear_cache(&cb));
}

EMSCRIPTEN_KEEPALIVE
int rac_wasm_file_manager_clear_temp(void) {
  rac_file_callbacks_t cb = make_wasm_file_callbacks();
  return static_cast<int>(rac_file_manager_clear_temp(&cb));
}

// ── Model-category / framework capability wrappers (proto-int ABI) ──────────
// The proto enums and the C enums use different numeric values, so these
// wrappers convert via rac_*_from_proto / _to_proto before delegating. They
// back the Web SDK's ModelTypes helpers — the same C helpers Swift routes
// through (RAModelCategory.requiresContextLength / .supportsThinking,
// rac_model_category_default_framework, rac_framework_display_name) — so the
// capability/display tables live in commons, not in each SDK's TS.

EMSCRIPTEN_KEEPALIVE
int rac_model_category_requires_context_length_proto(int proto_category) {
  rac_model_category_t category = RAC_MODEL_CATEGORY_UNKNOWN;
  if (rac_model_category_from_proto(static_cast<int32_t>(proto_category), &category) !=
      RAC_SUCCESS) {
    return 0;
  }
  return rac_model_category_requires_context_length(category) == RAC_TRUE ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE
int rac_model_category_supports_thinking_proto(int proto_category) {
  rac_model_category_t category = RAC_MODEL_CATEGORY_UNKNOWN;
  if (rac_model_category_from_proto(static_cast<int32_t>(proto_category), &category) !=
      RAC_SUCCESS) {
    return 0;
  }
  return rac_model_category_supports_thinking(category) == RAC_TRUE ? 1 : 0;
}

/** Returns the proto InferenceFramework value for a proto ModelCategory. */
EMSCRIPTEN_KEEPALIVE
int rac_model_category_default_framework_proto(int proto_category) {
  rac_model_category_t category = RAC_MODEL_CATEGORY_UNKNOWN;
  if (rac_model_category_from_proto(static_cast<int32_t>(proto_category), &category) !=
      RAC_SUCCESS) {
    return 0;
  }
  const rac_inference_framework_t framework = rac_model_category_default_framework(category);
  int32_t proto_framework = 0;
  if (rac_inference_framework_to_proto(framework, &proto_framework) != RAC_SUCCESS) {
    return 0;
  }
  return static_cast<int>(proto_framework);
}

/** Display name for a proto InferenceFramework value (static literal — do not free). */
EMSCRIPTEN_KEEPALIVE
const char* rac_framework_display_name_proto(int proto_framework) {
  rac_inference_framework_t framework = RAC_FRAMEWORK_UNKNOWN;
  if (rac_inference_framework_from_proto(static_cast<int32_t>(proto_framework), &framework) !=
      RAC_SUCCESS) {
    return "";
  }
  return rac_framework_display_name(framework);
}

} // extern "C"
