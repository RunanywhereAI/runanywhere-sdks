#ifndef RUNANYWHERE_TYPES_H
#define RUNANYWHERE_TYPES_H

/**
 * RunAnywhere Core Types
 *
 * Common type definitions used across all capabilities and backends.
 * This header is included by onnx_bridge_wrapper.h for completeness.
 */

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Result codes (also defined in onnx_bridge_wrapper.h)
#ifndef RA_RESULT_CODE_DEFINED
#define RA_RESULT_CODE_DEFINED
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
#endif

// Device types
#ifndef RA_DEVICE_TYPE_DEFINED
#define RA_DEVICE_TYPE_DEFINED
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
#endif

// Audio format types
#ifndef RA_AUDIO_FORMAT_DEFINED
#define RA_AUDIO_FORMAT_DEFINED
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
#endif

// Audio configuration
#ifndef RA_AUDIO_CONFIG_DEFINED
#define RA_AUDIO_CONFIG_DEFINED
typedef struct {
    int sample_rate;
    int channels;
    int bits_per_sample;
    ra_audio_format format;
} ra_audio_config;
#endif

// Default audio config for STT (16kHz mono)
#define RA_AUDIO_CONFIG_STT_DEFAULT { 16000, 1, 16, RA_AUDIO_FORMAT_PCM_F32 }

// Default audio config for TTS (22050Hz mono)
#define RA_AUDIO_CONFIG_TTS_DEFAULT { 22050, 1, 16, RA_AUDIO_FORMAT_PCM_F32 }

#ifdef __cplusplus
}
#endif

#endif // RUNANYWHERE_TYPES_H
