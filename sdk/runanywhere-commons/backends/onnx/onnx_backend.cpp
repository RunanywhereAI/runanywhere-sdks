/**
 * ONNX Backend Implementation
 *
 * This file implements the capability-based ONNX backend using:
 * - ONNX Runtime for general ML inference
 * - Sherpa-ONNX for speech tasks (STT, TTS, VAD, Diarization)
 */

#include "onnx_backend.h"

#include <dirent.h>

#include <cstring>
#include <sys/stat.h>

#include "../logger.h"

namespace runanywhere {

// =============================================================================
// ONNXBackendNew Implementation
// =============================================================================

ONNXBackendNew::ONNXBackendNew() {
    // Constructor
}

ONNXBackendNew::~ONNXBackendNew() {
    cleanup();
}

BackendInfo ONNXBackendNew::get_info() const {
    BackendInfo info;
    info.name = "onnx";
    info.version = "2.0.0";
    info.description = "ONNX Runtime backend with Sherpa-ONNX speech support";
    info.supported_capabilities = get_supported_capabilities();
    return info;
}

bool ONNXBackendNew::initialize(const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    if (initialized_) {
        return true;
    }

    config_ = config;

    // Initialize ONNX Runtime
    if (!initialize_ort()) {
        return false;
    }

    // Create capability implementations
    create_capabilities();

    initialized_ = true;
    return true;
}

bool ONNXBackendNew::is_initialized() const {
    return initialized_;
}

void ONNXBackendNew::cleanup() {
    std::lock_guard<std::mutex> lock(mutex_);

    // Clear all capabilities
    clear_capabilities();

    // Cleanup ONNX Runtime
    if (ort_env_) {
        ort_api_->ReleaseEnv(ort_env_);
        ort_env_ = nullptr;
    }

    initialized_ = false;
}

ra_device_type ONNXBackendNew::get_device_type() const {
    // TODO: Detect actual device (CoreML, NNAPI, etc.)
    return RA_DEVICE_CPU;
}

size_t ONNXBackendNew::get_memory_usage() const {
    // TODO: Implement memory tracking
    return 0;
}

void ONNXBackendNew::set_telemetry_callback(TelemetryCallback callback) {
    telemetry_.set_callback(callback);
}

bool ONNXBackendNew::initialize_ort() {
    ort_api_ = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    if (!ort_api_) {
        RA_LOG_ERROR("ONNX", "Failed to get ONNX Runtime API");
        return false;
    }

    OrtStatus* status = ort_api_->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "runanywhere", &ort_env_);
    if (status) {
        RA_LOG_ERROR("ONNX", "Failed to create ONNX Runtime environment: %s",
                     ort_api_->GetErrorMessage(status));
        ort_api_->ReleaseStatus(status);
        return false;
    }

    return true;
}

void ONNXBackendNew::create_capabilities() {
    // Register capabilities based on what's available

    // Text generation - always available with ONNX Runtime
    register_capability(CapabilityType::TEXT_GENERATION,
                        std::make_unique<ONNXTextGeneration>(this));

    // Embeddings - always available
    register_capability(CapabilityType::EMBEDDINGS, std::make_unique<ONNXEmbeddings>(this));

    // STT - available (Whisper via ONNX, streaming via Sherpa-ONNX if available)
    register_capability(CapabilityType::STT, std::make_unique<ONNXSTT>(this));

    // TTS - available via Sherpa-ONNX
#if SHERPA_ONNX_AVAILABLE
    register_capability(CapabilityType::TTS, std::make_unique<ONNXTTS>(this));

    // VAD - available via Sherpa-ONNX
    register_capability(CapabilityType::VAD, std::make_unique<ONNXVAD>(this));

    // Diarization - available via Sherpa-ONNX
    register_capability(CapabilityType::DIARIZATION, std::make_unique<ONNXDiarization>(this));
#endif
}

// =============================================================================
// ONNXTextGeneration Implementation
// =============================================================================

ONNXTextGeneration::ONNXTextGeneration(ONNXBackendNew* backend) : backend_(backend) {}

ONNXTextGeneration::~ONNXTextGeneration() {
    unload_model();
}

bool ONNXTextGeneration::is_ready() const {
    return model_loaded_;
}

bool ONNXTextGeneration::load_model(const std::string& model_path, const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

    // TODO: Implement ONNX model loading
    model_path_ = model_path;
    model_config_ = config;
    model_loaded_ = true;

    return true;
}

bool ONNXTextGeneration::is_model_loaded() const {
    return model_loaded_;
}

bool ONNXTextGeneration::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);

    if (session_) {
        backend_->get_ort_api()->ReleaseSession(session_);
        session_ = nullptr;
    }
    model_loaded_ = false;

    return true;
}

TextGenerationResult ONNXTextGeneration::generate(const TextGenerationRequest& request) {
    TextGenerationResult result;

    // TODO: Implement text generation inference
    result.text = "[Text generation not yet implemented]";
    result.tokens_generated = 0;
    result.finish_reason = "not_implemented";

    return result;
}

