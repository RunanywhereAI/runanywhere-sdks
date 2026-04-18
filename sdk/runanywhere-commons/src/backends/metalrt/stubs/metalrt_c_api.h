/**
 * @file metalrt_c_api.h (STUB)
 * @brief Stub declarations for the private MetalRT engine C API.
 *
 * This stub lives in the public repo so it compiles without access to the
 * closed-source MetalRT engine. When RAC_METALRT_ENGINE_AVAILABLE=ON is set
 * at configure time, the real header from the private MetalRT project is
 * included instead (CMake adjusts the include path).
 *
 * The stub struct layouts and function signatures must stay BINARY-COMPATIBLE
 * with the real private header — if the real engine changes its struct
 * layout, this stub must be updated in lockstep, otherwise an engine-enabled
 * build will mis-interpret memory.
 *
 * When the engine is not available:
 *   - Every function returns a sentinel (null handle / empty result / false)
 *     via metalrt_c_api_stub.c.
 *   - The backend's vtable entries short-circuit to RAC_ERROR_BACKEND_UNAVAILABLE
 *     before calling into the engine, so stubs are a safety net, not the
 *     primary error surface.
 */

#ifndef METALRT_C_API_STUB_H
#define METALRT_C_API_STUB_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// STRUCT LAYOUTS (public API surface — must match private header)
// =============================================================================

struct MetalRTOptions {
    int max_tokens;
    float temperature;
    int top_k;
    bool think;
    bool reset_cache;
    bool ignore_eos;
};

struct MetalRTResult {
    const char* text;  // engine-owned, freed by metalrt_free_result
    int prompt_tokens;
    int generated_tokens;
    double prefill_ms;
    double decode_ms;
    double tps;
};

struct MetalRTVisionOptions {
    int max_tokens;
    float temperature;
    int top_k;
    bool think;
};

struct MetalRTVisionResult {
    const char* text;  // engine-owned, freed by metalrt_vision_free_result
    int prompt_tokens;
    int generated_tokens;
    double prefill_ms;
    double decode_ms;
    double vision_encode_ms;
    double tps;
};

struct MetalRTAudio {
    float* samples;  // engine-owned, freed by metalrt_tts_free_audio
    int num_samples;
    int sample_rate;
    double synthesis_ms;
};

// Stream callback: returns `true` to continue, `false` to cancel.
typedef bool (*metalrt_stream_cb)(const char* piece, void* user_data);

// =============================================================================
// LLM ENGINE
// =============================================================================

void* metalrt_create(void);
bool metalrt_load(void* handle, const char* model_path);
void metalrt_destroy(void* handle);

struct MetalRTResult metalrt_generate(void* handle, const char* prompt,
                                      const struct MetalRTOptions* options);

struct MetalRTResult metalrt_generate_stream(void* handle, const char* prompt, metalrt_stream_cb cb,
                                             void* user_data, const struct MetalRTOptions* options);

struct MetalRTResult metalrt_generate_raw_continue(void* handle, const char* query,
                                                   const struct MetalRTOptions* options);

void metalrt_free_result(struct MetalRTResult result);

void metalrt_cache_prompt(void* handle, const char* text);
void metalrt_set_system_prompt(void* handle, const char* prompt);
void metalrt_clear_kv(void* handle);
void metalrt_reset(void* handle);

int metalrt_context_size(void* handle);
const char* metalrt_model_name(void* handle);

// =============================================================================
// STT ENGINE (Whisper)
// =============================================================================

void* metalrt_whisper_create(void);
bool metalrt_whisper_load(void* handle, const char* model_path);
void metalrt_whisper_destroy(void* handle);

// Returns engine-owned string; free via metalrt_whisper_free_text.
const char* metalrt_whisper_transcribe(void* handle, const float* samples, int n_samples,
                                       int sample_rate);

void metalrt_whisper_free_text(const char* text);
double metalrt_whisper_last_encode_ms(void* handle);
double metalrt_whisper_last_decode_ms(void* handle);

// =============================================================================
// TTS ENGINE (Kokoro)
// =============================================================================

void* metalrt_tts_create(void);
bool metalrt_tts_load(void* handle, const char* model_path);
void metalrt_tts_destroy(void* handle);

struct MetalRTAudio metalrt_tts_synthesize(void* handle, const char* text, const char* voice,
                                           float speed);

void metalrt_tts_free_audio(struct MetalRTAudio audio);

// =============================================================================
// VLM ENGINE (Vision)
// =============================================================================

void* metalrt_vision_create(void);
bool metalrt_vision_load(void* handle, const char* model_path);
void metalrt_vision_destroy(void* handle);
void metalrt_vision_reset(void* handle);

struct MetalRTVisionResult metalrt_vision_analyze(void* handle, const char* image_path,
                                                  const char* prompt,
                                                  const struct MetalRTVisionOptions* options);

struct MetalRTVisionResult
metalrt_vision_analyze_pixels(void* handle, const uint8_t* rgba_pixels, int width, int height,
                              const char* prompt, const struct MetalRTVisionOptions* options);

struct MetalRTVisionResult
metalrt_vision_analyze_stream(void* handle, const char* image_path, const char* prompt,
                              metalrt_stream_cb cb, void* user_data,
                              const struct MetalRTVisionOptions* options);

struct MetalRTVisionResult
metalrt_vision_analyze_pixels_stream(void* handle, const uint8_t* rgba_pixels, int width,
                                     int height, const char* prompt, metalrt_stream_cb cb,
                                     void* user_data, const struct MetalRTVisionOptions* options);

void metalrt_vision_free_result(struct MetalRTVisionResult result);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // METALRT_C_API_STUB_H
