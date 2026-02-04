// =============================================================================
// test_components.cpp - Test Wake Word, VAD, and ASR with WAV files
// =============================================================================
// Tests the voice pipeline components individually and together using the
// VoicePipeline class which wraps the RAC voice_agent API.
//
// Usage:
//   ./test-components --test-wakeword tests/audio/hey-jarvis.wav
//   ./test-components --test-vad tests/audio/speech.wav
//   ./test-components --test-stt tests/audio/speech.wav
//   ./test-components --test-full tests/audio/wakeword-plus-speech.wav
//   ./test-components --test-noise tests/audio/noise.wav
//   ./test-components --run-all
// =============================================================================

#include "model_config.h"
#include "voice_pipeline.h"

// RAC headers for wake word testing
#include <rac/backends/rac_vad_onnx.h>
#include <rac/backends/rac_wakeword_onnx.h>
#include <rac/features/voice_agent/rac_voice_agent.h>
#include <rac/core/rac_error.h>

#include <iostream>
#include <fstream>
#include <vector>
#include <cstdint>
#include <cstring>
#include <chrono>
#include <thread>

// =============================================================================
// WAV File Reader
// =============================================================================

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
        std::cerr << "Cannot open: " << path << std::endl;
        return false;
    }

    // Read RIFF header
    char riff[4];
    file.read(riff, 4);
    if (strncmp(riff, "RIFF", 4) != 0) {
        std::cerr << "Not a WAV file (no RIFF header)\n";
        return false;
    }

    uint32_t file_size;
    file.read(reinterpret_cast<char*>(&file_size), 4);

    char wave[4];
    file.read(wave, 4);
    if (strncmp(wave, "WAVE", 4) != 0) {
        std::cerr << "Not a WAVE file\n";
        return false;
    }

    // Find fmt and data chunks
    while (file.good()) {
        char chunk_id[4];
        file.read(chunk_id, 4);
        uint32_t chunk_size;
        file.read(reinterpret_cast<char*>(&chunk_size), 4);

        if (strncmp(chunk_id, "fmt ", 4) == 0) {
            uint16_t audio_format;
            file.read(reinterpret_cast<char*>(&audio_format), 2);
            file.read(reinterpret_cast<char*>(&wav.channels), 2);
            file.read(reinterpret_cast<char*>(&wav.sample_rate), 4);
            uint32_t byte_rate;
            file.read(reinterpret_cast<char*>(&byte_rate), 4);
            uint16_t block_align;
            file.read(reinterpret_cast<char*>(&block_align), 2);
            file.read(reinterpret_cast<char*>(&wav.bits_per_sample), 2);

            // Skip extra fmt bytes
            if (chunk_size > 16) {
                file.seekg(chunk_size - 16, std::ios::cur);
            }
        } else if (strncmp(chunk_id, "data", 4) == 0) {
            size_t num_samples = chunk_size / (wav.bits_per_sample / 8) / wav.channels;
            wav.samples.resize(num_samples);
            file.read(reinterpret_cast<char*>(wav.samples.data()), chunk_size);
            break;
        } else {
            file.seekg(chunk_size, std::ios::cur);
        }
    }

    wav.duration_sec = static_cast<float>(wav.samples.size()) / wav.sample_rate;

    std::cout << "WAV: " << path << "\n"
              << "  Sample rate: " << wav.sample_rate << " Hz\n"
              << "  Channels: " << wav.channels << "\n"
              << "  Bits: " << wav.bits_per_sample << "\n"
              << "  Samples: " << wav.samples.size() << "\n"
              << "  Duration: " << wav.duration_sec << "s\n";

    return !wav.samples.empty();
}

// =============================================================================
// Test Results
// =============================================================================

struct TestResult {
    std::string test_name;
    bool passed = false;
    std::string expected;
    std::string actual;
    std::string details;
};

void print_result(const TestResult& result) {
    std::cout << "\n" << (result.passed ? "✅ PASS" : "❌ FAIL")
              << ": " << result.test_name << "\n";
    if (!result.expected.empty()) {
        std::cout << "  Expected: " << result.expected << "\n";
    }
    if (!result.actual.empty()) {
        std::cout << "  Actual:   " << result.actual << "\n";
    }
    if (!result.details.empty()) {
        std::cout << "  Details:  " << result.details << "\n";
    }
}

