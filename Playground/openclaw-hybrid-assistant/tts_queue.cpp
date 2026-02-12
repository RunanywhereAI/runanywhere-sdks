// =============================================================================
// TTS Queue - Implementation
// =============================================================================

#include "tts_queue.h"

#include <iostream>

namespace openclaw {

TTSQueue::TTSQueue(AudioOutputFn play_audio)
    : play_audio_(std::move(play_audio)) {
    consumer_thread_ = std::thread(&TTSQueue::consume, this);
}

TTSQueue::~TTSQueue() {
    cancel();
    if (consumer_thread_.joinable()) {
        consumer_thread_.join();
    }
}

void TTSQueue::push(AudioChunk chunk) {
    if (cancelled_.load() || finished_.load()) return;

    {
        std::lock_guard<std::mutex> lock(mutex_);
        queue_.push(std::move(chunk));
    }
    cv_.notify_one();
}

void TTSQueue::finish() {
    finished_.store(true);
    cv_.notify_one();
}

void TTSQueue::cancel() {
    cancelled_.store(true);
    finished_.store(true);
    cv_.notify_all();
}

bool TTSQueue::is_active() const {
    return active_.load();
}

// Consumer: wait for chunks, play them as they arrive
void TTSQueue::consume() {
    while (!cancelled_.load()) {
        AudioChunk chunk;

        // Wait for data or finish signal
        {
            std::unique_lock<std::mutex> lock(mutex_);
            cv_.wait(lock, [this] {
                return !queue_.empty() || finished_.load() || cancelled_.load();
            });

            if (cancelled_.load()) break;
            if (queue_.empty()) break;  // finished and drained

            chunk = std::move(queue_.front());
            queue_.pop();
        }

        // Play it — pass cancelled_ so the callback can check between ALSA writes
        if (!chunk.samples.empty() && play_audio_ && !cancelled_.load()) {
            play_audio_(chunk.samples.data(), chunk.samples.size(),
                        chunk.sample_rate, cancelled_);
        }
    }

    active_.store(false);
}

} // namespace openclaw
