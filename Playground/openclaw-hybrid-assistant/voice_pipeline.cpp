// =============================================================================
// Voice Pipeline - Implementation
// =============================================================================
// Simplified pipeline for OpenClaw: Wake Word → VAD → STT → (send to OpenClaw)
// TTS is called separately when speak commands arrive.
// Uses rac_voice_agent API - NO LLM loaded.
// =============================================================================

#include "voice_pipeline.h"
#include "model_config.h"

// RAC headers - use voice_agent for unified API
#include <rac/features/voice_agent/rac_voice_agent.h>
#include <rac/backends/rac_wakeword_onnx.h>
#include <rac/core/rac_error.h>

#include <vector>
#include <mutex>
#include <iostream>
#include <chrono>
#include <cstring>

namespace openclaw {

// =============================================================================
// Constants
// =============================================================================

// Silence duration before treating speech as ended
static constexpr double DEFAULT_SILENCE_DURATION_SEC = 1.5;

// Minimum speech samples before processing (avoid false triggers)
static constexpr size_t DEFAULT_MIN_SPEECH_SAMPLES = 16000;  // 1 second at 16kHz

// Wake word timeout - return to listening after this many seconds of no speech
static constexpr double WAKE_WORD_TIMEOUT_SEC = 10.0;

// =============================================================================
// Implementation
// =============================================================================

struct VoicePipeline::Impl {
    // Voice agent handle (for VAD, STT, TTS)
    rac_voice_agent_handle_t voice_agent = nullptr;

    // Wake word detector (separate from voice agent)
    rac_handle_t wakeword_handle = nullptr;
    bool wakeword_enabled = false;
    bool wakeword_activated = false;
    std::chrono::steady_clock::time_point wakeword_activation_time;

    // Speech state
    bool speech_active = false;
    std::vector<int16_t> speech_buffer;
    std::chrono::steady_clock::time_point last_speech_time;
    bool speech_callback_fired = false;

    // Mutex for thread safety
    std::mutex mutex;
};

VoicePipeline::VoicePipeline()
    : impl_(std::make_unique<Impl>()) {
}

VoicePipeline::VoicePipeline(const VoicePipelineConfig& config)
    : impl_(std::make_unique<Impl>())
    , config_(config) {
}

VoicePipeline::~VoicePipeline() {
    stop();

    if (impl_->wakeword_handle) {
        rac_wakeword_onnx_destroy(impl_->wakeword_handle);
        impl_->wakeword_handle = nullptr;
    }
    if (impl_->voice_agent) {
        rac_voice_agent_destroy(impl_->voice_agent);
        impl_->voice_agent = nullptr;
    }
}

bool VoicePipeline::initialize() {
    if (initialized_) {
        return true;
    }

    // Initialize model system
    if (!init_model_system()) {
        last_error_ = "Failed to initialize model system";
        state_ = PipelineState::ERROR;
        return false;
    }

    // Check required models
    if (!are_all_models_available()) {
        last_error_ = "Required models are missing. Run scripts/download-models.sh";
        print_model_status(config_.enable_wake_word);
        state_ = PipelineState::ERROR;
        return false;
    }

    std::cout << "[Pipeline] Initializing components (NO LLM)...\n";

    // Create standalone voice agent
    rac_result_t result = rac_voice_agent_create_standalone(&impl_->voice_agent);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to create voice agent";
        state_ = PipelineState::ERROR;
        return false;
    }

    // Get model paths
    std::string stt_path = get_stt_model_path();
    std::string tts_path = get_tts_model_path();

    // Load STT model
    std::cout << "  Loading STT: " << STT_MODEL_ID << "\n";
    result = rac_voice_agent_load_stt_model(
        impl_->voice_agent,
        stt_path.c_str(),
        STT_MODEL_ID,
        "Whisper Tiny English"
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load STT model: " + stt_path;
        state_ = PipelineState::ERROR;
        return false;
    }

    // Skip LLM - we don't need it for OpenClaw channel
    std::cout << "  LLM: skipped (OpenClaw mode - no local LLM)\n";

    // Load TTS voice
    std::cout << "  Loading TTS: " << TTS_MODEL_ID << "\n";
    result = rac_voice_agent_load_tts_voice(
        impl_->voice_agent,
        tts_path.c_str(),
        TTS_MODEL_ID,
        "Piper Lessac US"
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load TTS voice: " + tts_path;
        state_ = PipelineState::ERROR;
        return false;
    }

