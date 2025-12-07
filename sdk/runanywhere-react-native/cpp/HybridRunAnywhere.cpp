/**
 * HybridRunAnywhere.cpp
 *
 * Nitrogen HybridObject implementation for RunAnywhere SDK.
 * Calls runanywhere-core C API for all AI operations.
 */

#include "HybridRunAnywhere.hpp"

#include <sstream>
#include <cstring>
#include <algorithm>
#include <cctype>
#include <chrono>
#include <sys/stat.h>
#include <dirent.h>
#include <vector>

// iOS AudioDecoder functions (defined in AudioDecoder.m)
#if defined(__APPLE__)
extern "C" {
  int ra_decode_audio_file(const char* filePath, float** samples, size_t* numSamples, int* sampleRate);
  void ra_free_audio_samples(float* samples);
}
#endif

#if defined(ANDROID) || defined(__ANDROID__)
#include <fstream>
#include <cstdint>

namespace {
// Simple WAV file reader for Android
struct WavHeader {
  char riff[4];           // "RIFF"
  uint32_t fileSize;      // File size - 8
  char wave[4];           // "WAVE"
  char fmt[4];            // "fmt "
  uint32_t fmtSize;       // Format chunk size
  uint16_t audioFormat;   // Audio format (1 = PCM)
  uint16_t numChannels;   // Number of channels
  uint32_t sampleRate;    // Sample rate
  uint32_t byteRate;      // Bytes per second
  uint16_t blockAlign;    // Bytes per sample * channels
  uint16_t bitsPerSample; // Bits per sample
};

bool readWavFile(const char* filePath, float** samples, size_t* numSamples, int* sampleRate) {
  std::ifstream file(filePath, std::ios::binary);
  if (!file.is_open()) {
    printf("[WAV Reader] Failed to open file: %s\n", filePath);
    return false;
  }

  // Read header
  WavHeader header;
  file.read(reinterpret_cast<char*>(&header), sizeof(WavHeader));
  
  // Verify RIFF/WAVE format
  if (strncmp(header.riff, "RIFF", 4) != 0 || strncmp(header.wave, "WAVE", 4) != 0) {
    printf("[WAV Reader] Not a valid WAV file\n");
    return false;
  }
  
  // Skip extra format bytes if present
  if (header.fmtSize > 16) {
    file.seekg(header.fmtSize - 16, std::ios::cur);
  }
  
  // Find data chunk
  char chunkId[4];
  uint32_t chunkSize;
  while (file.read(chunkId, 4) && file.read(reinterpret_cast<char*>(&chunkSize), 4)) {
    if (strncmp(chunkId, "data", 4) == 0) {
      break;
    }
    file.seekg(chunkSize, std::ios::cur);
  }
  
  if (strncmp(chunkId, "data", 4) != 0) {
    printf("[WAV Reader] No data chunk found\n");
    return false;
  }
  
  // Calculate number of samples
  int bytesPerSample = header.bitsPerSample / 8;
  size_t totalSamples = chunkSize / bytesPerSample / header.numChannels;
  
  // Allocate output buffer
  *samples = new float[totalSamples];
  *numSamples = totalSamples;
  *sampleRate = header.sampleRate;
  
  // Read and convert samples
  if (header.bitsPerSample == 16) {
    std::vector<int16_t> buffer(chunkSize / 2);
    file.read(reinterpret_cast<char*>(buffer.data()), chunkSize);
    
    for (size_t i = 0; i < totalSamples; i++) {
      // Mix channels to mono if needed
      float sum = 0;
      for (int ch = 0; ch < header.numChannels; ch++) {
        sum += buffer[i * header.numChannels + ch] / 32768.0f;
      }
      (*samples)[i] = sum / header.numChannels;
    }
  } else if (header.bitsPerSample == 32 && header.audioFormat == 3) {
    // Float32 PCM
    file.read(reinterpret_cast<char*>(*samples), chunkSize);
    if (header.numChannels > 1) {
      // Mix to mono
      for (size_t i = 0; i < totalSamples; i++) {
        float sum = 0;
        for (int ch = 0; ch < header.numChannels; ch++) {
          sum += (*samples)[i * header.numChannels + ch];
        }
        (*samples)[i] = sum / header.numChannels;
      }
    }
  } else {
    printf("[WAV Reader] Unsupported format: %d bits, format %d\n", header.bitsPerSample, header.audioFormat);
    delete[] *samples;
    *samples = nullptr;
    return false;
  }
  
  printf("[WAV Reader] Read %zu samples at %d Hz\n", *numSamples, *sampleRate);
  return true;
}

void freeWavSamples(float* samples) {
  delete[] samples;
}
} // anonymous namespace
#endif

