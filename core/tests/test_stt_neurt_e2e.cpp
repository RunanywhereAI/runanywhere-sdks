// End to end: a WAV file in through the SDK's own STT op table, a scored transcript out.
//
// This is the hop nothing else covers. `test_plugin_entry_neurt` proves the vtable slot is filled
// and the router pins the engine; `neurt_transcribe` in the neurun repo proves the runtime turns
// audio into the right words. Neither proves the two meet, and that seam is where a wrong struct
// offset or a byte-vs-sample mixup lives: both sides compile, both sides pass their own tests, and
// the transcript comes back empty or garbled.
//
// NOTHING HERE IS STUBBED. It loads a real published bundle, decodes real recorded speech, and
// scores the text against the clip's known reference with an edit distance. A hardcoded expected
// string would pass on a broken build the moment someone pasted the output back in, so the gate is
// the WER against LibriSpeech's own transcript, computed here.
//
// Skips cleanly (exit 0, reason printed) when the bundle or the audio is absent, because a 1.2 GB
// private-repo download cannot be a hard requirement of a unit test. Point it at one with:
//
//     RAC_ASR_BUNDLE=/path/to/parakeet-tdt-0.6b-v3_ANE \
//     RAC_ASR_WAV=/path/to/ls16k.wav ./test_stt_neurt_e2e

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/plugin/rac_engine_vtable.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_neurt.h"

namespace {

int g_pass = 0;
int g_fail = 0;

#define CHECK(cond, ...)                                    \
    do {                                                    \
        if (cond) { ++g_pass; }                             \
        else {                                              \
            ++g_fail;                                       \
            std::fprintf(stderr, "  FAIL %s:%d: ", __FILE__, __LINE__); \
            std::fprintf(stderr, __VA_ARGS__);              \
            std::fprintf(stderr, "\n");                     \
        }                                                   \
    } while (0)

// LibriSpeech 1272-128104-0000. The reference is the corpus's own transcript, not something this
// runtime produced, which is what makes the comparison meaningful.
constexpr const char* kReference =
    "Mr Quilter is the apostle of the middle classes and we are glad to welcome his gospel";

// 16-bit PCM WAV. Chunks are walked rather than assumed at a fixed offset: a file written by
// afconvert carries a LIST chunk before `data`, and a fixed-offset reader feeds metadata to the
// model as audio.
std::vector<int16_t> read_wav_i16(const std::string& path, int* sample_rate) {
    std::ifstream f(path, std::ios::binary);
    std::vector<int16_t> out;
    *sample_rate = 0;
    if (!f) return out;
    char riff[12];
    f.read(riff, 12);
    if (std::memcmp(riff, "RIFF", 4) != 0 || std::memcmp(riff + 8, "WAVE", 4) != 0) return out;
    int channels = 1, bits = 16;
    for (;;) {
        char id[4];
        uint32_t size = 0;
        if (!f.read(id, 4) || !f.read(reinterpret_cast<char*>(&size), 4)) break;
        if (std::memcmp(id, "fmt ", 4) == 0) {
            unsigned char fmt[16] = {0};
            const uint32_t want = size < 16 ? size : 16;
            f.read(reinterpret_cast<char*>(fmt), want);
            channels = fmt[2] | (fmt[3] << 8);
            *sample_rate = fmt[4] | (fmt[5] << 8) | (fmt[6] << 16) | (fmt[7] << 24);
            bits = fmt[14] | (fmt[15] << 8);
            if (size > want) f.seekg(size - want, std::ios::cur);
        } else if (std::memcmp(id, "data", 4) == 0) {
            if (bits != 16 || channels < 1) break;
            const std::streampos data_begin = f.tellg();
            if (data_begin == std::streampos(-1)) {
                break;
            }
            f.seekg(0, std::ios::end);
            const std::streampos data_end = f.tellg();
            if (data_end == std::streampos(-1)) {
                break;
            }
            const std::streamoff remaining = data_end - data_begin;
            if (remaining <= 0 || !f.seekg(data_begin)) {
                break;
            }
            const size_t usable =
                static_cast<size_t>(std::min<std::streamoff>(size, remaining)) & ~size_t{1};
            if (usable == 0) {
                break;
            }
            std::vector<int16_t> raw(usable / sizeof(int16_t));
            if (!f.read(reinterpret_cast<char*>(raw.data()),
                        static_cast<std::streamsize>(usable))) {
                break;
            }
            out.resize(raw.size() / static_cast<size_t>(channels));
            for (size_t i = 0; i < out.size(); ++i) {
                int acc = 0;
                for (int c = 0; c < channels; ++c) acc += raw[i * channels + c];
                out[i] = static_cast<int16_t>(acc / channels);
            }
            break;
        } else {
            f.seekg((size + 1u) & ~1u, std::ios::cur);
        }
    }
    return out;
}

// Lowercase, strip punctuation, split. "mister" folds to "mr" because the two models spell the
// same abbreviation differently and that is an orthography choice, not a recognition error.
std::vector<std::string> normalise(const std::string& s) {
    std::string low;
    low.reserve(s.size());
    for (const char c : s) low.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(c))));
    const std::string mister = "mister";
    for (size_t at = low.find(mister); at != std::string::npos; at = low.find(mister, at + 2)) {
        low.replace(at, mister.size(), "mr");
    }
    std::vector<std::string> words;
    std::string cur;
    for (const char c : low) {
        if (std::isalnum(static_cast<unsigned char>(c))) {
            cur.push_back(c);
        } else if (!cur.empty()) {
            words.push_back(cur);
            cur.clear();
        }
    }
    if (!cur.empty()) words.push_back(cur);
    return words;
}

