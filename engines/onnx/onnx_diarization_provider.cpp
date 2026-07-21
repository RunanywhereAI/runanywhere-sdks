/**
 * @file onnx_diarization_provider.cpp
 * @brief Streaming NVIDIA Sortformer v2.1 speaker diarization on ONNX Runtime.
 *
 * Drives the stateful streaming graph
 *   nvidia/diar_streaming_sortformer_4spk-v2.1  (ONNX: cgus/..-onnx)
 * whose I/O contract (from the authoritative parakeet-rs export script
 * scripts/export_diar_sortformer.py) is:
 *
 *   inputs:
 *     chunk            f32 [1, time_chunk, 128]  128-mel FastConformer features
 *     chunk_lengths    i64 [1]                   number of mel frames in chunk
 *     spkcache         f32 [1, time_cache, 512]  speaker-cache pre-encoded embeds
 *     spkcache_lengths i64 [1]
 *     fifo             f32 [1, time_fifo, 512]   FIFO pre-encoded embeds
 *     fifo_lengths     i64 [1]
 *   outputs:
 *     spkcache_fifo_chunk_preds  f32 [1, S+F+chunk_frames, 4]  per-frame sigmoids
 *     chunk_pre_encode_embs      f32 [1, chunk_frames, 512]    embeds to append
 *     chunk_pre_encode_lengths   i64 [1]
 *
 * The graph is one streaming STEP; the FIFO + speaker-cache embedding state and
 * the mel frontend live in this driver. Offline diarize() and the persistent
 * stream share the same streaming loop (offline runs every chunk through a
 * transient state). Feature frontend + state machine + cache compression are a
 * faithful C++ port of parakeet-rs src/sortformer.rs / src/audio.rs.
 *
 * The 12.5 fps output frame rate = hop(160) * subsampling(8) / 16000 = 80 ms.
 */

#include "onnx_diarization_provider.h"

#include "rac_runtime_onnxrt.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <limits>
#include <mutex>
#include <new>
#include <set>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"

namespace runanywhere::diarization {
namespace {

using runanywhere::runtime::onnxrt::ElementType;
using runanywhere::runtime::onnxrt::Session;
using runanywhere::runtime::onnxrt::SessionOptions;
using runanywhere::runtime::onnxrt::TensorInput;
using runanywhere::runtime::onnxrt::TensorOutput;

constexpr const char* kLogCategory = "Diarization.ONNX";
// Mirrors the segmentation provider's NVIDIA-license acceptance gate. Sortformer
// ships under the NVIDIA Open Model License.
constexpr const char* kLicenseAcceptanceEnv = "RAC_ACCEPT_NVIDIA_SORTFORMER_LICENSE";
constexpr const char* kModelId = "diar_streaming_sortformer_4spk-v2.1-onnx";
constexpr const char* kModelFileName = "diar_streaming_sortformer_4spk-v2.1.onnx";

// ---- Mel frontend constants (NeMo FilterbankFeatures / parakeet-rs) ----------
constexpr size_t kNFft = 512;
constexpr size_t kWinLength = 400;
constexpr size_t kHopLength = 160;
constexpr size_t kNMels = 128;
constexpr float kPreemph = 0.97f;
constexpr float kLogZeroGuard = 5.9604645e-8f;  // 2^-24
constexpr size_t kSampleRate = 16000;
constexpr size_t kFreqBins = kNFft / 2 + 1;  // 257
constexpr double kPi = 3.14159265358979323846;

// ---- Streaming constants (ONNX export defaults; see export_diar_sortformer) --
// These govern the driver's chunking/state loop. The ONNX graph's time axes are
// dynamic, so these are driver constants, not graph shapes. TODO(full-generality):
// read chunk_len/fifo_len/spkcache_len/right_context from ONNX metadata_props
// (the onnxrt Session wrapper does not currently expose metadata).
constexpr size_t kChunkLen = 124;     // frames per chunk (~10 s at 80 ms)
constexpr size_t kFifoLen = 124;      // FIFO buffer length
constexpr size_t kSpkcacheLen = 188;  // speaker cache length
constexpr size_t kRightContext = 1;   // future frames for lookahead
constexpr size_t kSubsampling = 8;    // audio frames -> model frames
constexpr size_t kEmbDim = 512;       // FastConformer embedding dim
constexpr size_t kNumSpeakers = 4;    // model supports 4 speakers
// Output frame period = hop(160) * subsampling(8) / 16000 = 80 ms (12.5 fps).
constexpr int64_t kFrameDurationMs = 80;

// ---- Cache compression constants (from NeMo) --------------------------------
constexpr size_t kSpkcacheSilFramesPerSpk = 3;
constexpr float kPredScoreThreshold = 0.25f;
constexpr float kStrongBoostRate = 0.75f;
constexpr float kWeakBoostRate = 1.5f;
constexpr float kMinPosScoresRate = 0.5f;
constexpr float kSilThreshold = 0.2f;
constexpr size_t kMaxIndex = 99999;

// Median smoothing window applied to per-frame probabilities before
// binarization (parakeet-rs default). Must be odd.
constexpr size_t kMedianWindow = 11;

bool accepted_license() {
    const char* value = std::getenv(kLicenseAcceptanceEnv);
    return value && (std::strcmp(value, "1") == 0 || std::strcmp(value, "true") == 0 ||
                     std::strcmp(value, "TRUE") == 0 || std::strcmp(value, "yes") == 0 ||
                     std::strcmp(value, "YES") == 0);
}

char* duplicate_string(const std::string& value) {
    char* copy = static_cast<char*>(std::malloc(value.size() + 1));
    if (copy) {
        std::memcpy(copy, value.c_str(), value.size() + 1);
    }
    return copy;
}

// ---- Slaney mel scale (librosa) ---------------------------------------------
constexpr double kFSp = 200.0 / 3.0;
constexpr double kMinLogHz = 1000.0;
constexpr double kMinLogMel = kMinLogHz / kFSp;
constexpr double kLogStep = 0.06875177742094912;

double hz_to_mel_slaney(double hz) {
    return hz < kMinLogHz ? hz / kFSp : kMinLogMel + std::log(hz / kMinLogHz) / kLogStep;
}
double mel_to_hz_slaney(double mel) {
    return mel < kMinLogMel ? mel * kFSp : kMinLogHz * std::exp((mel - kMinLogMel) * kLogStep);
}

// Slaney-normalized mel filterbank, shape (kNMels, kFreqBins), row-major.
std::vector<float> build_mel_filterbank() {
    std::vector<float> fb(kNMels * kFreqBins, 0.0f);
    const double fmax = static_cast<double>(kSampleRate) / 2.0;
    const double mel_min = hz_to_mel_slaney(0.0);
    const double mel_max = hz_to_mel_slaney(fmax);

    std::vector<double> mel_points(kNMels + 2);
    for (size_t i = 0; i < kNMels + 2; ++i) {
        mel_points[i] = mel_to_hz_slaney(mel_min + (mel_max - mel_min) * static_cast<double>(i) /
                                                       static_cast<double>(kNMels + 1));
    }
    std::vector<double> fft_freqs(kFreqBins);
    for (size_t k = 0; k < kFreqBins; ++k) {
        fft_freqs[k] =
            static_cast<double>(k) * static_cast<double>(kSampleRate) / static_cast<double>(kNFft);
    }
    std::vector<double> fdiff(kNMels + 1);
    for (size_t i = 0; i < kNMels + 1; ++i) {
        fdiff[i] = mel_points[i + 1] - mel_points[i];
    }
    for (size_t i = 0; i < kNMels; ++i) {
        for (size_t k = 0; k < kFreqBins; ++k) {
            const double lower = (fft_freqs[k] - mel_points[i]) / fdiff[i];
            const double upper = (mel_points[i + 2] - fft_freqs[k]) / fdiff[i + 1];
            fb[i * kFreqBins + k] = static_cast<float>(std::max(0.0, std::min(lower, upper)));
        }
        const double enorm = 2.0 / (mel_points[i + 2] - mel_points[i]);
        for (size_t k = 0; k < kFreqBins; ++k) {
            fb[i * kFreqBins + k] *= static_cast<float>(enorm);
        }
    }
    return fb;
}

// Periodic (fftbins) Hann window of length kWinLength, centered in a kNFft frame.
std::vector<float> build_fft_window() {
    std::vector<float> window(kNFft, 0.0f);
    const size_t offset = (kNFft - kWinLength) / 2;
    for (size_t i = 0; i < kWinLength; ++i) {
        window[offset + i] =
            0.5f - 0.5f * std::cos(2.0f * static_cast<float>(kPi) * static_cast<float>(i) /
                                   static_cast<float>(kWinLength));
    }
    return window;
}

// Iterative radix-2 Cooley-Tukey FFT tables for kNFft (a power of two).
struct FftTables {
    std::vector<uint32_t> bitrev;
    std::vector<float> cos_t;  // cos(2*pi*m/N), m in [0, N/2)
    std::vector<float> sin_t;  // sin(2*pi*m/N)