bool ONNXTextGeneration::generate_stream(const TextGenerationRequest& request,
                                         TextStreamCallback callback) {
    // TODO: Implement streaming text generation
    return false;
}

void ONNXTextGeneration::cancel() {
    cancel_requested_ = true;
}

nlohmann::json ONNXTextGeneration::get_model_info() const {
    return {{"path", model_path_}, {"loaded", model_loaded_}};
}

// =============================================================================
// ONNXEmbeddings Implementation
// =============================================================================

ONNXEmbeddings::ONNXEmbeddings(ONNXBackendNew* backend) : backend_(backend) {}

ONNXEmbeddings::~ONNXEmbeddings() {
    unload_model();
}

bool ONNXEmbeddings::is_ready() const {
    return model_loaded_;
}

bool ONNXEmbeddings::load_model(const std::string& model_path, const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);
    // TODO: Implement model loading
    model_loaded_ = true;
    return true;
}

bool ONNXEmbeddings::is_model_loaded() const {
    return model_loaded_;
}

bool ONNXEmbeddings::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (session_) {
        backend_->get_ort_api()->ReleaseSession(session_);
        session_ = nullptr;
    }
    model_loaded_ = false;
    return true;
}

EmbeddingResult ONNXEmbeddings::embed(const EmbeddingRequest& request) {
    EmbeddingResult result;
    // TODO: Implement embedding inference
    return result;
}

BatchEmbeddingResult ONNXEmbeddings::embed_batch(const std::vector<std::string>& texts) {
    BatchEmbeddingResult result;
    // TODO: Implement batch embedding
    return result;
}

