/**
 * @file energy_vad.cpp
 * @brief RunAnywhere Commons - Energy-based VAD Service Implementation
 *
 * C++ port of Swift's SimpleEnergyVADService.swift from:
 * Sources/RunAnywhere/Features/VAD/Services/SimpleEnergyVADService.swift
 *
 * CRITICAL: This is a direct port of Swift implementation - do NOT add custom logic!
 */

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_structured_error.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/features/vad/rac_vad_energy.h"

// =============================================================================
// INTERNAL STRUCTURE - Mirrors Swift's SimpleEnergyVADService properties
// =============================================================================

struct rac_energy_vad {
    // Configuration
    int32_t sample_rate;
    int32_t frame_length_samples;
    float energy_threshold;
    float base_energy_threshold;
    float tts_threshold_multiplier;
    float calibration_multiplier;

    // State tracking (mirrors Swift's state properties)
    bool is_active;
    bool is_currently_speaking;
    int32_t consecutive_silent_frames;
    int32_t consecutive_voice_frames;
    bool is_paused;
    bool is_tts_active;

    // Hysteresis parameters (mirrors Swift constants)
    int32_t voice_start_threshold;      // frames of voice to start
    int32_t voice_end_threshold;        // frames of silence to end
    int32_t tts_voice_start_threshold;  // more frames needed during TTS
    int32_t tts_voice_end_threshold;    // quicker end during TTS

    // Calibration (mirrors Swift calibration properties)
    bool is_calibrating;
    std::vector<float> calibration_samples;
    int32_t calibration_frame_count;
    int32_t calibration_frames_needed;
    float ambient_noise_level;

    // Debug statistics (mirrors Swift debug properties)
    std::vector<float> recent_energy_values;
    int32_t max_recent_values;
    int32_t debug_frame_count;

    // Callbacks
    rac_speech_activity_callback_fn speech_callback;
    void* speech_user_data;
    rac_audio_buffer_callback_fn audio_callback;
    void* audio_user_data;

    // Thread safety
    std::mutex mutex;
};

// =============================================================================
// HELPER FUNCTIONS - Mirrors Swift's private methods
// =============================================================================

/**
 * Update voice activity state with hysteresis
 * Mirrors Swift's updateVoiceActivityState(hasVoice:)
 */
static void update_voice_activity_state(rac_energy_vad* vad, bool has_voice) {
    // Use different thresholds based on TTS state (mirrors Swift logic)
    int32_t start_threshold =
        vad->is_tts_active ? vad->tts_voice_start_threshold : vad->voice_start_threshold;
    int32_t end_threshold =
        vad->is_tts_active ? vad->tts_voice_end_threshold : vad->voice_end_threshold;

    if (has_voice) {
        vad->consecutive_voice_frames++;
        vad->consecutive_silent_frames = 0;

        // Start speaking if we have enough consecutive voice frames
        if (!vad->is_currently_speaking && vad->consecutive_voice_frames >= start_threshold) {
            // Extra validation during TTS to prevent false positives (mirrors Swift)
            if (vad->is_tts_active) {
                RAC_LOG_WARNING("EnergyVAD",
                        "Voice detected during TTS playback - likely feedback! Ignoring.");
                return;
            }

            vad->is_currently_speaking = true;
            RAC_LOG_INFO("EnergyVAD", "VAD: SPEECH STARTED");

            // Fire callback
            if (vad->speech_callback) {
                vad->speech_callback(RAC_SPEECH_ACTIVITY_STARTED, vad->speech_user_data);
            }
        }
    } else {
        vad->consecutive_silent_frames++;
        vad->consecutive_voice_frames = 0;

        // Stop speaking if we have enough consecutive silent frames
        if (vad->is_currently_speaking && vad->consecutive_silent_frames >= end_threshold) {
            vad->is_currently_speaking = false;
            RAC_LOG_INFO("EnergyVAD", "VAD: SPEECH ENDED");

            // Fire callback
            if (vad->speech_callback) {
                vad->speech_callback(RAC_SPEECH_ACTIVITY_ENDED, vad->speech_user_data);
            }
        }
    }
}