// Levenshtein over words, divided by the reference length. Computed here rather than compared
// against a stored string, so the test measures recognition instead of memorising an output.
// Some bundles compile ONE static audio window and cannot hear a longer clip: Moonshine's is 64000
// samples (4.0 s) against this 5.9 s recording, so it transcribes the first two thirds and stops.
// That is the bundle's shape, not a recognition error.
//
// Scoring it against the full reference reports a WER that measures the window, so the caller opts
// into prefix scoring with RAC_ASR_EXPECT_PARTIAL=1 and the test prints the coverage it measured.
// Deliberately caller-controlled and off by default: switching automatically whenever the output is
// short would silently forgive a bundle that stopped early for a real reason, which is the failure
// this test exists to catch.
double word_error_rate(const std::string& ref, const std::string& hyp, bool allow_prefix = false,
                       double* coverage_out = nullptr) {
    std::vector<std::string> r = normalise(ref);
    const std::vector<std::string> h = normalise(hyp);
    if (coverage_out != nullptr) {
        *coverage_out = r.empty() ? 0.0 : static_cast<double>(h.size()) / static_cast<double>(r.size());
    }
    if (allow_prefix && !h.empty() && h.size() < r.size()) r.resize(h.size());
    if (r.empty()) return 1.0;
    std::vector<size_t> prev(h.size() + 1), cur(h.size() + 1);
    for (size_t j = 0; j <= h.size(); ++j) prev[j] = j;
    for (size_t i = 1; i <= r.size(); ++i) {
        cur[0] = i;
        for (size_t j = 1; j <= h.size(); ++j) {
            cur[j] = std::min({prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r[i - 1] != h[j - 1] ? 1u : 0u)});
        }
        prev = cur;
    }
    return static_cast<double>(prev[h.size()]) / static_cast<double>(r.size());
}

std::string env_or(const char* key, const char* dflt) {
    const char* v = std::getenv(key);
    return (v != nullptr && v[0] != '\0') ? std::string(v) : std::string(dflt);
}

struct StreamCapture {
    std::string final_text;
    int partial_calls = 0;
    int final_calls = 0;
};

void on_stream(const char* text, rac_bool_t is_final, void* user) {
    auto* c = static_cast<StreamCapture*>(user);
    if (text == nullptr) return;
    if (is_final == RAC_TRUE) {
        c->final_text = text;
        ++c->final_calls;
    } else {
        ++c->partial_calls;
    }
}

}  // namespace

