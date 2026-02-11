#pragma once

// =============================================================================
// Waiting Chime - Earcon feedback while waiting for OpenClaw response
// =============================================================================
// Loads a short WAV earcon file and plays it:
//   - Once immediately when start() is called
//   - Then every 5 seconds as a gentle reminder the agent is still working
//   - Stops instantly when stop() is called (response arrived)
//
// If the WAV file is missing, all operations are silent no-ops.
// =============================================================================

#include <atomic>
#include <chrono>
#include <cstdint>
#include <functional>
#include <string>
#include <thread>
#include <vector>

namespace openclaw {

// Audio output callback: (samples, num_samples, sample_rate)
using AudioOutputCallback = std::function<void(const int16_t*, size_t, int)>;

// =============================================================================
// WaitingChime
// =============================================================================

class WaitingChime {
public:
    // Load earcon WAV from file path. Silent no-op if file doesn't exist.
    WaitingChime(const std::string& wav_path, AudioOutputCallback play_audio);
    ~WaitingChime();

    // Non-copyable
    WaitingChime(const WaitingChime&) = delete;
    WaitingChime& operator=(const WaitingChime&) = delete;

    // Play earcon once immediately, then repeat every 5 seconds.
    // Safe to call if already playing (no-op).
    void start();

    // Stop immediately (thread-safe).
    // Safe to call if not playing (no-op).
    void stop();

    // Check if currently active
    bool is_playing() const;

private:
    AudioOutputCallback play_audio_;

    // Loaded WAV PCM data
    std::vector<int16_t> earcon_buffer_;
    int sample_rate_ = 0;
    bool loaded_ = false;

    // Repeat thread
    std::thread repeat_thread_;
    std::atomic<bool> playing_{false};

    static constexpr int REPEAT_INTERVAL_MS = 5000;  // 5 seconds between plays
    static constexpr size_t PLAYBACK_CHUNK_SAMPLES = 1024;  // For interruptible playback

    bool load_wav(const std::string& path);
    void play_earcon();          // Play the buffer once (interruptible)
    void repeat_loop();          // Thread: play, wait 5s, play, wait 5s, ...
};

} // namespace openclaw
