/**
 * ONNX Backend Implementation
 *
 * This file implements the ONNX backend using:
 * - ONNX Runtime for general ML inference
 * - Sherpa-ONNX for speech tasks (STT, TTS, VAD)
 *
 * NPU Acceleration:
 * - iOS/macOS: CoreML → Apple Neural Engine (ANE)
 * - Android Qualcomm: QNN → Hexagon NPU
 * - Android Other: NNAPI → Device NPU
 * - Desktop: CPU with SIMD
 */

#include "onnx_backend.h"

#include <dirent.h>
#include <sys/stat.h>

#include <cstring>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_error.h"

#if defined(__ANDROID__)
#include <android/log.h>
#include <dlfcn.h>
#include <sys/system_properties.h>
#endif

namespace runanywhere {

// =============================================================================
// NPU Provider Selection
// =============================================================================

#if defined(__ANDROID__)
/**
 * Check if device has Qualcomm Snapdragon SoC
 */
static bool is_qualcomm_device() {
    char soc_model[PROP_VALUE_MAX] = {0};
    char hardware[PROP_VALUE_MAX] = {0};
    
    // Check SoC model (e.g., "SM8650" for Snapdragon 8 Gen 3)
    if (__system_property_get("ro.soc.model", soc_model) > 0) {
        if (strstr(soc_model, "SM8") || strstr(soc_model, "SM7") || 
            strstr(soc_model, "SC8") || strstr(soc_model, "QCM") ||
            strstr(soc_model, "SDM")) {
            RAC_LOG_DEBUG("ONNX.NPU", "Detected Qualcomm SoC: %s", soc_model);
            return true;
        }
    }
    
    // Fallback: check hardware property
    if (__system_property_get("ro.hardware", hardware) > 0) {
        if (strstr(hardware, "qcom") || strstr(hardware, "qualcomm")) {
            RAC_LOG_DEBUG("ONNX.NPU", "Detected Qualcomm hardware: %s", hardware);
            return true;
        }
    }
    
    return false;
}

/**
 * Check if QNN libraries are available on device
 */
static bool is_qnn_available() {
    // Try to load QNN HTP library
    void* handle = dlopen("libQnnHtp.so", RTLD_NOW | RTLD_LOCAL);
    if (handle) {
        dlclose(handle);
        RAC_LOG_DEBUG("ONNX.NPU", "QNN HTP library available");
        return true;
    }
    RAC_LOG_DEBUG("ONNX.NPU", "QNN HTP library not available");
    return false;
}
#endif

/**
 * Get optimal execution provider for NPU acceleration
 *
 * Platform mapping:
 * - iOS/macOS: "coreml" → CoreML → Apple Neural Engine (ANE)
 * - Android Qualcomm with QNN: "qnn" → QNN HTP → Hexagon NPU
 * - Android Other: "nnapi" → NNAPI → Device NPU
 * - Desktop: "cpu" → Standard CPU execution with SIMD
 *
 * @param prefer_npu If true, prefer NPU providers; if false, force CPU
 * @return Provider string for Sherpa-ONNX configuration
 */
static const char* get_optimal_provider(bool prefer_npu = true) {
    if (!prefer_npu) {
        RAC_LOG_INFO("ONNX.NPU", "NPU disabled by configuration - using CPU provider");
        return "cpu";
    }

#if defined(__APPLE__)
    // CoreML automatically routes to Apple Neural Engine (ANE) when available
    // ANE is Apple's NPU present in A11+ (iPhone 8+) and M1+ chips
    RAC_LOG_INFO("ONNX.NPU", "============================================");
    RAC_LOG_INFO("ONNX.NPU", "  USING APPLE NPU (Neural Engine / ANE)");
    RAC_LOG_INFO("ONNX.NPU", "  Provider: CoreML");
    RAC_LOG_INFO("ONNX.NPU", "  Hardware: Apple Neural Engine (A11+/M1+)");
    RAC_LOG_INFO("ONNX.NPU", "============================================");
    return "coreml";
    
#elif defined(__ANDROID__)
    // Check for Qualcomm device with QNN support (best NPU performance)
    if (is_qualcomm_device() && is_qnn_available()) {
        RAC_LOG_INFO("ONNX.NPU", "============================================");
        RAC_LOG_INFO("ONNX.NPU", "  USING QUALCOMM QNN (HTP/NPU)");
        RAC_LOG_INFO("ONNX.NPU", "  Provider: QNN");
        RAC_LOG_INFO("ONNX.NPU", "  Hardware: Hexagon Tensor Processor");
        RAC_LOG_INFO("ONNX.NPU", "============================================");
        return "qnn";
    }
    
    // Fallback to NNAPI for other Android devices
    // NNAPI routes to device NPU: Samsung NPU, MediaTek APU, Google Tensor TPU
    RAC_LOG_INFO("ONNX.NPU", "============================================");
    RAC_LOG_INFO("ONNX.NPU", "  USING ANDROID NPU (via NNAPI)");
    RAC_LOG_INFO("ONNX.NPU", "  Provider: NNAPI");
    RAC_LOG_INFO("ONNX.NPU", "  Hardware: Device NPU (Samsung/MediaTek/Google)");
    RAC_LOG_INFO("ONNX.NPU", "============================================");
    return "nnapi";
    
#else
    // Desktop/Server: CPU with SIMD optimizations (AVX2, NEON, etc.)
    RAC_LOG_INFO("ONNX.NPU", "No NPU available on this platform - using CPU provider");
    return "cpu";
#endif
}

/**
 * Detect TTS model type from model directory contents
 */
static TTSModelType detect_tts_model_type(const std::string& model_path) {
    struct stat path_stat;
    
    // Check for Kokoro-specific files
    std::string voices_bin = model_path + "/voices.bin";
    if (stat(voices_bin.c_str(), &path_stat) == 0) {
        RAC_LOG_INFO("ONNX.TTS", "Detected Kokoro model (found voices.bin)");
        return TTSModelType::KOKORO;
    }
    
    // Check for Kitten-specific files
    std::string kitten_marker = model_path + "/kitten.json";
    if (stat(kitten_marker.c_str(), &path_stat) == 0) {
        RAC_LOG_INFO("ONNX.TTS", "Detected Kitten model (found kitten.json)");
        return TTSModelType::KITTEN;
    }
    
    // Check for Matcha-specific files
    std::string acoustic_model = model_path + "/acoustic_model.onnx";
    if (stat(acoustic_model.c_str(), &path_stat) == 0) {
        RAC_LOG_INFO("ONNX.TTS", "Detected Matcha model (found acoustic_model.onnx)");
        return TTSModelType::MATCHA;
    }
    
    // Default to VITS (Piper)
    RAC_LOG_INFO("ONNX.TTS", "Defaulting to VITS/Piper model type");
    return TTSModelType::VITS;
}

// =============================================================================
// ONNXBackendNew Implementation
// =============================================================================

ONNXBackendNew::ONNXBackendNew() {}

ONNXBackendNew::~ONNXBackendNew() {
    cleanup();
}

bool ONNXBackendNew::initialize(const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (initialized_) {
        return true;
    }

    config_ = config;

    if (!initialize_ort()) {
        return false;
    }

    create_capabilities();

    initialized_ = true;
    return true;
}

bool ONNXBackendNew::is_initialized() const {
    return initialized_;
}

void ONNXBackendNew::cleanup() {
    std::lock_guard<std::mutex> lock(mutex_);

    stt_.reset();
    tts_.reset();
    vad_.reset();

    if (ort_env_) {
        ort_api_->ReleaseEnv(ort_env_);
        ort_env_ = nullptr;
    }

    initialized_ = false;
}

DeviceType ONNXBackendNew::get_device_type() const {
#if defined(__APPLE__) || defined(__ANDROID__)
    // On Apple and Android, we use NPU when available
    return DeviceType::NPU;
#else
    return DeviceType::CPU;
#endif
}

size_t ONNXBackendNew::get_memory_usage() const {
    return 0;
}

void ONNXBackendNew::set_telemetry_callback(TelemetryCallback callback) {
    telemetry_.set_callback(callback);
}

bool ONNXBackendNew::initialize_ort() {
    ort_api_ = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    if (!ort_api_) {
        RAC_LOG_ERROR("ONNX", "Failed to get ONNX Runtime API");
        return false;
    }

    OrtStatus* status = ort_api_->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "runanywhere", &ort_env_);
    if (status) {
        RAC_LOG_ERROR("ONNX", "Failed to create ONNX Runtime environment: %s",
                     ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return false;
    }

    return true;
}

void ONNXBackendNew::create_capabilities() {
    stt_ = std::make_unique<ONNXSTT>(this);

#if SHERPA_ONNX_AVAILABLE
    tts_ = std::make_unique<ONNXTTS>(this);
    vad_ = std::make_unique<ONNXVAD>(this);
#endif
}

// =============================================================================
// ONNXSTT Implementation
// =============================================================================

ONNXSTT::ONNXSTT(ONNXBackendNew* backend) : backend_(backend) {}

ONNXSTT::~ONNXSTT() {
    unload_model();
}

bool ONNXSTT::is_ready() const {
#if SHERPA_ONNX_AVAILABLE
    return model_loaded_ && sherpa_recognizer_ != nullptr;
#else
    return model_loaded_;
#endif
}

bool ONNXSTT::load_model(const std::string& model_path, STTModelType model_type,
                         const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
    if (sherpa_recognizer_) {
        SherpaOnnxDestroyOfflineRecognizer(sherpa_recognizer_);
        sherpa_recognizer_ = nullptr;
    }

    model_type_ = model_type;
    model_dir_ = model_path;

    RAC_LOG_INFO("ONNX.STT", "Loading model from: %s", model_path.c_str());

    struct stat path_stat;
    if (stat(model_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.STT", "Model path does not exist: %s", model_path.c_str());
        return false;
    }

    std::string encoder_path;
    std::string decoder_path;
    std::string tokens_path;

    if (S_ISDIR(path_stat.st_mode)) {
        DIR* dir = opendir(model_path.c_str());
        if (!dir) {
            RAC_LOG_ERROR("ONNX.STT", "Cannot open model directory: %s", model_path.c_str());
            return false;
        }

        struct dirent* entry;
        while ((entry = readdir(dir)) != nullptr) {
            std::string filename = entry->d_name;
            std::string full_path = model_path + "/" + filename;

            if (filename.find("encoder") != std::string::npos && filename.size() > 5 &&
                filename.substr(filename.size() - 5) == ".onnx") {
                encoder_path = full_path;
                RAC_LOG_DEBUG("ONNX.STT", "Found encoder: %s", encoder_path.c_str());
            } else if (filename.find("decoder") != std::string::npos && filename.size() > 5 &&
                     filename.substr(filename.size() - 5) == ".onnx") {
                decoder_path = full_path;
                RAC_LOG_DEBUG("ONNX.STT", "Found decoder: %s", decoder_path.c_str());
            } else if (filename == "tokens.txt" || (filename.find("tokens") != std::string::npos &&
                                                  filename.find(".txt") != std::string::npos)) {
                tokens_path = full_path;
                RAC_LOG_DEBUG("ONNX.STT", "Found tokens: %s", tokens_path.c_str());
            }
        }
        closedir(dir);

        if (encoder_path.empty()) {
            std::string test_path = model_path + "/encoder.onnx";
            if (stat(test_path.c_str(), &path_stat) == 0) {
                encoder_path = test_path;
            }
        }
        if (decoder_path.empty()) {
            std::string test_path = model_path + "/decoder.onnx";
            if (stat(test_path.c_str(), &path_stat) == 0) {
                decoder_path = test_path;
            }
        }
        if (tokens_path.empty()) {
            std::string test_path = model_path + "/tokens.txt";
            if (stat(test_path.c_str(), &path_stat) == 0) {
                tokens_path = test_path;
            }
        }
    } else {
        encoder_path = model_path;
        size_t last_slash = model_path.find_last_of('/');
        if (last_slash != std::string::npos) {
            std::string dir = model_path.substr(0, last_slash);
            model_dir_ = dir;
            decoder_path = dir + "/decoder.onnx";
            tokens_path = dir + "/tokens.txt";
        }
    }

    language_ = "en";
    if (config.contains("language")) {
        language_ = config["language"].get<std::string>();
    }

    RAC_LOG_INFO("ONNX.STT", "Encoder: %s", encoder_path.c_str());
    RAC_LOG_INFO("ONNX.STT", "Decoder: %s", decoder_path.c_str());
    RAC_LOG_INFO("ONNX.STT", "Tokens: %s", tokens_path.c_str());
    RAC_LOG_INFO("ONNX.STT", "Language: %s", language_.c_str());

    if (stat(encoder_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.STT", "Encoder file not found: %s", encoder_path.c_str());
        return false;
    }
    if (stat(decoder_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.STT", "Decoder file not found: %s", decoder_path.c_str());
        return false;
    }
    if (stat(tokens_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.STT", "Tokens file not found: %s", tokens_path.c_str());
        return false;
    }

    SherpaOnnxOfflineRecognizerConfig recognizer_config;
    memset(&recognizer_config, 0, sizeof(recognizer_config));

    recognizer_config.feat_config.sample_rate = 16000;
    recognizer_config.feat_config.feature_dim = 80;

    recognizer_config.model_config.transducer.encoder = "";
    recognizer_config.model_config.transducer.decoder = "";
    recognizer_config.model_config.transducer.joiner = "";
    recognizer_config.model_config.paraformer.model = "";
    recognizer_config.model_config.nemo_ctc.model = "";
    recognizer_config.model_config.tdnn.model = "";

    recognizer_config.model_config.whisper.encoder = encoder_path.c_str();
    recognizer_config.model_config.whisper.decoder = decoder_path.c_str();
    recognizer_config.model_config.whisper.language = language_.c_str();
    recognizer_config.model_config.whisper.task = "transcribe";
    recognizer_config.model_config.whisper.tail_paddings = -1;

    recognizer_config.model_config.tokens = tokens_path.c_str();
    recognizer_config.model_config.num_threads = 2;
    recognizer_config.model_config.debug = 1;
    
    // Use NPU provider for STT acceleration
    const char* stt_provider = get_optimal_provider();
    recognizer_config.model_config.provider = stt_provider;
    RAC_LOG_INFO("ONNX.STT", "Using execution provider: %s", stt_provider);
    
    recognizer_config.model_config.model_type = "whisper";

    recognizer_config.model_config.modeling_unit = "cjkchar";
    recognizer_config.model_config.bpe_vocab = "";
    recognizer_config.model_config.telespeech_ctc = "";

    recognizer_config.model_config.sense_voice.model = "";
    recognizer_config.model_config.sense_voice.language = "";

    recognizer_config.model_config.moonshine.preprocessor = "";
    recognizer_config.model_config.moonshine.encoder = "";
    recognizer_config.model_config.moonshine.uncached_decoder = "";
    recognizer_config.model_config.moonshine.cached_decoder = "";

    recognizer_config.model_config.fire_red_asr.encoder = "";
    recognizer_config.model_config.fire_red_asr.decoder = "";

    recognizer_config.model_config.dolphin.model = "";
    recognizer_config.model_config.zipformer_ctc.model = "";

    recognizer_config.model_config.canary.encoder = "";
    recognizer_config.model_config.canary.decoder = "";
    recognizer_config.model_config.canary.src_lang = "";
    recognizer_config.model_config.canary.tgt_lang = "";

    recognizer_config.model_config.wenet_ctc.model = "";
    recognizer_config.model_config.omnilingual.model = "";

    recognizer_config.lm_config.model = "";
    recognizer_config.lm_config.scale = 1.0f;

    recognizer_config.decoding_method = "greedy_search";
    recognizer_config.max_active_paths = 4;
    recognizer_config.hotwords_file = "";
    recognizer_config.hotwords_score = 1.5f;
    recognizer_config.blank_penalty = 0.0f;
    recognizer_config.rule_fsts = "";
    recognizer_config.rule_fars = "";

    recognizer_config.hr.dict_dir = "";
    recognizer_config.hr.lexicon = "";
    recognizer_config.hr.rule_fsts = "";

    RAC_LOG_INFO("ONNX.STT", "Creating SherpaOnnxOfflineRecognizer...");

    sherpa_recognizer_ = SherpaOnnxCreateOfflineRecognizer(&recognizer_config);

    if (!sherpa_recognizer_) {
        RAC_LOG_ERROR("ONNX.STT", "Failed to create SherpaOnnxOfflineRecognizer");
        return false;
    }

    RAC_LOG_INFO("ONNX.STT", "STT model loaded successfully");
    model_loaded_ = true;
    return true;

#else
    RAC_LOG_ERROR("ONNX.STT", "Sherpa-ONNX not available - streaming STT disabled");
    return false;
#endif
}

bool ONNXSTT::is_model_loaded() const {
    return model_loaded_;
}

bool ONNXSTT::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
    for (auto& pair : sherpa_streams_) {
        if (pair.second) {
            SherpaOnnxDestroyOfflineStream(pair.second);
        }
    }
    sherpa_streams_.clear();

    if (sherpa_recognizer_) {
        SherpaOnnxDestroyOfflineRecognizer(sherpa_recognizer_);
        sherpa_recognizer_ = nullptr;
    }
#endif

    model_loaded_ = false;
    return true;
}

STTModelType ONNXSTT::get_model_type() const {
    return model_type_;
}

STTResult ONNXSTT::transcribe(const STTRequest& request) {
    STTResult result;

#if SHERPA_ONNX_AVAILABLE
    if (!sherpa_recognizer_ || !model_loaded_) {
        RAC_LOG_ERROR("ONNX.STT", "STT not ready for transcription");
        result.text = "[Error: STT model not loaded]";
        return result;
    }

    RAC_LOG_INFO("ONNX.STT", "Transcribing %zu samples at %d Hz", request.audio_samples.size(),
                request.sample_rate);

    const SherpaOnnxOfflineStream* stream = SherpaOnnxCreateOfflineStream(sherpa_recognizer_);
    if (!stream) {
        RAC_LOG_ERROR("ONNX.STT", "Failed to create offline stream");
        result.text = "[Error: Failed to create stream]";
        return result;
    }

    SherpaOnnxAcceptWaveformOffline(stream, request.sample_rate, request.audio_samples.data(),
                                    static_cast<int32_t>(request.audio_samples.size()));

    RAC_LOG_DEBUG("ONNX.STT", "Decoding audio...");
    SherpaOnnxDecodeOfflineStream(sherpa_recognizer_, stream);

    const SherpaOnnxOfflineRecognizerResult* recognizer_result =
        SherpaOnnxGetOfflineStreamResult(stream);

    if (recognizer_result && recognizer_result->text) {
        result.text = recognizer_result->text;
        RAC_LOG_INFO("ONNX.STT", "Transcription result: \"%s\"", result.text.c_str());

        if (recognizer_result->lang) {
            result.detected_language = recognizer_result->lang;
        }

        SherpaOnnxDestroyOfflineRecognizerResult(recognizer_result);
    } else {
        result.text = "";
        RAC_LOG_DEBUG("ONNX.STT", "No transcription result (empty audio or silence)");
    }

    SherpaOnnxDestroyOfflineStream(stream);

    return result;

#else
    RAC_LOG_ERROR("ONNX.STT", "Sherpa-ONNX not available");
    result.text = "[Error: Sherpa-ONNX not available]";
    return result;
#endif
}

bool ONNXSTT::supports_streaming() const {
#if SHERPA_ONNX_AVAILABLE
    return false;
#else
    return false;
#endif
}

std::string ONNXSTT::create_stream(const nlohmann::json& config) {
#if SHERPA_ONNX_AVAILABLE
    std::lock_guard<std::mutex> lock(mutex_);

    if (!sherpa_recognizer_) {
        RAC_LOG_ERROR("ONNX.STT", "Cannot create stream: recognizer not initialized");
        return "";
    }

    const SherpaOnnxOfflineStream* stream = SherpaOnnxCreateOfflineStream(sherpa_recognizer_);
    if (!stream) {
        RAC_LOG_ERROR("ONNX.STT", "Failed to create offline stream");
        return "";
    }

    std::string stream_id = "stt_stream_" + std::to_string(++stream_counter_);
    sherpa_streams_[stream_id] = stream;

    RAC_LOG_DEBUG("ONNX.STT", "Created stream: %s", stream_id.c_str());
    return stream_id;
#else
    return "";
#endif
}

bool ONNXSTT::feed_audio(const std::string& stream_id, const std::vector<float>& samples,
                         int sample_rate) {
#if SHERPA_ONNX_AVAILABLE
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = sherpa_streams_.find(stream_id);
    if (it == sherpa_streams_.end() || !it->second) {
        RAC_LOG_ERROR("ONNX.STT", "Stream not found: %s", stream_id.c_str());
        return false;
    }

    SherpaOnnxAcceptWaveformOffline(it->second, sample_rate, samples.data(),
                                    static_cast<int32_t>(samples.size()));

    return true;
#else
    return false;
#endif
}

bool ONNXSTT::is_stream_ready(const std::string& stream_id) {
#if SHERPA_ONNX_AVAILABLE
    std::lock_guard<std::mutex> lock(mutex_);
    auto it = sherpa_streams_.find(stream_id);
    return it != sherpa_streams_.end() && it->second != nullptr;
#else
    return false;
#endif
}

STTResult ONNXSTT::decode(const std::string& stream_id) {
    STTResult result;

#if SHERPA_ONNX_AVAILABLE
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = sherpa_streams_.find(stream_id);
    if (it == sherpa_streams_.end() || !it->second) {
        RAC_LOG_ERROR("ONNX.STT", "Stream not found for decode: %s", stream_id.c_str());
        return result;
    }

    if (!sherpa_recognizer_) {
        RAC_LOG_ERROR("ONNX.STT", "Recognizer not available");
        return result;
    }

    SherpaOnnxDecodeOfflineStream(sherpa_recognizer_, it->second);

    const SherpaOnnxOfflineRecognizerResult* recognizer_result =
        SherpaOnnxGetOfflineStreamResult(it->second);

    if (recognizer_result && recognizer_result->text) {
        result.text = recognizer_result->text;
        RAC_LOG_INFO("ONNX.STT", "Decode result: \"%s\"", result.text.c_str());

        if (recognizer_result->lang) {
            result.detected_language = recognizer_result->lang;
        }

        SherpaOnnxDestroyOfflineRecognizerResult(recognizer_result);
    }
#endif

    return result;
}

bool ONNXSTT::is_endpoint(const std::string& stream_id) {
    return false;
}

void ONNXSTT::input_finished(const std::string& stream_id) {}

void ONNXSTT::reset_stream(const std::string& stream_id) {
#if SHERPA_ONNX_AVAILABLE
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = sherpa_streams_.find(stream_id);
    if (it != sherpa_streams_.end() && it->second) {
        SherpaOnnxDestroyOfflineStream(it->second);

        if (sherpa_recognizer_) {
            it->second = SherpaOnnxCreateOfflineStream(sherpa_recognizer_);
        } else {
            sherpa_streams_.erase(it);
        }
    }
#endif
}

void ONNXSTT::destroy_stream(const std::string& stream_id) {
#if SHERPA_ONNX_AVAILABLE
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = sherpa_streams_.find(stream_id);
    if (it != sherpa_streams_.end()) {
        if (it->second) {
            SherpaOnnxDestroyOfflineStream(it->second);
        }
        sherpa_streams_.erase(it);
        RAC_LOG_DEBUG("ONNX.STT", "Destroyed stream: %s", stream_id.c_str());
    }
#endif
}

void ONNXSTT::cancel() {
    cancel_requested_ = true;
}

std::vector<std::string> ONNXSTT::get_supported_languages() const {
    return {"en", "zh", "de",  "es", "ru", "ko", "fr", "ja", "pt", "tr", "pl", "ca", "nl",
            "ar", "sv", "it",  "id", "hi", "fi", "vi", "he", "uk", "el", "ms", "cs", "ro",
            "da", "hu", "ta",  "no", "th", "ur", "hr", "bg", "lt", "la", "mi", "ml", "cy",
            "sk", "te", "fa",  "lv", "bn", "sr", "az", "sl", "kn", "et", "mk", "br", "eu",
            "is", "hy", "ne",  "mn", "bs", "kk", "sq", "sw", "gl", "mr", "pa", "si", "km",
            "sn", "yo", "so",  "af", "oc", "ka", "be", "tg", "sd", "gu", "am", "yi", "lo",
            "uz", "fo", "ht",  "ps", "tk", "nn", "mt", "sa", "lb", "my", "bo", "tl", "mg",
            "as", "tt", "haw", "ln", "ha", "ba", "jw", "su"};
}

// =============================================================================
// ONNXTTS Implementation
// =============================================================================

ONNXTTS::ONNXTTS(ONNXBackendNew* backend) : backend_(backend) {}

ONNXTTS::~ONNXTTS() {
    try {
        unload_model();
    } catch (...) {}
}

bool ONNXTTS::is_ready() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return model_loaded_ && sherpa_tts_ != nullptr;
}

bool ONNXTTS::load_model(const std::string& model_path, TTSModelType model_type,
                         const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
    if (sherpa_tts_) {
        SherpaOnnxDestroyOfflineTts(sherpa_tts_);
        sherpa_tts_ = nullptr;
    }

    model_type_ = model_type;
    model_dir_ = model_path;

    RAC_LOG_INFO("ONNX.TTS", "Loading model from: %s", model_path.c_str());
    
#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "=== LOAD MODEL START ===");
    __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "model_path: %s", model_path.c_str());
    __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "model_type: %d", static_cast<int>(model_type));
#endif

    std::string model_onnx_path;
    std::string tokens_path;
    std::string data_dir;
    std::string lexicon_path;
    std::string voices_bin;  // For Kokoro - must stay in scope until SherpaOnnxCreateOfflineTts
    std::string dict_dir;    // For Kokoro - must stay in scope until SherpaOnnxCreateOfflineTts

    struct stat path_stat;
    if (stat(model_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Model path does not exist: %s", model_path.c_str());
#ifdef __ANDROID__
        __android_log_print(ANDROID_LOG_ERROR, "ONNX_TTS", "Model path does NOT exist: %s", model_path.c_str());
#endif
        return false;
    }

#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "Model path exists, is_dir=%d", S_ISDIR(path_stat.st_mode));
    
    // List directory contents for debugging
    if (S_ISDIR(path_stat.st_mode)) {
        DIR* debug_dir = opendir(model_path.c_str());
        if (debug_dir) {
            __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "=== Directory contents of %s ===", model_path.c_str());
            struct dirent* debug_entry;
            while ((debug_entry = readdir(debug_dir)) != nullptr) {
                __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "  - %s", debug_entry->d_name);
            }
            closedir(debug_dir);
            __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "=== End directory contents ===");
        }
    }