int ONNXEmbeddings::get_dimensions() const {
    return dimensions_;
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
    // Unload any existing model
    if (sherpa_recognizer_) {
        SherpaOnnxDestroyOfflineRecognizer(sherpa_recognizer_);
        sherpa_recognizer_ = nullptr;
    }

    model_type_ = model_type;
    model_dir_ = model_path;

    RA_LOG_INFO("ONNX.STT", "Loading model from: %s", model_path.c_str());

    // Check if model_path is a directory or file
    struct stat path_stat;
    if (stat(model_path.c_str(), &path_stat) != 0) {
        RA_LOG_ERROR("ONNX.STT", "Model path does not exist: %s", model_path.c_str());
        return false;
    }

    // Determine model files based on model type
    std::string encoder_path;
    std::string decoder_path;
    std::string tokens_path;

    if (S_ISDIR(path_stat.st_mode)) {
        // It's a directory - search for model files
        // For Whisper models from sherpa-onnx:
        // - encoder: *-encoder.onnx or encoder.onnx
        // - decoder: *-decoder.onnx or decoder.onnx
        // - tokens: tokens.txt or *tokens*.txt

        DIR* dir = opendir(model_path.c_str());
        if (!dir) {
            RA_LOG_ERROR("ONNX.STT", "Cannot open model directory: %s", model_path.c_str());
            return false;
        }

        struct dirent* entry;
        while ((entry = readdir(dir)) != nullptr) {
            std::string filename = entry->d_name;
            std::string full_path = model_path + "/" + filename;

            // Find encoder
            if (filename.find("encoder") != std::string::npos && filename.size() > 5 &&
                filename.substr(filename.size() - 5) == ".onnx") {
                encoder_path = full_path;
                RA_LOG_DEBUG("ONNX.STT", "Found encoder: %s", encoder_path.c_str());
            }
            // Find decoder
            else if (filename.find("decoder") != std::string::npos && filename.size() > 5 &&
                     filename.substr(filename.size() - 5) == ".onnx") {
                decoder_path = full_path;
                RA_LOG_DEBUG("ONNX.STT", "Found decoder: %s", decoder_path.c_str());
            }
            // Find tokens
            else if (filename == "tokens.txt" || (filename.find("tokens") != std::string::npos &&
                                                  filename.find(".txt") != std::string::npos)) {
                tokens_path = full_path;
                RA_LOG_DEBUG("ONNX.STT", "Found tokens: %s", tokens_path.c_str());
            }
        }
        closedir(dir);

        // If we didn't find encoder/decoder by name pattern, try common names
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
        // It's a file - assume it's the encoder and look for siblings
        encoder_path = model_path;
        size_t last_slash = model_path.find_last_of('/');
        if (last_slash != std::string::npos) {
            std::string dir = model_path.substr(0, last_slash);
            model_dir_ = dir;

            // Try to find decoder and tokens in same directory
            decoder_path = dir + "/decoder.onnx";
            tokens_path = dir + "/tokens.txt";
        }
    }

    // Get language from config or default to English
    language_ = "en";
    if (config.contains("language")) {
        language_ = config["language"].get<std::string>();
    }

    RA_LOG_INFO("ONNX.STT", "Encoder: %s", encoder_path.c_str());
    RA_LOG_INFO("ONNX.STT", "Decoder: %s", decoder_path.c_str());
    RA_LOG_INFO("ONNX.STT", "Tokens: %s", tokens_path.c_str());
    RA_LOG_INFO("ONNX.STT", "Language: %s", language_.c_str());

    // Verify required files exist
    if (stat(encoder_path.c_str(), &path_stat) != 0) {
        RA_LOG_ERROR("ONNX.STT", "Encoder file not found: %s", encoder_path.c_str());
        return false;
    }
    if (stat(decoder_path.c_str(), &path_stat) != 0) {
        RA_LOG_ERROR("ONNX.STT", "Decoder file not found: %s", decoder_path.c_str());
        return false;
    }
    if (stat(tokens_path.c_str(), &path_stat) != 0) {
        RA_LOG_ERROR("ONNX.STT", "Tokens file not found: %s", tokens_path.c_str());
        return false;
    }

    // Create recognizer configuration
    SherpaOnnxOfflineRecognizerConfig recognizer_config;
    memset(&recognizer_config, 0, sizeof(recognizer_config));

    // Feature configuration - Whisper expects 16kHz audio, 80-dim features
    recognizer_config.feat_config.sample_rate = 16000;
    recognizer_config.feat_config.feature_dim = 80;

    // Initialize ALL string fields to empty strings to prevent strlen(nullptr) crash
    // Transducer model (not used but fields must not be null)
    recognizer_config.model_config.transducer.encoder = "";
    recognizer_config.model_config.transducer.decoder = "";
    recognizer_config.model_config.transducer.joiner = "";

    // Paraformer model (not used)
    recognizer_config.model_config.paraformer.model = "";

    // NeMo CTC model (not used)
    recognizer_config.model_config.nemo_ctc.model = "";

    // TDNN model (not used)
    recognizer_config.model_config.tdnn.model = "";

    // Model configuration for Whisper (the one we're actually using)
    recognizer_config.model_config.whisper.encoder = encoder_path.c_str();
    recognizer_config.model_config.whisper.decoder = decoder_path.c_str();
    recognizer_config.model_config.whisper.language = language_.c_str();
    recognizer_config.model_config.whisper.task = "transcribe";
    recognizer_config.model_config.whisper.tail_paddings = -1;  // Use default

    // General model config
    recognizer_config.model_config.tokens = tokens_path.c_str();
    recognizer_config.model_config.num_threads = 2;
    recognizer_config.model_config.debug = 1;
    recognizer_config.model_config.provider = "cpu";
    recognizer_config.model_config.model_type = "whisper";

    // Required string fields - must be empty string, not nullptr
    // Sherpa-ONNX calls strlen() on these, so nullptr causes crash
    recognizer_config.model_config.modeling_unit = "cjkchar";
    recognizer_config.model_config.bpe_vocab = "";
    recognizer_config.model_config.telespeech_ctc = "";

    // SenseVoice model (not used)
    recognizer_config.model_config.sense_voice.model = "";
    recognizer_config.model_config.sense_voice.language = "";

    // Moonshine model (not used)
    recognizer_config.model_config.moonshine.preprocessor = "";
    recognizer_config.model_config.moonshine.encoder = "";
    recognizer_config.model_config.moonshine.uncached_decoder = "";
    recognizer_config.model_config.moonshine.cached_decoder = "";

    // FireRedAsr model (not used)
    recognizer_config.model_config.fire_red_asr.encoder = "";
    recognizer_config.model_config.fire_red_asr.decoder = "";

    // Dolphin model (not used)
    recognizer_config.model_config.dolphin.model = "";

    // ZipformerCtc model (not used)
    recognizer_config.model_config.zipformer_ctc.model = "";

    // Canary model (not used)
    recognizer_config.model_config.canary.encoder = "";
    recognizer_config.model_config.canary.decoder = "";
    recognizer_config.model_config.canary.src_lang = "";
    recognizer_config.model_config.canary.tgt_lang = "";

    // WenetCtc model (not used)
    recognizer_config.model_config.wenet_ctc.model = "";

    // Omnilingual model (not used)
    recognizer_config.model_config.omnilingual.model = "";

    // LM config defaults (must match library expectations)
    recognizer_config.lm_config.model = "";
    recognizer_config.lm_config.scale = 1.0f;
    // Note: lodr_scale, lodr_fst, lodr_backoff_id removed in sherpa-onnx 1.12.18+
    // Note: ctc_fst_decoder_config removed in sherpa-onnx 1.12.18+

    // Decoding configuration
    recognizer_config.decoding_method = "greedy_search";
    recognizer_config.max_active_paths = 4;
    recognizer_config.hotwords_file = "";
    recognizer_config.hotwords_score = 1.5f;
    recognizer_config.blank_penalty = 0.0f;
    recognizer_config.rule_fsts = "";
    recognizer_config.rule_fars = "";

    // Homophone replacer config
    recognizer_config.hr.dict_dir = "";
    recognizer_config.hr.lexicon = "";
    recognizer_config.hr.rule_fsts = "";

    // Create the recognizer - with extensive debug logging
    RA_LOG_INFO("ONNX.STT", "Creating SherpaOnnxOfflineRecognizer...");
    RA_LOG_DEBUG("ONNX.STT", "Config: sample_rate=%d, feature_dim=%d",
                 recognizer_config.feat_config.sample_rate,
                 recognizer_config.feat_config.feature_dim);
    RA_LOG_DEBUG("ONNX.STT", "Whisper encoder=%s",
                 recognizer_config.model_config.whisper.encoder
                     ? recognizer_config.model_config.whisper.encoder
                     : "NULL");
    RA_LOG_DEBUG("ONNX.STT", "Whisper decoder=%s",
                 recognizer_config.model_config.whisper.decoder
                     ? recognizer_config.model_config.whisper.decoder
                     : "NULL");
    RA_LOG_DEBUG("ONNX.STT", "Whisper language=%s, task=%s",
                 recognizer_config.model_config.whisper.language
                     ? recognizer_config.model_config.whisper.language
                     : "NULL",
                 recognizer_config.model_config.whisper.task
                     ? recognizer_config.model_config.whisper.task
                     : "NULL");
    RA_LOG_DEBUG(
        "ONNX.STT", "tokens=%s, provider=%s, model_type=%s",
        recognizer_config.model_config.tokens ? recognizer_config.model_config.tokens : "NULL",
        recognizer_config.model_config.provider ? recognizer_config.model_config.provider : "NULL",
        recognizer_config.model_config.model_type ? recognizer_config.model_config.model_type
                                                  : "NULL");
    RA_LOG_DEBUG("ONNX.STT", "Struct size=%zu bytes", sizeof(recognizer_config));

    sherpa_recognizer_ = SherpaOnnxCreateOfflineRecognizer(&recognizer_config);

    if (!sherpa_recognizer_) {
        RA_LOG_ERROR("ONNX.STT", "Failed to create SherpaOnnxOfflineRecognizer");
        return false;
    }

    RA_LOG_INFO("ONNX.STT", "STT model loaded successfully");
    model_loaded_ = true;
    return true;

#else
    RA_LOG_ERROR("ONNX.STT", "Sherpa-ONNX not available - streaming STT disabled");
    return false;
#endif
}

