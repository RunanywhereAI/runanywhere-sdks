// =============================================================================
// test_pipeline.cpp — Feed a WAV file through the voice pipeline
// =============================================================================
// Usage: ./test-pipeline <input.wav>
//
// Bypasses ALSA audio capture and feeds a 16 kHz mono PCM WAV file through
// the same owned STT -> LLM -> TTS components used by the application.
// =============================================================================

#include "config/model_config.h"
#include "pipeline/voice_pipeline.h"

#include <rac/backends/rac_llm_llamacpp.h>
#include <rac/core/rac_error.h>
#include <rac/plugin/rac_plugin_entry_sherpa.h>

#include <cstdint>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

namespace {

constexpr uint32_t INPUT_SAMPLE_RATE = 16000;

bool read_wav(const std::string& path, std::vector<int16_t>& samples,
              uint32_t& sample_rate) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Cannot open: " << path << std::endl;
        return false;
    }

    char riff[4];
    file.read(riff, 4);
    if (!file || std::strncmp(riff, "RIFF", 4) != 0) {
        std::cerr << "Not a WAV file\n";
        return false;
    }

    uint32_t file_size = 0;
    file.read(reinterpret_cast<char*>(&file_size), 4);
    (void)file_size;
    char wave[4];
    file.read(wave, 4);
    if (!file || std::strncmp(wave, "WAVE", 4) != 0) {
        std::cerr << "Not a WAVE file\n";
        return false;
    }

    uint16_t num_channels = 0;
    uint16_t bits_per_sample = 0;
    sample_rate = 0;

    while (file) {
        char chunk_id[4];
        uint32_t chunk_size = 0;
        file.read(chunk_id, 4);
        file.read(reinterpret_cast<char*>(&chunk_size), 4);
        if (!file) {
            break;
        }

        if (std::strncmp(chunk_id, "fmt ", 4) == 0) {
            uint16_t audio_format = 0;
            file.read(reinterpret_cast<char*>(&audio_format), 2);
            file.read(reinterpret_cast<char*>(&num_channels), 2);
            file.read(reinterpret_cast<char*>(&sample_rate), 4);
            uint32_t byte_rate = 0;
            uint16_t block_align = 0;
            file.read(reinterpret_cast<char*>(&byte_rate), 4);
            file.read(reinterpret_cast<char*>(&block_align), 2);
            file.read(reinterpret_cast<char*>(&bits_per_sample), 2);
            (void)byte_rate;
            (void)block_align;
            if (audio_format != 1) {
                std::cerr << "Only PCM WAV files are supported\n";
                return false;
            }
            if (chunk_size > 16) {
                file.seekg(chunk_size - 16, std::ios::cur);
            }
        } else if (std::strncmp(chunk_id, "data", 4) == 0) {
            if (bits_per_sample != 16 || (num_channels != 1 && num_channels != 2)) {
                std::cerr << "Only 16-bit mono or stereo WAV files are supported\n";
                return false;
            }

            const size_t total_samples = chunk_size / sizeof(int16_t);
            const size_t num_frames = total_samples / num_channels;
            if (num_channels == 1) {
                samples.resize(num_frames);
                file.read(reinterpret_cast<char*>(samples.data()), chunk_size);
            } else {
                std::vector<int16_t> stereo(total_samples);
                file.read(reinterpret_cast<char*>(stereo.data()), chunk_size);
                samples.resize(num_frames);
                for (size_t i = 0; i < num_frames; ++i) {
                    samples[i] = static_cast<int16_t>(
                        (static_cast<int32_t>(stereo[i * 2]) + stereo[i * 2 + 1]) / 2);
                }
            }
            break;
        } else {
            file.seekg(chunk_size, std::ios::cur);
        }
    }

    if (!file && samples.empty()) {
        std::cerr << "WAV data is truncated or missing\n";
        return false;
    }

    std::cout << "WAV: " << sample_rate << " Hz, " << num_channels << " ch, "
              << bits_per_sample << " bit, " << samples.size() << " samples ("
              << static_cast<double>(samples.size()) / sample_rate << "s)\n";
    return !samples.empty();
}

