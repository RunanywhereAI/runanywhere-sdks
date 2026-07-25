#ifndef RUNANYWHERE_SHERPA_BACKEND_H
#define RUNANYWHERE_SHERPA_BACKEND_H

/**
 * Sherpa-ONNX Backend - Internal implementation for STT, TTS, VAD
 *
 * This backend uses Sherpa-ONNX for speech-specific tasks (STT, TTS, VAD).
 * Internal C++ implementation wrapped by the Sherpa RAC API.
 */

#include <atomic>
#include <cstdlib>
#include <cstring>
#include <list>
#include <memory>
#include <mutex>
#include <nlohmann/json.hpp>
#include <string>
#include <unordered_map>
#include <vector>

#include "common/rac_engine_device_type.h"
#include "common/rac_engine_stt_types.h"

// Sherpa-ONNX C API for TTS/STT
#if SHERPA_ONNX_AVAILABLE
#include <sherpa-onnx/c-api/c-api.h>
#endif

namespace rac::backends::sherpa {

// =============================================================================
// SHARED HELPERS
// =============================================================================

/**
 * Build a minimal JSON array of string codes. Returns a malloc'd NUL-terminated
 * buffer; caller must free() it. We skip escaping because language codes are
 * ASCII alphabet / digits / hyphen.
 */
inline char* build_json_string_array(const std::vector<std::string>& items) {
    std::string json;
    json.reserve(items.size() * 8 + 2);
    json.push_back('[');
    for (size_t i = 0; i < items.size(); ++i) {
        if (i > 0)
            json.push_back(',');
        json.push_back('"');
        json.append(items[i]);
        json.push_back('"');
    }
    json.push_back(']');
    return strdup(json.c_str());
}

}  // namespace rac::backends::sherpa

namespace runanywhere {

// =============================================================================
// INTERNAL TYPES
// =============================================================================

// DeviceType is shared across engines — see
// engines/common/rac_engine_device_type.h

struct DeviceInfo {
    DeviceType device_type = DeviceType::CPU;
    std::string device_name;
    std::string platform;
    size_t available_memory = 0;
    int cpu_cores = 0;
};

// STT types (STTModelType, AudioSegment, STTRequest, STTResult) are shared
// across engines — see engines/common/rac_engine_stt_types.h.

// Structured outcome of a SherpaSTT::transcribe() call. Sherpa-local (NOT part
// of the shared STTResult): it lets the RAC C-ABI layer (rac_stt_sherpa.cpp)
// switch on a concrete failure cause instead of string-parsing "[Error: ...]"
// sentinels out of result.text. Each enumerator maps 1:1 to a former sentinel
// string; on any non-Ok status the result text is left empty.
enum class SherpaSttStatus {
    Ok,                     // transcription succeeded (text may still be empty for silence)
    ModelNotLoaded,         // recognizer missing / model_loaded_ false
    LanguageNotSupported,   // per-call language rejected (non-Whisper) or rebuild for it failed
    RecognizerBuildFailed,  // could not (re)build any recognizer; model now unloaded
    StreamCreationFailed,   // SherpaOnnxCreateOfflineStream returned null
    BackendUnavailable,     // built without SHERPA_ONNX_AVAILABLE
};

enum class SherpaRecognizerMode {
    Offline,
    OnlineTransducer,
};

struct SherpaStreamUpdate {
    std::string text;
    bool is_final = false;
};

// =============================================================================
// TTS TYPES
// =============================================================================

enum class TTSModelType { PIPER, COQUI, BARK, ESPEAK, CUSTOM };

struct VoiceInfo {
    std::string id;
    std::string name;
    std::string language;
    std::string gender;
    std::string description;
    int sample_rate = 22050;
};

struct TTSRequest {
    std::string text;
    std::string voice_id;
    std::string language;
    float speed_rate = 1.0f;
    int sample_rate = 22050;
};

struct TTSResult {
    std::vector<float> audio_samples;
    int sample_rate = 22050;
    int channels = 1;
    double duration_ms = 0.0;
    double inference_time_ms = 0.0;
};

// =============================================================================
// VAD TYPES
// =============================================================================

enum class VADModelType { SILERO, WEBRTC, SHERPA, CUSTOM };

struct SpeechSegment {
    double start_time_ms = 0.0;
    double end_time_ms = 0.0;
    float confidence = 0.0f;
    bool is_speech = true;
};

struct VADConfig {
    float threshold = 0.5f;
    int min_speech_duration_ms = 250;
    int min_silence_duration_ms = 100;
    int padding_ms = 30;
    int window_size_ms = 32;
    int sample_rate = 16000;
};

struct VADResult {
    bool is_speech = false;
    float probability = 0.0f;
    double timestamp_ms = 0.0;
    std::vector<SpeechSegment> segments;
};

// =============================================================================
// FORWARD DECLARATIONS
// =============================================================================

class SherpaSTT;
class SherpaTTS;
class SherpaVAD;

// =============================================================================
// SHERPA BACKEND
// =============================================================================

class SherpaBackend {
   public:
    SherpaBackend();
    ~SherpaBackend();