// =============================================================================
// Test: Wake Word Detection (using RAC wake word API directly)
// =============================================================================

TestResult test_wakeword(const std::string& wav_path, bool expect_detection) {
    TestResult result;
    result.test_name = "Wake Word Detection - " + wav_path;
    result.expected = expect_detection ? "Wake word detected" : "No wake word";

    WavFile wav;
    if (!read_wav(wav_path, wav)) {
        result.actual = "Failed to read WAV file";
        return result;
    }

    // Check sample rate
    if (wav.sample_rate != 16000) {
        result.actual = "Wrong sample rate: " + std::to_string(wav.sample_rate) + " (need 16000)";
        return result;
    }

    // Initialize wake word detector
    // NOTE: Threshold 0.5 is recommended for production to avoid false positives
    // Lower values increase sensitivity but also false positive rate
    rac_wakeword_onnx_config_t config = RAC_WAKEWORD_ONNX_CONFIG_DEFAULT;
    config.threshold = 0.5f;  // Production threshold for good balance

    rac_handle_t handle = nullptr;
    rac_result_t res = rac_wakeword_onnx_create(&config, &handle);
    if (res != RAC_SUCCESS) {
        result.actual = "Failed to create wake word detector (code: " + std::to_string(res) + ")";
        return result;
    }

    // Load models
    std::string embedding_path = openclaw::get_wakeword_embedding_path();
    std::string melspec_path = openclaw::get_wakeword_melspec_path();
    std::string wakeword_path = openclaw::get_wakeword_model_path();

    res = rac_wakeword_onnx_init_shared_models(handle, embedding_path.c_str(), melspec_path.c_str());
    if (res != RAC_SUCCESS) {
        result.actual = "Failed to load embedding model (code: " + std::to_string(res) + ")";
        rac_wakeword_onnx_destroy(handle);
        return result;
    }

    res = rac_wakeword_onnx_load_model(handle, wakeword_path.c_str(), "hey-jarvis", "Hey Jarvis");
    if (res != RAC_SUCCESS) {
        result.actual = "Failed to load wake word model (code: " + std::to_string(res) + ")";
        rac_wakeword_onnx_destroy(handle);
        return result;
    }

    // Process audio in chunks (80ms = 1280 samples at 16kHz)
    const size_t chunk_size = 1280;
    std::vector<float> float_samples(chunk_size);

    bool detected = false;
    float max_confidence = 0.0f;
    int detection_frame = -1;
    int total_frames = 0;

    std::cout << "  Processing " << wav.samples.size() << " samples in "
              << chunk_size << "-sample chunks..." << std::endl;
    std::cout << "  Embedding path: " << embedding_path << std::endl;
    std::cout << "  Melspec path: " << melspec_path << std::endl;
    std::cout << "  Wakeword path: " << wakeword_path << std::endl;

    for (size_t offset = 0; offset + chunk_size <= wav.samples.size(); offset += chunk_size) {
        // Convert to float WITHOUT normalizing - openWakeWord expects raw int16 values cast to float
        for (size_t i = 0; i < chunk_size; ++i) {
            float_samples[i] = static_cast<float>(wav.samples[offset + i]);
        }

        int32_t detected_index = -1;
        float confidence = 0.0f;

        res = rac_wakeword_onnx_process(handle, float_samples.data(), chunk_size, &detected_index, &confidence);
        total_frames++;

        // Print every 10th frame's confidence
        if (total_frames % 10 == 0 || confidence > 0.01f) {
            std::cout << "  Frame " << total_frames << " (t=" << offset / 16000.0f
                      << "s): conf=" << confidence << std::endl;
        }

        if (confidence > max_confidence) {
            max_confidence = confidence;
        }

        if (res == RAC_SUCCESS && detected_index >= 0) {
            detected = true;
            detection_frame = total_frames;
            result.details = "Detected at frame " + std::to_string(detection_frame) +
                           " (t=" + std::to_string(offset / 16000.0f) + "s), confidence=" +
                           std::to_string(confidence);
            std::cout << "  >>> DETECTED! confidence=" << confidence << std::endl;
            break;
        }
    }

    std::cout << "  Processed " << total_frames << " frames, max confidence: " << max_confidence << std::endl;

    rac_wakeword_onnx_destroy(handle);

    result.actual = detected ? "Wake word detected (max conf=" + std::to_string(max_confidence) + ")"
                            : "No wake word (max conf=" + std::to_string(max_confidence) + ")";
    result.passed = (detected == expect_detection);

    return result;
}

