/**
 * @file test_diarization_onnx.cpp
 * @brief Streaming-Sortformer diarization provider: wiring, self-contained DSP
 *        math vs independent scalar oracles, and graceful-failure contracts.
 *
 * This target does NOT need ONNX Runtime weights or the 492 MB Sortformer
 * bundle. It exercises three things that are cheap and deterministic:
 *   (a) the diarization service op-table (g_onnx_diarization_ops) is fully
 *       populated so Commons can dispatch through it;
 *   (b) the pure math the provider ships — radix-2 FFT, the 128-mel Slaney
 *       log-filterbank, per-speaker median smoothing, and probability ->
 *       segment binarization — each matches a hand-written scalar reference;
 *   (c) create()/initialize()/diarize() reject a null/missing model with an
 *       error code instead of crashing.
 *
 * The provider .cpp is #included directly so the file-local (anonymous-
 * namespace) DSP helpers are reachable from the test TU; the service-vtable
 * adapter (rac_onnx_diarization_register.cpp) is compiled as a separate source
 * to expose g_onnx_diarization_ops. Neither pulls in rac_backend_onnx, so the
 * provider's symbols are defined exactly once (here).
 */

// The production provider TU. Included (not linked) so the anonymous-namespace
// math helpers compute_log_mel_features / median_filter_preds / binarize_preds
// and the FftTables / Slaney helpers are in this translation unit.
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "onnx_diarization_provider.cpp"  // NOLINT(bugprone-suspicious-include)
#include "rac/core/rac_error.h"
#include "rac/features/diarization/rac_diarization_service.h"
#include "rac/features/diarization/rac_diarization_types.h"

// The service-vtable adapter, compiled as a sibling TU.
extern "C" const rac_diarization_service_ops_t g_onnx_diarization_ops;

// Reach the provider's file-local DSP helpers + constants.
using namespace runanywhere::diarization;

