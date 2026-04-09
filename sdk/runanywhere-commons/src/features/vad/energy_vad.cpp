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
#include <new>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/core/rac_structured_error.h"
#include "rac/features/vad/rac_vad_energy.h"

// =============================================================================
// INTERNAL STRUCTURE - Mirrors Swift's SimpleEnergyVADService properties
// =============================================================================

// Cache line size for alignment (64 bytes on most modern CPUs)
static constexpr size_t CACHE_LINE_SIZE = 64;

struct rac_energy_vad {

    // === Group 1: Hot processing data (read/written every frame) ===
    // Kept together on their own cache line(s) for spatial locality

    float energy_threshold;
    float energy_threshold_sq;   // energy_threshold², for sqrt-free comparison in hot path
    float base_energy_threshold;

    int32_t consecutive_silent_frames;
    int32_t consecutive_voice_frames;

    bool is_active;
    bool is_currently_speaking;
    bool is_paused;
    bool is_tts_active;

    int32_t voice_start_threshold;
    int32_t voice_end_threshold;
    int32_t tts_voice_start_threshold;
    int32_t tts_voice_end_threshold;

    // === Group 2: Debug ring buffer (written every frame, separate cache line) ===
    alignas(CACHE_LINE_SIZE) size_t ring_buffer_write_index;
    size_t ring_buffer_count;
    std::vector<float> recent_energy_values;
    int32_t max_recent_values;
    int32_t debug_frame_count;

    // === Group 3: Cold config data (set once at init, read-only in hot path) ===
    alignas(CACHE_LINE_SIZE) int32_t sample_rate;
    int32_t frame_length_samples;
    float tts_threshold_multiplier;
    float calibration_multiplier;

    // === Group 4: Calibration state (only active during calibration phase) ===
    bool is_calibrating;
    float ambient_noise_level;
    int32_t calibration_frame_count;
    int32_t calibration_frames_needed;
    std::vector<float> calibration_samples;

    // === Group 5: Callbacks (read in hot path, written rarely) ===
    alignas(CACHE_LINE_SIZE) rac_speech_activity_callback_fn speech_callback;
    void* speech_user_data;
    rac_audio_buffer_callback_fn audio_callback;
    void* audio_user_data;

    // === Group 6: Mutex (separate cache line to avoid false sharing) ===
    alignas(CACHE_LINE_SIZE) std::mutex mutex;
};

// Verify struct layout hasn't regressed. rac_energy_vad is split into
// cache-line-aligned groups (see alignas(64) above). If someone adds fields,
// this assert fires as a reminder to check the layout.
// On most platforms: ~448-512 bytes (varies due to std::mutex/vector sizes).
// The assert is generous; tighten it when profiling reveals a regression.
static_assert(sizeof(rac_energy_vad) <= 1024,
              "rac_energy_vad grew unexpectedly — check cache-line alignment groups");

// =============================================================================
// HELPER FUNCTIONS - Mirrors Swift's private methods
// =============================================================================

/**
 * Update threshold_sq whenever energy_threshold changes.
 * This pre-computes the squared threshold so the hot-path
 * comparison can use mean-square energy vs threshold² (no sqrt).
 */
static inline void update_threshold_sq(rac_energy_vad* vad) {
    vad->energy_threshold_sq = vad->energy_threshold * vad->energy_threshold;
}

/**
 * Compute mean-square energy (sum_of_squares / n) WITHOUT the final sqrt.
 * Used in the hot path to avoid a per-frame sqrt; the caller compares
 * the result against energy_threshold_sq instead.
 *
 * This is the same math as rac_energy_vad_calculate_rms() minus the sqrt.
 */
static float calculate_mean_square(const float* __restrict audio_data, size_t sample_count) {
    if (sample_count == 0 || audio_data == nullptr) {
        return 0.0f;
    }

    float s0 = 0.0f, s1 = 0.0f, s2 = 0.0f, s3 = 0.0f;
    size_t i = 0;

    for (; i + 3 < sample_count; i += 4) {
        const float a = audio_data[i];
        const float b = audio_data[i + 1];
        const float c = audio_data[i + 2];
        const float d = audio_data[i + 3];
        s0 += a * a;
        s1 += b * b;
        s2 += c * c;
        s3 += d * d;
    }

    float sum_squares = (s0 + s1) + (s2 + s3);

    for (; i < sample_count; ++i) {
        const float x = audio_data[i];
        sum_squares += x * x;
    }
    return sum_squares / static_cast<float>(sample_count);
}