// =============================================================================
// Test: VAD + STT using VoicePipeline
// =============================================================================

TestResult test_vad_stt(const std::string& wav_path, bool expect_speech, const std::string& expected_text = "") {
    TestResult result;
    result.test_name = "VAD+STT - " + wav_path;
    result.expected = expect_speech ? "Speech detected and transcribed" : "No speech";

    WavFile wav;
    if (!read_wav(wav_path, wav)) {
        result.actual = "Failed to read WAV file";
        return result;
    }

    if (wav.sample_rate != 16000) {
        result.actual = "Wrong sample rate";
        return result;
    }

    // Create a voice agent just for STT
    rac_voice_agent_handle_t agent = nullptr;
    rac_result_t res = rac_voice_agent_create_standalone(&agent);
    if (res != RAC_SUCCESS) {
        result.actual = "Failed to create voice agent";
        return result;
    }

    // Load STT model
    std::string stt_path = openclaw::get_stt_model_path();
    res = rac_voice_agent_load_stt_model(agent, stt_path.c_str(), "whisper-tiny-en", "Whisper");
    if (res != RAC_SUCCESS) {
        result.actual = "Failed to load STT model";
        rac_voice_agent_destroy(agent);
        return result;
    }

    // Load TTS (required for initialization even if not used)
    std::string tts_path = openclaw::get_tts_model_path();
    res = rac_voice_agent_load_tts_voice(agent, tts_path.c_str(), "piper", "Piper");
    if (res != RAC_SUCCESS) {
        result.actual = "Failed to load TTS";
        rac_voice_agent_destroy(agent);
        return result;
    }

    res = rac_voice_agent_initialize_with_loaded_models(agent);
    if (res != RAC_SUCCESS) {
        result.actual = "Failed to initialize";
        rac_voice_agent_destroy(agent);
        return result;
    }

    // Check VAD on the audio
    const size_t chunk_size = 512;
    std::vector<float> float_samples(chunk_size);
    int speech_frames = 0;
    int total_frames = 0;

    for (size_t offset = 0; offset + chunk_size <= wav.samples.size(); offset += chunk_size) {
        for (size_t i = 0; i < chunk_size; ++i) {
            float_samples[i] = wav.samples[offset + i] / 32768.0f;
        }

        rac_bool_t is_speech = RAC_FALSE;
        rac_voice_agent_detect_speech(agent, float_samples.data(), chunk_size, &is_speech);

        if (is_speech == RAC_TRUE) {
            speech_frames++;
        }
        total_frames++;
    }

    float speech_ratio = total_frames > 0 ? static_cast<float>(speech_frames) / total_frames : 0;
    bool speech_detected = (speech_ratio > 0.1f);

    result.details = "VAD: " + std::to_string(speech_frames) + "/" + std::to_string(total_frames) +
                    " frames (" + std::to_string(speech_ratio * 100) + "% speech)";

    // Try STT if speech detected
    std::string transcription;
    if (speech_detected) {
        char* transcription_ptr = nullptr;
        res = rac_voice_agent_transcribe(agent, wav.samples.data(), wav.samples.size() * sizeof(int16_t), &transcription_ptr);

        if (res == RAC_SUCCESS && transcription_ptr && strlen(transcription_ptr) > 0) {
            transcription = transcription_ptr;
            result.details += "\nSTT: \"" + transcription + "\"";
        }
        if (transcription_ptr) {
            free(transcription_ptr);
        }
    }

    rac_voice_agent_destroy(agent);

    result.actual = speech_detected ? "Speech detected: \"" + transcription + "\"" : "No speech detected";

    if (expect_speech) {
        result.passed = speech_detected && !transcription.empty();
        if (!expected_text.empty() && result.passed) {
            // Check if expected text is in transcription (case-insensitive)
            std::string lower_trans = transcription;
            std::string lower_expected = expected_text;
            for (auto& c : lower_trans) c = tolower(c);
            for (auto& c : lower_expected) c = tolower(c);
            result.passed = (lower_trans.find(lower_expected) != std::string::npos);
        }
    } else {
        result.passed = !speech_detected;
    }

    return result;
}