    // Initialize with loaded models
    result = rac_voice_agent_initialize_with_loaded_models(impl_->voice_agent);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to initialize voice agent";
        state_ = PipelineState::ERROR;
        return false;
    }

    // Initialize Wake Word (optional)
    if (config_.enable_wake_word) {
        std::cout << "  Loading Wake Word: " << WAKEWORD_MODEL_ID << "\n";
        if (!initialize_wakeword()) {
            std::cerr << "[Pipeline] Wake word init failed, continuing without it\n";
            impl_->wakeword_enabled = false;
        } else {
            impl_->wakeword_enabled = true;
            std::cout << "  Wake word enabled: \"" << config_.wake_word << "\"\n";
        }
    }

    std::cout << "[Pipeline] All components loaded successfully!\n";
    initialized_ = true;
    state_ = impl_->wakeword_enabled ? PipelineState::WAITING_FOR_WAKE_WORD : PipelineState::LISTENING;

    return true;
}

bool VoicePipeline::initialize_wakeword() {
    if (!are_wakeword_models_available()) {
        last_error_ = "Wake word models not available";
        return false;
    }

    // Create wake word detector
    rac_wakeword_onnx_config_t ww_config = RAC_WAKEWORD_ONNX_CONFIG_DEFAULT;
    ww_config.threshold = config_.wake_word_threshold;

    rac_result_t result = rac_wakeword_onnx_create(&ww_config, &impl_->wakeword_handle);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to create wake word detector";
        return false;
    }

    // Load shared models
    std::string embedding_path = get_wakeword_embedding_path();
    std::string melspec_path = get_wakeword_melspec_path();
    std::string wakeword_path = get_wakeword_model_path();

    result = rac_wakeword_onnx_init_shared_models(
        impl_->wakeword_handle,
        embedding_path.c_str(),
        melspec_path.c_str()
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load wake word embedding model";
        rac_wakeword_onnx_destroy(impl_->wakeword_handle);
        impl_->wakeword_handle = nullptr;
        return false;
    }

    // Load wake word model
    result = rac_wakeword_onnx_load_model(
        impl_->wakeword_handle,
        wakeword_path.c_str(),
        WAKEWORD_MODEL_ID,
        config_.wake_word.c_str()
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load wake word model";
        rac_wakeword_onnx_destroy(impl_->wakeword_handle);
        impl_->wakeword_handle = nullptr;
        return false;
    }

    return true;
}

void VoicePipeline::start() {
    running_ = true;
    impl_->wakeword_activated = false;
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
    impl_->speech_callback_fired = false;

    if (impl_->wakeword_enabled) {
        state_ = PipelineState::WAITING_FOR_WAKE_WORD;
    } else {
        state_ = PipelineState::LISTENING;
    }
}

void VoicePipeline::stop() {
    running_ = false;
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
    impl_->speech_callback_fired = false;
    impl_->wakeword_activated = false;
}

bool VoicePipeline::is_running() const {
    return running_;
}

bool VoicePipeline::is_ready() const {
    if (!initialized_ || !impl_->voice_agent) {
        return false;
    }
    rac_bool_t ready = RAC_FALSE;
    rac_voice_agent_is_ready(impl_->voice_agent, &ready);
    return ready == RAC_TRUE;
}

void VoicePipeline::process_audio(const int16_t* samples, size_t num_samples) {
    if (!initialized_ || !running_) {
        return;
    }

    std::lock_guard<std::mutex> lock(impl_->mutex);

    // Convert to float for processing
    // NOTE: Different components need different normalization:
    // - Wake word (openWakeWord): Raw int16 cast to float (no normalization)
    // - VAD/STT: Normalized to [-1, 1] (divide by 32768)
    std::vector<float> float_samples(num_samples);
    std::vector<float> float_samples_raw(num_samples);  // For wake word (unnormalized)
    for (size_t i = 0; i < num_samples; ++i) {
        float_samples[i] = samples[i] / 32768.0f;       // Normalized for VAD/STT
        float_samples_raw[i] = static_cast<float>(samples[i]);  // Raw for wake word
    }

    auto now = std::chrono::steady_clock::now();

    // Stage 1: Wake Word Detection (if enabled and not activated)
    if (impl_->wakeword_enabled && !impl_->wakeword_activated) {
        process_wakeword(float_samples_raw.data(), num_samples);  // Use raw (unnormalized) for openWakeWord
        return;  // Don't process further until wake word detected
    }

    // Check wake word timeout
    if (impl_->wakeword_enabled && impl_->wakeword_activated && !impl_->speech_active) {
        double elapsed = std::chrono::duration<double>(
            now - impl_->wakeword_activation_time
        ).count();

        if (elapsed >= WAKE_WORD_TIMEOUT_SEC) {
            if (config_.debug_wakeword) {
                std::cout << "[WakeWord] Timeout, returning to wake word mode\n";
            }
            impl_->wakeword_activated = false;
            impl_->speech_buffer.clear();
            impl_->speech_callback_fired = false;
            state_ = PipelineState::WAITING_FOR_WAKE_WORD;
            return;
        }
    }

    // Stage 2: VAD + Speech Buffering
    process_vad(float_samples.data(), num_samples, samples);
}

