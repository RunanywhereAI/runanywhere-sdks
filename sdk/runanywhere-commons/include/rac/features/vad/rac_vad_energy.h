/**
 * @file rac_vad_energy.h
 * @brief Energy-based Voice Activity Detection
 *
 * C port of Swift's SimpleEnergyVADService.swift
 * Swift Source: Sources/RunAnywhere/Features/VAD/Services/SimpleEnergyVADService.swift
 *
 * IMPORTANT: This is a direct translation of the Swift implementation.
 * Do NOT add features not present in the Swift code.
 */

#ifndef RAC_VAD_ENERGY_H
#define RAC_VAD_ENERGY_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/vad/rac_vad_types.h"

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// CONSTANTS - Mirrors Swift's VADConstants
// NOTE: Core constants (RAC_VAD_DEFAULT_SAMPLE_RATE, RAC_VAD_DEFAULT_FRAME_LENGTH,
//       RAC_VAD_DEFAULT_ENERGY_THRESHOLD, RAC_VAD_DEFAULT_CALIBRATION_MULTIPLIER)
//       are defined in rac_vad_types.h
// =============================================================================

/** Frames of voice needed to start speech (normal mode) */
#define RAC_VAD_VOICE_START_THRESHOLD 1

/** Frames of silence needed to end speech (normal mode) */
#define RAC_VAD_VOICE_END_THRESHOLD 12

/** Frames of voice needed during TTS (prevents feedback) */
#define RAC_VAD_TTS_VOICE_START_THRESHOLD 10

/** Frames of silence needed during TTS */
#define RAC_VAD_TTS_VOICE_END_THRESHOLD 5

/** Number of calibration frames needed (~2 seconds at 100ms) */
#define RAC_VAD_CALIBRATION_FRAMES_NEEDED 20

/** Default calibration multiplier */
#define RAC_VAD_DEFAULT_CALIBRATION_MULTIPLIER 2.0f

/** Default TTS threshold multiplier */
#define RAC_VAD_DEFAULT_TTS_THRESHOLD_MULTIPLIER 3.0f

/** Maximum threshold cap */
#define RAC_VAD_MAX_THRESHOLD 0.020f

/** Minimum threshold */
#define RAC_VAD_MIN_THRESHOLD 0.003f

/** Maximum recent values for statistics */
#define RAC_VAD_MAX_RECENT_VALUES 50

// =============================================================================
// TYPES
// =============================================================================

/**
 * @brief Opaque handle for energy VAD service.
 */
typedef struct rac_energy_vad* rac_energy_vad_handle_t;

/**
 * @brief Speech activity event types.
 * Mirrors Swift's SpeechActivityEvent enum.
 */
typedef enum rac_speech_activity_event {
    RAC_SPEECH_ACTIVITY_STARTED = 0, /**< Speech has started */
    RAC_SPEECH_ACTIVITY_ENDED = 1    /**< Speech has ended */
} rac_speech_activity_event_t;

/**
 * @brief Configuration for energy VAD.
 * Mirrors Swift's SimpleEnergyVADService init parameters.
 */
typedef struct rac_energy_vad_config {
    /** Audio sample rate (default: 16000) */
    int32_t sample_rate;

    /** Frame length in seconds (default: 0.1 = 100ms) */
    float frame_length;

    /** Energy threshold for voice detection (default: 0.005) */
    float energy_threshold;
} rac_energy_vad_config_t;

/**
 * @brief Default energy VAD configuration.
 */
static const rac_energy_vad_config_t RAC_ENERGY_VAD_CONFIG_DEFAULT = {
    .sample_rate = RAC_VAD_DEFAULT_SAMPLE_RATE,
    .frame_length = RAC_VAD_DEFAULT_FRAME_LENGTH,
    .energy_threshold = RAC_VAD_DEFAULT_ENERGY_THRESHOLD};

/**
 * @brief Energy VAD statistics for debugging.
 * Mirrors Swift's SimpleEnergyVADService.getStatistics().
 * Note: This is separate from rac_vad_statistics_t in rac_vad_types.h
 */