    FftTables() {
        bitrev.resize(kNFft);
        uint32_t bits = 0;
        while ((1u << bits) < kNFft) {
            ++bits;
        }
        for (uint32_t i = 0; i < kNFft; ++i) {
            uint32_t r = 0;
            for (uint32_t b = 0; b < bits; ++b) {
                r |= ((i >> b) & 1u) << (bits - 1 - b);
            }
            bitrev[i] = r;
        }
        cos_t.resize(kNFft / 2);
        sin_t.resize(kNFft / 2);
        for (size_t m = 0; m < kNFft / 2; ++m) {
            const double a = 2.0 * kPi * static_cast<double>(m) / static_cast<double>(kNFft);
            cos_t[m] = static_cast<float>(std::cos(a));
            sin_t[m] = static_cast<float>(std::sin(a));
        }
    }

    // In-place forward FFT of real-imag buffers of length kNFft.
    void forward(std::vector<float>& re, std::vector<float>& im) const {
        for (uint32_t i = 0; i < kNFft; ++i) {
            const uint32_t j = bitrev[i];
            if (j > i) {
                std::swap(re[i], re[j]);
                std::swap(im[i], im[j]);
            }
        }
        for (size_t len = 2; len <= kNFft; len <<= 1) {
            const size_t half = len / 2;
            const size_t step = kNFft / len;
            for (size_t base = 0; base < kNFft; base += len) {
                for (size_t k = 0; k < half; ++k) {
                    const size_t tw = k * step;
                    const float wr = cos_t[tw];
                    const float wi = -sin_t[tw];  // W = cos - i*sin (forward transform)
                    const size_t a = base + k;
                    const size_t b = base + k + half;
                    const float xr = re[b] * wr - im[b] * wi;
                    const float xi = re[b] * wi + im[b] * wr;
                    re[b] = re[a] - xr;
                    im[b] = im[a] - xi;
                    re[a] += xr;
                    im[a] += xi;
                }
            }
        }
    }
};

// ---- Streaming state (the parts the ONNX graph does NOT own) ----------------
struct StreamState {
    std::vector<float> spkcache;  // spkcache_frames * kEmbDim
    size_t spkcache_frames = 0;
    bool has_spkcache_preds = false;
    std::vector<float> spkcache_preds;  // spkcache_frames * kNumSpeakers
    std::vector<float> fifo;            // fifo_frames * kEmbDim
    size_t fifo_frames = 0;
    std::vector<float> fifo_preds;    // fifo_frames * kNumSpeakers
    std::vector<float> mean_sil_emb;  // kEmbDim
    size_t n_sil_frames = 0;

