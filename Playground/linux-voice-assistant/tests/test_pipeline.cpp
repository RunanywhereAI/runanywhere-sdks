// =============================================================================
// test_pipeline.cpp — Feed a WAV file through the voice pipeline
// =============================================================================
// Usage: ./test-pipeline <input.wav>
//
// Bypasses ALSA audio capture, reads a 16kHz mono 16-bit WAV file, and feeds
// the audio directly through the full pipeline: VAD → STT → LLM → TTS
// =============================================================================

#include "config/model_config.h"

#include <rac/backends/rac_vad_onnx.h>
#include <rac/backends/rac_llm_llamacpp.h>
#include <rac/features/voice_agent/rac_voice_agent.h>
#include <rac/features/stt/rac_stt_component.h>
#include <rac/features/tts/rac_tts_component.h>
#include <rac/features/vad/rac_vad_component.h>
#include <rac/features/llm/rac_llm_component.h>
#include <rac/core/rac_error.h>

#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <cstring>

static constexpr uint32_t TTS_SAMPLE_RATE = 22050;

// Read a 16-bit PCM WAV file, return samples
bool read_wav(const std::string& path, std::vector<int16_t>& samples, uint32_t& sample_rate) {
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Cannot open: " << path << std::endl;
        return false;
    }

    // Read WAV header
    char riff[4]; file.read(riff, 4);
    if (strncmp(riff, "RIFF", 4) != 0) { std::cerr << "Not a WAV file\n"; return false; }

    uint32_t file_size; file.read(reinterpret_cast<char*>(&file_size), 4);
    char wave[4]; file.read(wave, 4);
    if (strncmp(wave, "WAVE", 4) != 0) { std::cerr << "Not a WAVE file\n"; return false; }

    // Find fmt and data chunks
    uint16_t num_channels = 0, bits_per_sample = 0;
    sample_rate = 0;

    while (file.good()) {
        char chunk_id[4]; file.read(chunk_id, 4);
        uint32_t chunk_size; file.read(reinterpret_cast<char*>(&chunk_size), 4);

        if (strncmp(chunk_id, "fmt ", 4) == 0) {
            uint16_t audio_format;
            file.read(reinterpret_cast<char*>(&audio_format), 2);
            file.read(reinterpret_cast<char*>(&num_channels), 2);
            file.read(reinterpret_cast<char*>(&sample_rate), 4);
            uint32_t byte_rate; file.read(reinterpret_cast<char*>(&byte_rate), 4);
            uint16_t block_align; file.read(reinterpret_cast<char*>(&block_align), 2);
            file.read(reinterpret_cast<char*>(&bits_per_sample), 2);
            // Skip any extra fmt bytes
            if (chunk_size > 16) {
                file.seekg(chunk_size - 16, std::ios::cur);
            }
        } else if (strncmp(chunk_id, "data", 4) == 0) {
            if (bits_per_sample != 16) {
                std::cerr << "Only 16-bit WAV supported\n";
                return false;
            }
            size_t total_samples = chunk_size / sizeof(int16_t);
            size_t num_frames = total_samples / num_channels;
            if (num_channels == 1) {
                samples.resize(num_frames);
                file.read(reinterpret_cast<char*>(samples.data()), chunk_size);
            } else if (num_channels == 2) {
                std::vector<int16_t> stereo(total_samples);
                file.read(reinterpret_cast<char*>(stereo.data()), chunk_size);
                samples.resize(num_frames);
                for (size_t i = 0; i < num_frames; ++i) {
                    samples[i] = static_cast<int16_t>(
                        (static_cast<int32_t>(stereo[i*2]) + stereo[i*2+1]) / 2);
                }
            } else {
                std::cerr << "Unsupported channel count: " << num_channels << "\n";
                return false;
            }
            break;
        } else {
            file.seekg(chunk_size, std::ios::cur);
        }
    }

    std::cout << "WAV: " << sample_rate << " Hz, " << num_channels << " ch, "
              << bits_per_sample << " bit, " << samples.size() << " samples ("
              << (float)samples.size() / sample_rate << "s)\n";
    return !samples.empty();
}

