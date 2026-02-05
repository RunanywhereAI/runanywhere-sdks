// =============================================================================
// Waiting Feedback - Implementation
// =============================================================================

#include "waiting_feedback.h"

#include <iostream>
#include <random>
#include <cmath>
#include <algorithm>

namespace openclaw {

// =============================================================================
// Constructor / Destructor
// =============================================================================

WaitingFeedback::WaitingFeedback() {
    init_default_phrases();
}

WaitingFeedback::WaitingFeedback(const WaitingFeedbackConfig& config)
    : config_(config) {
    init_default_phrases();
}

WaitingFeedback::~WaitingFeedback() {
    stop();
}

// =============================================================================
// Default Phrases - Warm, Professional, Human
// =============================================================================

void WaitingFeedback::init_default_phrases() {
    // Acknowledgment phrases - immediate, short, warm
    // These play right after the user finishes speaking
    acknowledgment_phrases_ = {
        "Let me think about that.",
        "One moment, please.",
        "Let me check on that for you.",
        "Give me just a second.",
        "Sure, let me look into that.",
        "Alright, thinking...",
        "Got it, one moment.",
        "Let me see what I can find.",
        "Hmm, let me think.",
        "Working on it."
    };

    // Waiting phrases - for longer waits (5+ seconds)
    // These keep the user engaged during processing
    waiting_phrases_ = {
        "Still working on that.",
        "Almost there.",
        "Just a bit longer.",
        "This might take a moment.",
        "Bear with me.",
        "I'm on it.",
        "Processing your request.",
        "Still thinking about that.",
        "Hang tight.",
        "Working through the details."
    };
}

// =============================================================================
// State Management
// =============================================================================

void WaitingFeedback::start(const std::string& user_query) {
    if (waiting_) {
        return;  // Already waiting
    }

    current_query_ = user_query;
    waiting_ = true;
    acknowledgment_played_ = false;
    first_phrase_played_ = false;
    phrase_count_ = 0;

    auto now = std::chrono::steady_clock::now();
    start_time_ = now;
    last_phrase_time_ = now;
    last_tone_time_ = now;

    std::cout << "[WaitingFeedback] Started waiting mode\n";
}

void WaitingFeedback::stop() {
    if (!waiting_) {
        return;
    }

    waiting_ = false;
    current_query_.clear();

    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start_time_
    ).count();

    std::cout << "[WaitingFeedback] Stopped (waited " << elapsed << "ms)\n";
}

bool WaitingFeedback::is_waiting() const {
    return waiting_;
}

// =============================================================================
// Update Loop - Call periodically from main loop
// =============================================================================

bool WaitingFeedback::update() {
    if (!waiting_) {
        return false;
    }

    auto now = std::chrono::steady_clock::now();
    auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
        now - start_time_
    ).count();

    bool played_something = false;

    // Stage 1: Immediate acknowledgment (after short delay)
    if (!acknowledgment_played_ && elapsed_ms >= config_.acknowledgment_delay_ms) {
        play_acknowledgment();
        acknowledgment_played_ = true;
        last_phrase_time_ = now;
        last_tone_time_ = now;
        played_something = true;
        return played_something;  // Return early to give TTS time to play
    }

    // Don't play anything else until acknowledgment is done
    if (!acknowledgment_played_) {
        return false;
    }

    // Calculate time since last phrase and tone
    auto since_last_phrase = std::chrono::duration_cast<std::chrono::milliseconds>(
        now - last_phrase_time_
    ).count();
    auto since_last_tone = std::chrono::duration_cast<std::chrono::milliseconds>(
        now - last_tone_time_
    ).count();

    // Stage 2: First "thinking" phrase (after first_phrase_delay_ms)
    if (!first_phrase_played_ && elapsed_ms >= config_.first_phrase_delay_ms + config_.acknowledgment_delay_ms) {
        // Play a subtle tone to indicate we're still working
        if (config_.enable_waiting_tones) {
            play_tone(config_.tone_frequency_hz, config_.tone_duration_ms, config_.tone_volume * 0.7f);
        }
        first_phrase_played_ = true;
        last_tone_time_ = now;
        played_something = true;
        return played_something;
    }

    // Stage 3: Periodic waiting feedback for longer waits
    if (first_phrase_played_) {
        // Play waiting phrase every phrase_interval_ms
        if (config_.enable_waiting_phrases && since_last_phrase >= config_.phrase_interval_ms) {
            play_waiting_phrase();
            last_phrase_time_ = now;
            last_tone_time_ = now;  // Reset tone timer too
            phrase_count_++;
            played_something = true;

            // Limit total phrases to avoid being annoying
            if (phrase_count_ >= 5) {
                // After 5 phrases (~30 seconds), just play tones
                config_.enable_waiting_phrases = false;
            }
            return played_something;
        }

        // Play gentle tone between phrases
        if (config_.enable_waiting_tones && since_last_tone >= config_.tone_interval_ms) {
            // Vary the tone slightly for a more organic feel
            int freq_variation = (phrase_count_ % 2 == 0) ? 0 : 100;
            play_tone(config_.tone_frequency_hz + freq_variation,
                     config_.tone_duration_ms,
                     config_.tone_volume * 0.5f);
            last_tone_time_ = now;
            played_something = true;
        }
    }

    return played_something;
}

