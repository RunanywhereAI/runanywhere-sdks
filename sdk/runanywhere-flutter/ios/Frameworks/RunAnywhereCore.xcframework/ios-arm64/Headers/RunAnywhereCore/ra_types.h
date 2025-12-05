#ifndef RA_CORE_TYPES_H
#define RA_CORE_TYPES_H

/**
 * RunAnywhere Core Types
 *
 * Common type definitions used across all capabilities and backends.
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// RESULT CODES
// =============================================================================

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

// =============================================================================
// DEVICE TYPES
// =============================================================================

typedef enum {
    RA_DEVICE_CPU = 0,
    RA_DEVICE_GPU = 1,
    RA_DEVICE_NEURAL_ENGINE = 2,  // Apple Neural Engine
    RA_DEVICE_METAL = 3,          // Apple Metal
    RA_DEVICE_CUDA = 4,           // NVIDIA CUDA
    RA_DEVICE_NNAPI = 5,          // Android NNAPI
    RA_DEVICE_COREML = 6,         // Apple CoreML
    RA_DEVICE_VULKAN = 7,         // Vulkan compute
    RA_DEVICE_UNKNOWN = 99
} ra_device_type;

// =============================================================================
// AUDIO TYPES
// =============================================================================

typedef enum {
    RA_AUDIO_FORMAT_PCM_F32 = 0,   // Float32 [-1.0, 1.0]
    RA_AUDIO_FORMAT_PCM_S16 = 1,   // Signed 16-bit
    RA_AUDIO_FORMAT_PCM_S32 = 2,   // Signed 32-bit
    RA_AUDIO_FORMAT_WAV = 10,      // WAV container
    RA_AUDIO_FORMAT_MP3 = 11,      // MP3 compressed
    RA_AUDIO_FORMAT_FLAC = 12,     // FLAC lossless
    RA_AUDIO_FORMAT_AAC = 13,      // AAC compressed
    RA_AUDIO_FORMAT_OPUS = 14      // Opus compressed
} ra_audio_format;

typedef struct {
    int sample_rate;           // Sample rate in Hz (default: 16000)
    int channels;              // Number of channels (default: 1 - mono)
    int bits_per_sample;       // Bits per sample (default: 16)
    ra_audio_format format;    // Audio format
} ra_audio_config;

// Default audio config for STT (16kHz mono)
#define RA_AUDIO_CONFIG_STT_DEFAULT { 16000, 1, 16, RA_AUDIO_FORMAT_PCM_F32 }

// Default audio config for TTS (22050Hz mono)
#define RA_AUDIO_CONFIG_TTS_DEFAULT { 22050, 1, 16, RA_AUDIO_FORMAT_PCM_F32 }

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

// Opaque handle to a backend instance
typedef void* ra_backend_handle;

// Opaque handle to a streaming session (STT, VAD, etc.)
typedef void* ra_stream_handle;

// =============================================================================
// CALLBACKS
// =============================================================================

#include <stdbool.h>

// Text generation streaming callback
// Returns: true to continue, false to cancel
typedef bool (*ra_text_stream_callback)(const char* token, void* user_data);

// STT streaming callback
// is_final: true when result is final, false for partial
// Returns: true to continue, false to cancel
typedef bool (*ra_stt_stream_callback)(const char* text, bool is_final, void* user_data);

// TTS streaming callback
// samples: float32 audio samples
// num_samples: number of samples in this chunk
// is_final: true when synthesis is complete
// Returns: true to continue, false to cancel
typedef bool (*ra_tts_stream_callback)(const float* samples, size_t num_samples, bool is_final, void* user_data);

// VAD streaming callback
typedef void (*ra_vad_stream_callback)(bool is_speech, float probability, double timestamp_ms, void* user_data);

#ifdef __cplusplus
}
#endif

#endif // RA_CORE_TYPES_H
