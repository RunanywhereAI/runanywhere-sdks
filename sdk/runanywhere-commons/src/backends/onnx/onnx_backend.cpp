/**
 * ONNX Backend Implementation
 *
 * This file implements the ONNX backend using:
 * - ONNX Runtime for general ML inference
 * - Sherpa-ONNX for speech tasks (STT, TTS, VAD)
 *
 * ⚠️  SHERPA-ONNX VERSION DEPENDENCY:
 * The SherpaOnnx*Config structs used here MUST match the prebuilt
 * libsherpa-onnx-c-api.so exactly (same version of c-api.h).
 * A mismatch causes SIGSEGV due to ABI/struct layout differences.
 * See VERSIONS file for the current SHERPA_ONNX_VERSION_ANDROID.
 */

#include "onnx_backend.h"

#include <dirent.h>
#include <sys/stat.h>

#include <cctype>
#include <cstdio>
#include <cstring>

#include "rac/core/rac_logger.h"

#if SHERPA_ONNX_AVAILABLE
extern "C" {
    int espeak_Initialize(int output, int buflength, const char *path, int options);
    int espeak_SetVoiceByName(const char *name);
}
#define ESPEAK_AUDIO_OUTPUT_SYNCHRONOUS 0x0003
#endif

namespace runanywhere {

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
    return DeviceType::CPU;
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

