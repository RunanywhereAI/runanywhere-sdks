/**
 * @file rac_tts_types.h
 * @brief RunAnywhere Commons - TTS Types and Data Structures
 *
 * C port of Swift's TTS Models from:
 * Sources/RunAnywhere/Features/TTS/Models/TTSConfiguration.swift
 * Sources/RunAnywhere/Features/TTS/Models/TTSOptions.swift
 * Sources/RunAnywhere/Features/TTS/Models/TTSInput.swift
 * Sources/RunAnywhere/Features/TTS/Models/TTSOutput.swift
 *
 * This header defines data structures only. For the service interface,
 * see rac_tts_service.h.
 */

#ifndef RAC_TTS_TYPES_H
#define RAC_TTS_TYPES_H

#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_types.h"  // For rac_audio_format_enum_t

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CONSTANTS - Single Source of Truth for TTS
// Swift references these via CRACommons import
// =============================================================================

// Audio Format Constants
#define RAC_TTS_DEFAULT_SAMPLE_RATE 22050
#define RAC_TTS_HIGH_QUALITY_SAMPLE_RATE 24000
#define RAC_TTS_CD_QUALITY_SAMPLE_RATE 44100
#define RAC_TTS_MAX_SAMPLE_RATE 48000
#define RAC_TTS_BYTES_PER_SAMPLE 2
#define RAC_TTS_CHANNELS 1

// Speaking Rate Constants
#define RAC_TTS_DEFAULT_SPEAKING_RATE 1.0f
#define RAC_TTS_MIN_SPEAKING_RATE 0.5f
#define RAC_TTS_MAX_SPEAKING_RATE 2.0f

// Streaming Constants
#define RAC_TTS_DEFAULT_STREAMING_CHUNK_BYTES 4096

// =============================================================================
// CONFIGURATION - Mirrors Swift's TTSConfiguration
// =============================================================================

/**
 * @brief TTS component configuration
 *
 * Mirrors Swift's TTSConfiguration struct exactly.
 * See: Sources/RunAnywhere/Features/TTS/Models/TTSConfiguration.swift
 */
typedef struct rac_tts_config {
    /** Model ID (voice identifier for TTS, optional) */
    const char* model_id;

    /** Preferred framework (use -1 for auto) */
    int32_t preferred_framework;

    /** Voice identifier to use for synthesis */
    const char* voice;

    /** Language for synthesis (BCP-47 format, e.g., "en-US") */
    const char* language;

    /** Speaking rate (0.5 to 2.0, 1.0 is normal) */
    float speaking_rate;

    /** Speech pitch (0.5 to 2.0, 1.0 is normal) */
    float pitch;

    /** Speech volume (0.0 to 1.0) */
    float volume;

    /** Audio format for output */
    rac_audio_format_enum_t audio_format;

    /** Whether to use neural/premium voice if available */
    rac_bool_t use_neural_voice;

    /** Whether to enable SSML markup support */
    rac_bool_t enable_ssml;
} rac_tts_config_t;

/**
 * @brief Default TTS configuration
 */
static const rac_tts_config_t RAC_TTS_CONFIG_DEFAULT = {
    RAC_NULL,                        /* model_id */
    -1,                             /* preferred_framework */
    RAC_NULL,                       /* voice */
    "en-US",                        /* language */
    1.0f,                           /* speaking_rate */
    1.0f,                           /* pitch */
    1.0f,                           /* volume */
    RAC_AUDIO_FORMAT_PCM,           /* audio_format */
    RAC_TRUE,                       /* use_neural_voice */
    RAC_FALSE                        /* enable_ssml */
};

// =============================================================================
// OPTIONS - Mirrors Swift's TTSOptions
// =============================================================================

/**
 * @brief TTS synthesis options
 *
 * Mirrors Swift's TTSOptions struct exactly.
 * See: Sources/RunAnywhere/Features/TTS/Models/TTSOptions.swift
 */
typedef struct rac_tts_options {
    /** Voice to use for synthesis (can be NULL for default) */
    const char* voice;

    /** Language for synthesis (BCP-47 format, e.g., "en-US") */
    const char* language;

    /** Speech rate (0.0 to 2.0, 1.0 is normal) */
    float rate;

    /** Speech pitch (0.0 to 2.0, 1.0 is normal) */
    float pitch;

    /** Speech volume (0.0 to 1.0) */
    float volume;

    /** Audio format for output */
    rac_audio_format_enum_t audio_format;

    /** Sample rate for output audio in Hz */
    int32_t sample_rate;

    /** Whether to use SSML markup */
    rac_bool_t use_ssml;
} rac_tts_options_t;

/**
 * @brief Default TTS options
 */
static const rac_tts_options_t RAC_TTS_OPTIONS_DEFAULT = {RAC_NULL,
                                                          "en-US",                        /* language */
                                                          1.0f,                           /* rate */
                                                          1.0f,                           /* pitch */
                                                          1.0f,                           /* volume */
                                                          RAC_AUDIO_FORMAT_PCM,           /* audio_format */
                                                          RAC_TTS_DEFAULT_SAMPLE_RATE,    /* sample_rate */
                                                          RAC_FALSE                        /* use_ssml */
};

// =============================================================================
// INPUT - Mirrors Swift's TTSInput
// =============================================================================

/**
 * @brief TTS input data
 *
 * Mirrors Swift's TTSInput struct exactly.
 * See: Sources/RunAnywhere/Features/TTS/Models/TTSInput.swift
 */
typedef struct rac_tts_input {
    /** Text to synthesize */
    const char* text;

    /** Optional SSML markup (overrides text if provided, can be NULL) */
    const char* ssml;

    /** Voice ID override (can be NULL) */
    const char* voice_id;

    /** Language override (can be NULL) */
    const char* language;

    /** Custom options override (can be NULL) */
    const rac_tts_options_t* options;
} rac_tts_input_t;