bool ONNXSTT::is_model_loaded() const {
    return model_loaded_;
}

bool ONNXSTT::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
    // Destroy all active streams first
    for (auto& pair : sherpa_streams_) {
        if (pair.second) {
            SherpaOnnxDestroyOfflineStream(pair.second);
        }
    }
    sherpa_streams_.clear();

    // Destroy the recognizer
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
        RA_LOG_ERROR("ONNX.STT", "STT not ready for transcription");
        result.text = "[Error: STT model not loaded]";
        return result;
    }

    RA_LOG_INFO("ONNX.STT", "Transcribing %zu samples at %d Hz", request.audio_samples.size(),
                request.sample_rate);

    // Create an offline stream
    const SherpaOnnxOfflineStream* stream = SherpaOnnxCreateOfflineStream(sherpa_recognizer_);
    if (!stream) {
        RA_LOG_ERROR("ONNX.STT", "Failed to create offline stream");
        result.text = "[Error: Failed to create stream]";
        return result;
    }

    // Accept the waveform data
    // Note: Sherpa-ONNX expects samples normalized to [-1, 1] range
    SherpaOnnxAcceptWaveformOffline(stream, request.sample_rate, request.audio_samples.data(),
                                    static_cast<int32_t>(request.audio_samples.size()));

    // Decode the audio
    RA_LOG_DEBUG("ONNX.STT", "Decoding audio...");
    SherpaOnnxDecodeOfflineStream(sherpa_recognizer_, stream);

    // Get the result
    const SherpaOnnxOfflineRecognizerResult* recognizer_result =
        SherpaOnnxGetOfflineStreamResult(stream);

    if (recognizer_result && recognizer_result->text) {
        result.text = recognizer_result->text;
        RA_LOG_INFO("ONNX.STT", "Transcription result: \"%s\"", result.text.c_str());

        // Extract timestamps if available
        if (recognizer_result->timestamps && recognizer_result->count > 0) {
            // Could populate segments here if needed
            result.inference_time_ms = 0;  // Would need timing code
        }

        // Get language if available
        if (recognizer_result->lang) {
            result.detected_language = recognizer_result->lang;
        }

        // Parse JSON result for more details if needed
        if (recognizer_result->json) {
            try {
                auto json_result = nlohmann::json::parse(recognizer_result->json);
                // Could extract additional fields from JSON
            } catch (...) {
                // Ignore JSON parsing errors
            }
        }

        // Free the result
        SherpaOnnxDestroyOfflineRecognizerResult(recognizer_result);
    } else {
        result.text = "";
        RA_LOG_DEBUG("ONNX.STT", "No transcription result (empty audio or silence)");
    }

    // Destroy the stream
    SherpaOnnxDestroyOfflineStream(stream);

    return result;