typedef struct rac_energy_vad_stats {
    /** Current energy value */
    float current;

    /** Current threshold value */
    float threshold;

    /** Ambient noise level from calibration */
    float ambient;

    /** Recent average energy */
    float recent_avg;

    /** Recent maximum energy */
    float recent_max;
} rac_energy_vad_stats_t;

/**
 * @brief Callback for speech activity events.
 * Mirrors Swift's onSpeechActivity callback.
 *
 * @param event The speech activity event type
 * @param user_data User-provided context
 */
typedef void (*rac_speech_activity_callback_fn)(rac_speech_activity_event_t event, void* user_data);

/**
 * @brief Callback for processed audio buffers.
 * Mirrors Swift's onAudioBuffer callback.
 *
 * @param audio_data Audio data buffer
 * @param audio_size Size of audio data in bytes
 * @param user_data User-provided context
 */
typedef void (*rac_audio_buffer_callback_fn)(const void* audio_data, size_t audio_size,
                                             void* user_data);

// =============================================================================
// LIFECYCLE API - Mirrors Swift's VADService protocol
// =============================================================================

/**
 * @brief Create an energy VAD service.
 *
 * Mirrors Swift's SimpleEnergyVADService init.
 *
 * @param config Configuration (can be NULL for defaults)
 * @param out_handle Output: Handle to the created service
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_create(const rac_energy_vad_config_t* config,
                                           rac_energy_vad_handle_t* out_handle);

/**
 * @brief Destroy an energy VAD service.
 *
 * @param handle Service handle to destroy
 */
RAC_API void rac_energy_vad_destroy(rac_energy_vad_handle_t handle);

/**
 * @brief Initialize the VAD service.
 *
 * Mirrors Swift's VADService.initialize().
 * This starts the service and begins calibration.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_initialize(rac_energy_vad_handle_t handle);

/**
 * @brief Start voice activity detection.
 *
 * Mirrors Swift's SimpleEnergyVADService.start().
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_start(rac_energy_vad_handle_t handle);

/**
 * @brief Stop voice activity detection.
 *
 * Mirrors Swift's SimpleEnergyVADService.stop().
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_stop(rac_energy_vad_handle_t handle);

/**
 * @brief Reset the VAD state.
 *
 * Mirrors Swift's VADService.reset().
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_reset(rac_energy_vad_handle_t handle);

// =============================================================================
// PROCESSING API
// =============================================================================

/**
 * @brief Process raw audio data for voice activity detection.
 *
 * Mirrors Swift's SimpleEnergyVADService.processAudioData(_:).
 *
 * @param handle Service handle
 * @param audio_data Array of audio samples (float32)
 * @param sample_count Number of samples
 * @param out_has_voice Output: Whether voice was detected
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_process_audio(rac_energy_vad_handle_t handle,
                                                  const float* audio_data, size_t sample_count,
                                                  rac_bool_t* out_has_voice);

/**
 * @brief Calculate RMS energy of an audio signal.
 *
 * Mirrors Swift's calculateAverageEnergy(of:) using vDSP_rmsqv.
 *
 * @param audio_data Array of audio samples (float32)
 * @param sample_count Number of samples
 * @return RMS energy value, or 0.0 if empty
 */
RAC_API float rac_energy_vad_calculate_rms(const float* audio_data, size_t sample_count);

// =============================================================================
// PAUSE/RESUME API
// =============================================================================