#endif

    if (S_ISDIR(path_stat.st_mode)) {
        model_onnx_path = model_path + "/model.onnx";
        tokens_path = model_path + "/tokens.txt";
        data_dir = model_path + "/espeak-ng-data";
        lexicon_path = model_path + "/lexicon.txt";

        if (stat(model_onnx_path.c_str(), &path_stat) != 0) {
#ifdef __ANDROID__
            __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "model.onnx not found, scanning for .onnx files...");
#endif
            DIR* dir = opendir(model_path.c_str());
            if (dir) {
                struct dirent* entry;
                while ((entry = readdir(dir)) != nullptr) {
                    std::string filename = entry->d_name;
                    if (filename.size() > 5 && filename.substr(filename.size() - 5) == ".onnx") {
                        model_onnx_path = model_path + "/" + filename;
                        RAC_LOG_DEBUG("ONNX.TTS", "Found model file: %s", model_onnx_path.c_str());
#ifdef __ANDROID__
                        __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "Found ONNX file: %s", filename.c_str());
#endif
                        break;
                    }
                }
                closedir(dir);
            }
        }

        if (stat(data_dir.c_str(), &path_stat) != 0) {
            std::string alt_data_dir = model_path + "/data";
            if (stat(alt_data_dir.c_str(), &path_stat) == 0) {
                data_dir = alt_data_dir;
            }
        }

        if (stat(lexicon_path.c_str(), &path_stat) != 0) {
            std::string alt_lexicon = model_path + "/lexicon";
            if (stat(alt_lexicon.c_str(), &path_stat) == 0) {
                lexicon_path = alt_lexicon;
            }
        }
    } else {
        model_onnx_path = model_path;

        size_t last_slash = model_path.find_last_of('/');
        if (last_slash != std::string::npos) {
            std::string dir = model_path.substr(0, last_slash);
            tokens_path = dir + "/tokens.txt";
            data_dir = dir + "/espeak-ng-data";
            lexicon_path = dir + "/lexicon.txt";
            model_dir_ = dir;
        }
    }

    RAC_LOG_INFO("ONNX.TTS", "Model ONNX: %s", model_onnx_path.c_str());
    RAC_LOG_INFO("ONNX.TTS", "Tokens: %s", tokens_path.c_str());

    if (stat(model_onnx_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Model ONNX file not found: %s", model_onnx_path.c_str());
        char err[256];
        snprintf(err, sizeof(err), "ONNX file missing: %s", model_onnx_path.c_str());
        rac_error_set_details(err);
        return false;
    }

    if (stat(tokens_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Tokens file not found: %s", tokens_path.c_str());
        char err[256];
        snprintf(err, sizeof(err), "tokens.txt missing: %s", tokens_path.c_str());
        rac_error_set_details(err);
        return false;
    }

    // Detect model type from directory contents
    TTSModelType detected_type = detect_tts_model_type(model_path);
    
    // Get optimal provider for NPU acceleration
    const char* provider = get_optimal_provider();
    RAC_LOG_INFO("ONNX.TTS", "Using execution provider: %s", provider);

    SherpaOnnxOfflineTtsConfig tts_config;
    memset(&tts_config, 0, sizeof(tts_config));

    // Configure based on model type
    if (detected_type == TTSModelType::KOKORO) {
        // Kokoro TTS configuration
        RAC_LOG_INFO("ONNX.TTS", "Configuring Kokoro TTS model");
        
        // Set up paths (variables declared at function scope to avoid dangling pointers)
        voices_bin = model_path + "/voices.bin";
        dict_dir = model_path + "/dict";
        
        // CRITICAL: Kokoro requires voices.bin
        if (stat(voices_bin.c_str(), &path_stat) != 0) {
            RAC_LOG_ERROR("ONNX.TTS", "Kokoro voices.bin not found: %s", voices_bin.c_str());
            char err[256];
            snprintf(err, sizeof(err), "voices.bin missing: %s", voices_bin.c_str());
            rac_error_set_details(err);
            return false;
        }
        RAC_LOG_INFO("ONNX.TTS", "Kokoro voices.bin found: %ld bytes", (long)path_stat.st_size);
        
        // Check for language-specific lexicon
        std::string lexicon_us = model_path + "/lexicon-us-en.txt";
        if (stat(lexicon_us.c_str(), &path_stat) == 0) {
            lexicon_path = lexicon_us;
        }
        
        RAC_LOG_INFO("ONNX.TTS", "Kokoro config: model=%s, voices=%s, tokens=%s", 
            model_onnx_path.c_str(), voices_bin.c_str(), tokens_path.c_str());
        
        tts_config.model.kokoro.model = model_onnx_path.c_str();
        tts_config.model.kokoro.voices = voices_bin.c_str();
        tts_config.model.kokoro.tokens = tokens_path.c_str();
        
        if (stat(lexicon_path.c_str(), &path_stat) == 0) {
            tts_config.model.kokoro.lexicon = lexicon_path.c_str();
            RAC_LOG_DEBUG("ONNX.TTS", "Using Kokoro lexicon: %s", lexicon_path.c_str());
        }
        
        if (stat(data_dir.c_str(), &path_stat) == 0 && S_ISDIR(path_stat.st_mode)) {
            tts_config.model.kokoro.data_dir = data_dir.c_str();
            RAC_LOG_DEBUG("ONNX.TTS", "Using Kokoro data_dir: %s", data_dir.c_str());
        }
        
        // Check for dict directory
        if (stat(dict_dir.c_str(), &path_stat) == 0 && S_ISDIR(path_stat.st_mode)) {
            tts_config.model.kokoro.dict_dir = dict_dir.c_str();
            RAC_LOG_DEBUG("ONNX.TTS", "Using Kokoro dict_dir: %s", dict_dir.c_str());
        }
        
        tts_config.model.kokoro.length_scale = 1.0f;
        tts_config.model.kokoro.lang = "en-us";
        
    } else {
        // VITS/Piper TTS configuration (default)
        RAC_LOG_INFO("ONNX.TTS", "Configuring VITS/Piper TTS model");
        
        tts_config.model.vits.model = model_onnx_path.c_str();
        tts_config.model.vits.tokens = tokens_path.c_str();

        if (stat(lexicon_path.c_str(), &path_stat) == 0 && S_ISREG(path_stat.st_mode)) {
            tts_config.model.vits.lexicon = lexicon_path.c_str();
            RAC_LOG_DEBUG("ONNX.TTS", "Using lexicon file: %s", lexicon_path.c_str());
        }

        if (stat(data_dir.c_str(), &path_stat) == 0 && S_ISDIR(path_stat.st_mode)) {
            tts_config.model.vits.data_dir = data_dir.c_str();
            RAC_LOG_DEBUG("ONNX.TTS", "Using espeak-ng data dir: %s", data_dir.c_str());
        }

        tts_config.model.vits.noise_scale = 0.667f;
        tts_config.model.vits.noise_scale_w = 0.8f;
        tts_config.model.vits.length_scale = 1.0f;
    }

    // Common settings - use NPU provider
    tts_config.model.provider = provider;
    tts_config.model.num_threads = 2;
    tts_config.model.debug = 1;

    RAC_LOG_INFO("ONNX.TTS", "Creating SherpaOnnxOfflineTts with %s provider...", provider);

#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "=== Creating SherpaOnnxOfflineTts ===");
    __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "provider: %s", provider);
    __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "detected_type: %d (VITS=0, PIPER=1, KOKORO=2)", static_cast<int>(detected_type));
    if (detected_type == TTSModelType::KOKORO) {
        __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "kokoro.model: %s", tts_config.model.kokoro.model ? tts_config.model.kokoro.model : "(null)");
        __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "kokoro.voices: %s", tts_config.model.kokoro.voices ? tts_config.model.kokoro.voices : "(null)");
        __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "kokoro.tokens: %s", tts_config.model.kokoro.tokens ? tts_config.model.kokoro.tokens : "(null)");
        __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "kokoro.data_dir: %s", tts_config.model.kokoro.data_dir ? tts_config.model.kokoro.data_dir : "(null)");
        __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "kokoro.dict_dir: %s", tts_config.model.kokoro.dict_dir ? tts_config.model.kokoro.dict_dir : "(null)");
        __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "kokoro.lexicon: %s", tts_config.model.kokoro.lexicon ? tts_config.model.kokoro.lexicon : "(null)");
    } else {
        __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "vits.model: %s", tts_config.model.vits.model ? tts_config.model.vits.model : "(null)");
        __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "vits.tokens: %s", tts_config.model.vits.tokens ? tts_config.model.vits.tokens : "(null)");
    }
