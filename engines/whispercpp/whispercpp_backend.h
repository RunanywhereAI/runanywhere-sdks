#ifndef RUNANYWHERE_WHISPERCPP_BACKEND_H
#define RUNANYWHERE_WHISPERCPP_BACKEND_H

/**
 * WhisperCPP Backend - Speech-to-Text via whisper.cpp
 *
 * This backend uses whisper.cpp for on-device speech recognition with GGML
 * Whisper models. Internal C++ implementation wrapped by RAC API
 * (rac_stt_whispercpp.cpp).
 */

#include <whisper.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

// DeviceType + STT request/result types are shared across engines — see
// engines/common/. Defining them here used to fight sherpa_backend.h's
// definitions in any TU that pulled in both (ODR landmine).
#include "common/rac_engine_device_type.h"
#include "common/rac_engine_stt_types.h"

namespace runanywhere {

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================

class WhisperCppSTT;

// =============================================================================
// WHISPERCPP BACKEND
// =============================================================================

class WhisperCppBackend {
   public:
    WhisperCppBackend();
    ~WhisperCppBackend();

    bool initialize(const nlohmann::json& config = {});
    bool is_initialized() const;
    void cleanup();

    DeviceType get_device_type() const;
    size_t get_memory_usage() const;

    int get_num_threads() const { return num_threads_; }
    bool is_gpu_enabled() const { return use_gpu_; }

    WhisperCppSTT* get_stt() { return stt_.get(); }

   private:
    void create_stt();

    bool initialized_ = false;
    nlohmann::json config_;
    int num_threads_ = 0;
    bool use_gpu_ = true;
    std::unique_ptr<WhisperCppSTT> stt_;
    mutable std::mutex mutex_;
};

// =============================================================================
// STT IMPLEMENTATION
// =============================================================================

class WhisperCppSTT {
   public:
    explicit WhisperCppSTT(WhisperCppBackend* backend);
    ~WhisperCppSTT();

    bool is_ready() const;
    bool load_model(const std::string& model_path, STTModelType model_type = STTModelType::WHISPER,
                    const nlohmann::json& config = {});
    bool is_model_loaded() const;
    bool unload_model();
    STTModelType get_model_type() const;

    STTResult transcribe(const STTRequest& request);

    void cancel();
    std::vector<std::string> get_supported_languages() const;

   private:
    STTResult transcribe_internal(const std::vector<float>& audio, const std::string& language,
                                  bool detect_language, bool translate, bool word_timestamps);
    std::vector<float> resample_to_16khz(const std::vector<float>& samples, int source_rate);

    WhisperCppBackend* backend_;
    whisper_context* ctx_ = nullptr;

    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};

    std::string model_path_;
    nlohmann::json model_config_;

    mutable std::mutex mutex_;
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_WHISPERCPP_BACKEND_H
