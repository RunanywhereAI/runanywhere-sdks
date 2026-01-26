// =============================================================================
// Voice Pipeline - Implementation using runanywhere-commons Voice Agent
// =============================================================================

#include "voice_pipeline.h"
#include "model_config.h"

#include <rac/features/voice_agent/rac_voice_agent.h>
#include <rac/features/stt/rac_stt_component.h>
#include <rac/features/tts/rac_tts_component.h>
#include <rac/features/vad/rac_vad_component.h>
#include <rac/features/llm/rac_llm_component.h>
#include <rac/core/rac_error.h>

#include <vector>
#include <mutex>
#include <iostream>

namespace runanywhere {

// =============================================================================
// Implementation
// =============================================================================

struct VoicePipeline::Impl {
    rac_voice_agent_handle_t voice_agent = nullptr;

    // Audio accumulation buffer for VAD
    std::vector<float> audio_buffer;
    std::mutex buffer_mutex;

    // State
    bool speech_active = false;
    std::vector<int16_t> speech_buffer;
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
    if (impl_->voice_agent) {
        rac_voice_agent_destroy(impl_->voice_agent);
        impl_->voice_agent = nullptr;
    }
}

bool VoicePipeline::initialize() {
    if (initialized_) {
        return true;
    }

    // Initialize model system (sets base directory)
    if (!init_model_system()) {
        last_error_ = "Failed to initialize model system";
        return false;
    }

    // Check if all models are available
    if (!are_all_models_available()) {
        last_error_ = "One or more models are missing. Run scripts/download-models.sh";
        print_model_status();
        return false;
    }

    // Create standalone voice agent
    rac_result_t result = rac_voice_agent_create_standalone(&impl_->voice_agent);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to create voice agent";
        return false;
    }

    // Get model paths
    std::string stt_path = get_stt_model_path();
    std::string llm_path = get_llm_model_path();
    std::string tts_path = get_tts_model_path();

    std::cout << "Loading models..." << std::endl;

    // Load STT model
    std::cout << "  Loading STT: " << STT_MODEL_ID << std::endl;
    result = rac_voice_agent_load_stt_model(
        impl_->voice_agent,
        stt_path.c_str(),
        STT_MODEL_ID,
        "Whisper Tiny English"
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load STT model: " + stt_path;
        return false;
    }

    // Load LLM model
    std::cout << "  Loading LLM: " << LLM_MODEL_ID << std::endl;
    result = rac_voice_agent_load_llm_model(
        impl_->voice_agent,
        llm_path.c_str(),
        LLM_MODEL_ID,
        "Qwen2.5 0.5B"
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load LLM model: " + llm_path;
        return false;
    }

    // Load TTS voice
    std::cout << "  Loading TTS: " << TTS_MODEL_ID << std::endl;
    result = rac_voice_agent_load_tts_voice(
        impl_->voice_agent,
        tts_path.c_str(),
        TTS_MODEL_ID,
        "Piper Lessac US"
    );
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to load TTS voice: " + tts_path;
        return false;
    }

    // Initialize with loaded models
    result = rac_voice_agent_initialize_with_loaded_models(impl_->voice_agent);
    if (result != RAC_SUCCESS) {
        last_error_ = "Failed to initialize voice agent";
        return false;
    }

    std::cout << "All models loaded successfully!" << std::endl;
    initialized_ = true;
    return true;
}

bool VoicePipeline::is_ready() const {
    if (!impl_->voice_agent) {
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

    // Convert to float for VAD
    std::vector<float> float_samples(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        float_samples[i] = samples[i] / 32768.0f;
    }

    // Detect speech
    rac_bool_t is_speech = RAC_FALSE;
    rac_voice_agent_detect_speech(
        impl_->voice_agent,
        float_samples.data(),
        num_samples,
        &is_speech
    );

    bool speech_detected = (is_speech == RAC_TRUE);

    // Handle state transitions
    if (speech_detected && !impl_->speech_active) {
        // Speech started
        impl_->speech_active = true;
        impl_->speech_buffer.clear();
        if (config_.on_voice_activity) {
            config_.on_voice_activity(true);
        }
    }

    if (impl_->speech_active) {
        // Accumulate speech audio
        impl_->speech_buffer.insert(
            impl_->speech_buffer.end(),
            samples, samples + num_samples
        );
    }

    if (!speech_detected && impl_->speech_active) {
        // Speech ended - process the utterance
        impl_->speech_active = false;
        if (config_.on_voice_activity) {
            config_.on_voice_activity(false);
        }

        // Process the accumulated speech
        if (!impl_->speech_buffer.empty()) {
            process_voice_turn(
                impl_->speech_buffer.data(),
                impl_->speech_buffer.size()
            );
        }
    }
}

bool VoicePipeline::process_voice_turn(const int16_t* samples, size_t num_samples) {
    if (!initialized_) {
        return false;
    }

    // Use voice agent to process complete turn
    rac_voice_agent_result_t result = {};

    rac_result_t status = rac_voice_agent_process_voice_turn(
        impl_->voice_agent,
        samples,
        num_samples * sizeof(int16_t),
        &result
    );

    if (status != RAC_SUCCESS) {
        if (config_.on_error) {
            config_.on_error("Voice processing failed");
        }
        return false;
    }

    // Report transcription
    if (result.transcription && config_.on_transcription) {
        config_.on_transcription(result.transcription, true);
    }

    // Report LLM response
    if (result.response && config_.on_response) {
        config_.on_response(result.response, true);
    }

    // Report TTS audio
    if (result.synthesized_audio && result.synthesized_audio_size > 0 && config_.on_audio_output) {
        // Assume 22050 Hz output from TTS (common rate)
        config_.on_audio_output(
            static_cast<const int16_t*>(result.synthesized_audio),
            result.synthesized_audio_size / sizeof(int16_t),
            22050
        );
    }

    // Free result
    rac_voice_agent_result_free(&result);

    return result.speech_detected == RAC_TRUE;
}

void VoicePipeline::start() {
    running_ = true;
}

void VoicePipeline::stop() {
    running_ = false;
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
}

bool VoicePipeline::is_running() const {
    return running_;
}

void VoicePipeline::cancel() {
    // Cancel any ongoing generation
    // Note: Voice agent API may not support mid-generation cancellation
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
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

std::string VoicePipeline::get_llm_model_id() const {
    if (impl_->voice_agent) {
        const char* id = rac_voice_agent_get_llm_model_id(impl_->voice_agent);
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

} // namespace runanywhere
