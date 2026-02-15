// =============================================================================
// Linux Voice Assistant - Main Entry Point
// =============================================================================
// A complete on-device voice AI pipeline for Linux (Raspberry Pi 5, etc.)
//
// Pipeline: Wake Word -> VAD -> STT -> LLM -> TTS
// All inference runs locally — no cloud required.
//
// Usage: ./voice-assistant [options]
//
// Options:
//   --list-devices    List available audio devices
//   --input <device>  Audio input device (default: "default")
//   --output <device> Audio output device (default: "default")
//   --wakeword        Enable wake word detection ("Hey Jarvis")
//   --help            Show this help message
//
// Controls:
//   Ctrl+C            Exit the application
// =============================================================================

#include "config/model_config.h"
#include "pipeline/voice_pipeline.h"
#include "audio/audio_capture.h"
#include "audio/audio_playback.h"

// Backend registration
#include <rac/backends/rac_vad_onnx.h>
#include <rac/backends/rac_llm_llamacpp.h>
#include <rac/backends/rac_wakeword_onnx.h>

#include <iostream>
#include <csignal>
#include <atomic>
#include <thread>
#include <chrono>
#include <string>
#include <cstring>

// =============================================================================
// Global State
// =============================================================================

std::atomic<bool> g_running{true};

void signal_handler(int signum) {
    (void)signum;
    g_running = false;
}

// =============================================================================
// Command Line Arguments
// =============================================================================

struct AppConfig {
    std::string input_device = "default";
    std::string output_device = "default";
    bool list_devices = false;
    bool show_help = false;
    bool enable_wakeword = false;
};

void print_usage(const char* prog_name) {
    std::cout << "Usage: " << prog_name << " [options]\n\n"
              << "Options:\n"
              << "  --list-devices    List available audio devices\n"
              << "  --input <device>  Audio input device (default: \"default\")\n"
              << "  --output <device> Audio output device (default: \"default\")\n"
              << "  --wakeword        Enable wake word detection (\"Hey Jarvis\")\n"
              << "  --help            Show this help message\n\n"
              << "Controls:\n"
              << "  Ctrl+C            Exit the application\n"
              << std::endl;
}

AppConfig parse_args(int argc, char* argv[]) {
    AppConfig config;

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--list-devices") == 0) {
            config.list_devices = true;
        } else if (strcmp(argv[i], "--input") == 0 && i + 1 < argc) {
            config.input_device = argv[++i];
        } else if (strcmp(argv[i], "--output") == 0 && i + 1 < argc) {
            config.output_device = argv[++i];
        } else if (strcmp(argv[i], "--wakeword") == 0) {
            config.enable_wakeword = true;
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            config.show_help = true;
        }
    }

    return config;
}

void list_audio_devices() {
    std::cout << "Input devices (microphones):\n";
    auto input_devices = runanywhere::AudioCapture::list_devices();
    for (const auto& dev : input_devices) {
        std::cout << "  " << dev << "\n";
    }

    std::cout << "\nOutput devices (speakers):\n";
    auto output_devices = runanywhere::AudioPlayback::list_devices();
    for (const auto& dev : output_devices) {
        std::cout << "  " << dev << "\n";
    }
    std::cout << std::endl;
}

// =============================================================================
// Main
// =============================================================================

