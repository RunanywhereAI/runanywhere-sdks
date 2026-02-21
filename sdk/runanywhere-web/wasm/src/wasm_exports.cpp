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

// Core
#include "rac/core/rac_analytics_events.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_types.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/core/rac_structured_error.h"
#include "rac/core/capabilities/rac_lifecycle.h"

// Infrastructure
#include "rac/infrastructure/events/rac_events.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/network/rac_dev_config.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/network/rac_http_client.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"
#include "rac/infrastructure/telemetry/rac_telemetry_types.h"

// Backends (conditionally compiled)
#ifdef RAC_WASM_LLAMACPP
#include "rac/backends/rac_llm_llamacpp.h"
#endif

#if defined(RAC_WASM_LLAMACPP) && defined(RAC_WASM_VLM)
#include "rac/backends/rac_vlm_llamacpp.h"
#endif

#ifdef RAC_WASM_WHISPERCPP
#include "rac/backends/rac_stt_whispercpp.h"
#endif

#ifdef RAC_WASM_ONNX
#include "rac/backends/rac_tts_onnx.h"
#include "rac/backends/rac_vad_onnx.h"
#endif

// Features
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_types.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/features/vad/rac_vad_types.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/features/vlm/rac_vlm_types.h"
#include "rac/features/vlm/rac_vlm_component.h"
#include "rac/features/diffusion/rac_diffusion.h"
#include "rac/features/embeddings/rac_embeddings.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/llm/rac_llm_structured_output.h"

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
int rac_wasm_sizeof_config(void) {
    return (int)sizeof(rac_config_t);
}

/**
 * Helper: Get the size of rac_llm_options_t for JS struct allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_llm_options(void) {
    return (int)sizeof(rac_llm_options_t);
}

/**
 * Helper: Get the size of rac_llm_result_t for JS struct allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_llm_result(void) {
    return (int)sizeof(rac_llm_result_t);
}

/**
 * Helper: Allocate and initialize a default rac_llm_options_t.
 * Returns pointer to heap-allocated struct (caller must rac_free).
 */
EMSCRIPTEN_KEEPALIVE
rac_llm_options_t* rac_wasm_create_llm_options_default(void) {
    rac_llm_options_t* opts = (rac_llm_options_t*)rac_alloc(sizeof(rac_llm_options_t));
    if (opts) {
        *opts = RAC_LLM_OPTIONS_DEFAULT;
    }
    return opts;
}

/**
 * Helper: Get sizeof rac_stt_options_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_stt_options(void) {
    return (int)sizeof(rac_stt_options_t);
}

/**
 * Helper: Get sizeof rac_stt_result_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_stt_result(void) {
    return (int)sizeof(rac_stt_result_t);
}

/**
 * Helper: Get sizeof rac_tts_options_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_tts_options(void) {
    return (int)sizeof(rac_tts_options_t);
}

/**
 * Helper: Get sizeof rac_tts_result_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_tts_result(void) {
    return (int)sizeof(rac_tts_result_t);
}

/**
 * Helper: Get sizeof rac_vad_config_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_vad_config(void) {
    return (int)sizeof(rac_vad_config_t);
}

/**
 * Helper: Get sizeof rac_voice_agent_config_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_voice_agent_config(void) {
    return (int)sizeof(rac_voice_agent_config_t);
}

/**
 * Helper: Get sizeof rac_voice_agent_result_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_voice_agent_result(void) {
    return (int)sizeof(rac_voice_agent_result_t);
}

/**
 * Helper: Get sizeof rac_vlm_options_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_vlm_options(void) {
    return (int)sizeof(rac_vlm_options_t);
}

/**
 * Helper: Get sizeof rac_vlm_result_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_vlm_result(void) {
    return (int)sizeof(rac_vlm_result_t);
}

/**
 * Helper: Get sizeof rac_vlm_image_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_vlm_image(void) {
    return (int)sizeof(rac_vlm_image_t);
}

/**
 * Helper: Get sizeof rac_structured_output_config_t for JS allocation.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_sizeof_structured_output_config(void) {
    return (int)sizeof(rac_structured_output_config_t);
}

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
int rac_wasm_ping(void) {
    return 42;
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

#include <cstddef>  // offsetof

// ---- rac_config_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_config_log_level(void) {
    return (int)offsetof(rac_config_t, log_level);
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
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_result_time_to_first_token_ms(void) {
    return (int)offsetof(rac_vlm_result_t, time_to_first_token_ms);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_result_image_encode_time_ms(void) {
    return (int)offsetof(rac_vlm_result_t, image_encode_time_ms);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_result_total_time_ms(void) {
    return (int)offsetof(rac_vlm_result_t, total_time_ms);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_vlm_result_tokens_per_second(void) {
    return (int)offsetof(rac_vlm_result_t, tokens_per_second);
}

// ---- rac_structured_output_config_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_structured_output_config_json_schema(void) {
    return (int)offsetof(rac_structured_output_config_t, json_schema);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_structured_output_config_include_schema(void) {
    return (int)offsetof(rac_structured_output_config_t, include_schema_in_prompt);
}

// ---- rac_structured_output_validation_t ----
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_structured_output_validation_is_valid(void) {
    return (int)offsetof(rac_structured_output_validation_t, is_valid);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_structured_output_validation_error_message(void) {
    return (int)offsetof(rac_structured_output_validation_t, error_message);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_structured_output_validation_extracted_json(void) {
    return (int)offsetof(rac_structured_output_validation_t, extracted_json);
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
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_embeddings_result_num_embeddings(void) {
    return (int)offsetof(rac_embeddings_result_t, num_embeddings);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_embeddings_result_dimension(void) {
    return (int)offsetof(rac_embeddings_result_t, dimension);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_embeddings_result_processing_time_ms(void) {
    return (int)offsetof(rac_embeddings_result_t, processing_time_ms);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_embeddings_result_total_tokens(void) {
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
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_negative_prompt(void) {
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
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_guidance_scale(void) {
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
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_denoise_strength(void) {
    return (int)offsetof(rac_diffusion_options_t, denoise_strength);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_report_intermediate(void) {
    return (int)offsetof(rac_diffusion_options_t, report_intermediate_images);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_options_progress_stride(void) {
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
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_result_generation_time_ms(void) {
    return (int)offsetof(rac_diffusion_result_t, generation_time_ms);
}
EMSCRIPTEN_KEEPALIVE int rac_wasm_offsetof_diffusion_result_safety_flagged(void) {
    return (int)offsetof(rac_diffusion_result_t, safety_flagged);
}

// =============================================================================
// DEV CONFIG WRAPPERS
//
// Expose development configuration values (Supabase URL/key, build token)
// so that the TypeScript HTTP layer can use them for dev-mode telemetry.
// =============================================================================

EMSCRIPTEN_KEEPALIVE
int rac_wasm_dev_config_is_available(void) {
    return rac_dev_config_is_available() ? 1 : 0;
}

EMSCRIPTEN_KEEPALIVE
const char* rac_wasm_dev_config_get_supabase_url(void) {
    return rac_dev_config_get_supabase_url();
}

EMSCRIPTEN_KEEPALIVE
const char* rac_wasm_dev_config_get_supabase_key(void) {
    return rac_dev_config_get_supabase_key();
}

EMSCRIPTEN_KEEPALIVE
const char* rac_wasm_dev_config_get_build_token(void) {
    return rac_dev_config_get_build_token();
}

} // extern "C"