/**
 * Update voice activity state with hysteresis.
 * Mirrors Swift's updateVoiceActivityState(hasVoice:).
 *
 * Returns the pending speech event to fire AFTER releasing the mutex:
 *   -1 = no event, RAC_SPEECH_ACTIVITY_STARTED (0), RAC_SPEECH_ACTIVITY_ENDED (1).
 * The caller is responsible for invoking the callback outside the lock.
 */
static int update_voice_activity_state(rac_energy_vad* vad, const bool has_voice) {
    // Use different thresholds based on TTS state (mirrors Swift logic)
    const int32_t start_threshold =
        vad->is_tts_active ? vad->tts_voice_start_threshold : vad->voice_start_threshold;
    const int32_t end_threshold =
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
                // Reset counter to prevent instant re-trigger once TTS ends.
                // Without this, consecutive_voice_frames keeps accumulating
                // across TTS duration and immediately exceeds the start threshold
                // on the first voiced frame after TTS finishes.
                vad->consecutive_voice_frames = 0;
                return -1;
            }

            vad->is_currently_speaking = true;
            RAC_LOG_INFO("EnergyVAD", "VAD: SPEECH STARTED");
            return RAC_SPEECH_ACTIVITY_STARTED;
        }
    } else {
        vad->consecutive_silent_frames++;
        vad->consecutive_voice_frames = 0;

        // Stop speaking if we have enough consecutive silent frames
        if (vad->is_currently_speaking && vad->consecutive_silent_frames >= end_threshold) {
            vad->is_currently_speaking = false;
            RAC_LOG_INFO("EnergyVAD", "VAD: SPEECH ENDED");
            return RAC_SPEECH_ACTIVITY_ENDED;
        }
    }

    return -1;
}

/**
 * Handle a frame during calibration
 * Mirrors Swift's handleCalibrationFrame(energy:)
 */
static void handle_calibration_frame(rac_energy_vad* vad, const float energy) {
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

        const size_t count = sorted_samples.size();
        const float percentile_90 =
            sorted_samples[std::min(count - 1, static_cast<size_t>(count * 0.90f))];

        // Use 90th percentile as ambient noise level (mirrors Swift)
        vad->ambient_noise_level = percentile_90;

        // Calculate dynamic threshold (mirrors Swift logic)
        const float minimum_threshold = std::max(vad->ambient_noise_level * 2.0f, RAC_VAD_MIN_THRESHOLD);
        const float calculated_threshold = vad->ambient_noise_level * vad->calibration_multiplier;

        // Apply threshold with sensible bounds
        vad->energy_threshold = std::max(calculated_threshold, minimum_threshold);

        // Cap at reasonable maximum (mirrors Swift cap)
        if (vad->energy_threshold > RAC_VAD_MAX_THRESHOLD) {
            vad->energy_threshold = RAC_VAD_MAX_THRESHOLD;
            RAC_LOG_WARNING("EnergyVAD",
                            "Calibration detected high ambient noise. Capping threshold.");
        }

        update_threshold_sq(vad);

        RAC_LOG_INFO("EnergyVAD", "VAD Calibration Complete");

        vad->is_calibrating = false;
        vad->calibration_samples.clear();
    }
}

/**
 * Update debug statistics
 * Mirrors Swift's updateDebugStatistics(energy:) 
 * Optimised to use ring buffer 
 */
static void update_debug_statistics(rac_energy_vad* vad, const float energy) {
    if (vad->recent_energy_values.empty()) {
        return;
    }
    
    vad->recent_energy_values[vad->ring_buffer_write_index] = energy;

    vad->ring_buffer_write_index++;
    if (vad->ring_buffer_write_index >= vad->recent_energy_values.size()) {
        vad->ring_buffer_write_index = 0;
    }

    if (vad->ring_buffer_count < vad->recent_energy_values.size()) {
        vad->ring_buffer_count++;
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

    rac_energy_vad* vad = new (std::nothrow) rac_energy_vad();
    if (!vad) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Initialize from config (mirrors Swift init)
    vad->sample_rate = cfg->sample_rate;
    vad->frame_length_samples =
        static_cast<int32_t>(cfg->frame_length * static_cast<float>(cfg->sample_rate));
    vad->energy_threshold = cfg->energy_threshold;
    vad->energy_threshold_sq = cfg->energy_threshold * cfg->energy_threshold;
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

    // Debug Ring Buffer Init
    vad->max_recent_values = RAC_VAD_MAX_RECENT_VALUES;
    vad->debug_frame_count = 0;
    vad->ring_buffer_write_index = 0;
    vad->ring_buffer_count = 0;

    vad->recent_energy_values.resize(vad->max_recent_values, 0.0f);

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

    // Deferred callback (invoked outside lock to prevent re-entrant deadlock)
    rac_speech_activity_callback_fn deferred_cb = nullptr;
    void* deferred_data = nullptr;

    {
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
                deferred_cb = handle->speech_callback;
                deferred_data = handle->speech_user_data;
            }
        }

        handle->is_active = false;
        handle->consecutive_silent_frames = 0;
        handle->consecutive_voice_frames = 0;

        RAC_LOG_INFO("EnergyVAD", "SimpleEnergyVADService stopped");
    }

    if (deferred_cb) {
        deferred_cb(RAC_SPEECH_ACTIVITY_ENDED, deferred_data);
    }

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

