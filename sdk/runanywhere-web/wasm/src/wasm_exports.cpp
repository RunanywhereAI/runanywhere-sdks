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
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/network/rac_http_client.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"
#include "rac/infrastructure/telemetry/rac_telemetry_types.h"

// Backends (conditionally compiled)
#ifdef RAC_WASM_LLAMACPP
#include "rac/backends/rac_llm_llamacpp.h"
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
 * Ping function for testing WASM module is loaded correctly.
 */
EMSCRIPTEN_KEEPALIVE
int rac_wasm_ping(void) {
    return 42;
}

} // extern "C"