    // Scan the model directory for files
    std::string encoder_path;
    std::string decoder_path;
    std::string tokens_path;
    std::string nemo_ctc_model_path;  // Single-file CTC model (model.int8.onnx or model.onnx)

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
            } else if ((filename == "model.int8.onnx" || filename == "model.onnx") &&
                       encoder_path.empty()) {
                // Single-file model (NeMo CTC, etc.) - prefer int8 if both exist
                if (filename == "model.int8.onnx" || nemo_ctc_model_path.empty()) {
                    nemo_ctc_model_path = full_path;
                    RAC_LOG_DEBUG("ONNX.STT", "Found single-file model: %s", nemo_ctc_model_path.c_str());
                }
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

    // Auto-detect model type if not explicitly set:
    // If we found a single-file model (model.int8.onnx / model.onnx) but no encoder/decoder,
    // this is a NeMo CTC model. Also detect from path keywords.
    if (model_type_ != STTModelType::NEMO_CTC) {
        bool has_encoder_decoder = !encoder_path.empty() && !decoder_path.empty();
        bool has_single_model = !nemo_ctc_model_path.empty();
        bool path_suggests_nemo = (model_path.find("nemo") != std::string::npos ||
                                   model_path.find("parakeet") != std::string::npos ||
                                   model_path.find("ctc") != std::string::npos);

        if ((!has_encoder_decoder && has_single_model) || path_suggests_nemo) {
            model_type_ = STTModelType::NEMO_CTC;
            RAC_LOG_INFO("ONNX.STT", "Auto-detected NeMo CTC model type");
        }
    }

    // Branch based on model type
    bool is_nemo_ctc = (model_type_ == STTModelType::NEMO_CTC);

    if (is_nemo_ctc) {
        // NeMo CTC: single model file + tokens
        if (nemo_ctc_model_path.empty()) {
            RAC_LOG_ERROR("ONNX.STT", "NeMo CTC model file not found (model.int8.onnx or model.onnx) in: %s",
                          model_path.c_str());
            return false;
        }
        RAC_LOG_INFO("ONNX.STT", "NeMo CTC model: %s", nemo_ctc_model_path.c_str());
        RAC_LOG_INFO("ONNX.STT", "Tokens: %s", tokens_path.c_str());
    } else {
        // Whisper: encoder + decoder
        RAC_LOG_INFO("ONNX.STT", "Encoder: %s", encoder_path.c_str());
        RAC_LOG_INFO("ONNX.STT", "Decoder: %s", decoder_path.c_str());
        RAC_LOG_INFO("ONNX.STT", "Tokens: %s", tokens_path.c_str());
    }
    RAC_LOG_INFO("ONNX.STT", "Language: %s", language_.c_str());

    // Validate required files
    if (!is_nemo_ctc) {
        if (stat(encoder_path.c_str(), &path_stat) != 0) {
            RAC_LOG_ERROR("ONNX.STT", "Encoder file not found: %s", encoder_path.c_str());
            return false;
        }
        if (stat(decoder_path.c_str(), &path_stat) != 0) {
            RAC_LOG_ERROR("ONNX.STT", "Decoder file not found: %s", decoder_path.c_str());
            return false;
        }
    }
    if (stat(tokens_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.STT", "Tokens file not found: %s", tokens_path.c_str());
        return false;
    }

    // Keep path strings in members so config pointers stay valid for recognizer lifetime
    encoder_path_ = encoder_path;
    decoder_path_ = decoder_path;
    tokens_path_ = tokens_path;
    nemo_ctc_model_path_ = nemo_ctc_model_path;

    // Initialize all config fields explicitly to avoid any uninitialized pointer issues.
    // The struct layout MUST match the prebuilt libsherpa-onnx-c-api.so version (v1.12.20).
    SherpaOnnxOfflineRecognizerConfig recognizer_config;
    memset(&recognizer_config, 0, sizeof(recognizer_config));

    recognizer_config.feat_config.sample_rate = 16000;
    recognizer_config.feat_config.feature_dim = 80;

    // Zero out all model slots
    recognizer_config.model_config.transducer.encoder = "";
    recognizer_config.model_config.transducer.decoder = "";
    recognizer_config.model_config.transducer.joiner = "";
    recognizer_config.model_config.paraformer.model = "";
    recognizer_config.model_config.nemo_ctc.model = "";
    recognizer_config.model_config.tdnn.model = "";
    recognizer_config.model_config.whisper.encoder = "";
    recognizer_config.model_config.whisper.decoder = "";
    recognizer_config.model_config.whisper.language = "";
    recognizer_config.model_config.whisper.task = "";
    recognizer_config.model_config.whisper.tail_paddings = -1;

    if (is_nemo_ctc) {
        // Configure for NeMo CTC (Parakeet, etc.)
        recognizer_config.model_config.nemo_ctc.model = nemo_ctc_model_path_.c_str();
        recognizer_config.model_config.model_type = "nemo_ctc";

        RAC_LOG_INFO("ONNX.STT", "Configuring NeMo CTC recognizer");
    } else {
        // Configure for Whisper (encoder-decoder)
        recognizer_config.model_config.whisper.encoder = encoder_path_.c_str();
        recognizer_config.model_config.whisper.decoder = decoder_path_.c_str();
        recognizer_config.model_config.whisper.language = language_.c_str();
        recognizer_config.model_config.whisper.task = "transcribe";
        recognizer_config.model_config.model_type = "whisper";
    }

    recognizer_config.model_config.tokens = tokens_path_.c_str();
    recognizer_config.model_config.num_threads = 2;
    recognizer_config.model_config.debug = 1;
    recognizer_config.model_config.provider = "cpu";

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

    // NOTE: Do NOT set medasr or funasr_nano here - they don't exist in
    // Sherpa-ONNX v1.12.20 (the prebuilt .so version). Setting them would shift
    // the struct layout and cause SherpaOnnxCreateOfflineRecognizer to crash.

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

    RAC_LOG_INFO("ONNX.STT", "Creating SherpaOnnxOfflineRecognizer (%s)...",
                 is_nemo_ctc ? "NeMo CTC" : "Whisper");

    sherpa_recognizer_ = SherpaOnnxCreateOfflineRecognizer(&recognizer_config);

    if (!sherpa_recognizer_) {
        RAC_LOG_ERROR("ONNX.STT", "Failed to create SherpaOnnxOfflineRecognizer");
        return false;
    }

    RAC_LOG_INFO("ONNX.STT", "STT model loaded successfully (%s)",
                 is_nemo_ctc ? "NeMo CTC" : "Whisper");
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

/**
 * Ensures espeak-ng voice files from lang/ subdirectories are also
 * accessible directly under voices/ so that espeak_SetVoiceByName()
 * can find them via the fast direct-file-lookup path.
 *
 * espeak's LoadVoice("en-us", 1) tries voices/en-us then lang/en-us
 * but NOT lang/gmw/en-US (the actual location in Piper archives).
 * The fallback (espeak_ListVoices -> directory scan) should handle
 * this but fails at runtime on iOS. This function creates copies
 * of lang voice files directly in voices/ to bypass the issue.
 */
static void ensure_espeak_voice_files(const std::string& espeak_data_dir) {
    std::string lang_dir = espeak_data_dir + "/lang";
    std::string voices_dir = espeak_data_dir + "/voices";

    RAC_LOG_INFO("ONNX.TTS", "[ensure_voices] lang_dir=%s, voices_dir=%s", lang_dir.c_str(), voices_dir.c_str());

    struct stat st;
    if (stat(lang_dir.c_str(), &st) != 0 || !S_ISDIR(st.st_mode)) {
        RAC_LOG_ERROR("ONNX.TTS", "[ensure_voices] lang/ directory NOT FOUND or not a dir: %s (errno=%d)", lang_dir.c_str(), errno);
        return;
    }

    if (stat(voices_dir.c_str(), &st) != 0) {
        int mk = mkdir(voices_dir.c_str(), 0755);
        RAC_LOG_INFO("ONNX.TTS", "[ensure_voices] Created voices/ dir: result=%d errno=%d", mk, errno);
    } else {
        RAC_LOG_INFO("ONNX.TTS", "[ensure_voices] voices/ dir already exists");
    }

    DIR* lang_root = opendir(lang_dir.c_str());
    if (!lang_root) {
        RAC_LOG_ERROR("ONNX.TTS", "[ensure_voices] Failed to open lang/ dir (errno=%d)", errno);
        return;
    }

    int copied = 0;
    int skipped = 0;
    int errors = 0;
    struct dirent* family_entry;
    while ((family_entry = readdir(lang_root)) != nullptr) {
        if (family_entry->d_name[0] == '.') continue;

        std::string family_path = lang_dir + "/" + family_entry->d_name;
        if (stat(family_path.c_str(), &st) != 0) continue;

        if (S_ISREG(st.st_mode)) {
            std::string basename = family_entry->d_name;
            std::string lowercase_name;
            for (char c : basename) lowercase_name += (char)tolower((unsigned char)c);

            std::string dest = voices_dir + "/" + lowercase_name;
            if (stat(dest.c_str(), &st) == 0) { skipped++; continue; }

            FILE* src_f = fopen(family_path.c_str(), "rb");
            FILE* dst_f = fopen(dest.c_str(), "wb");
            if (src_f && dst_f) {
                char buf[4096];
                size_t n;
                while ((n = fread(buf, 1, sizeof(buf), src_f)) > 0) {
                    fwrite(buf, 1, n, dst_f);
                }
                copied++;
                RAC_LOG_DEBUG("ONNX.TTS", "[ensure_voices] Copied: %s -> %s", family_path.c_str(), dest.c_str());
            } else {
                errors++;
                RAC_LOG_ERROR("ONNX.TTS", "[ensure_voices] FAILED to copy %s -> %s (src=%p dst=%p errno=%d)",
                    family_path.c_str(), dest.c_str(), (void*)src_f, (void*)dst_f, errno);
            }
            if (src_f) fclose(src_f);
            if (dst_f) fclose(dst_f);
            continue;
        }

        if (!S_ISDIR(st.st_mode)) continue;

        RAC_LOG_DEBUG("ONNX.TTS", "[ensure_voices] Scanning family dir: %s", family_entry->d_name);
        DIR* family_dir = opendir(family_path.c_str());
        if (!family_dir) continue;

        struct dirent* voice_entry;
        while ((voice_entry = readdir(family_dir)) != nullptr) {
            if (voice_entry->d_name[0] == '.') continue;

            std::string voice_path = family_path + "/" + voice_entry->d_name;
            if (stat(voice_path.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) continue;

            std::string basename = voice_entry->d_name;
            std::string lowercase_name;
            for (char c : basename) lowercase_name += (char)tolower((unsigned char)c);

            std::string dest = voices_dir + "/" + lowercase_name;
            if (stat(dest.c_str(), &st) == 0) { skipped++; continue; }

            FILE* src_f = fopen(voice_path.c_str(), "rb");
            FILE* dst_f = fopen(dest.c_str(), "wb");
            if (src_f && dst_f) {
                char buf[4096];
                size_t n;
                while ((n = fread(buf, 1, sizeof(buf), src_f)) > 0) {
                    fwrite(buf, 1, n, dst_f);
                }
                copied++;
                RAC_LOG_INFO("ONNX.TTS", "[ensure_voices] Copied: %s -> voices/%s", voice_entry->d_name, lowercase_name.c_str());
            } else {
                errors++;
                RAC_LOG_ERROR("ONNX.TTS", "[ensure_voices] FAILED: %s -> voices/%s (src=%p dst=%p errno=%d)",
                    voice_entry->d_name, lowercase_name.c_str(), (void*)src_f, (void*)dst_f, errno);
            }
            if (src_f) fclose(src_f);
            if (dst_f) fclose(dst_f);
        }
        closedir(family_dir);
    }
    closedir(lang_root);

    RAC_LOG_INFO("ONNX.TTS", "[ensure_voices] Done: copied=%d skipped=%d errors=%d", copied, skipped, errors);

    // Dump voices/ directory contents for verification
    DIR* vdir = opendir(voices_dir.c_str());
    if (vdir) {
        RAC_LOG_INFO("ONNX.TTS", "[ensure_voices] === voices/ directory contents ===");
        struct dirent* ve;
        int count = 0;
        while ((ve = readdir(vdir)) != nullptr) {
            if (ve->d_name[0] == '.') continue;
            std::string vpath = voices_dir + "/" + ve->d_name;
            struct stat vs;
            stat(vpath.c_str(), &vs);
            RAC_LOG_INFO("ONNX.TTS", "[ensure_voices]   [%s] %s (%lld bytes)",
                S_ISDIR(vs.st_mode) ? "DIR" : "FILE", ve->d_name, (long long)vs.st_size);
            count++;
        }
        closedir(vdir);
        RAC_LOG_INFO("ONNX.TTS", "[ensure_voices] === Total: %d entries ===", count);
    }
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

    RAC_LOG_INFO("ONNX.TTS", "[BUILD_V5] Loading model from: %s", model_path.c_str());

    std::string model_onnx_path;
    std::string tokens_path;
    std::string lexicon_path;
    // sherpa-onnx data_dir: the espeak-ng-data directory path itself.
    // espeak's check_data_path tries path+"/espeak-ng-data" first, then path itself.
    // Passing the espeak-ng-data dir directly works via the fallback branch.
    std::string espeak_data_dir;

    struct stat path_stat;
    if (stat(model_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Model path does not exist: %s", model_path.c_str());
        return false;
    }

    // Diagnostic: list top-level directory contents
    if (S_ISDIR(path_stat.st_mode)) {
        DIR* diag_dir = opendir(model_path.c_str());
        if (diag_dir) {
            RAC_LOG_INFO("ONNX.TTS", "=== Model directory contents: %s ===", model_path.c_str());
            struct dirent* diag_entry;
            while ((diag_entry = readdir(diag_dir)) != nullptr) {
                if (diag_entry->d_name[0] == '.') continue;
                RAC_LOG_INFO("ONNX.TTS", "  [%s] %s",
                    diag_entry->d_type == DT_DIR ? "DIR" : "FILE",
                    diag_entry->d_name);
            }
            closedir(diag_dir);
            RAC_LOG_INFO("ONNX.TTS", "=== End directory listing ===");
        }
    }

    if (S_ISDIR(path_stat.st_mode)) {
        model_onnx_path = model_path + "/model.onnx";
        tokens_path = model_path + "/tokens.txt";
        lexicon_path = model_path + "/lexicon.txt";

        if (stat(model_onnx_path.c_str(), &path_stat) != 0) {
            DIR* dir = opendir(model_path.c_str());
            if (dir) {
                struct dirent* entry;
                while ((entry = readdir(dir)) != nullptr) {
                    std::string filename = entry->d_name;
                    if (filename.size() > 5 && filename.substr(filename.size() - 5) == ".onnx") {
                        model_onnx_path = model_path + "/" + filename;
                        RAC_LOG_DEBUG("ONNX.TTS", "Found model file: %s", model_onnx_path.c_str());
                        break;
                    }
                }
                closedir(dir);
            }
        }

        // Look for espeak-ng-data directory
        std::string candidate = model_path + "/espeak-ng-data";
        if (stat(candidate.c_str(), &path_stat) == 0 && S_ISDIR(path_stat.st_mode)) {
            espeak_data_dir = candidate;
        } else {
            candidate = model_path + "/data/espeak-ng-data";
            if (stat(candidate.c_str(), &path_stat) == 0 && S_ISDIR(path_stat.st_mode)) {
                espeak_data_dir = candidate;
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
            lexicon_path = dir + "/lexicon.txt";
            model_dir_ = dir;

            std::string candidate = dir + "/espeak-ng-data";
            if (stat(candidate.c_str(), &path_stat) == 0 && S_ISDIR(path_stat.st_mode)) {
                espeak_data_dir = candidate;
            }
        }
    }

    RAC_LOG_INFO("ONNX.TTS", "Model ONNX: %s", model_onnx_path.c_str());
    RAC_LOG_INFO("ONNX.TTS", "Tokens: %s", tokens_path.c_str());
    RAC_LOG_INFO("ONNX.TTS", "espeak_data_dir: %s", espeak_data_dir.c_str());

    if (stat(model_onnx_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Model ONNX file not found: %s", model_onnx_path.c_str());
        return false;
    }

    if (stat(tokens_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Tokens file not found: %s", tokens_path.c_str());
        return false;
    }

    if (!espeak_data_dir.empty()) {
        // Verify key files exist
        std::string lang_gmw_dir = espeak_data_dir + "/lang/gmw";
        std::string en_us_voice = lang_gmw_dir + "/en-US";
        RAC_LOG_INFO("ONNX.TTS", "Checking lang/gmw/en-US: %s",
            stat(en_us_voice.c_str(), &path_stat) == 0 ? "EXISTS" : "MISSING");

        // Ensure voice files are accessible directly from voices/
        ensure_espeak_voice_files(espeak_data_dir);

        // Verify voices/en-us now exists
        std::string voices_en_us = espeak_data_dir + "/voices/en-us";
        RAC_LOG_INFO("ONNX.TTS", "voices/en-us after ensure: %s",
            stat(voices_en_us.c_str(), &path_stat) == 0 ? "EXISTS" : "MISSING");
    }

    SherpaOnnxOfflineTtsConfig tts_config;
    memset(&tts_config, 0, sizeof(tts_config));

    tts_config.model.vits.model = model_onnx_path.c_str();
    tts_config.model.vits.tokens = tokens_path.c_str();

    if (stat(lexicon_path.c_str(), &path_stat) == 0 && S_ISREG(path_stat.st_mode)) {
        tts_config.model.vits.lexicon = lexicon_path.c_str();
        RAC_LOG_DEBUG("ONNX.TTS", "Using lexicon file: %s", lexicon_path.c_str());
    }

    espeak_data_dir_ = espeak_data_dir;
    if (!espeak_data_dir.empty()) {
        tts_config.model.vits.data_dir = espeak_data_dir_.c_str();
        RAC_LOG_INFO("ONNX.TTS", "Using espeak data_dir: %s", espeak_data_dir_.c_str());
    } else {
        RAC_LOG_WARNING("ONNX.TTS", "espeak-ng-data NOT FOUND in model dir — Piper TTS will fail");
    }

    tts_config.model.vits.noise_scale = 0.667f;
    tts_config.model.vits.noise_scale_w = 0.8f;
    tts_config.model.vits.length_scale = 1.0f;

    tts_config.model.provider = "cpu";
    tts_config.model.num_threads = 2;
    tts_config.model.debug = 1;

    RAC_LOG_INFO("ONNX.TTS", "Creating SherpaOnnxOfflineTts (VITS/Piper)...");

    const SherpaOnnxOfflineTts* new_tts = nullptr;
    try {
        new_tts = SherpaOnnxCreateOfflineTts(&tts_config);
    } catch (const std::exception& e) {
        RAC_LOG_ERROR("ONNX.TTS", "Exception during TTS creation: %s", e.what());
        return false;
    } catch (...) {
        RAC_LOG_ERROR("ONNX.TTS", "Unknown exception during TTS creation");
        return false;
    }

    if (!new_tts) {
        RAC_LOG_ERROR("ONNX.TTS", "Failed to create SherpaOnnxOfflineTts");
        return false;
    }

    sherpa_tts_ = new_tts;

    // Force espeak-ng to use THIS model's data_dir.
    // Sherpa-ONNX uses std::once_flag for espeak_Initialize, so only the first
    // model loaded gets its data_dir registered. Re-calling espeak_Initialize
    // directly resets the internal path_home to the current model's directory.
    if (!espeak_data_dir_.empty()) {
        int reinit = espeak_Initialize(ESPEAK_AUDIO_OUTPUT_SYNCHRONOUS, 0, espeak_data_dir_.c_str(), 0);
        RAC_LOG_INFO("ONNX.TTS", "espeak_Initialize override: result=%d (expected 22050), data_dir=%s",
            reinit, espeak_data_dir_.c_str());

        if (reinit == 22050) {
            int voice_test = espeak_SetVoiceByName("en-us");
            RAC_LOG_INFO("ONNX.TTS", "espeak_SetVoiceByName('en-us') test: result=%d (0=success)", voice_test);
            int voice_test_gb = espeak_SetVoiceByName("en-gb");
            RAC_LOG_INFO("ONNX.TTS", "espeak_SetVoiceByName('en-gb') test: result=%d (0=success)", voice_test_gb);
        } else {
            RAC_LOG_ERROR("ONNX.TTS", "espeak_Initialize override FAILED with code %d", reinit);
        }
    }

    sample_rate_ = SherpaOnnxOfflineTtsSampleRate(sherpa_tts_);
    int num_speakers = SherpaOnnxOfflineTtsNumSpeakers(sherpa_tts_);

    RAC_LOG_INFO("ONNX.TTS", "TTS model loaded successfully");
    RAC_LOG_INFO("ONNX.TTS", "Sample rate: %d, speakers: %d", sample_rate_, num_speakers);

    voices_.clear();
    for (int i = 0; i < num_speakers; ++i) {
        VoiceInfo voice;
        voice.id = std::to_string(i);
        voice.name = "Speaker " + std::to_string(i);
        voice.language = "en";
        voice.sample_rate = sample_rate_;
        voices_.push_back(voice);
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

    const SherpaOnnxGeneratedAudio* audio = nullptr;
    try {
        audio = SherpaOnnxOfflineTtsGenerate(tts_ptr, request.text.c_str(), speaker_id, speed);
    } catch (const std::exception& e) {
        RAC_LOG_ERROR("ONNX.TTS", "Exception during TTS synthesis: %s", e.what());
        RAC_LOG_ERROR("ONNX.TTS", "Model dir: %s, espeak data was: %s",
                     model_dir_.c_str(),
                     espeak_data_dir_.empty() ? "<EMPTY/NOT SET>" : espeak_data_dir_.c_str());
        return result;
    } catch (...) {
        RAC_LOG_ERROR("ONNX.TTS", "Unknown exception during TTS synthesis");
        return result;
    }

    if (!audio || audio->n <= 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Synthesis returned null/empty audio. Model dir: %s, espeak data: %s",
                     model_dir_.c_str(),
                     espeak_data_dir_.empty() ? "<EMPTY/NOT SET>" : espeak_data_dir_.c_str());
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
// ONNXVAD Implementation - Silero VAD via Sherpa-ONNX
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

#if SHERPA_ONNX_AVAILABLE
    // Destroy previous instance if any
    if (sherpa_vad_) {
        SherpaOnnxDestroyVoiceActivityDetector(sherpa_vad_);
        sherpa_vad_ = nullptr;
    }

    model_path_ = model_path;

    SherpaOnnxVadModelConfig vad_config;
    memset(&vad_config, 0, sizeof(vad_config));

    vad_config.silero_vad.model = model_path_.c_str();
    vad_config.silero_vad.threshold = 0.5f;
    vad_config.silero_vad.min_silence_duration = 0.5f;
    vad_config.silero_vad.min_speech_duration = 0.25f;
    vad_config.silero_vad.max_speech_duration = 15.0f;
    vad_config.silero_vad.window_size = 512;
    vad_config.sample_rate = 16000;
    vad_config.num_threads = 1;
    vad_config.debug = 0;
    vad_config.provider = "cpu";

    // Override threshold from config JSON if provided
    if (config.contains("energy_threshold")) {
        vad_config.silero_vad.threshold = config["energy_threshold"].get<float>();
    }

    sherpa_vad_ = SherpaOnnxCreateVoiceActivityDetector(&vad_config, 30.0f);
    if (!sherpa_vad_) {
        RAC_LOG_ERROR("ONNX.VAD", "Failed to create Silero VAD detector from: %s", model_path.c_str());
        return false;
    }

    RAC_LOG_INFO("ONNX.VAD", "Silero VAD loaded: %s (threshold=%.2f)", model_path.c_str(),
                 vad_config.silero_vad.threshold);
    model_loaded_ = true;
    return true;
#else
    model_loaded_ = true;
    return true;
#endif
}

bool ONNXVAD::is_model_loaded() const {
    return model_loaded_;
}

bool ONNXVAD::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
    if (sherpa_vad_) {
        SherpaOnnxDestroyVoiceActivityDetector(sherpa_vad_);
        sherpa_vad_ = nullptr;
    }
#endif

    pending_samples_.clear();
    model_loaded_ = false;
    return true;
}

bool ONNXVAD::configure_vad(const VADConfig& config) {
    config_ = config;
    return true;
}

VADResult ONNXVAD::process(const std::vector<float>& audio_samples, int sample_rate) {
    VADResult result;

#if SHERPA_ONNX_AVAILABLE
    if (!sherpa_vad_ || audio_samples.empty()) {
        return result;
    }

    const int32_t window_size = 512;  // Silero native window size

    // Append incoming audio to the pending buffer.
    // Audio capture may deliver chunks smaller than window_size (e.g. 256 samples),
    // but Silero VAD requires exactly 512 samples per call.
    pending_samples_.insert(pending_samples_.end(), audio_samples.begin(), audio_samples.end());

    // Feed complete window_size chunks to Silero VAD
    while (pending_samples_.size() >= static_cast<size_t>(window_size)) {
        SherpaOnnxVoiceActivityDetectorAcceptWaveform(
            sherpa_vad_, pending_samples_.data(), window_size);
        pending_samples_.erase(pending_samples_.begin(), pending_samples_.begin() + window_size);
    }

    // Check if speech is currently detected in the latest frame
    result.is_speech = SherpaOnnxVoiceActivityDetectorDetected(sherpa_vad_) != 0;
    result.probability = result.is_speech ? 1.0f : 0.0f;

    // Drain any completed speech segments (keeps internal queue from growing)
    while (SherpaOnnxVoiceActivityDetectorEmpty(sherpa_vad_) == 0) {
        const SherpaOnnxSpeechSegment* seg = SherpaOnnxVoiceActivityDetectorFront(sherpa_vad_);
        if (seg) {
            SherpaOnnxDestroySpeechSegment(seg);
        }
        SherpaOnnxVoiceActivityDetectorPop(sherpa_vad_);
    }
#endif

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

void ONNXVAD::reset() {
#if SHERPA_ONNX_AVAILABLE
    if (sherpa_vad_) {
        SherpaOnnxVoiceActivityDetectorReset(sherpa_vad_);
    }
#endif
    pending_samples_.clear();
}

VADConfig ONNXVAD::get_vad_config() const {
    return config_;
}

}  // namespace runanywhere