// =============================================================================
// Acknowledgment
// =============================================================================

void WaitingFeedback::play_acknowledgment() {
    std::cout << "[WaitingFeedback] Playing acknowledgment\n";

    // Play a gentle "listening acknowledged" tone
    if (config_.enable_acknowledgment_sound && config_.on_audio) {
        // Two-tone chime: ascending (pleasant acknowledgment)
        play_tone(600, 80, config_.tone_volume * 0.6f);

        // Small gap
        std::vector<int16_t> silence(config_.sample_rate * 50 / 1000, 0);  // 50ms silence
        if (config_.on_audio) {
            config_.on_audio(silence.data(), silence.size(), config_.sample_rate);
        }

        play_tone(800, 100, config_.tone_volume * 0.8f);
    }

    // Speak acknowledgment phrase
    if (config_.enable_acknowledgment_phrase && config_.on_speak) {
        std::string phrase = select_random_phrase(acknowledgment_phrases_);
        std::cout << "[WaitingFeedback] Speaking: \"" << phrase << "\"\n";
        config_.on_speak(phrase);
    }
}

// =============================================================================
// Waiting Phrases
// =============================================================================

void WaitingFeedback::play_waiting_phrase() {
    if (!config_.on_speak || waiting_phrases_.empty()) {
        return;
    }

    std::string phrase = select_random_phrase(waiting_phrases_);
    std::cout << "[WaitingFeedback] Speaking: \"" << phrase << "\"\n";
    config_.on_speak(phrase);
}

// =============================================================================
// Tone Generation
// =============================================================================

void WaitingFeedback::play_tone(int frequency_hz, int duration_ms, float volume) {
    if (!config_.on_audio) {
        return;
    }

    std::vector<int16_t> buffer;
    generate_tone(buffer, frequency_hz, duration_ms, volume);

    if (!buffer.empty()) {
        config_.on_audio(buffer.data(), buffer.size(), config_.sample_rate);
    }
}

void WaitingFeedback::generate_tone(std::vector<int16_t>& buffer,
                                     int frequency_hz,
                                     int duration_ms,
                                     float volume) {
    int num_samples = config_.sample_rate * duration_ms / 1000;
    buffer.resize(num_samples);

    // Clamp volume
    volume = std::max(0.0f, std::min(1.0f, volume));

    // Generate sine wave with smooth envelope (fade in/out)
    const float two_pi = 2.0f * 3.14159265358979f;
    const int fade_samples = std::min(num_samples / 4, config_.sample_rate / 50);  // ~20ms fade

    for (int i = 0; i < num_samples; ++i) {
        // Base sine wave
        float t = static_cast<float>(i) / static_cast<float>(config_.sample_rate);
        float sample = std::sin(two_pi * frequency_hz * t);

        // Apply envelope (smooth fade in/out to avoid clicks)
        float envelope = 1.0f;
        if (i < fade_samples) {
            // Fade in (cosine curve for smooth start)
            envelope = 0.5f * (1.0f - std::cos(3.14159f * i / fade_samples));
        } else if (i >= num_samples - fade_samples) {
            // Fade out
            int fade_pos = i - (num_samples - fade_samples);
            envelope = 0.5f * (1.0f + std::cos(3.14159f * fade_pos / fade_samples));
        }

        // Apply volume and envelope
        sample *= volume * envelope;

        // Convert to int16
        buffer[i] = static_cast<int16_t>(sample * 32767.0f);
    }
}

// =============================================================================
// Phrase Selection
// =============================================================================

std::string WaitingFeedback::select_random_phrase(const std::vector<std::string>& phrases) {
    if (phrases.empty()) {
        return "";
    }

    // Use random device for better randomness
    static std::random_device rd;
    static std::mt19937 gen(rd());
    std::uniform_int_distribution<size_t> dist(0, phrases.size() - 1);

    return phrases[dist(gen)];
}

// =============================================================================
// Configuration
// =============================================================================

void WaitingFeedback::set_config(const WaitingFeedbackConfig& config) {
    config_ = config;
}

void WaitingFeedback::set_acknowledgment_phrases(const std::vector<std::string>& phrases) {
    if (!phrases.empty()) {
        acknowledgment_phrases_ = phrases;
    }
}

void WaitingFeedback::set_waiting_phrases(const std::vector<std::string>& phrases) {
    if (!phrases.empty()) {
        waiting_phrases_ = phrases;
    }
}

} // namespace openclaw
