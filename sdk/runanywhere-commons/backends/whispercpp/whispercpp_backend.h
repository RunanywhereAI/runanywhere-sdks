#ifndef RUNANYWHERE_WHISPERCPP_BACKEND_H
#define RUNANYWHERE_WHISPERCPP_BACKEND_H

/**
 * WhisperCPP Backend - Speech-to-Text via whisper.cpp
 *
 * This backend uses whisper.cpp for on-device speech recognition with GGML Whisper models.
 *
 * Supported Capabilities:
 * - STT: Batch transcription and streaming via whisper.cpp
 *   - Language detection (98 languages)
 *   - Translation to English
 *   - Word-level timestamps
 */

#include <whisper.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "capabilities/backend.h"
#include "capabilities/stt.h"
#include "capabilities/types.h"

namespace runanywhere {

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================

class WhisperCppSTT;

// =============================================================================
// WHISPERCPP BACKEND
// =============================================================================

class WhisperCppBackend : public Backend {
   public:
    WhisperCppBackend();
    ~WhisperCppBackend() override;

    // Backend interface
    BackendInfo get_info() const override;
    bool initialize(const nlohmann::json& config = {}) override;
    bool is_initialized() const override;
    void cleanup() override;

    ra_device_type get_device_type() const override;
    size_t get_memory_usage() const override;

    // Get number of threads to use
    int get_num_threads() const { return num_threads_; }

    // Check if GPU is enabled
    bool is_gpu_enabled() const { return use_gpu_; }

   private:
    void create_capabilities();

    bool initialized_ = false;
    nlohmann::json config_;
    int num_threads_ = 0;
    bool use_gpu_ = true;
    mutable std::mutex mutex_;
};

// =============================================================================
// STREAMING STATE
// =============================================================================

struct WhisperStreamState {
    whisper_state* state = nullptr;
    std::vector<float> audio_buffer;
    std::string language;
    bool input_finished = false;
    int sample_rate = 16000;  // WHISPER_SAMPLE_RATE
};

// =============================================================================
// STT CAPABILITY (WHISPER)
// =============================================================================

class WhisperCppSTT : public ISTT {
   public:
    explicit WhisperCppSTT(WhisperCppBackend* backend);
    ~WhisperCppSTT() override;

    // ICapability
    bool is_ready() const override;

    // ISTT interface - Model management
    bool load_model(const std::string& model_path, STTModelType model_type = STTModelType::WHISPER,
                    const nlohmann::json& config = {}) override;
    bool is_model_loaded() const override;
    bool unload_model() override;
    STTModelType get_model_type() const override;

    // Batch transcription
    STTResult transcribe(const STTRequest& request) override;

    // Streaming support
    bool supports_streaming() const override;
    std::string create_stream(const nlohmann::json& config = {}) override;
    bool feed_audio(const std::string& stream_id, const std::vector<float>& samples,
                    int sample_rate) override;
    bool is_stream_ready(const std::string& stream_id) override;
    STTResult decode(const std::string& stream_id) override;
    bool is_endpoint(const std::string& stream_id) override;
    void input_finished(const std::string& stream_id) override;
    void reset_stream(const std::string& stream_id) override;
    void destroy_stream(const std::string& stream_id) override;

    // Control
    void cancel() override;
    std::vector<std::string> get_supported_languages() const override;

   private:
    // Internal transcription
    STTResult transcribe_internal(const std::vector<float>& audio, const std::string& language,
                                  bool detect_language, bool translate, bool word_timestamps);

    // Audio resampling (simple linear interpolation)
    std::vector<float> resample_to_16khz(const std::vector<float>& samples, int source_rate);

    // Generate unique stream ID
    std::string generate_stream_id();

    WhisperCppBackend* backend_;
    whisper_context* ctx_ = nullptr;

    bool model_loaded_ = false;
    std::atomic<bool> cancel_requested_{false};

    std::string model_path_;
    nlohmann::json model_config_;

    // Streaming state management
    std::unordered_map<std::string, std::unique_ptr<WhisperStreamState>> streams_;
    int stream_counter_ = 0;

    mutable std::mutex mutex_;
};

// =============================================================================
// BACKEND FACTORY & REGISTRATION
// =============================================================================

// Export macro for shared library builds (needed for Android)
#if defined(_WIN32)
#define RA_WHISPERCPP_EXPORT __declspec(dllexport)
#elif defined(__GNUC__) || defined(__clang__)
#define RA_WHISPERCPP_EXPORT __attribute__((visibility("default")))
#else
#define RA_WHISPERCPP_EXPORT
#endif

/**
 * Creates a new WhisperCPP backend instance.
 *
 * This factory function is called by the bridge to create backend instances.
 * The registration is done by the bridge itself to avoid singleton issues
 * across shared libraries.
 */
RA_WHISPERCPP_EXPORT std::unique_ptr<Backend> create_whispercpp_backend();

/**
 * Explicitly registers the WhisperCPP backend with the BackendRegistry.
 *
 * NOTE: For shared library builds (Android), prefer calling create_whispercpp_backend()
 * from the bridge and letting the bridge register it. This function calls
 * BackendRegistry::instance() which may create a separate singleton in each .so.
 *
 * For static library builds (iOS), this function works correctly.
 */
RA_WHISPERCPP_EXPORT void register_whispercpp_backend();

}  // namespace runanywhere

#endif  // RUNANYWHERE_WHISPERCPP_BACKEND_H
