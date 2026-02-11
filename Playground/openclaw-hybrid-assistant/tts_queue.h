#pragma once

// =============================================================================
// TTS Queue - Simple producer/consumer for streaming TTS playback
// =============================================================================
// Producer: synthesizes sentences, pushes audio into the queue
// Consumer: plays audio via ALSA as soon as it arrives
//
// This lets sentence N+1 synthesize while sentence N plays.
// =============================================================================

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <queue>
#include <thread>
#include <vector>

namespace openclaw {

// Audio output callback: (samples, num_samples, sample_rate)
using AudioOutputFn = std::function<void(const int16_t*, size_t, int)>;

// A single sentence's synthesized audio
struct AudioChunk {
    std::vector<int16_t> samples;
    int sample_rate = 0;
};

// =============================================================================
// TTS Queue
// =============================================================================

class TTSQueue {
public:
    explicit TTSQueue(AudioOutputFn play_audio);
    ~TTSQueue();

    // Non-copyable
    TTSQueue(const TTSQueue&) = delete;
    TTSQueue& operator=(const TTSQueue&) = delete;

    // Push a synthesized chunk for playback (called from producer thread)
    void push(AudioChunk chunk);

    // Signal that all chunks have been pushed (consumer exits after draining)
    void finish();

    // Cancel everything immediately (thread-safe)
    void cancel();

    // Is the consumer still running?
    bool is_active() const;

private:
    AudioOutputFn play_audio_;

    std::queue<AudioChunk> queue_;
    std::mutex mutex_;
    std::condition_variable cv_;

    std::atomic<bool> finished_{false};
    std::atomic<bool> cancelled_{false};
    std::atomic<bool> active_{true};

    std::thread consumer_thread_;
    void consume();
};

} // namespace openclaw