// Write a WAV file from int16 samples
bool write_wav(const std::string& path, const int16_t* samples, size_t num_samples, uint32_t sample_rate) {
    std::ofstream file(path, std::ios::binary);
    if (!file.is_open()) return false;

    uint32_t data_size = num_samples * sizeof(int16_t);
    uint32_t file_size = 36 + data_size;

    file.write("RIFF", 4);
    file.write(reinterpret_cast<char*>(&file_size), 4);
    file.write("WAVE", 4);

    // fmt chunk
    file.write("fmt ", 4);
    uint32_t fmt_size = 16; file.write(reinterpret_cast<char*>(&fmt_size), 4);
    uint16_t audio_format = 1; file.write(reinterpret_cast<char*>(&audio_format), 2);
    uint16_t channels = 1; file.write(reinterpret_cast<char*>(&channels), 2);
    file.write(reinterpret_cast<const char*>(&sample_rate), 4);
    uint32_t byte_rate = sample_rate * 2; file.write(reinterpret_cast<char*>(&byte_rate), 4);
    uint16_t block_align = 2; file.write(reinterpret_cast<char*>(&block_align), 2);
    uint16_t bits = 16; file.write(reinterpret_cast<char*>(&bits), 2);

    // data chunk
    file.write("data", 4);
    file.write(reinterpret_cast<char*>(&data_size), 4);
    file.write(reinterpret_cast<const char*>(samples), data_size);

    return true;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <input.wav>\n";
        return 1;
    }

    std::string input_path = argv[1];

    // --- Read input WAV ---
    std::vector<int16_t> samples;
    uint32_t sample_rate;
    if (!read_wav(input_path, samples, sample_rate)) {
        return 1;
    }

    // --- Register backends ---
    std::cout << "\n=== Registering backends ===\n";
    rac_result_t res = rac_backend_onnx_register();
    std::cout << "ONNX backend: " << (res == RAC_SUCCESS ? "OK" : "FAILED") << "\n";
    res = rac_backend_llamacpp_register();
    std::cout << "LlamaCPP backend: " << (res == RAC_SUCCESS ? "OK" : "FAILED") << "\n";

    // --- Create voice agent ---
    std::cout << "\n=== Creating voice agent ===\n";
    rac_voice_agent_handle_t agent = nullptr;
    res = rac_voice_agent_create_standalone(&agent);
    if (res != RAC_SUCCESS) {
        std::cerr << "Failed to create voice agent: " << res << "\n";
        return 1;
    }

    // --- Load models ---
    std::cout << "\n=== Loading models ===\n";

    std::string stt_path = runanywhere::get_stt_model_path();
    std::string llm_path = runanywhere::get_llm_model_path();
    std::string tts_path = runanywhere::get_tts_model_path();

    std::cout << "STT path: " << stt_path << "\n";
    std::cout << "LLM path: " << llm_path << "\n";
    std::cout << "TTS path: " << tts_path << "\n";

    std::cout << "\nLoading STT...\n";
    res = rac_voice_agent_load_stt_model(agent, stt_path.c_str(), "whisper-tiny-en", "Whisper Tiny EN");
    std::cout << "STT: " << (res == RAC_SUCCESS ? "OK" : "FAILED") << " (code: " << res << ")\n";
    if (res != RAC_SUCCESS) { rac_voice_agent_destroy(agent); return 1; }

    std::cout << "\nLoading LLM...\n";
    res = rac_voice_agent_load_llm_model(agent, llm_path.c_str(), "qwen2.5", "Qwen2.5 0.5B");
    std::cout << "LLM: " << (res == RAC_SUCCESS ? "OK" : "FAILED") << " (code: " << res << ")\n";
    if (res != RAC_SUCCESS) { rac_voice_agent_destroy(agent); return 1; }

    std::cout << "\nLoading TTS...\n";
    res = rac_voice_agent_load_tts_voice(agent, tts_path.c_str(), "piper-lessac", "Piper Lessac");
    std::cout << "TTS: " << (res == RAC_SUCCESS ? "OK" : "FAILED") << " (code: " << res << ")\n";
    if (res != RAC_SUCCESS) { rac_voice_agent_destroy(agent); return 1; }

    std::cout << "\nInitializing with loaded models...\n";
    res = rac_voice_agent_initialize_with_loaded_models(agent);
    std::cout << "Init: " << (res == RAC_SUCCESS ? "OK" : "FAILED") << " (code: " << res << ")\n";
    if (res != RAC_SUCCESS) { rac_voice_agent_destroy(agent); return 1; }

    // --- Process the full audio as one voice turn ---
    std::cout << "\n=== Processing voice turn ===\n";
    std::cout << "Feeding " << samples.size() << " samples ("
              << (float)samples.size() / sample_rate << "s) to STT→LLM→TTS pipeline...\n\n";

    rac_voice_agent_result_t result = {};
    res = rac_voice_agent_process_voice_turn(
        agent,
        samples.data(),
        samples.size() * sizeof(int16_t),
        &result
    );

    std::cout << "\n=== Results ===\n";
    std::cout << "Status: " << (res == RAC_SUCCESS ? "OK" : "FAILED") << " (code: " << res << ")\n";

    if (result.transcription) {
        std::cout << "Transcription: \"" << result.transcription << "\"\n";
    } else {
        std::cout << "Transcription: (null)\n";
    }

    if (result.response) {
        std::cout << "LLM Response: \"" << result.response << "\"\n";
    } else {
        std::cout << "LLM Response: (null)\n";
    }

    if (result.synthesized_audio && result.synthesized_audio_size > 0) {
        size_t tts_samples = result.synthesized_audio_size / sizeof(int16_t);
        std::cout << "TTS Audio: " << tts_samples << " samples ("
                  << (float)tts_samples / TTS_SAMPLE_RATE << "s at " << TTS_SAMPLE_RATE << "Hz)\n";

        // Save TTS output
        std::string out_path = "/tmp/tts_output.wav";
        if (write_wav(out_path, static_cast<const int16_t*>(result.synthesized_audio), tts_samples, TTS_SAMPLE_RATE)) {
            std::cout << "TTS output saved to: " << out_path << "\n";
        }
    } else {
        std::cout << "TTS Audio: (none)\n";
    }

    rac_voice_agent_result_free(&result);
    rac_voice_agent_destroy(agent);

    std::cout << "\n=== Done ===\n";
    return 0;
}