// =============================================================================
// Test: Full Pipeline (Wake Word + VAD + STT)
// =============================================================================

TestResult test_full_pipeline(const std::string& wav_path,
                              bool expect_wakeword,
                              bool expect_transcription,
                              const std::string& expected_text = "") {
    TestResult result;
    result.test_name = "Full Pipeline - " + wav_path;

    std::string expected;
    if (expect_wakeword && expect_transcription) {
        expected = "Wake word + transcription sent to OpenClaw";
    } else if (expect_wakeword) {
        expected = "Wake word only (NO transcription - not enough speech)";
    } else {
        expected = "No activation (wake word not detected)";
    }
    result.expected = expected;

    WavFile wav;
    if (!read_wav(wav_path, wav)) {
        result.actual = "Failed to read WAV file";
        return result;
    }

    // Track pipeline events
    bool wakeword_detected = false;
    bool voice_activity_started = false;
    bool voice_activity_ended = false;
    std::string transcription;
    bool transcription_sent = false;

    // Configure pipeline
    openclaw::VoicePipelineConfig config;
    config.enable_wake_word = true;
    config.wake_word = "Hey Jarvis";
    config.wake_word_threshold = 0.5f;
    config.silence_duration_sec = 1.0;  // Shorter for testing
    config.min_speech_samples = 8000;   // 0.5s minimum
    config.debug_wakeword = false;
    config.debug_vad = false;
    config.debug_stt = false;

    config.on_wake_word = [&](const std::string& word, float confidence) {
        wakeword_detected = true;
        result.details += "Wake word detected (conf=" + std::to_string(confidence) + ")\n";
    };

    config.on_voice_activity = [&](bool active) {
        if (active) {
            voice_activity_started = true;
            result.details += "Voice activity started\n";
        } else {
            voice_activity_ended = true;
            result.details += "Voice activity ended\n";
        }
    };

    config.on_transcription = [&](const std::string& text, bool is_final) {
        if (is_final && !text.empty()) {
            transcription = text;
            transcription_sent = true;
            result.details += "Transcription SENT: \"" + text + "\"\n";
        }
    };

    config.on_error = [&](const std::string& error) {
        result.details += "Error: " + error + "\n";
    };

    // Initialize pipeline
    openclaw::VoicePipeline pipeline(config);
    if (!pipeline.initialize()) {
        result.actual = "Failed to initialize pipeline: " + pipeline.last_error();
        return result;
    }

    pipeline.start();

    // Feed audio in chunks (simulating real-time)
    const size_t chunk_size = 256;  // Same as audio capture period
    for (size_t offset = 0; offset + chunk_size <= wav.samples.size(); offset += chunk_size) {
        pipeline.process_audio(wav.samples.data() + offset, chunk_size);
    }

    // Feed silence to trigger end of speech detection
    std::vector<int16_t> silence(chunk_size * 100, 0);  // ~6 seconds of silence
    for (size_t offset = 0; offset + chunk_size <= silence.size(); offset += chunk_size) {
        pipeline.process_audio(silence.data() + offset, chunk_size);
    }

    pipeline.stop();

    // Evaluate results
    std::string actual;
    if (wakeword_detected) {
        actual += "Wake word DETECTED. ";
    } else {
        actual += "Wake word NOT detected. ";
    }

    if (transcription_sent) {
        actual += "Transcription SENT: \"" + transcription + "\"";
    } else {
        actual += "Transcription NOT sent.";
    }

    result.actual = actual;

    // Check expectations
    bool correct = true;
    if (expect_wakeword && !wakeword_detected) {
        correct = false;
    }
    if (!expect_wakeword && wakeword_detected) {
        correct = false;
    }
    if (expect_transcription && !transcription_sent) {
        correct = false;
    }
    if (!expect_transcription && transcription_sent) {
        correct = false;  // CRITICAL: Should NOT send transcription
    }

    result.passed = correct;
    return result;
}

