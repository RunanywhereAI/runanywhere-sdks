// =============================================================================
// OpenClaw Hybrid Assistant - Main Entry Point
// =============================================================================
// A lightweight voice channel for OpenClaw.
// NO local LLM - just Wake Word + VAD + ASR → OpenClaw, TTS ← OpenClaw
//
// Usage: ./openclaw-assistant [options]
//
// Options:
//   --list-devices           List available audio devices
//   --input <device>         Audio input device (default: "default")
//   --output <device>        Audio output device (default: "default")
//   --wakeword               Enable wake word detection ("Hey Jarvis")
//   --wakeword-threshold <f> Wake word threshold 0.0-1.0 (default: 0.5)
//   --openclaw-url <url>     OpenClaw WebSocket URL (default: "ws://localhost:8082")
//   --device-id <id>         Device identifier (default: hostname)
//   --debug-wakeword         Enable wake word debug logging
//   --debug-vad              Enable VAD debug logging
//   --debug-stt              Enable STT debug logging
//   --help                   Show this help message
//
// Controls:
//   Ctrl+C                   Exit the application
// =============================================================================

#include "model_config.h"
#include "voice_pipeline.h"
#include "audio_capture.h"
#include "audio_playback.h"
#include "openclaw_client.h"
#include "waiting_chime.h"

// Backend registration
#include <rac/backends/rac_vad_onnx.h>
#include <rac/backends/rac_wakeword_onnx.h>

#include <iostream>
#include <csignal>
#include <atomic>
#include <thread>
#include <chrono>
#include <string>
#include <cstring>
#include <unistd.h>

// =============================================================================
// Global State
// =============================================================================

std::atomic<bool> g_running{true};

void signal_handler(int signum) {
    (void)signum;
    std::cout << "\nShutting down..." << std::endl;
    g_running = false;
}

// =============================================================================
// Command Line Arguments
// =============================================================================

struct AppConfig {
    std::string input_device = "default";
    std::string output_device = "default";
    std::string openclaw_url = "ws://localhost:8082";
    std::string device_id;
    bool list_devices = false;
    bool show_help = false;
    bool enable_wakeword = false;
    float wakeword_threshold = 0.5f;
    bool debug_wakeword = false;
    bool debug_vad = false;
    bool debug_stt = false;
};

void print_usage(const char* prog_name) {
    std::cout << "OpenClaw Hybrid Assistant\n"
              << "A lightweight voice channel for OpenClaw (NO local LLM)\n\n"
              << "Usage: " << prog_name << " [options]\n\n"
              << "Options:\n"
              << "  --list-devices           List available audio devices\n"
              << "  --input <device>         Audio input device (default: \"default\")\n"
              << "  --output <device>        Audio output device (default: \"default\")\n"
              << "  --wakeword               Enable wake word detection (\"Hey Jarvis\")\n"
              << "  --wakeword-threshold <f> Wake word threshold 0.0-1.0 (default: 0.5)\n"
              << "  --openclaw-url <url>     OpenClaw WebSocket URL (default: \"ws://localhost:8082\")\n"
              << "  --device-id <id>         Device identifier (default: hostname)\n"
              << "  --debug-wakeword         Enable wake word debug logging\n"
              << "  --debug-vad              Enable VAD debug logging\n"
              << "  --debug-stt              Enable STT debug logging\n"
              << "  --help                   Show this help message\n\n"
              << "Controls:\n"
              << "  Ctrl+C                   Exit the application\n"
              << std::endl;
}