    StreamState() : mean_sil_emb(kEmbDim, 0.0f) {}
};

struct Segment {
    int64_t start_ms;
    int64_t end_ms;
    int32_t speaker;
};

// ---- Pure DSP/postprocessing helpers (no provider state) --------------------
// These are stateless functions of their inputs + file-scope constants. They
// live at namespace scope (not as private Impl methods) so the offline path,
// the streaming path, AND the unit tests can all exercise the exact same math
// against an independent scalar oracle (see tests/test_diarization_onnx.cpp).

// 128-mel log-filterbank frontend: preemphasis -> center-pad -> Hann-windowed
// radix-2 FFT -> power spectrum -> Slaney mel matmul -> log. Output is
// (num_frames * kNMels) row-major.
void compute_log_mel_features(const float* audio, size_t n, const std::vector<float>& mel_basis,
                              const std::vector<float>& fft_window, const FftTables& fft,
                              std::vector<float>* out, size_t* out_frames) {
    out->clear();
    *out_frames = 0;
    if (n == 0) {
        return;
    }
    // 1. Preemphasis y[0]=x[0]; y[i]=x[i]-0.97*x[i-1].
    std::vector<float> pre(n);
    pre[0] = audio[0];
    for (size_t i = 1; i < n; ++i) {
        pre[i] = audio[i] - kPreemph * audio[i - 1];
    }
    // 2. Center pad by kNFft/2 on each side (librosa/torch center=True).
    const size_t pad = kNFft / 2;
    std::vector<float> padded(n + kNFft, 0.0f);
    std::memcpy(padded.data() + pad, pre.data(), n * sizeof(float));

    const size_t num_frames = n / kHopLength + 1;
    out->assign(num_frames * kNMels, 0.0f);

    std::vector<float> re(kNFft);
    std::vector<float> im(kNFft);
    std::vector<float> power(kFreqBins);
    for (size_t f = 0; f < num_frames; ++f) {
        const size_t start = f * kHopLength;
        for (size_t i = 0; i < kNFft; ++i) {
            const size_t idx = start + i;
            re[i] = idx < padded.size() ? padded[idx] * fft_window[i] : 0.0f;
            im[i] = 0.0f;
        }
        fft.forward(re, im);
        for (size_t k = 0; k < kFreqBins; ++k) {
            power[k] = re[k] * re[k] + im[k] * im[k];  // NeMo mag_power=2.0
        }
        for (size_t m = 0; m < kNMels; ++m) {
            const float* row = mel_basis.data() + m * kFreqBins;
            float acc = 0.0f;
            for (size_t k = 0; k < kFreqBins; ++k) {
                acc += row[k] * power[k];
            }
            (*out)[f * kNMels + m] = std::log(acc + kLogZeroGuard);  // normalize='NA'
        }
    }
    *out_frames = num_frames;
}

// Per-speaker sliding median smoothing over the (frames * kNumSpeakers)
// probability grid. Window kMedianWindow (odd), edges clamped.
std::vector<float> median_filter_preds(const std::vector<float>& preds, size_t frames) {
    if (kMedianWindow <= 1 || frames == 0) {
        return preds;
    }
    std::vector<float> out(preds);
    const size_t half = kMedianWindow / 2;
    std::vector<float> window;
    for (size_t s = 0; s < kNumSpeakers; ++s) {
        for (size_t t = 0; t < frames; ++t) {
            const size_t start = t > half ? t - half : 0;
            const size_t end = std::min(t + half + 1, frames);
            window.clear();
            for (size_t i = start; i < end; ++i) {
                window.push_back(preds[i * kNumSpeakers + s]);
            }
            std::sort(window.begin(), window.end());
            out[t * kNumSpeakers + s] = window[window.size() / 2];
        }
    }
    return out;
}

// Threshold + minimum-duration + same-speaker merge -> sorted segments.
std::vector<Segment> binarize_preds(const std::vector<float>& preds, size_t frames,
                                    const rac_diarization_options_t& options) {
    // The C ABI carries a single threshold; use it for both onset and offset
    // (simple threshold hysteresis). minimum_duration_ms filters short blips,
    // merge_gap_ms merges close same-speaker segments.
    const float threshold = options.threshold > 0.0f ? options.threshold : 0.5f;
    const int64_t min_on_ms = options.minimum_duration_ms;
    const int64_t merge_gap_ms = options.merge_gap_ms;

    std::vector<Segment> segments;
    for (size_t s = 0; s < kNumSpeakers; ++s) {
        std::vector<Segment> per_spk;
        bool in_seg = false;
        size_t seg_start = 0;
        for (size_t t = 0; t < frames; ++t) {
            const float p = preds[t * kNumSpeakers + s];
            if (p >= threshold && !in_seg) {
                in_seg = true;
                seg_start = t;
            } else if (p < threshold && in_seg) {
                in_seg = false;
                const int64_t start_ms = static_cast<int64_t>(seg_start) * kFrameDurationMs;
                const int64_t end_ms = static_cast<int64_t>(t) * kFrameDurationMs;
                if (end_ms - start_ms >= min_on_ms) {
                    per_spk.push_back({start_ms, end_ms, static_cast<int32_t>(s)});
                }
            }
        }
        if (in_seg) {
            const int64_t start_ms = static_cast<int64_t>(seg_start) * kFrameDurationMs;
            const int64_t end_ms = static_cast<int64_t>(frames) * kFrameDurationMs;
            if (end_ms - start_ms >= min_on_ms) {
                per_spk.push_back({start_ms, end_ms, static_cast<int32_t>(s)});
            }
        }
        // Merge same-speaker segments closer than merge_gap_ms.
        if (per_spk.size() > 1 && merge_gap_ms > 0) {
            std::vector<Segment> merged{per_spk[0]};
            for (size_t i = 1; i < per_spk.size(); ++i) {
                const int64_t gap = per_spk[i].start_ms - merged.back().end_ms;
                if (gap < merge_gap_ms) {
                    merged.back().end_ms = per_spk[i].end_ms;
                } else {
                    merged.push_back(per_spk[i]);
                }
            }
            per_spk = std::move(merged);
        }
        segments.insert(segments.end(), per_spk.begin(), per_spk.end());
    }
    std::sort(segments.begin(), segments.end(),
              [](const Segment& a, const Segment& b) { return a.start_ms < b.start_ms; });
    return segments;
}

}  // namespace

// A persistent streaming session handle (returned to Commons as rac_handle_t).
struct DiarizationStream {
    StreamState state;
    std::vector<float> all_preds;  // accumulated (total_frames * kNumSpeakers)
    size_t total_frames = 0;
    std::vector<float> audio_buffer;
    rac_diarization_options_t options{};
    int64_t processing_time_ms = 0;
    size_t total_samples = 0;
};

class ONNXDiarizationProvider::Impl {
   public:
    Impl() : mel_basis_(build_mel_filterbank()), fft_window_(build_fft_window()) {}

    ~Impl() { destroy_all_streams(); }

    rac_result_t initialize(const std::string& model_path);
    rac_result_t diarize(const float* samples, size_t sample_count,
                         const rac_diarization_options_t& options,
                         rac_diarization_result_t* out_result);
    rac_result_t stream_create(const rac_diarization_options_t& options,
                               rac_handle_t* out_stream_handle);
    rac_result_t stream_feed_audio_chunk(rac_handle_t stream_handle, const float* samples,
                                         size_t sample_count,
                                         rac_diarization_stream_callback_t callback,
                                         void* user_data);
    rac_result_t stream_destroy(rac_handle_t stream_handle);
    void cleanup();
    bool is_ready() const;

   private:
    // --- DSP ---
    void extract_mel_features(const float* audio, size_t n, std::vector<float>* out,
                              size_t* out_frames) const;