/**
 * Handle a frame during calibration
 * Mirrors Swift's handleCalibrationFrame(energy:)
 */
static void handle_calibration_frame(rac_energy_vad* vad, float energy) {
    if (!vad->is_calibrating) {
        return;
    }

    vad->calibration_samples.push_back(energy);
    vad->calibration_frame_count++;

    if (vad->calibration_frame_count >= vad->calibration_frames_needed) {
        // Complete calibration - mirrors Swift's completeCalibration()
        if (vad->calibration_samples.empty()) {
            vad->is_calibrating = false;
            return;
        }

        // Calculate statistics (mirrors Swift logic)
        std::vector<float> sorted_samples = vad->calibration_samples;
        std::sort(sorted_samples.begin(), sorted_samples.end());

        size_t count = sorted_samples.size();
        float percentile_90 =
            sorted_samples[std::min(count - 1, static_cast<size_t>(count * 0.90f))];

        // Use 90th percentile as ambient noise level (mirrors Swift)
        vad->ambient_noise_level = percentile_90;

        // Calculate dynamic threshold (mirrors Swift logic)
        float minimum_threshold = std::max(vad->ambient_noise_level * 2.0f, RAC_VAD_MIN_THRESHOLD);
        float calculated_threshold = vad->ambient_noise_level * vad->calibration_multiplier;

        // Apply threshold with sensible bounds
        vad->energy_threshold = std::max(calculated_threshold, minimum_threshold);

        // Cap at reasonable maximum (mirrors Swift cap)
        if (vad->energy_threshold > RAC_VAD_MAX_THRESHOLD) {
            vad->energy_threshold = RAC_VAD_MAX_THRESHOLD;
            RAC_LOG_WARNING("EnergyVAD",
                    "Calibration detected high ambient noise. Capping threshold.");
        }

        RAC_LOG_INFO("EnergyVAD", "VAD Calibration Complete");

        vad->is_calibrating = false;
        vad->calibration_samples.clear();
    }
}

/**
 * Update debug statistics
 * Mirrors Swift's updateDebugStatistics(energy:)
 */
static void update_debug_statistics(rac_energy_vad* vad, float energy) {
    vad->recent_energy_values.push_back(energy);
    if (static_cast<int32_t>(vad->recent_energy_values.size()) > vad->max_recent_values) {
        vad->recent_energy_values.erase(vad->recent_energy_values.begin());
    }
}

// =============================================================================
// PUBLIC API - Mirrors Swift's VADService methods
// =============================================================================