#else
    RA_LOG_ERROR("ONNX.STT", "Sherpa-ONNX not available");
    result.text = "[Error: Sherpa-ONNX not available]";
    return result;
#endif
}

bool ONNXSTT::supports_streaming() const {
#if SHERPA_ONNX_AVAILABLE
    // Whisper models in sherpa-onnx support offline (batch) mode
    // For true streaming, we'd need online models like Zipformer
    return false;  // Whisper is offline only
#else
    return false;
#endif
}

std::string ONNXSTT::create_stream(const nlohmann::json& config) {
#if SHERPA_ONNX_AVAILABLE
    std::lock_guard<std::mutex> lock(mutex_);

    if (!sherpa_recognizer_) {
        RA_LOG_ERROR("ONNX.STT", "Cannot create stream: recognizer not initialized");
        return "";
    }

    // Create a new offline stream
    const SherpaOnnxOfflineStream* stream = SherpaOnnxCreateOfflineStream(sherpa_recognizer_);
    if (!stream) {
        RA_LOG_ERROR("ONNX.STT", "Failed to create offline stream");
        return "";
    }

    // Generate a unique stream ID
    std::string stream_id = "stt_stream_" + std::to_string(++stream_counter_);
    sherpa_streams_[stream_id] = stream;

    RA_LOG_DEBUG("ONNX.STT", "Created stream: %s", stream_id.c_str());
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
        RA_LOG_ERROR("ONNX.STT", "Stream not found: %s", stream_id.c_str());
        return false;
    }

    // For offline streams, we accumulate audio
    // Note: SherpaOnnxAcceptWaveformOffline can only be called once per stream
    // So for streaming-like behavior, we need to buffer and process at the end
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
        RA_LOG_ERROR("ONNX.STT", "Stream not found for decode: %s", stream_id.c_str());
        return result;
    }

    if (!sherpa_recognizer_) {
        RA_LOG_ERROR("ONNX.STT", "Recognizer not available");
        return result;
    }

    // Decode the stream
    SherpaOnnxDecodeOfflineStream(sherpa_recognizer_, it->second);

    // Get the result
    const SherpaOnnxOfflineRecognizerResult* recognizer_result =
        SherpaOnnxGetOfflineStreamResult(it->second);

    if (recognizer_result && recognizer_result->text) {
        result.text = recognizer_result->text;
        RA_LOG_INFO("ONNX.STT", "Decode result: \"%s\"", result.text.c_str());

        if (recognizer_result->lang) {
            result.detected_language = recognizer_result->lang;
        }

        SherpaOnnxDestroyOfflineRecognizerResult(recognizer_result);
    }
#endif

    return result;
}

bool ONNXSTT::is_endpoint(const std::string& stream_id) {
    // For offline recognition, endpoint detection isn't applicable
    // This is more relevant for online/streaming recognition
    return false;
}

void ONNXSTT::input_finished(const std::string& stream_id) {
    // For offline recognition, this is a no-op
    // The decode() call will process all received audio
}

void ONNXSTT::reset_stream(const std::string& stream_id) {
#if SHERPA_ONNX_AVAILABLE
    std::lock_guard<std::mutex> lock(mutex_);

    auto it = sherpa_streams_.find(stream_id);
    if (it != sherpa_streams_.end() && it->second) {
        // Destroy old stream
        SherpaOnnxDestroyOfflineStream(it->second);

        // Create new stream
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
        RA_LOG_DEBUG("ONNX.STT", "Destroyed stream: %s", stream_id.c_str());
    }
#endif
}

void ONNXSTT::cancel() {
    cancel_requested_ = true;
}

std::vector<std::string> ONNXSTT::get_supported_languages() const {
    // Whisper supports many languages
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
    // Try to unload, but don't block if mutex is already destroyed
    // This can happen during static destruction
    try {
        unload_model();
    } catch (...) {
        // Silently ignore - object is being destroyed anyway
    }
}

bool ONNXTTS::is_ready() const {
    // Lock for thread-safe access to both model_loaded_ and sherpa_tts_
    std::lock_guard<std::mutex> lock(mutex_);
    return model_loaded_ && sherpa_tts_ != nullptr;
}

