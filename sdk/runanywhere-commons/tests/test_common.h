#ifndef TEST_COMMON_H
#define TEST_COMMON_H

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <functional>
#include <iostream>
#include <map>
#include <string>
#include <vector>

// =============================================================================
// Test Result
// =============================================================================

struct TestResult {
    std::string test_name;
    bool passed = false;
    std::string expected;
    std::string actual;
    std::string details;
};

inline void print_result(const TestResult& r) {
    if (r.passed) {
        std::cout << "\033[32m[PASS]\033[0m " << r.test_name;
    } else {
        std::cout << "\033[31m[FAIL]\033[0m " << r.test_name;
    }
    if (!r.details.empty()) {
        std::cout << " - " << r.details;
    }
    if (!r.passed) {
        if (!r.expected.empty()) {
            std::cout << "\n       Expected: " << r.expected;
        }
        if (!r.actual.empty()) {
            std::cout << "\n       Actual:   " << r.actual;
        }
    }
    std::cout << "\n";
}

inline int print_summary(const std::vector<TestResult>& results) {
    int passed = 0;
    int failed = 0;
    for (const auto& r : results) {
        if (r.passed) {
            ++passed;
        } else {
            ++failed;
        }
    }
    std::cout << "\n========================================\n";
    std::cout << "Results: " << passed << " passed, " << failed << " failed, "
              << results.size() << " total\n";
    std::cout << "========================================\n";
    return (failed > 0) ? 1 : 0;
}

// =============================================================================
// WAV File I/O
// =============================================================================

struct WavFile {
    std::vector<int16_t> samples;
    uint32_t sample_rate = 0;
    uint16_t channels = 0;
    uint16_t bits_per_sample = 0;
};

inline bool read_wav(const std::string& path, WavFile& wav) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "read_wav: cannot open " << path << "\n";
        return false;
    }

    // --- RIFF header ---
    char riff_id[4];
    file.read(riff_id, 4);
    if (std::strncmp(riff_id, "RIFF", 4) != 0) {
        std::cerr << "read_wav: not a RIFF file\n";
        return false;
    }

    uint32_t file_size = 0;
    file.read(reinterpret_cast<char*>(&file_size), 4);

    char wave_id[4];
    file.read(wave_id, 4);
    if (std::strncmp(wave_id, "WAVE", 4) != 0) {
        std::cerr << "read_wav: not a WAVE file\n";
        return false;
    }

    // --- Find fmt and data chunks ---
    bool found_fmt = false;
    bool found_data = false;
    uint16_t audio_format = 0;

    while (file.good() && !(found_fmt && found_data)) {
        char chunk_id[4];
        uint32_t chunk_size = 0;
        file.read(chunk_id, 4);
        file.read(reinterpret_cast<char*>(&chunk_size), 4);

        if (!file.good()) break;

        if (std::strncmp(chunk_id, "fmt ", 4) == 0) {
            // fmt chunk layout (16 bytes minimum):
            //   AudioFormat(2) Channels(2) SampleRate(4)
            //   ByteRate(4) BlockAlign(2) BitsPerSample(2)
            auto fmt_start = file.tellg();

            file.read(reinterpret_cast<char*>(&audio_format), 2);
            file.read(reinterpret_cast<char*>(&wav.channels), 2);
            file.read(reinterpret_cast<char*>(&wav.sample_rate), 4);

            uint32_t byte_rate = 0;
            file.read(reinterpret_cast<char*>(&byte_rate), 4);

            uint16_t block_align = 0;
            file.read(reinterpret_cast<char*>(&block_align), 2);

            file.read(reinterpret_cast<char*>(&wav.bits_per_sample), 2);

            // Seek to end of chunk (handles extended fmt chunks)
            file.seekg(fmt_start + static_cast<std::streamoff>(chunk_size));
            found_fmt = true;

        } else if (std::strncmp(chunk_id, "data", 4) == 0) {
            if (wav.bits_per_sample != 16) {
                std::cerr << "read_wav: only 16-bit PCM supported (got "
                          << wav.bits_per_sample << ")\n";
                return false;
            }

            size_t num_samples_total = chunk_size / sizeof(int16_t);
            std::vector<int16_t> raw(num_samples_total);
            file.read(reinterpret_cast<char*>(raw.data()),
                       static_cast<std::streamsize>(chunk_size));

            if (wav.channels == 1) {
                wav.samples = std::move(raw);
            } else {
                // Convert stereo (or multi-channel) to mono by averaging
                size_t frames = num_samples_total / wav.channels;
                wav.samples.resize(frames);
                for (size_t i = 0; i < frames; ++i) {
                    int32_t sum = 0;
                    for (uint16_t ch = 0; ch < wav.channels; ++ch) {
                        sum += raw[i * wav.channels + ch];
                    }
                    wav.samples[i] = static_cast<int16_t>(sum / wav.channels);
                }
                wav.channels = 1;
            }
            found_data = true;

        } else {
            // Skip unknown chunk
            file.seekg(chunk_size, std::ios::cur);
        }
    }

    if (!found_fmt || !found_data) {
        std::cerr << "read_wav: missing fmt or data chunk\n";
        return false;
    }

    return true;
}

