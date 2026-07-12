// =============================================================================
// Voice Pipeline - Implementation using owned runanywhere-commons components
// =============================================================================

#include "voice_pipeline.h"
#include "config/model_config.h"

#include <rac/core/rac_error.h>
#include <rac/features/llm/rac_llm_component.h>
#include <rac/features/stt/rac_stt_component.h>
#include <rac/features/tts/rac_tts_component.h>
#include <rac/features/vad/rac_vad_component.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <iostream>
#include <mutex>
#include <vector>

namespace runanywhere {

namespace {

// Minimum silence duration before treating speech as ended.
constexpr double SILENCE_DURATION_SEC = 1.5;

// Require at least one second of 16 kHz input before processing a turn.
constexpr size_t MIN_SPEECH_SAMPLES = 16000;

std::string error_message(const char* operation, rac_result_t result) {
    const char* detail = rac_error_message(result);
    return std::string(operation) + " failed (" + std::to_string(result) + "): " +
           (detail ? detail : "unknown error");
}

bool deliver_tts_audio(const rac_tts_result_t& result, const AudioOutputCallback& callback) {
    if (!callback) {
        return true;
    }
    if (!result.audio_data || result.audio_size == 0 ||
        result.audio_size % sizeof(float) != 0 || result.sample_rate <= 0) {
        return false;
    }

    // The configured Sherpa TTS backend emits normalized float PCM.
    const auto* input = static_cast<const float*>(result.audio_data);
    const size_t sample_count = result.audio_size / sizeof(float);
    std::vector<int16_t> pcm16(sample_count);
    for (size_t i = 0; i < sample_count; ++i) {
        const float sample = std::clamp(input[i], -1.0f, 1.0f);
        pcm16[i] = static_cast<int16_t>(std::lround(sample * 32767.0f));
    }

    callback(pcm16.data(), pcm16.size(), result.sample_rate);
    return true;
}

}  // namespace

struct VoicePipeline::Impl {
    rac_handle_t stt_component = nullptr;
    rac_handle_t llm_component = nullptr;
    rac_handle_t tts_component = nullptr;
    rac_handle_t vad_component = nullptr;

    bool speech_active = false;
    std::vector<int16_t> speech_buffer;
    std::chrono::steady_clock::time_point last_speech_time;
    bool speech_callback_fired = false;
    std::mutex mutex;

    void reset_components() {
        if (vad_component) {
            rac_vad_component_destroy(vad_component);
            vad_component = nullptr;
        }
        if (tts_component) {
            rac_tts_component_destroy(tts_component);
            tts_component = nullptr;
        }
        if (llm_component) {
            rac_llm_component_destroy(llm_component);
            llm_component = nullptr;
        }
        if (stt_component) {
            rac_stt_component_destroy(stt_component);
            stt_component = nullptr;
        }
    }