namespace margelo::nitro::runanywhere {

// ============================================================================
// Base64 Utilities
// ============================================================================

namespace {

static const std::string BASE64_CHARS =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

std::string base64Encode(const unsigned char* data, size_t length) {
  std::string result;
  result.reserve(((length + 2) / 3) * 4);

  for (size_t i = 0; i < length; i += 3) {
    unsigned int n = static_cast<unsigned int>(data[i]) << 16;
    if (i + 1 < length) n |= static_cast<unsigned int>(data[i + 1]) << 8;
    if (i + 2 < length) n |= static_cast<unsigned int>(data[i + 2]);

    result.push_back(BASE64_CHARS[(n >> 18) & 0x3F]);
    result.push_back(BASE64_CHARS[(n >> 12) & 0x3F]);
    result.push_back((i + 1 < length) ? BASE64_CHARS[(n >> 6) & 0x3F] : '=');
    result.push_back((i + 2 < length) ? BASE64_CHARS[n & 0x3F] : '=');
  }

  return result;
}

std::vector<unsigned char> base64Decode(const std::string& encoded) {
  std::vector<unsigned char> result;
  result.reserve((encoded.size() / 4) * 3);

  std::vector<int> T(256, -1);
  for (int i = 0; i < 64; i++) {
    T[static_cast<unsigned char>(BASE64_CHARS[i])] = i;
  }

  int val = 0, valb = -8;
  for (unsigned char c : encoded) {
    if (T[c] == -1) break;
    val = (val << 6) + T[c];
    valb += 6;
    if (valb >= 0) {
      result.push_back(static_cast<unsigned char>((val >> valb) & 0xFF));
      valb -= 8;
    }
  }

  return result;
}

std::string encodeBase64Audio(const float* samples, size_t count) {
  return base64Encode(reinterpret_cast<const unsigned char*>(samples),
                      count * sizeof(float));
}

bool endsWith(const std::string& str, const std::string& suffix) {
  if (suffix.size() > str.size()) return false;
  return std::equal(suffix.rbegin(), suffix.rend(), str.rbegin());
}

// Simple JSON value extraction (handles: "key": 123 or "key": 0.5)
int extractIntValue(const std::string& json, const std::string& key, int defaultValue) {
  std::string searchKey = "\"" + key + "\":";
  size_t pos = json.find(searchKey);
  if (pos == std::string::npos) return defaultValue;
  pos += searchKey.length();
  while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
  if (pos >= json.size()) return defaultValue;
  return std::stoi(json.substr(pos));
}

float extractFloatValue(const std::string& json, const std::string& key, float defaultValue) {
  std::string searchKey = "\"" + key + "\":";
  size_t pos = json.find(searchKey);
  if (pos == std::string::npos) return defaultValue;
  pos += searchKey.length();
  while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t')) pos++;
  if (pos >= json.size()) return defaultValue;
  return std::stof(json.substr(pos));
}

// Simple JSON builder
std::string buildJsonObject(const std::vector<std::pair<std::string, std::string>>& keyValues) {
  std::string result = "{";
  for (size_t i = 0; i < keyValues.size(); i++) {
    if (i > 0) result += ",";
    result += "\"" + keyValues[i].first + "\":" + keyValues[i].second;
  }
  result += "}";
  return result;
}

std::string jsonString(const std::string& value) {
  std::string escaped = "\"";
  for (char c : value) {
    if (c == '"') escaped += "\\\"";
    else if (c == '\\') escaped += "\\\\";
    else if (c == '\n') escaped += "\\n";
    else if (c == '\r') escaped += "\\r";
    else if (c == '\t') escaped += "\\t";
    else escaped += c;
  }
  escaped += "\"";
  return escaped;
}

} // anonymous namespace

// ============================================================================
// Constructor / Destructor
// ============================================================================

HybridRunAnywhere::HybridRunAnywhere() : HybridObject(TAG) {
  printf("[HybridRunAnywhere] Constructor called\n");

  // Check which backends are available
  int count = 0;
  const char** backends = ra_get_available_backends(&count);

  printf("[HybridRunAnywhere] Found %d available backends:\n", count);
  for (int i = 0; i < count; i++) {
    printf("[HybridRunAnywhere]   - %s\n", backends[i]);
  }
}

HybridRunAnywhere::~HybridRunAnywhere() {
  printf("[HybridRunAnywhere] Destructor called\n");

  std::lock_guard<std::mutex> lock(backendMutex_);

  if (onnxBackend_) {
    ra_destroy(onnxBackend_);
    onnxBackend_ = nullptr;
  }

  if (backend_) {
    ra_destroy(backend_);
    backend_ = nullptr;
  }
}

// ============================================================================
// Backend Lifecycle
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::createBackend(
    const std::string& name) {
  return Promise<bool>::async([this, name]() {
    std::lock_guard<std::mutex> lock(backendMutex_);

    printf("[HybridRunAnywhere] createBackend: %s\n", name.c_str());

    backend_ = ra_create_backend(name.c_str());
    if (!backend_) {
      setLastError("Failed to create backend: " + name);
      return false;
    }

    printf("[HybridRunAnywhere] Backend created successfully\n");
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::initialize(
    const std::string& configJson) {
  return Promise<bool>::async([this, configJson]() {
    std::lock_guard<std::mutex> lock(backendMutex_);

    if (!backend_) {
      setLastError("Backend not created");
      return false;
    }

    printf("[HybridRunAnywhere] Initializing with config...\n");

    ra_result_code result = ra_initialize(backend_, configJson.c_str());
    if (result != RA_SUCCESS) {
      setLastError("Failed to initialize backend");
      return false;
    }

    isInitialized_ = true;
    printf("[HybridRunAnywhere] Initialized successfully\n");
    return true;
  });
}

std::shared_ptr<Promise<void>> HybridRunAnywhere::destroy() {
  return Promise<void>::async([this]() {
    std::lock_guard<std::mutex> lock(backendMutex_);

    if (onnxBackend_) {
      ra_destroy(onnxBackend_);
      onnxBackend_ = nullptr;
    }

    if (backend_) {
      ra_destroy(backend_);
      backend_ = nullptr;
    }

    isInitialized_ = false;
    printf("[HybridRunAnywhere] Destroyed\n");
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isInitialized() {
  return Promise<bool>::async([this]() { return isInitialized_; });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getBackendInfo() {
  return Promise<std::string>::async([this]() {
    std::lock_guard<std::mutex> lock(backendMutex_);

    if (!backend_) {
      return std::string("{}");
    }

    const char* info = ra_get_backend_info(backend_);
    return std::string(info ? info : "{}");
  });
}

// ============================================================================
// Text Generation (LLM)
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::loadTextModel(
    const std::string& path,
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([this, path, configJson]() {
    std::lock_guard<std::mutex> lock(modelMutex_);

    if (!backend_) {
      setLastError("Backend not created");
      return false;
    }

    printf("[HybridRunAnywhere] Loading text model: %s\n", path.c_str());

    ra_result_code result = ra_text_load_model(
        backend_, path.c_str(),
        configJson.has_value() ? configJson->c_str() : nullptr);

    if (result != RA_SUCCESS) {
      setLastError("Failed to load model");
      return false;
    }

    printf("[HybridRunAnywhere] Text model loaded successfully\n");
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isTextModelLoaded() {
  return Promise<bool>::async([this]() {
    std::lock_guard<std::mutex> lock(modelMutex_);
    if (!backend_) return false;
    return ra_text_is_model_loaded(backend_);
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::unloadTextModel() {
  return Promise<bool>::async([this]() {
    std::lock_guard<std::mutex> lock(modelMutex_);
    if (!backend_) return false;

    ra_result_code result = ra_text_unload_model(backend_);
    return result == RA_SUCCESS;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::generate(
    const std::string& prompt,
    const std::optional<std::string>& optionsJson) {
  return Promise<std::string>::async([this, prompt, optionsJson]() {
    std::lock_guard<std::mutex> lock(modelMutex_);

    if (!backend_ || !ra_text_is_model_loaded(backend_)) {
      setLastError("Model not loaded");
      return buildJsonObject({{"error", jsonString("Model not loaded")}});
    }

    // Parse options from JSON
    int maxTokens = 256;
    float temperature = 0.7f;
    std::string systemPrompt;

    if (optionsJson.has_value()) {
      maxTokens = extractIntValue(*optionsJson, "max_tokens", 256);
      temperature = extractFloatValue(*optionsJson, "temperature", 0.7f);
      
      // Extract system_prompt string
      size_t sysStart = optionsJson->find("\"system_prompt\":");
      if (sysStart != std::string::npos) {
        sysStart = optionsJson->find("\"", sysStart + 16);
        if (sysStart != std::string::npos) {
          sysStart++;
          size_t sysEnd = optionsJson->find("\"", sysStart);
          if (sysEnd != std::string::npos) {
            systemPrompt = optionsJson->substr(sysStart, sysEnd - sysStart);
          }
        }
      }
    }

    printf("[HybridRunAnywhere] generate() called\n");
    printf("[HybridRunAnywhere] prompt: %.50s...\n", prompt.c_str());
    printf("[HybridRunAnywhere] maxTokens: %d, temperature: %.2f\n", maxTokens, temperature);

    // Prepare full prompt with system prompt if provided
    std::string fullPrompt = prompt;
    if (!systemPrompt.empty() && systemPrompt != "null") {
      fullPrompt = systemPrompt + "\n\n" + prompt;
    }

    auto startTime = std::chrono::high_resolution_clock::now();

    char* result_json = nullptr;
    ra_result_code result = ra_text_generate(
        backend_, fullPrompt.c_str(), nullptr,
        maxTokens, temperature, &result_json);

    auto endTime = std::chrono::high_resolution_clock::now();
    auto durationMs = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime).count();

    if (result != RA_SUCCESS || !result_json) {
      setLastError("Text generation failed");
      return buildJsonObject({{"error", jsonString("Text generation failed")}});
    }

    // Parse the result JSON from runanywhere-core
    std::string coreResult(result_json);
    ra_free_string(result_json);

    // Extract text from the core result
    std::string generatedText;
    size_t textStart = coreResult.find("\"text\":");
    if (textStart != std::string::npos) {
      textStart = coreResult.find("\"", textStart + 7);
      if (textStart != std::string::npos) {
        textStart++;
        size_t textEnd = textStart;
        // Find the closing quote, handling escaped quotes
        while (textEnd < coreResult.size()) {
          textEnd = coreResult.find("\"", textEnd);
          if (textEnd == std::string::npos) break;
          // Check if it's escaped
          int backslashes = 0;
          size_t pos = textEnd - 1;
          while (pos < coreResult.size() && coreResult[pos] == '\\') {
            backslashes++;
            if (pos == 0) break;
            pos--;
          }
          if (backslashes % 2 == 0) break; // Not escaped
          textEnd++;
        }
        if (textEnd != std::string::npos) {
          generatedText = coreResult.substr(textStart, textEnd - textStart);
          // Unescape the string
          std::string unescaped;
          for (size_t i = 0; i < generatedText.size(); i++) {
            if (generatedText[i] == '\\' && i + 1 < generatedText.size()) {
              char next = generatedText[i + 1];
              if (next == 'n') { unescaped += '\n'; i++; }
              else if (next == 'r') { unescaped += '\r'; i++; }
              else if (next == 't') { unescaped += '\t'; i++; }
              else if (next == '"') { unescaped += '"'; i++; }
              else if (next == '\\') { unescaped += '\\'; i++; }
              else { unescaped += generatedText[i]; }
            } else {
              unescaped += generatedText[i];
            }
          }
          generatedText = unescaped;
        }
      }
    }

    // If we couldn't parse text, use raw result
    if (generatedText.empty()) {
      generatedText = coreResult;
    }

    int tokensUsed = extractIntValue(coreResult, "tokens_used", 0);
    if (tokensUsed == 0) {
      tokensUsed = extractIntValue(coreResult, "tokensUsed", 0);
    }
    if (tokensUsed == 0) {
      tokensUsed = static_cast<int>(generatedText.size() / 4); // Rough estimate
    }

    double tokensPerSecond = durationMs > 0 ? (tokensUsed * 1000.0 / durationMs) : 0;

    // Build response in the format expected by the JS SDK
    std::string response = buildJsonObject({
      {"text", jsonString(generatedText)},
      {"tokensUsed", std::to_string(tokensUsed)},
      {"modelUsed", jsonString("llamacpp")},
      {"latencyMs", std::to_string(durationMs)},
      {"executionTarget", "0"},
      {"savedAmount", "0"},
      {"framework", jsonString("llama.cpp")},
      {"hardwareUsed", "0"},
      {"memoryUsed", "0"},
      {"performanceMetrics", buildJsonObject({
        {"timeToFirstTokenMs", std::to_string(durationMs > 0 ? durationMs / 10 : 0)},
        {"tokensPerSecond", std::to_string(tokensPerSecond)},
        {"inferenceTimeMs", std::to_string(durationMs)}
      })}
    });

    printf("[HybridRunAnywhere] generate() completed in %lld ms, %d tokens\n", durationMs, tokensUsed);
    return response;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::generateStream(
    const std::string& prompt,
    const std::string& optionsJson,
    const std::function<void(const std::string&, bool)>& callback) {
  return Promise<std::string>::async([this, prompt, optionsJson, callback]() {
    std::lock_guard<std::mutex> lock(modelMutex_);

    if (!backend_ || !ra_text_is_model_loaded(backend_)) {
      setLastError("Model not loaded");
      return std::string("");
    }

    int maxTokens = extractIntValue(optionsJson, "max_tokens", 512);
    float temperature = extractFloatValue(optionsJson, "temperature", 0.7f);

    std::string fullResponse;

    // Create callback data struct
    struct CallbackData {
      std::function<void(const std::string&, bool)> callback;
      std::string* fullResponse;
    };

    CallbackData callbackData{callback, &fullResponse};

    // Streaming callback wrapper - returns bool (true to continue)
    ra_text_stream_callback streamCallback = [](const char* token, void* userData) -> bool {
      auto* data = static_cast<CallbackData*>(userData);
      std::string tokenStr(token ? token : "");
      *(data->fullResponse) += tokenStr;
      if (data->callback) {
        // Note: we pass false for isComplete, final callback happens after stream ends
        data->callback(tokenStr, false);
      }
      return true; // continue streaming
    };

    ra_result_code result = ra_text_generate_stream(
        backend_, prompt.c_str(), nullptr,
        maxTokens, temperature, streamCallback, &callbackData);

    // Signal completion
    if (callback) {
      callback("", true);
    }

    if (result != RA_SUCCESS) {
      setLastError("Streaming generation failed");
      return std::string("");
    }

    return fullResponse;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::cancelGeneration() {
  return Promise<bool>::async([this]() {
    if (!backend_) return false;
    ra_text_cancel(backend_);
    return true;
  });
}

// ============================================================================
// Speech-to-Text (STT)
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::loadSTTModel(
    const std::string& path,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([this, path, modelType, configJson]() {
    std::lock_guard<std::mutex> lock(modelMutex_);

    if (!onnxBackend_) {
      printf("[HybridRunAnywhere] Creating ONNX backend for STT...\n");
      onnxBackend_ = ra_create_backend("onnx");
      if (!onnxBackend_) {
        setLastError("Failed to create ONNX backend");
        return false;
      }

      ra_result_code initResult = ra_initialize(onnxBackend_, nullptr);
      if (initResult != RA_SUCCESS) {
        ra_destroy(onnxBackend_);
        onnxBackend_ = nullptr;
        setLastError("Failed to initialize ONNX backend");
        return false;
      }
    }

    std::string modelPath = extractArchiveIfNeeded(path);
    printf("[HybridRunAnywhere] Loading STT model: %s\n", modelPath.c_str());

    ra_result_code result = ra_stt_load_model(
        onnxBackend_, modelPath.c_str(), modelType.c_str(),
        configJson.has_value() ? configJson->c_str() : nullptr);

    if (result != RA_SUCCESS) {
      setLastError("Failed to load STT model");
      return false;
    }

    printf("[HybridRunAnywhere] STT model loaded successfully\n");
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isSTTModelLoaded() {
  return Promise<bool>::async([this]() {
    if (!onnxBackend_) return false;
    return ra_stt_is_model_loaded(onnxBackend_);
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::unloadSTTModel() {
  return Promise<bool>::async([this]() {
    if (!onnxBackend_) return false;
    ra_result_code result = ra_stt_unload_model(onnxBackend_);
    return result == RA_SUCCESS;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::transcribe(
    const std::string& audioBase64,
    double sampleRate,
    const std::optional<std::string>& language) {
  return Promise<std::string>::async(
      [this, audioBase64, sampleRate, language]() {
        std::lock_guard<std::mutex> lock(modelMutex_);

        if (!onnxBackend_ || !ra_stt_is_model_loaded(onnxBackend_)) {
          return buildJsonObject({{"error", jsonString("STT model not loaded")}});
        }

        auto audioBytes = base64Decode(audioBase64);
        const float* samples =
            reinterpret_cast<const float*>(audioBytes.data());
        size_t numSamples = audioBytes.size() / sizeof(float);

        printf("[HybridRunAnywhere] Transcribing %zu samples at %d Hz\n",
               numSamples, static_cast<int>(sampleRate));

        char* result_json = nullptr;
        ra_result_code result = ra_stt_transcribe(
            onnxBackend_, samples, numSamples, static_cast<int>(sampleRate),
            language.has_value() ? language->c_str() : "en", &result_json);

        if (result != RA_SUCCESS || !result_json) {
          return buildJsonObject({{"error", jsonString("Transcription failed")}});
        }

        std::string response(result_json);
        ra_free_string(result_json);
        return response;
      });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::transcribeFile(
    const std::string& filePath,
    const std::optional<std::string>& language) {
  return Promise<std::string>::async([this, filePath, language]() {
    std::lock_guard<std::mutex> lock(modelMutex_);

    if (!onnxBackend_ || !ra_stt_is_model_loaded(onnxBackend_)) {
      return buildJsonObject({{"error", jsonString("STT model not loaded")}});
    }

    printf("[HybridRunAnywhere] transcribeFile: %s\n", filePath.c_str());

    float* samples = nullptr;
    size_t numSamples = 0;
    int sampleRate = 0;

#if defined(__APPLE__)
    // Use the iOS AudioDecoder to convert the file to PCM float32
    int decodeResult = ra_decode_audio_file(filePath.c_str(), &samples, &numSamples, &sampleRate);
    if (decodeResult != 1 || !samples || numSamples == 0) {
      printf("[HybridRunAnywhere] Failed to decode audio file\n");
      return buildJsonObject({{"error", jsonString("Failed to decode audio file")}});
    }
#elif defined(ANDROID) || defined(__ANDROID__)
    // Use simple WAV reader on Android
    if (!readWavFile(filePath.c_str(), &samples, &numSamples, &sampleRate)) {
      printf("[HybridRunAnywhere] Failed to read WAV file\n");
      return buildJsonObject({{"error", jsonString("Failed to read audio file. Only WAV format is supported on Android.")}});
    }
#else
    return buildJsonObject({{"error", jsonString("transcribeFile not supported on this platform")}});
#endif

    printf("[HybridRunAnywhere] Decoded %zu samples at %d Hz\n", numSamples, sampleRate);

    // Transcribe the samples
    char* result_json = nullptr;
    ra_result_code result = ra_stt_transcribe(
        onnxBackend_, samples, numSamples, sampleRate,
        language.has_value() ? language->c_str() : "en", &result_json);

    // Free the decoded samples
#if defined(__APPLE__)
    ra_free_audio_samples(samples);
#elif defined(ANDROID) || defined(__ANDROID__)
    freeWavSamples(samples);
#endif

    if (result != RA_SUCCESS || !result_json) {
      printf("[HybridRunAnywhere] Transcription failed\n");
      return buildJsonObject({{"error", jsonString("Transcription failed")}});
    }

    std::string response(result_json);
    ra_free_string(result_json);
    return response;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::supportsSTTStreaming() {
  return Promise<bool>::async([this]() {
    if (!onnxBackend_) return false;
    return ra_stt_supports_streaming(onnxBackend_);
  });
}

// ============================================================================
// Text-to-Speech (TTS)
// ============================================================================

std::shared_ptr<Promise<bool>> HybridRunAnywhere::loadTTSModel(
    const std::string& path,
    const std::string& modelType,
    const std::optional<std::string>& configJson) {
  return Promise<bool>::async([this, path, modelType, configJson]() {
    std::lock_guard<std::mutex> lock(modelMutex_);

    if (!onnxBackend_) {
      printf("[HybridRunAnywhere] Creating ONNX backend for TTS...\n");
      onnxBackend_ = ra_create_backend("onnx");
      if (!onnxBackend_) {
        setLastError("Failed to create ONNX backend");
        return false;
      }

      ra_result_code initResult = ra_initialize(onnxBackend_, nullptr);
      if (initResult != RA_SUCCESS) {
        ra_destroy(onnxBackend_);
        onnxBackend_ = nullptr;
        setLastError("Failed to initialize ONNX backend");
        return false;
      }
    }

    std::string modelPath = extractArchiveIfNeeded(path);
    printf("[HybridRunAnywhere] Loading TTS model: %s\n", modelPath.c_str());

    ra_result_code result = ra_tts_load_model(
        onnxBackend_, modelPath.c_str(), modelType.c_str(),
        configJson.has_value() ? configJson->c_str() : nullptr);

    if (result != RA_SUCCESS) {
      setLastError("Failed to load TTS model");
      return false;
    }

    printf("[HybridRunAnywhere] TTS model loaded successfully\n");
    return true;
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::isTTSModelLoaded() {
  return Promise<bool>::async([this]() {
    if (!onnxBackend_) return false;
    return ra_tts_is_model_loaded(onnxBackend_);
  });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::unloadTTSModel() {
  return Promise<bool>::async([this]() {
    if (!onnxBackend_) return false;
    ra_result_code result = ra_tts_unload_model(onnxBackend_);
    return result == RA_SUCCESS;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::synthesize(
    const std::string& text,
    const std::string& voiceId,
    double speedRate,
    double pitchShift) {
  return Promise<std::string>::async(
      [this, text, voiceId, speedRate, pitchShift]() {
        std::lock_guard<std::mutex> lock(modelMutex_);

        if (!onnxBackend_ || !ra_tts_is_model_loaded(onnxBackend_)) {
          return buildJsonObject({{"error", jsonString("TTS model not loaded")}});
        }

        printf("[HybridRunAnywhere] Synthesizing: %s\n", text.c_str());

        float* audioData = nullptr;
        size_t numSamples = 0;
        int sampleRate = 0;

        ra_result_code result = ra_tts_synthesize(
            onnxBackend_, text.c_str(),
            voiceId.empty() ? nullptr : voiceId.c_str(),
            static_cast<float>(speedRate), static_cast<float>(pitchShift),
            &audioData, &numSamples, &sampleRate);

        if (result != RA_SUCCESS || !audioData) {
          return buildJsonObject({{"error", jsonString("Synthesis failed")}});
        }

        std::string audioBase64 = encodeBase64Audio(audioData, numSamples);
        ra_free_audio(audioData);

        double durationSec = static_cast<double>(numSamples) / sampleRate;

        // Use camelCase keys to match JS expectations
        return buildJsonObject({
            {"audio", jsonString(audioBase64)},
            {"sampleRate", std::to_string(sampleRate)},
            {"numSamples", std::to_string(numSamples)},
            {"duration", std::to_string(durationSec)}
        });
      });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getTTSVoices() {
  return Promise<std::string>::async([]() {
    return std::string("[{\"id\":\"default\",\"name\":\"Default Voice\",\"language\":\"en-US\"}]");
  });
}

// ============================================================================
// Utility Functions
// ============================================================================

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getLastError() {
  return Promise<std::string>::async([this]() { return lastError_; });
}

std::shared_ptr<Promise<bool>> HybridRunAnywhere::extractArchive(
    const std::string& archivePath,
    const std::string& destPath) {
  return Promise<bool>::async([archivePath, destPath]() {
    ra_result_code result =
        ra_extract_archive(archivePath.c_str(), destPath.c_str());
    return result == RA_SUCCESS;
  });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhere::getDeviceCapabilities() {
  return Promise<std::string>::async([]() {
    std::string platform =
#if defined(__APPLE__)
        "ios";
#else
        "android";
#endif
    bool supportsMetal =
#if defined(__APPLE__)
        true;
#else
        false;
#endif
    bool supportsVulkan =
#if defined(__APPLE__)
        false;
#else
        true;
#endif
    return buildJsonObject({
        {"platform", jsonString(platform)},
        {"supports_metal", supportsMetal ? "true" : "false"},
        {"supports_vulkan", supportsVulkan ? "true" : "false"}
    });
  });
}

std::shared_ptr<Promise<double>> HybridRunAnywhere::getMemoryUsage() {
  return Promise<double>::async([this]() {
    if (!backend_) return 0.0;
    return static_cast<double>(ra_get_memory_usage(backend_));
  });
}

// ============================================================================
// Helper Methods
// ============================================================================

void HybridRunAnywhere::setLastError(const std::string& error) {
  lastError_ = error;
  printf("[HybridRunAnywhere] Error: %s\n", error.c_str());
}

std::string HybridRunAnywhere::extractArchiveIfNeeded(
    const std::string& archivePath) {
  bool isTarBz2 =
      endsWith(archivePath, ".tar.bz2") || endsWith(archivePath, ".bz2");
  bool isTarGz =
      endsWith(archivePath, ".tar.gz") || endsWith(archivePath, ".tgz");

  if (!isTarBz2 && !isTarGz) {
    return archivePath;
  }

  std::string modelName;
  size_t lastSlash = archivePath.rfind('/');
  if (lastSlash != std::string::npos) {
    modelName = archivePath.substr(lastSlash + 1);
  } else {
    modelName = archivePath;
  }

  size_t dotPos = modelName.find('.');
  if (dotPos != std::string::npos) {
    modelName = modelName.substr(0, dotPos);
  }

  std::string docsPath;
  size_t modelsPos = archivePath.find("/Documents/");
  if (modelsPos != std::string::npos) {
    docsPath = archivePath.substr(0, modelsPos + 11);
  } else {
    if (lastSlash != std::string::npos) {
      docsPath = archivePath.substr(0, lastSlash + 1);
    } else {
      return archivePath;
    }
  }

  std::string extractDir = docsPath + "sherpa-models/" + modelName;

  struct stat st;
  if (stat(extractDir.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
    DIR* dir = opendir(extractDir.c_str());
    if (dir) {
      struct dirent* entry;
      std::string subdirName;
      int count = 0;
      while ((entry = readdir(dir)) != nullptr) {
        if (entry->d_name[0] != '.') {
          subdirName = entry->d_name;
          count++;
        }
      }
      closedir(dir);

      if (count == 1) {
        std::string subdirPath = extractDir + "/" + subdirName;
        if (stat(subdirPath.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
          return subdirPath;
        }
      }
    }
    return extractDir;
  }

  printf("[HybridRunAnywhere] Extracting archive to: %s\n", extractDir.c_str());
  ra_result_code result =
      ra_extract_archive(archivePath.c_str(), extractDir.c_str());

  if (result != RA_SUCCESS) {
    return archivePath;
  }

  DIR* dir = opendir(extractDir.c_str());
  if (dir) {
    struct dirent* entry;
    std::string subdirName;
    int count = 0;
    while ((entry = readdir(dir)) != nullptr) {
      if (entry->d_name[0] != '.') {
        subdirName = entry->d_name;
        count++;
      }
    }
    closedir(dir);

    if (count == 1) {
      std::string subdirPath = extractDir + "/" + subdirName;
      if (stat(subdirPath.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
        return subdirPath;
      }
    }
  }

  return extractDir;
}

} // namespace margelo::nitro::runanywhere