rac_result_t rac_energy_vad_process_audio(rac_energy_vad_handle_t handle, const float* __restrict audio_data,
                                          size_t sample_count, rac_bool_t* out_has_voice) {
    if (!handle || !audio_data || sample_count == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // --- Phase 1: Read shared flags under lock (minimal critical section) ---
    bool is_active;
    bool is_tts_active;
    bool is_paused;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        is_active = handle->is_active;
        is_tts_active = handle->is_tts_active;
        is_paused = handle->is_paused;
    }

    // Early-out checks (no lock needed)
    if (!is_active || is_tts_active || is_paused) {
        if (out_has_voice)
            *out_has_voice = RAC_FALSE;
        return RAC_SUCCESS;
    }

    // --- Phase 2: Pure math — no shared state, no lock needed ---
    // Compute mean-square energy (no sqrt). The hot-path voice detection
    // compares mean_sq > threshold² instead of sqrt(mean_sq) > threshold,
    // saving ~15 cycles/frame on ARM.
    const float mean_sq = calculate_mean_square(audio_data, sample_count);

    // Deferred callback data (invoked outside lock to prevent re-entrant deadlock).
    // If a callback re-enters any rac_energy_vad_* function on the same thread,
    // std::mutex (non-recursive) would deadlock without this deferral pattern.
    int pending_speech_event = -1;
    rac_speech_activity_callback_fn deferred_speech_cb = nullptr;
    void* deferred_speech_data = nullptr;
    rac_audio_buffer_callback_fn deferred_audio_cb = nullptr;
    void* deferred_audio_data = nullptr;

    // --- Phase 3: Update shared state under lock (minimal critical section) ---
    {
        std::lock_guard<std::mutex> lock(handle->mutex);

        // Re-check flags that may have changed between Phase 1 and Phase 3.
        // If stop()/pause()/notify_tts_start() ran in the gap, they already
        // handled state transitions (including SPEECH_ENDED callbacks).
        // Processing stale data here would cause duplicate callbacks.
        if (!handle->is_active || handle->is_tts_active || handle->is_paused) {
            if (out_has_voice)
                *out_has_voice = RAC_FALSE;
            return RAC_SUCCESS;
        }

        // Handle calibration if active — needs RMS (with sqrt) for
        // correct threshold calculation. Calibration is infrequent
        // (~20 frames at startup), so the sqrt cost is acceptable.
        if (handle->is_calibrating) {
            const float energy_rms = std::sqrt(mean_sq);
            update_debug_statistics(handle, mean_sq);
            handle_calibration_frame(handle, energy_rms);
            if (out_has_voice)
                *out_has_voice = RAC_FALSE;
            return RAC_SUCCESS;
        }

        // Normal operation: store mean-square in debug ring buffer.
        // get_statistics() converts back to RMS when reading.
        update_debug_statistics(handle, mean_sq);

        // Compare in squared domain — no sqrt needed.
        // Re-read threshold_sq under lock in case it changed (TTS notification).
        const bool has_voice = mean_sq > handle->energy_threshold_sq;

        // Update state (mirrors Swift's updateVoiceActivityState)
        pending_speech_event = update_voice_activity_state(handle, has_voice);

        // Copy callback pointers for deferred invocation outside the lock
        if (pending_speech_event >= 0 && handle->speech_callback) {
            deferred_speech_cb = handle->speech_callback;
            deferred_speech_data = handle->speech_user_data;
        }
        if (handle->audio_callback) {
            deferred_audio_cb = handle->audio_callback;
            deferred_audio_data = handle->audio_user_data;
        }

        if (out_has_voice) {
            *out_has_voice = has_voice ? RAC_TRUE : RAC_FALSE;
        }
    }

    // --- Phase 4: Invoke callbacks outside the lock ---
    if (deferred_speech_cb) {
        deferred_speech_cb(static_cast<rac_speech_activity_event_t>(pending_speech_event),
                           deferred_speech_data);
    }
    if (deferred_audio_cb) {
        deferred_audio_cb(audio_data, sample_count * sizeof(float), deferred_audio_data);
    }

    return RAC_SUCCESS;
}