/**
 * @brief Pause VAD processing.
 *
 * Mirrors Swift's SimpleEnergyVADService.pause().
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_pause(rac_energy_vad_handle_t handle);

/**
 * @brief Resume VAD processing.
 *
 * Mirrors Swift's SimpleEnergyVADService.resume().
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_resume(rac_energy_vad_handle_t handle);

// =============================================================================
// CALIBRATION API
// =============================================================================

/**
 * @brief Start automatic calibration to determine ambient noise level.
 *
 * Mirrors Swift's SimpleEnergyVADService.startCalibration().
 * Non-blocking; call rac_energy_vad_is_calibrating() to check status.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_start_calibration(rac_energy_vad_handle_t handle);

/**
 * @brief Check if calibration is in progress.
 *
 * @param handle Service handle
 * @param out_is_calibrating Output: RAC_TRUE if calibrating
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_is_calibrating(rac_energy_vad_handle_t handle,
                                                   rac_bool_t* out_is_calibrating);

/**
 * @brief Set calibration parameters.
 *
 * Mirrors Swift's setCalibrationParameters(multiplier:).
 *
 * @param handle Service handle
 * @param multiplier Calibration multiplier (clamped to 1.5-4.0)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_set_calibration_multiplier(rac_energy_vad_handle_t handle,
                                                               float multiplier);

// =============================================================================
// TTS FEEDBACK PREVENTION API
// =============================================================================

/**
 * @brief Notify VAD that TTS is about to start playing.
 *
 * Mirrors Swift's notifyTTSWillStart().
 * Increases threshold to prevent TTS audio from triggering VAD.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_notify_tts_start(rac_energy_vad_handle_t handle);

/**
 * @brief Notify VAD that TTS has finished playing.
 *
 * Mirrors Swift's notifyTTSDidFinish().
 * Restores threshold to base value.
 *
 * @param handle Service handle
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_notify_tts_finish(rac_energy_vad_handle_t handle);

/**
 * @brief Set TTS threshold multiplier.
 *
 * Mirrors Swift's setTTSThresholdMultiplier(_:).
 *
 * @param handle Service handle
 * @param multiplier TTS threshold multiplier (clamped to 2.0-5.0)
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_set_tts_multiplier(rac_energy_vad_handle_t handle,
                                                       float multiplier);

// =============================================================================
// STATE QUERY API
// =============================================================================

/**
 * @brief Check if speech is currently active.
 *
 * Mirrors Swift's VADService.isSpeechActive property.
 *
 * @param handle Service handle
 * @param out_is_active Output: RAC_TRUE if speech is active
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_is_speech_active(rac_energy_vad_handle_t handle,
                                                     rac_bool_t* out_is_active);

/**
 * @brief Get current energy threshold.
 *
 * @param handle Service handle
 * @param out_threshold Output: Current threshold value
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_get_threshold(rac_energy_vad_handle_t handle,
                                                  float* out_threshold);

/**
 * @brief Set energy threshold.
 *
 * @param handle Service handle
 * @param threshold New threshold value
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_set_threshold(rac_energy_vad_handle_t handle, float threshold);

/**
 * @brief Get VAD statistics for debugging.
 *
 * Mirrors Swift's getStatistics().
 *
 * @param handle Service handle
 * @param out_stats Output: VAD statistics
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_get_statistics(rac_energy_vad_handle_t handle,
                                                   rac_energy_vad_stats_t* out_stats);

/**
 * @brief Get sample rate.
 *
 * Mirrors Swift's sampleRate property.
 *
 * @param handle Service handle
 * @param out_sample_rate Output: Sample rate
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_get_sample_rate(rac_energy_vad_handle_t handle,
                                                    int32_t* out_sample_rate);

/**
 * @brief Get frame length in samples.
 *
 * Mirrors Swift's frameLengthSamples property.
 *
 * @param handle Service handle
 * @param out_frame_length Output: Frame length in samples
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_get_frame_length_samples(rac_energy_vad_handle_t handle,
                                                             int32_t* out_frame_length);

// =============================================================================
// CALLBACK API
// =============================================================================

/**
 * @brief Set speech activity callback.
 *
 * Mirrors Swift's onSpeechActivity property.
 *
 * @param handle Service handle
 * @param callback Callback function (can be NULL to clear)
 * @param user_data User-provided context
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_set_speech_callback(rac_energy_vad_handle_t handle,
                                                        rac_speech_activity_callback_fn callback,
                                                        void* user_data);

/**
 * @brief Set audio buffer callback.
 *
 * Mirrors Swift's onAudioBuffer property.
 *
 * @param handle Service handle
 * @param callback Callback function (can be NULL to clear)
 * @param user_data User-provided context
 * @return RAC_SUCCESS or error code
 */
RAC_API rac_result_t rac_energy_vad_set_audio_callback(rac_energy_vad_handle_t handle,
                                                       rac_audio_buffer_callback_fn callback,
                                                       void* user_data);

#ifdef __cplusplus
}
#endif

#endif /* RAC_VAD_ENERGY_H */
