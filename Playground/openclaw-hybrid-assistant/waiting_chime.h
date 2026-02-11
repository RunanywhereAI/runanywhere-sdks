#pragma once

// =============================================================================
// Waiting Chime - Gentle audio feedback while waiting for OpenClaw response
// =============================================================================
// Generates a warm, soothing chime tone programmatically and loops it
// while the user waits for OpenClaw to process their request.
//
// No external audio files needed - tone is generated at construction time.
// Playback runs on a background thread with low-latency interruption (~50ms).
// =============================================================================

#include <atomic>
#include <cstdint>
#include <functional>
#include <thread>
#include <vector>

namespace openclaw {

// =============================================================================
// Configuration
// =============================================================================

struct WaitingChimeConfig {
    int sample_rate = 22050;          // Match TTS playback sample rate
    float volume = 0.20f;             // Subtle (20% of max, 0.0 - 1.0)
    float frequency_hz = 523.25f;     // C5 - warm, pleasant fundamental
    int tone_duration_ms = 1500;      // Duration of the chime tone
    int silence_duration_ms = 1000;   // Silence gap between loop iterations
    int fade_in_ms = 50;              // Smooth fade-in to avoid clicks
    int fade_out_ms = 500;            // Long fade-out for a breathing feel
    float harmonic_2nd = 0.40f;       // 2nd harmonic amplitude (body)
    float harmonic_3rd = 0.15f;       // 3rd harmonic amplitude (warmth)
};

// Audio output callback: (samples, num_samples, sample_rate)
using AudioOutputCallback = std::function<void(const int16_t*, size_t, int)>;

// =============================================================================
// WaitingChime
// =============================================================================

class WaitingChime {
public:
    WaitingChime(const WaitingChimeConfig& config, AudioOutputCallback play_audio);
    ~WaitingChime();

    // Non-copyable
    WaitingChime(const WaitingChime&) = delete;
    WaitingChime& operator=(const WaitingChime&) = delete;

    // Start looping the chime (non-blocking, spawns background thread)
    // Safe to call if already playing (no-op).
    void start();

    // Stop the chime immediately (thread-safe, blocks until thread joins)
    // Safe to call if not playing (no-op).
    void stop();

    // Check if currently playing
    bool is_playing() const;

private:
    WaitingChimeConfig config_;
    AudioOutputCallback play_audio_;

    // Pre-generated PCM buffer (tone + trailing silence)
    std::vector<int16_t> chime_buffer_;

    // Playback thread
    std::thread loop_thread_;
    std::atomic<bool> playing_{false};

    // Tone generation (called once in constructor)
    void generate_chime();

    // Background thread function
    void loop_playback();
};

} // namespace openclaw
