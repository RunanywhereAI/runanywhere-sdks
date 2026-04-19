/**
 * @file rac_stt_types.h
 * @brief RunAnywhere Commons - STT Types and Data Structures
 *
 * C port of Swift's STT Models from:
 * Sources/RunAnywhere/Features/STT/Models/STTConfiguration.swift
 * Sources/RunAnywhere/Features/STT/Models/STTOptions.swift
 * Sources/RunAnywhere/Features/STT/Models/STTInput.swift
 * Sources/RunAnywhere/Features/STT/Models/STTOutput.swift
 * Sources/RunAnywhere/Features/STT/Models/STTTranscriptionResult.swift
 *
 * This header defines data structures only. For the service interface,
 * see rac_stt_service.h.
 */

#ifndef RAC_STT_TYPES_H
#define RAC_STT_TYPES_H

#include "rac_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CONSTANTS - Mirrors Swift's STTConstants
// =============================================================================

/** Default sample rate for STT (16kHz) */
#define RAC_STT_DEFAULT_SAMPLE_RATE 16000

// =============================================================================
// AUDIO FORMAT - Mirrors Swift's AudioFormat
// =============================================================================

/**
 * @brief Audio format enumeration
 */
typedef enum rac_audio_format_enum {
    RAC_AUDIO_FORMAT_PCM = 0,
    RAC_AUDIO_FORMAT_WAV = 1,
    RAC_AUDIO_FORMAT_MP3 = 2,
    RAC_AUDIO_FORMAT_OPUS = 3,
    RAC_AUDIO_FORMAT_FLAC = 4
} rac_audio_format_enum_t;

// =============================================================================
// CONFIGURATION - Mirrors Swift's STTConfiguration
// =============================================================================

/**
 * @brief STT component configuration
 *
 * Mirrors Swift's STTConfiguration struct exactly.
 * See: Sources/RunAnywhere/Features/STT/Models/STTConfiguration.swift
 */
typedef struct rac_stt_config {
    /** Model ID (optional - uses default if NULL) */
    const char* model_id;

    /** Preferred framework for transcription (use -1 for auto) */
    int32_t preferred_framework;

    /** Language code for transcription (e.g., "en-US") */
    const char* language;

    /** Sample rate in Hz (default: 16000) */
    int32_t sample_rate;

    /** Enable automatic punctuation in transcription */
    rac_bool_t enable_punctuation;

    /** Enable speaker diarization */
    rac_bool_t enable_diarization;

    /** Vocabulary list for improved recognition (NULL-terminated array, can be NULL) */
    const char* const* vocabulary_list;
    size_t num_vocabulary;

    /** Maximum number of alternative transcriptions (default: 1) */
    int32_t max_alternatives;

    /** Enable word-level timestamps */
    rac_bool_t enable_timestamps;
} rac_stt_config_t;

/**
 * @brief Default STT configuration
 */
static const rac_stt_config_t RAC_STT_CONFIG_DEFAULT = {.model_id = RAC_NULL,
                                                        .preferred_framework = -1,
                                                        .language = "en-US",
                                                        .sample_rate = RAC_STT_DEFAULT_SAMPLE_RATE,
                                                        .enable_punctuation = RAC_TRUE,
                                                        .enable_diarization = RAC_FALSE,
                                                        .vocabulary_list = RAC_NULL,
                                                        .num_vocabulary = 0,
                                                        .max_alternatives = 1,
                                                        .enable_timestamps = RAC_TRUE};

// =============================================================================
// OPTIONS - Mirrors Swift's STTOptions
// =============================================================================

/**
 * @brief STT transcription options
 *
 * Mirrors Swift's STTOptions struct.
 * See: Sources/RunAnywhere/Features/STT/Models/STTOptions.swift
 */
typedef struct rac_stt_options {
    /** Language code for transcription (e.g., "en", "es", "fr") */
    const char* language;

    /** Whether to auto-detect the spoken language */
    rac_bool_t detect_language;

    /** Enable automatic punctuation in transcription */
    rac_bool_t enable_punctuation;

    /** Enable speaker diarization */
    rac_bool_t enable_diarization;

    /** Maximum number of speakers (0 = auto) */
    int32_t max_speakers;

    /** Enable word-level timestamps */
    rac_bool_t enable_timestamps;

    /** Audio format of input data */
    rac_audio_format_enum_t audio_format;

    /** Sample rate of input audio (default: 16000 Hz) */
    int32_t sample_rate;
} rac_stt_options_t;

/**
 * @brief Default STT options
 */
static const rac_stt_options_t RAC_STT_OPTIONS_DEFAULT = {.language = "en",
                                                          .detect_language = RAC_FALSE,
                                                          .enable_punctuation = RAC_TRUE,
                                                          .enable_diarization = RAC_FALSE,
                                                          .max_speakers = 0,
                                                          .enable_timestamps = RAC_TRUE,
                                                          .audio_format = RAC_AUDIO_FORMAT_PCM,
                                                          .sample_rate = 16000};

// =============================================================================
// RESULT - Mirrors Swift's STTTranscriptionResult
// =============================================================================

/**
 * @brief Word timestamp information
 */
typedef struct rac_stt_word {
    /** The word text */
    const char* text;
    /** Start time in milliseconds */
    int64_t start_ms;
    /** End time in milliseconds */
    int64_t end_ms;
    /** Confidence score (0.0 to 1.0) */
    float confidence;
} rac_stt_word_t;

