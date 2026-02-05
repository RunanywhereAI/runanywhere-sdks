/**
 * WhisperCPP Backend Implementation
 *
 * Speech-to-Text via whisper.cpp
 */

#include "whispercpp_backend.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <iomanip>
#include <sstream>

#include "rac/core/rac_logger.h"

// Use the RAC logging system
#define LOGI(...) RAC_LOG_INFO("STT.WhisperCpp", __VA_ARGS__)
#define LOGE(...) RAC_LOG_ERROR("STT.WhisperCpp", __VA_ARGS__)
#define LOGW(...) RAC_LOG_WARNING("STT.WhisperCpp", __VA_ARGS__)

// Whisper sample rate constant
#ifndef WHISPER_SAMPLE_RATE
#define WHISPER_SAMPLE_RATE 16000
#endif

namespace runanywhere {

// =============================================================================
// WHISPERCPP BACKEND IMPLEMENTATION
// =============================================================================

WhisperCppBackend::WhisperCppBackend() {
    LOGI("WhisperCppBackend created");
}

WhisperCppBackend::~WhisperCppBackend() {
    cleanup();
    LOGI("WhisperCppBackend destroyed");
}

bool WhisperCppBackend::initialize(const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (initialized_) {
        LOGI("WhisperCppBackend already initialized");
        return true;
    }

    config_ = config;

    if (config.contains("num_threads")) {
        num_threads_ = config["num_threads"].get<int>();
    }
    if (num_threads_ <= 0) {
#if defined(_SC_NPROCESSORS_ONLN)
        num_threads_ =
            std::max(1, std::min(8, static_cast<int>(sysconf(_SC_NPROCESSORS_ONLN)) - 2));
#else
        num_threads_ = 4;
#endif
    }

    if (config.contains("use_gpu")) {
        use_gpu_ = config["use_gpu"].get<bool>();
    }

    LOGI("WhisperCppBackend initialized with %d threads, GPU: %s", num_threads_,
         use_gpu_ ? "enabled" : "disabled");

    create_stt();
    initialized_ = true;
    return true;
}

bool WhisperCppBackend::is_initialized() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return initialized_;
}

void WhisperCppBackend::cleanup() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!initialized_) {
        return;
    }

    stt_.reset();
    initialized_ = false;
    LOGI("WhisperCppBackend cleaned up");
}

void WhisperCppBackend::create_stt() {
    stt_ = std::make_unique<WhisperCppSTT>(this);
    LOGI("Created STT component");
}

DeviceType WhisperCppBackend::get_device_type() const {
#if defined(GGML_USE_METAL)
    return DeviceType::METAL;
#elif defined(GGML_USE_CUDA)
    return DeviceType::CUDA;
#else
    return DeviceType::CPU;
#endif
}

size_t WhisperCppBackend::get_memory_usage() const {
    return 0;
}

// =============================================================================
// WHISPERCPP STT IMPLEMENTATION
// =============================================================================

WhisperCppSTT::WhisperCppSTT(WhisperCppBackend* backend) : backend_(backend) {
    LOGI("WhisperCppSTT created");
}

WhisperCppSTT::~WhisperCppSTT() {
    unload_model();

    for (auto& [id, state] : streams_) {
        if (state && state->state) {
            whisper_free_state(state->state);
        }
    }
    streams_.clear();

    LOGI("WhisperCppSTT destroyed");
}

bool WhisperCppSTT::is_ready() const {
    return model_loaded_ && ctx_ != nullptr;
}

bool WhisperCppSTT::load_model(const std::string& model_path, STTModelType model_type,
                               const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (model_loaded_ && ctx_) {
        LOGI("Unloading previous model");
        whisper_free(ctx_);
        ctx_ = nullptr;
        model_loaded_ = false;
    }

    LOGI("Loading whisper model from: %s", model_path.c_str());

    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = backend_->is_gpu_enabled();

    if (config.contains("word_timestamps") && config["word_timestamps"].get<bool>()) {
        cparams.dtw_token_timestamps = true;
        cparams.dtw_aheads_preset = WHISPER_AHEADS_LARGE_V3;
    }

    if (config.contains("flash_attention")) {
        cparams.flash_attn = config["flash_attention"].get<bool>();
    }

    ctx_ = whisper_init_from_file_with_params(model_path.c_str(), cparams);

    if (!ctx_) {
        LOGE("Failed to load whisper model from: %s", model_path.c_str());
        return false;
    }

    model_path_ = model_path;
    model_config_ = config;
    model_loaded_ = true;

    LOGI("Whisper model loaded successfully. Multilingual: %s",
         whisper_is_multilingual(ctx_) ? "yes" : "no");

    return true;
}