void VoicePipeline::process_wakeword(const float* samples, size_t num_samples) {
    if (!impl_->wakeword_handle) {
        return;
    }

    int32_t detected_index = -1;
    float confidence = 0.0f;

    rac_result_t result = rac_wakeword_onnx_process(
        impl_->wakeword_handle,
        samples,
        num_samples,
        &detected_index,
        &confidence
    );

    if (config_.debug_wakeword && confidence > 0.1f) {
        std::cout << "[WakeWord] Confidence: " << confidence << "\n";
    }

    if (result == RAC_SUCCESS && detected_index >= 0) {
        // Wake word detected!
        impl_->wakeword_activated = true;
        impl_->wakeword_activation_time = std::chrono::steady_clock::now();
        impl_->speech_buffer.clear();
        impl_->speech_active = false;
        impl_->speech_callback_fired = false;
        state_ = PipelineState::LISTENING;

        std::cout << "[WakeWord] Detected: \"" << config_.wake_word
                  << "\" (confidence: " << confidence << ")\n";

        if (config_.on_wake_word) {
            config_.on_wake_word(config_.wake_word, confidence);
        }
    }
}

void VoicePipeline::process_vad(const float* samples, size_t num_samples, const int16_t* raw_samples) {
    if (!impl_->voice_agent) {
        return;
    }

    auto now = std::chrono::steady_clock::now();

    // Detect speech using voice agent's VAD
    rac_bool_t is_speech = RAC_FALSE;
    rac_voice_agent_detect_speech(
        impl_->voice_agent,
        samples,
        num_samples,
        &is_speech
    );

    bool speech_detected = (is_speech == RAC_TRUE);

    if (config_.debug_vad) {
        static int frame_count = 0;
        if (++frame_count % 50 == 0) {  // Log every 50 frames
            std::cout << "[VAD] Speech: " << (speech_detected ? "YES" : "no")
                      << ", Buffer: " << impl_->speech_buffer.size() << " samples\n";
        }
    }

    if (speech_detected) {
        // Update timestamps
        impl_->last_speech_time = now;

        if (impl_->wakeword_enabled) {
            impl_->wakeword_activation_time = now;
        }

        if (!impl_->speech_active) {
            // Speech just started
            impl_->speech_active = true;
            impl_->speech_buffer.clear();
            impl_->speech_callback_fired = false;

            if (config_.debug_vad) {
                std::cout << "[VAD] Speech started\n";
            }
        }

        // Fire "listening" callback once we have enough samples
        size_t min_samples = config_.min_speech_samples > 0 ? config_.min_speech_samples : DEFAULT_MIN_SPEECH_SAMPLES;
        if (!impl_->speech_callback_fired && impl_->speech_buffer.size() + num_samples >= min_samples / 2) {
            impl_->speech_callback_fired = true;
            if (config_.on_voice_activity) {
                config_.on_voice_activity(true);
            }
        }
    }

    // Accumulate audio while speech session is active
    if (impl_->speech_active) {
        impl_->speech_buffer.insert(
            impl_->speech_buffer.end(),
            raw_samples, raw_samples + num_samples
        );
    }

    // Check for end of speech (silence timeout)
    double silence_duration = config_.silence_duration_sec > 0 ? config_.silence_duration_sec : DEFAULT_SILENCE_DURATION_SEC;

    if (impl_->speech_active && !speech_detected) {
        double silence_elapsed = std::chrono::duration<double>(
            now - impl_->last_speech_time
        ).count();

        if (silence_elapsed >= silence_duration) {
            // End of speech
            impl_->speech_active = false;
            state_ = PipelineState::PROCESSING_STT;

            if (config_.debug_vad) {
                std::cout << "[VAD] Speech ended, " << impl_->speech_buffer.size()
                          << " samples buffered\n";
            }

            if (config_.on_voice_activity) {
                config_.on_voice_activity(false);
            }

            // Process STT if we have enough speech
            size_t min_samples = config_.min_speech_samples > 0 ? config_.min_speech_samples : DEFAULT_MIN_SPEECH_SAMPLES;
            if (impl_->speech_buffer.size() >= min_samples) {
                process_stt(impl_->speech_buffer.data(), impl_->speech_buffer.size());
            } else if (config_.debug_stt) {
                std::cout << "[STT] Not enough speech (" << impl_->speech_buffer.size()
                          << " < " << min_samples << ")\n";
            }

            // Reset state
            impl_->speech_buffer.clear();
            impl_->speech_callback_fired = false;

            // Return to wake word mode if enabled
            if (impl_->wakeword_enabled) {
                impl_->wakeword_activated = false;
                rac_wakeword_onnx_reset(impl_->wakeword_handle);
                state_ = PipelineState::WAITING_FOR_WAKE_WORD;
            } else {
                state_ = PipelineState::LISTENING;
            }
        }
    }
}

