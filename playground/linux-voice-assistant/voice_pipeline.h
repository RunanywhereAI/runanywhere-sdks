#pragma once

// =============================================================================
// Voice Pipeline - Orchestration of VAD -> STT -> LLM -> TTS
// =============================================================================
// Wraps the runanywhere-commons Voice Agent to provide a simple interface
// for the voice assistant application.
//
// Pipeline flow:
// 1. VAD: Detect speech in audio
// 2. STT: Transcribe speech to text
// 3. LLM: Generate response
// 4. TTS: Synthesize speech from response
// =============================================================================

#include <functional>
#include <memory>
#include <string>
#include <cstdint>

namespace runanywhere {

// =============================================================================
// Callbacks
// =============================================================================

// Called when wake word is detected
using WakeWordCallback = std::function<void(const std::string& wake_word, float confidence)>;

// Called when speech is detected/ended
using VoiceActivityCallback = std::function<void(bool is_speaking)>;

// Called when transcription is available
using TranscriptionCallback = std::function<void(const std::string& text, bool is_final)>;

// Called when LLM response is available
using ResponseCallback = std::function<void(const std::string& text, bool is_complete)>;

// Called when TTS audio is available
using AudioOutputCallback = std::function<void(const int16_t* samples, size_t num_samples, int sample_rate)>;

// Called on errors
using ErrorCallback = std::function<void(const std::string& error)>;

// =============================================================================
// Pipeline Configuration
// =============================================================================

struct VoicePipelineConfig {
    // Callbacks (required)
    WakeWordCallback on_wake_word;
    VoiceActivityCallback on_voice_activity;
    TranscriptionCallback on_transcription;
    ResponseCallback on_response;
    AudioOutputCallback on_audio_output;
    ErrorCallback on_error;

    // Wake word settings (optional)
    bool enable_wake_word = false;
    std::string wake_word = "Hey Jarvis";
    float wake_word_threshold = 0.5f;

    // VAD settings
    float vad_energy_threshold = 0.005f;
    int vad_sample_rate = 16000;

    // LLM settings
    std::string system_prompt = "You are a helpful voice assistant. Keep your responses concise and conversational.";
    int max_tokens = 256;
    float temperature = 0.7f;

    // TTS settings
    float speaking_rate = 1.0f;

    // Moltbot integration (optional)
    // When enabled, transcriptions are sent to Moltbot voice bridge instead of local LLM
    bool enable_moltbot = false;
    std::string moltbot_voice_bridge_url = "http://localhost:8081";
    std::string moltbot_session_id = "voice-session";
};

// =============================================================================
// Voice Pipeline
// =============================================================================

class VoicePipeline {
public:
    VoicePipeline();
    explicit VoicePipeline(const VoicePipelineConfig& config);
    ~VoicePipeline();

    // Non-copyable
    VoicePipeline(const VoicePipeline&) = delete;
    VoicePipeline& operator=(const VoicePipeline&) = delete;

    // Initialize pipeline (loads models)
    bool initialize();

    // Check if ready
    bool is_ready() const;

    // Process audio input (call this with microphone audio)
    // audio: 16-bit PCM, 16kHz, mono
    void process_audio(const int16_t* samples, size_t num_samples);

    // Process a complete voice turn (batch mode)
    // Returns true if speech was detected and processed
    bool process_voice_turn(const int16_t* samples, size_t num_samples);

    // Start/stop continuous processing
    void start();
    void stop();
    bool is_running() const;

    // Cancel current generation
    void cancel();

    // Update configuration
    void set_config(const VoicePipelineConfig& config);
    const VoicePipelineConfig& config() const { return config_; }

    // Get last error
    const std::string& last_error() const { return last_error_; }

    // Model information
    std::string get_stt_model_id() const;
    std::string get_llm_model_id() const;
    std::string get_tts_model_id() const;

    // Poll Moltbot voice bridge for speak commands (from other channels)
    // Returns true if a message was spoken
    bool poll_speak_queue();

    // Synthesize and play text via TTS
    bool speak_text(const std::string& text);

private:
    // Initialize wake word detector
    bool initialize_wakeword();

    // Process voice turn via Moltbot integration (STT -> Moltbot -> TTS)
    bool process_voice_turn_moltbot(const int16_t* samples, size_t num_samples);

    struct Impl;
    std::unique_ptr<Impl> impl_;

    VoicePipelineConfig config_;
    std::string last_error_;
    bool initialized_ = false;
    bool running_ = false;
};

} // namespace runanywhere