bool WhisperCppSTT::is_model_loaded() const {
    return model_loaded_;
}

bool WhisperCppSTT::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!model_loaded_ || !ctx_) {
        return true;
    }

    for (auto& [id, state] : streams_) {
        if (state && state->state) {
            whisper_free_state(state->state);
        }
    }
    streams_.clear();

    whisper_free(ctx_);
    ctx_ = nullptr;
    model_loaded_ = false;
    model_path_.clear();

    LOGI("Whisper model unloaded");
    return true;
}

STTModelType WhisperCppSTT::get_model_type() const {
    return STTModelType::WHISPER;
}

STTResult WhisperCppSTT::transcribe(const STTRequest& request) {
    std::lock_guard<std::mutex> lock(mutex_);

    STTResult result;
    result.is_final = true;

    if (!model_loaded_ || !ctx_) {
        LOGE("Model not loaded");
        return result;
    }

    cancel_requested_.store(false);

    std::vector<float> audio = request.audio_samples;
    if (request.sample_rate != WHISPER_SAMPLE_RATE) {
        audio = resample_to_16khz(request.audio_samples, request.sample_rate);
    }

    return transcribe_internal(audio, request.language,
                               request.detect_language || request.language.empty(),
                               request.translate_to_english, request.word_timestamps);
}

STTResult WhisperCppSTT::transcribe_internal(const std::vector<float>& audio,
                                             const std::string& language, bool detect_language,
                                             bool translate, bool word_timestamps) {
    STTResult result;
    result.is_final = true;

    auto start_time = std::chrono::high_resolution_clock::now();

    whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.n_threads = backend_->get_num_threads();
    wparams.print_progress = false;
    wparams.print_realtime = false;
    wparams.print_special = false;
    wparams.print_timestamps = false;

    if (detect_language || language.empty()) {
        wparams.language = nullptr;
        wparams.detect_language = true;
    } else {
        wparams.language = language.c_str();
        wparams.detect_language = false;
    }

    wparams.translate = translate;
    wparams.token_timestamps = word_timestamps;

    wparams.abort_callback = [](void* user_data) -> bool {
        auto* cancel_flag = static_cast<std::atomic<bool>*>(user_data);
        return cancel_flag->load();
    };
    wparams.abort_callback_user_data = &cancel_requested_;

    int ret = whisper_full(ctx_, wparams, audio.data(), static_cast<int>(audio.size()));

    if (ret != 0) {
        LOGE("whisper_full failed with code: %d", ret);
        return result;
    }

    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time);

    const int n_segments = whisper_full_n_segments(ctx_);
    std::string full_text;
    full_text.reserve(n_segments * 64); 

    result.segments.reserve(n_segments);

    if (word_timestamps) {
        result.word_timings.reserve(n_segments * 15);
    }

    for (int i = 0; i < n_segments; ++i) {
        const char* text = whisper_full_get_segment_text(ctx_, i);
        if (text) {
            full_text += text;

            result.segments.emplace_back();
            AudioSegment& segment = result.segments.back();
            segment.text = text;
            segment.start_time_ms = whisper_full_get_segment_t0(ctx_, i) * 10.0;
            segment.end_time_ms = whisper_full_get_segment_t1(ctx_, i) * 10.0;

            float no_speech_prob = whisper_full_get_segment_no_speech_prob(ctx_, i);
            segment.confidence = 1.0f - no_speech_prob;

            if (word_timestamps) {
                const int n_tokens = whisper_full_n_tokens(ctx_, i);
                for (int j = 0; j < n_tokens; ++j) {
                    whisper_token_data token_data = whisper_full_get_token_data(ctx_, i, j);
                    const char* token_text = whisper_full_get_token_text(ctx_, i, j);

                    if (token_text && token_text[0] != '\0' && token_text[0] != '<') {
                        result.word_timings.emplace_back();
                        WordTiming& word = result.word_timings.back();
                        word.word = token_text;
                        word.start_time_ms = token_data.t0 * 10.0;
                        word.end_time_ms = token_data.t1 * 10.0;
                        word.confidence = token_data.p;
                    }
                }
            }
        }
    }

    result.text = full_text;
    result.audio_duration_ms = (audio.size() / static_cast<double>(WHISPER_SAMPLE_RATE)) * 1000.0;
    result.inference_time_ms = static_cast<double>(duration.count());

    int lang_id = whisper_full_lang_id(ctx_);
    if (lang_id >= 0) {
        result.detected_language = whisper_lang_str(lang_id);
    }

    if (!result.segments.empty()) {
        float total_conf = 0.0f;
        for (const auto& seg : result.segments) {
            total_conf += seg.confidence;
        }
        result.confidence = total_conf / static_cast<float>(result.segments.size());
    }

    LOGI("Transcription complete: %d segments, %.0fms inference, lang=%s", n_segments,
         result.inference_time_ms,
         result.detected_language.empty() ? "unknown" : result.detected_language.c_str());

    return result;
}

