#pragma once

// =============================================================================
// Waiting Feedback - Audio/TTS feedback while waiting for OpenClaw response
// =============================================================================
// Provides a warm, professional user experience by giving audio feedback
// while the user waits for OpenClaw to process their request.
//
// Features:
// - Immediate acknowledgment (sound + optional phrase)
// - Periodic "thinking" sounds during longer waits
// - Random warm phrases to keep user engaged
// - Seamless interruption when response arrives
// =============================================================================

#include <string>
#include <vector>
#include <functional>
#include <memory>
#include <atomic>
#include <chrono>

namespace openclaw {

// =============================================================================
// Configuration
// =============================================================================

struct WaitingFeedbackConfig {
    // Timing (milliseconds)
    int acknowledgment_delay_ms = 200;        // Delay before first acknowledgment
    int first_phrase_delay_ms = 1500;         // Delay before first "thinking" phrase
    int phrase_interval_ms = 6000;            // Interval between phrases during long waits
    int tone_interval_ms = 3000;              // Interval for gentle tones between phrases

    // Audio settings
    int sample_rate = 24000;                  // Match TTS sample rate (Kokoro = 24kHz)
    float tone_volume = 0.3f;                 // Volume for generated tones (0.0 - 1.0)
    int tone_duration_ms = 150;               // Duration of notification tone
    int tone_frequency_hz = 800;              // Frequency of notification tone

    // Behavior
    bool enable_acknowledgment_sound = true;  // Play sound on acknowledgment
    bool enable_acknowledgment_phrase = true; // Speak phrase on acknowledgment
    bool enable_waiting_phrases = true;       // Speak periodic waiting phrases
    bool enable_waiting_tones = true;         // Play periodic waiting tones

    // Callbacks (must be set before use)
    std::function<void(const std::string&)> on_speak;           // TTS callback
    std::function<void(const int16_t*, size_t, int)> on_audio;  // Raw audio callback
};

// =============================================================================
// Waiting Feedback Manager
// =============================================================================

class WaitingFeedback {
public:
    WaitingFeedback();
    explicit WaitingFeedback(const WaitingFeedbackConfig& config);
    ~WaitingFeedback();

    // Non-copyable
    WaitingFeedback(const WaitingFeedback&) = delete;
    WaitingFeedback& operator=(const WaitingFeedback&) = delete;

    // Start waiting feedback (call after sending transcription to OpenClaw)
    // user_query: The user's transcribed text (used to select appropriate responses)
    void start(const std::string& user_query = "");

    // Stop waiting feedback (call when response arrives)
    // This will interrupt any ongoing TTS or sounds immediately
    void stop();

    // Check if currently in waiting state
    bool is_waiting() const;

    // Update loop - call periodically from main loop (returns true if feedback was played)
    bool update();

    // Configuration
    void set_config(const WaitingFeedbackConfig& config);
    const WaitingFeedbackConfig& config() const { return config_; }

    // Phrase management (can be customized at runtime)
    void set_acknowledgment_phrases(const std::vector<std::string>& phrases);
    void set_waiting_phrases(const std::vector<std::string>& phrases);

private:
    WaitingFeedbackConfig config_;

    // State
    std::atomic<bool> waiting_{false};
    std::chrono::steady_clock::time_point start_time_;
    std::chrono::steady_clock::time_point last_phrase_time_;
    std::chrono::steady_clock::time_point last_tone_time_;
    bool acknowledgment_played_ = false;
    bool first_phrase_played_ = false;
    int phrase_count_ = 0;

    // Phrase pools
    std::vector<std::string> acknowledgment_phrases_;
    std::vector<std::string> waiting_phrases_;

    // Current user query (for context-aware responses)
    std::string current_query_;

    // Internal methods
    void play_acknowledgment();
    void play_waiting_phrase();
    void play_tone(int frequency_hz, int duration_ms, float volume);
    void generate_tone(std::vector<int16_t>& buffer, int frequency_hz, int duration_ms, float volume);
    std::string select_random_phrase(const std::vector<std::string>& phrases);

    // Initialize default phrases
    void init_default_phrases();
};

} // namespace openclaw