bool ONNXTTS::load_model(const std::string& model_path, TTSModelType model_type,
                         const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
    // Unload any existing model
    if (sherpa_tts_) {
        SherpaOnnxDestroyOfflineTts(sherpa_tts_);
        sherpa_tts_ = nullptr;
    }

    model_type_ = model_type;
    model_dir_ = model_path;

    RA_LOG_INFO("ONNX.TTS", "Loading model from: %s", model_path.c_str());

    // Check for model files in the directory
    // Sherpa-onnx VITS model packages typically contain:
    // - model.onnx (or <name>.onnx)
    // - tokens.txt
    // - espeak-ng-data/ directory

    std::string model_onnx_path;
    std::string tokens_path;
    std::string data_dir;
    std::string lexicon_path;

    // Try to find model files
    // First, check if model_path is a file or directory
    struct stat path_stat;
    if (stat(model_path.c_str(), &path_stat) != 0) {
        RA_LOG_ERROR("ONNX.TTS", "Model path does not exist: %s", model_path.c_str());
        return false;
    }

    if (S_ISDIR(path_stat.st_mode)) {
        // It's a directory, look for model files
        model_onnx_path = model_path + "/model.onnx";
        tokens_path = model_path + "/tokens.txt";
        data_dir = model_path + "/espeak-ng-data";
        lexicon_path = model_path + "/lexicon.txt";

        // Check if model.onnx exists, if not try to find any .onnx file
        if (stat(model_onnx_path.c_str(), &path_stat) != 0) {
            // Try to find .onnx file in the directory
            DIR* dir = opendir(model_path.c_str());
            if (dir) {
                struct dirent* entry;
                while ((entry = readdir(dir)) != nullptr) {
                    std::string filename = entry->d_name;
                    if (filename.size() > 5 && filename.substr(filename.size() - 5) == ".onnx") {
                        model_onnx_path = model_path + "/" + filename;
                        RA_LOG_DEBUG("ONNX.TTS", "Found model file: %s", model_onnx_path.c_str());
                        break;
                    }
                }
                closedir(dir);
            }
        }

        // Check for data directory variants
        if (stat(data_dir.c_str(), &path_stat) != 0) {
            // Try alternative names
            std::string alt_data_dir = model_path + "/data";
            if (stat(alt_data_dir.c_str(), &path_stat) == 0) {
                data_dir = alt_data_dir;
            }
        }

        // Check for lexicon file variants
        if (stat(lexicon_path.c_str(), &path_stat) != 0) {
            // Try alternative names
            std::string alt_lexicon = model_path + "/lexicon";
            if (stat(alt_lexicon.c_str(), &path_stat) == 0) {
                lexicon_path = alt_lexicon;
            }
        }
    } else {
        // It's a file, assume it's the model file
        model_onnx_path = model_path;

        // Derive directory from file path
        size_t last_slash = model_path.find_last_of('/');
        if (last_slash != std::string::npos) {
            std::string dir = model_path.substr(0, last_slash);
            tokens_path = dir + "/tokens.txt";
            data_dir = dir + "/espeak-ng-data";
            lexicon_path = dir + "/lexicon.txt";
            model_dir_ = dir;
        }
    }

    RA_LOG_INFO("ONNX.TTS", "Model ONNX: %s", model_onnx_path.c_str());
    RA_LOG_INFO("ONNX.TTS", "Tokens: %s", tokens_path.c_str());
    RA_LOG_DEBUG("ONNX.TTS", "Data dir: %s", data_dir.c_str());
    RA_LOG_DEBUG("ONNX.TTS", "Lexicon: %s", lexicon_path.c_str());

    // Verify model file exists
    if (stat(model_onnx_path.c_str(), &path_stat) != 0) {
        RA_LOG_ERROR("ONNX.TTS", "Model ONNX file not found: %s", model_onnx_path.c_str());
        return false;
    }

    // Verify tokens file exists (required)
    if (stat(tokens_path.c_str(), &path_stat) != 0) {
        RA_LOG_ERROR("ONNX.TTS", "Tokens file not found: %s", tokens_path.c_str());
        return false;
    }

    // Create TTS configuration
    SherpaOnnxOfflineTtsConfig tts_config;
    memset(&tts_config, 0, sizeof(tts_config));

    // Configure VITS model (used by Piper and KittenTTS)
    tts_config.model.vits.model = model_onnx_path.c_str();
    tts_config.model.vits.tokens = tokens_path.c_str();

    // Check if lexicon file exists and set it (required for some models like KittenTTS)
    if (stat(lexicon_path.c_str(), &path_stat) == 0 && S_ISREG(path_stat.st_mode)) {
        tts_config.model.vits.lexicon = lexicon_path.c_str();
        RA_LOG_DEBUG("ONNX.TTS", "Using lexicon file: %s", lexicon_path.c_str());
    } else {
        RA_LOG_DEBUG("ONNX.TTS", "Lexicon file not found (optional): %s", lexicon_path.c_str());
    }

    // Check if data_dir exists and set it
    if (stat(data_dir.c_str(), &path_stat) == 0 && S_ISDIR(path_stat.st_mode)) {
        tts_config.model.vits.data_dir = data_dir.c_str();
        RA_LOG_DEBUG("ONNX.TTS", "Using espeak-ng data dir: %s", data_dir.c_str());
    } else {
        RA_LOG_DEBUG("ONNX.TTS", "espeak-ng data dir not found (optional): %s", data_dir.c_str());
    }

    // Set inference parameters (defaults for VITS/Piper)
    tts_config.model.vits.noise_scale = 0.667f;
    tts_config.model.vits.noise_scale_w = 0.8f;
    tts_config.model.vits.length_scale = 1.0f;  // Normal speed

    // Set model provider to CPU
    tts_config.model.provider = "cpu";
    tts_config.model.num_threads = 2;
    tts_config.model.debug = 1;  // Enable debug output

    // Create TTS instance with error handling
    RA_LOG_INFO("ONNX.TTS", "Creating SherpaOnnxOfflineTts...");
    RA_LOG_DEBUG("ONNX.TTS", "Model path: %s", model_onnx_path.c_str());
    RA_LOG_DEBUG("ONNX.TTS", "Tokens path: %s", tokens_path.c_str());

    const SherpaOnnxOfflineTts* new_tts = nullptr;
    try {
        new_tts = SherpaOnnxCreateOfflineTts(&tts_config);
    } catch (const std::exception& e) {
        RA_LOG_ERROR("ONNX.TTS", "Exception during TTS creation: %s", e.what());
        return false;
    } catch (...) {
        RA_LOG_ERROR("ONNX.TTS", "Unknown exception during TTS creation");
        return false;
    }

    if (!new_tts) {
        RA_LOG_ERROR("ONNX.TTS", "Failed to create SherpaOnnxOfflineTts");
        return false;
    }

    // Only assign to member variable after successful creation
    // This ensures we don't have a partially initialized object
    sherpa_tts_ = new_tts;

    // Get sample rate from the TTS instance
    sample_rate_ = SherpaOnnxOfflineTtsSampleRate(sherpa_tts_);
    int num_speakers = SherpaOnnxOfflineTtsNumSpeakers(sherpa_tts_);

    RA_LOG_INFO("ONNX.TTS", "TTS model loaded successfully");
    RA_LOG_INFO("ONNX.TTS", "Sample rate: %d, speakers: %d", sample_rate_, num_speakers);

    // Create voice info entries for each speaker
    voices_.clear();
    for (int i = 0; i < num_speakers; ++i) {
        VoiceInfo voice;
        voice.id = std::to_string(i);
        voice.name = "Speaker " + std::to_string(i);
        voice.language = "en";  // Default to English
        voices_.push_back(voice);
    }

    // Mark as loaded only after everything is initialized
    model_loaded_ = true;
    return true;

#else
    RA_LOG_ERROR("ONNX.TTS", "Sherpa-ONNX not available - TTS disabled");
    return false;
#endif
}