/**
 * @brief STT transcription result
 *
 * Mirrors Swift's STTTranscriptionResult struct.
 */
typedef struct rac_stt_result {
    /** Full transcribed text (owned, must be freed with rac_free) */
    char* text;

    /** Detected language code (can be NULL) */
    char* detected_language;

    /** Word-level timestamps (can be NULL) */
    rac_stt_word_t* words;
    size_t num_words;

    /** Overall confidence score (0.0 to 1.0) */
    float confidence;

    /** Processing time in milliseconds */
    int64_t processing_time_ms;
} rac_stt_result_t;

// =============================================================================
// INFO - Mirrors Swift's STTService properties
// =============================================================================

/**
 * @brief STT service info
 */
typedef struct rac_stt_info {
    /** Whether the service is ready */
    rac_bool_t is_ready;

    /** Current model identifier (can be NULL) */
    const char* current_model;

    /** Whether streaming is supported */
    rac_bool_t supports_streaming;
} rac_stt_info_t;

// =============================================================================
// CALLBACKS
// =============================================================================

/**
 * @brief STT streaming callback
 *
 * Called for partial transcription results during streaming.
 *
 * @param partial_text Partial transcription text
 * @param is_final Whether this is a final result
 * @param user_data User-provided context
 */
typedef void (*rac_stt_stream_callback_t)(const char* partial_text, rac_bool_t is_final,
                                          void* user_data);

// =============================================================================
// INPUT - Mirrors Swift's STTInput
// =============================================================================

/**
 * @brief STT input data
 *
 * Mirrors Swift's STTInput struct.
 * See: Sources/RunAnywhere/Features/STT/Models/STTInput.swift
 */
typedef struct rac_stt_input {
    /** Audio data bytes (raw audio data) */
    const uint8_t* audio_data;
    size_t audio_data_size;

    /** Alternative: audio buffer (PCM float samples) */
    const float* audio_samples;
    size_t num_samples;

    /** Audio format of input data */
    rac_audio_format_enum_t format;

    /** Language code override (can be NULL to use config default) */
    const char* language;

    /** Sample rate of the audio (default: 16000) */
    int32_t sample_rate;

    /** Custom options override (can be NULL) */
    const rac_stt_options_t* options;
} rac_stt_input_t;

/**
 * @brief Default STT input
 */
static const rac_stt_input_t RAC_STT_INPUT_DEFAULT = {.audio_data = RAC_NULL,
                                                      .audio_data_size = 0,
                                                      .audio_samples = RAC_NULL,
                                                      .num_samples = 0,
                                                      .format = RAC_AUDIO_FORMAT_PCM,
                                                      .language = RAC_NULL,
                                                      .sample_rate = RAC_STT_DEFAULT_SAMPLE_RATE,
                                                      .options = RAC_NULL};

// =============================================================================
// TRANSCRIPTION METADATA - Mirrors Swift's TranscriptionMetadata
// =============================================================================

/**
 * @brief Transcription metadata
 *
 * Mirrors Swift's TranscriptionMetadata struct.
 * See: Sources/RunAnywhere/Features/STT/Models/STTOutput.swift
 */
typedef struct rac_transcription_metadata {
    /** Model ID used for transcription */
    const char* model_id;

    /** Processing time in milliseconds */
    int64_t processing_time_ms;

    /** Audio length in milliseconds */
    int64_t audio_length_ms;

    /** Real-time factor (processing_time / audio_length) */
    float real_time_factor;
} rac_transcription_metadata_t;

// =============================================================================
// TRANSCRIPTION ALTERNATIVE - Mirrors Swift's TranscriptionAlternative
// =============================================================================

/**
 * @brief Alternative transcription
 *
 * Mirrors Swift's TranscriptionAlternative struct.
 */
typedef struct rac_transcription_alternative {
    /** Alternative transcription text */
    const char* text;

    /** Confidence score (0.0 to 1.0) */
    float confidence;
} rac_transcription_alternative_t;

// =============================================================================
// OUTPUT - Mirrors Swift's STTOutput
// =============================================================================

/**
 * @brief STT output data
 *
 * Mirrors Swift's STTOutput struct.
 * See: Sources/RunAnywhere/Features/STT/Models/STTOutput.swift
 */
typedef struct rac_stt_output {
    /** Transcribed text (owned, must be freed with rac_free) */
    char* text;

    /** Confidence score (0.0 to 1.0) */
    float confidence;

    /** Word-level timestamps (can be NULL) */
    rac_stt_word_t* word_timestamps;
    size_t num_word_timestamps;

    /** Detected language if auto-detected (can be NULL) */
    char* detected_language;

    /** Alternative transcriptions (can be NULL) */
    rac_transcription_alternative_t* alternatives;
    size_t num_alternatives;

    /** Processing metadata */
    rac_transcription_metadata_t metadata;

    /** Timestamp in milliseconds since epoch */
    int64_t timestamp_ms;
} rac_stt_output_t;

// =============================================================================
// TRANSCRIPTION RESULT - Alias for compatibility
// =============================================================================

/**
 * @brief STT transcription result (alias for rac_stt_output_t)
 *
 * For compatibility with existing code that uses "result" terminology.
 */
typedef rac_stt_output_t rac_stt_transcription_result_t;

#ifdef __cplusplus
}
#endif

#endif /* RAC_STT_TYPES_H */
