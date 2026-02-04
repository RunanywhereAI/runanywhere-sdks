#pragma once

// =============================================================================
// Audio Playback - ALSA-based audio output for Linux
// =============================================================================
// Provides audio playback to speaker using ALSA.
// Supports multiple sample rates for TTS output.
// =============================================================================

#include <memory>
#include <cstdint>
#include <string>
#include <vector>

namespace openclaw {

// Audio playback configuration
struct AudioPlaybackConfig {
    std::string device;          // ALSA device (default: "default")
    uint32_t sample_rate;        // Sample rate in Hz (default: 22050 for TTS)
    uint32_t channels;           // Number of channels (default: 1)
    uint32_t buffer_frames;      // Frames per buffer (default: 4096)
    uint32_t period_frames;      // Frames per period (default: 1024)

    // Default configuration optimized for TTS output
    static AudioPlaybackConfig defaults() {
        return {
            .device = "default",
            .sample_rate = 22050,  // Common TTS sample rate
            .channels = 1,
            .buffer_frames = 4096,
            .period_frames = 1024
        };
    }

    // High quality configuration (24kHz)
    static AudioPlaybackConfig high_quality() {
        return {
            .device = "default",
            .sample_rate = 24000,
            .channels = 1,
            .buffer_frames = 4096,
            .period_frames = 1024
        };
    }
};

class AudioPlayback {
public:
    AudioPlayback();
    explicit AudioPlayback(const AudioPlaybackConfig& config);
    ~AudioPlayback();

    // Non-copyable
    AudioPlayback(const AudioPlayback&) = delete;
    AudioPlayback& operator=(const AudioPlayback&) = delete;

    // Initialize ALSA device
    bool initialize();

    // Reinitialize with different sample rate (for TTS output)
    bool reinitialize(uint32_t sample_rate);

    // Play audio samples (blocking)
    // samples: 16-bit PCM audio data
    // num_samples: number of samples (not bytes)
    bool play(const int16_t* samples, size_t num_samples);

    // Play audio samples (non-blocking, queued)
    bool play_async(const int16_t* samples, size_t num_samples);

    // Stop playback and clear queue
    void stop();

    // Wait for all queued audio to finish
    void drain();

    // Query state
    bool is_initialized() const;
    bool is_playing() const;

    // Get configuration
    const AudioPlaybackConfig& config() const { return config_; }

    // Get last error
    const std::string& last_error() const { return last_error_; }

    // List available playback devices
    static std::vector<std::string> list_devices();

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;

    AudioPlaybackConfig config_;
    std::string last_error_;
    bool initialized_ = false;
};

} // namespace openclaw
