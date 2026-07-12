// =============================================================================
// test_components.cpp - Test VAD, STT, and the continuous-listening pipeline
// =============================================================================

#include "config/model_config.h"
#include "pipeline/voice_pipeline.h"

#include <rac/core/rac_error.h>
#include <rac/features/stt/rac_stt_component.h>
#include <rac/features/vad/rac_vad_component.h>
#include <rac/plugin/rac_plugin_entry_sherpa.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

struct WavFile {
    std::vector<int16_t> samples;
    uint32_t sample_rate = 0;
    uint16_t channels = 0;
    uint16_t bits_per_sample = 0;
    float duration_sec = 0.0f;
};

bool read_wav(const std::string& path, WavFile& wav) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Cannot open: " << path << '\n';
        return false;
    }

    char riff[4];
    file.read(riff, sizeof(riff));
    if (!file || std::strncmp(riff, "RIFF", sizeof(riff)) != 0) {
        std::cerr << "Not a RIFF WAV file: " << path << '\n';
        return false;
    }

    uint32_t file_size = 0;
    file.read(reinterpret_cast<char*>(&file_size), sizeof(file_size));
    (void)file_size;

    char wave[4];
    file.read(wave, sizeof(wave));
    if (!file || std::strncmp(wave, "WAVE", sizeof(wave)) != 0) {
        std::cerr << "Not a WAVE file: " << path << '\n';
        return false;
    }

    while (file) {
        char chunk_id[4];
        uint32_t chunk_size = 0;
        file.read(chunk_id, sizeof(chunk_id));
        file.read(reinterpret_cast<char*>(&chunk_size), sizeof(chunk_size));
        if (!file) break;

        if (std::strncmp(chunk_id, "fmt ", sizeof(chunk_id)) == 0) {
            uint16_t audio_format = 0;
            uint32_t byte_rate = 0;
            uint16_t block_align = 0;
            file.read(reinterpret_cast<char*>(&audio_format), sizeof(audio_format));
            file.read(reinterpret_cast<char*>(&wav.channels), sizeof(wav.channels));
            file.read(reinterpret_cast<char*>(&wav.sample_rate), sizeof(wav.sample_rate));
            file.read(reinterpret_cast<char*>(&byte_rate), sizeof(byte_rate));
            file.read(reinterpret_cast<char*>(&block_align), sizeof(block_align));
            file.read(reinterpret_cast<char*>(&wav.bits_per_sample), sizeof(wav.bits_per_sample));
            (void)byte_rate;
            (void)block_align;
            if (audio_format != 1 || wav.bits_per_sample != 16) {
                std::cerr << "Only 16-bit PCM WAV files are supported\n";
                return false;
            }
            if (chunk_size > 16) file.seekg(chunk_size - 16, std::ios::cur);
        } else if (std::strncmp(chunk_id, "data", sizeof(chunk_id)) == 0) {
            if (wav.channels == 0 || wav.bits_per_sample != 16) return false;
            const size_t total_samples = chunk_size / sizeof(int16_t);
            const size_t frame_count = total_samples / wav.channels;
            if (wav.channels == 1) {
                wav.samples.resize(frame_count);
                file.read(reinterpret_cast<char*>(wav.samples.data()), chunk_size);
            } else if (wav.channels == 2) {
                std::vector<int16_t> stereo(total_samples);
                file.read(reinterpret_cast<char*>(stereo.data()), chunk_size);
                wav.samples.resize(frame_count);
                for (size_t i = 0; i < frame_count; ++i) {
                    wav.samples[i] = static_cast<int16_t>(
                        (static_cast<int32_t>(stereo[i * 2]) + stereo[i * 2 + 1]) / 2);
                }
            } else {
                std::cerr << "Unsupported channel count: " << wav.channels << '\n';
                return false;
            }
            break;
        } else {
            file.seekg(chunk_size, std::ios::cur);
        }
    }

    if (wav.samples.empty() || wav.sample_rate == 0) return false;
    wav.duration_sec = static_cast<float>(wav.samples.size()) / wav.sample_rate;
    return true;
}

struct TestResult {
    std::string test_name;
    bool passed = false;
    std::string expected;
    std::string actual;
    std::string details;
};