rac_result_t rac_energy_vad_create(const rac_energy_vad_config_t* config,
                                   rac_energy_vad_handle_t* out_handle) {
    if (!out_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const rac_energy_vad_config_t* cfg = config ? config : &RAC_ENERGY_VAD_CONFIG_DEFAULT;

    rac_energy_vad* vad = new rac_energy_vad();

    // Initialize from config (mirrors Swift init)
    vad->sample_rate = cfg->sample_rate;
    vad->frame_length_samples =
        static_cast<int32_t>(cfg->frame_length * static_cast<float>(cfg->sample_rate));
    vad->energy_threshold = cfg->energy_threshold;
    vad->base_energy_threshold = cfg->energy_threshold;
    vad->calibration_multiplier = RAC_VAD_DEFAULT_CALIBRATION_MULTIPLIER;
    vad->tts_threshold_multiplier = RAC_VAD_DEFAULT_TTS_THRESHOLD_MULTIPLIER;

    // State tracking (mirrors Swift defaults)
    vad->is_active = false;
    vad->is_currently_speaking = false;
    vad->consecutive_silent_frames = 0;
    vad->consecutive_voice_frames = 0;
    vad->is_paused = false;
    vad->is_tts_active = false;

    // Hysteresis parameters (mirrors Swift constants)
    vad->voice_start_threshold = RAC_VAD_VOICE_START_THRESHOLD;
    vad->voice_end_threshold = RAC_VAD_VOICE_END_THRESHOLD;
    vad->tts_voice_start_threshold = RAC_VAD_TTS_VOICE_START_THRESHOLD;
    vad->tts_voice_end_threshold = RAC_VAD_TTS_VOICE_END_THRESHOLD;

    // Calibration (mirrors Swift defaults)
    vad->is_calibrating = false;
    vad->calibration_frame_count = 0;
    vad->calibration_frames_needed = RAC_VAD_CALIBRATION_FRAMES_NEEDED;
    vad->ambient_noise_level = 0.0f;

    // Debug (mirrors Swift defaults)
    vad->max_recent_values = RAC_VAD_MAX_RECENT_VALUES;
    vad->debug_frame_count = 0;

    // Callbacks
    vad->speech_callback = nullptr;
    vad->speech_user_data = nullptr;
    vad->audio_callback = nullptr;
    vad->audio_user_data = nullptr;

    RAC_LOG_INFO("EnergyVAD", "SimpleEnergyVADService initialized");

    *out_handle = vad;
    return RAC_SUCCESS;
}

void rac_energy_vad_destroy(rac_energy_vad_handle_t handle) {
    if (!handle) {
        return;
    }

    delete handle;
    RAC_LOG_DEBUG("EnergyVAD", "SimpleEnergyVADService destroyed");
}

rac_result_t rac_energy_vad_initialize(rac_energy_vad_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's initialize() - start and begin calibration
    handle->is_active = true;
    handle->is_currently_speaking = false;
    handle->consecutive_silent_frames = 0;
    handle->consecutive_voice_frames = 0;

    // Start calibration (mirrors Swift's startCalibration)
    RAC_LOG_INFO("EnergyVAD", "Starting VAD calibration - measuring ambient noise");

    handle->is_calibrating = true;
    handle->calibration_samples.clear();
    handle->calibration_frame_count = 0;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_start(rac_energy_vad_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's start()
    if (handle->is_active) {
        return RAC_SUCCESS;
    }

    handle->is_active = true;
    handle->is_currently_speaking = false;
    handle->consecutive_silent_frames = 0;
    handle->consecutive_voice_frames = 0;

    RAC_LOG_INFO("EnergyVAD", "SimpleEnergyVADService started");
    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_stop(rac_energy_vad_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's stop()
    if (!handle->is_active) {
        return RAC_SUCCESS;
    }

    // If currently speaking, send end event
    if (handle->is_currently_speaking) {
        handle->is_currently_speaking = false;
        RAC_LOG_INFO("EnergyVAD", "VAD: SPEECH ENDED (stopped)");

        if (handle->speech_callback) {
            handle->speech_callback(RAC_SPEECH_ACTIVITY_ENDED, handle->speech_user_data);
        }
    }

    handle->is_active = false;
    handle->consecutive_silent_frames = 0;
    handle->consecutive_voice_frames = 0;

    RAC_LOG_INFO("EnergyVAD", "SimpleEnergyVADService stopped");
    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_reset(rac_energy_vad_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's reset()
    handle->is_active = false;
    handle->is_currently_speaking = false;
    handle->consecutive_silent_frames = 0;
    handle->consecutive_voice_frames = 0;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_process_audio(rac_energy_vad_handle_t handle, const float* audio_data,
                                          size_t sample_count, rac_bool_t* out_has_voice) {
    if (!handle || !audio_data || sample_count == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's processAudioData(_:)
    if (!handle->is_active) {
        if (out_has_voice)
            *out_has_voice = RAC_FALSE;
        return RAC_SUCCESS;
    }

    // Complete audio blocking during TTS (mirrors Swift)
    if (handle->is_tts_active) {
        if (out_has_voice)
            *out_has_voice = RAC_FALSE;
        return RAC_SUCCESS;
    }

    if (handle->is_paused) {
        if (out_has_voice)
            *out_has_voice = RAC_FALSE;
        return RAC_SUCCESS;
    }

    // Calculate energy using RMS
    float energy = rac_energy_vad_calculate_rms(audio_data, sample_count);

    // Update debug statistics
    update_debug_statistics(handle, energy);

    // Handle calibration if active (mirrors Swift)
    if (handle->is_calibrating) {
        handle_calibration_frame(handle, energy);
        if (out_has_voice)
            *out_has_voice = RAC_FALSE;
        return RAC_SUCCESS;
    }

    bool has_voice = energy > handle->energy_threshold;

    // Update state (mirrors Swift's updateVoiceActivityState)
    update_voice_activity_state(handle, has_voice);

    // Call audio buffer callback if provided
    if (handle->audio_callback) {
        handle->audio_callback(audio_data, sample_count * sizeof(float), handle->audio_user_data);
    }

    if (out_has_voice) {
        *out_has_voice = has_voice ? RAC_TRUE : RAC_FALSE;
    }

    return RAC_SUCCESS;
}

float rac_energy_vad_calculate_rms(const float* audio_data, size_t sample_count) {
    if (sample_count == 0 || audio_data == nullptr) {
        return 0.0f;
    }

    // RMS calculation: sqrt(sum(x^2) / N)
    // Mirrors Swift's calculateAverageEnergy using vDSP_rmsqv
    float sum_squares = 0.0f;
    for (size_t i = 0; i < sample_count; ++i) {
        sum_squares += audio_data[i] * audio_data[i];
    }
    return std::sqrt(sum_squares / static_cast<float>(sample_count));
}

rac_result_t rac_energy_vad_pause(rac_energy_vad_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's pause()
    if (handle->is_paused) {
        return RAC_SUCCESS;
    }

    handle->is_paused = true;
    RAC_LOG_INFO("EnergyVAD", "VAD paused");

    // If currently speaking, send end event
    if (handle->is_currently_speaking) {
        handle->is_currently_speaking = false;
        if (handle->speech_callback) {
            handle->speech_callback(RAC_SPEECH_ACTIVITY_ENDED, handle->speech_user_data);
        }
    }

    // Clear recent energy values
    handle->recent_energy_values.clear();
    handle->consecutive_silent_frames = 0;
    handle->consecutive_voice_frames = 0;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_resume(rac_energy_vad_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's resume()
    if (!handle->is_paused) {
        return RAC_SUCCESS;
    }

    handle->is_paused = false;

    // Reset state for clean resumption
    handle->is_currently_speaking = false;
    handle->consecutive_silent_frames = 0;
    handle->consecutive_voice_frames = 0;
    handle->recent_energy_values.clear();
    handle->debug_frame_count = 0;

    RAC_LOG_INFO("EnergyVAD", "VAD resumed");
    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_start_calibration(rac_energy_vad_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    RAC_LOG_INFO("EnergyVAD", "Starting VAD calibration");

    handle->is_calibrating = true;
    handle->calibration_samples.clear();
    handle->calibration_frame_count = 0;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_is_calibrating(rac_energy_vad_handle_t handle,
                                           rac_bool_t* out_is_calibrating) {
    if (!handle || !out_is_calibrating) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    *out_is_calibrating = handle->is_calibrating ? RAC_TRUE : RAC_FALSE;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_set_calibration_multiplier(rac_energy_vad_handle_t handle,
                                                       float multiplier) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's setCalibrationParameters(multiplier:) - clamp to 1.5-4.0
    handle->calibration_multiplier = std::max(1.5f, std::min(4.0f, multiplier));

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_notify_tts_start(rac_energy_vad_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's notifyTTSWillStart()
    handle->is_tts_active = true;

    // Save base threshold
    handle->base_energy_threshold = handle->energy_threshold;

    // Increase threshold significantly to prevent TTS audio from triggering VAD
    float new_threshold = handle->energy_threshold * handle->tts_threshold_multiplier;
    handle->energy_threshold = std::min(new_threshold, 0.1f);

    RAC_LOG_INFO("EnergyVAD", "TTS starting - VAD blocked and threshold increased");

    // End any current speech detection
    if (handle->is_currently_speaking) {
        handle->is_currently_speaking = false;
        if (handle->speech_callback) {
            handle->speech_callback(RAC_SPEECH_ACTIVITY_ENDED, handle->speech_user_data);
        }
    }

    // Reset counters
    handle->consecutive_silent_frames = 0;
    handle->consecutive_voice_frames = 0;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_notify_tts_finish(rac_energy_vad_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's notifyTTSDidFinish()
    handle->is_tts_active = false;

    // Immediately restore threshold
    handle->energy_threshold = handle->base_energy_threshold;

    RAC_LOG_INFO("EnergyVAD", "TTS finished - VAD threshold restored");

    // Reset state for immediate readiness
    handle->recent_energy_values.clear();
    handle->consecutive_silent_frames = 0;
    handle->consecutive_voice_frames = 0;
    handle->is_currently_speaking = false;
    handle->debug_frame_count = 0;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_set_tts_multiplier(rac_energy_vad_handle_t handle, float multiplier) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's setTTSThresholdMultiplier(_:) - clamp to 2.0-5.0
    handle->tts_threshold_multiplier = std::max(2.0f, std::min(5.0f, multiplier));

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_is_speech_active(rac_energy_vad_handle_t handle,
                                             rac_bool_t* out_is_active) {
    if (!handle || !out_is_active) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's isSpeechActive
    *out_is_active = handle->is_currently_speaking ? RAC_TRUE : RAC_FALSE;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_get_threshold(rac_energy_vad_handle_t handle, float* out_threshold) {
    if (!handle || !out_threshold) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    *out_threshold = handle->energy_threshold;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_set_threshold(rac_energy_vad_handle_t handle, float threshold) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    handle->energy_threshold = threshold;
    handle->base_energy_threshold = threshold;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_get_statistics(rac_energy_vad_handle_t handle,
                                           rac_energy_vad_stats_t* out_stats) {
    if (!handle || !out_stats) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's getStatistics()
    float recent_avg = 0.0f;
    float recent_max = 0.0f;
    float current = 0.0f;

    if (!handle->recent_energy_values.empty()) {
        for (float val : handle->recent_energy_values) {
            recent_avg += val;
            recent_max = std::max(recent_max, val);
        }
        recent_avg /= static_cast<float>(handle->recent_energy_values.size());
        current = handle->recent_energy_values.back();
    }

    out_stats->current = current;
    out_stats->threshold = handle->energy_threshold;
    out_stats->ambient = handle->ambient_noise_level;
    out_stats->recent_avg = recent_avg;
    out_stats->recent_max = recent_max;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_get_sample_rate(rac_energy_vad_handle_t handle,
                                            int32_t* out_sample_rate) {
    if (!handle || !out_sample_rate) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    *out_sample_rate = handle->sample_rate;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_get_frame_length_samples(rac_energy_vad_handle_t handle,
                                                     int32_t* out_frame_length) {
    if (!handle || !out_frame_length) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    *out_frame_length = handle->frame_length_samples;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_set_speech_callback(rac_energy_vad_handle_t handle,
                                                rac_speech_activity_callback_fn callback,
                                                void* user_data) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->speech_callback = callback;
    handle->speech_user_data = user_data;

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_set_audio_callback(rac_energy_vad_handle_t handle,
                                               rac_audio_buffer_callback_fn callback,
                                               void* user_data) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    handle->audio_callback = callback;
    handle->audio_user_data = user_data;

    return RAC_SUCCESS;
}
