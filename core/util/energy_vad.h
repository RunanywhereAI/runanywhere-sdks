// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Energy-based Voice Activity Detection. Ports the capability from
// `sdk/runanywhere-commons/include/rac/features/vad/rac_vad_energy.h`
// into C++20 / RAII.
//
// Lightweight VAD with no ML dependencies — suitable as a fallback when
// silero-onnx isn't available or for low-power devices. Auto-calibrates
// against ambient noise on the first N frames then tracks the
// speech/silence state machine. TTS feedback suppression raises the
// threshold temporarily while the assistant is speaking.

#ifndef RA_CORE_ENERGY_VAD_H
#define RA_CORE_ENERGY_VAD_H

#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>

namespace ra::core::util {

struct EnergyVADConfig {
    int   sample_rate_hz  = 16000;
    float frame_length_s  = 0.1f;     // 100 ms
    float energy_threshold = 0.005f;  // Initial guess; refined by calibration
};

struct EnergyVADStats {
    float current    = 0.0f;
    float threshold  = 0.0f;
    float ambient    = 0.0f;
    float recent_avg = 0.0f;
    float recent_max = 0.0f;
};

enum class SpeechActivity { kStarted, kEnded };

class EnergyVAD {
public:
    explicit EnergyVAD(EnergyVADConfig cfg = {});

    // Process `num_samples` of f32 PCM. Returns true when the current
    // frame is voiced. Also drives state transitions which invoke the
    // speech activity callback if set.
    bool process(const float* pcm_f32, std::size_t num_samples);

    // Clear state + restart calibration from scratch.
    void reset();

    // --- Calibration -----------------------------------------------------
    void  start_calibration();
    bool  is_calibrating() const { return calibrating_; }
    void  set_calibration_multiplier(float m);

    // --- TTS feedback suppression ---------------------------------------
    void  notify_tts_start();
    void  notify_tts_finish();
    void  set_tts_multiplier(float m);

    // --- State / stats ---------------------------------------------------
    bool  is_speech_active() const { return speech_active_; }
    float threshold() const        { return current_threshold_; }
    void  set_threshold(float t)   { current_threshold_ = t; base_threshold_ = t; }
    EnergyVADStats stats() const;

    int   sample_rate() const          { return cfg_.sample_rate_hz; }
    int   frame_length_samples() const;

    // --- Callback --------------------------------------------------------
    void on_speech_activity(std::function<void(SpeechActivity)> cb) {
        on_activity_ = std::move(cb);
    }

    // RMS of an f32 buffer. Returns 0 for empty input.
    static float rms(const float* pcm_f32, std::size_t num_samples);

private:
    void update_recent(float energy);
    void finalize_calibration();

    EnergyVADConfig cfg_;
    float           current_threshold_;
    float           base_threshold_;
    float           ambient_noise_ = 0.0f;
    float           calibration_multiplier_ = 2.0f;
    float           tts_multiplier_         = 3.0f;

    // State machine — matches legacy defaults (1 frame to start, 12 to end).
    int             voice_start_frames_ = 0;
    int             voice_end_frames_   = 0;
    int             voice_start_thr_    = 1;
    int             voice_end_thr_      = 12;

    bool            speech_active_ = false;
    bool            tts_playing_   = false;
    bool            calibrating_   = false;
    int             calibration_frames_seen_ = 0;
    static constexpr int kCalibrationFramesNeeded = 20;
    float           calibration_sum_    = 0.0f;

    std::deque<float> recent_energies_;
    static constexpr std::size_t kMaxRecent = 50;

    std::function<void(SpeechActivity)> on_activity_;
};

}  // namespace ra::core::util

#endif  // RA_CORE_ENERGY_VAD_H
