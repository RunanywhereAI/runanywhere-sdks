// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "energy_vad.h"

#include <algorithm>
#include <cmath>

namespace ra::core::util {

namespace {
constexpr float kMaxThreshold = 0.020f;
constexpr float kMinThreshold = 0.003f;
}  // namespace

EnergyVAD::EnergyVAD(EnergyVADConfig cfg)
    : cfg_(cfg),
      current_threshold_(cfg.energy_threshold),
      base_threshold_(cfg.energy_threshold) {}

float EnergyVAD::rms(const float* pcm_f32, std::size_t num_samples) {
    if (!pcm_f32 || num_samples == 0) return 0.0f;
    double acc = 0.0;
    for (std::size_t i = 0; i < num_samples; ++i) {
        const double s = pcm_f32[i];
        acc += s * s;
    }
    return static_cast<float>(std::sqrt(acc / static_cast<double>(num_samples)));
}

int EnergyVAD::frame_length_samples() const {
    return static_cast<int>(cfg_.frame_length_s
                            * static_cast<float>(cfg_.sample_rate_hz));
}

void EnergyVAD::start_calibration() {
    calibrating_            = true;
    calibration_frames_seen_ = 0;
    calibration_sum_        = 0.0f;
    ambient_noise_          = 0.0f;
}

void EnergyVAD::finalize_calibration() {
    if (calibration_frames_seen_ == 0) { calibrating_ = false; return; }
    ambient_noise_ = calibration_sum_
                     / static_cast<float>(calibration_frames_seen_);
    float t = ambient_noise_ * calibration_multiplier_;
    t = std::clamp(t, kMinThreshold, kMaxThreshold);
    base_threshold_    = t;
    current_threshold_ = tts_playing_ ? t * tts_multiplier_ : t;
    calibrating_       = false;
}

void EnergyVAD::set_calibration_multiplier(float m) {
    calibration_multiplier_ = std::clamp(m, 1.5f, 4.0f);
}

void EnergyVAD::notify_tts_start() {
    tts_playing_       = true;
    current_threshold_ = std::min(base_threshold_ * tts_multiplier_, kMaxThreshold);
    voice_start_thr_   = 10;  // require 10 frames to trigger during TTS
    voice_end_thr_     = 5;
}

void EnergyVAD::notify_tts_finish() {
    tts_playing_       = false;
    current_threshold_ = base_threshold_;
    voice_start_thr_   = 1;
    voice_end_thr_     = 12;
}

void EnergyVAD::set_tts_multiplier(float m) {
    tts_multiplier_ = std::clamp(m, 2.0f, 5.0f);
}

void EnergyVAD::update_recent(float energy) {
    recent_energies_.push_back(energy);
    while (recent_energies_.size() > kMaxRecent) {
        recent_energies_.pop_front();
    }
}

EnergyVADStats EnergyVAD::stats() const {
    EnergyVADStats s;
    s.current   = recent_energies_.empty() ? 0.0f : recent_energies_.back();
    s.threshold = current_threshold_;
    s.ambient   = ambient_noise_;
    if (!recent_energies_.empty()) {
        float sum = 0.0f, mx = 0.0f;
        for (const auto v : recent_energies_) { sum += v; mx = std::max(mx, v); }
        s.recent_avg = sum / static_cast<float>(recent_energies_.size());
        s.recent_max = mx;
    }
    return s;
}

void EnergyVAD::reset() {
    speech_active_           = false;
    voice_start_frames_      = 0;
    voice_end_frames_        = 0;
    recent_energies_.clear();
    calibrating_             = false;
    calibration_frames_seen_ = 0;
    calibration_sum_         = 0.0f;
    ambient_noise_           = 0.0f;
    current_threshold_       = base_threshold_;
}

bool EnergyVAD::process(const float* pcm_f32, std::size_t num_samples) {
    const float energy = rms(pcm_f32, num_samples);
    update_recent(energy);

    if (calibrating_) {
        calibration_sum_ += energy;
        if (++calibration_frames_seen_ >= kCalibrationFramesNeeded) {
            finalize_calibration();
        }
        return false;
    }

    const bool voiced = energy > current_threshold_;
    if (voiced) {
        voice_end_frames_ = 0;
        if (!speech_active_) {
            if (++voice_start_frames_ >= voice_start_thr_) {
                speech_active_ = true;
                voice_start_frames_ = 0;
                if (on_activity_) on_activity_(SpeechActivity::kStarted);
            }
        }
    } else {
        voice_start_frames_ = 0;
        if (speech_active_) {
            if (++voice_end_frames_ >= voice_end_thr_) {
                speech_active_ = false;
                voice_end_frames_ = 0;
                if (on_activity_) on_activity_(SpeechActivity::kEnded);
            }
        }
    }
    return voiced;
}

}  // namespace ra::core::util