#endif

    const SherpaOnnxOfflineTts* new_tts = nullptr;
    try {
        new_tts = SherpaOnnxCreateOfflineTts(&tts_config);
    } catch (const std::exception& e) {
        RAC_LOG_ERROR("ONNX.TTS", "Exception during TTS creation: %s", e.what());
        
        // Fallback to CPU if NPU fails
        if (strcmp(provider, "cpu") != 0) {
            RAC_LOG_INFO("ONNX.TTS", "NPU failed, falling back to CPU provider");
            tts_config.model.provider = "cpu";
            try {
                new_tts = SherpaOnnxCreateOfflineTts(&tts_config);
            } catch (...) {
                RAC_LOG_ERROR("ONNX.TTS", "CPU fallback also failed");
                return false;
            }
        } else {
            return false;
        }
    } catch (...) {
        RAC_LOG_ERROR("ONNX.TTS", "Unknown exception during TTS creation");
        return false;
    }

    if (!new_tts) {
#ifdef __ANDROID__
        __android_log_print(ANDROID_LOG_ERROR, "ONNX_TTS", "SherpaOnnxCreateOfflineTts returned NULL!");
#endif
        // Fallback to CPU if NPU provider returned null
        if (strcmp(provider, "cpu") != 0) {
            RAC_LOG_INFO("ONNX.TTS", "============================================");
            RAC_LOG_INFO("ONNX.TTS", "  NPU FAILED - FALLING BACK TO CPU");
            RAC_LOG_INFO("ONNX.TTS", "============================================");
#ifdef __ANDROID__
            __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "Trying CPU fallback...");
#endif
            tts_config.model.provider = "cpu";
            new_tts = SherpaOnnxCreateOfflineTts(&tts_config);
        }
        
        if (!new_tts) {
            RAC_LOG_ERROR("ONNX.TTS", "Failed to create SherpaOnnxOfflineTts");
#ifdef __ANDROID__
            __android_log_print(ANDROID_LOG_ERROR, "ONNX_TTS", "FINAL FAILURE: Could not create TTS even with CPU");
#endif
            // List directory to help debug
            std::string file_list = "";
            DIR* dir = opendir(model_path.c_str());
            if (dir) {
                struct dirent* entry;
                int count = 0;
                while ((entry = readdir(dir)) != nullptr && count < 10) {
                    if (entry->d_name[0] != '.') {
                        file_list += std::string(entry->d_name) + ",";
                        count++;
                    }
                }
                closedir(dir);
            }
            
            // Set detailed error for debugging
            char err[1024];
            snprintf(err, sizeof(err), 
                "SherpaOnnx NULL|type=%s|prov=%s|files=[%s]|model=%s|tokens=%s|voices=%s",
                detected_type == TTSModelType::KOKORO ? "KOKORO" : "PIPER",
                tts_config.model.provider ? tts_config.model.provider : "null",
                file_list.c_str(),
                model_onnx_path.c_str(),
                tokens_path.c_str(),
                voices_bin.empty() ? "N/A" : voices_bin.c_str());
            rac_error_set_details(err);
            return false;
        }
    }
    