bool write_wav(const std::string& path, const int16_t* samples, size_t num_samples,
               uint32_t sample_rate) {
    std::ofstream file(path, std::ios::binary);
    if (!file.is_open() || !samples || num_samples == 0 || sample_rate == 0) {
        return false;
    }

    const uint32_t data_size = static_cast<uint32_t>(num_samples * sizeof(int16_t));
    const uint32_t file_size = 36 + data_size;
    file.write("RIFF", 4);
    file.write(reinterpret_cast<const char*>(&file_size), 4);
    file.write("WAVE", 4);

    file.write("fmt ", 4);
    const uint32_t fmt_size = 16;
    const uint16_t audio_format = 1;
    const uint16_t channels = 1;
    const uint32_t byte_rate = sample_rate * sizeof(int16_t);
    const uint16_t block_align = sizeof(int16_t);
    const uint16_t bits = 16;
    file.write(reinterpret_cast<const char*>(&fmt_size), 4);
    file.write(reinterpret_cast<const char*>(&audio_format), 2);
    file.write(reinterpret_cast<const char*>(&channels), 2);
    file.write(reinterpret_cast<const char*>(&sample_rate), 4);
    file.write(reinterpret_cast<const char*>(&byte_rate), 4);
    file.write(reinterpret_cast<const char*>(&block_align), 2);
    file.write(reinterpret_cast<const char*>(&bits), 2);

    file.write("data", 4);
    file.write(reinterpret_cast<const char*>(&data_size), 4);
    file.write(reinterpret_cast<const char*>(samples), data_size);
    return static_cast<bool>(file);
}

}  // namespace

int main(int argc, char* argv[]) {
    if (argc != 2) {
        std::cerr << "Usage: " << argv[0] << " <input.wav>\n";
        return 1;
    }

    std::vector<int16_t> input_samples;
    uint32_t input_sample_rate = 0;
    if (!read_wav(argv[1], input_samples, input_sample_rate)) {
        return 1;
    }
    if (input_sample_rate != INPUT_SAMPLE_RATE) {
        std::cerr << "Input must be 16 kHz PCM; got " << input_sample_rate << " Hz\n";
        return 1;
    }

    std::cout << "\n=== Registering backends ===\n";
    rac_result_t result = rac_backend_sherpa_register();
    std::cout << "Sherpa backend: " << (result == RAC_SUCCESS ? "OK" : "FAILED") << "\n";
    if (result != RAC_SUCCESS) {
        return 1;
    }
    result = rac_backend_llamacpp_register();
    std::cout << "LlamaCPP backend: " << (result == RAC_SUCCESS ? "OK" : "FAILED") << "\n";
    if (result != RAC_SUCCESS) {
        return 1;
    }

    std::string transcription;
    std::string response;
    std::string pipeline_error;
    std::vector<int16_t> output_samples;
    int output_sample_rate = 0;

    runanywhere::VoicePipelineConfig config;
    config.on_transcription = [&](const std::string& text, bool is_final) {
        if (is_final) {
            transcription = text;
        }
    };
    config.on_response = [&](const std::string& text, bool is_complete) {
        if (is_complete) {
            response = text;
        }
    };
    config.on_audio_output = [&](const int16_t* samples, size_t count, int sample_rate) {
        output_samples.assign(samples, samples + count);
        output_sample_rate = sample_rate;
    };
    config.on_error = [&](const std::string& error) {
        pipeline_error = error;
    };

    std::cout << "\n=== Initializing pipeline ===\n";
    runanywhere::VoicePipeline pipeline(config);
    if (!pipeline.initialize()) {
        std::cerr << "Pipeline initialization failed: " << pipeline.last_error() << "\n";
        return 1;
    }

    std::cout << "\n=== Processing voice turn ===\n";
    if (!pipeline.process_voice_turn(input_samples.data(), input_samples.size())) {
        std::cerr << "Pipeline failed";
        if (!pipeline_error.empty()) {
            std::cerr << ": " << pipeline_error;
        }
        std::cerr << "\n";
        return 1;
    }

    std::cout << "\n=== Results ===\n"
              << "Transcription: \"" << transcription << "\"\n"
              << "LLM Response: \"" << response << "\"\n"
              << "TTS Audio: " << output_samples.size() << " samples at "
              << output_sample_rate << " Hz\n";

    const std::string output_path = "/tmp/tts_output.wav";
    if (!write_wav(output_path, output_samples.data(), output_samples.size(),
                   static_cast<uint32_t>(output_sample_rate))) {
        std::cerr << "Failed to write TTS output\n";
        return 1;
    }

    std::cout << "TTS output saved to: " << output_path << "\n"
              << "\n=== Done ===\n";
    return 0;
}