bool ONNXTTS::is_model_loaded() const {
    return model_loaded_;
}

bool ONNXTTS::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
    // Mark as not loaded first to prevent new operations
    model_loaded_ = false;

    // Check if synthesis is in progress (just for logging)
    if (active_synthesis_count_ > 0) {
        RA_LOG_WARNING("ONNX.TTS",
                       "Unloading model while %d synthesis operation(s) may be in progress",
                       active_synthesis_count_.load());
    }

    // Clear voices before destroying TTS
    voices_.clear();

    // Destroy TTS instance
    // Note: We release the lock before synthesis, so active synthesis operations
    // have a local copy of the pointer. However, destroying the TTS object here
    // could cause issues if synthesis is still using it. The caller should ensure
    // synthesis is complete before calling unload_model().
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
    // Use RAII to ensure counter is decremented even on exception
    struct SynthesisGuard {
        std::atomic<int>& count_;
        SynthesisGuard(std::atomic<int>& count) : count_(count) { count_++; }
        ~SynthesisGuard() { count_--; }
    };
    SynthesisGuard guard(active_synthesis_count_);

    // Lock mutex to get a local copy of the TTS pointer
    // We'll release the lock before the long-running synthesis call
    const SherpaOnnxOfflineTts* tts_ptr = nullptr;
    {
        std::lock_guard<std::mutex> lock(mutex_);

        if (!sherpa_tts_ || !model_loaded_) {
            RA_LOG_ERROR("ONNX.TTS", "TTS not ready for synthesis");
            return result;  // Guard will decrement counter
        }

        // Make a local copy of the pointer while holding the lock
        // This ensures we have a valid pointer even if the object is destroyed
        tts_ptr = sherpa_tts_;
    }  // Release lock here - synthesis can take a long time

    // Now we can safely call the long-running function without holding the lock
    // Note: The TTS object should not be destroyed while synthesis is in progress
    // This is the responsibility of the caller to ensure proper lifecycle management

    RA_LOG_INFO("ONNX.TTS", "Synthesizing: \"%s...\"", request.text.substr(0, 50).c_str());

    // Parse speaker ID from voice_id (default to 0)
    int speaker_id = 0;
    if (!request.voice_id.empty()) {
        try {
            speaker_id = std::stoi(request.voice_id);
        } catch (...) {
            // Use default
        }
    }

    // Calculate speed (speed_rate where 1.0 = normal)
    float speed = request.speed_rate > 0 ? request.speed_rate : 1.0f;

    RA_LOG_DEBUG("ONNX.TTS", "Speaker ID: %d, Speed: %.2f", speaker_id, speed);

    // Generate audio - this is the long-running operation
    // We're not holding the mutex here, so if the object is destroyed,
    // we won't crash with "destroyed mutex" error
    const SherpaOnnxGeneratedAudio* audio =
        SherpaOnnxOfflineTtsGenerate(tts_ptr, request.text.c_str(), speaker_id, speed);

    if (!audio || audio->n <= 0) {
        RA_LOG_ERROR("ONNX.TTS", "Failed to generate audio");
        return result;
    }

    RA_LOG_INFO("ONNX.TTS", "Generated %d samples at %d Hz", audio->n, audio->sample_rate);

    // Copy audio samples to result
    result.audio_samples.assign(audio->samples, audio->samples + audio->n);
    result.sample_rate = audio->sample_rate;
    result.duration_ms =
        (static_cast<double>(audio->n) / static_cast<double>(audio->sample_rate)) * 1000.0;

    // Free the generated audio
    SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);

    RA_LOG_INFO("ONNX.TTS", "Synthesis complete. Duration: %.2fs", (result.duration_ms / 1000.0));

    // Guard will automatically decrement active_synthesis_count_ when it goes out of scope