#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_INFO, "ONNX_TTS", "SUCCESS: SherpaOnnxOfflineTts created!");
#endif

    sherpa_tts_ = new_tts;

    sample_rate_ = SherpaOnnxOfflineTtsSampleRate(sherpa_tts_);
    int num_speakers = SherpaOnnxOfflineTtsNumSpeakers(sherpa_tts_);

    // Log success with NPU status
    const char* npu_status = (strcmp(tts_config.model.provider, "cpu") != 0) ? "NPU" : "CPU";
    RAC_LOG_INFO("ONNX.TTS", "============================================");
    RAC_LOG_INFO("ONNX.TTS", "  TTS MODEL LOADED WITH %s ACCELERATION", npu_status);
    RAC_LOG_INFO("ONNX.TTS", "  Model Type: %s", detected_type == TTSModelType::KOKORO ? "Kokoro" : "VITS/Piper");
    RAC_LOG_INFO("ONNX.TTS", "  Provider: %s", tts_config.model.provider);
    RAC_LOG_INFO("ONNX.TTS", "  Sample Rate: %d Hz", sample_rate_);
    RAC_LOG_INFO("ONNX.TTS", "  Speakers: %d", num_speakers);
    RAC_LOG_INFO("ONNX.TTS", "============================================");

    // Register voices
    voices_.clear();
    
    if (detected_type == TTSModelType::KOKORO && num_speakers > 20) {
        // Kokoro v1.0+ has 53 speakers with specific names
        const char* kokoro_voices[] = {
            "af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica",
            "af_kore", "af_nicole", "af_nova", "af_river", "af_sarah", "af_sky",
            "am_adam", "am_echo", "am_eric", "am_fenrir", "am_liam",
            "am_michael", "am_onyx", "am_puck", "am_santa",
            "bf_alice", "bf_emma", "bf_isabella", "bf_lily",
            "bm_daniel", "bm_fable", "bm_george", "bm_lewis"
        };
        int num_kokoro_voices = sizeof(kokoro_voices) / sizeof(kokoro_voices[0]);
        
        for (int i = 0; i < std::min(num_speakers, num_kokoro_voices); ++i) {
            VoiceInfo voice;
            voice.id = kokoro_voices[i];
            voice.name = kokoro_voices[i];
            voice.language = (kokoro_voices[i][0] == 'a') ? "en-US" : "en-GB";
            voices_.push_back(voice);
        }
        RAC_LOG_INFO("ONNX.TTS", "Registered %d Kokoro voices", (int)voices_.size());
    } else {
        // Generic voice registration
        for (int i = 0; i < num_speakers; ++i) {
            VoiceInfo voice;
            voice.id = std::to_string(i);
            voice.name = "Speaker " + std::to_string(i);
            voice.language = "en";
            voices_.push_back(voice);
        }
    }

    model_loaded_ = true;
    return true;