AppConfig parse_args(int argc, char* argv[]) {
    AppConfig config;

    // Get hostname as default device ID
    char hostname[256];
    if (gethostname(hostname, sizeof(hostname)) == 0) {
        config.device_id = hostname;
    } else {
        config.device_id = "openclaw-assistant";
    }

    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--list-devices") == 0) {
            config.list_devices = true;
        } else if (strcmp(argv[i], "--input") == 0 && i + 1 < argc) {
            config.input_device = argv[++i];
        } else if (strcmp(argv[i], "--output") == 0 && i + 1 < argc) {
            config.output_device = argv[++i];
        } else if (strcmp(argv[i], "--wakeword") == 0) {
            config.enable_wakeword = true;
        } else if (strcmp(argv[i], "--wakeword-threshold") == 0 && i + 1 < argc) {
            config.wakeword_threshold = std::stof(argv[++i]);
        } else if (strcmp(argv[i], "--openclaw-url") == 0 && i + 1 < argc) {
            config.openclaw_url = argv[++i];
        } else if (strcmp(argv[i], "--device-id") == 0 && i + 1 < argc) {
            config.device_id = argv[++i];
        } else if (strcmp(argv[i], "--debug-wakeword") == 0) {
            config.debug_wakeword = true;
        } else if (strcmp(argv[i], "--debug-vad") == 0) {
            config.debug_vad = true;
        } else if (strcmp(argv[i], "--debug-stt") == 0) {
            config.debug_stt = true;
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            config.show_help = true;
        }
    }

    return config;
}