inline bool write_wav(const std::string& path, const int16_t* samples,
                      size_t count, uint32_t sample_rate) {
    std::ofstream file(path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "write_wav: cannot open " << path << "\n";
        return false;
    }

    uint16_t channels = 1;
    uint16_t bits_per_sample = 16;
    uint32_t byte_rate = sample_rate * channels * (bits_per_sample / 8);
    uint16_t block_align = channels * (bits_per_sample / 8);
    uint32_t data_size = static_cast<uint32_t>(count * sizeof(int16_t));
    uint32_t file_size = 36 + data_size;

    // RIFF header
    file.write("RIFF", 4);
    file.write(reinterpret_cast<const char*>(&file_size), 4);
    file.write("WAVE", 4);

    // fmt chunk
    file.write("fmt ", 4);
    uint32_t fmt_size = 16;
    file.write(reinterpret_cast<const char*>(&fmt_size), 4);
    uint16_t audio_format = 1; // PCM
    file.write(reinterpret_cast<const char*>(&audio_format), 2);
    file.write(reinterpret_cast<const char*>(&channels), 2);
    file.write(reinterpret_cast<const char*>(&sample_rate), 4);
    file.write(reinterpret_cast<const char*>(&byte_rate), 4);
    file.write(reinterpret_cast<const char*>(&block_align), 2);
    file.write(reinterpret_cast<const char*>(&bits_per_sample), 2);

    // data chunk
    file.write("data", 4);
    file.write(reinterpret_cast<const char*>(&data_size), 4);
    file.write(reinterpret_cast<const char*>(samples),
               static_cast<std::streamsize>(data_size));

    return file.good();
}

// =============================================================================
// Audio Conversion Utilities
// =============================================================================

inline std::vector<float> int16_to_float(const std::vector<int16_t>& samples) {
    std::vector<float> out(samples.size());
    for (size_t i = 0; i < samples.size(); ++i) {
        out[i] = static_cast<float>(samples[i]) / 32768.0f;
    }
    return out;
}

inline std::vector<float> int16_to_float_raw(const std::vector<int16_t>& samples) {
    std::vector<float> out(samples.size());
    for (size_t i = 0; i < samples.size(); ++i) {
        out[i] = static_cast<float>(samples[i]);
    }
    return out;
}

inline std::vector<int16_t> float_to_int16(const std::vector<float>& samples) {
    std::vector<int16_t> out(samples.size());
    for (size_t i = 0; i < samples.size(); ++i) {
        float clamped = std::max(-1.0f, std::min(1.0f, samples[i]));
        out[i] = static_cast<int16_t>(clamped * 32767.0f);
    }
    return out;
}

// =============================================================================
// Audio Generation Utilities
// =============================================================================

