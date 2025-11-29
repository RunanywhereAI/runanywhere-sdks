#ifndef LLAMACPP_BRIDGE_WRAPPER_H
#define LLAMACPP_BRIDGE_WRAPPER_H

/**
 * RunAnywhere LlamaCPP Bridge API
 *
 * This is the C API that Swift uses to interact with the LlamaCPP backend.
 * It provides TEXT_GENERATION capability for LLM inference with GGUF models.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

// Include common types (ra_result_code, ra_device_type)
#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CAPABILITY TYPES
// =============================================================================

typedef enum {
    RA_CAP_TEXT_GENERATION = 0,
    RA_CAP_EMBEDDINGS = 1,
    RA_CAP_STT = 2,
    RA_CAP_TTS = 3,
    RA_CAP_VAD = 4,
    RA_CAP_DIARIZATION = 5
} ra_capability_type;

// =============================================================================
// HANDLE TYPES
// =============================================================================

typedef void* ra_backend_handle;

// =============================================================================
// CALLBACKS
// =============================================================================

typedef bool (*ra_text_stream_callback)(const char* token, void* user_data);

// =============================================================================
// BACKEND LIFECYCLE
// =============================================================================

const char** ra_get_available_backends(int* count);
ra_backend_handle ra_create_backend(const char* backend_name);
ra_result_code ra_initialize(ra_backend_handle handle, const char* config_json);
bool ra_is_initialized(ra_backend_handle handle);
void ra_destroy(ra_backend_handle handle);
char* ra_get_backend_info(ra_backend_handle handle);
bool ra_supports_capability(ra_backend_handle handle, ra_capability_type capability);
int ra_get_capabilities(ra_backend_handle handle, ra_capability_type* capabilities, int max_count);
ra_device_type ra_get_device(ra_backend_handle handle);
size_t ra_get_memory_usage(ra_backend_handle handle);

// =============================================================================
// TEXT GENERATION
// =============================================================================

ra_result_code ra_text_load_model(ra_backend_handle handle, const char* model_path, const char* config_json);
bool ra_text_is_model_loaded(ra_backend_handle handle);
ra_result_code ra_text_unload_model(ra_backend_handle handle);

ra_result_code ra_text_generate(
    ra_backend_handle handle,
    const char* prompt,
    const char* system_prompt,
    int max_tokens,
    float temperature,
    char** result_json
);

ra_result_code ra_text_generate_stream(
    ra_backend_handle handle,
    const char* prompt,
    const char* system_prompt,
    int max_tokens,
    float temperature,
    ra_text_stream_callback callback,
    void* user_data
);

void ra_text_cancel(ra_backend_handle handle);

// Get model info as JSON string
char* ra_text_get_model_info(ra_backend_handle handle);

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

void ra_free_string(char* str);
const char* ra_get_last_error(void);
const char* ra_get_version(void);

#ifdef __cplusplus
}
#endif

#endif // LLAMACPP_BRIDGE_WRAPPER_H