namespace {

int g_checks = 0;
int g_failures = 0;

#define CHECK(condition, label)                                                      \
    do {                                                                             \
        ++g_checks;                                                                  \
        if (condition) {                                                             \
            std::fprintf(stdout, "  ok:   %s\n", label);                             \
        } else {                                                                     \
            ++g_failures;                                                            \
            std::fprintf(stderr, "  FAIL: %s (%s:%d)\n", label, __FILE__, __LINE__); \
        }                                                                            \
    } while (0)

constexpr double kPiD = 3.14159265358979323846;

// -----------------------------------------------------------------------------
// (b1) Radix-2 FFT vs an independent naive DFT (double precision).
// -----------------------------------------------------------------------------
bool test_fft() {
    bool ok = true;
    FftTables fft;

    // Impulse -> flat unit spectrum (re[k]=1, im[k]=0 for every bin).
    {
        std::vector<float> re(kNFft, 0.0f);
        std::vector<float> im(kNFft, 0.0f);
        re[0] = 1.0f;
        fft.forward(re, im);
        for (size_t k = 0; k < kNFft; ++k) {
            if (std::fabs(re[k] - 1.0f) > 1e-4f || std::fabs(im[k]) > 1e-4f) {
                ok = false;
                break;
            }
        }
    }
    CHECK(ok, "FFT: unit impulse maps to a flat spectrum");

    // Composite real signal vs naive DFT: X[k] = sum_n x[n] (cos - i sin).
    std::vector<float> x(kNFft);
    for (size_t n = 0; n < kNFft; ++n) {
        const double nn = static_cast<double>(n) / static_cast<double>(kNFft);
        x[n] = static_cast<float>(std::sin(2.0 * kPiD * 5.0 * nn) +
                                  0.5 * std::cos(2.0 * kPiD * 20.0 * nn) +
                                  0.25 * std::sin(2.0 * kPiD * 63.0 * nn));
    }
    std::vector<float> re(x);
    std::vector<float> im(kNFft, 0.0f);
    fft.forward(re, im);

    double max_err = 0.0;
    for (size_t k = 0; k < kNFft; ++k) {
        double ref_re = 0.0;
        double ref_im = 0.0;
        for (size_t n = 0; n < kNFft; ++n) {
            const double ang = 2.0 * kPiD * static_cast<double>(k) * static_cast<double>(n) /
                               static_cast<double>(kNFft);
            ref_re += static_cast<double>(x[n]) * std::cos(ang);
            ref_im -= static_cast<double>(x[n]) * std::sin(ang);
        }
        max_err = std::max(max_err, std::fabs(static_cast<double>(re[k]) - ref_re));
        max_err = std::max(max_err, std::fabs(static_cast<double>(im[k]) - ref_im));
    }
    CHECK(max_err < 1e-1, "FFT: composite signal matches naive DFT (max |err| < 0.1)");
    return ok && max_err < 1e-1;
}

// -----------------------------------------------------------------------------
// (b2) 128-mel Slaney log-filterbank vs an independent Slaney reference.
// -----------------------------------------------------------------------------
double ref_hz_to_mel(double hz) {
    constexpr double f_sp = 200.0 / 3.0;
    constexpr double min_log_hz = 1000.0;
    constexpr double min_log_mel = min_log_hz / f_sp;
    constexpr double logstep = 0.06875177742094912;
    return hz < min_log_hz ? hz / f_sp : min_log_mel + std::log(hz / min_log_hz) / logstep;
}
double ref_mel_to_hz(double mel) {
    constexpr double f_sp = 200.0 / 3.0;
    constexpr double min_log_hz = 1000.0;
    constexpr double min_log_mel = min_log_hz / f_sp;
    constexpr double logstep = 0.06875177742094912;
    return mel < min_log_mel ? mel * f_sp : min_log_hz * std::exp((mel - min_log_mel) * logstep);
}

bool test_mel_filterbank() {
    const std::vector<float> fb = build_mel_filterbank();  // (kNMels * kFreqBins)
    if (fb.size() != kNMels * kFreqBins) {
        CHECK(false, "mel filterbank has (kNMels * kFreqBins) entries");
        return false;
    }

    // Independent Slaney filterbank.
    const double sr = static_cast<double>(kSampleRate);
    const double fmax = sr / 2.0;
    const double mel_min = ref_hz_to_mel(0.0);
    const double mel_max = ref_hz_to_mel(fmax);
    std::vector<double> mel_points(kNMels + 2);
    for (size_t i = 0; i < kNMels + 2; ++i) {
        mel_points[i] =
            ref_mel_to_hz(mel_min + (mel_max - mel_min) * static_cast<double>(i) / (kNMels + 1));
    }
    std::vector<double> fftfreq(kFreqBins);
    for (size_t k = 0; k < kFreqBins; ++k) {
        fftfreq[k] = static_cast<double>(k) * sr / static_cast<double>(kNFft);
    }

    double max_err = 0.0;
    double row_sum_total = 0.0;
    for (size_t m = 0; m < kNMels; ++m) {
        const double lo = mel_points[m];
        const double ctr = mel_points[m + 1];
        const double hi = mel_points[m + 2];
        const double enorm = 2.0 / (hi - lo);
        for (size_t k = 0; k < kFreqBins; ++k) {
            const double lower = (fftfreq[k] - lo) / (ctr - lo);
            const double upper = (hi - fftfreq[k]) / (hi - ctr);
            const double ref = std::max(0.0, std::min(lower, upper)) * enorm;
            const double got = static_cast<double>(fb[m * kFreqBins + k]);
            max_err = std::max(max_err, std::fabs(got - ref));
            row_sum_total += got;
        }
    }
    CHECK(max_err < 1e-5, "mel filterbank matches independent Slaney reference (max |err| < 1e-5)");
    CHECK(row_sum_total > 0.0, "mel filterbank is non-trivial (positive total weight)");

    // Frontend end-to-end: a 1 kHz tone must produce finite log-mel features
    // whose energy concentrates in the low/mid mel bands (not silence).
    std::vector<float> tone(kSampleRate);  // 1 s
    for (size_t n = 0; n < tone.size(); ++n) {
        tone[n] =
            0.5f * static_cast<float>(std::sin(2.0 * kPiD * 1000.0 * static_cast<double>(n) / sr));
    }
    std::vector<float> feats;
    size_t frames = 0;
    compute_log_mel_features(tone.data(), tone.size(), fb, build_fft_window(), FftTables(), &feats,
                             &frames);
    bool finite = frames > 0 && feats.size() == frames * kNMels;
    for (float v : feats) {
        if (!std::isfinite(v)) {
            finite = false;
            break;
        }
    }
    CHECK(finite, "log-mel frontend yields finite features for a 1 kHz tone");
    return max_err < 1e-5 && finite;
}

// -----------------------------------------------------------------------------
// (b3) Per-speaker median smoothing vs a naive windowed-median oracle.
// -----------------------------------------------------------------------------
float ref_median(std::vector<float> v) {
    std::sort(v.begin(), v.end());
    return v[v.size() / 2];
}

bool test_median() {
    const size_t frames = 15;
    std::vector<float> preds(frames * kNumSpeakers, 0.0f);
    // Deterministic pseudo-signal per speaker with isolated spikes.
    for (size_t t = 0; t < frames; ++t) {
        for (size_t s = 0; s < kNumSpeakers; ++s) {
            float base = static_cast<float>((t * 7 + s * 3) % 5) / 4.0f;
            if ((t + s) % 6 == 0) {
                base = 0.95f;  // spike the median should absorb near edges
            }
            preds[t * kNumSpeakers + s] = base;
        }
    }

    const std::vector<float> got = median_filter_preds(preds, frames);
    const size_t half = kMedianWindow / 2;
    bool ok = got.size() == preds.size();
    for (size_t s = 0; s < kNumSpeakers && ok; ++s) {
        for (size_t t = 0; t < frames; ++t) {
            const size_t start = t > half ? t - half : 0;
            const size_t end = std::min(t + half + 1, frames);
            std::vector<float> window;
            for (size_t i = start; i < end; ++i) {
                window.push_back(preds[i * kNumSpeakers + s]);
            }
            if (std::fabs(got[t * kNumSpeakers + s] - ref_median(window)) > 1e-6f) {
                ok = false;
                break;
            }
        }
    }
    CHECK(ok, "median smoothing matches an independent windowed-median oracle");
    return ok;
}

// -----------------------------------------------------------------------------
// (b4) Probability -> segment binarization vs an independent run-finder oracle.
// -----------------------------------------------------------------------------
struct SegTriple {
    int64_t start_ms;
    int64_t end_ms;
    int32_t speaker;
    bool operator==(const SegTriple& o) const {
        return start_ms == o.start_ms && end_ms == o.end_ms && speaker == o.speaker;
    }
};

std::vector<SegTriple> oracle_binarize(const std::vector<float>& preds, size_t frames,
                                       const rac_diarization_options_t& opt) {
    const float thr = opt.threshold > 0.0f ? opt.threshold : 0.5f;
    std::vector<SegTriple> all;
    for (size_t s = 0; s < kNumSpeakers; ++s) {
        // Independent contiguous-run finder (vs the provider's state machine).
        std::vector<SegTriple> per;
        size_t t = 0;
        while (t < frames) {
            if (preds[t * kNumSpeakers + s] >= thr) {
                size_t a = t;
                while (t < frames && preds[t * kNumSpeakers + s] >= thr) {
                    ++t;
                }
                const int64_t start = static_cast<int64_t>(a) * kFrameDurationMs;
                const int64_t end = static_cast<int64_t>(t) * kFrameDurationMs;
                if (end - start >= opt.minimum_duration_ms) {
                    per.push_back({start, end, static_cast<int32_t>(s)});
                }
            } else {
                ++t;
            }
        }
        if (per.size() > 1 && opt.merge_gap_ms > 0) {
            std::vector<SegTriple> merged{per[0]};
            for (size_t i = 1; i < per.size(); ++i) {
                if (per[i].start_ms - merged.back().end_ms < opt.merge_gap_ms) {
                    merged.back().end_ms = per[i].end_ms;
                } else {
                    merged.push_back(per[i]);
                }
            }
            per = std::move(merged);
        }
        all.insert(all.end(), per.begin(), per.end());
    }
    std::sort(all.begin(), all.end(),
              [](const SegTriple& x, const SegTriple& y) { return x.start_ms < y.start_ms; });
    return all;
}

bool compare_segments(const std::vector<Segment>& got, const std::vector<SegTriple>& ref) {
    if (got.size() != ref.size()) {
        return false;
    }
    for (size_t i = 0; i < got.size(); ++i) {
        const SegTriple g{got[i].start_ms, got[i].end_ms, got[i].speaker};
        if (!(g == ref[i])) {
            return false;
        }
    }
    return true;
}

bool test_binarize() {
    const size_t frames = 30;
    std::vector<float> preds(frames * kNumSpeakers, 0.0f);
    // Speaker 0: frames [2,5) active. Speaker 1: [10,11) active (1 frame),
    // then [13,18) active with a 1-frame gap at 15 -> two runs.
    for (size_t t = 2; t < 5; ++t)
        preds[t * kNumSpeakers + 0] = 0.9f;
    preds[10 * kNumSpeakers + 1] = 0.8f;
    for (size_t t = 13; t < 18; ++t)
        preds[t * kNumSpeakers + 1] = 0.7f;
    preds[15 * kNumSpeakers + 1] = 0.1f;  // dip -> split unless merged
    // Speaker 2: full-tail run [25, 30).
    for (size_t t = 25; t < frames; ++t)
        preds[t * kNumSpeakers + 2] = 0.99f;

    bool ok = true;

    // Plain threshold, no min-duration, no merge.
    {
        rac_diarization_options_t opt = RAC_DIARIZATION_OPTIONS_DEFAULT;
        const auto got = binarize_preds(preds, frames, opt);
        const auto ref = oracle_binarize(preds, frames, opt);
        ok &= compare_segments(got, ref);
        // Independent hand-computed spot-check on the first segment.
        ok &= !got.empty() && got.front().start_ms == 160 && got.front().end_ms == 400 &&
              got.front().speaker == 0;
    }
    CHECK(ok, "binarize (threshold only) matches oracle + hand-computed segment");

    // Minimum-duration filter drops the 1-frame speaker-1 blip at frame 10.
    {
        rac_diarization_options_t opt = RAC_DIARIZATION_OPTIONS_DEFAULT;
        opt.minimum_duration_ms = 120;  // > 80 ms single frame
        const auto got = binarize_preds(preds, frames, opt);
        const auto ref = oracle_binarize(preds, frames, opt);
        bool blip_gone = true;
        for (const auto& seg : got) {
            if (seg.speaker == 1 && seg.start_ms == 800) {
                blip_gone = false;  // 10*80 ms
            }
        }
        CHECK(compare_segments(got, ref) && blip_gone,
              "binarize honours minimum_duration_ms (drops sub-threshold blip)");
        ok &= compare_segments(got, ref) && blip_gone;
    }

    // Merge-gap stitches the speaker-1 dip at frame 15 into one segment. Gap of
    // 120 ms bridges the single 80 ms frame dip (runs [13,15)+[16,18)) but NOT
    // the 160 ms hole before the frame-10 blip, so the blip stays separate.
    {
        rac_diarization_options_t opt = RAC_DIARIZATION_OPTIONS_DEFAULT;
        opt.merge_gap_ms = 120;
        const auto got = binarize_preds(preds, frames, opt);
        const auto ref = oracle_binarize(preds, frames, opt);
        int stitched = 0;
        int64_t stitched_start = -1;
        int64_t stitched_end = -1;
        for (const auto& seg : got) {
            if (seg.speaker == 1 && seg.start_ms >= 13 * kFrameDurationMs) {
                ++stitched;
                stitched_start = seg.start_ms;
                stitched_end = seg.end_ms;
            }
        }
        const bool span_ok = stitched == 1 && stitched_start == 13 * kFrameDurationMs &&
                             stitched_end == 18 * kFrameDurationMs;
        CHECK(compare_segments(got, ref) && span_ok,
              "binarize honours merge_gap_ms (stitches split same-speaker runs)");
        ok &= compare_segments(got, ref) && span_ok;
    }
    return ok;
}

// -----------------------------------------------------------------------------
// (a) Service op-table wiring.
// -----------------------------------------------------------------------------
bool test_wiring() {
    const rac_diarization_service_ops_t& ops = g_onnx_diarization_ops;
    const bool all_set = ops.initialize && ops.diarize && ops.stream_create &&
                         ops.stream_feed_audio_chunk && ops.stream_destroy && ops.cleanup &&
                         ops.destroy && ops.create;
    CHECK(all_set, "g_onnx_diarization_ops exposes every service fn-pointer");
    return all_set;
}

// -----------------------------------------------------------------------------
// (c) Graceful failure — never crash on a null / missing model.
// -----------------------------------------------------------------------------
bool test_graceful_failure() {
    const rac_diarization_service_ops_t& ops = g_onnx_diarization_ops;
    bool ok = true;

    // Null-argument guards on the ABI boundary.
    void* bad = nullptr;
    ok &= ops.create(nullptr, nullptr, &bad) != RAC_SUCCESS;
    ok &= ops.create("m", nullptr, nullptr) != RAC_SUCCESS;
    ok &= ops.diarize(nullptr, nullptr, 0, nullptr, nullptr) != RAC_SUCCESS;
    CHECK(ok, "null-argument calls return an error, not a crash");

    // Real impl, but no model loaded / a missing model path.
    void* impl = nullptr;
    const rac_result_t create_rc = ops.create("diar-model", nullptr, &impl);
    CHECK(create_rc == RAC_SUCCESS && impl != nullptr, "create() allocates a provider impl");
    if (create_rc != RAC_SUCCESS || !impl) {
        return false;
    }

    CHECK(ops.initialize(impl, nullptr) == RAC_ERROR_NULL_POINTER,
          "initialize(null path) is rejected");

    const rac_result_t init_rc = ops.initialize(impl, "/nonexistent/sortformer/model");
    CHECK(init_rc != RAC_SUCCESS, "initialize(missing model) returns an error");

    // diarize before a successful initialize must fail cleanly and leave a
    // free-safe result.
    const std::vector<float> pcm(16000, 0.1f);
    rac_diarization_result_t result = {};
    const rac_result_t diar_rc =
        ops.diarize(impl, pcm.data(), pcm.size(), &RAC_DIARIZATION_OPTIONS_DEFAULT, &result);
    CHECK(diar_rc != RAC_SUCCESS, "diarize() before load returns an error (no session)");
    rac_diarization_result_free(&result);  // must be safe on the error result

    if (ops.cleanup) {
        (void)ops.cleanup(impl);
    }
    ops.destroy(impl);
    ok &= diar_rc != RAC_SUCCESS && init_rc != RAC_SUCCESS;
    return ok;
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_diarization_onnx (wiring + self-contained DSP math)\n");
    test_wiring();
    test_fft();
    test_mel_filterbank();
    test_median();
    test_binarize();
    test_graceful_failure();
    std::fprintf(stdout, "\n%d checks, %d failed\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