/**
 * @brief Default TTS input
 */
static const rac_tts_input_t RAC_TTS_INPUT_DEFAULT = {
    RAC_NULL,                       /* text */
    RAC_NULL,                       /* ssml */
    RAC_NULL,                       /* voice_id */
    RAC_NULL,                       /* language */
    RAC_NULL                        /* options */
};

// =============================================================================
// RESULT - Mirrors Swift's TTS result
// =============================================================================

/**
 * @brief TTS synthesis result
 */
typedef struct rac_tts_result {
    /** Audio data (owned, must be freed with rac_free) */
    void* audio_data;

    /** Size of audio data in bytes */
    size_t audio_size;

    /** Audio format */
    rac_audio_format_enum_t audio_format;

    /** Sample rate */
    int32_t sample_rate;

    /** Duration in milliseconds */
    int64_t duration_ms;

    /** Processing time in milliseconds */
    int64_t processing_time_ms;
} rac_tts_result_t;

// =============================================================================
// INFO - Mirrors Swift's TTSService properties
// =============================================================================

/**
 * @brief TTS service info
 */
typedef struct rac_tts_info {
    /** Whether the service is ready */
    rac_bool_t is_ready;

    /** Whether currently synthesizing */
    rac_bool_t is_synthesizing;

    /** Available voices (null-terminated array) */
    const char* const* available_voices;
    size_t num_voices;
} rac_tts_info_t;

// =============================================================================
// CALLBACKS
// =============================================================================

/**
 * @brief TTS streaming callback
 *
 * Called for each audio chunk during streaming synthesis.
 *
 * @param audio_data Audio chunk data
 * @param audio_size Size of audio chunk
 * @param user_data User-provided context
 */
typedef void (*rac_tts_stream_callback_t)(const void* audio_data, size_t audio_size,
                                          void* user_data);

// =============================================================================
// PHONEME TIMESTAMP - Mirrors Swift's TTSPhonemeTimestamp
// =============================================================================

/**
 * @brief Phoneme timestamp information
 *
 * Mirrors Swift's TTSPhonemeTimestamp struct.
 * See: Sources/RunAnywhere/Features/TTS/Models/TTSOutput.swift
 */
typedef struct rac_tts_phoneme_timestamp {
    /** The phoneme */
    const char* phoneme;

    /** Start time in milliseconds */
    int64_t start_time_ms;

    /** End time in milliseconds */
    int64_t end_time_ms;
} rac_tts_phoneme_timestamp_t;

// =============================================================================
// SYNTHESIS METADATA - Mirrors Swift's TTSSynthesisMetadata
// =============================================================================

/**
 * @brief Synthesis metadata
 *
 * Mirrors Swift's TTSSynthesisMetadata struct.
 * See: Sources/RunAnywhere/Features/TTS/Models/TTSOutput.swift
 */
typedef struct rac_tts_synthesis_metadata {
    /** Voice used for synthesis */
    const char* voice;

    /** Language used for synthesis */
    const char* language;

    /** Processing time in milliseconds */
    int64_t processing_time_ms;

    /** Number of characters synthesized */
    int32_t character_count;

    /** Characters processed per second */
    float characters_per_second;
} rac_tts_synthesis_metadata_t;

// =============================================================================
// OUTPUT - Mirrors Swift's TTSOutput
// =============================================================================

/**
 * @brief TTS output data
 *
 * Mirrors Swift's TTSOutput struct exactly.
 * See: Sources/RunAnywhere/Features/TTS/Models/TTSOutput.swift
 */
typedef struct rac_tts_output {
    /** Synthesized audio data (owned, must be freed with rac_free) */
    void* audio_data;

    /** Size of audio data in bytes */
    size_t audio_size;

    /** Audio format of the output */
    rac_audio_format_enum_t format;

    /** Duration of the audio in milliseconds */
    int64_t duration_ms;

    /** Phoneme timestamps if available (can be NULL) */
    rac_tts_phoneme_timestamp_t* phoneme_timestamps;
    size_t num_phoneme_timestamps;

    /** Processing metadata */
    rac_tts_synthesis_metadata_t metadata;

    /** Timestamp in milliseconds since epoch */
    int64_t timestamp_ms;
} rac_tts_output_t;

// =============================================================================
// SPEAK RESULT - Mirrors Swift's TTSSpeakResult
// =============================================================================

/**
 * @brief Speak result (metadata only, no audio data)
 *
 * Mirrors Swift's TTSSpeakResult struct.
 * The SDK handles audio playback internally when using speak().
 * See: Sources/RunAnywhere/Features/TTS/Models/TTSOutput.swift
 */
typedef struct rac_tts_speak_result {
    /** Duration of the spoken audio in milliseconds */
    int64_t duration_ms;

    /** Audio format used */
    rac_audio_format_enum_t format;

    /** Audio size in bytes (0 for system TTS which plays directly) */
    size_t audio_size_bytes;

    /** Synthesis metadata */
    rac_tts_synthesis_metadata_t metadata;

    /** Timestamp when speech completed (milliseconds since epoch) */
    int64_t timestamp_ms;
} rac_tts_speak_result_t;

// =============================================================================
// MEMORY MANAGEMENT
// =============================================================================

/**
 * @brief Free TTS result resources
 *
 * @param result Result to free (can be NULL)
 */
RAC_API void rac_tts_result_free(rac_tts_result_t* result);

#ifdef __cplusplus
}
#endif

#endif /* RAC_TTS_TYPES_H */