inline std::vector<float> generate_silence(size_t num_samples) {
    return std::vector<float>(num_samples, 0.0f);
}

inline std::vector<float> generate_sine_wave(float freq_hz, float duration_sec,
                                              int sample_rate, float amplitude = 0.5f) {
    size_t num_samples = static_cast<size_t>(duration_sec * sample_rate);
    std::vector<float> out(num_samples);
    const float two_pi = 2.0f * static_cast<float>(M_PI);
    for (size_t i = 0; i < num_samples; ++i) {
        float t = static_cast<float>(i) / static_cast<float>(sample_rate);
        out[i] = amplitude * std::sin(two_pi * freq_hz * t);
    }
    return out;
}

inline std::vector<float> generate_white_noise(size_t num_samples, float amplitude = 0.1f) {
    std::vector<float> out(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        float r = static_cast<float>(std::rand()) / static_cast<float>(RAND_MAX);
        out[i] = amplitude * (2.0f * r - 1.0f);
    }
    return out;
}

// =============================================================================
// Audio Resampling (linear interpolation)
// =============================================================================

/**
 * Resample float audio from one sample rate to another using linear interpolation.
 * Used for TTS→STT/VAD round-trip tests (22050Hz → 16000Hz).
 */
inline std::vector<float> resample_linear(const float* input, size_t input_len,
                                           int from_rate, int to_rate) {
    if (from_rate == to_rate || input_len == 0) {
        return std::vector<float>(input, input + input_len);
    }
    double ratio = static_cast<double>(from_rate) / static_cast<double>(to_rate);
    size_t output_len = static_cast<size_t>(static_cast<double>(input_len) / ratio);
    std::vector<float> output(output_len);
    for (size_t i = 0; i < output_len; ++i) {
        double src_idx = static_cast<double>(i) * ratio;
        size_t idx0 = static_cast<size_t>(src_idx);
        size_t idx1 = idx0 + 1;
        if (idx1 >= input_len) idx1 = input_len - 1;
        double frac = src_idx - static_cast<double>(idx0);
        output[i] = static_cast<float>(
            static_cast<double>(input[idx0]) * (1.0 - frac) +
            static_cast<double>(input[idx1]) * frac);
    }
    return output;
}

// =============================================================================
// Case-insensitive substring check
// =============================================================================

inline bool contains_ci(const std::string& haystack, const std::string& needle) {
    if (needle.empty()) return true;
    std::string h = haystack, n = needle;
    std::transform(h.begin(), h.end(), h.begin(), ::tolower);
    std::transform(n.begin(), n.end(), n.begin(), ::tolower);
    return h.find(n) != std::string::npos;
}

// =============================================================================
// Scoped Timer
// =============================================================================

class ScopedTimer {
public:
    explicit ScopedTimer(const std::string& label)
        : label_(label), start_(std::chrono::steady_clock::now()) {}

    ~ScopedTimer() {
        auto end = std::chrono::steady_clock::now();
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(end - start_).count();
        std::cout << "[TIMER] " << label_ << ": " << ms << " ms\n";
    }

    ScopedTimer(const ScopedTimer&) = delete;
    ScopedTimer& operator=(const ScopedTimer&) = delete;

private:
    std::string label_;
    std::chrono::steady_clock::time_point start_;
};

// =============================================================================
// Test Runner / Argument Parser
// =============================================================================

