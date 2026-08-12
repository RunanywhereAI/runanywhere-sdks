/**
 * @file test_audio_compute_level_db.cpp
 * @brief Sanity tests for rac_audio_compute_level_db (RMS->dB DSP centralised
 *        from Swift AudioCaptureManager.updateAudioLevel).
 */

#include "test_common.h"

#include <cmath>
#include <cstddef>
#include <vector>

#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_error.h"

// -----------------------------------------------------------------------------
// Test: silence -> -100 dB floor
// -----------------------------------------------------------------------------

static TestResult test_silence_floor() {
    std::vector<float> samples(1024, 0.0f);
    float db = 0.0f;
    rac_result_t rc = rac_audio_compute_level_db(samples.data(), samples.size(), &db);
    ASSERT_EQ(rc, RAC_SUCCESS, "compute_level_db should succeed on silence");
    ASSERT_TRUE(db == -100.0f, "silent buffer must clamp to -100 dB floor");
    return TEST_PASS();
}

// -----------------------------------------------------------------------------
// Test: full-scale sine -> ~ -3 dB (RMS of a unit-amplitude sine is 1/sqrt(2))
// -----------------------------------------------------------------------------

static TestResult test_full_scale_sine() {
    // RMS of a sine with amplitude 1.0 is 1/sqrt(2) ~= 0.7071,
    // so 20 * log10(0.7071) ~= -3.0103 dB.
    const size_t num_samples = 16000;
    const double freq = 440.0;
    const double sample_rate = 16000.0;
    std::vector<float> samples(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        samples[i] =
            static_cast<float>(std::sin(2.0 * M_PI * freq * static_cast<double>(i) / sample_rate));
    }

    float db = 0.0f;
    rac_result_t rc = rac_audio_compute_level_db(samples.data(), samples.size(), &db);
    ASSERT_EQ(rc, RAC_SUCCESS, "compute_level_db should succeed on sine");
    ASSERT_TRUE(db < 0.0f, "sine RMS < 1.0 implies dB < 0");
    ASSERT_TRUE(std::fabs(db - (-3.0103f)) < 0.05f, "unit-amplitude sine should yield ~ -3 dB RMS");
    return TEST_PASS();
}

// -----------------------------------------------------------------------------
// Test: constant DC at amplitude 1.0 -> 0 dB (RMS == 1.0 -> 20*log10(1)=0)
// -----------------------------------------------------------------------------

static TestResult test_full_scale_dc() {
    std::vector<float> samples(512, 1.0f);
    float db = 0.0f;
    rac_result_t rc = rac_audio_compute_level_db(samples.data(), samples.size(), &db);
    ASSERT_EQ(rc, RAC_SUCCESS, "compute_level_db should succeed on full-scale DC");
    ASSERT_TRUE(std::fabs(db) < 1e-4f, "RMS=1.0 must yield 0 dB");
    return TEST_PASS();
}

// -----------------------------------------------------------------------------
// Test: NULL / zero-count validation
// -----------------------------------------------------------------------------

static TestResult test_null_validation() {
    float db = 0.0f;
    ASSERT_EQ(rac_audio_compute_level_db(nullptr, 16, &db), RAC_ERROR_NULL_POINTER,
              "NULL samples should be rejected");

    std::vector<float> samples(16, 0.0f);
    ASSERT_EQ(rac_audio_compute_level_db(samples.data(), 0, &db), RAC_ERROR_NULL_POINTER,
              "zero count should be rejected");
    ASSERT_EQ(rac_audio_compute_level_db(samples.data(), samples.size(), nullptr),
              RAC_ERROR_NULL_POINTER, "NULL out_db should be rejected");

    return TEST_PASS();
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

int main(int argc, char** argv) {
    TestSuite suite("audio_compute_level_db");
    suite.add("silence_floor", test_silence_floor);
    suite.add("full_scale_sine", test_full_scale_sine);
    suite.add("full_scale_dc", test_full_scale_dc);
    suite.add("null_validation", test_null_validation);
    return suite.run(argc, argv);
}