bool WhisperCppSTT::supports_streaming() const {
    return true;
}

std::string WhisperCppSTT::generate_stream_id() {
    std::stringstream ss;
    ss << "whisper_stream_" << ++stream_counter_;
    return ss.str();
}

std::string WhisperCppSTT::create_stream(const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (!model_loaded_ || !ctx_) {
        LOGE("Cannot create stream: model not loaded");
        return "";
    }

    std::string stream_id = generate_stream_id();

    auto state = std::make_unique<WhisperStreamState>();
    state->state = whisper_init_state(ctx_);

    if (!state->state) {
        LOGE("Failed to create whisper state for stream");
        return "";
    }

    if (config.contains("language")) {
        state->language = config["language"].get<std::string>();
    }

    if (config.contains("sample_rate")) {
        state->sample_rate = config["sample_rate"].get<int>();
    }

    streams_[stream_id] = std::move(state);

    LOGI("Created stream: %s", stream_id.c_str());
    return stream_id;
}

bool WhisperCppSTT::feed_audio(const std::string& stream_id, const std::vector<float>& samples,
                               int sample_rate) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = streams_.find(stream_id);
    if (it == streams_.end()) {
        LOGE("Stream not found: %s", stream_id.c_str());
        return false;
    }

    auto& state = it->second;

    std::vector<float> resampled = samples;
    if (sample_rate != WHISPER_SAMPLE_RATE) {
        resampled = resample_to_16khz(samples, sample_rate);
    }

    state->audio_buffer.insert(state->audio_buffer.end(), resampled.begin(), resampled.end());

    return true;
}

bool WhisperCppSTT::is_stream_ready(const std::string& stream_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = streams_.find(stream_id);
    if (it == streams_.end()) {
        return false;
    }

    const size_t min_samples = WHISPER_SAMPLE_RATE;
    return it->second->audio_buffer.size() >= min_samples || it->second->input_finished;
}

STTResult WhisperCppSTT::decode(const std::string& stream_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    STTResult result;

    auto it = streams_.find(stream_id);
    if (it == streams_.end()) {
        LOGE("Stream not found: %s", stream_id.c_str());
        return result;
    }

    auto& stream_state = it->second;

    if (stream_state->audio_buffer.empty()) {
        result.is_final = stream_state->input_finished;
        return result;
    }

    whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.n_threads = backend_->get_num_threads();
    wparams.single_segment = !stream_state->input_finished;
    wparams.no_context = false;
    wparams.print_progress = false;
    wparams.print_realtime = false;
    wparams.print_timestamps = false;

    if (!stream_state->language.empty()) {
        wparams.language = stream_state->language.c_str();
    }

    int ret = whisper_full_with_state(ctx_, stream_state->state, wparams,
                                      stream_state->audio_buffer.data(),
                                      static_cast<int>(stream_state->audio_buffer.size()));

    if (ret != 0) {
        LOGE("whisper_full_with_state failed: %d", ret);
        return result;
    }

    const int n_segments = whisper_full_n_segments_from_state(stream_state->state);
    std::string full_text;

    for (int i = 0; i < n_segments; ++i) {
        const char* text = whisper_full_get_segment_text_from_state(stream_state->state, i);
        if (text) {
            full_text += text;

            AudioSegment segment;
            segment.text = text;
            segment.start_time_ms =
                whisper_full_get_segment_t0_from_state(stream_state->state, i) * 10.0;
            segment.end_time_ms =
                whisper_full_get_segment_t1_from_state(stream_state->state, i) * 10.0;
            result.segments.push_back(segment);
        }
    }

    result.text = full_text;
    result.is_final = stream_state->input_finished;
    result.audio_duration_ms =
        (stream_state->audio_buffer.size() / static_cast<double>(WHISPER_SAMPLE_RATE)) * 1000.0;

    int lang_id = whisper_full_lang_id_from_state(stream_state->state);
    if (lang_id >= 0) {
        result.detected_language = whisper_lang_str(lang_id);
    }

    stream_state->audio_buffer.clear();

    return result;
}