void print_result(const TestResult& result) {
    std::cout << "\n" << (result.passed ? "PASS" : "FAIL") << ": " << result.test_name << '\n';
    if (!result.expected.empty()) std::cout << "  Expected: " << result.expected << '\n';
    if (!result.actual.empty()) std::cout << "  Actual:   " << result.actual << '\n';
    if (!result.details.empty()) std::cout << "  Details:  " << result.details << '\n';
}

TestResult test_vad_stt(const std::string& wav_path, bool expect_speech,
                        const std::string& expected_text = "") {
    TestResult result;
    result.test_name = "VAD + STT - " + wav_path;
    result.expected = expect_speech ? "Speech detected and transcribed" : "No speech";

    WavFile wav;
    if (!read_wav(wav_path, wav) || wav.sample_rate != 16000) {
        result.actual = "Expected a readable 16 kHz PCM WAV file";
        return result;
    }

    rac_handle_t stt = nullptr;
    rac_result_t status = rac_stt_component_create(&stt);
    rac_stt_config_t stt_config = RAC_STT_CONFIG_DEFAULT;
    if (status == RAC_SUCCESS) status = rac_stt_component_configure(stt, &stt_config);
    const std::string stt_path = openclaw::get_stt_model_path();
    if (status == RAC_SUCCESS) {
        status = rac_stt_component_load_model(
            stt, stt_path.c_str(), openclaw::STT_MODEL_ID, "Parakeet TDT-CTC 110M EN");
    }
    if (status != RAC_SUCCESS) {
        result.actual = "Failed to initialize the STT component (code " +
                        std::to_string(status) + ")";
        if (stt) rac_stt_component_destroy(stt);
        return result;
    }

    rac_handle_t vad = nullptr;
    status = rac_vad_component_create(&vad);
    rac_vad_config_t vad_config = RAC_VAD_CONFIG_DEFAULT;
    vad_config.sample_rate = 16000;
    if (status == RAC_SUCCESS) status = rac_vad_component_configure(vad, &vad_config);
    if (status == RAC_SUCCESS) status = rac_vad_component_initialize(vad);
    if (status == RAC_SUCCESS) {
        const std::string vad_path = openclaw::get_vad_model_path();
        status = rac_vad_component_load_model(
            vad, vad_path.c_str(), openclaw::VAD_MODEL_ID, "Silero VAD");
    }
    if (status == RAC_SUCCESS) status = rac_vad_component_start(vad);
    if (status != RAC_SUCCESS) {
        result.actual = "Failed to initialize the VAD component (code " +
                        std::to_string(status) + ")";
        if (vad) rac_vad_component_destroy(vad);
        rac_stt_component_destroy(stt);
        return result;
    }

    constexpr size_t chunk_size = 512;
    std::vector<float> samples(chunk_size);
    size_t speech_frames = 0;
    size_t total_frames = 0;
    for (size_t offset = 0; offset + chunk_size <= wav.samples.size(); offset += chunk_size) {
        for (size_t i = 0; i < chunk_size; ++i) {
            samples[i] = static_cast<float>(wav.samples[offset + i]) / 32768.0f;
        }
        rac_bool_t is_speech = RAC_FALSE;
        status = rac_vad_component_process(vad, samples.data(), samples.size(), &is_speech);
        if (status != RAC_SUCCESS) break;
        if (is_speech == RAC_TRUE) ++speech_frames;
        ++total_frames;
    }

    (void)rac_vad_component_stop(vad);
    rac_vad_component_destroy(vad);

    if (status != RAC_SUCCESS) {
        result.actual = "VAD processing failed (code " + std::to_string(status) + ")";
        rac_stt_component_destroy(stt);
        return result;
    }

    const float speech_ratio = total_frames == 0
        ? 0.0f
        : static_cast<float>(speech_frames) / static_cast<float>(total_frames);
    const bool speech_detected = speech_ratio > 0.1f;
    std::string transcription;

    if (speech_detected) {
        rac_stt_result_t stt_result{};
        rac_stt_options_t options = RAC_STT_OPTIONS_DEFAULT;
        options.sample_rate = static_cast<int32_t>(wav.sample_rate);
        status = rac_stt_component_transcribe(
            stt, wav.samples.data(), wav.samples.size() * sizeof(int16_t), &options, &stt_result);
        if (status == RAC_SUCCESS && stt_result.text) transcription = stt_result.text;
        rac_stt_result_free(&stt_result);
    }
    rac_stt_component_destroy(stt);

    result.details = "VAD speech frames: " + std::to_string(speech_frames) + "/" +
                     std::to_string(total_frames) + "; STT: \"" + transcription + "\"";
    result.actual = speech_detected ? "Speech detected" : "No speech detected";
    if (expect_speech) {
        result.passed = speech_detected && status == RAC_SUCCESS && !transcription.empty();
        if (result.passed && !expected_text.empty()) {
            std::string actual_lower = transcription;
            std::string expected_lower = expected_text;
            std::transform(actual_lower.begin(), actual_lower.end(), actual_lower.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
            std::transform(expected_lower.begin(), expected_lower.end(), expected_lower.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
            result.passed = actual_lower.find(expected_lower) != std::string::npos;
        }
    } else {
        result.passed = !speech_detected;
    }
    return result;
}

TestResult test_full_pipeline(const std::string& wav_path, bool expect_transcription) {
    TestResult result;
    result.test_name = "Continuous pipeline - " + wav_path;
    result.expected = expect_transcription ? "Final transcription callback" : "No transcription";

    WavFile wav;
    if (!read_wav(wav_path, wav) || wav.sample_rate != 16000) {
        result.actual = "Expected a readable 16 kHz PCM WAV file";
        return result;
    }

    std::string transcription;
    openclaw::VoicePipelineConfig config;
    config.silence_duration_sec = 1.0;
    config.min_speech_samples = 8000;
    config.debug_vad = false;
    config.debug_stt = false;
    config.on_transcription = [&](const std::string& text, bool is_final) {
        if (is_final) transcription = text;
    };
    config.on_error = [&](const std::string& error) { result.details += error + "\n"; };

    openclaw::VoicePipeline pipeline(config);
    if (!pipeline.initialize()) {
        result.actual = "Failed to initialize pipeline: " + pipeline.last_error();
        return result;
    }
    pipeline.start();

    constexpr size_t chunk_size = 256;
    for (size_t offset = 0; offset + chunk_size <= wav.samples.size(); offset += chunk_size) {
        pipeline.process_audio(wav.samples.data() + offset, chunk_size);
    }
    std::vector<int16_t> silence(chunk_size * 100, 0);
    for (size_t offset = 0; offset < silence.size(); offset += chunk_size) {
        pipeline.process_audio(silence.data() + offset, chunk_size);
    }
    pipeline.stop();

    const bool transcribed = !transcription.empty();
    result.actual = transcribed ? "Transcription: \"" + transcription + "\"" : "No transcription";
    result.passed = transcribed == expect_transcription;
    return result;
}

void print_usage(const char* program) {
    std::cout << "Usage: " << program << " [options]\n\n"
              << "  --test-vad-stt <wav>  Test VAD and STT components\n"
              << "  --test-full <wav>     Test continuous pipeline with speech\n"
              << "  --test-noise <wav>    Verify continuous pipeline rejects noise\n"
              << "  --run-all             Run the default fixture suite\n"
              << "  --help                Show this help\n";
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }
    if (!openclaw::init_model_system()) {
        std::cerr << "Failed to initialize model system\n";
        return 1;
    }
    if (rac_backend_sherpa_register() != RAC_SUCCESS) {
        std::cerr << "Failed to register Sherpa backend\n";
        return 1;
    }

    std::vector<TestResult> results;
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--help" || arg == "-h") {
            print_usage(argv[0]);
            return 0;
        } else if (arg == "--test-vad-stt" && i + 1 < argc) {
            results.push_back(test_vad_stt(argv[++i], true));
        } else if (arg == "--test-full" && i + 1 < argc) {
            results.push_back(test_full_pipeline(argv[++i], true));
        } else if (arg == "--test-noise" && i + 1 < argc) {
            results.push_back(test_full_pipeline(argv[++i], false));
        } else if (arg == "--run-all") {
            results.push_back(test_vad_stt("tests/audio/speech.wav", true, "weather"));
            results.push_back(test_vad_stt("tests/audio/silence.wav", false));
            results.push_back(test_full_pipeline("tests/audio/speech.wav", true));
            results.push_back(test_full_pipeline("tests/audio/noise.wav", false));
        } else {
            std::cerr << "Unknown or incomplete option: " << arg << '\n';
            return 1;
        }
    }

    int failures = 0;
    for (const auto& result : results) {
        print_result(result);
        if (!result.passed) ++failures;
    }
    std::cout << "\nTOTAL: " << results.size() - failures << " passed, "
              << failures << " failed\n";
    return failures == 0 ? 0 : 1;
}
