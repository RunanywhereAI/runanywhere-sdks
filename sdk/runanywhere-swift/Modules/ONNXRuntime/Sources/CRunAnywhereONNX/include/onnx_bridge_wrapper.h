#ifndef ONNX_BRIDGE_WRAPPER_H
#define ONNX_BRIDGE_WRAPPER_H

/**
 * RunAnywhere Unified Bridge API
 *
 * This is the C API that Swift uses to interact with ML backends.
 * It provides a capability-based interface where backends can implement
 * any subset of capabilities (STT, TTS, VAD, Text Generation, etc.)
 */

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// COMMON TYPES
// =============================================================================

// Result codes
typedef enum {
    RA_SUCCESS = 0,
    RA_ERROR_INIT_FAILED = -1,
    RA_ERROR_MODEL_LOAD_FAILED = -2,
    RA_ERROR_INFERENCE_FAILED = -3,
    RA_ERROR_INVALID_HANDLE = -4,
    RA_ERROR_INVALID_PARAMS = -5,
    RA_ERROR_OUT_OF_MEMORY = -6,
    RA_ERROR_NOT_IMPLEMENTED = -7,
    RA_ERROR_CANCELLED = -8,
    RA_ERROR_TIMEOUT = -9,
    RA_ERROR_IO = -10,
    RA_ERROR_UNKNOWN = -99
} ra_result_code;

// Device types
typedef enum {
    RA_DEVICE_CPU = 0,
    RA_DEVICE_GPU = 1,
    RA_DEVICE_NEURAL_ENGINE = 2,
    RA_DEVICE_METAL = 3,
    RA_DEVICE_CUDA = 4,
    RA_DEVICE_NNAPI = 5,
    RA_DEVICE_COREML = 6,
    RA_DEVICE_VULKAN = 7,
    RA_DEVICE_UNKNOWN = 99
} ra_device_type;

// Audio format types
typedef enum {
    RA_AUDIO_FORMAT_PCM_F32 = 0,
    RA_AUDIO_FORMAT_PCM_S16 = 1,
    RA_AUDIO_FORMAT_PCM_S32 = 2,
    RA_AUDIO_FORMAT_WAV = 10,
    RA_AUDIO_FORMAT_MP3 = 11,
    RA_AUDIO_FORMAT_FLAC = 12,
    RA_AUDIO_FORMAT_AAC = 13,
    RA_AUDIO_FORMAT_OPUS = 14
} ra_audio_format;

// Audio configuration
typedef struct {
    int sample_rate;
    int channels;
    int bits_per_sample;
    ra_audio_format format;
} ra_audio_config;

// Capability types
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
typedef void* ra_stream_handle;

// =============================================================================
// CALLBACKS
// =============================================================================

typedef bool (*ra_text_stream_callback)(const char* token, void* user_data);
typedef bool (*ra_stt_stream_callback)(const char* text, bool is_final, void* user_data);
typedef bool (*ra_tts_stream_callback)(const float* samples, size_t num_samples, bool is_final, void* user_data);
typedef void (*ra_vad_stream_callback)(bool is_speech, float probability, double timestamp_ms, void* user_data);

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

// =============================================================================
// EMBEDDINGS
// =============================================================================

ra_result_code ra_embed_load_model(ra_backend_handle handle, const char* model_path, const char* config_json);
bool ra_embed_is_model_loaded(ra_backend_handle handle);
ra_result_code ra_embed_unload_model(ra_backend_handle handle);

ra_result_code ra_embed_text(
    ra_backend_handle handle,
    const char* text,
    float** embedding,
    int* dimensions
);

ra_result_code ra_embed_batch(
    ra_backend_handle handle,
    const char** texts,
    int num_texts,
    float*** embeddings,
    int* dimensions
);

int ra_embed_get_dimensions(ra_backend_handle handle);
void ra_free_embedding(float* embedding);
void ra_free_embeddings(float** embeddings, int count);

// =============================================================================
// SPEECH-TO-TEXT (STT)
// =============================================================================

ra_result_code ra_stt_load_model(
    ra_backend_handle handle,
    const char* model_path,
    const char* model_type,
    const char* config_json
);

bool ra_stt_is_model_loaded(ra_backend_handle handle);
ra_result_code ra_stt_unload_model(ra_backend_handle handle);

ra_result_code ra_stt_transcribe(
    ra_backend_handle handle,
    const float* audio_samples,
    size_t num_samples,
    int sample_rate,
    const char* language,
    char** result_json
);

