// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "energy_vad.h"

#include <gtest/gtest.h>

#include <cmath>
#include <vector>

namespace {

using ra::core::util::EnergyVAD;
using ra::core::util::EnergyVADConfig;
using ra::core::util::SpeechActivity;

std::vector<float> tone(std::size_t n, float amplitude, float freq_hz = 440.0f,
                        int sr = 16000) {
    std::vector<float> out(n);
    for (std::size_t i = 0; i < n; ++i) {
        out[i] = amplitude * std::sin(2.0f * 3.14159265358979f
                                      * freq_hz * static_cast<float>(i)
                                      / static_cast<float>(sr));
    }
    return out;
}

TEST(EnergyVAD, RmsOfSilenceIsZero) {
    const std::vector<float> silence(16000, 0.0f);
    EXPECT_FLOAT_EQ(EnergyVAD::rms(silence.data(), silence.size()), 0.0f);
}

TEST(EnergyVAD, RmsOfFullScaleToneIsHalfSqrt2) {
    const auto samples = tone(16000, 1.0f);
    const auto r = EnergyVAD::rms(samples.data(), samples.size());
    EXPECT_NEAR(r, 0.7071f, 0.01f);
}

TEST(EnergyVAD, CalibrationAdjustsThresholdFromAmbient) {
    EnergyVAD v;
    v.start_calibration();
    const auto quiet = tone(1600, 0.001f);  // 100 ms of very quiet audio
    // Feed 20 frames of the quiet signal to complete calibration.
    for (int i = 0; i < 20; ++i) {
        v.process(quiet.data(), quiet.size());
    }
    EXPECT_FALSE(v.is_calibrating());
    // Ambient calibration should have brought the threshold down to the
    // min, not stayed at the initial 0.005 guess (ambient * 2 < min).
    EXPECT_GE(v.threshold(), 0.003f);
    EXPECT_LE(v.threshold(), 0.020f);
}

TEST(EnergyVAD, DetectsSpeechTransitionAndInvokesCallback) {
    EnergyVAD v;
    v.set_threshold(0.05f);  // manual threshold bypasses calibration
    int starts = 0, ends = 0;
    v.on_speech_activity([&](SpeechActivity a) {
        if (a == SpeechActivity::kStarted) ++starts;
        else                                ++ends;
    });

    const auto quiet = tone(1600, 0.001f);
    const auto loud  = tone(1600, 0.5f);

    v.process(quiet.data(), quiet.size());
    EXPECT_FALSE(v.is_speech_active());

    v.process(loud.data(), loud.size());  // 1 frame ≥ voice_start_thr
    EXPECT_TRUE(v.is_speech_active());
    EXPECT_EQ(starts, 1);

    // Need 12 quiet frames to end speech.
    for (int i = 0; i < 12; ++i) v.process(quiet.data(), quiet.size());
    EXPECT_FALSE(v.is_speech_active());
    EXPECT_EQ(ends, 1);
}

TEST(EnergyVAD, TtsPlaybackRaisesThreshold) {
    EnergyVAD v;
    v.set_threshold(0.01f);
    const float before = v.threshold();
    v.notify_tts_start();
    EXPECT_GT(v.threshold(), before);
    v.notify_tts_finish();
    EXPECT_FLOAT_EQ(v.threshold(), before);
}

}  // namespace
