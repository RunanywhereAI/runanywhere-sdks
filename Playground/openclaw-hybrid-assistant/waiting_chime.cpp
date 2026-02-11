// =============================================================================
// Waiting Chime - Implementation
// =============================================================================
// Generates a warm chime tone using additive synthesis (fundamental + harmonics)
// with a smooth ADSR-like envelope. Loops playback in small chunks so it can
// be interrupted within ~50ms when the OpenClaw response arrives.
// =============================================================================

#include "waiting_chime.h"

#include <algorithm>
#include <cmath>
#include <iostream>

namespace openclaw {

// Chunk size for playback - controls interrupt latency.
// At 22050 Hz, 1024 samples = ~46ms → response detected within one chunk.
static constexpr size_t PLAYBACK_CHUNK_SAMPLES = 1024;

static constexpr float TWO_PI = 2.0f * 3.14159265358979f;

// =============================================================================
// Constructor / Destructor
// =============================================================================

WaitingChime::WaitingChime(const WaitingChimeConfig& config, AudioOutputCallback play_audio)
    : config_(config)
    , play_audio_(std::move(play_audio)) {
    generate_chime();
}

WaitingChime::~WaitingChime() {
    stop();
}

// =============================================================================
// Tone Generation (called once at construction)
// =============================================================================

void WaitingChime::generate_chime() {
    const int tone_samples = config_.sample_rate * config_.tone_duration_ms / 1000;
    const int silence_samples = config_.sample_rate * config_.silence_duration_ms / 1000;
    const int total_samples = tone_samples + silence_samples;

    chime_buffer_.resize(total_samples, 0);

    const float volume = std::clamp(config_.volume, 0.0f, 1.0f);
    const int fade_in_samples = std::min(
        config_.sample_rate * config_.fade_in_ms / 1000,
        tone_samples / 4
    );
    const int fade_out_samples = std::min(
        config_.sample_rate * config_.fade_out_ms / 1000,
        tone_samples / 2
    );

    // Normalization factor: sum of all harmonic amplitudes
    const float norm = 1.0f / (1.0f + config_.harmonic_2nd + config_.harmonic_3rd);

    for (int i = 0; i < tone_samples; ++i) {
        const float t = static_cast<float>(i) / static_cast<float>(config_.sample_rate);

        // Additive synthesis: fundamental + harmonics
        float sample = std::sin(TWO_PI * config_.frequency_hz * t);                        // Fundamental
        sample += config_.harmonic_2nd * std::sin(TWO_PI * config_.frequency_hz * 2.0f * t); // 2nd harmonic
        sample += config_.harmonic_3rd * std::sin(TWO_PI * config_.frequency_hz * 3.0f * t); // 3rd harmonic

        // Normalize so combined amplitude stays within [-1, 1]
        sample *= norm;

        // Envelope: smooth fade-in and fade-out using cosine curves
        float envelope = 1.0f;
        if (i < fade_in_samples) {
            envelope = 0.5f * (1.0f - std::cos(3.14159f * static_cast<float>(i) / static_cast<float>(fade_in_samples)));
        } else if (i >= tone_samples - fade_out_samples) {
            const int fade_pos = i - (tone_samples - fade_out_samples);
            envelope = 0.5f * (1.0f + std::cos(3.14159f * static_cast<float>(fade_pos) / static_cast<float>(fade_out_samples)));
        }

        sample *= volume * envelope;

        chime_buffer_[i] = static_cast<int16_t>(std::clamp(sample * 32767.0f, -32767.0f, 32767.0f));
    }

    // Silence portion is already zero-initialized by resize

    std::cout << "[WaitingChime] Generated " << tone_samples << " tone + "
              << silence_samples << " silence samples ("
              << total_samples * 2 / 1024 << " KB)\n";
}

// =============================================================================
// Start / Stop
// =============================================================================

void WaitingChime::start() {
    // Already playing - nothing to do
    if (playing_.load()) {
        return;
    }

    // If a previous thread is still joinable (shouldn't happen, but be safe)
    if (loop_thread_.joinable()) {
        loop_thread_.join();
    }

    playing_.store(true);
    loop_thread_ = std::thread(&WaitingChime::loop_playback, this);

    std::cout << "[WaitingChime] Started waiting chime loop\n";
}

void WaitingChime::stop() {
    if (!playing_.load()) {
        return;
    }

    playing_.store(false);

    if (loop_thread_.joinable()) {
        loop_thread_.join();
    }

    std::cout << "[WaitingChime] Stopped\n";
}

bool WaitingChime::is_playing() const {
    return playing_.load();
}

// =============================================================================
// Background Loop
// =============================================================================

void WaitingChime::loop_playback() {
    if (chime_buffer_.empty() || !play_audio_) {
        playing_.store(false);
        return;
    }

    while (playing_.load()) {
        // Play the buffer in small chunks for low-latency interruption
        size_t offset = 0;
        while (offset < chime_buffer_.size() && playing_.load()) {
            const size_t remaining = chime_buffer_.size() - offset;
            const size_t chunk = std::min(remaining, PLAYBACK_CHUNK_SAMPLES);

            play_audio_(chime_buffer_.data() + offset, chunk, config_.sample_rate);
            offset += chunk;
        }
        // Loop back to start (if still playing)
    }
}

} // namespace openclaw
