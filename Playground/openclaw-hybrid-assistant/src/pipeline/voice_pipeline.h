#pragma once

// =============================================================================
// Voice Pipeline for OpenClaw Hybrid Assistant
// =============================================================================
// Simplified pipeline - NO LLM:
// - Wake Word Detection (openWakeWord)
// - Voice Activity Detection (Silero VAD)
// - Speech-to-Text (Parakeet TDT-CTC / NeMo CTC)
// - Text-to-Speech (Piper)
//
// ASR results are sent to OpenClaw via callback (fire-and-forget).
// TTS is triggered externally when speak commands arrive from OpenClaw.
// =============================================================================

#include <string>
#include <functional>
#include <memory>
#include <cstdint>
#include <atomic>
#include <thread>
#include <mutex>

namespace openclaw {

// =============================================================================
// Pipeline Configuration
// =============================================================================

struct VoicePipelineConfig {
    // Wake word settings
    bool enable_wake_word = false;
    std::string wake_word = "Hey Jarvis";
    float wake_word_threshold = 0.5f;

    // VAD settings
    float vad_threshold = 0.5f;
    double silence_duration_sec = 1.5;
    size_t min_speech_samples = 16000;  // 1 second at 16kHz

    // VAD noise robustness settings (for noisy environments like Pi with fan)
    int speech_start_frames = 3;           // Consecutive speech frames needed to start (debounce)
    int noise_burst_max_frames = 2;        // Isolated bursts shorter than this don't reset silence timer
    double max_speech_duration_sec = 60.0; // Force-end speech after this long (prevents infinite buffering)

    // Callbacks
    std::function<void(const std::string&, float)> on_wake_word;           // Wake word detected
    std::function<void(bool)> on_voice_activity;                           // Speech started/stopped
    std::function<void(const std::string&, bool)> on_transcription;        // ASR result
    std::function<void(const int16_t*, size_t, int, const std::atomic<bool>&)> on_audio_output;  // TTS audio (with cancel flag)
    std::function<void()> on_audio_stop;                                   // Force-stop ALSA playback immediately
    std::function<void()> on_cancel_pending_responses;                     // Clear stale speak messages on barge-in
    std::function<void(const std::string&)> on_error;                      // Error occurred
    std::function<void()> on_speech_interrupted;                            // Wake word barge-in during TTS

    // Debug settings
    bool debug_wakeword = false;
    bool debug_vad = false;
    bool debug_stt = false;
    bool debug_audio = false;   // Log mic input levels (RMS, peak) every ~1s
};

// =============================================================================
// Pipeline State
// =============================================================================

enum class PipelineState {
    NOT_INITIALIZED,
    WAITING_FOR_WAKE_WORD,
    LISTENING,
    PROCESSING_STT,
    SPEAKING,
    ERROR
};

// =============================================================================
// Voice Pipeline
// =============================================================================

class VoicePipeline {
public:
    VoicePipeline();
    explicit VoicePipeline(const VoicePipelineConfig& config);
    ~VoicePipeline();

    // Lifecycle
    bool initialize();
    void start();
    void stop();
    bool is_running() const;
    bool is_ready() const;

    // Audio input (from microphone)
    void process_audio(const int16_t* samples, size_t num_samples);

    // TTS output (called when speak command received from OpenClaw)
    bool speak_text(const std::string& text);

    // Async TTS - returns immediately, synthesis + playback runs in background.
    // Sentences are pre-synthesized ahead of playback for gapless audio.
    void speak_text_async(const std::string& text);

    // Cancel any in-progress async TTS playback immediately.
    void cancel_speech();

    // Check if async TTS is currently playing or synthesizing.
    bool is_speaking() const;

    // State
    PipelineState state() const { return state_.load(); }
    std::string state_string() const;

    // Configuration
    void set_config(const VoicePipelineConfig& config);
    const VoicePipelineConfig& config() const { return config_; }

    // Model info
    std::string get_stt_model_id() const;
    std::string get_tts_model_id() const;

    // Error handling
    std::string last_error() const { return last_error_; }

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;

    VoicePipelineConfig config_;
    std::atomic<PipelineState> state_{PipelineState::NOT_INITIALIZED};
    std::string last_error_;
    std::atomic<bool> initialized_{false};
    std::atomic<bool> running_{false};

    // Async TTS state
    struct AsyncTTSState;
    std::unique_ptr<AsyncTTSState> async_tts_;

    // Internal methods
    bool initialize_wakeword();
    bool initialize_stt();
    bool initialize_tts();
    bool initialize_vad();

    void process_wakeword(const float* samples, size_t num_samples);
    void process_vad(const float* samples, size_t num_samples, const int16_t* raw_samples);
    bool process_stt(const int16_t* samples, size_t num_samples);
};

// =============================================================================
// Component Testers (for debugging individual components)
// =============================================================================

// Test wake word detection on a WAV file
bool test_wakeword(const std::string& wav_path, float threshold = 0.5f);

// Test VAD on a WAV file
bool test_vad(const std::string& wav_path);

// Test STT on a WAV file
std::string test_stt(const std::string& wav_path);

// Test TTS
bool test_tts(const std::string& text, const std::string& output_path);

} // namespace openclaw