    ~Impl() {
        reset_components();
    }
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
    impl_->reset_components();
}

bool VoicePipeline::initialize() {
    if (initialized_) {
        return true;
    }

    last_error_.clear();
    impl_->reset_components();

    if (!init_model_system()) {
        last_error_ = "Failed to initialize model system";
        return false;
    }

    if (!are_all_models_available()) {
        last_error_ = "One or more models are missing. Run scripts/download-models.sh";
        print_model_status();
        return false;
    }

    const std::string stt_path = get_stt_model_path();
    const std::string llm_path = get_llm_model_path();
    const std::string tts_path = get_tts_model_path();
    const std::string vad_path = get_vad_model_path();

    std::cout << "Loading models..." << std::endl;

    rac_result_t result = rac_stt_component_create(&impl_->stt_component);
    if (result == RAC_SUCCESS) {
        std::cout << "  Loading STT: " << STT_MODEL_ID << std::endl;
        result = rac_stt_component_load_model(impl_->stt_component, stt_path.c_str(),
                                              STT_MODEL_ID, "Whisper Tiny English");
    }
    if (result != RAC_SUCCESS) {
        last_error_ = error_message("STT initialization", result);
        impl_->reset_components();
        return false;
    }

    result = rac_llm_component_create(&impl_->llm_component);
    if (result == RAC_SUCCESS) {
        std::cout << "  Loading LLM: " << LLM_MODEL_ID << std::endl;
        result = rac_llm_component_load_model(impl_->llm_component, llm_path.c_str(),
                                              LLM_MODEL_ID, "Qwen3 1.7B");
    }
    if (result != RAC_SUCCESS) {
        last_error_ = error_message("LLM initialization", result);
        impl_->reset_components();
        return false;
    }

    result = rac_tts_component_create(&impl_->tts_component);
    if (result == RAC_SUCCESS) {
        std::cout << "  Loading TTS: " << TTS_MODEL_ID << std::endl;
        result = rac_tts_component_load_voice(impl_->tts_component, tts_path.c_str(),
                                              TTS_MODEL_ID, "Piper Lessac US");
    }
    if (result != RAC_SUCCESS) {
        last_error_ = error_message("TTS initialization", result);
        impl_->reset_components();
        return false;
    }

    result = rac_vad_component_create(&impl_->vad_component);
    if (result == RAC_SUCCESS) {
        rac_vad_config_t vad_config = RAC_VAD_CONFIG_DEFAULT;
        vad_config.sample_rate = config_.vad_sample_rate;
        vad_config.energy_threshold = config_.vad_threshold;
        result = rac_vad_component_configure(impl_->vad_component, &vad_config);
    }
    if (result == RAC_SUCCESS) {
        result = rac_vad_component_initialize(impl_->vad_component);
    }
    if (result == RAC_SUCCESS) {
        std::cout << "  Loading VAD: " << VAD_MODEL_ID << std::endl;
        result = rac_vad_component_load_model(impl_->vad_component, vad_path.c_str(),
                                              VAD_MODEL_ID, "Silero VAD");
    }
    if (result == RAC_SUCCESS) {
        result = rac_vad_component_set_energy_threshold(impl_->vad_component,
                                                        config_.vad_threshold);
    }
    if (result != RAC_SUCCESS) {
        last_error_ = error_message("VAD initialization", result);
        impl_->reset_components();
        return false;
    }

    std::cout << "All models loaded successfully!" << std::endl;
    initialized_ = true;
    return true;
}

bool VoicePipeline::is_ready() const {
    return initialized_ && impl_->stt_component && impl_->llm_component &&
           impl_->tts_component && impl_->vad_component &&
           rac_stt_component_is_loaded(impl_->stt_component) == RAC_TRUE &&
           rac_llm_component_is_loaded(impl_->llm_component) == RAC_TRUE &&
           rac_tts_component_is_loaded(impl_->tts_component) == RAC_TRUE &&
           rac_vad_component_is_loaded(impl_->vad_component) == RAC_TRUE;
}

void VoicePipeline::process_audio(const int16_t* samples, size_t num_samples) {
    if (!initialized_ || !running_ || !samples || num_samples == 0) {
        return;
    }

    std::lock_guard<std::mutex> lock(impl_->mutex);

    std::vector<float> float_samples(num_samples);
    for (size_t i = 0; i < num_samples; ++i) {
        float_samples[i] = samples[i] / 32768.0f;
    }

    rac_bool_t is_speech = RAC_FALSE;
    const rac_result_t result = rac_vad_component_process(
        impl_->vad_component, float_samples.data(), num_samples, &is_speech);
    if (result != RAC_SUCCESS) {
        if (config_.on_error) {
            config_.on_error(error_message("VAD processing", result));
        }
        return;
    }

    const bool speech_detected = is_speech == RAC_TRUE;
    const auto now = std::chrono::steady_clock::now();

    if (speech_detected) {
        impl_->last_speech_time = now;

        if (!impl_->speech_active) {
            impl_->speech_active = true;
            impl_->speech_buffer.clear();
            impl_->speech_callback_fired = false;
        }

        if (!impl_->speech_callback_fired &&
            impl_->speech_buffer.size() + num_samples >= MIN_SPEECH_SAMPLES) {
            impl_->speech_callback_fired = true;
            if (config_.on_voice_activity) {
                config_.on_voice_activity(true);
            }
        }
    }

    if (impl_->speech_active) {
        impl_->speech_buffer.insert(impl_->speech_buffer.end(), samples,
                                    samples + num_samples);
    }

    if (impl_->speech_active && !speech_detected) {
        const double silence_elapsed =
            std::chrono::duration<double>(now - impl_->last_speech_time).count();

        if (silence_elapsed >= SILENCE_DURATION_SEC) {
            impl_->speech_active = false;

            if (config_.on_voice_activity) {
                config_.on_voice_activity(false);
            }

            if (impl_->speech_buffer.size() >= MIN_SPEECH_SAMPLES) {
                process_voice_turn(impl_->speech_buffer.data(), impl_->speech_buffer.size());
            }

            impl_->speech_buffer.clear();
            impl_->speech_callback_fired = false;
            (void)rac_vad_component_reset(impl_->vad_component);
        }
    }
}

bool VoicePipeline::process_voice_turn(const int16_t* samples, size_t num_samples) {
    if (!is_ready() || !samples || num_samples == 0) {
        return false;
    }

    rac_stt_options_t stt_options = RAC_STT_OPTIONS_DEFAULT;
    stt_options.sample_rate = config_.vad_sample_rate;
    rac_stt_result_t stt_result = {};
    rac_result_t status = rac_stt_component_transcribe(
        impl_->stt_component, samples, num_samples * sizeof(int16_t), &stt_options,
        &stt_result);
    if (status != RAC_SUCCESS) {
        rac_stt_result_free(&stt_result);
        if (config_.on_error) {
            config_.on_error(error_message("Speech transcription", status));
        }
        return false;
    }

    const std::string transcription = stt_result.text ? stt_result.text : "";
    rac_stt_result_free(&stt_result);
    if (transcription.empty()) {
        return false;
    }
    if (config_.on_transcription) {
        config_.on_transcription(transcription, true);
    }

    rac_llm_options_t llm_options = RAC_LLM_OPTIONS_DEFAULT;
    llm_options.max_tokens = config_.max_tokens;
    llm_options.temperature = config_.temperature;
    llm_options.system_prompt = config_.system_prompt.c_str();

    rac_llm_result_t llm_result = {};
    status = rac_llm_component_generate(impl_->llm_component, transcription.c_str(),
                                        &llm_options, &llm_result);
    if (status != RAC_SUCCESS) {
        rac_llm_result_free(&llm_result);
        if (config_.on_error) {
            config_.on_error(error_message("Response generation", status));
        }
        return false;
    }

    const std::string response = llm_result.text ? llm_result.text : "";
    rac_llm_result_free(&llm_result);
    if (response.empty()) {
        if (config_.on_error) {
            config_.on_error("Response generation returned empty text");
        }
        return false;
    }
    if (config_.on_response) {
        config_.on_response(response, true);
    }

    rac_tts_options_t tts_options = RAC_TTS_OPTIONS_DEFAULT;
    tts_options.rate = config_.speaking_rate;
    rac_tts_result_t tts_result = {};
    status = rac_tts_component_synthesize(impl_->tts_component, response.c_str(),
                                          &tts_options, &tts_result);
    if (status != RAC_SUCCESS) {
        rac_tts_result_free(&tts_result);
        if (config_.on_error) {
            config_.on_error(error_message("Speech synthesis", status));
        }
        return false;
    }

    const bool delivered = deliver_tts_audio(tts_result, config_.on_audio_output);
    rac_tts_result_free(&tts_result);
    if (!delivered && config_.on_error) {
        config_.on_error("Speech synthesis returned invalid audio");
    }
    return delivered;
}

bool VoicePipeline::speak_text(const std::string& text) {
    if (!is_ready() || text.empty()) {
        return false;
    }

    rac_tts_options_t options = RAC_TTS_OPTIONS_DEFAULT;
    options.rate = config_.speaking_rate;
    rac_tts_result_t result = {};
    const rac_result_t status = rac_tts_component_synthesize(
        impl_->tts_component, text.c_str(), &options, &result);
    if (status != RAC_SUCCESS) {
        rac_tts_result_free(&result);
        if (config_.on_error) {
            config_.on_error(error_message("Speech synthesis", status));
        }
        return false;
    }

    const bool delivered = deliver_tts_audio(result, config_.on_audio_output);
    rac_tts_result_free(&result);
    if (!delivered && config_.on_error) {
        config_.on_error("Speech synthesis returned invalid audio");
    }
    return delivered;
}

void VoicePipeline::start() {
    if (!initialized_ || !impl_->vad_component) {
        return;
    }
    const rac_result_t result = rac_vad_component_start(impl_->vad_component);
    if (result != RAC_SUCCESS) {
        last_error_ = error_message("VAD start", result);
        if (config_.on_error) {
            config_.on_error(last_error_);
        }
        return;
    }
    running_ = true;
}

void VoicePipeline::stop() {
    running_ = false;
    if (impl_->vad_component) {
        (void)rac_vad_component_stop(impl_->vad_component);
    }
    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
    impl_->speech_callback_fired = false;
}

bool VoicePipeline::is_running() const {
    return running_;
}

void VoicePipeline::cancel() {
    if (impl_->llm_component) {
        (void)rac_llm_component_cancel(impl_->llm_component);
    }
    if (impl_->tts_component) {
        (void)rac_tts_component_stop(impl_->tts_component);
    }

    std::lock_guard<std::mutex> lock(impl_->mutex);
    impl_->speech_active = false;
    impl_->speech_buffer.clear();
    impl_->speech_callback_fired = false;
}

void VoicePipeline::set_config(const VoicePipelineConfig& config) {
    config_ = config;
}

std::string VoicePipeline::get_stt_model_id() const {
    if (!impl_->stt_component) {
        return "";
    }
    const char* id = rac_stt_component_get_model_id(impl_->stt_component);
    return id ? id : "";
}

std::string VoicePipeline::get_llm_model_id() const {
    if (!impl_->llm_component) {
        return "";
    }
    const char* id = rac_llm_component_get_model_id(impl_->llm_component);
    return id ? id : "";
}

std::string VoicePipeline::get_tts_model_id() const {
    if (!impl_->tts_component) {
        return "";
    }
    const char* id = rac_tts_component_get_voice_id(impl_->tts_component);
    return id ? id : "";
}

}  // namespace runanywhere
