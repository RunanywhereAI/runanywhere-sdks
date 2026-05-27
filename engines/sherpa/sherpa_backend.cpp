/**
 * Sherpa-ONNX Backend Implementation
 *
 * Owns STT, TTS, and VAD primitives backed by Sherpa-ONNX.
 *
 * WARNING: The SherpaOnnx*Config structs used here MUST match the prebuilt
 * libsherpa-onnx-c-api binary exactly (same version of c-api.h). A mismatch
 * can crash because the C ABI struct layouts are version-sensitive.
 */

#include "sherpa_backend.h"

#include "core/internal/platform_compat.h"

#ifdef _WIN32
#include <direct.h> // for _mkdir
#endif

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <vector>

#include "rac/core/rac_logger.h"

namespace runanywhere {

// =============================================================================
// SherpaBackend Implementation
// =============================================================================

SherpaBackend::SherpaBackend() {}

SherpaBackend::~SherpaBackend() { cleanup(); }

bool SherpaBackend::initialize(const nlohmann::json &config) {
  std::lock_guard<std::mutex> lock(mutex_);

  if (initialized_) {
    return true;
  }

  config_ = config;
  create_capabilities();
  initialized_ = true;
  return true;
}

bool SherpaBackend::is_initialized() const { return initialized_; }

void SherpaBackend::cleanup() {
  std::lock_guard<std::mutex> lock(mutex_);

  stt_.reset();
  tts_.reset();
  vad_.reset();
  initialized_ = false;
}

DeviceType SherpaBackend::get_device_type() const { return DeviceType::CPU; }

size_t SherpaBackend::get_memory_usage() const { return 0; }

void SherpaBackend::set_telemetry_callback(TelemetryCallback callback) {
  telemetry_.set_callback(callback);
}

void SherpaBackend::create_capabilities() {
  stt_ = std::make_unique<SherpaSTT>(this);

#if SHERPA_ONNX_AVAILABLE
  tts_ = std::make_unique<SherpaTTS>(this);
  vad_ = std::make_unique<SherpaVAD>(this);
#endif
}

// =============================================================================
// SherpaSTT Implementation
// =============================================================================

SherpaSTT::SherpaSTT(SherpaBackend *backend) : backend_(backend) {}

SherpaSTT::~SherpaSTT() { unload_model(); }

bool SherpaSTT::is_ready() const {
#if SHERPA_ONNX_AVAILABLE
  return model_loaded_ && sherpa_recognizer_ != nullptr;
#else
  return model_loaded_;
#endif
}

bool SherpaSTT::load_model(const std::string &model_path,
                           STTModelType model_type,
                           const nlohmann::json &config) {
  std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
  if (sherpa_recognizer_) {
    SherpaOnnxDestroyOfflineRecognizer(sherpa_recognizer_);
    sherpa_recognizer_ = nullptr;
  }

  // engines-sherpa-001: the per-language LRU cache populated by transcribe()
  // belongs to the *previous* model. Without this teardown a swap from model A
  // to model B would leave A's recognizers parked in recognizer_cache_, and a
  // subsequent transcribe() with the cached language would silently reuse the
  // wrong-model recognizer (and leak A's ONNX-runtime sessions). Mirror the
  // unload_model() teardown so the cache is always coherent with the loaded
  // model.
  for (auto &entry : recognizer_cache_) {
    if (entry.second) {
      SherpaOnnxDestroyOfflineRecognizer(entry.second);
    }
  }
  recognizer_cache_.clear();
  recognizer_lru_.clear();

  model_type_ = model_type;
  model_dir_ = model_path;

  RAC_LOG_INFO("Sherpa.STT", "Loading model from: %s", model_path.c_str());

  struct stat path_stat;
  if (stat(model_path.c_str(), &path_stat) != 0) {
    RAC_LOG_ERROR("Sherpa.STT", "Model path does not exist: %s",
                  model_path.c_str());
    return false;
  }

  // Scan the model directory for files
  std::string encoder_path;
  std::string decoder_path;
  std::string tokens_path;
  std::string nemo_ctc_model_path; // Single-file CTC model (model.int8.onnx or
                                   // model.onnx)

  if (S_ISDIR(path_stat.st_mode)) {
    DIR *dir = opendir(model_path.c_str());
    if (!dir) {
      RAC_LOG_ERROR("Sherpa.STT", "Cannot open model directory: %s",
                    model_path.c_str());
      return false;
    }

    // Iteration order from readdir() is filesystem-dependent. To make
    // model discovery deterministic across devices/extractions, we
    // remember candidates separately and pick the preferred variant
    // after the scan. Concretely: when both `*-encoder.onnx` and
    // `*-encoder.int8.onnx` (quantized) exist (which is the case for
    // Sherpa-ONNX Whisper archives like `sherpa-onnx-whisper-tiny.en`
    // that ship `tiny.en-encoder.onnx` AND `tiny.en-encoder.int8.onnx`),
    // we prefer the int8 variant because it is what Sherpa-ONNX
    // recommends for on-device inference (smaller, faster, identical
    // accuracy on Whisper-tiny) and matches what the Voice Assistant
    // path (AK-15) successfully loads. Without this preference, the
    // standalone STT path (AK-11/AK-12) sometimes ended up with the
    // fp32 encoder paired against an int8 decoder (or vice versa) and
    // SherpaOnnxCreateOfflineRecognizer rejected the mismatched pair
    // → -111 RAC_ERROR_MODEL_LOAD_FAILED within ~5 ms.
    std::string encoder_fp32, encoder_int8;
    std::string decoder_fp32, decoder_int8;

    struct dirent *entry;
    while ((entry = readdir(dir)) != nullptr) {
      std::string filename = entry->d_name;
      if (filename == "." || filename == "..")
        continue;
      std::string full_path = model_path + "/" + filename;

      // Match *.onnx files containing "encoder" / "decoder" as a
      // substring (handles the `tiny.en-encoder.onnx` /
      // `tiny.en-encoder.int8.onnx` prefixed naming Sherpa-ONNX uses
      // upstream). Splitting fp32/int8 makes the pairing decision
      // explicit instead of relying on directory-iteration order.
      bool is_onnx = filename.size() > 5 &&
                     filename.substr(filename.size() - 5) == ".onnx";
      bool is_int8 = filename.find(".int8.onnx") != std::string::npos;

      if (is_onnx && filename.find("encoder") != std::string::npos) {
        if (is_int8) {
          encoder_int8 = full_path;
        } else {
          encoder_fp32 = full_path;
        }
        RAC_LOG_DEBUG("Sherpa.STT", "Found encoder candidate: %s",
                      full_path.c_str());
      } else if (is_onnx && filename.find("decoder") != std::string::npos) {
        if (is_int8) {
          decoder_int8 = full_path;
        } else {
          decoder_fp32 = full_path;
        }
        RAC_LOG_DEBUG("Sherpa.STT", "Found decoder candidate: %s",
                      full_path.c_str());
      } else if (filename == "tokens.txt" ||
                 (filename.find("tokens") != std::string::npos &&
                  filename.find(".txt") != std::string::npos)) {
        tokens_path = full_path;
        RAC_LOG_DEBUG("Sherpa.STT", "Found tokens: %s", tokens_path.c_str());
      } else if ((filename == "model.int8.onnx" || filename == "model.onnx") &&
                 encoder_fp32.empty() && encoder_int8.empty()) {
        // Single-file model (NeMo CTC, etc.) - prefer int8 if both exist
        if (filename == "model.int8.onnx" || nemo_ctc_model_path.empty()) {
          nemo_ctc_model_path = full_path;
          RAC_LOG_DEBUG("Sherpa.STT", "Found single-file model: %s",
                        nemo_ctc_model_path.c_str());
        }
      }
    }
    closedir(dir);

    // Pair selection: prefer matching int8 pair (encoder + decoder both
    // quantized). Fall back to fp32 pair, then to whichever side exists.
    // We deliberately avoid mixing fp32 encoder with int8 decoder because
    // Sherpa-ONNX requires the pair to come from the same export.
    if (!encoder_int8.empty() && !decoder_int8.empty()) {
      encoder_path = encoder_int8;
      decoder_path = decoder_int8;
    } else if (!encoder_fp32.empty() && !decoder_fp32.empty()) {
      encoder_path = encoder_fp32;
      decoder_path = decoder_fp32;
    } else {
      encoder_path = !encoder_int8.empty() ? encoder_int8 : encoder_fp32;
      decoder_path = !decoder_int8.empty() ? decoder_int8 : decoder_fp32;
    }

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
  // If we found a single-file model (model.int8.onnx / model.onnx) but no
  // encoder/decoder, this is a NeMo CTC model. Also detect from path keywords.
  if (model_type_ != STTModelType::NEMO_CTC) {
    bool has_encoder_decoder = !encoder_path.empty() && !decoder_path.empty();
    bool has_single_model = !nemo_ctc_model_path.empty();
    bool path_suggests_nemo =
        (model_path.find("nemo") != std::string::npos ||
         model_path.find("parakeet") != std::string::npos ||
         model_path.find("ctc") != std::string::npos);

    if ((!has_encoder_decoder && has_single_model) || path_suggests_nemo) {
      model_type_ = STTModelType::NEMO_CTC;
      RAC_LOG_INFO("Sherpa.STT", "Auto-detected NeMo CTC model type");
    }
  }

  // Branch based on model type
  bool is_nemo_ctc = (model_type_ == STTModelType::NEMO_CTC);

  if (is_nemo_ctc) {
    // NeMo CTC: single model file + tokens
    if (nemo_ctc_model_path.empty()) {
      RAC_LOG_ERROR("Sherpa.STT",
                    "NeMo CTC model file not found (model.int8.onnx or "
                    "model.onnx) in: %s",
                    model_path.c_str());
      return false;
    }
    RAC_LOG_INFO("Sherpa.STT", "NeMo CTC model: %s",
                 nemo_ctc_model_path.c_str());
    RAC_LOG_INFO("Sherpa.STT", "Tokens: %s", tokens_path.c_str());
  } else {
    // Whisper: encoder + decoder
    RAC_LOG_INFO("Sherpa.STT", "Encoder: %s", encoder_path.c_str());
    RAC_LOG_INFO("Sherpa.STT", "Decoder: %s", decoder_path.c_str());
    RAC_LOG_INFO("Sherpa.STT", "Tokens: %s", tokens_path.c_str());
  }
  RAC_LOG_INFO("Sherpa.STT", "Language: %s", language_.c_str());

  // Validate required files
  if (!is_nemo_ctc) {
    if (stat(encoder_path.c_str(), &path_stat) != 0) {
      RAC_LOG_ERROR("Sherpa.STT", "Encoder file not found: %s",
                    encoder_path.c_str());
      return false;
    }
    if (stat(decoder_path.c_str(), &path_stat) != 0) {
      RAC_LOG_ERROR("Sherpa.STT", "Decoder file not found: %s",
                    decoder_path.c_str());
      return false;
    }
  }
  if (stat(tokens_path.c_str(), &path_stat) != 0) {
    RAC_LOG_ERROR("Sherpa.STT", "Tokens file not found: %s",
                  tokens_path.c_str());
    return false;
  }

  // Keep path strings in members so config pointers stay valid for recognizer
  // lifetime
  encoder_path_ = encoder_path;
  decoder_path_ = decoder_path;
  tokens_path_ = tokens_path;
  nemo_ctc_model_path_ = nemo_ctc_model_path;

  if (!build_offline_recognizer_locked()) {
    return false;
  }

  RAC_LOG_INFO("Sherpa.STT", "STT model loaded successfully (%s)",
               is_nemo_ctc ? "NeMo CTC" : "Whisper");
  model_loaded_ = true;
  return true;

#else
  RAC_LOG_ERROR("Sherpa.STT",
                "Sherpa-ONNX not available - streaming STT disabled");
  return false;
#endif
}

bool SherpaSTT::build_offline_recognizer_locked() {
#if SHERPA_ONNX_AVAILABLE
  // Tear down any prior recognizer so we can rebuild with the current
  // `language_` setting. Used both by load_model() and by transcribe() when
  // the per-call language differs from what the recognizer was last built
  // with (engine-sherpa-001).
  if (sherpa_recognizer_) {
    SherpaOnnxDestroyOfflineRecognizer(sherpa_recognizer_);
    sherpa_recognizer_ = nullptr;
  }

  const bool is_nemo_ctc = (model_type_ == STTModelType::NEMO_CTC);

  // Initialize all config fields explicitly to avoid any uninitialized pointer
  // issues. The struct layout MUST match the prebuilt libsherpa-onnx-c-api.so
  // version (v1.13.2).
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
    recognizer_config.model_config.nemo_ctc.model =
        nemo_ctc_model_path_.c_str();
    recognizer_config.model_config.model_type = "nemo_ctc";

    RAC_LOG_INFO("Sherpa.STT", "Configuring NeMo CTC recognizer");
  } else {
    recognizer_config.model_config.whisper.encoder = encoder_path_.c_str();
    recognizer_config.model_config.whisper.decoder = decoder_path_.c_str();
    // Whisper auto-detects language when whisper.language == "". That's the
    // mode we use when the caller passes detect_language=true.
    recognizer_config.model_config.whisper.language = language_.c_str();
    recognizer_config.model_config.whisper.task = "transcribe";
    recognizer_config.model_config.model_type = "whisper";
  }

  recognizer_config.model_config.tokens = tokens_path_.c_str();
#if defined(__EMSCRIPTEN__)
  // ONNX Runtime tries to spawn an Eigen ThreadPool whenever
  // num_threads > 1. The vendored sherpa-onnx-c-api WASM build links a
  // single-threaded ONNX Runtime (the build script forces pthreads=OFF
  // because the prebuilt .a was not compiled with pthread support). In a
  // browser without a working pthread pool this aborts with
  // "PosixThread: pthread_create failed". Run inference single-threaded
  // on Web so the recognizer can come up without threading support.
  recognizer_config.model_config.num_threads = 1;
#else
  recognizer_config.model_config.num_threads = 2;
#endif
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

  // Any newer model slots (e.g. medasr, funasr_nano in 1.13.2) are already
  // zero-initialized by the memset above; explicit assignments here are
  // limited to the slots we actively populate.

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

  RAC_LOG_INFO("Sherpa.STT",
               "Creating SherpaOnnxOfflineRecognizer (%s, lang=\"%s\")...",
               is_nemo_ctc ? "NeMo CTC" : "Whisper", language_.c_str());

  try {
    sherpa_recognizer_ = SherpaOnnxCreateOfflineRecognizer(&recognizer_config);
  } catch (const std::exception &e) {
    RAC_LOG_ERROR("Sherpa.STT", "SherpaOnnxCreateOfflineRecognizer threw: %s",
                  e.what());
    return false;
  } catch (...) {
    RAC_LOG_ERROR("Sherpa.STT", "SherpaOnnxCreateOfflineRecognizer threw");
    return false;
  }

  if (!sherpa_recognizer_) {
    RAC_LOG_ERROR("Sherpa.STT", "Failed to create SherpaOnnxOfflineRecognizer");
    return false;
  }
  return true;
#else
  return false;
#endif
}

bool SherpaSTT::is_model_loaded() const { return model_loaded_; }

bool SherpaSTT::unload_model() {
  std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
  for (auto &pair : sherpa_streams_) {
    if (pair.second) {
      SherpaOnnxDestroyOfflineStream(pair.second);
    }
  }
  sherpa_streams_.clear();

  if (sherpa_recognizer_) {
    SherpaOnnxDestroyOfflineRecognizer(sherpa_recognizer_);
    sherpa_recognizer_ = nullptr;
  }

  // pass2-syn-066: also destroy any cached per-language recognizers parked
  // by transcribe() when callers alternated languages.
  for (auto &entry : recognizer_cache_) {
    if (entry.second) {
      SherpaOnnxDestroyOfflineRecognizer(entry.second);
    }
  }
  recognizer_cache_.clear();
  recognizer_lru_.clear();
#endif

  model_loaded_ = false;
  return true;
}

STTModelType SherpaSTT::get_model_type() const { return model_type_; }

STTResult SherpaSTT::transcribe(const STTRequest &request) {
  STTResult result;

#if SHERPA_ONNX_AVAILABLE
  // Lock for the lifetime of this call so we can safely (a) honor a per-call
  // language change by rebuilding the recognizer and (b) use the recognizer
  // without racing other callers who might rebuild/destroy it.
  std::lock_guard<std::mutex> lock(mutex_);

  if (!sherpa_recognizer_ || !model_loaded_) {
    RAC_LOG_ERROR("Sherpa.STT", "STT not ready for transcription");
    result.text = "[Error: STT model not loaded]";
    return result;
  }

  // engine-sherpa-001: the recognizer is built once with `language_` (default
  // "en"). Per-call STTRequest.language / detect_language was previously
  // ignored, so multilingual Whisper users got English-forced output. Honor
  // the request by rebuilding the Whisper recognizer with the new whisper.
  // language slot when it differs. detect_language=true maps to Whisper's
  // auto-detect mode (whisper.language == ""). Non-Whisper recognizers
  // (e.g. NeMo CTC) are single-language by construction, so an explicit
  // mismatched per-call language is reported as not-supported.
  std::string desired_language = language_;
  if (request.detect_language) {
    desired_language = "";
  } else if (!request.language.empty()) {
    desired_language = request.language;
  }

  if (desired_language != language_) {
    if (model_type_ != STTModelType::WHISPER) {
      RAC_LOG_WARNING("Sherpa.STT",
                      "Per-call language='%s' (detect=%d) not supported for "
                      "non-Whisper recognizer; rejecting request",
                      request.language.c_str(),
                      request.detect_language ? 1 : 0);
      result.text = "[Error: language not supported by recognizer]";
      return result;
    }

    // pass2-syn-066: cache recognizers by language with a small LRU so a
    // caller alternating between languages does not pay the multi-second
    // SherpaOnnxCreateOfflineRecognizer cost on every utterance.
    //
    // Strategy: park the current recognizer in the cache under its current
    // language key, then try to fetch the desired-language recognizer from
    // the cache. Only on a cache miss do we incur a fresh build.
    const std::string previous_language = language_;

    // Park the in-use recognizer in the cache under its current language so
    // subsequent calls to the same language hit the cache. Touch LRU.
    if (sherpa_recognizer_) {
      recognizer_cache_[previous_language] = sherpa_recognizer_;
      recognizer_lru_.remove(previous_language);
      recognizer_lru_.push_front(previous_language);
      sherpa_recognizer_ = nullptr;
    }

    // Cache hit? Reuse without rebuilding.
    auto hit = recognizer_cache_.find(desired_language);
    if (hit != recognizer_cache_.end()) {
      sherpa_recognizer_ = hit->second;
      recognizer_cache_.erase(hit);
      recognizer_lru_.remove(desired_language);
      language_ = desired_language;
      RAC_LOG_INFO("Sherpa.STT",
                   "Reusing cached Whisper recognizer for language=\"%s\"",
                   desired_language.c_str());
    } else {
      // Cache miss: build a fresh recognizer. build_offline_recognizer_locked
      // first destroys sherpa_recognizer_ (already null here, so it's a
      // no-op) and then constructs a new one using language_.
      language_ = desired_language;
      if (!build_offline_recognizer_locked()) {
        RAC_LOG_ERROR(
            "Sherpa.STT",
            "Failed to build Whisper recognizer for language=\"%s\"; "
            "restoring previous \"%s\" from cache",
            desired_language.c_str(), previous_language.c_str());
        // Recover the previous recognizer from the cache we just populated.
        auto prev_hit = recognizer_cache_.find(previous_language);
        if (prev_hit != recognizer_cache_.end()) {
          sherpa_recognizer_ = prev_hit->second;
          recognizer_cache_.erase(prev_hit);
          recognizer_lru_.remove(previous_language);
          language_ = previous_language;
          result.text = "[Error: language not supported by recognizer]";
          return result;
        }
        // Previous recognizer not in cache (initial build never ran or
        // already-evicted) — last-ditch rebuild for the previous language.
        language_ = previous_language;
        if (!build_offline_recognizer_locked()) {
          model_loaded_ = false;
          result.text = "[Error: recognizer rebuild failed]";
          return result;
        }
        result.text = "[Error: language not supported by recognizer]";
        return result;
      }
    }

    // Enforce LRU cap. recognizer_lru_ tracks recently-parked entries; evict
    // tail entries until the cache is within the cap. Note: the currently
    // active recognizer is NOT in the cache, so the cap bounds *idle*
    // recognizers. pass3-syn-132: peak transient resident count is
    // kRecognizerCacheCap + 2 — at this point we have (a) the freshly-built
    // active recognizer in `sherpa_recognizer_`, (b) up to kRecognizerCacheCap
    // legitimate idle entries in the cache, and (c) one stale entry that was
    // parked above but is about to be evicted in the loop below. The transient
    // (c) only exists between the park-step and this loop iteration; the
    // steady-state resident count after the loop is kRecognizerCacheCap + 1
    // (cap idle + 1 active).
    while (recognizer_cache_.size() > kRecognizerCacheCap) {
      if (recognizer_lru_.empty()) {
        break;
      }
      const std::string evict_key = recognizer_lru_.back();
      recognizer_lru_.pop_back();
      auto evict_it = recognizer_cache_.find(evict_key);
      if (evict_it != recognizer_cache_.end()) {
        if (evict_it->second) {
          SherpaOnnxDestroyOfflineRecognizer(evict_it->second);
        }
        recognizer_cache_.erase(evict_it);
        RAC_LOG_DEBUG("Sherpa.STT",
                      "Evicted cached recognizer for language=\"%s\" (cap=%zu)",
                      evict_key.c_str(), kRecognizerCacheCap);
      }
    }
  }

  RAC_LOG_INFO("Sherpa.STT", "Transcribing %zu samples at %d Hz (lang=\"%s\")",
               request.audio_samples.size(), request.sample_rate,
               language_.c_str());

  const SherpaOnnxOfflineStream *stream =
      SherpaOnnxCreateOfflineStream(sherpa_recognizer_);
  if (!stream) {
    RAC_LOG_ERROR("Sherpa.STT", "Failed to create offline stream");
    result.text = "[Error: Failed to create stream]";
    return result;
  }

  SherpaOnnxAcceptWaveformOffline(
      stream, request.sample_rate, request.audio_samples.data(),
      static_cast<int32_t>(request.audio_samples.size()));

  RAC_LOG_DEBUG("Sherpa.STT", "Decoding audio...");
  SherpaOnnxDecodeOfflineStream(sherpa_recognizer_, stream);

  const SherpaOnnxOfflineRecognizerResult *recognizer_result =
      SherpaOnnxGetOfflineStreamResult(stream);

  if (recognizer_result && recognizer_result->text) {
    result.text = recognizer_result->text;
    RAC_LOG_INFO("Sherpa.STT", "Transcription result: \"%s\"",
                 result.text.c_str());

    if (recognizer_result->lang) {
      result.detected_language = recognizer_result->lang;
    }

    SherpaOnnxDestroyOfflineRecognizerResult(recognizer_result);
  } else {
    result.text = "";
    RAC_LOG_DEBUG("Sherpa.STT",
                  "No transcription result (empty audio or silence)");
  }

  SherpaOnnxDestroyOfflineStream(stream);

  return result;

#else
  RAC_LOG_ERROR("Sherpa.STT", "Sherpa-ONNX not available");
  result.text = "[Error: Sherpa-ONNX not available]";
  return result;
#endif
}

bool SherpaSTT::supports_streaming() const {
#if SHERPA_ONNX_AVAILABLE
  return false;
#else
  return false;
#endif
}

std::string SherpaSTT::create_stream(const nlohmann::json &config) {
#if SHERPA_ONNX_AVAILABLE
  std::lock_guard<std::mutex> lock(mutex_);

  if (!sherpa_recognizer_) {
    RAC_LOG_ERROR("Sherpa.STT",
                  "Cannot create stream: recognizer not initialized");
    return "";
  }

  const SherpaOnnxOfflineStream *stream =
      SherpaOnnxCreateOfflineStream(sherpa_recognizer_);
  if (!stream) {
    RAC_LOG_ERROR("Sherpa.STT", "Failed to create offline stream");
    return "";
  }

  std::string stream_id = "stt_stream_" + std::to_string(++stream_counter_);
  sherpa_streams_[stream_id] = stream;

  RAC_LOG_DEBUG("Sherpa.STT", "Created stream: %s", stream_id.c_str());
  return stream_id;
#else
  return "";
#endif
}

bool SherpaSTT::feed_audio(const std::string &stream_id,
                           const std::vector<float> &samples, int sample_rate) {
#if SHERPA_ONNX_AVAILABLE
  std::lock_guard<std::mutex> lock(mutex_);

  auto it = sherpa_streams_.find(stream_id);
  if (it == sherpa_streams_.end() || !it->second) {
    RAC_LOG_ERROR("Sherpa.STT", "Stream not found: %s", stream_id.c_str());
    return false;
  }

  SherpaOnnxAcceptWaveformOffline(it->second, sample_rate, samples.data(),
                                  static_cast<int32_t>(samples.size()));

  return true;
#else
  return false;
#endif
}

bool SherpaSTT::is_stream_ready(const std::string &stream_id) {
#if SHERPA_ONNX_AVAILABLE
  std::lock_guard<std::mutex> lock(mutex_);
  auto it = sherpa_streams_.find(stream_id);
  return it != sherpa_streams_.end() && it->second != nullptr;
#else
  return false;
#endif
}

STTResult SherpaSTT::decode(const std::string &stream_id) {
  STTResult result;

#if SHERPA_ONNX_AVAILABLE
  std::lock_guard<std::mutex> lock(mutex_);

  auto it = sherpa_streams_.find(stream_id);
  if (it == sherpa_streams_.end() || !it->second) {
    RAC_LOG_ERROR("Sherpa.STT", "Stream not found for decode: %s",
                  stream_id.c_str());
    return result;
  }

  if (!sherpa_recognizer_) {
    RAC_LOG_ERROR("Sherpa.STT", "Recognizer not available");
    return result;
  }

  SherpaOnnxDecodeOfflineStream(sherpa_recognizer_, it->second);

  const SherpaOnnxOfflineRecognizerResult *recognizer_result =
      SherpaOnnxGetOfflineStreamResult(it->second);

  if (recognizer_result && recognizer_result->text) {
    result.text = recognizer_result->text;
    RAC_LOG_INFO("Sherpa.STT", "Decode result: \"%s\"", result.text.c_str());

    if (recognizer_result->lang) {
      result.detected_language = recognizer_result->lang;
    }

    SherpaOnnxDestroyOfflineRecognizerResult(recognizer_result);
  }
#endif

  return result;
}

bool SherpaSTT::is_endpoint(const std::string &stream_id) { return false; }

void SherpaSTT::input_finished(const std::string &stream_id) {}

void SherpaSTT::reset_stream(const std::string &stream_id) {
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

void SherpaSTT::destroy_stream(const std::string &stream_id) {
#if SHERPA_ONNX_AVAILABLE
  std::lock_guard<std::mutex> lock(mutex_);

  auto it = sherpa_streams_.find(stream_id);
  if (it != sherpa_streams_.end()) {
    if (it->second) {
      SherpaOnnxDestroyOfflineStream(it->second);
    }
    sherpa_streams_.erase(it);
    RAC_LOG_DEBUG("Sherpa.STT", "Destroyed stream: %s", stream_id.c_str());
  }
#endif
}

void SherpaSTT::cancel() { cancel_requested_ = true; }

std::vector<std::string> SherpaSTT::get_supported_languages() const {
  return {"en", "zh", "de", "es", "ru", "ko",  "fr", "ja", "pt", "tr", "pl",
          "ca", "nl", "ar", "sv", "it", "id",  "hi", "fi", "vi", "he", "uk",
          "el", "ms", "cs", "ro", "da", "hu",  "ta", "no", "th", "ur", "hr",
          "bg", "lt", "la", "mi", "ml", "cy",  "sk", "te", "fa", "lv", "bn",
          "sr", "az", "sl", "kn", "et", "mk",  "br", "eu", "is", "hy", "ne",
          "mn", "bs", "kk", "sq", "sw", "gl",  "mr", "pa", "si", "km", "sn",
          "yo", "so", "af", "oc", "ka", "be",  "tg", "sd", "gu", "am", "yi",
          "lo", "uz", "fo", "ht", "ps", "tk",  "nn", "mt", "sa", "lb", "my",
          "bo", "tl", "mg", "as", "tt", "haw", "ln", "ha", "ba", "jw", "su"};
}

// =============================================================================
// SherpaTTS Implementation
// =============================================================================

SherpaTTS::SherpaTTS(SherpaBackend *backend) : backend_(backend) {}

SherpaTTS::~SherpaTTS() {
  try {
    unload_model();
  } catch (...) {
  }
}

bool SherpaTTS::is_ready() const {
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
static void ensure_espeak_voice_files(const std::string &espeak_data_dir) {
  std::string lang_dir = espeak_data_dir + "/lang";
  std::string voices_dir = espeak_data_dir + "/voices";

  RAC_LOG_INFO("Sherpa.TTS", "[ensure_voices] lang_dir=%s, voices_dir=%s",
               lang_dir.c_str(), voices_dir.c_str());

  struct stat st;
  if (stat(lang_dir.c_str(), &st) != 0 || !S_ISDIR(st.st_mode)) {
    RAC_LOG_ERROR(
        "Sherpa.TTS",
        "[ensure_voices] lang/ directory NOT FOUND or not a dir: %s (errno=%d)",
        lang_dir.c_str(), errno);
    return;
  }

  if (stat(voices_dir.c_str(), &st) != 0) {
#ifdef _WIN32
    int mk = _mkdir(voices_dir.c_str());
#else
    int mk = mkdir(voices_dir.c_str(), 0755);
#endif
    RAC_LOG_INFO("Sherpa.TTS",
                 "[ensure_voices] Created voices/ dir: result=%d errno=%d", mk,
                 errno);
  } else {
    RAC_LOG_INFO("Sherpa.TTS", "[ensure_voices] voices/ dir already exists");
  }

  DIR *lang_root = opendir(lang_dir.c_str());
  if (!lang_root) {
    RAC_LOG_ERROR("Sherpa.TTS",
                  "[ensure_voices] Failed to open lang/ dir (errno=%d)", errno);
    return;
  }

  int copied = 0;
  int skipped = 0;
  int errors = 0;
  struct dirent *family_entry;
  while ((family_entry = readdir(lang_root)) != nullptr) {
    if (family_entry->d_name[0] == '.')
      continue;

    std::string family_path = lang_dir + "/" + family_entry->d_name;
    if (stat(family_path.c_str(), &st) != 0)
      continue;

    if (S_ISREG(st.st_mode)) {
      std::string basename = family_entry->d_name;
      std::string lowercase_name;
      for (char c : basename)
        lowercase_name += (char)tolower((unsigned char)c);

      std::string dest = voices_dir + "/" + lowercase_name;
      if (stat(dest.c_str(), &st) == 0) {
        skipped++;
        continue;
      }

      FILE *src_f = fopen(family_path.c_str(), "rb");
      FILE *dst_f = fopen(dest.c_str(), "wb");
      if (src_f && dst_f) {
        char buf[4096];
        size_t n;
        bool io_ok = true;
        while ((n = fread(buf, 1, sizeof(buf), src_f)) > 0) {
          if (fwrite(buf, 1, n, dst_f) != n) {
            io_ok = false;
            break;
          }
        }
        if (io_ok && ferror(src_f) == 0) {
          copied++;
          RAC_LOG_DEBUG("Sherpa.TTS", "[ensure_voices] Copied: %s -> %s",
                        family_path.c_str(), dest.c_str());
        } else {
          errors++;
          RAC_LOG_ERROR("Sherpa.TTS",
                        "[ensure_voices] I/O error copying %s -> %s (errno=%d)",
                        family_path.c_str(), dest.c_str(), errno);
        }
      } else {
        errors++;
        RAC_LOG_ERROR(
            "Sherpa.TTS",
            "[ensure_voices] FAILED to copy %s -> %s (src=%p dst=%p errno=%d)",
            family_path.c_str(), dest.c_str(), (void *)src_f, (void *)dst_f,
            errno);
      }
      if (src_f)
        fclose(src_f);
      if (dst_f)
        fclose(dst_f);
      continue;
    }

    if (!S_ISDIR(st.st_mode))
      continue;

    RAC_LOG_DEBUG("Sherpa.TTS", "[ensure_voices] Scanning family dir: %s",
                  family_entry->d_name);
    DIR *family_dir = opendir(family_path.c_str());
    if (!family_dir)
      continue;

    struct dirent *voice_entry;
    while ((voice_entry = readdir(family_dir)) != nullptr) {
      if (voice_entry->d_name[0] == '.')
        continue;

      std::string voice_path = family_path + "/" + voice_entry->d_name;
      if (stat(voice_path.c_str(), &st) != 0 || !S_ISREG(st.st_mode))
        continue;

      std::string basename = voice_entry->d_name;
      std::string lowercase_name;
      for (char c : basename)
        lowercase_name += (char)tolower((unsigned char)c);

      std::string dest = voices_dir + "/" + lowercase_name;
      if (stat(dest.c_str(), &st) == 0) {
        skipped++;
        continue;
      }

      FILE *src_f = fopen(voice_path.c_str(), "rb");
      FILE *dst_f = fopen(dest.c_str(), "wb");
      if (src_f && dst_f) {
        char buf[4096];
        size_t n;
        bool io_ok = true;
        while ((n = fread(buf, 1, sizeof(buf), src_f)) > 0) {
          if (fwrite(buf, 1, n, dst_f) != n) {
            io_ok = false;
            break;
          }
        }
        if (io_ok && ferror(src_f) == 0) {
          copied++;
          RAC_LOG_INFO("Sherpa.TTS", "[ensure_voices] Copied: %s -> voices/%s",
                       voice_entry->d_name, lowercase_name.c_str());
        } else {
          errors++;
          RAC_LOG_ERROR("Sherpa.TTS",
                        "[ensure_voices] I/O error: %s -> voices/%s (errno=%d)",
                        voice_entry->d_name, lowercase_name.c_str(), errno);
        }
      } else {
        errors++;
        RAC_LOG_ERROR(
            "Sherpa.TTS",
            "[ensure_voices] FAILED: %s -> voices/%s (src=%p dst=%p errno=%d)",
            voice_entry->d_name, lowercase_name.c_str(), (void *)src_f,
            (void *)dst_f, errno);
      }
      if (src_f)
        fclose(src_f);
      if (dst_f)
        fclose(dst_f);
    }
    closedir(family_dir);
  }
  closedir(lang_root);

  RAC_LOG_INFO("Sherpa.TTS",
               "[ensure_voices] Done: copied=%d skipped=%d errors=%d", copied,
               skipped, errors);

  // Dump voices/ directory contents for verification
  DIR *vdir = opendir(voices_dir.c_str());
  if (vdir) {
    RAC_LOG_INFO("Sherpa.TTS",
                 "[ensure_voices] === voices/ directory contents ===");
    struct dirent *ve;
    int count = 0;
    while ((ve = readdir(vdir)) != nullptr) {
      if (ve->d_name[0] == '.')
        continue;
      std::string vpath = voices_dir + "/" + ve->d_name;
      struct stat vs;
      stat(vpath.c_str(), &vs);
      RAC_LOG_INFO("Sherpa.TTS", "[ensure_voices]   [%s] %s (%lld bytes)",
                   S_ISDIR(vs.st_mode) ? "DIR" : "FILE", ve->d_name,
                   (long long)vs.st_size);
      count++;
    }
    closedir(vdir);
    RAC_LOG_INFO("Sherpa.TTS",
                 "[ensure_voices] === Total: %d entries ===", count);
  }
}

bool SherpaTTS::load_model(const std::string &model_path,
                           TTSModelType model_type,
                           const nlohmann::json &config) {
  std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
  if (sherpa_tts_) {
    SherpaOnnxDestroyOfflineTts(sherpa_tts_);
    sherpa_tts_ = nullptr;
  }

  model_type_ = model_type;
  model_dir_ = model_path;

  RAC_LOG_INFO("Sherpa.TTS", "[BUILD_V5] Loading model from: %s",
               model_path.c_str());

  std::string model_onnx_path;
  std::string tokens_path;
  std::string lexicon_path;
  // sherpa-onnx data_dir: the espeak-ng-data directory path itself.
  // espeak's check_data_path tries path+"/espeak-ng-data" first, then path
  // itself. Passing the espeak-ng-data dir directly works via the fallback
  // branch.
  std::string espeak_data_dir;

  struct stat path_stat;
  if (stat(model_path.c_str(), &path_stat) != 0) {
    RAC_LOG_ERROR("Sherpa.TTS", "Model path does not exist: %s",
                  model_path.c_str());
    return false;
  }

  // Diagnostic: list top-level directory contents
  if (S_ISDIR(path_stat.st_mode)) {
    DIR *diag_dir = opendir(model_path.c_str());
    if (diag_dir) {
      RAC_LOG_INFO("Sherpa.TTS",
                   "=== Model directory contents: %s ===", model_path.c_str());
      struct dirent *diag_entry;
      while ((diag_entry = readdir(diag_dir)) != nullptr) {
        if (diag_entry->d_name[0] == '.')
          continue;
        RAC_LOG_INFO("Sherpa.TTS", "  [%s] %s",
                     diag_entry->d_type == DT_DIR ? "DIR" : "FILE",
                     diag_entry->d_name);
      }
      closedir(diag_dir);
      RAC_LOG_INFO("Sherpa.TTS", "=== End directory listing ===");
    }
  }

  if (S_ISDIR(path_stat.st_mode)) {
    // Prefer the quantized int8 model over the full-precision one when both
    // exist.
    const std::string int8_candidate = model_path + "/model.int8.onnx";
    if (stat(int8_candidate.c_str(), &path_stat) == 0) {
      model_onnx_path = int8_candidate;
      RAC_LOG_DEBUG("Sherpa.TTS", "Using int8 model: %s",
                    model_onnx_path.c_str());
    } else {
      model_onnx_path = model_path + "/model.onnx";
    }
    tokens_path = model_path + "/tokens.txt";
    lexicon_path = model_path + "/lexicon.txt";

    if (stat(model_onnx_path.c_str(), &path_stat) != 0) {
      DIR *dir = opendir(model_path.c_str());
      if (dir) {
        struct dirent *entry;
        while ((entry = readdir(dir)) != nullptr) {
          std::string filename = entry->d_name;
          if (filename.size() > 5 &&
              filename.substr(filename.size() - 5) == ".onnx") {
            model_onnx_path = model_path + "/" + filename;
            RAC_LOG_DEBUG("Sherpa.TTS", "Found model file: %s",
                          model_onnx_path.c_str());
            break;
          }
        }
        closedir(dir);
      }
    }

    // Look for espeak-ng-data directory
    std::string candidate = model_path + "/espeak-ng-data";
    if (stat(candidate.c_str(), &path_stat) == 0 &&
        S_ISDIR(path_stat.st_mode)) {
      espeak_data_dir = candidate;
    } else {
      candidate = model_path + "/data/espeak-ng-data";
      if (stat(candidate.c_str(), &path_stat) == 0 &&
          S_ISDIR(path_stat.st_mode)) {
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
      if (stat(candidate.c_str(), &path_stat) == 0 &&
          S_ISDIR(path_stat.st_mode)) {
        espeak_data_dir = candidate;
      }
    }
  }

  RAC_LOG_INFO("Sherpa.TTS", "Model ONNX: %s", model_onnx_path.c_str());
  RAC_LOG_INFO("Sherpa.TTS", "Tokens: %s", tokens_path.c_str());
  RAC_LOG_INFO("Sherpa.TTS", "espeak_data_dir: %s", espeak_data_dir.c_str());

  if (stat(model_onnx_path.c_str(), &path_stat) != 0) {
    RAC_LOG_ERROR("Sherpa.TTS", "Model ONNX file not found: %s",
                  model_onnx_path.c_str());
    return false;
  }

  if (stat(tokens_path.c_str(), &path_stat) != 0) {
    RAC_LOG_ERROR("Sherpa.TTS", "Tokens file not found: %s",
                  tokens_path.c_str());
    return false;
  }

  if (!espeak_data_dir.empty()) {
    // Verify key files exist
    std::string lang_gmw_dir = espeak_data_dir + "/lang/gmw";
    std::string en_us_voice = lang_gmw_dir + "/en-US";
    RAC_LOG_INFO("Sherpa.TTS", "Checking lang/gmw/en-US: %s",
                 stat(en_us_voice.c_str(), &path_stat) == 0 ? "EXISTS"
                                                            : "MISSING");

    // Ensure voice files are accessible directly from voices/
    ensure_espeak_voice_files(espeak_data_dir);

    // Verify voices/en-us now exists
    std::string voices_en_us = espeak_data_dir + "/voices/en-us";
    RAC_LOG_INFO("Sherpa.TTS", "voices/en-us after ensure: %s",
                 stat(voices_en_us.c_str(), &path_stat) == 0 ? "EXISTS"
                                                             : "MISSING");
  }

  SherpaOnnxOfflineTtsConfig tts_config;
  memset(&tts_config, 0, sizeof(tts_config));

  tts_config.model.vits.model = model_onnx_path.c_str();
  tts_config.model.vits.tokens = tokens_path.c_str();

  if (stat(lexicon_path.c_str(), &path_stat) == 0 &&
      S_ISREG(path_stat.st_mode)) {
    tts_config.model.vits.lexicon = lexicon_path.c_str();
    RAC_LOG_DEBUG("Sherpa.TTS", "Using lexicon file: %s", lexicon_path.c_str());
  }

  espeak_data_dir_ = espeak_data_dir;
  if (!espeak_data_dir.empty()) {
    tts_config.model.vits.data_dir = espeak_data_dir_.c_str();
    RAC_LOG_INFO("Sherpa.TTS", "Using espeak data_dir: %s",
                 espeak_data_dir_.c_str());
  } else {
    RAC_LOG_WARNING(
        "Sherpa.TTS",
        "espeak-ng-data NOT FOUND in model dir — Piper TTS will fail");
  }

  tts_config.model.vits.noise_scale = 0.667f;
  tts_config.model.vits.noise_scale_w = 0.8f;
  tts_config.model.vits.length_scale = 1.0f;

  tts_config.model.provider = "cpu";
#if defined(__EMSCRIPTEN__)
  // Match STT: single-threaded ORT on WASM (no pthread pool in racommons-onnx-sherpa).
  tts_config.model.num_threads = 1;
#else
  tts_config.model.num_threads = 2;
#endif
  tts_config.model.debug = 1;

  RAC_LOG_INFO("Sherpa.TTS", "Creating SherpaOnnxOfflineTts (VITS/Piper)...");

  const SherpaOnnxOfflineTts *new_tts = nullptr;
  try {
    new_tts = SherpaOnnxCreateOfflineTts(&tts_config);
  } catch (const std::exception &e) {
    RAC_LOG_ERROR("Sherpa.TTS", "Exception during TTS creation: %s", e.what());
    return false;
  } catch (...) {
    RAC_LOG_ERROR("Sherpa.TTS", "Unknown exception during TTS creation");
    return false;
  }

  if (!new_tts) {
    RAC_LOG_ERROR("Sherpa.TTS", "Failed to create SherpaOnnxOfflineTts");
    return false;
  }

  // Workaround for sherpa-onnx std::once_flag issue: espeak_Initialize is
  // only called internally on the very first SherpaOnnxCreateOfflineTts call.
  // When switching TTS models with different data_dir, destroy and recreate
  // the instance so the config (including data_dir) is applied correctly.
  if (sherpa_tts_ && sherpa_tts_ != new_tts) {
    SherpaOnnxDestroyOfflineTts(sherpa_tts_);
    sherpa_tts_ = nullptr;
  }
  sherpa_tts_ = new_tts;

  sample_rate_ = SherpaOnnxOfflineTtsSampleRate(sherpa_tts_);
  int num_speakers = SherpaOnnxOfflineTtsNumSpeakers(sherpa_tts_);

  RAC_LOG_INFO("Sherpa.TTS", "TTS model loaded successfully");
  RAC_LOG_INFO("Sherpa.TTS", "Sample rate: %d, speakers: %d", sample_rate_,
               num_speakers);

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
  RAC_LOG_ERROR("Sherpa.TTS", "Sherpa-ONNX not available - TTS disabled");
  return false;
#endif
}

bool SherpaTTS::is_model_loaded() const { return model_loaded_; }

bool SherpaTTS::unload_model() {
  std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
  model_loaded_ = false;

  // pass3-syn-130: previously a warning logged when active_synthesis_count_ > 0
  // here, but pass2-syn-065 made synthesize() hold mutex_ for its entire
  // duration and unload_model() takes the same mutex on entry — so no
  // synthesize() can be in flight when we reach this point. The counter and
  // its SynthesisGuard RAII helper inside synthesize() are now dead and the
  // warning was unreachable; both are removed.
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

TTSModelType SherpaTTS::get_model_type() const { return model_type_; }

TTSResult SherpaTTS::synthesize(const TTSRequest &request) {
  TTSResult result;

#if SHERPA_ONNX_AVAILABLE
  // pass2-syn-065: serialize synthesize() under mutex_ across the entire
  // call. Previously the lock was scoped only around the sherpa_tts_ read,
  // so overlapping synthesize() invocations could clobber each other's
  // cancel signals — call #2's `cancel_requested_.store(false, ...)` at
  // entry would erase a cancel intended for an in-flight call #1, and #1
  // would then emit audio the SDK had explicitly stopped. Holding mutex_
  // for the whole call makes per-voice synthesize serial; cancel() and the
  // post-generate drop still work because cancel() only writes the atomic
  // flag (no lock) and we read the flag after the blocking generator
  // returns. NOTE: synthesize() on a single SherpaTTS instance is no
  // longer parallelism-safe — concurrent callers queue.
  std::lock_guard<std::mutex> lock(mutex_);

  // pass3-syn-130: the former SynthesisGuard RAII helper (and the matching
  // active_synthesis_count_ atomic + warning in unload_model()) used to track
  // concurrent synthesize() callers. After pass2-syn-065 made synthesize()
  // hold mutex_ across its full duration, at most one synthesize() can be
  // running at a time and unload_model() must wait for it to release the
  // mutex before tearing the model down — so the counter could only ever be
  // 0 when observed under the same mutex. Both the guard and the warning are
  // dead and have been removed.

  // hotspot-engine-sherpa-004: clear any stale cancel signal from a prior
  // synthesis so cancel() observed during THIS call's blocking
  // SherpaOnnxOfflineTtsGenerate is what we react to. The Sherpa-ONNX C TTS
  // API has no cancellation hook, so the flag is consulted post-generate to
  // suppress the result instead of preempting compute. With the mutex held
  // across the whole call, this reset cannot race a concurrent synthesize().
  cancel_requested_.store(false, std::memory_order_release);

  if (!sherpa_tts_ || !model_loaded_) {
    RAC_LOG_ERROR("Sherpa.TTS", "TTS not ready for synthesis");
    return result;
  }

  const SherpaOnnxOfflineTts *tts_ptr = sherpa_tts_;

  RAC_LOG_INFO("Sherpa.TTS", "Synthesizing: \"%s...\"",
               request.text.substr(0, 50).c_str());

  int speaker_id = 0;
  if (!request.voice_id.empty()) {
    try {
      speaker_id = std::stoi(request.voice_id);
    } catch (...) {
    }
  }

  float speed = request.speed_rate > 0 ? request.speed_rate : 1.0f;

  RAC_LOG_DEBUG("Sherpa.TTS", "Speaker ID: %d, Speed: %.2f", speaker_id, speed);

  const SherpaOnnxGeneratedAudio *audio = nullptr;
  try {
    audio = SherpaOnnxOfflineTtsGenerate(tts_ptr, request.text.c_str(),
                                         speaker_id, speed);
  } catch (const std::exception &e) {
    RAC_LOG_ERROR("Sherpa.TTS", "Exception during TTS synthesis: %s", e.what());
    RAC_LOG_ERROR("Sherpa.TTS", "Model dir: %s, espeak data was: %s",
                  model_dir_.c_str(),
                  espeak_data_dir_.empty() ? "<EMPTY/NOT SET>"
                                           : espeak_data_dir_.c_str());
    return result;
  } catch (...) {
    RAC_LOG_ERROR("Sherpa.TTS", "Unknown exception during TTS synthesis");
    return result;
  }

  if (!audio || audio->n <= 0) {
    RAC_LOG_ERROR(
        "Sherpa.TTS",
        "Synthesis returned null/empty audio. Model dir: %s, espeak data: %s",
        model_dir_.c_str(),
        espeak_data_dir_.empty() ? "<EMPTY/NOT SET>"
                                 : espeak_data_dir_.c_str());
    return result;
  }

  // hotspot-engine-sherpa-004: drop the post-stop result if cancel() fired
  // while SherpaOnnxOfflineTtsGenerate was running. We can't preempt the
  // blocking Piper generator, but we MUST NOT surface its chunk/completion
  // through the stream wrapper after the SDK requested a stop — empty
  // audio_samples here makes the rac_tts_sherpa_synthesize wrapper return
  // RAC_ERROR_INFERENCE_FAILED so the lifecycle stream/one-shot path does
  // not deliver phantom audio.
  if (cancel_requested_.load(std::memory_order_acquire)) {
    int dropped_samples = audio->n;
    SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);
    RAC_LOG_WARNING("Sherpa.TTS",
                    "Dropping %d-sample synthesis result; cancel was "
                    "requested during blocking generation (Sherpa-ONNX TTS "
                    "compute cannot be preempted)",
                    dropped_samples);
    return result;
  }

  RAC_LOG_INFO("Sherpa.TTS", "Generated %d samples at %d Hz", audio->n,
               audio->sample_rate);

  result.audio_samples.assign(audio->samples, audio->samples + audio->n);
  result.sample_rate = audio->sample_rate;
  result.duration_ms = (static_cast<double>(audio->n) /
                        static_cast<double>(audio->sample_rate)) *
                       1000.0;

  SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio);

  RAC_LOG_INFO("Sherpa.TTS", "Synthesis complete. Duration: %.2fs",
               (result.duration_ms / 1000.0));

#else
  RAC_LOG_ERROR("Sherpa.TTS", "Sherpa-ONNX not available");
#endif

  return result;
}

bool SherpaTTS::supports_streaming() const { return false; }

void SherpaTTS::cancel() { cancel_requested_ = true; }

std::vector<VoiceInfo> SherpaTTS::get_voices() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return voices_;
}

std::string SherpaTTS::get_default_voice(const std::string &language) const {
  return "0";
}

// =============================================================================
// SherpaVAD Implementation - Silero VAD via Sherpa-ONNX
// =============================================================================

SherpaVAD::SherpaVAD(SherpaBackend *backend) : backend_(backend) {}

SherpaVAD::~SherpaVAD() { unload_model(); }

#if SHERPA_ONNX_AVAILABLE
// VADConfig.padding_ms default mirrors the struct definition in
// sherpa_backend.h (currently 30). Used to detect non-default values that the
// caller may have set expecting them to take effect — they won't, since the
// Sherpa SilerVad ABI has no equivalent slot (pass3-syn-131).
static constexpr int kSherpaVadDefaultPaddingMs = 30;

void SherpaVAD::fill_sherpa_vad_config_locked(
    SherpaOnnxVadModelConfig &out) const {
  // Translate VADConfig (ms-based, schema-aligned with Swift/Kotlin/Dart) into
  // the Sherpa-ONNX SilerVadModelConfig (seconds / samples). Single source of
  // truth used by both load_model() and configure_vad() so non-threshold
  // fields are no longer silently dropped on the rebuild path
  // (pass2-syn-064).
  //
  // pass3-syn-131: VADConfig.padding_ms (used by other backends to extend
  // detected speech segments) has no equivalent slot in
  // SherpaOnnxSileroVadModelConfig — Sherpa's SilerVad C ABI exposes only
  // threshold / min_silence_duration / min_speech_duration / window_size /
  // max_speech_duration. We therefore intentionally do NOT thread padding_ms
  // through to the detector; configure_vad() emits a one-time warning if a
  // non-default value is observed so callers can detect the silent drop.
  memset(&out, 0, sizeof(out));

  out.silero_vad.model = model_path_.c_str();
  out.silero_vad.threshold = config_.threshold;
  // VADConfig durations are in milliseconds; SilerVAD expects seconds.
  out.silero_vad.min_silence_duration =
      static_cast<float>(config_.min_silence_duration_ms) / 1000.0f;
  out.silero_vad.min_speech_duration =
      static_cast<float>(config_.min_speech_duration_ms) / 1000.0f;
  // max_speech_duration is not exposed via VADConfig; keep the prior default.
  out.silero_vad.max_speech_duration = 15.0f;
  // SilerVAD's window_size is in samples. Derive it from window_size_ms at
  // the configured sample rate so a caller who passes the Silero-native
  // window (e.g. 32 ms @ 16 kHz) gets the canonical 512-sample window.
  const int derived_window =
      (config_.window_size_ms * config_.sample_rate) / 1000;
  out.silero_vad.window_size = derived_window > 0 ? derived_window : 512;
  out.sample_rate = config_.sample_rate > 0 ? config_.sample_rate : 16000;
  out.num_threads = 1;
  out.debug = 0;
  out.provider = "cpu";
}
#endif

bool SherpaVAD::is_ready() const { return model_loaded_; }

bool SherpaVAD::is_speech_active() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return last_is_speech_;
}

bool SherpaVAD::load_model(const std::string &model_path,
                           VADModelType model_type,
                           const nlohmann::json &config) {
  std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
  // Destroy previous instance if any
  if (sherpa_vad_) {
    SherpaOnnxDestroyVoiceActivityDetector(sherpa_vad_);
    sherpa_vad_ = nullptr;
  }

  // Resolve model_path: if it's a directory, find the .onnx file inside
  model_path_ = model_path;
  struct stat path_stat;
  if (stat(model_path.c_str(), &path_stat) == 0 && S_ISDIR(path_stat.st_mode)) {
    // Collect every `.onnx` filename and sort lexicographically so the
    // choice is deterministic across runs (readdir() order is
    // filesystem-dependent and not stable).
    std::vector<std::string> candidates;
    DIR *dir = opendir(model_path.c_str());
    if (dir) {
      struct dirent *entry;
      while ((entry = readdir(dir)) != nullptr) {
        std::string filename = entry->d_name;
        if (filename.size() > 5 &&
            filename.substr(filename.size() - 5) == ".onnx") {
          candidates.push_back(std::move(filename));
        }
      }
      closedir(dir);
    }
    if (!candidates.empty()) {
      std::sort(candidates.begin(), candidates.end());
      model_path_ = model_path + "/" + candidates.front();
      RAC_LOG_DEBUG("Sherpa.VAD", "Found VAD model file: %s (%zu candidate%s)",
                    model_path_.c_str(), candidates.size(),
                    candidates.size() == 1 ? "" : "s");
    } else {
      RAC_LOG_ERROR("Sherpa.VAD", "No .onnx file found in directory: %s",
                    model_path.c_str());
      return false;
    }
  }

  // Hydrate `config_` from the JSON config first so the helper sees every
  // VADConfig field. Defaults match the struct definition in
  // sherpa_backend.h (VADConfig).
  if (config.contains("energy_threshold")) {
    config_.threshold = config["energy_threshold"].get<float>();
  }
  if (config.contains("min_speech_duration_ms")) {
    config_.min_speech_duration_ms =
        config["min_speech_duration_ms"].get<int>();
  }
  if (config.contains("min_silence_duration_ms")) {
    config_.min_silence_duration_ms =
        config["min_silence_duration_ms"].get<int>();
  }
  if (config.contains("window_size_ms")) {
    config_.window_size_ms = config["window_size_ms"].get<int>();
  }
  if (config.contains("sample_rate")) {
    config_.sample_rate = config["sample_rate"].get<int>();
  }

  SherpaOnnxVadModelConfig vad_config;
  fill_sherpa_vad_config_locked(vad_config);

  try {
    sherpa_vad_ = SherpaOnnxCreateVoiceActivityDetector(&vad_config, 30.0f);
  } catch (const std::exception &e) {
    RAC_LOG_ERROR("Sherpa.VAD", "SherpaOnnxCreateVoiceActivityDetector threw: %s",
                  e.what());
    return false;
  } catch (...) {
    RAC_LOG_ERROR("Sherpa.VAD", "SherpaOnnxCreateVoiceActivityDetector threw");
    return false;
  }
  if (!sherpa_vad_) {
    RAC_LOG_ERROR("Sherpa.VAD", "Failed to create Silero VAD detector from: %s",
                  model_path.c_str());
    return false;
  }

  RAC_LOG_INFO("Sherpa.VAD", "Silero VAD loaded: %s (threshold=%.2f)",
               model_path.c_str(), vad_config.silero_vad.threshold);
  model_loaded_ = true;
  return true;
#else
  model_loaded_ = true;
  return true;
#endif
}

bool SherpaVAD::is_model_loaded() const { return model_loaded_; }

bool SherpaVAD::unload_model() {
  std::lock_guard<std::mutex> lock(mutex_);

#if SHERPA_ONNX_AVAILABLE
  if (sherpa_vad_) {
    SherpaOnnxDestroyVoiceActivityDetector(sherpa_vad_);
    sherpa_vad_ = nullptr;
  }
#endif

  pending_samples_.clear();
  last_is_speech_ = false;
  model_loaded_ = false;
  return true;
}

bool SherpaVAD::configure_vad(const VADConfig &config) {
  std::lock_guard<std::mutex> lock(mutex_);

  const VADConfig old_config = config_;
  config_ = config;

#if SHERPA_ONNX_AVAILABLE
  // pass3-syn-131: Sherpa SilerVad has no padding equivalent. Warn (once per
  // change) when the caller passes a non-default padding_ms so the silent drop
  // is observable in logs. Intentionally NOT failing the call: this matches
  // the other VAD backends' best-effort posture and keeps configure_vad a
  // total function. padding_ms is also deliberately excluded from
  // detector_changed below since a rebuild can't apply a value Sherpa won't
  // accept.
  if (config_.padding_ms != kSherpaVadDefaultPaddingMs &&
      config_.padding_ms != old_config.padding_ms) {
    RAC_LOG_WARNING(
        "Sherpa.VAD",
        "configure_vad: VADConfig.padding_ms=%d has no equivalent in "
        "Sherpa-ONNX SilerVad and will be ignored (default=%d)",
        config_.padding_ms, kSherpaVadDefaultPaddingMs);
  }

  // Sherpa-ONNX's SilerVAD captures every parameter at detector construction
  // and exposes no setters, so a configure_vad() that only mutates `config_`
  // round-trips through the service layer as a successful no-op while the
  // model-based VAD decision still uses the original parameters (see
  // engine-sherpa-002). Rebuild the live detector whenever any field that
  // affects detection actually changes so the new values affect subsequent
  // process() calls. pass2-syn-064: previously only `threshold` was
  // considered, and the rebuild path hardcoded every other field — now the
  // full VADConfig snapshot is threaded through fill_sherpa_vad_config_locked.
  // padding_ms is omitted by design (pass3-syn-131); see helper comment.
  const bool detector_changed =
      old_config.threshold != config_.threshold ||
      old_config.min_speech_duration_ms != config_.min_speech_duration_ms ||
      old_config.min_silence_duration_ms != config_.min_silence_duration_ms ||
      old_config.window_size_ms != config_.window_size_ms ||
      old_config.sample_rate != config_.sample_rate;

  if (sherpa_vad_ != nullptr && !model_path_.empty() && detector_changed) {
    SherpaOnnxVadModelConfig vad_config;
    fill_sherpa_vad_config_locked(vad_config);

    const SherpaOnnxVoiceActivityDetector *new_vad = nullptr;
    try {
      new_vad = SherpaOnnxCreateVoiceActivityDetector(&vad_config, 30.0f);
    } catch (const std::exception &e) {
      RAC_LOG_ERROR("Sherpa.VAD",
                    "configure_vad: failed to recreate VAD detector with "
                    "threshold=%.2f: %s",
                    config_.threshold, e.what());
      config_ = old_config;
      return false;
    } catch (...) {
      RAC_LOG_ERROR("Sherpa.VAD",
                    "configure_vad: failed to recreate VAD detector with "
                    "threshold=%.2f",
                    config_.threshold);
      config_ = old_config;
      return false;
    }
    if (!new_vad) {
      RAC_LOG_ERROR("Sherpa.VAD",
                    "configure_vad: SherpaOnnxCreateVoiceActivityDetector "
                    "returned null for threshold=%.2f",
                    config_.threshold);
      config_ = old_config;
      return false;
    }

    SherpaOnnxDestroyVoiceActivityDetector(sherpa_vad_);
    sherpa_vad_ = new_vad;
    pending_samples_.clear();
    last_is_speech_ = false;
    RAC_LOG_INFO("Sherpa.VAD",
                 "VAD detector recreated: threshold=%.2f (was %.2f), "
                 "min_speech_ms=%d (was %d), min_silence_ms=%d (was %d), "
                 "window_ms=%d (was %d), sample_rate=%d (was %d)",
                 config_.threshold, old_config.threshold,
                 config_.min_speech_duration_ms,
                 old_config.min_speech_duration_ms,
                 config_.min_silence_duration_ms,
                 old_config.min_silence_duration_ms, config_.window_size_ms,
                 old_config.window_size_ms, config_.sample_rate,
                 old_config.sample_rate);
  }
#endif

  return true;
}

VADResult SherpaVAD::process(const std::vector<float> &audio_samples,
                             int sample_rate) {
  std::lock_guard<std::mutex> lock(mutex_);
  VADResult result;

#if SHERPA_ONNX_AVAILABLE
  if (!sherpa_vad_ || audio_samples.empty()) {
    return result;
  }

  static constexpr int32_t SILERO_WINDOW_SIZE = 512;

  // Append incoming audio to the pending buffer.
  // Audio capture may deliver chunks smaller than SILERO_WINDOW_SIZE (e.g. 256
  // samples), but Silero VAD requires exactly 512 samples per call.
  pending_samples_.insert(pending_samples_.end(), audio_samples.begin(),
                          audio_samples.end());

  // Feed complete SILERO_WINDOW_SIZE chunks to Silero VAD.
  // Use offset tracking instead of repeated front-erase (O(n) per erase).
  size_t consumed = 0;
  while (consumed + SILERO_WINDOW_SIZE <= pending_samples_.size()) {
    SherpaOnnxVoiceActivityDetectorAcceptWaveform(
        sherpa_vad_, pending_samples_.data() + consumed, SILERO_WINDOW_SIZE);
    consumed += SILERO_WINDOW_SIZE;
  }
  if (consumed > 0) {
    pending_samples_.erase(pending_samples_.begin(),
                           pending_samples_.begin() +
                               static_cast<ptrdiff_t>(consumed));
  }

  // Check if speech is currently detected in the latest frame
  result.is_speech = SherpaOnnxVoiceActivityDetectorDetected(sherpa_vad_) != 0;
  result.probability = result.is_speech ? 1.0f : 0.0f;
  // Cache for is_speech_active() so lifecycle/state queries reflect the
  // detector's actual frame state, not is_ready() (model-loaded flag).
  last_is_speech_ = result.is_speech;

  // Drain any completed speech segments (keeps internal queue from growing)
  while (SherpaOnnxVoiceActivityDetectorEmpty(sherpa_vad_) == 0) {
    const SherpaOnnxSpeechSegment *seg =
        SherpaOnnxVoiceActivityDetectorFront(sherpa_vad_);
    if (seg) {
      SherpaOnnxDestroySpeechSegment(seg);
    }
    SherpaOnnxVoiceActivityDetectorPop(sherpa_vad_);
  }
#endif

  return result;
}

std::vector<SpeechSegment>
SherpaVAD::detect_segments(const std::vector<float> &audio_samples,
                           int sample_rate) {
  return {};
}

std::string SherpaVAD::create_stream(const VADConfig &config) { return ""; }

VADResult SherpaVAD::feed_audio(const std::string &stream_id,
                                const std::vector<float> &samples,
                                int sample_rate) {
  return {};
}

void SherpaVAD::destroy_stream(const std::string &stream_id) {}

void SherpaVAD::reset() {
  std::lock_guard<std::mutex> lock(mutex_);
#if SHERPA_ONNX_AVAILABLE
  if (sherpa_vad_) {
    SherpaOnnxVoiceActivityDetectorReset(sherpa_vad_);
  }
#endif
  pending_samples_.clear();
  last_is_speech_ = false;
}

VADConfig SherpaVAD::get_vad_config() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return config_;
}

} // namespace runanywhere
