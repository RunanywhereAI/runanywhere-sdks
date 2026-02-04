#pragma once

// =============================================================================
// Audio Capture - ALSA-based audio input for Linux
// =============================================================================
// Provides real-time audio capture from microphone using ALSA.
// Audio format: 16kHz, 16-bit PCM, mono (optimal for STT)
// =============================================================================

#include <functional>
#include <memory>
#include <cstdint>
#include <string>
#include <vector>

namespace openclaw {

// Audio callback: receives audio samples (16-bit PCM, 16kHz, mono)
using AudioCaptureCallback = std::function<void(const int16_t* samples, size_t num_samples)>;

// Audio capture configuration
struct AudioCaptureConfig {
    std::string device;          // ALSA device (default: "default" or "plughw:0,0")
    uint32_t sample_rate;        // Sample rate in Hz (default: 16000)
    uint32_t channels;           // Number of channels (default: 1)
    uint32_t buffer_frames;      // Frames per buffer (default: 512)
    uint32_t period_frames;      // Frames per period (default: 256)

    // Default configuration optimized for STT
    static AudioCaptureConfig defaults() {
        return {
            .device = "default",
            .sample_rate = 16000,
            .channels = 1,
            .buffer_frames = 512,
            .period_frames = 256
        };
    }
};

class AudioCapture {
public:
    AudioCapture();
    explicit AudioCapture(const AudioCaptureConfig& config);
    ~AudioCapture();

    // Non-copyable
    AudioCapture(const AudioCapture&) = delete;
    AudioCapture& operator=(const AudioCapture&) = delete;

    // Initialize ALSA device
    bool initialize();

    // Set callback for received audio
    void set_callback(AudioCaptureCallback callback);

    // Start/stop capture
    bool start();
    void stop();

    // Query state
    bool is_running() const;
    bool is_initialized() const;

    // Get configuration
    const AudioCaptureConfig& config() const { return config_; }

    // Get last error
    const std::string& last_error() const { return last_error_; }

    // List available capture devices
    static std::vector<std::string> list_devices();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;

    AudioCaptureConfig config_;
    AudioCaptureCallback callback_;
    std::string last_error_;
    bool initialized_ = false;
    bool running_ = false;
};

} // namespace openclaw