    bool initialize(const nlohmann::json& config = {});
    bool is_initialized() const;
    void cleanup();

    DeviceType get_device_type() const;
    size_t get_memory_usage() const;

    const DeviceInfo& get_device_info() const { return device_info_; }

    // Get capability implementations
    SherpaSTT* get_stt() { return stt_.get(); }
    SherpaTTS* get_tts() { return tts_.get(); }
    SherpaVAD* get_vad() { return vad_.get(); }

   private:
    void create_capabilities();

    std::atomic<bool> initialized_{false};
    nlohmann::json config_;
    DeviceInfo device_info_;

    std::unique_ptr<SherpaSTT> stt_;
    std::unique_ptr<SherpaTTS> tts_;
    std::unique_ptr<SherpaVAD> vad_;

    mutable std::mutex mutex_;
};

// =============================================================================
// STT IMPLEMENTATION
// =============================================================================

class SherpaSTT {
   public:
    explicit SherpaSTT(SherpaBackend* backend);
    ~SherpaSTT();

    bool is_ready() const;
    bool load_model(const std::string& model_path, STTModelType model_type = STTModelType::WHISPER,
                    const nlohmann::json& config = {});
    bool is_model_loaded() const;
    bool unload_model();
    STTModelType get_model_type() const;

    // Transcribe one audio buffer. When `out_status` is non-null it receives the
    // structured outcome (SherpaSttStatus) so callers can branch on the failure
    // cause without parsing result.text. On any non-Ok status result.text is
    // empty. The default nullptr keeps existing call sites source-compatible.
    STTResult transcribe(const STTRequest& request, SherpaSttStatus* out_status = nullptr);
    bool supports_streaming() const;
    bool supports_persistent_streaming() const;

    std::string create_stream(const nlohmann::json& config = {});
    bool feed_audio(const std::string& stream_id, const std::vector<float>& samples,
                    int sample_rate);
    bool feed_audio_and_decode(const std::string& stream_id, const std::vector<float>& samples,
                               std::vector<SherpaStreamUpdate>* updates);
    bool is_stream_ready(const std::string& stream_id);
    STTResult decode(const std::string& stream_id);
    bool is_endpoint(const std::string& stream_id);
    void input_finished(const std::string& stream_id);
    void reset_stream(const std::string& stream_id);
    void destroy_stream(const std::string& stream_id);

    std::vector<std::string> get_supported_languages() const;

   private:
    // Builds the offline recognizer using cached model paths and the current
    // `language_`. Mutex MUST be held by the caller. Returns true on success.
    // Existing recognizer (if any) is destroyed first. Used by load_model() to
    // do the initial build and by transcribe() to honor per-call language /
    // detect-language requests on recognizers that expose language config.
    bool build_offline_recognizer_locked();

    // Builds a stateful Sherpa online transducer recognizer. Used only after
    // structure-first ONNX inspection identifies streaming encoder cache
    // inputs; offline encoder/decoder/joiner bundles never enter this path.
    bool build_online_recognizer_locked();

    // Cap on the LRU cache of per-language recognizers.
    // Each entry holds a fully constructed SherpaOnnxOfflineRecognizer whose
    // ONNX-runtime session is the heavy part of init, so we keep this small to
    // bound resident model memory. With Whisper-small at ~hundreds of MB per
    // recognizer, 3 entries is the practical ceiling for mobile/web.
    static constexpr size_t kRecognizerCacheCap = 3;

    SherpaBackend* backend_;
#if SHERPA_ONNX_AVAILABLE
    struct StreamState {
        const SherpaOnnxOfflineStream* offline = nullptr;
        const SherpaOnnxOnlineStream* online = nullptr;
        int sample_rate = 16000;
        std::string language;
        std::string last_text;
    };

    const SherpaOnnxOfflineRecognizer* sherpa_recognizer_ = nullptr;
    const SherpaOnnxOnlineRecognizer* sherpa_online_recognizer_ = nullptr;
    std::unordered_map<std::string, StreamState> sherpa_streams_;
    // LRU cache of recognizers keyed by language (empty string == auto-detect
    // for Whisper; Canary requires an explicit supported language).
    // Populated lazily on first transcribe() per language, hit on subsequent
    // calls so alternating-language workloads don't pay the multi-second
    // SherpaOnnxCreateOfflineRecognizer cost every utterance.
    // recognizer_lru_ front = most-recently-used. Both structures are guarded
    // by mutex_.
    std::unordered_map<std::string, const SherpaOnnxOfflineRecognizer*> recognizer_cache_;
    std::list<std::string> recognizer_lru_;
#else
    void* sherpa_recognizer_ = nullptr;
#endif
    STTModelType model_type_ = STTModelType::WHISPER;
    SherpaRecognizerMode recognizer_mode_ = SherpaRecognizerMode::Offline;
    bool uses_language_prompt_ = false;
    std::atomic<bool> model_loaded_{false};
    int stream_counter_ = 0;
    std::string model_dir_;
    std::string language_;
    // Kept alive so config string pointers remain valid for recognizer lifetime
    std::string encoder_path_;
    std::string decoder_path_;
    std::string joiner_path_;
    std::string tokens_path_;
    std::string nemo_ctc_model_path_;
    mutable std::mutex mutex_;
};

// =============================================================================
// TTS IMPLEMENTATION
// =============================================================================

class SherpaTTS {
   public:
    explicit SherpaTTS(SherpaBackend* backend);
    ~SherpaTTS();