    // --- One streaming step: run the ONNX graph + update FIFO/spkcache state.
    // chunk_feat is (current_len * kNMels) row-major; returns kept chunk
    // predictions (keep * kNumSpeakers) appended into *out_chunk_preds.
    rac_result_t streaming_update(StreamState* state, const std::vector<float>& chunk_feat,
                                  size_t current_len, std::vector<float>* out_chunk_preds,
                                  size_t* out_keep_frames);

    rac_result_t run_onnx(StreamState* state, const std::vector<float>& chunk_feat,
                          size_t current_len, std::vector<float>* preds, size_t* preds_frames,
                          std::vector<float>* embs, size_t* embs_frames);

    void update_silence_profile(StreamState* state, const std::vector<float>& embs,
                                const std::vector<float>& preds, size_t frames) const;
    void compress_spkcache(StreamState* state) const;

    void destroy_all_streams();

    std::unique_ptr<Session> session_;
    std::vector<float> mel_basis_;   // kNMels * kFreqBins
    std::vector<float> fft_window_;  // kNFft
    FftTables fft_;
    std::set<DiarizationStream*> streams_;
    mutable std::mutex mutex_;  // guards session_ (ORT run) + streams_
};

// ---------------------------------------------------------------------------
// Initialization
// ---------------------------------------------------------------------------
rac_result_t ONNXDiarizationProvider::Impl::initialize(const std::string& model_path) {
    try {
        if (!accepted_license()) {
            RAC_LOG_WARNING(kLogCategory,
                            "Sortformer load requires %s=1 after reviewing the NVIDIA Open Model "
                            "License",
                            kLicenseAcceptanceEnv);
            return RAC_ERROR_PERMISSION_DENIED;
        }
        std::filesystem::path supplied(model_path);
        std::filesystem::path onnx_path;
        std::error_code ec;
        if (std::filesystem::is_directory(supplied, ec)) {
            const auto pinned = supplied / kModelFileName;
            if (std::filesystem::is_regular_file(pinned, ec)) {
                onnx_path = pinned;
            } else {
                // Fall back to the single .onnx file in the directory.
                for (const auto& entry : std::filesystem::directory_iterator(supplied, ec)) {
                    if (entry.is_regular_file(ec) && entry.path().extension() == ".onnx") {
                        onnx_path = entry.path();
                        break;
                    }
                }
            }
        } else if (std::filesystem::is_regular_file(supplied, ec)) {
            onnx_path = supplied;
        }
        if (onnx_path.empty() || !std::filesystem::is_regular_file(onnx_path, ec)) {
            RAC_LOG_ERROR(kLogCategory, "no Sortformer .onnx model found at %s",
                          model_path.c_str());
            return RAC_ERROR_MODEL_VALIDATION_FAILED;
        }

        SessionOptions options;
        options.log_id = "RunAnywhereSortformer";
        std::string error;
        auto session = Session::create(onnx_path.string(), options, &error);
        if (!session) {
            RAC_LOG_ERROR(kLogCategory, "Sortformer ORT session creation failed: %s",
                          error.c_str());
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }

        std::lock_guard<std::mutex> lock(mutex_);
        session_ = std::move(session);
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (const std::exception& exception) {
        RAC_LOG_ERROR(kLogCategory, "Sortformer initialize failed: %s", exception.what());
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    } catch (...) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
}

// ---------------------------------------------------------------------------
// Mel frontend
// ---------------------------------------------------------------------------
void ONNXDiarizationProvider::Impl::extract_mel_features(const float* audio, size_t n,
                                                         std::vector<float>* out,
                                                         size_t* out_frames) const {
    compute_log_mel_features(audio, n, mel_basis_, fft_window_, fft_, out, out_frames);
}

// ---------------------------------------------------------------------------
// ONNX graph invocation
// ---------------------------------------------------------------------------
rac_result_t ONNXDiarizationProvider::Impl::run_onnx(StreamState* state,
                                                     const std::vector<float>& chunk_feat,
                                                     size_t current_len, std::vector<float>* preds,
                                                     size_t* preds_frames, std::vector<float>* embs,
                                                     size_t* embs_frames) {
    const size_t s = state->spkcache_frames;
    const size_t fF = state->fifo_frames;
    static const float kZero = 0.0f;

    const int64_t chunk_shape[] = {1, static_cast<int64_t>(current_len),
                                   static_cast<int64_t>(kNMels)};
    const int64_t spkcache_shape[] = {1, static_cast<int64_t>(s), static_cast<int64_t>(kEmbDim)};
    const int64_t fifo_shape[] = {1, static_cast<int64_t>(fF), static_cast<int64_t>(kEmbDim)};
    const int64_t scalar_shape[] = {1};
    const int64_t chunk_len_v = static_cast<int64_t>(current_len);
    const int64_t spkcache_len_v = static_cast<int64_t>(s);
    const int64_t fifo_len_v = static_cast<int64_t>(fF);

    const TensorInput inputs[] = {
        {.name = "chunk",
         .data = chunk_feat.data(),
         .data_bytes = chunk_feat.size() * sizeof(float),
         .shape = chunk_shape,
         .rank = 3,
         .type = ElementType::Float32},
        {.name = "chunk_lengths",
         .data = &chunk_len_v,
         .data_bytes = sizeof(int64_t),
         .shape = scalar_shape,
         .rank = 1,
         .type = ElementType::Int64},
        {.name = "spkcache",
         .data = s > 0 ? state->spkcache.data() : &kZero,
         .data_bytes = state->spkcache.size() * sizeof(float),
         .shape = spkcache_shape,
         .rank = 3,
         .type = ElementType::Float32},
        {.name = "spkcache_lengths",
         .data = &spkcache_len_v,
         .data_bytes = sizeof(int64_t),
         .shape = scalar_shape,
         .rank = 1,
         .type = ElementType::Int64},
        {.name = "fifo",
         .data = fF > 0 ? state->fifo.data() : &kZero,
         .data_bytes = state->fifo.size() * sizeof(float),
         .shape = fifo_shape,
         .rank = 3,
         .type = ElementType::Float32},
        {.name = "fifo_lengths",
         .data = &fifo_len_v,
         .data_bytes = sizeof(int64_t),
         .shape = scalar_shape,
         .rank = 1,
         .type = ElementType::Int64},
    };
    const char* output_names[] = {"spkcache_fifo_chunk_preds", "chunk_pre_encode_embs",
                                  "chunk_pre_encode_lengths"};
    std::vector<TensorOutput> outputs;
    std::string error;
    rac_result_t rc = session_->run(inputs, 6, output_names, 3, outputs, &error);
    if (rc != RAC_SUCCESS) {
        RAC_LOG_ERROR(kLogCategory, "Sortformer inference failed: %s", error.c_str());
        return rc;
    }
    if (outputs.size() < 2 || outputs[0].dtype != ElementType::Float32 ||
        outputs[1].dtype != ElementType::Float32 || outputs[0].shape.size() != 3 ||
        outputs[1].shape.size() != 3 || outputs[0].shape[2] != static_cast<int64_t>(kNumSpeakers) ||
        outputs[1].shape[2] != static_cast<int64_t>(kEmbDim)) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
    *preds_frames = static_cast<size_t>(outputs[0].shape[1]);
    *embs_frames = static_cast<size_t>(outputs[1].shape[1]);
    preds->assign(*preds_frames * kNumSpeakers, 0.0f);
    std::memcpy(preds->data(), outputs[0].bytes.data(),
                std::min(outputs[0].bytes.size(), preds->size() * sizeof(float)));
    embs->assign(*embs_frames * kEmbDim, 0.0f);
    std::memcpy(embs->data(), outputs[1].bytes.data(),
                std::min(outputs[1].bytes.size(), embs->size() * sizeof(float)));
    return RAC_SUCCESS;
}

// ---------------------------------------------------------------------------
// Streaming step (port of parakeet-rs streaming_update)
// ---------------------------------------------------------------------------
rac_result_t ONNXDiarizationProvider::Impl::streaming_update(StreamState* state,
                                                             const std::vector<float>& chunk_feat,
                                                             size_t current_len,
                                                             std::vector<float>* out_chunk_preds,
                                                             size_t* out_keep_frames) {
    const size_t s0 = state->spkcache_frames;
    const size_t f0 = state->fifo_frames;

    std::vector<float> preds;
    std::vector<float> embs;
    size_t preds_frames = 0;
    size_t embs_frames = 0;
    rac_result_t rc =
        run_onnx(state, chunk_feat, current_len, &preds, &preds_frames, &embs, &embs_frames);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    // Keep only chunk_len chunk frames; right_context lookahead is discarded.
    const size_t valid_frames = (current_len + kSubsampling - 1) / kSubsampling;  // ceil
    size_t keep = std::min(kChunkLen, valid_frames);
    keep = std::min(keep, embs_frames);
    if (preds_frames < s0 + f0) {
        return RAC_ERROR_MODEL_VALIDATION_FAILED;
    }
    keep = std::min(keep, preds_frames - s0 - f0);
    *out_keep_frames = keep;

    // chunk predictions: preds[s0+f0 .. s0+f0+keep]
    const size_t chunk_off = (s0 + f0) * kNumSpeakers;
    out_chunk_preds->assign(preds.begin() + chunk_off,
                            preds.begin() + chunk_off + keep * kNumSpeakers);
    // chunk embeddings: embs[0 .. keep]
    std::vector<float> chunk_embs(embs.begin(), embs.begin() + keep * kEmbDim);

    // fifo predictions slice: preds[s0 .. s0+f0]
    std::vector<float> fifo_preds_slice;
    if (f0 > 0) {
        fifo_preds_slice.assign(preds.begin() + s0 * kNumSpeakers,
                                preds.begin() + (s0 + f0) * kNumSpeakers);
    }

    // Append chunk embeddings to FIFO.
    state->fifo.insert(state->fifo.end(), chunk_embs.begin(), chunk_embs.end());
    state->fifo_frames = f0 + keep;
    // Update FIFO predictions = concat(fifo_preds_slice, chunk_preds).
    state->fifo_preds.assign(fifo_preds_slice.begin(), fifo_preds_slice.end());
    state->fifo_preds.insert(state->fifo_preds.end(), out_chunk_preds->begin(),
                             out_chunk_preds->end());

    const size_t fifo_after = state->fifo_frames;
    if (fifo_after > kFifoLen) {
        size_t pop_out_len = kChunkLen;
        const size_t extra = keep > kFifoLen ? keep - kFifoLen : 0;
        pop_out_len = std::max(pop_out_len, extra + f0);
        pop_out_len = std::min(pop_out_len, fifo_after);

        std::vector<float> pop_embs(state->fifo.begin(),
                                    state->fifo.begin() + pop_out_len * kEmbDim);
        std::vector<float> pop_preds(state->fifo_preds.begin(),
                                     state->fifo_preds.begin() + pop_out_len * kNumSpeakers);

        update_silence_profile(state, pop_embs, pop_preds, pop_out_len);

        // Remove popped frames from FIFO.
        state->fifo.erase(state->fifo.begin(), state->fifo.begin() + pop_out_len * kEmbDim);
        state->fifo_preds.erase(state->fifo_preds.begin(),
                                state->fifo_preds.begin() + pop_out_len * kNumSpeakers);
        state->fifo_frames = fifo_after - pop_out_len;

        // Append popped frames to the speaker cache.
        state->spkcache.insert(state->spkcache.end(), pop_embs.begin(), pop_embs.end());
        state->spkcache_frames = s0 + pop_out_len;
        if (state->has_spkcache_preds) {
            state->spkcache_preds.insert(state->spkcache_preds.end(), pop_preds.begin(),
                                         pop_preds.end());
        }

        if (state->spkcache_frames > kSpkcacheLen) {
            if (!state->has_spkcache_preds) {
                // Initialize cache preds from this step's spkcache-region output.
                state->spkcache_preds.assign(preds.begin(), preds.begin() + s0 * kNumSpeakers);
                state->spkcache_preds.insert(state->spkcache_preds.end(), pop_preds.begin(),
                                             pop_preds.end());
                state->has_spkcache_preds = true;
            }
            compress_spkcache(state);
        }
    }
    return RAC_SUCCESS;
}

void ONNXDiarizationProvider::Impl::update_silence_profile(StreamState* state,
                                                           const std::vector<float>& embs,
                                                           const std::vector<float>& preds,
                                                           size_t frames) const {
    for (size_t t = 0; t < frames; ++t) {
        float sum = 0.0f;
        for (size_t s = 0; s < kNumSpeakers; ++s) {
            sum += preds[t * kNumSpeakers + s];
        }
        if (sum < kSilThreshold) {
            const float n_old = static_cast<float>(state->n_sil_frames);
            state->n_sil_frames += 1;
            const float n_new = static_cast<float>(state->n_sil_frames);
            const float* emb = embs.data() + t * kEmbDim;
            for (size_t i = 0; i < kEmbDim; ++i) {
                state->mean_sil_emb[i] = (state->mean_sil_emb[i] * n_old + emb[i]) / n_new;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Smart cache compression (port of parakeet-rs compress_spkcache)
// ---------------------------------------------------------------------------
void ONNXDiarizationProvider::Impl::compress_spkcache(StreamState* state) const {
    if (!state->has_spkcache_preds) {
        return;
    }
    const size_t n_frames = state->spkcache_frames;
    const size_t per_spk = kSpkcacheLen / kNumSpeakers;
    if (per_spk <= kSpkcacheSilFramesPerSpk) {
        // Cache too small to compress: truncate to spkcache_len.
        state->spkcache.resize(kSpkcacheLen * kEmbDim);
        state->spkcache_preds.resize(kSpkcacheLen * kNumSpeakers);
        state->spkcache_frames = kSpkcacheLen;
        return;
    }
    const size_t len_per_spk = per_spk - kSpkcacheSilFramesPerSpk;
    const size_t strong = static_cast<size_t>(static_cast<float>(len_per_spk) * kStrongBoostRate);
    const size_t weak = static_cast<size_t>(static_cast<float>(len_per_spk) * kWeakBoostRate);
    const size_t min_pos = static_cast<size_t>(static_cast<float>(len_per_spk) * kMinPosScoresRate);

    const std::vector<float>& cp = state->spkcache_preds;  // (n_frames, kNumSpeakers)
    const float neg_inf = -std::numeric_limits<float>::infinity();
    const float pos_inf = std::numeric_limits<float>::infinity();
    const float ln_half = std::log(0.5f);

    // get_log_pred_scores
    std::vector<float> scores(n_frames * kNumSpeakers, 0.0f);
    for (size_t t = 0; t < n_frames; ++t) {
        float log_1_sum = 0.0f;
        for (size_t s = 0; s < kNumSpeakers; ++s) {
            const float p = std::max(cp[t * kNumSpeakers + s], kPredScoreThreshold);
            log_1_sum += std::log(std::max(1.0f - p, kPredScoreThreshold));
        }
        for (size_t s = 0; s < kNumSpeakers; ++s) {
            const float p = std::max(cp[t * kNumSpeakers + s], kPredScoreThreshold);
            const float log_p = std::log(p);
            const float log_1_p = std::log(std::max(1.0f - p, kPredScoreThreshold));
            scores[t * kNumSpeakers + s] = log_p - log_1_p + log_1_sum - ln_half;
        }
    }

    // disable_low_scores
    std::array<size_t, kNumSpeakers> pos_count{};
    for (size_t t = 0; t < n_frames; ++t) {
        for (size_t s = 0; s < kNumSpeakers; ++s) {
            if (scores[t * kNumSpeakers + s] > 0.0f) {
                ++pos_count[s];
            }
        }
    }
    for (size_t t = 0; t < n_frames; ++t) {
        for (size_t s = 0; s < kNumSpeakers; ++s) {
            const bool is_speech = cp[t * kNumSpeakers + s] > 0.5f;
            if (!is_speech) {
                scores[t * kNumSpeakers + s] = neg_inf;
            } else if (scores[t * kNumSpeakers + s] <= 0.0f && pos_count[s] >= min_pos) {
                scores[t * kNumSpeakers + s] = neg_inf;
            }
        }
    }

    // boost_topk_scores (strong scale 2.0, then weak scale 1.0)
    auto boost = [&](size_t n_boost, float scale) {
        if (n_boost == 0) {
            return;
        }
        for (size_t s = 0; s < kNumSpeakers; ++s) {
            std::vector<std::pair<float, size_t>> col(n_frames);
            for (size_t t = 0; t < n_frames; ++t) {
                col[t] = {scores[t * kNumSpeakers + s], t};
            }
            std::sort(col.begin(), col.end(),
                      [](const auto& a, const auto& b) { return a.first > b.first; });
            const size_t k = std::min(n_boost, n_frames);
            for (size_t i = 0; i < k; ++i) {
                const size_t t = col[i].second;
                if (scores[t * kNumSpeakers + s] != neg_inf) {
                    scores[t * kNumSpeakers + s] -= scale * ln_half;
                }
            }
        }
    };
    boost(strong, 2.0f);
    boost(weak, 1.0f);

    // Append kSpkcacheSilFramesPerSpk silence rows with +inf scores.
    const size_t padded_frames = n_frames + kSpkcacheSilFramesPerSpk;
    scores.resize(padded_frames * kNumSpeakers, pos_inf);
    // (resize fills the appended silence rows with +inf via the fill value.)

    // get_topk_indices: flatten (speaker-major), take top kSpkcacheLen.
    std::vector<std::pair<float, size_t>> flat;
    flat.reserve(padded_frames * kNumSpeakers);
    for (size_t s = 0; s < kNumSpeakers; ++s) {
        for (size_t t = 0; t < padded_frames; ++t) {
            flat.push_back({scores[t * kNumSpeakers + s], s * padded_frames + t});
        }
    }
    std::sort(flat.begin(), flat.end(),
              [](const auto& a, const auto& b) { return a.first > b.first; });
    std::vector<size_t> topk_flat;
    topk_flat.reserve(kSpkcacheLen);
    for (size_t i = 0; i < kSpkcacheLen && i < flat.size(); ++i) {
        topk_flat.push_back(flat[i].first == neg_inf ? kMaxIndex : flat[i].second);
    }
    std::sort(topk_flat.begin(), topk_flat.end());

    std::vector<size_t> frame_indices(kSpkcacheLen, 0);
    std::vector<char> is_disabled(kSpkcacheLen, 0);
    for (size_t i = 0; i < topk_flat.size(); ++i) {
        const size_t flat_idx = topk_flat[i];
        if (flat_idx == kMaxIndex) {
            is_disabled[i] = 1;
            continue;
        }
        const size_t frame_idx = flat_idx % padded_frames;
        if (frame_idx >= n_frames) {  // n_frames_no_sil == original spkcache frames
            is_disabled[i] = 1;
        } else {
            frame_indices[i] = frame_idx;
        }
    }

    // gather_spkcache
    std::vector<float> new_embs(kSpkcacheLen * kEmbDim, 0.0f);
    std::vector<float> new_preds(kSpkcacheLen * kNumSpeakers, 0.0f);
    for (size_t i = 0; i < kSpkcacheLen; ++i) {
        if (is_disabled[i]) {
            std::memcpy(new_embs.data() + i * kEmbDim, state->mean_sil_emb.data(),
                        kEmbDim * sizeof(float));
        } else {
            const size_t idx = frame_indices[i];
            if (idx < state->spkcache_frames) {
                std::memcpy(new_embs.data() + i * kEmbDim, state->spkcache.data() + idx * kEmbDim,
                            kEmbDim * sizeof(float));
                std::memcpy(new_preds.data() + i * kNumSpeakers, cp.data() + idx * kNumSpeakers,
                            kNumSpeakers * sizeof(float));
            }
        }
    }
    state->spkcache = std::move(new_embs);
    state->spkcache_preds = std::move(new_preds);
    state->spkcache_frames = kSpkcacheLen;
}

// ---------------------------------------------------------------------------
// Result assembly
// ---------------------------------------------------------------------------
namespace {

rac_result_t build_result(const std::vector<Segment>& segments, int64_t audio_duration_ms,
                          int64_t processing_time_ms, rac_diarization_result_t* out) {
    *out = {};
    out->audio_duration_ms = audio_duration_ms;
    out->processing_time_ms = processing_time_ms;
    out->model_id = duplicate_string(kModelId);
    if (!out->model_id) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    std::array<bool, kNumSpeakers> present{};
    for (const auto& seg : segments) {
        if (seg.speaker >= 0 && static_cast<size_t>(seg.speaker) < kNumSpeakers) {
            present[static_cast<size_t>(seg.speaker)] = true;
        }
    }
    int32_t speaker_count = 0;
    for (bool p : present) {
        speaker_count += p ? 1 : 0;
    }
    out->speaker_count = speaker_count;

    out->segment_count = segments.size();
    if (!segments.empty()) {
        out->segments = static_cast<rac_diarization_segment_t*>(
            std::calloc(segments.size(), sizeof(rac_diarization_segment_t)));
        if (!out->segments) {
            rac_diarization_result_free(out);
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        for (size_t i = 0; i < segments.size(); ++i) {
            out->segments[i].start_ms = segments[i].start_ms;
            out->segments[i].end_ms = segments[i].end_ms;
            out->segments[i].speaker_index = segments[i].speaker;
            out->segments[i].speaker_id =
                duplicate_string("speaker_" + std::to_string(segments[i].speaker));
            if (!out->segments[i].speaker_id) {
                rac_diarization_result_free(out);
                return RAC_ERROR_OUT_OF_MEMORY;
            }
        }
    }
    return RAC_SUCCESS;
}

}  // namespace

// ---------------------------------------------------------------------------
// Offline diarization
// ---------------------------------------------------------------------------
rac_result_t ONNXDiarizationProvider::Impl::diarize(const float* samples, size_t sample_count,
                                                    const rac_diarization_options_t& options,
                                                    rac_diarization_result_t* out_result) {
    if (!out_result || !samples || sample_count == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *out_result = {};

    std::lock_guard<std::mutex> lock(mutex_);
    if (!session_) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }
    const auto started = std::chrono::steady_clock::now();
    try {
        std::vector<float> features;
        size_t total_frames = 0;
        extract_mel_features(samples, sample_count, &features, &total_frames);
        if (total_frames == 0) {
            return build_result({}, 0, 0, out_result);
        }

        StreamState state;
        std::vector<float> all_preds;
        size_t all_frames = 0;
        const size_t chunk_stride = kChunkLen * kSubsampling;
        const size_t feed_size = (kChunkLen + kRightContext) * kSubsampling;
        const size_t num_chunks = (total_frames + chunk_stride - 1) / chunk_stride;

        for (size_t ci = 0; ci < num_chunks; ++ci) {
            const size_t start = ci * chunk_stride;
            const size_t end = std::min(start + feed_size, total_frames);
            const size_t current_len = end - start;

            std::vector<float> chunk_feat(feed_size * kNMels, 0.0f);
            std::memcpy(chunk_feat.data(), features.data() + start * kNMels,
                        current_len * kNMels * sizeof(float));

            std::vector<float> chunk_preds;
            size_t keep = 0;
            rac_result_t rc =
                streaming_update(&state, chunk_feat, current_len, &chunk_preds, &keep);
            if (rc != RAC_SUCCESS) {
                return rc;
            }
            all_preds.insert(all_preds.end(), chunk_preds.begin(), chunk_preds.end());
            all_frames += keep;
        }

        const std::vector<float> filtered = median_filter_preds(all_preds, all_frames);
        std::vector<Segment> segments = binarize_preds(filtered, all_frames, options);
        const int64_t audio_ms =
            static_cast<int64_t>(sample_count) * 1000 / static_cast<int64_t>(kSampleRate);
        // Clip to audio duration.
        for (auto& seg : segments) {
            seg.end_ms = std::min(seg.end_ms, audio_ms);
        }
        segments.erase(std::remove_if(segments.begin(), segments.end(),
                                      [](const Segment& s) { return s.end_ms <= s.start_ms; }),
                       segments.end());
        const int64_t proc_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                                    std::chrono::steady_clock::now() - started)
                                    .count();
        return build_result(segments, audio_ms, proc_ms, out_result);
    } catch (const std::bad_alloc&) {
        rac_diarization_result_free(out_result);
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        rac_diarization_result_free(out_result);
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

// ---------------------------------------------------------------------------
// Streaming session
// ---------------------------------------------------------------------------
rac_result_t ONNXDiarizationProvider::Impl::stream_create(const rac_diarization_options_t& options,
                                                          rac_handle_t* out_stream_handle) {
    if (!out_stream_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_stream_handle = nullptr;
    std::lock_guard<std::mutex> lock(mutex_);
    if (!session_) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }
    try {
        auto* stream = new DiarizationStream();
        stream->options = options;
        streams_.insert(stream);
        *out_stream_handle = static_cast<rac_handle_t>(stream);
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
}

rac_result_t ONNXDiarizationProvider::Impl::stream_feed_audio_chunk(
    rac_handle_t stream_handle, const float* samples, size_t sample_count,
    rac_diarization_stream_callback_t callback, void* user_data) {
    if (!stream_handle || !callback) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::unique_lock<std::mutex> lock(mutex_);
    if (!session_) {
        return RAC_ERROR_BACKEND_NOT_READY;
    }
    auto* stream = static_cast<DiarizationStream*>(stream_handle);
    if (streams_.find(stream) == streams_.end()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    const bool flush = (samples == nullptr || sample_count == 0);
    const auto started = std::chrono::steady_clock::now();
    try {
        if (!flush) {
            stream->audio_buffer.insert(stream->audio_buffer.end(), samples,
                                        samples + sample_count);
            stream->total_samples += sample_count;
        }

        const size_t feed_size = (kChunkLen + kRightContext) * kSubsampling;  // mel frames
        const size_t feed_samples = feed_size * kHopLength;                   // 10 s
        const size_t stride_samples = kChunkLen * kSubsampling * kHopLength;  // ~9.92 s

        // Drain full windows.
        while (stream->audio_buffer.size() >= feed_samples) {
            std::vector<float> features;
            size_t frames = 0;
            extract_mel_features(stream->audio_buffer.data(), feed_samples, &features, &frames);
            std::vector<float> chunk_feat(feed_size * kNMels, 0.0f);
            const size_t copy_frames = std::min(feed_size, frames);
            std::memcpy(chunk_feat.data(), features.data(), copy_frames * kNMels * sizeof(float));

            std::vector<float> chunk_preds;
            size_t keep = 0;
            rac_result_t rc =
                streaming_update(&stream->state, chunk_feat, feed_size, &chunk_preds, &keep);
            if (rc != RAC_SUCCESS) {
                return rc;
            }
            stream->all_preds.insert(stream->all_preds.end(), chunk_preds.begin(),
                                     chunk_preds.end());
            stream->total_frames += keep;
            stream->audio_buffer.erase(stream->audio_buffer.begin(),
                                       stream->audio_buffer.begin() + stride_samples);
        }

        // On flush, process the remaining tail (zero-padded).
        if (flush && !stream->audio_buffer.empty()) {
            std::vector<float> remaining = std::move(stream->audio_buffer);
            stream->audio_buffer.clear();
            std::vector<float> features;
            size_t frames = 0;
            extract_mel_features(remaining.data(), remaining.size(), &features, &frames);
            const size_t current_len = std::min(frames, feed_size);
            std::vector<float> chunk_feat(feed_size * kNMels, 0.0f);
            std::memcpy(chunk_feat.data(), features.data(),
                        std::min(current_len, frames) * kNMels * sizeof(float));

            std::vector<float> chunk_preds;
            size_t keep = 0;
            rac_result_t rc =
                streaming_update(&stream->state, chunk_feat, current_len, &chunk_preds, &keep);
            if (rc != RAC_SUCCESS) {
                return rc;
            }
            stream->all_preds.insert(stream->all_preds.end(), chunk_preds.begin(),
                                     chunk_preds.end());
            stream->total_frames += keep;
        }

        stream->processing_time_ms += std::chrono::duration_cast<std::chrono::milliseconds>(
                                          std::chrono::steady_clock::now() - started)
                                          .count();

        // Build the complete current-session snapshot and emit it once.
        const std::vector<float> filtered =
            median_filter_preds(stream->all_preds, stream->total_frames);
        std::vector<Segment> segments =
            binarize_preds(filtered, stream->total_frames, stream->options);
        const int64_t audio_ms =
            static_cast<int64_t>(stream->total_samples) * 1000 / static_cast<int64_t>(kSampleRate);
        for (auto& seg : segments) {
            seg.end_ms = std::min(seg.end_ms, audio_ms);
        }
        segments.erase(std::remove_if(segments.begin(), segments.end(),
                                      [](const Segment& s) { return s.end_ms <= s.start_ms; }),
                       segments.end());

        rac_diarization_result_t snapshot;
        rac_result_t rc = build_result(segments, audio_ms, stream->processing_time_ms, &snapshot);
        if (rc != RAC_SUCCESS) {
            return rc;
        }
        // Emit the snapshot outside the provider lock so a callback that
        // re-enters the provider cannot deadlock. The snapshot is a fully
        // owned copy, independent of any provider/stream state.
        lock.unlock();
        callback(&snapshot, user_data);
        rac_diarization_result_free(&snapshot);
        return RAC_SUCCESS;
    } catch (const std::bad_alloc&) {
        return RAC_ERROR_OUT_OF_MEMORY;
    } catch (...) {
        return RAC_ERROR_INFERENCE_FAILED;
    }
}

rac_result_t ONNXDiarizationProvider::Impl::stream_destroy(rac_handle_t stream_handle) {
    if (!stream_handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    auto* stream = static_cast<DiarizationStream*>(stream_handle);
    auto it = streams_.find(stream);
    if (it == streams_.end()) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    streams_.erase(it);
    delete stream;
    return RAC_SUCCESS;
}

void ONNXDiarizationProvider::Impl::destroy_all_streams() {
    std::lock_guard<std::mutex> lock(mutex_);
    for (auto* stream : streams_) {
        delete stream;
    }
    streams_.clear();
}

void ONNXDiarizationProvider::Impl::cleanup() {
    destroy_all_streams();
    std::lock_guard<std::mutex> lock(mutex_);
    session_.reset();
}

bool ONNXDiarizationProvider::Impl::is_ready() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return session_ != nullptr;
}

// ---------------------------------------------------------------------------
// Public forwards
// ---------------------------------------------------------------------------
ONNXDiarizationProvider::ONNXDiarizationProvider() : impl_(std::make_unique<Impl>()) {}
ONNXDiarizationProvider::~ONNXDiarizationProvider() = default;

rac_result_t ONNXDiarizationProvider::initialize(const std::string& model_path) {
    return impl_->initialize(model_path);
}
rac_result_t ONNXDiarizationProvider::diarize(const float* samples, size_t sample_count,
                                              const rac_diarization_options_t& options,
                                              rac_diarization_result_t* out_result) {
    return impl_->diarize(samples, sample_count, options, out_result);
}
rac_result_t ONNXDiarizationProvider::stream_create(const rac_diarization_options_t& options,
                                                    rac_handle_t* out_stream_handle) {
    return impl_->stream_create(options, out_stream_handle);
}
rac_result_t ONNXDiarizationProvider::stream_feed_audio_chunk(
    rac_handle_t stream_handle, const float* samples, size_t sample_count,
    rac_diarization_stream_callback_t callback, void* user_data) {
    return impl_->stream_feed_audio_chunk(stream_handle, samples, sample_count, callback,
                                          user_data);
}
rac_result_t ONNXDiarizationProvider::stream_destroy(rac_handle_t stream_handle) {
    return impl_->stream_destroy(stream_handle);
}
void ONNXDiarizationProvider::cleanup() {
    impl_->cleanup();
}
bool ONNXDiarizationProvider::is_ready() const {
    return impl_->is_ready();
}

}  // namespace runanywhere::diarization
