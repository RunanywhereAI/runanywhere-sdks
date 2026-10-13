/**
 * @file test_tts_neurt_e2e.cpp
 * @brief End-to-end proof that SYNTHESIZE is reachable through the PUBLIC C API.
 *
 * `test_plugin_entry_neurt` only inspects the vtable's SHAPE: it can tell you `tts_ops` is
 * non-null, and nothing more. This file goes through the entry points a platform SDK uses --
 * rac_tts_create -> _initialize -> _synthesize -> rac_tts_result_free -- so a filled slot that
 * nothing can actually drive fails here rather than shipping.
 *
 * The assertions are chosen so that a driver returning a well-formed EMPTY buffer cannot pass.
 * That is the specific failure this whole family of tests exists to catch: "a bundle that loads
 * is not a bundle that works." An all-zero PCM buffer has a correct size, a correct sample rate
 * and a plausible duration, and is silence.
 *
 * Env-gated, and exits 77 (registered as CTest's SKIP_RETURN_CODE) when the bundle is absent, so
 * an absent bundle is reported as SKIPPED and never as passed -- the exact bug that let
 * test_stt_neurt_e2e report success for its entire existence without once running.
 */
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_neurt.h"
#include "rac/plugin/rac_primitive.h"

namespace {

int g_fail = 0;

void check(bool ok, const char* what) {
    std::fprintf(stdout, "  %s %s\n", ok ? "ok:" : "FAIL:", what);
    if (!ok) {
        ++g_fail;
    }
}

/** Peak absolute amplitude over a float32 PCM buffer (already normalised to 1.0). */
double peak_amplitude(const rac_tts_result_t& r) {
    const size_t n = r.audio_size / sizeof(float);
    if (n == 0 || !r.audio_data) {
        return 0.0;
    }
    const auto* pcm = static_cast<const float*>(r.audio_data);
    double peak = 0.0;
    for (size_t i = 0; i < n; ++i) {
        const double v = pcm[i] < 0.0f ? -static_cast<double>(pcm[i]) : pcm[i];
        if (v > peak) {
            peak = v;
        }
    }
    return peak;
}

/** Fraction of samples pinned at full scale. Saturation is what an int16 buffer read as
 *  float32 looks like: plausible duration, plausible rate, and 18.7% of it clipped. */
double clipped_fraction(const rac_tts_result_t& r) {
    const size_t n = r.audio_size / sizeof(float);
    if (n == 0 || !r.audio_data) {
        return 1.0;
    }
    const auto* pcm = static_cast<const float*>(r.audio_data);
    size_t hot = 0;
    for (size_t i = 0; i < n; ++i) {
        if (pcm[i] >= 0.999f || pcm[i] <= -0.999f) {
            ++hot;
        }
    }
    return static_cast<double>(hot) / static_cast<double>(n);
}

/** How many distinct sample values the buffer holds, capped -- a DC or constant buffer scores 1. */
size_t distinct_values(const rac_tts_result_t& r, size_t cap) {
    const size_t n = r.audio_size / sizeof(float);
    if (n == 0 || !r.audio_data) {
        return 0;
    }
    const auto* pcm = static_cast<const float*>(r.audio_data);
    // Small fixed set; n is tens of thousands, so a linear scan against a tiny table is fine.
    float seen[64];
    size_t count = 0;
    for (size_t i = 0; i < n && count < cap && count < 64; ++i) {
        bool known = false;
        for (size_t k = 0; k < count; ++k) {
            if (seen[k] == pcm[i]) {
                known = true;
                break;
            }
        }
        if (!known) {
            seen[count++] = pcm[i];
        }
    }
    return count;
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_tts_neurt_e2e\n");

    const char* bundle = std::getenv("RAC_TEST_NEURT_TTS_BUNDLE");
    if (!bundle || bundle[0] == '\0') {
        std::fprintf(stdout, "SKIP: set RAC_TEST_NEURT_TTS_BUNDLE to a Kokoro-82M _ANE bundle\n");
        return 77;   // CTest SKIP_RETURN_CODE -- reported as skipped, never as passed
    }

    const rac_engine_vtable_t* vt = rac_plugin_entry_neurt();
    check(vt != nullptr, "neurt plugin entry resolves");
    if (!vt) {
        return 1;
    }
    check(vt->tts_ops != nullptr, "neurt fills tts_ops");
    check(rac_plugin_register(vt) == RAC_SUCCESS, "neurt registers");
    check(rac_plugin_find(RAC_PRIMITIVE_SYNTHESIZE) != nullptr,
          "registry routes SYNTHESIZE after registration");

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_tts_create(bundle, &handle);
    check(rc == RAC_SUCCESS && handle != nullptr, "rac_tts_create");
    if (rc != RAC_SUCCESS || !handle) {
        std::fprintf(stderr, "  create rc=%d\n", static_cast<int>(rc));
        return 1;
    }

    rc = rac_tts_initialize(handle);
    check(rc == RAC_SUCCESS, "rac_tts_initialize");
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "  initialize rc=%d\n", static_cast<int>(rc));
        rac_tts_destroy(handle);
        return 1;
    }

    auto synthesize = [&](const char* text, rac_tts_result_t* out) -> bool {
        std::memset(out, 0, sizeof(*out));
        const rac_result_t r = rac_tts_synthesize(handle, text, nullptr, out);
        if (r != RAC_SUCCESS) {
            std::fprintf(stderr, "  synthesize(\"%s\") rc=%d\n", text, static_cast<int>(r));
            return false;
        }
        return true;
    };

    const char* kShort = "Hello.";
    const char* kLong = "The neural engine synthesizes this sentence entirely on device.";

    rac_tts_result_t shorter{};
    check(synthesize(kShort, &shorter), "rac_tts_synthesize (short)");

    rac_tts_result_t longer{};
    check(synthesize(kLong, &longer), "rac_tts_synthesize (long)");

    // --- The buffer is real audio, not a well-formed empty one ------------------------------
    check(longer.audio_size > 0, "audio_size is non-zero");
    check(longer.audio_size % sizeof(float) == 0, "audio_size is a whole number of float32 samples");
    check(longer.audio_format == RAC_AUDIO_FORMAT_PCM, "audio_format is PCM");

    // Rule 46: the sample rate is the model's, not a host default. Kokoro is 24 kHz, and
    // resampling silently to 16 kHz would still produce audible speech -- at the wrong pitch.
    check(longer.sample_rate == 24000, "sample_rate is the bundle's 24 kHz");

    const size_t samples = longer.audio_size / sizeof(float);
    const int64_t expected_ms =
        longer.sample_rate > 0 ? static_cast<int64_t>(samples) * 1000 / longer.sample_rate : 0;
    check(std::llabs(longer.duration_ms - expected_ms) <= 1,
          "duration_ms agrees with audio_size and sample_rate");

    // Silence is the failure this test exists for: it has the right size, rate and duration.
    const double peak = peak_amplitude(longer);
    check(peak > 0.01, "audio is not silence");
    check(peak <= 1.0, "audio does not clip past full scale");
    check(distinct_values(longer, 32) >= 32, "audio is not a constant/DC buffer");

    // The dtype is NOT in the type system: RAC_AUDIO_FORMAT_PCM names a container
    // (idl/model_types.proto -- pcm/wav/mp3/opus) and carries no bit depth, so an engine can
    // emit int16 where every consumer assumes float and nothing reports an error. Two checks
    // pin it. The duration cross-check above already fails on a wrong dtype -- reading int16 as
    // float halves the sample count while duration_ms still describes the true one. This second
    // check names the symptom directly, because int16 bit patterns read as float32 saturate.
    check(clipped_fraction(longer) < 0.01,
          "audio is not saturated (int16 read as float32 pins ~19% of samples at full scale)");

    // A driver returning a fixed-size scratch buffer passes every check above. Length has to
    // track the input.
    check(longer.audio_size > shorter.audio_size,
          "a longer sentence produces more audio than a shorter one");

    // A CPU/GPU fallback still produces correct audio -- it is only slower. Kokoro on the ANE
    // runs an order of magnitude faster than realtime, so "at least realtime" is a loose floor
    // that a full fallback cannot clear while staying well clear of CI noise. Loading is
    // excluded: processing_time_ms is the synthesis itself.
    const double realtime_x = longer.processing_time_ms > 0
        ? static_cast<double>(longer.duration_ms) / static_cast<double>(longer.processing_time_ms)
        : 0.0;
    check(realtime_x > 1.0, "synthesis is faster than realtime (not a compute-unit fallback)");

    std::fprintf(stdout,
                 "  short: %zu bytes  long: %zu bytes  %d Hz  %lld ms audio  "
                 "%lld ms synth  %.1fx realtime  peak %.3f\n",
                 shorter.audio_size, longer.audio_size, longer.sample_rate,
                 static_cast<long long>(longer.duration_ms),
                 static_cast<long long>(longer.processing_time_ms), realtime_x, peak);

    rac_tts_result_free(&shorter);
    rac_tts_result_free(&longer);
    rac_tts_cleanup(handle);
    rac_tts_destroy(handle);

    std::fprintf(stdout, g_fail == 0 ? "PASS\n" : "FAIL (%d)\n", g_fail);
    return g_fail == 0 ? 0 : 1;
}