    bool is_ready() const;
    bool load_model(const std::string& model_path, TTSModelType model_type = TTSModelType::PIPER,
                    const nlohmann::json& config = {});
    bool is_model_loaded() const;
    bool unload_model();
    TTSModelType get_model_type() const;

    TTSResult synthesize(const TTSRequest& request);
    bool supports_streaming() const;

    void cancel();
    std::vector<VoiceInfo> get_voices() const;

   private:
    SherpaBackend* backend_;
#if SHERPA_ONNX_AVAILABLE
    const SherpaOnnxOfflineTts* sherpa_tts_ = nullptr;
#else
    void* sherpa_tts_ = nullptr;
#endif
    TTSModelType model_type_ = TTSModelType::PIPER;
    std::atomic<bool> model_loaded_{false};
    std::atomic<bool> cancel_requested_{false};
    // Cancel epoch counter incremented every time cancel()
    // is observed. synthesize() snapshots this at entry (before clearing
    // cancel_requested_) and re-reads it post-generate to honor cancels that
    // raced into the lock between two synthesize() calls. Without this, a
    // stop issued between the post-result drop of call #1 and call #2's lock
    // acquisition (where cancel_requested_ is reset) was silently lost.
    std::atomic<uint64_t> cancel_epoch_{0};
    std::atomic<int> active_synthesis_count_{0};
    std::vector<VoiceInfo> voices_;
    std::string model_dir_;
    std::string espeak_data_dir_;
    // Synthesis language carried by the TTS load config (config["language"],
    // default "en"). Sherpa-ONNX's offline-TTS C-API exposes no per-speaker
    // language, so this engine-configured value is what get_voices() reports for
    // every speaker instead of a hardcoded literal (mirrors SherpaSTT::language_).
    std::string language_ = "en";
    int sample_rate_ = 22050;
    mutable std::mutex mutex_;
};

// =============================================================================
// VAD IMPLEMENTATION
// =============================================================================

class SherpaVAD {
   public:
    explicit SherpaVAD(SherpaBackend* backend);
    ~SherpaVAD();

    bool is_ready() const;
    // Returns true iff the most recent process() call observed speech in the
    // latest Silero window. Distinct from is_ready(), which only reports model
    // load status. Lifecycle/state APIs (VADServiceState.is_speech_active) and
    // the rac_vad_sherpa_is_speech_active vtable slot route through here so
    // consumers see actual frame state, not stale readiness.
    bool is_speech_active() const;
    bool load_model(const std::string& model_path, VADModelType model_type = VADModelType::SILERO,
                    const nlohmann::json& config = {});
    bool is_model_loaded() const;
    bool unload_model();

    bool configure_vad(const VADConfig& config);
    VADResult process(const std::vector<float>& audio_samples, int sample_rate);

    void reset();
    VADConfig get_vad_config() const;

   private:
#if SHERPA_ONNX_AVAILABLE
    // Translate the current `config_` snapshot (plus `model_path_`) into the
    // Sherpa-ONNX SilerVAD model config. Used by both `load_model()` (after
    // `config_` is populated from JSON) and `configure_vad()` (rebuild path) so
    // that every VADConfig field — threshold, min_silence_duration_ms,
    // min_speech_duration_ms, window_size_ms, sample_rate — actually reaches the
    // detector instead of getting silently dropped.
    // Caller MUST hold mutex_.
    void fill_sherpa_vad_config_locked(SherpaOnnxVadModelConfig& out) const;
#endif

    SherpaBackend* backend_;
#if SHERPA_ONNX_AVAILABLE
    const SherpaOnnxVoiceActivityDetector* sherpa_vad_ = nullptr;
#else
    void* sherpa_vad_ = nullptr;
#endif
    std::string model_path_;
    VADConfig config_;
    std::atomic<bool> model_loaded_{false};
    // Latest detected speech state, refreshed by process() and cleared by
    // reset()/unload_model()/configure_vad(rebuild). Guarded by mutex_.
    bool last_is_speech_ = false;
    mutable std::mutex mutex_;

    // Internal buffer to accumulate audio until we have a full Silero window (512
    // samples). Audio capture may deliver chunks smaller than the required window
    // size.
    std::vector<float> pending_samples_;
};

}  // namespace runanywhere

#endif  // RUNANYWHERE_SHERPA_BACKEND_H
