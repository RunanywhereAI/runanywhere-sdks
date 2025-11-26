#ifndef RUNANYWHERE_MODALITY_TYPES_H
#define RUNANYWHERE_MODALITY_TYPES_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Modality types
typedef enum {
    RA_MODALITY_TEXT_TO_TEXT = 0,      // LLM text generation
    RA_MODALITY_VOICE_TO_TEXT = 1,     // ASR/Speech-to-text
    RA_MODALITY_TEXT_TO_VOICE = 2,     // TTS/Text-to-speech
    RA_MODALITY_IMAGE_TO_TEXT = 3,     // Image captioning/OCR
    RA_MODALITY_TEXT_TO_IMAGE = 4,     // Image generation
    RA_MODALITY_MULTIMODAL = 5         // Multiple modalities
} ra_modality_type;

// Audio format types
typedef enum {
    RA_AUDIO_FORMAT_PCM = 0,           // Raw PCM 16-bit
    RA_AUDIO_FORMAT_WAV = 1,           // WAV container
    RA_AUDIO_FORMAT_MP3 = 2,           // MP3 compressed
    RA_AUDIO_FORMAT_FLAC = 3,          // FLAC lossless
    RA_AUDIO_FORMAT_AAC = 4,           // AAC compressed
    RA_AUDIO_FORMAT_OPUS = 5           // Opus compressed
} ra_audio_format;

// Audio configuration
typedef struct {
    int sample_rate;                   // Sample rate in Hz (default: 16000)
    int channels;                      // Number of channels (default: 1 - mono)
    int bits_per_sample;               // Bits per sample (default: 16)
    ra_audio_format format;            // Audio format
} ra_audio_config;

#ifdef __cplusplus
}
#endif

#endif // RUNANYWHERE_MODALITY_TYPES_H