#else
    RAC_LOG_ERROR("ONNX.TTS", "Sherpa-ONNX not available - TTS disabled");
    return false;
#endif
}

bool ONNXTTS::is_model_loaded() const {
    return model_loaded_;
}

bool ONNXTTS::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
    model_loaded_ = false;

    if (active_synthesis_count_ > 0) {
        RAC_LOG_WARNING("ONNX.TTS",
                       "Unloading model while %d synthesis operation(s) may be in progress",
                       active_synthesis_count_.load());
    }

    voices_.clear();

    if (sherpa_tts_) {
        SherpaOnnxDestroyOfflineTts(sherpa_tts_);
        sherpa_tts_ = nullptr;
    }
#else
    model_loaded_ = false;
    voices_.clear();
#endif

    return true;
}

TTSModelType ONNXTTS::get_model_type() const {
    return model_type_;
}

TTSResult ONNXTTS::synthesize(const TTSRequest& request) {
    TTSResult result;

#if SHERPA_ONNX_AVAILABLE
    struct SynthesisGuard {
        std::atomic<int>& count_;
        SynthesisGuard(std::atomic<int>& count) : count_(count) { count_++; }
        ~SynthesisGuard() { count_--; }
    };
    SynthesisGuard guard(active_synthesis_count_);

    const SherpaOnnxOfflineTts* tts_ptr = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);

        if (!sherpa_tts_ || !model_loaded_) {
            RAC_LOG_ERROR("ONNX.TTS", "TTS not ready for synthesis");
            return result;
        }

        tts_ptr = sherpa_tts_;
    }

    RAC_LOG_INFO("ONNX.TTS", "Synthesizing: \"%s...\"", request.text.substr(0, 50).c_str());

    int speaker_id = 0;
    if (!request.voice_id.empty()) {
        try {
            speaker_id = std::stoi(request.voice_id);
        } catch (...) {}
    }

    float speed = request.speed_rate > 0 ? request.speed_rate : 1.0f;

    RAC_LOG_DEBUG("ONNX.TTS", "Speaker ID: %d, Speed: %.2f", speaker_id, speed);

    const SherpaOnnxGeneratedAudio* audio =
        SherpaOnnxOfflineTtsGenerate(tts_ptr, request.text.c_str(), speaker_id, speed);

    if (!audio || audio->n <= 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Failed to generate audio");
        return result;
    }

    RAC_LOG_INFO("ONNX.TTS", "Generated %d samples at %d Hz", audio->n, audio->sample_rate);

    result.audio_samples.assign(audio->samples, audio->samples + audio->n);
    result.sample_rate = audio->sample_rate;
    result.duration_ms =
        (static_cast<double>(audio->n) / static_cast<double>(audio->sample_rate)) * 1000.0;

    SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);

    RAC_LOG_INFO("ONNX.TTS", "Synthesis complete. Duration: %.2fs", (result.duration_ms / 1000.0));