void list_audio_devices() {
    std::cout << "Input devices (microphones):\n";
    auto input_devices = openclaw::AudioCapture::list_devices();
    for (const auto& dev : input_devices) {
        std::cout << "  " << dev << "\n";
    }

    std::cout << "\nOutput devices (speakers):\n";
    auto output_devices = openclaw::AudioPlayback::list_devices();
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
              << "    OpenClaw Hybrid Assistant\n"
              << "    (NO local LLM)\n"
              << "========================================\n"
              << std::endl;

    // Check model availability
    std::cout << "Checking models...\n";
    openclaw::print_model_status(app_config.enable_wakeword);
    std::cout << std::endl;

    if (!openclaw::are_all_models_available()) {
        std::cerr << "ERROR: Some required models are missing!\n"
                  << "Please run: ./scripts/download-models.sh\n"
                  << std::endl;
        return 1;
    }

    // Check wake word models if enabled
    if (app_config.enable_wakeword && !openclaw::are_wakeword_models_available()) {
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
    // Initialize OpenClaw Client
    // =============================================================================

    std::cout << "Initializing OpenClaw client...\n";
    std::cout << "  URL: " << app_config.openclaw_url << "\n";
    std::cout << "  Device ID: " << app_config.device_id << "\n";

    openclaw::OpenClawClientConfig client_config;
    client_config.url = app_config.openclaw_url;
    client_config.device_id = app_config.device_id;

    openclaw::OpenClawClient openclaw_client(client_config);

    // Connect (uses HTTP mode for now)
    if (!openclaw_client.connect()) {
        std::cerr << "WARNING: Failed to connect to OpenClaw: " << openclaw_client.last_error() << "\n";
        std::cerr << "Continuing anyway (will retry on each request)...\n";
    }
    std::cout << std::endl;

    // =============================================================================
    // Initialize Audio
    // =============================================================================

    std::cout << "Initializing audio...\n";

    // Audio capture (microphone)
    openclaw::AudioCaptureConfig capture_config = openclaw::AudioCaptureConfig::defaults();
    capture_config.device = app_config.input_device;

    openclaw::AudioCapture capture(capture_config);
    if (!capture.initialize()) {
        std::cerr << "ERROR: Failed to initialize audio capture: "
                  << capture.last_error() << std::endl;
        return 1;
    }
    std::cout << "  Input: " << capture.config().device
              << " @ " << capture.config().sample_rate << " Hz\n";

    // Audio playback (speaker)
    openclaw::AudioPlaybackConfig playback_config = openclaw::AudioPlaybackConfig::defaults();
    playback_config.device = app_config.output_device;

    openclaw::AudioPlayback playback(playback_config);
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

    std::cout << "Initializing voice pipeline (NO LLM)...\n";

    openclaw::VoicePipelineConfig pipeline_config;

    // Configure wake word (optional)
    pipeline_config.enable_wake_word = app_config.enable_wakeword;
    if (app_config.enable_wakeword) {
        pipeline_config.wake_word = "Hey Jarvis";
        pipeline_config.wake_word_threshold = app_config.wakeword_threshold;
    }

    // Debug settings
    pipeline_config.debug_wakeword = app_config.debug_wakeword;
    pipeline_config.debug_vad = app_config.debug_vad;
    pipeline_config.debug_stt = app_config.debug_stt;

    // Wake word callback
    pipeline_config.on_wake_word = [](const std::string& wake_word, float confidence) {
        std::cout << "\n*** Wake word detected: \"" << wake_word
                  << "\" (confidence: " << confidence << ") ***\n"
                  << "[Listening for command...]" << std::flush;
    };

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

    // Transcription callback - SEND TO OPENCLAW
    // Note: waiting_chime is captured by pointer set after construction (see below)
    openclaw::WaitingChime* waiting_chime_ptr = nullptr;

    pipeline_config.on_transcription = [&openclaw_client, &waiting_chime_ptr](const std::string& text, bool is_final) {
        if (is_final && !text.empty()) {
            std::cout << "[USER] " << text << std::endl;

            // Send to OpenClaw (fire-and-forget)
            openclaw_client.send_transcription(text, true);

            // Start the waiting chime loop while we wait for OpenClaw response
            if (waiting_chime_ptr) {
                waiting_chime_ptr->start();
            }
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

    openclaw::VoicePipeline pipeline(pipeline_config);

    if (!pipeline.initialize()) {
        std::cerr << "ERROR: Failed to initialize voice pipeline: "
                  << pipeline.last_error() << std::endl;
        return 1;
    }

    std::cout << "\nModels loaded (NO LLM):\n"
              << "  STT: " << pipeline.get_stt_model_id() << "\n"
              << "  TTS: " << pipeline.get_tts_model_id() << "\n"
              << std::endl;

    // =============================================================================
    // Initialize Waiting Chime
    // =============================================================================
    // Provides a gentle audio chime loop while waiting for OpenClaw to respond.
    // The tone is generated programmatically at startup (no external files needed).

    std::cout << "Initializing waiting chime...\n";

    openclaw::WaitingChimeConfig chime_config;
    chime_config.sample_rate = playback.config().sample_rate;

    openclaw::WaitingChime waiting_chime(chime_config, [&playback](const int16_t* samples, size_t num_samples, int sample_rate) {
        if (static_cast<uint32_t>(sample_rate) != playback.config().sample_rate) {
            playback.reinitialize(sample_rate);
        }
        playback.play(samples, num_samples);
    });

    // Set the pointer so the transcription callback can start the chime
    waiting_chime_ptr = &waiting_chime;

    std::cout << "  Waiting chime ready\n" << std::endl;

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
              << "OpenClaw Hybrid Assistant is ready!\n"
              << "Mode: OpenClaw Channel (NO local LLM)\n"
              << "OpenClaw URL: " << app_config.openclaw_url << "\n";
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

    // Polling interval for speak queue (200ms for responsive chime→response transition)
    auto last_poll_time = std::chrono::steady_clock::now();
    const auto poll_interval = std::chrono::milliseconds(200);

    // Main loop
    while (g_running) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));

        // Poll OpenClaw for speak messages (from any channel)
        auto now = std::chrono::steady_clock::now();
        if (now - last_poll_time >= poll_interval) {
            last_poll_time = now;

            openclaw::SpeakMessage message;
            if (openclaw_client.poll_speak_queue(message)) {
                // Stop the waiting chime immediately - response has arrived
                waiting_chime.stop();

                std::cout << "[" << message.source_channel << "] " << message.text << std::endl;
                pipeline.speak_text(message.text);
            }
        }
    }

    // =============================================================================
    // Cleanup
    // =============================================================================

    std::cout << "\nStopping..." << std::endl;

    waiting_chime.stop();
    pipeline.stop();
    capture.stop();
    playback.stop();
    openclaw_client.disconnect();

    std::cout << "Goodbye!" << std::endl;
    return 0;
}
