#ifndef ONNX_BRIDGE_WRAPPER_H
#define ONNX_BRIDGE_WRAPPER_H

// This wrapper re-exports the XCFramework headers with proper types
// to avoid module.modulemap conflicts in Xcode builds

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque handle types
typedef void* ra_onnx_handle;

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
    RA_ERROR_UNKNOWN = -99
} ra_result_code;

// Modality types
typedef enum {
    RA_MODALITY_TEXT_TO_TEXT = 0,
    RA_MODALITY_VOICE_TO_TEXT = 1,
    RA_MODALITY_TEXT_TO_VOICE = 2,
    RA_MODALITY_IMAGE_TO_TEXT = 3,
    RA_MODALITY_TEXT_TO_IMAGE = 4,
    RA_MODALITY_MULTIMODAL = 5
} ra_modality_type;

// Audio format types
typedef enum {
    RA_AUDIO_FORMAT_PCM = 0,
    RA_AUDIO_FORMAT_WAV = 1,
    RA_AUDIO_FORMAT_MP3 = 2,
    RA_AUDIO_FORMAT_FLAC = 3,
    RA_AUDIO_FORMAT_AAC = 4,
    RA_AUDIO_FORMAT_OPUS = 5
} ra_audio_format;

// Audio configuration
typedef struct {
    int sample_rate;
    int channels;
    int bits_per_sample;
    ra_audio_format format;
} ra_audio_config;

// Core ONNX Runtime functions
ra_onnx_handle ra_onnx_create(void);
int ra_onnx_initialize(ra_onnx_handle handle, const char* config_json);
int ra_onnx_load_model(ra_onnx_handle handle, const char* model_path);
int ra_onnx_is_model_loaded(ra_onnx_handle handle);
void ra_onnx_destroy(ra_onnx_handle handle);
void ra_free_string(char* str);

// Modality functions
int ra_onnx_set_modality(ra_onnx_handle handle, ra_modality_type modality);
ra_modality_type ra_onnx_get_modality(ra_onnx_handle handle);

// ASR/STT (Speech-to-Text) functions
int ra_onnx_transcribe(
    ra_onnx_handle handle,
    const uint8_t* audio_data,
    size_t audio_size,
    const ra_audio_config* audio_config,
    const char* language,
    char** result_json
);

// TTS (Text-to-Speech) functions
int ra_onnx_synthesize(
    ra_onnx_handle handle,
    const char* text,
    const char* voice_id,
    const ra_audio_config* audio_config,
    float rate,
    float pitch,
    uint8_t** audio_data,
    size_t* audio_size,
    double* duration_ms
);

void ra_free_audio_data(uint8_t* audio_data);

// LLM (Text generation) functions
int ra_onnx_generate_text(
    ra_onnx_handle handle,
    const char* messages_json,
    const char* system_prompt,
    int max_tokens,
    float temperature,
    char** result_json
);

// Streaming callbacks
typedef void (*ra_text_stream_callback)(const char* token, void* user_data);

int ra_onnx_generate_text_stream(
    ra_onnx_handle handle,
    const char* messages_json,
    const char* system_prompt,
    int max_tokens,
    float temperature,
    ra_text_stream_callback callback,
    void* user_data
);

//------------------------------------------------------------------------------
// Sherpa-ONNX Streaming STT Functions
//------------------------------------------------------------------------------

// Opaque handle for sherpa-onnx recognizer
typedef void* ra_sherpa_recognizer_handle;
typedef void* ra_sherpa_stream_handle;

/**
 * @brief Create a sherpa-onnx online recognizer for streaming STT
 * @param model_dir Path to directory containing sherpa-onnx model files
 * @param config_json Optional JSON configuration (can be NULL)
 * @return Handle to recognizer, or NULL on failure
 */
ra_sherpa_recognizer_handle ra_sherpa_create_recognizer(
    const char* model_dir,
    const char* config_json
);

/**
 * @brief Create a stream for the recognizer
 * @param recognizer The recognizer handle
 * @return Handle to stream, or NULL on failure
 */
ra_sherpa_stream_handle ra_sherpa_create_stream(
    ra_sherpa_recognizer_handle recognizer
);

/**
 * @brief Feed audio samples to the stream
 * @param stream The stream handle
 * @param sample_rate Sample rate in Hz (e.g., 16000)
 * @param samples Float32 audio samples normalized to [-1, 1]
 * @param num_samples Number of samples
 */
void ra_sherpa_accept_waveform(
    ra_sherpa_stream_handle stream,
    int sample_rate,
    const float* samples,
    int num_samples
);

/**
 * @brief Check if stream is ready for decoding
 * @param recognizer The recognizer handle
 * @param stream The stream handle
 * @return 1 if ready, 0 otherwise
 */
int ra_sherpa_is_ready(
    ra_sherpa_recognizer_handle recognizer,
    ra_sherpa_stream_handle stream
);

/**
 * @brief Decode the stream (run neural network)
 * @param recognizer The recognizer handle
 * @param stream The stream handle
 */
void ra_sherpa_decode(
    ra_sherpa_recognizer_handle recognizer,
    ra_sherpa_stream_handle stream
);

/**
 * @brief Get the current transcription result
 * @param recognizer The recognizer handle
 * @param stream The stream handle
 * @return Transcription text (do not free - internal pointer)
 */
const char* ra_sherpa_get_result(
    ra_sherpa_recognizer_handle recognizer,
    ra_sherpa_stream_handle stream
);

/**
 * @brief Signal that no more audio will be provided
 * @param stream The stream handle
 */
void ra_sherpa_input_finished(ra_sherpa_stream_handle stream);

/**
 * @brief Check if endpoint is detected (end of speech)
 * @param recognizer The recognizer handle
 * @param stream The stream handle
 * @return 1 if endpoint detected, 0 otherwise
 */
int ra_sherpa_is_endpoint(
    ra_sherpa_recognizer_handle recognizer,
    ra_sherpa_stream_handle stream
);

/**
 * @brief Reset the stream state
 * @param recognizer The recognizer handle
 * @param stream The stream handle
 */
void ra_sherpa_reset(
    ra_sherpa_recognizer_handle recognizer,
    ra_sherpa_stream_handle stream
);

/**
 * @brief Destroy a stream
 * @param stream The stream handle
 */
void ra_sherpa_destroy_stream(ra_sherpa_stream_handle stream);

/**
 * @brief Destroy a recognizer
 * @param recognizer The recognizer handle
 */
void ra_sherpa_destroy_recognizer(ra_sherpa_recognizer_handle recognizer);

//------------------------------------------------------------------------------
// Archive Extraction Utilities
//------------------------------------------------------------------------------

/**
 * @brief Extract a tar.bz2 archive
 * @param archive_path Path to the .tar.bz2 file
 * @param dest_dir Destination directory for extraction
 * @return RA_SUCCESS on success, error code otherwise
 */
int ra_extract_tar_bz2(const char* archive_path, const char* dest_dir);

#ifdef __cplusplus
}
#endif

#endif // ONNX_BRIDGE_WRAPPER_H