bool VoicePipeline::process_stt(const int16_t* samples, size_t num_samples) {
    if (!impl_->voice_agent) {
        return false;
    }

    if (config_.debug_stt) {
        std::cout << "[STT] Processing " << num_samples << " samples ("
                  << (float)num_samples / 16000.0f << "s)\n";
    }

    // Transcribe using voice agent
    char* transcription_ptr = nullptr;
    rac_result_t result = rac_voice_agent_transcribe(
        impl_->voice_agent,
        samples,
        num_samples * sizeof(int16_t),
        &transcription_ptr
    );

    if (result != RAC_SUCCESS || !transcription_ptr || strlen(transcription_ptr) == 0) {
        if (config_.on_error) {
            config_.on_error("STT transcription failed");
        }
        if (transcription_ptr) {
            free(transcription_ptr);
        }
        return false;
    }

    std::string transcription = transcription_ptr;
    free(transcription_ptr);

    std::cout << "[STT] Transcription: \"" << transcription << "\"\n";

    // Fire callback (this will send to OpenClaw)
    if (config_.on_transcription) {
        config_.on_transcription(transcription, true);
    }

    return true;
}

bool VoicePipeline::speak_text(const std::string& text) {
    if (!initialized_ || !impl_->voice_agent) {
        return false;
    }

    std::cout << "[TTS] Synthesizing: \"" << text << "\"\n";
    state_ = PipelineState::SPEAKING;

    // Synthesize speech using voice agent
    void* audio_data = nullptr;
    size_t audio_size = 0;

    rac_result_t result = rac_voice_agent_synthesize_speech(
        impl_->voice_agent,
        text.c_str(),
        &audio_data,
        &audio_size
    );

    if (result != RAC_SUCCESS || !audio_data || audio_size == 0) {
        if (config_.on_error) {
            config_.on_error("TTS synthesis failed");
        }
        state_ = impl_->wakeword_enabled ? PipelineState::WAITING_FOR_WAKE_WORD : PipelineState::LISTENING;
        return false;
    }

    // Output audio via callback
    if (config_.on_audio_output) {
        config_.on_audio_output(
            static_cast<const int16_t*>(audio_data),
            audio_size / sizeof(int16_t),
            22050  // TTS sample rate
        );
    }

    free(audio_data);
    state_ = impl_->wakeword_enabled ? PipelineState::WAITING_FOR_WAKE_WORD : PipelineState::LISTENING;

    return true;
}

std::string VoicePipeline::state_string() const {
    switch (state_) {
        case PipelineState::NOT_INITIALIZED: return "NOT_INITIALIZED";
        case PipelineState::WAITING_FOR_WAKE_WORD: return "WAITING_FOR_WAKE_WORD";
        case PipelineState::LISTENING: return "LISTENING";
        case PipelineState::PROCESSING_STT: return "PROCESSING_STT";
        case PipelineState::SPEAKING: return "SPEAKING";
        case PipelineState::ERROR: return "ERROR";
        default: return "UNKNOWN";
    }
}

void VoicePipeline::set_config(const VoicePipelineConfig& config) {
    config_ = config;
}

std::string VoicePipeline::get_stt_model_id() const {
    if (impl_->voice_agent) {
        const char* id = rac_voice_agent_get_stt_model_id(impl_->voice_agent);
        return id ? id : "";
    }
    return "";
}

std::string VoicePipeline::get_tts_model_id() const {
    if (impl_->voice_agent) {
        const char* id = rac_voice_agent_get_tts_voice_id(impl_->voice_agent);
        return id ? id : "";
    }
    return "";
}

// =============================================================================
// Component Testers
// =============================================================================

bool test_wakeword(const std::string& wav_path, float threshold) {
    std::cout << "[Test] Wake word test not yet implemented\n";
    return false;
}

bool test_vad(const std::string& wav_path) {
    std::cout << "[Test] VAD test not yet implemented\n";
    return false;
}

std::string test_stt(const std::string& wav_path) {
    std::cout << "[Test] STT test not yet implemented\n";
    return "";
}

bool test_tts(const std::string& text, const std::string& output_path) {
    std::cout << "[Test] TTS test not yet implemented\n";
    return false;
}

} // namespace openclaw
