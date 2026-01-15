/**
 * @file rac_vad_types.h
 * @brief RunAnywhere Commons - VAD Types and Data Structures
 *
 * C port of Swift's VAD Models from:
 * Sources/RunAnywhere/Features/VAD/Models/VADConfiguration.swift
 * Sources/RunAnywhere/Features/VAD/Models/VADInput.swift
 * Sources/RunAnywhere/Features/VAD/Models/VADOutput.swift
 * Sources/RunAnywhere/Features/VAD/VADConstants.swift
 *
 * This header defines data structures only. For the service interface,
 * see rac_vad_service.h.
 */

#ifndef RAC_VAD_TYPES_H
#define RAC_VAD_TYPES_H

#include <RACommons/rac_types.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CONSTANTS - Single Source of Truth for VAD
// Swift references these via CRACommons import
// =============================================================================

// Audio Format Constants
#define RAC_VAD_DEFAULT_SAMPLE_RATE 16000
#define RAC_VAD_MAX_SAMPLE_RATE 48000
#define RAC_VAD_MIN_SAMPLE_RATE 8000

// Energy Thresholds
#define RAC_VAD_DEFAULT_ENERGY_THRESHOLD 0.015f
#define RAC_VAD_MIN_ENERGY_THRESHOLD 0.001f
#define RAC_VAD_MAX_ENERGY_THRESHOLD 0.5f

// Frame Processing
#define RAC_VAD_DEFAULT_FRAME_LENGTH 0.1f
#define RAC_VAD_MIN_FRAME_LENGTH 0.02f
#define RAC_VAD_MAX_FRAME_LENGTH 0.5f

// Calibration
#define RAC_VAD_DEFAULT_CALIBRATION_MULTIPLIER 2.0f
#define RAC_VAD_MIN_CALIBRATION_MULTIPLIER 1.2f
#define RAC_VAD_MAX_CALIBRATION_MULTIPLIER 5.0f

// Speech Detection
#define RAC_VAD_MIN_SPEECH_DURATION_MS 100
#define RAC_VAD_MIN_SILENCE_DURATION_MS 300

// =============================================================================
// CONFIGURATION - Mirrors Swift's VADConfiguration
// =============================================================================

/**
 * @brief VAD component configuration
 *
 * Mirrors Swift's VADConfiguration struct exactly.
 * See: Sources/RunAnywhere/Features/VAD/Models/VADConfiguration.swift
 */
typedef struct rac_vad_config {
    /** Model ID (not used for VAD, can be NULL) */
    const char* model_id;

    /** Preferred framework (use -1 for auto) */
    int32_t preferred_framework;

    /** Energy threshold for voice detection (0.0 to 1.0) */
    float energy_threshold;

    /** Sample rate in Hz (default: 16000) */
    int32_t sample_rate;

    /** Frame length in seconds (default: 0.1 = 100ms) */
    float frame_length;

    /** Enable automatic calibration */
    rac_bool_t enable_auto_calibration;

    /** Calibration multiplier (threshold = ambient noise * multiplier) */
    float calibration_multiplier;
} rac_vad_config_t;

/**
 * @brief Default VAD configuration
 */
static const rac_vad_config_t RAC_VAD_CONFIG_DEFAULT = {
    .model_id = RAC_NULL,
    .preferred_framework = -1,
    .energy_threshold = RAC_VAD_DEFAULT_ENERGY_THRESHOLD,
    .sample_rate = RAC_VAD_DEFAULT_SAMPLE_RATE,
    .frame_length = RAC_VAD_DEFAULT_FRAME_LENGTH,
    .enable_auto_calibration = RAC_FALSE,
    .calibration_multiplier = RAC_VAD_DEFAULT_CALIBRATION_MULTIPLIER};

// =============================================================================
// SPEECH ACTIVITY - Mirrors Swift's SpeechActivityEvent
// =============================================================================

/**
 * @brief Speech activity event type
 *
 * Mirrors Swift's SpeechActivityEvent.
 */
typedef enum rac_speech_activity {
    RAC_SPEECH_STARTED = 0,
    RAC_SPEECH_ENDED = 1,
    RAC_SPEECH_ONGOING = 2
} rac_speech_activity_t;

// =============================================================================
// INPUT - Mirrors Swift's VADInput
// =============================================================================

/**
 * @brief VAD input data
 *
 * Mirrors Swift's VADInput struct exactly.
 * See: Sources/RunAnywhere/Features/VAD/Models/VADInput.swift
 */
typedef struct rac_vad_input {
    /** Audio samples as float array (PCM float samples in range [-1.0, 1.0]) */
    const float* audio_samples;
    size_t num_samples;

    /** Optional override for energy threshold (use -1 for no override) */
    float energy_threshold_override;
} rac_vad_input_t;

/**
 * @brief Default VAD input
 */
static const rac_vad_input_t RAC_VAD_INPUT_DEFAULT = {
    .audio_samples = RAC_NULL,
    .num_samples = 0,
    .energy_threshold_override = -1.0f /* No override */
};

// =============================================================================
// OUTPUT - Mirrors Swift's VADOutput
// =============================================================================

/**
 * @brief VAD output data
 *
 * Mirrors Swift's VADOutput struct exactly.
 * See: Sources/RunAnywhere/Features/VAD/Models/VADOutput.swift
 */
typedef struct rac_vad_output {
    /** Whether speech is detected in the current frame */
    rac_bool_t is_speech_detected;

    /** Current audio energy level (RMS value) */
    float energy_level;

    /** Timestamp in milliseconds since epoch */
    int64_t timestamp_ms;
} rac_vad_output_t;

// =============================================================================
// INFO - Mirrors Swift's VADService properties
// =============================================================================

/**
 * @brief VAD service info
 *
 * Mirrors Swift's VADService properties.
 */
typedef struct rac_vad_info {
    /** Whether speech is currently active (isSpeechActive) */
    rac_bool_t is_speech_active;

    /** Energy threshold for voice detection (energyThreshold) */
    float energy_threshold;

    /** Sample rate of the audio in Hz (sampleRate) */
    int32_t sample_rate;

    /** Frame length in seconds (frameLength) */
    float frame_length;
} rac_vad_info_t;

// =============================================================================
// STATISTICS - Mirrors Swift's VADStatistics
// =============================================================================

/**
 * @brief VAD statistics
 *
 * Mirrors Swift's VADStatistics struct from SimpleEnergyVADService.
 */
typedef struct rac_vad_statistics {
    /** Current calibrated threshold */
    float current_threshold;

    /** Ambient noise level */
    float ambient_noise_level;

    /** Total speech segments detected */
    int32_t total_speech_segments;

    /** Total duration of speech in milliseconds */
    int64_t total_speech_duration_ms;

    /** Average energy level */
    float average_energy;

    /** Peak energy level */
    float peak_energy;
} rac_vad_statistics_t;

// =============================================================================
// CALLBACKS
// =============================================================================

/**
 * @brief Speech activity callback
 *
 * Mirrors Swift's VADService.onSpeechActivity callback.
 *
 * @param activity The speech activity event
 * @param user_data User-provided context
 */
typedef void (*rac_vad_activity_callback_fn)(rac_speech_activity_t activity, void* user_data);

/**
 * @brief Audio buffer callback
 *
 * Mirrors Swift's VADService.onAudioBuffer callback.
 *
 * @param audio_data Audio data buffer (PCM float samples)
 * @param num_samples Number of samples
 * @param user_data User-provided context
 */
typedef void (*rac_vad_audio_callback_fn)(const float* audio_data, size_t num_samples,
                                          void* user_data);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_TYPES_H */