inline int parse_test_args(int argc, char** argv,
                           const std::map<std::string, std::function<TestResult()>>& tests) {
    std::vector<TestResult> results;

    if (argc < 2) {
        std::cout << "Usage: " << argv[0] << " --run-all | --test-<name> [--test-<name> ...]\n";
        std::cout << "Available tests:\n";
        for (const auto& kv : tests) {
            std::cout << "  --test-" << kv.first << "\n";
        }
        return 1;
    }

    bool run_all = false;
    std::vector<std::string> selected;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--run-all") {
            run_all = true;
        } else if (arg.rfind("--test-", 0) == 0) {
            std::string name = arg.substr(7); // strip "--test-"
            selected.push_back(name);
        }
    }

    if (run_all) {
        for (const auto& kv : tests) {
            std::cout << "\n--- Running: " << kv.first << " ---\n";
            TestResult r = kv.second();
            print_result(r);
            results.push_back(r);
        }
    } else {
        for (const auto& name : selected) {
            auto it = tests.find(name);
            if (it == tests.end()) {
                std::cerr << "Unknown test: " << name << "\n";
                TestResult r;
                r.test_name = name;
                r.passed = false;
                r.details = "Unknown test name";
                results.push_back(r);
            } else {
                std::cout << "\n--- Running: " << name << " ---\n";
                TestResult r = it->second();
                print_result(r);
                results.push_back(r);
            }
        }
    }

    return print_summary(results);
}

// =============================================================================
// Assertion Macros (return early from test function on failure)
// =============================================================================

#define ASSERT_EQ(_a, _e, _m)                                                  \
    do {                                                                        \
        auto _av = (_a);                                                        \
        auto _ev = (_e);                                                        \
        if (_av != _ev) {                                                       \
            TestResult _fail_result;                                            \
            _fail_result.passed = false;                                        \
            _fail_result.expected = std::to_string(_ev);                        \
            _fail_result.actual = std::to_string(_av);                          \
            _fail_result.details = (_m);                                        \
            return _fail_result;                                                \
        }                                                                       \
    } while (0)

#define ASSERT_TRUE(_cond, _m)                                                  \
    do {                                                                        \
        if (!(_cond)) {                                                         \
            TestResult _fail_result;                                            \
            _fail_result.passed = false;                                        \
            _fail_result.details = (_m);                                        \
            return _fail_result;                                                \
        }                                                                       \
    } while (0)

inline TestResult make_pass_result() {
    TestResult r;
    r.passed = true;
    return r;
}

#define TEST_PASS() make_pass_result()

// =============================================================================
// TestSuite: ordered test runner with CLI arg parsing
// =============================================================================

class TestSuite {
public:
    explicit TestSuite(const std::string& name) : suite_name_(name) {}

    void add(const std::string& test_name, std::function<TestResult()> fn) {
        tests_[test_name] = std::move(fn);
        order_.push_back(test_name);
    }

    int run(int argc, char** argv) {
        std::vector<TestResult> results;

        if (argc < 2) {
            std::cout << "Usage: " << argv[0]
                      << " --run-all | --test-<name> [--test-<name> ...]\n";
            std::cout << "Available tests in suite '" << suite_name_ << "':\n";
            for (const auto& name : order_) {
                std::cout << "  --test-" << name << "\n";
            }
            return 1;
        }

        bool run_all = false;
        std::vector<std::string> selected;
        for (int i = 1; i < argc; ++i) {
            std::string arg = argv[i];
            if (arg == "--run-all") {
                run_all = true;
            } else if (arg.rfind("--test-", 0) == 0) {
                selected.push_back(arg.substr(7));
            }
        }

        auto run_test = [&](const std::string& name) {
            auto it = tests_.find(name);
            if (it == tests_.end()) {
                TestResult r;
                r.test_name = name;
                r.passed = false;
                r.details = "Unknown test name";
                results.push_back(r);
                print_result(r);
                return;
            }
            std::cout << "\n--- Running: " << name << " ---\n";
            TestResult r = it->second();
            if (r.test_name.empty()) r.test_name = name;
            print_result(r);
            results.push_back(r);
        };

        if (run_all) {
            for (const auto& name : order_) {
                run_test(name);
            }
        } else {
            for (const auto& name : selected) {
                run_test(name);
            }
        }

        return print_summary(results);
    }

private:
    std::string suite_name_;
    std::map<std::string, std::function<TestResult()>> tests_;
    std::vector<std::string> order_;
};

#endif // TEST_COMMON_H
