/**
 * ONNX Backend Implementation
 *
 * This file implements the ONNX backend using:
 * - ONNX Runtime for general ML inference
 * - Sherpa-ONNX for speech tasks (STT, TTS, VAD)
 */

#include "onnx_backend.h"

#include <dirent.h>
#include <sys/stat.h>

#include <cstring>

#include "rac/core/rac_logger.h"

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
        recognizer_config.model_config.nemo_ctc.model = nemo_ctc_model_path.c_str();
        recognizer_config.model_config.model_type = "nemo_ctc";

        RAC_LOG_INFO("ONNX.STT", "Configuring NeMo CTC recognizer");
    } else {
        // Configure for Whisper (encoder-decoder)
        recognizer_config.model_config.whisper.encoder = encoder_path.c_str();
        recognizer_config.model_config.whisper.decoder = decoder_path.c_str();
        recognizer_config.model_config.whisper.language = language_.c_str();
        recognizer_config.model_config.whisper.task = "transcribe";
        recognizer_config.model_config.model_type = "whisper";
    }

    recognizer_config.model_config.tokens = tokens_path.c_str();
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

    std::string model_onnx_path;
    std::string tokens_path;
    std::string data_dir;
    std::string lexicon_path;
    std::string voices_path;  // For Kokoro TTS

    struct stat path_stat;
    if (stat(model_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Model path does not exist: %s", model_path.c_str());
        return false;
    }

    if (S_ISDIR(path_stat.st_mode)) {
        model_onnx_path = model_path + "/model.onnx";
        tokens_path = model_path + "/tokens.txt";
        data_dir = model_path + "/espeak-ng-data";
        lexicon_path = model_path + "/lexicon.txt";
        voices_path = model_path + "/voices.bin";  // Kokoro specific

        // Try model.onnx first, then model.int8.onnx (for int8 quantized Kokoro)
        if (stat(model_onnx_path.c_str(), &path_stat) != 0) {
            std::string int8_model_path = model_path + "/model.int8.onnx";
            if (stat(int8_model_path.c_str(), &path_stat) == 0) {
                model_onnx_path = int8_model_path;
                RAC_LOG_DEBUG("ONNX.TTS", "Found int8 model file: %s", model_onnx_path.c_str());
            } else {
                // Fallback: search for any .onnx file
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

        // Try to find combined lexicon files for Kokoro
        std::string lexicon_us_en = model_path + "/lexicon-us-en.txt";
        std::string lexicon_zh = model_path + "/lexicon-zh.txt";
        std::string lexicon_gb_en = model_path + "/lexicon-gb-en.txt";
        if (stat(lexicon_us_en.c_str(), &path_stat) == 0) {
            lexicon_path = lexicon_us_en;
            // Check for additional lexicons and combine paths
            if (stat(lexicon_zh.c_str(), &path_stat) == 0) {
                lexicon_path = lexicon_us_en + "," + lexicon_zh;
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
            voices_path = dir + "/voices.bin";
            model_dir_ = dir;
        }
    }

    RAC_LOG_INFO("ONNX.TTS", "Model ONNX: %s", model_onnx_path.c_str());
    RAC_LOG_INFO("ONNX.TTS", "Tokens: %s", tokens_path.c_str());

    if (stat(model_onnx_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Model ONNX file not found: %s", model_onnx_path.c_str());
        return false;
    }

    if (stat(tokens_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Tokens file not found: %s", tokens_path.c_str());
        return false;
    }

    // Detect Kokoro model: either explicitly set as KOKORO type, or has voices.bin file
    bool is_kokoro = (model_type == TTSModelType::KOKORO) ||
                     (stat(voices_path.c_str(), &path_stat) == 0 && S_ISREG(path_stat.st_mode));

    if (is_kokoro) {
        model_type_ = TTSModelType::KOKORO;
        RAC_LOG_INFO("ONNX.TTS", "Detected Kokoro TTS model");
    }

    SherpaOnnxOfflineTtsConfig tts_config;
    memset(&tts_config, 0, sizeof(tts_config));

    if (is_kokoro) {
        // Configure for Kokoro TTS (high quality, multi-speaker, 24kHz)
        tts_config.model.kokoro.model = model_onnx_path.c_str();
        tts_config.model.kokoro.tokens = tokens_path.c_str();
        tts_config.model.kokoro.voices = voices_path.c_str();
        tts_config.model.kokoro.length_scale = 1.0f;  // Normal speed

        if (stat(data_dir.c_str(), &path_stat) == 0 && S_ISDIR(path_stat.st_mode)) {
            tts_config.model.kokoro.data_dir = data_dir.c_str();
            RAC_LOG_DEBUG("ONNX.TTS", "Using espeak-ng data dir: %s", data_dir.c_str());
        }

        if (!lexicon_path.empty() && stat(lexicon_path.c_str(), &path_stat) == 0) {
            tts_config.model.kokoro.lexicon = lexicon_path.c_str();
            RAC_LOG_DEBUG("ONNX.TTS", "Using lexicon: %s", lexicon_path.c_str());
        }

        RAC_LOG_INFO("ONNX.TTS", "Voices file: %s", voices_path.c_str());
    } else {
        // Configure for VITS/Piper TTS
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

    tts_config.model.provider = "cpu";
    tts_config.model.num_threads = 2;
    tts_config.model.debug = 1;

    RAC_LOG_INFO("ONNX.TTS", "Creating SherpaOnnxOfflineTts (%s)...",
                 is_kokoro ? "Kokoro" : "VITS/Piper");

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

    sample_rate_ = SherpaOnnxOfflineTtsSampleRate(sherpa_tts_);
    int num_speakers = SherpaOnnxOfflineTtsNumSpeakers(sherpa_tts_);

    RAC_LOG_INFO("ONNX.TTS", "TTS model loaded successfully");
    RAC_LOG_INFO("ONNX.TTS", "Sample rate: %d, speakers: %d", sample_rate_, num_speakers);

    voices_.clear();

    if (is_kokoro && num_speakers >= 53) {
        // Kokoro multi-lang v1.0 speaker names
        // Reference: https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html
        const char* kokoro_speakers[] = {
            "af_alloy", "af_aoede", "af_bella", "af_heart", "af_jessica",
            "af_kore", "af_nicole", "af_nova", "af_river", "af_sarah",
            "af_sky", "am_adam", "am_echo", "am_eric", "am_fenrir",
            "am_liam", "am_michael", "am_onyx", "am_puck", "am_santa",
            "bf_alice", "bf_emma", "bf_isabella", "bf_lily", "bm_daniel",
            "bm_fable", "bm_george", "bm_lewis", "ef_dora", "em_alex",
            "ff_siwis", "hf_alpha", "hf_beta", "hm_omega", "hm_psi",
            "if_sara", "im_nicola", "jf_alpha", "jf_gongitsune", "jf_nezumi",
            "jf_tebukuro", "jm_kumo", "pf_dora", "pm_alex", "pm_santa",
            "zf_xiaobei", "zf_xiaoni", "zf_xiaoxiao", "zf_xiaoyi", "zm_yunjian",
            "zm_yunxi", "zm_yunxia", "zm_yunyang"
        };

        for (int i = 0; i < std::min(num_speakers, 53); ++i) {
            VoiceInfo voice;
            voice.id = std::to_string(i);
            voice.name = kokoro_speakers[i];
            // Determine language from speaker prefix
            if (voice.name[0] == 'a' || voice.name[0] == 'b') {
                voice.language = "en";
            } else if (voice.name[0] == 'z') {
                voice.language = "zh";
            } else {
                voice.language = "en";
            }
            // Determine gender from speaker prefix
            voice.gender = (voice.name[1] == 'm') ? "male" : "female";
            voice.sample_rate = 24000;  // Kokoro is 24kHz
            voices_.push_back(voice);
        }
        // Add remaining speakers if any
        for (int i = 53; i < num_speakers; ++i) {
            VoiceInfo voice;
            voice.id = std::to_string(i);
            voice.name = "Speaker " + std::to_string(i);
            voice.language = "en";
            voice.sample_rate = 24000;
            voices_.push_back(voice);
        }
    } else {
        // Generic speaker names for VITS/Piper or other models
        for (int i = 0; i < num_speakers; ++i) {
            VoiceInfo voice;
            voice.id = std::to_string(i);
            voice.name = "Speaker " + std::to_string(i);
            voice.language = "en";
            voice.sample_rate = sample_rate_;
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