bool ra_stt_supports_streaming(ra_backend_handle handle);

ra_stream_handle ra_stt_create_stream(ra_backend_handle handle, const char* config_json);

ra_result_code ra_stt_feed_audio(
    ra_backend_handle handle,
    ra_stream_handle stream,
    const float* samples,
    size_t num_samples,
    int sample_rate
);

bool ra_stt_is_ready(ra_backend_handle handle, ra_stream_handle stream);

ra_result_code ra_stt_decode(ra_backend_handle handle, ra_stream_handle stream, char** result_json);

bool ra_stt_is_endpoint(ra_backend_handle handle, ra_stream_handle stream);

void ra_stt_input_finished(ra_backend_handle handle, ra_stream_handle stream);

void ra_stt_reset_stream(ra_backend_handle handle, ra_stream_handle stream);

void ra_stt_destroy_stream(ra_backend_handle handle, ra_stream_handle stream);

void ra_stt_cancel(ra_backend_handle handle);

// =============================================================================
// TEXT-TO-SPEECH (TTS)
// =============================================================================

ra_result_code ra_tts_load_model(
    ra_backend_handle handle,
    const char* model_path,
    const char* model_type,
    const char* config_json
);

bool ra_tts_is_model_loaded(ra_backend_handle handle);
ra_result_code ra_tts_unload_model(ra_backend_handle handle);

ra_result_code ra_tts_synthesize(
    ra_backend_handle handle,
    const char* text,
    const char* voice_id,
    float speed_rate,
    float pitch_shift,
    float** audio_samples,
    size_t* num_samples,
    int* sample_rate
);

ra_result_code ra_tts_synthesize_stream(
    ra_backend_handle handle,
    const char* text,
    const char* voice_id,
    float speed_rate,
    float pitch_shift,
    ra_tts_stream_callback callback,
    void* user_data
);

bool ra_tts_supports_streaming(ra_backend_handle handle);
char* ra_tts_get_voices(ra_backend_handle handle);
void ra_tts_cancel(ra_backend_handle handle);
void ra_free_audio(float* audio_samples);

// =============================================================================
// VOICE ACTIVITY DETECTION (VAD)
// =============================================================================

ra_result_code ra_vad_load_model(ra_backend_handle handle, const char* model_path, const char* config_json);
bool ra_vad_is_model_loaded(ra_backend_handle handle);
ra_result_code ra_vad_unload_model(ra_backend_handle handle);

ra_result_code ra_vad_process(
    ra_backend_handle handle,
    const float* samples,
    size_t num_samples,
    int sample_rate,
    bool* is_speech,
    float* probability
);

ra_result_code ra_vad_detect_segments(
    ra_backend_handle handle,
    const float* samples,
    size_t num_samples,
    int sample_rate,
    char** result_json
);

ra_stream_handle ra_vad_create_stream(ra_backend_handle handle, const char* config_json);

ra_result_code ra_vad_feed_stream(
    ra_backend_handle handle,
    ra_stream_handle stream,
    const float* samples,
    size_t num_samples,
    int sample_rate,
    bool* is_speech,
    float* probability
);

void ra_vad_destroy_stream(ra_backend_handle handle, ra_stream_handle stream);
void ra_vad_reset(ra_backend_handle handle);

// =============================================================================
// SPEAKER DIARIZATION
// =============================================================================

ra_result_code ra_diarize_load_model(ra_backend_handle handle, const char* model_path, const char* config_json);
bool ra_diarize_is_model_loaded(ra_backend_handle handle);
ra_result_code ra_diarize_unload_model(ra_backend_handle handle);

ra_result_code ra_diarize(
    ra_backend_handle handle,
    const float* samples,
    size_t num_samples,
    int sample_rate,
    int min_speakers,
    int max_speakers,
    char** result_json
);

void ra_diarize_cancel(ra_backend_handle handle);

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

void ra_free_string(char* str);
const char* ra_get_last_error(void);
const char* ra_get_version(void);

/**
 * Extract an archive (tar.bz2, tar.gz, zip) to a destination directory
 * Uses libarchive for robust cross-platform archive extraction.
 * @param archive_path Path to the archive file
 * @param dest_dir Destination directory path
 * @return RA_SUCCESS or error code
 */
ra_result_code ra_extract_archive(const char* archive_path, const char* dest_dir);

#ifdef __cplusplus
}
#endif

#endif // ONNX_BRIDGE_WRAPPER_H