float rac_energy_vad_calculate_rms(const float* __restrict audio_data,
                                  size_t sample_count) {
    if (sample_count == 0 || audio_data == nullptr) {
        return 0.0f;
    }

    float s0 = 0.0f, s1 = 0.0f, s2 = 0.0f, s3 = 0.0f;
    size_t i = 0;

    for (; i + 3 < sample_count; i += 4) {
        float a = audio_data[i];
        float b = audio_data[i + 1];
        float c = audio_data[i + 2];
        float d = audio_data[i + 3];
        s0 += a * a;
        s1 += b * b;
        s2 += c * c;
        s3 += d * d;
    }

    float sum_squares = (s0 + s1) + (s2 + s3);

    for (; i < sample_count; ++i) {
        float x = audio_data[i];
        sum_squares += x * x;
    }
    return std::sqrt(sum_squares / static_cast<float>(sample_count));
}

rac_result_t rac_energy_vad_pause(rac_energy_vad_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Deferred callback (invoked outside lock to prevent re-entrant deadlock)
    rac_speech_activity_callback_fn deferred_cb = nullptr;
    void* deferred_data = nullptr;

    {
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
                deferred_cb = handle->speech_callback;
                deferred_data = handle->speech_user_data;
            }
        }

        // Clear recent energy values (Reset Ring Buffer)
        handle->ring_buffer_count = 0;
        handle->ring_buffer_write_index = 0;
        // No need to zero out vector, just reset indices
        handle->consecutive_silent_frames = 0;
        handle->consecutive_voice_frames = 0;
    }

    if (deferred_cb) {
        deferred_cb(RAC_SPEECH_ACTIVITY_ENDED, deferred_data);
    }

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

    handle->is_currently_speaking = false;
    handle->consecutive_silent_frames = 0;
    handle->consecutive_voice_frames = 0;

    handle->ring_buffer_count = 0;
    handle->ring_buffer_write_index = 0;

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

    // Deferred callback (invoked outside lock to prevent re-entrant deadlock)
    rac_speech_activity_callback_fn deferred_cb = nullptr;
    void* deferred_data = nullptr;

    {
        std::lock_guard<std::mutex> lock(handle->mutex);

        // Mirrors Swift's notifyTTSWillStart()
        handle->is_tts_active = true;

        // Save base threshold
        handle->base_energy_threshold = handle->energy_threshold;

        // Increase threshold significantly to prevent TTS audio from triggering VAD
        float new_threshold = handle->energy_threshold * handle->tts_threshold_multiplier;
        handle->energy_threshold = std::min(new_threshold, 0.1f);
        update_threshold_sq(handle);

        RAC_LOG_INFO("EnergyVAD", "TTS starting - VAD blocked and threshold increased");

        // End any current speech detection
        if (handle->is_currently_speaking) {
            handle->is_currently_speaking = false;
            if (handle->speech_callback) {
                deferred_cb = handle->speech_callback;
                deferred_data = handle->speech_user_data;
            }
        }

        // Reset counters
        handle->consecutive_silent_frames = 0;
        handle->consecutive_voice_frames = 0;
    }

    if (deferred_cb) {
        deferred_cb(RAC_SPEECH_ACTIVITY_ENDED, deferred_data);
    }

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
    update_threshold_sq(handle);

    RAC_LOG_INFO("EnergyVAD", "TTS finished - VAD threshold restored");

    // Reset state for immediate readiness
    handle->ring_buffer_count = 0;
    handle->ring_buffer_write_index = 0;
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
    update_threshold_sq(handle);

    return RAC_SUCCESS;
}

rac_result_t rac_energy_vad_get_statistics(rac_energy_vad_handle_t handle,
                                           rac_energy_vad_stats_t* out_stats) {
    if (!handle || !out_stats) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);

    // Mirrors Swift's getStatistics()
    // Note: the ring buffer stores mean-square values (not RMS) to avoid
    // per-frame sqrt in process_audio(). We convert back to RMS here since
    // get_statistics() is called infrequently (on demand, not per frame).
    float recent_avg = 0.0f;
    float recent_max = 0.0f;
    float current = 0.0f;

    size_t count = handle->ring_buffer_count;
    if (count > 0) {

        size_t last_idx = (handle->ring_buffer_write_index == 0)
                              ? (handle->recent_energy_values.size() - 1)
                              : (handle->ring_buffer_write_index - 1);
        current = std::sqrt(handle->recent_energy_values[last_idx]);

        for (size_t i = 0; i < count; ++i) {
            float val = std::sqrt(handle->recent_energy_values[i]);
            recent_avg += val;
            recent_max = std::max(recent_max, val);
        }
        recent_avg /= static_cast<float>(count);
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