bool WhisperCppSTT::is_endpoint(const std::string& stream_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = streams_.find(stream_id);
    if (it == streams_.end()) {
        return false;
    }

    return it->second->input_finished;
}

void WhisperCppSTT::input_finished(const std::string& stream_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = streams_.find(stream_id);
    if (it != streams_.end()) {
        it->second->input_finished = true;
        LOGI("Input finished for stream: %s", stream_id.c_str());
    }
}

void WhisperCppSTT::reset_stream(const std::string& stream_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = streams_.find(stream_id);
    if (it != streams_.end()) {
        it->second->audio_buffer.clear();
        it->second->input_finished = false;
        LOGI("Reset stream: %s", stream_id.c_str());
    }
}

void WhisperCppSTT::destroy_stream(const std::string& stream_id) {
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = streams_.find(stream_id);
    if (it != streams_.end()) {
        if (it->second && it->second->state) {
            whisper_free_state(it->second->state);
        }
        streams_.erase(it);
        LOGI("Destroyed stream: %s", stream_id.c_str());
    }
}

void WhisperCppSTT::cancel() {
    cancel_requested_.store(true);
    LOGI("Cancellation requested");
}

std::vector<std::string> WhisperCppSTT::get_supported_languages() const {
    std::vector<std::string> languages;

    const int max_lang = whisper_lang_max_id();
    for (int i = 0; i <= max_lang; ++i) {
        const char* lang = whisper_lang_str(i);
        if (lang) {
            languages.push_back(lang);
        }
    }

    return languages;
}

std::vector<float> WhisperCppSTT::resample_to_16khz(const std::vector<float>& samples,
                                                    int source_rate) {
    if (source_rate == WHISPER_SAMPLE_RATE || samples.empty()) {
        return samples;
    }

    const double step = static_cast<double>(source_rate) / WHISPER_SAMPLE_RATE;
    const size_t output_size = static_cast<size_t>(samples.size() / step);

    std::vector<float> output;
    

    if (source_rate % WHISPER_SAMPLE_RATE == 0) {
    int stride = source_rate / WHISPER_SAMPLE_RATE;
    output.resize(samples.size() / stride);
    for (size_t i = 0; i < output.size(); ++i) {
        output[i] = samples[i * stride];
    }
    return output;
}
        
    output.reserve(output_size);

    const float* __restrict src_ptr = samples.data();
    const size_t src_size = samples.size();

    const size_t safe_output_limit = (output_size > 0) ? output_size - 1 : 0;

    double pos = 0.0;

    for (size_t i = 0; i < safe_output_limit; ++i) {
        size_t idx0 = static_cast<size_t>(pos);
        if (idx0 >= src_size - 1) break;

        double frac = pos - idx0;
        
        float val0 = src_ptr[idx0];
        float val1 = src_ptr[idx0 + 1];

        output.push_back(val0 + static_cast<float>(frac) * (val1 - val0));
        pos += step;
    }

    while (output.size() < output_size) {
        size_t idx0 = static_cast<size_t>(pos);
        if (idx0 >= src_size) idx0 = src_size - 1;

        size_t idx1 = (idx0 + 1 < src_size) ? idx0 + 1 : src_size - 1;

        double frac = pos - static_cast<double>(idx0);
        float val0 = src_ptr[idx0];
        float val1 = src_ptr[idx1];

        output.push_back(val0 + static_cast<float>(frac) * (val1 - val0));
        pos += step;
    }

    LOGI("Resampled audio from %d Hz to %d Hz (%zu -> %zu samples)", source_rate,
         WHISPER_SAMPLE_RATE, samples.size(), output_size);

    return output;
}

}  // namespace runanywhere