#else
    RA_LOG_ERROR("ONNX.TTS", "Sherpa-ONNX not available");
#endif

    return result;
}

bool ONNXTTS::synthesize_stream(const TTSRequest& request, TTSStreamCallback callback) {
    // VITS/Piper doesn't support true streaming, but we can chunk the output
    TTSResult result = synthesize(request);

    if (result.audio_samples.empty()) {
        return false;
    }

    // Return all audio in a single chunk
    callback(result.audio_samples, true);
    return true;
}

bool ONNXTTS::supports_streaming() const {
    return false;  // VITS doesn't support true streaming
}

void ONNXTTS::cancel() {
    cancel_requested_ = true;
}

std::vector<VoiceInfo> ONNXTTS::get_voices() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return voices_;
}

std::string ONNXTTS::get_default_voice(const std::string& language) const {
    return "0";  // Default to speaker 0
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
    // TODO: Implement model loading
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
    // TODO: Implement VAD processing
    return result;
}

std::vector<SpeechSegment> ONNXVAD::detect_segments(const std::vector<float>& audio_samples,
                                                    int sample_rate) {
    // TODO: Implement segment detection
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

// =============================================================================
// ONNXDiarization Implementation
// =============================================================================

ONNXDiarization::ONNXDiarization(ONNXBackendNew* backend) : backend_(backend) {}

ONNXDiarization::~ONNXDiarization() {
    unload_model();
}

bool ONNXDiarization::is_ready() const {
    return model_loaded_;
}

bool ONNXDiarization::load_model(const std::string& model_path, DiarizationModelType model_type,
                                 const nlohmann::json& config) {
    std::lock_guard<std::mutex> lock(mutex_);
    // TODO: Implement model loading
    model_loaded_ = true;
    return true;
}

bool ONNXDiarization::is_model_loaded() const {
    return model_loaded_;
}

bool ONNXDiarization::unload_model() {
    std::lock_guard<std::mutex> lock(mutex_);
    model_loaded_ = false;
    return true;
}

DiarizationResult ONNXDiarization::diarize(const DiarizationRequest& request) {
    DiarizationResult result;
    // TODO: Implement diarization
    return result;
}

std::vector<float> ONNXDiarization::extract_embedding(const std::vector<float>& audio_samples,
                                                      int sample_rate) {
    // TODO: Implement speaker embedding extraction
    return {};
}

float ONNXDiarization::compare_speakers(const std::vector<float>& embedding1,
                                        const std::vector<float>& embedding2) {
    // TODO: Implement speaker comparison
    return 0.0f;
}

void ONNXDiarization::cancel() {
    cancel_requested_ = true;
}

// =============================================================================
// Backend Registration
// =============================================================================

// NOTE: We use an explicit registration function instead of the REGISTER_BACKEND
// macro because C++ static initializers in static libraries are not guaranteed
// to run when the library is linked into iOS/macOS apps. The linker may strip
// object files that only contain static initializers with no external references.

// Factory function - creates a new ONNX backend instance
// This is exported and called by the bridge to avoid singleton issues across shared libraries
std::unique_ptr<Backend> create_onnx_backend() {
    return std::make_unique<ONNXBackendNew>();
}

// Registration function - for static library builds (iOS)
// NOTE: For shared library builds (Android), the bridge calls create_onnx_backend()
// directly and registers it to avoid singleton issues
void register_onnx_backend() {
    // Use a static flag to ensure we only register once
    static bool registered = false;
    if (registered) {
        return;
    }

    BackendRegistry::instance().register_backend("onnx", create_onnx_backend);

    registered = true;
}

}  // namespace runanywhere
