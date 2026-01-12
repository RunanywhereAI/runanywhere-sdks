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
    recognizer_config.model_config.provider = "cpu";
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

    std::string model_onnx_path;
    std::string tokens_path;
    std::string data_dir;
    std::string lexicon_path;

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
        return false;
    }

    if (stat(tokens_path.c_str(), &path_stat) != 0) {
        RAC_LOG_ERROR("ONNX.TTS", "Tokens file not found: %s", tokens_path.c_str());
        return false;
    }

    SherpaOnnxOfflineTtsConfig tts_config;
    memset(&tts_config, 0, sizeof(tts_config));

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

    tts_config.model.provider = "cpu";
    tts_config.model.num_threads = 2;
    tts_config.model.debug = 1;

    RAC_LOG_INFO("ONNX.TTS", "Creating SherpaOnnxOfflineTts...");

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
    for (int i = 0; i < num_speakers; ++i) {
        VoiceInfo voice;
        voice.id = std::to_string(i);
        voice.name = "Speaker " + std::to_string(i);
        voice.language = "en";
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