int main() {
    std::printf("=== NeuRT STT end-to-end, through the SDK op table ===\n");

    const std::string bundle = env_or("RAC_ASR_BUNDLE", "");
    const std::string wav = env_or("RAC_ASR_WAV", "");
    if (bundle.empty() || wav.empty()) {
        std::printf("SKIP: set RAC_ASR_BUNDLE and RAC_ASR_WAV to run this against a real bundle\n");
        return 0;
    }
    int sample_rate = 0;
    const std::vector<int16_t> pcm = read_wav_i16(wav, &sample_rate);
    if (pcm.empty() || sample_rate <= 0) {
        std::printf("SKIP: cannot read 16-bit PCM WAV at %s\n", wav.c_str());
        return 0;
    }
    std::printf("audio: %zu samples @ %d Hz (%.2f s)\n", pcm.size(), sample_rate,
                static_cast<double>(pcm.size()) / sample_rate);
    const bool allow_prefix = !env_or("RAC_ASR_EXPECT_PARTIAL", "").empty();
    if (allow_prefix) {
        std::printf("prefix scoring ON: this bundle's compiled audio window is shorter than the "
                    "clip, so the transcript is scored against the reference prefix\n");
    }

    const rac_engine_vtable_t* vt = rac_plugin_entry_neurt();
    CHECK(vt != nullptr, "the neurt plugin entry returned null");
    if (vt == nullptr) return 1;
    CHECK(vt->stt_ops != nullptr, "stt_ops is null; the ASR op table is not linked in");
    if (vt->stt_ops == nullptr) return 1;

    const rac_stt_service_ops_t* ops = vt->stt_ops;
    CHECK(ops->create != nullptr && ops->initialize != nullptr && ops->transcribe != nullptr &&
              ops->destroy != nullptr,
          "the op table is missing a required entry point");
    if (ops->create == nullptr || ops->initialize == nullptr || ops->transcribe == nullptr ||
        ops->destroy == nullptr) {
        return 1;
    }

    void* impl = nullptr;
    rac_result_t rc = ops->create(bundle.c_str(), nullptr, &impl);
    CHECK(rc == RAC_SUCCESS && impl != nullptr, "create failed: %d", static_cast<int>(rc));
    if (rc != RAC_SUCCESS || impl == nullptr) return 1;

    rc = ops->initialize(impl, bundle.c_str());
    CHECK(rc == RAC_SUCCESS, "initialize failed: %d", static_cast<int>(rc));
    if (rc != RAC_SUCCESS) {
        ops->destroy(impl);
        return 1;
    }

    rac_stt_info_t info{};
    if (ops->get_info != nullptr) {
        rc = ops->get_info(impl, &info);
        CHECK(rc == RAC_SUCCESS, "get_info failed: %d", static_cast<int>(rc));
        CHECK(info.is_ready == RAC_TRUE, "the service reports not ready after a successful load");
    }

    // The batch path. `audio_size` is BYTES, which is the SDK's convention; passing a sample count
    // transcribes the first half of the clip and still returns plausible words.
    rac_stt_options_t opts{};
    opts.sample_rate = sample_rate;
    rac_stt_result_t result{};
    rc = ops->transcribe(impl, pcm.data(), pcm.size() * sizeof(int16_t), &opts, &result);
    CHECK(rc == RAC_SUCCESS, "transcribe failed: %d", static_cast<int>(rc));
    CHECK(result.text != nullptr && result.text[0] != '\0', "transcribe returned no text");

    if (result.text != nullptr) {
        const std::string got = result.text;
        double coverage = 0.0;
        const double wer = word_error_rate(kReference, got, allow_prefix, &coverage);
        std::printf("transcript: %s\n", got.c_str());
        std::printf("WER vs the LibriSpeech reference: %.4f (%lld ms, coverage %.0f%%%s)\n", wer,
                    static_cast<long long>(result.processing_time_ms), coverage * 100.0,
                    allow_prefix ? ", prefix-scored" : "");
        // Whatever the window, the model has to have produced something. Prefix scoring must not
        // turn a one-word transcript into a pass.
        CHECK(coverage > 0.25, "coverage %.0f%% is too low to call this a transcript",
              coverage * 100.0);
        // 0.05 is the same gate the recipes use. Not 0.0: a correct ASR port still differs from a
        // human transcript on orthography, and demanding an exact match would gate on luck.
        CHECK(wer <= 0.05, "WER %.4f exceeds the 0.05 gate", wer);
        CHECK(result.processing_time_ms >= 0, "processing_time_ms is negative");
    }
    rac_stt_result_free(&result);

    // The streaming path. Same audio, same engine, and the final must agree with the batch call:
    // if they disagree, one of them is reading the buffer differently.
    if (ops->transcribe_stream != nullptr) {
        StreamCapture cap;
        rc = ops->transcribe_stream(impl, pcm.data(), pcm.size() * sizeof(int16_t), &opts,
                                    on_stream, &cap);
        CHECK(rc == RAC_SUCCESS, "transcribe_stream failed: %d", static_cast<int>(rc));
        CHECK(cap.final_calls == 1, "expected exactly one final callback, got %d", cap.final_calls);
        CHECK(!cap.final_text.empty(), "the streaming final was empty");
        if (!cap.final_text.empty()) {
            const double wer = word_error_rate(kReference, cap.final_text, allow_prefix, nullptr);
            std::printf("streaming final: %s\n", cap.final_text.c_str());
            std::printf("streaming WER: %.4f (%d partial callbacks)\n", wer, cap.partial_calls);
            CHECK(wer <= 0.05, "streaming WER %.4f exceeds the 0.05 gate", wer);
        }
    }

    // A short buffer must be refused rather than transcribed as noise.
    rac_stt_result_t tiny{};
    rc = ops->transcribe(impl, pcm.data(), 1, &opts, &tiny);
    CHECK(rc != RAC_SUCCESS, "a 1-byte buffer was accepted");

    // Null audio likewise.
    rc = ops->transcribe(impl, nullptr, 0, &opts, &tiny);
    CHECK(rc != RAC_SUCCESS, "null audio was accepted");

    if (ops->cleanup != nullptr) {
        rc = ops->cleanup(impl);
        CHECK(rc == RAC_SUCCESS, "cleanup failed: %d", static_cast<int>(rc));
    }
    ops->destroy(impl);

    std::printf("\n%d passed, %d failed\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