int main(int argc, char* argv[]) {
    // Parse command line
    AppConfig app_config = parse_args(argc, argv);

    if (app_config.show_help) {
        print_usage(argv[0]);
        return 0;
    }

    if (app_config.list_devices) {
        list_audio_devices();
        return 0;
    }

    // Install signal handlers
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    std::cout << "========================================\n"
              << "    Linux Voice Assistant\n"
              << "========================================\n"
              << std::endl;

    // Check model availability
    std::cout << "Checking models...\n";
    runanywhere::print_model_status(app_config.enable_wakeword);
    std::cout << std::endl;

    if (!runanywhere::are_all_models_available()) {
        std::cerr << "ERROR: Some required models are missing!\n"
                  << "Please run: ./scripts/download-models.sh\n"
                  << std::endl;
        return 1;
    }

    // Check wake word models if enabled
    if (app_config.enable_wakeword && !runanywhere::are_wakeword_models_available()) {
        std::cerr << "WARNING: Wake word models are missing!\n"
                  << "Please run: ./scripts/download-models.sh --wakeword\n"
                  << "Disabling wake word detection.\n"
                  << std::endl;
        app_config.enable_wakeword = false;
    }

    // =============================================================================
    // Register Backends
    // =============================================================================

    std::cout << "Registering backends...\n";
    rac_result_t reg_result = rac_backend_onnx_register();
    if (reg_result != RAC_SUCCESS) {
        std::cerr << "WARNING: Failed to register ONNX backend (code: " << reg_result << ")\n";
    } else {
        std::cout << "  ONNX backend registered (STT, TTS, VAD)\n";
    }

    reg_result = rac_backend_llamacpp_register();
    if (reg_result != RAC_SUCCESS) {
        std::cerr << "WARNING: Failed to register LlamaCPP backend (code: " << reg_result << ")\n";
    } else {
        std::cout << "  LlamaCPP backend registered (LLM)\n";
    }

    if (app_config.enable_wakeword) {
        reg_result = rac_backend_wakeword_onnx_register();
        if (reg_result != RAC_SUCCESS) {
            std::cerr << "WARNING: Failed to register Wake Word backend (code: " << reg_result << ")\n";
        } else {
            std::cout << "  Wake Word backend registered (openWakeWord)\n";
        }
    }
    std::cout << std::endl;

    // =============================================================================
    // Initialize Audio
    // =============================================================================

    std::cout << "Initializing audio...\n";

    // Audio capture (microphone)
    runanywhere::AudioCaptureConfig capture_config = runanywhere::AudioCaptureConfig::defaults();
    capture_config.device = app_config.input_device;

    runanywhere::AudioCapture capture(capture_config);
    if (!capture.initialize()) {
        std::cerr << "ERROR: Failed to initialize audio capture: "
                  << capture.last_error() << std::endl;
        return 1;
    }
    std::cout << "  Input: " << capture.config().device
              << " @ " << capture.config().sample_rate << " Hz\n";

    // Audio playback (speaker)
    runanywhere::AudioPlaybackConfig playback_config = runanywhere::AudioPlaybackConfig::defaults();
    playback_config.device = app_config.output_device;

    runanywhere::AudioPlayback playback(playback_config);
    if (!playback.initialize()) {
        std::cerr << "ERROR: Failed to initialize audio playback: "
                  << playback.last_error() << std::endl;
        return 1;
    }
    std::cout << "  Output: " << playback.config().device
              << " @ " << playback.config().sample_rate << " Hz\n";

    std::cout << std::endl;

    // =============================================================================
    // Initialize Voice Pipeline
    // =============================================================================

    std::cout << "Initializing voice pipeline...\n";

    runanywhere::VoicePipelineConfig pipeline_config;

    // Configure wake word (optional)
    pipeline_config.enable_wake_word = app_config.enable_wakeword;
    if (app_config.enable_wakeword) {
        pipeline_config.wake_word = "Hey Jarvis";
        pipeline_config.wake_word_threshold = 0.5f;

        // Wake word callback
        pipeline_config.on_wake_word = [](const std::string& wake_word, float confidence) {
            std::cout << "\n*** Wake word detected: \"" << wake_word
                      << "\" (confidence: " << confidence << ") ***\n"
                      << "[Listening for command...]" << std::flush;
        };
    }

    // Voice activity callback
    pipeline_config.on_voice_activity = [&app_config](bool is_speaking) {
        if (is_speaking) {
            if (!app_config.enable_wakeword) {
                std::cout << "\n[Listening...]" << std::flush;
            }
        } else {
            std::cout << " [Processing...]\n" << std::flush;
        }
    };

    // Transcription callback
    pipeline_config.on_transcription = [](const std::string& text, bool is_final) {
        if (is_final) {
            std::cout << "[USER] " << text << std::endl;
        }
    };

    // LLM response callback
    pipeline_config.on_response = [](const std::string& text, bool is_complete) {
        if (is_complete) {
            std::cout << "[ASSISTANT] " << text << std::endl;
        }
    };

    // TTS audio callback
    pipeline_config.on_audio_output = [&playback](const int16_t* samples, size_t num_samples, int sample_rate) {
        // Reinitialize playback if sample rate changed
        if (static_cast<uint32_t>(sample_rate) != playback.config().sample_rate) {
            playback.reinitialize(sample_rate);
        }
        playback.play(samples, num_samples);
    };

    // Error callback
    pipeline_config.on_error = [](const std::string& error) {
        std::cerr << "[ERROR] " << error << std::endl;
    };

    runanywhere::VoicePipeline pipeline(pipeline_config);

    if (!pipeline.initialize()) {
        std::cerr << "ERROR: Failed to initialize voice pipeline: "
                  << pipeline.last_error() << std::endl;
        return 1;
    }

    std::cout << "\nModels loaded:\n"
              << "  STT: " << pipeline.get_stt_model_id() << "\n"
              << "  LLM: " << pipeline.get_llm_model_id() << "\n"
              << "  TTS: " << pipeline.get_tts_model_id() << "\n"
              << std::endl;

    // =============================================================================
    // Connect Audio to Pipeline
    // =============================================================================

    // Set audio callback to feed pipeline
    capture.set_callback([&pipeline](const int16_t* samples, size_t num_samples) {
        pipeline.process_audio(samples, num_samples);
    });

    // =============================================================================
    // Run Main Loop
    // =============================================================================

    std::cout << "========================================\n"
              << "Voice Assistant is ready!\n"
              << "Mode: Local LLM (full on-device pipeline)\n";
    if (app_config.enable_wakeword) {
        std::cout << "Say \"Hey Jarvis\" to activate.\n";
    } else {
        std::cout << "Speak to interact.\n";
    }
    std::cout << "Press Ctrl+C to exit.\n"
              << "========================================\n"
              << std::endl;

    // Start audio capture
    if (!capture.start()) {
        std::cerr << "ERROR: Failed to start audio capture: "
                  << capture.last_error() << std::endl;
        return 1;
    }

    // Start voice pipeline
    pipeline.start();

    // Main loop
    while (g_running) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }

    // =============================================================================
    // Cleanup
    // =============================================================================

    std::cout << "\nShutting down...\nStopping..." << std::endl;

    pipeline.stop();
    capture.stop();
    playback.stop();

    std::cout << "Goodbye!" << std::endl;
    return 0;
}