#else
    RAC_LOG_ERROR("ONNX.TTS", "Sherpa-ONNX not available");
#endif

    return result;
}

bool ONNXTTS::supports_streaming() const {
    return false;
}

void ONNXTTS::cancel() {
    cancel_requested_ = true;
}

std::vector<VoiceInfo> ONNXTTS::get_voices() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return voices_;
}

std::string ONNXTTS::get_default_voice(const std::string& language) const {
    return "0";
}

// =============================================================================
// ONNXVAD Implementation
// =============================================================================

ONNXVAD::ONNXVAD(ONNXBackendNew* backend) : backend_(backend) {}

ONNXVAD::~ONNXVAD() {
    unload_model();
}

bool ONNXVAD::is_ready() const {
    return model_loaded_;
}

bool ONNXVAD::load_model(const std::string& model_path, VADModelType model_type,
                         const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);
    model_loaded_ = true;
    return true;
}

bool ONNXVAD::is_model_loaded() const {
    return model_loaded_;
}

bool ONNXVAD::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);
    model_loaded_ = false;
    return true;
}

bool ONNXVAD::configure_vad(const VADConfig& config) {
    config_ = config;
    return true;
}

VADResult ONNXVAD::process(const std::vector<float>& audio_samples, int sample_rate) {
    VADResult result;
    return result;
}

std::vector<SpeechSegment> ONNXVAD::detect_segments(const std::vector<float>& audio_samples,
                                                    int sample_rate) {
    return {};
}

std::string ONNXVAD::create_stream(const VADConfig& config) {
    return "";
}

VADResult ONNXVAD::feed_audio(const std::string& stream_id, const std::vector<float>& samples,
                              int sample_rate) {
    return {};
}

void ONNXVAD::destroy_stream(const std::string& stream_id) {}

void ONNXVAD::reset() {}

VADConfig ONNXVAD::get_vad_config() const {
    return config_;
}

}  // namespace runanywhere