// =============================================================================
// Main
// =============================================================================

void print_usage(const char* prog) {
    std::cout << "Usage: " << prog << " [options]\n\n"
              << "Options:\n"
              << "  --test-wakeword <wav>    Test wake word detection (expect detection)\n"
              << "  --test-no-wakeword <wav> Test wake word detection (expect NO detection)\n"
              << "  --test-vad-stt <wav>     Test VAD + STT\n"
              << "  --test-full <wav>        Test full pipeline (wake word + speech)\n"
              << "  --test-wakeword-only <wav> Test wake word only (should NOT send to OpenClaw)\n"
              << "  --test-noise <wav>       Test noise (should NOT trigger anything)\n"
              << "  --run-all                Run all tests with tests/audio/ files\n"
              << "  --help                   Show this help\n";
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    // Initialize model system
    if (!openclaw::init_model_system()) {
        std::cerr << "Failed to initialize model system\n";
        return 1;
    }

    // Register backends
    rac_backend_onnx_register();
    rac_backend_wakeword_onnx_register();

    std::vector<TestResult> results;

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];

        if (arg == "--help" || arg == "-h") {
            print_usage(argv[0]);
            return 0;
        }
        else if (arg == "--test-wakeword" && i + 1 < argc) {
            results.push_back(test_wakeword(argv[++i], true));
        }
        else if (arg == "--test-no-wakeword" && i + 1 < argc) {
            results.push_back(test_wakeword(argv[++i], false));
        }
        else if (arg == "--test-vad-stt" && i + 1 < argc) {
            results.push_back(test_vad_stt(argv[++i], true));
        }
        else if (arg == "--test-full" && i + 1 < argc) {
            results.push_back(test_full_pipeline(argv[++i], true, true));
        }
        else if (arg == "--test-wakeword-only" && i + 1 < argc) {
            // Wake word detected but NO speech after - should NOT send to OpenClaw
            results.push_back(test_full_pipeline(argv[++i], true, false));
        }
        else if (arg == "--test-noise" && i + 1 < argc) {
            // Noise only - should NOT trigger wake word or send anything
            results.push_back(test_full_pipeline(argv[++i], false, false));
        }
        else if (arg == "--run-all") {
            std::cout << "\n" << std::string(60, '=') << "\n"
                      << "  COMPREHENSIVE TEST SUITE\n"
                      << "  OpenClaw Hybrid Assistant\n"
                      << std::string(60, '=') << "\n\n";

            std::cout << "NOTE: TTS-generated 'Hey Jarvis' audio may not trigger wake word\n";
            std::cout << "      detection as the model was trained on human voices.\n";
            std::cout << "      For accurate wake word testing, use real human recordings.\n\n";

            // ================================================================
            // SECTION 1: WAKE WORD REJECTION TESTS (should NOT trigger)
            // ================================================================
            std::cout << "\n--- SECTION 1: WAKE WORD REJECTION TESTS ---\n\n";

            // Test 1.1: TTS-generated Hey Jarvis (informational - may not work)
            std::cout << "Test 1.1: TTS 'Hey Jarvis' (may not match human speech)\n";
            auto tts_result = test_wakeword("tests/audio/hey-jarvis.wav", true);
            tts_result.test_name += " [TTS - informational]";
            // Don't add to pass/fail - just informational
            std::cout << "  Result: " << (tts_result.passed ? "Detected" : "Not detected (expected for TTS)") << "\n";

            // Test 1.2: Pink noise should NOT trigger
            std::cout << "\nTest 1.2: Pink noise should NOT trigger wake word\n";
            results.push_back(test_wakeword("tests/audio/noise.wav", false));

            // Test 1.3: White noise should NOT trigger
            std::cout << "\nTest 1.3: White noise should NOT trigger wake word\n";
            results.push_back(test_wakeword("tests/audio/white-noise.wav", false));

            // Test 1.4: Silence should NOT trigger
            std::cout << "\nTest 1.4: Silence should NOT trigger wake word\n";
            results.push_back(test_wakeword("tests/audio/silence.wav", false));

            // Test 1.5: Random words should NOT trigger
            std::cout << "\nTest 1.5: Random words should NOT trigger wake word\n";
            results.push_back(test_wakeword("tests/audio/random-words.wav", false));

            // Test 1.6: Similar sounding words should NOT trigger
            std::cout << "\nTest 1.6: Similar words (Hey Travis, etc.) should NOT trigger\n";
            results.push_back(test_wakeword("tests/audio/similar-words.wav", false));

            // ================================================================
            // SECTION 2: VAD + STT TESTS (Core Functionality)
            // ================================================================
            std::cout << "\n--- SECTION 2: VAD + STT (CORE) ---\n\n";

            // Test 2.1: Speech should be detected and transcribed
            std::cout << "Test 2.1: Speech should be transcribed (contains 'weather')\n";
            results.push_back(test_vad_stt("tests/audio/speech.wav", true, "weather"));

            // Test 2.2: Silence should NOT produce transcription
            std::cout << "\nTest 2.2: Silence should NOT produce speech\n";
            results.push_back(test_vad_stt("tests/audio/silence.wav", false));

            // ================================================================
            // SECTION 3: PIPELINE REJECTION TESTS (Critical for Safety)
            // ================================================================
            std::cout << "\n--- SECTION 3: PIPELINE REJECTION TESTS ---\n\n";

            // Test 3.1: CRITICAL - Noise should NOT trigger anything
            std::cout << "Test 3.1: [CRITICAL] Noise only -> should NOT trigger wake word\n";
            results.push_back(test_full_pipeline("tests/audio/noise.wav", false, false));

            // Test 3.2: Silence should NOT trigger anything
            std::cout << "\nTest 3.2: Silence -> should NOT trigger anything\n";
            results.push_back(test_full_pipeline("tests/audio/silence.wav", false, false));

            // Test 3.3: Random speech without wake word -> should NOT activate
            std::cout << "\nTest 3.3: Random speech (no wake word) -> should NOT activate\n";
            results.push_back(test_full_pipeline("tests/audio/random-words.wav", false, false));

            // ================================================================
            // SECTION 4: WAKE WORD + PIPELINE (Informational with TTS audio)
            // ================================================================
            std::cout << "\n--- SECTION 4: WAKE WORD PIPELINE (TTS - Informational) ---\n\n";
            std::cout << "NOTE: These tests use TTS audio which may not trigger wake word.\n";
            std::cout << "      For production testing, use real human recordings.\n\n";

            // Test 4.1: Wake word + speech (TTS)
            std::cout << "Test 4.1: TTS Wake word + speech (informational)\n";
            auto test_ww_speech = test_full_pipeline("tests/audio/wakeword-plus-speech.wav", true, true);
            std::cout << "  Status: " << (test_ww_speech.passed ? "Working with TTS!" : "TTS audio not detected (expected)") << "\n";

            // Test 4.2: Wake word only (TTS)
            std::cout << "\nTest 4.2: TTS Wake word only (informational)\n";
            auto test_ww_only = test_full_pipeline("tests/audio/hey-jarvis.wav", true, false);
            std::cout << "  Status: " << (test_ww_only.passed ? "Working with TTS!" : "TTS audio not detected (expected)") << "\n";
        }
    }

    // Print summary
    std::cout << "\n" << std::string(60, '=') << "\n"
              << "  TEST RESULTS SUMMARY\n"
              << std::string(60, '=') << "\n";

    int passed = 0, failed = 0;
    for (const auto& result : results) {
        print_result(result);
        if (result.passed) passed++;
        else failed++;
    }

    std::cout << "\n" << std::string(60, '-') << "\n"
              << "  TOTAL: " << passed << " passed, " << failed << " failed\n"
              << std::string(60, '-') << "\n";

    return failed > 0 ? 1 : 0;
}
