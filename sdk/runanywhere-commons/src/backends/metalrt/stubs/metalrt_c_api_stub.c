/**
 * @file metalrt_c_api_stub.c
 * @brief No-op implementations of the MetalRT engine C API.
 *
 * Compiled into the public build when the private MetalRT engine is not
 * available (RAC_METALRT_ENGINE_AVAILABLE=OFF, the default). Every entry
 * returns a safe sentinel so the public repo links cleanly. The wrapper
 * layer (rac_*_metalrt.cpp) + registration short-circuit to
 * RAC_ERROR_BACKEND_UNAVAILABLE before these are called at runtime, so
 * these stubs are a belt-and-suspenders safety net, not the primary error
 * surface.
 */

#include "metalrt_c_api.h"

#include <stddef.h>

// LLM ------------------------------------------------------------------------

void* metalrt_create(void) { return NULL; }
bool  metalrt_load(void* handle, const char* model_path) {
    (void)handle; (void)model_path;
    return false;
}
void  metalrt_destroy(void* handle) { (void)handle; }

struct MetalRTResult metalrt_generate(void* handle, const char* prompt,
                                      const struct MetalRTOptions* options) {
    (void)handle; (void)prompt; (void)options;
    struct MetalRTResult r = {0};
    return r;
}

struct MetalRTResult metalrt_generate_stream(void* handle, const char* prompt,
                                             metalrt_stream_cb cb, void* user_data,
                                             const struct MetalRTOptions* options) {
    (void)handle; (void)prompt; (void)cb; (void)user_data; (void)options;
    struct MetalRTResult r = {0};
    return r;
}

struct MetalRTResult metalrt_generate_raw_continue(void* handle, const char* query,
                                                   const struct MetalRTOptions* options) {
    (void)handle; (void)query; (void)options;
    struct MetalRTResult r = {0};
    return r;
}

void metalrt_free_result(struct MetalRTResult result) { (void)result; }

void metalrt_cache_prompt(void* handle, const char* text) { (void)handle; (void)text; }
void metalrt_set_system_prompt(void* handle, const char* prompt) { (void)handle; (void)prompt; }
void metalrt_clear_kv(void* handle) { (void)handle; }
void metalrt_reset(void* handle) { (void)handle; }

int         metalrt_context_size(void* handle) { (void)handle; return 0; }
const char* metalrt_model_name(void* handle) { (void)handle; return NULL; }

// STT ------------------------------------------------------------------------

void* metalrt_whisper_create(void) { return NULL; }
bool  metalrt_whisper_load(void* handle, const char* model_path) {
    (void)handle; (void)model_path;
    return false;
}
void  metalrt_whisper_destroy(void* handle) { (void)handle; }

const char* metalrt_whisper_transcribe(void* handle, const float* samples,
                                       int n_samples, int sample_rate) {
    (void)handle; (void)samples; (void)n_samples; (void)sample_rate;
    return NULL;
}

void   metalrt_whisper_free_text(const char* text) { (void)text; }
double metalrt_whisper_last_encode_ms(void* handle) { (void)handle; return 0.0; }
double metalrt_whisper_last_decode_ms(void* handle) { (void)handle; return 0.0; }

// TTS ------------------------------------------------------------------------

void* metalrt_tts_create(void) { return NULL; }
bool  metalrt_tts_load(void* handle, const char* model_path) {
    (void)handle; (void)model_path;
    return false;
}
void  metalrt_tts_destroy(void* handle) { (void)handle; }

struct MetalRTAudio metalrt_tts_synthesize(void* handle, const char* text,
                                           const char* voice, float speed) {
    (void)handle; (void)text; (void)voice; (void)speed;
    struct MetalRTAudio a = {0};
    return a;
}

void metalrt_tts_free_audio(struct MetalRTAudio audio) { (void)audio; }

// VLM ------------------------------------------------------------------------

void* metalrt_vision_create(void) { return NULL; }
bool  metalrt_vision_load(void* handle, const char* model_path) {
    (void)handle; (void)model_path;
    return false;
}
void  metalrt_vision_destroy(void* handle) { (void)handle; }
void  metalrt_vision_reset(void* handle) { (void)handle; }

struct MetalRTVisionResult metalrt_vision_analyze(void* handle, const char* image_path,
                                                  const char* prompt,
                                                  const struct MetalRTVisionOptions* options) {
    (void)handle; (void)image_path; (void)prompt; (void)options;
    struct MetalRTVisionResult r = {0};
    return r;
}

struct MetalRTVisionResult metalrt_vision_analyze_pixels(void* handle,
                                                         const uint8_t* rgba_pixels,
                                                         int width, int height,
                                                         const char* prompt,
                                                         const struct MetalRTVisionOptions* options) {
    (void)handle; (void)rgba_pixels; (void)width; (void)height; (void)prompt; (void)options;
    struct MetalRTVisionResult r = {0};
    return r;
}

struct MetalRTVisionResult metalrt_vision_analyze_stream(void* handle, const char* image_path,
                                                         const char* prompt,
                                                         metalrt_stream_cb cb, void* user_data,
                                                         const struct MetalRTVisionOptions* options) {
    (void)handle; (void)image_path; (void)prompt; (void)cb; (void)user_data; (void)options;
    struct MetalRTVisionResult r = {0};
    return r;
}

struct MetalRTVisionResult metalrt_vision_analyze_pixels_stream(void* handle,
                                                                const uint8_t* rgba_pixels,
                                                                int width, int height,
                                                                const char* prompt,
                                                                metalrt_stream_cb cb, void* user_data,
                                                                const struct MetalRTVisionOptions* options) {
    (void)handle; (void)rgba_pixels; (void)width; (void)height; (void)prompt;
    (void)cb; (void)user_data; (void)options;
    struct MetalRTVisionResult r = {0};
    return r;
}

void metalrt_vision_free_result(struct MetalRTVisionResult result) { (void)result; }
