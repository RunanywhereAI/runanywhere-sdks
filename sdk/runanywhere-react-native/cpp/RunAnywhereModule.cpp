/**
 * RunAnywhereModule.cpp
 *
 * Pure C++ TurboModule implementation for RunAnywhere React Native SDK.
 * Directly calls runanywhere-core C API for all AI operations.
 */

#include "RunAnywhereModule.h"

// Compile-time debug: check if codegen header was included
#if __has_include("RunAnywhereSpecJSI.h")
#pragma message("✅ RunAnywhereSpecJSI.h IS included - using codegen base class")
#else
#pragma message("❌ RunAnywhereSpecJSI.h NOT included - using TurboModule directly")
#endif

#include <sstream>
#include <cstring>
#include <algorithm>
#include <cctype>
#include <sys/stat.h>
#include <dirent.h>

// Base64 encoding/decoding utilities
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

} // anonymous namespace

namespace facebook::react {

// ============================================================================
// Constructor / Destructor
// ============================================================================

RunAnywhereModule::RunAnywhereModule(std::shared_ptr<CallInvoker> jsInvoker)
#if __has_include("RunAnywhereSpecJSI.h")
    : NativeRunAnywhereCxxSpec<RunAnywhereModule>(jsInvoker)
#else
    : TurboModule("RunAnywhere", jsInvoker)
#endif
    , jsInvoker_(std::move(jsInvoker)) {
    printf("\n");
    printf("═══════════════════════════════════════════════════════════\n");
    printf("  RunAnywhereModule Constructor - START\n");
    printf("═══════════════════════════════════════════════════════════\n");
    printf("[RunAnywhere C++] this pointer: %p\n", (void*)this);
    printf("[RunAnywhere C++] CallInvoker valid: %s\n", jsInvoker_ ? "YES" : "NO");

#if __has_include("RunAnywhereSpecJSI.h")
    printf("[RunAnywhere C++] Base class: NativeRunAnywhereCxxSpec<RunAnywhereModule> (CODEGEN)\n");
#else
    printf("[RunAnywhere C++] Base class: TurboModule (FALLBACK)\n");
#endif

    // Check which backends are available
    int count = 0;
    const char** backends = ra_get_available_backends(&count);

    printf("[RunAnywhere C++] Found %d available backends:\n", count);
    for (int i = 0; i < count; i++) {
        printf("[RunAnywhere C++]   - %s\n", backends[i]);
    }

    if (count == 0) {
        printf("[RunAnywhere C++] ⚠️  WARNING: No backends registered!\n");
    }

    printf("═══════════════════════════════════════════════════════════\n");
    printf("  RunAnywhereModule Constructor - END\n");
    printf("═══════════════════════════════════════════════════════════\n");
    printf("\n");
}

RunAnywhereModule::~RunAnywhereModule() {
    // Clean up all STT streams
    for (auto& [id, stream] : sttStreams_) {
        if (backend_ && stream) {
            ra_stt_destroy_stream(onnxBackend_, stream);
        }
    }
    sttStreams_.clear();

    // Destroy backend
    if (backend_) {
        ra_destroy(backend_);
        backend_ = nullptr;
    }
}

// ============================================================================
// Backend Lifecycle Implementation
// ============================================================================
// NOTE: The base class NativeRunAnywhereCxxSpec<RunAnywhereModule> handles get()
// automatically by forwarding to its internal delegate

std::vector<std::string> RunAnywhereModule::getAvailableBackends(jsi::Runtime& rt) {
    std::vector<std::string> result;

    int count = 0;
    const char** backends = ra_get_available_backends(&count);

    for (int i = 0; i < count; i++) {
        result.push_back(backends[i]);
    }

    return result;
}

bool RunAnywhereModule::createBackend(jsi::Runtime& rt, const std::string& name) {
    printf("[RunAnywhere C++] createBackend called with name: %s\n", name.c_str());

    if (backend_) {
        printf("[RunAnywhere C++] Destroying existing backend\n");
        ra_destroy(backend_);
        backend_ = nullptr;
    }

    backend_ = ra_create_backend(name.c_str());
    bool success = backend_ != nullptr;
    printf("[RunAnywhere C++] createBackend result: %s\n", success ? "SUCCESS" : "FAILED");
    return success;
}

bool RunAnywhereModule::initialize(jsi::Runtime& rt,
                                    const std::optional<std::string>& configJson) {
    if (!backend_) return false;

    ra_result_code result = ra_initialize(
        backend_,
        configJson.has_value() ? configJson->c_str() : nullptr);

    return result == RA_SUCCESS;
}

void RunAnywhereModule::destroy(jsi::Runtime& rt) {
    // Clean up STT streams first (they use ONNX backend)
    for (auto& [id, stream] : sttStreams_) {
        if (onnxBackend_ && stream) {
            ra_stt_destroy_stream(onnxBackend_, stream);
        }
    }
    sttStreams_.clear();

    // Destroy ONNX backend (for STT/TTS)
    if (onnxBackend_) {
        ra_destroy(onnxBackend_);
        onnxBackend_ = nullptr;
    }

    // Destroy main backend (for text generation)
    if (backend_) {
        ra_destroy(backend_);
        backend_ = nullptr;
    }
}

bool RunAnywhereModule::isInitialized(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_is_initialized(backend_);
}

std::string RunAnywhereModule::getBackendInfo(jsi::Runtime& rt) {
    if (!backend_) return "{}";

    char* info = ra_get_backend_info(backend_);
    if (!info) return "{}";

    std::string result(info);
    ra_free_string(info);
    return result;
}

// ============================================================================
// Capability Query Implementation
// ============================================================================

bool RunAnywhereModule::supportsCapability(jsi::Runtime& rt, int capability) {
    if (!backend_) return false;
    return ra_supports_capability(backend_, static_cast<ra_capability_type>(capability));
}

std::vector<int> RunAnywhereModule::getCapabilities(jsi::Runtime& rt) {
    std::vector<int> result;
    if (!backend_) return result;

    ra_capability_type caps[10];
    int count = ra_get_capabilities(backend_, caps, 10);

    for (int i = 0; i < count; i++) {
        result.push_back(static_cast<int>(caps[i]));
    }
    return result;
}

int RunAnywhereModule::getDeviceType(jsi::Runtime& rt) {
    if (!backend_) return 99; // RA_DEVICE_UNKNOWN
    return static_cast<int>(ra_get_device(backend_));
}

double RunAnywhereModule::getMemoryUsage(jsi::Runtime& rt) {
    if (!backend_) return 0;
    return static_cast<double>(ra_get_memory_usage(backend_));
}

// ============================================================================
// Text Generation Implementation
// ============================================================================

bool RunAnywhereModule::loadTextModel(jsi::Runtime& rt, const std::string& path,
                                       const std::optional<std::string>& configJson) {
    if (!backend_) return false;

    ra_result_code result = ra_text_load_model(
        backend_,
        path.c_str(),
        configJson.has_value() ? configJson->c_str() : nullptr);

    return result == RA_SUCCESS;
}

bool RunAnywhereModule::isTextModelLoaded(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_text_is_model_loaded(backend_);
}

bool RunAnywhereModule::unloadTextModel(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_text_unload_model(backend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::generate(jsi::Runtime& rt, const std::string& prompt,
                                         const std::optional<std::string>& systemPrompt,
                                         int maxTokens, double temperature) {
    if (!backend_) return "{\"error\": \"Backend not initialized\"}";

    char* resultJson = nullptr;
    ra_result_code result = ra_text_generate(
        backend_,
        prompt.c_str(),
        systemPrompt.has_value() ? systemPrompt->c_str() : nullptr,
        maxTokens,
        static_cast<float>(temperature),
        &resultJson);

    if (result != RA_SUCCESS || !resultJson) {
        std::ostringstream oss;
        oss << "{\"error\": \"" << (ra_get_last_error() ? ra_get_last_error() : "Generation failed") << "\"}";
        return oss.str();
    }

    std::string resultStr(resultJson);
    ra_free_string(resultJson);
    return resultStr;
}

// Streaming callback context
struct StreamContext {
    jsi::Runtime* runtime;
    RunAnywhereModule* module;
};

static bool textStreamCallback(const char* token, void* userData) {
    // Note: This is called from a native thread, so we need to be careful
    // In a real implementation, we'd use jsInvoker_ to safely call JS
    // For now, we'll store tokens and emit them on the JS thread
    return true;
}

void RunAnywhereModule::generateStream(jsi::Runtime& rt, const std::string& prompt,
                                        const std::optional<std::string>& systemPrompt,
                                        int maxTokens, double temperature) {
    if (!backend_) {
        emitEvent(rt, "onGenerationError", "{\"error\": \"Backend not initialized\"}");
        return;
    }

    // Start streaming on background thread
    // For now, emit a placeholder event
    emitEvent(rt, "onGenerationStart", "{}");

    StreamContext ctx{&rt, this};

    ra_result_code result = ra_text_generate_stream(
        backend_,
        prompt.c_str(),
        systemPrompt.has_value() ? systemPrompt->c_str() : nullptr,
        maxTokens,
        static_cast<float>(temperature),
        textStreamCallback,
        &ctx);

    if (result != RA_SUCCESS) {
        emitEvent(rt, "onGenerationError",
                  std::string("{\"error\": \"") + (ra_get_last_error() ? ra_get_last_error() : "Unknown error") + "\"}");
    } else {
        emitEvent(rt, "onGenerationComplete", "{}");
    }
}

void RunAnywhereModule::cancelGeneration(jsi::Runtime& rt) {
    if (backend_) {
        ra_text_cancel(backend_);
    }
}

// ============================================================================
// Archive Extraction Helper
// ============================================================================

// Helper function to check if path ends with a suffix (case-insensitive)
static bool endsWith(const std::string& str, const std::string& suffix) {
    if (suffix.size() > str.size()) return false;
    return std::equal(suffix.rbegin(), suffix.rend(), str.rbegin(),
                      [](char a, char b) { return std::tolower(a) == std::tolower(b); });
}

// Helper function to find model directory, checking for single subdirectory
static std::string findModelDirectory(const std::string& extractDir) {
    struct stat st;
    
    // Check if there's a single subdirectory (common in tar archives)
    // If so, return that subdirectory as it contains the actual model files
    DIR* dir = opendir(extractDir.c_str());
    if (dir) {
        struct dirent* entry;
        std::string subdirName;
        int count = 0;
        while ((entry = readdir(dir)) != nullptr) {
            if (entry->d_name[0] != '.') { // Skip hidden files
                subdirName = entry->d_name;
                count++;
            }
        }
        closedir(dir);
        
        if (count == 1) {
            std::string subdirPath = extractDir + "/" + subdirName;
            if (stat(subdirPath.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
                printf("[RA_MODEL] Model files in subdirectory: %s\n", subdirPath.c_str());
                return subdirPath;
            }
        }
    }
    
    return extractDir;
}

// Helper function to get extracted model directory from archive path
// Returns the extraction directory path, extracting the archive if needed
static std::string extractArchiveIfNeeded(const std::string& archivePath) {
    // Check if it's an archive file
    bool isTarBz2 = endsWith(archivePath, ".tar.bz2") || endsWith(archivePath, ".bz2");
    bool isTarGz = endsWith(archivePath, ".tar.gz") || endsWith(archivePath, ".tgz");
    
    if (!isTarBz2 && !isTarGz) {
        // Not an archive, return as-is
        printf("[RA_MODEL] Not an archive, using path as-is: %s\n", archivePath.c_str());
        return archivePath;
    }
    
    printf("[RA_MODEL] Processing archive: %s\n", archivePath.c_str());
    
    // Get the documents directory for extraction
    // Extract to sherpa-models/<model-name> directory
    std::string modelName;
    size_t lastSlash = archivePath.rfind('/');
    if (lastSlash != std::string::npos) {
        modelName = archivePath.substr(lastSlash + 1);
    } else {
        modelName = archivePath;
    }
    
    // Remove extensions to get base name
    // e.g., "vits-piper-en-us-lessac.tar.bz2" -> "vits-piper-en-us-lessac"
    size_t dotPos = modelName.find('.');
    if (dotPos != std::string::npos) {
        modelName = modelName.substr(0, dotPos);
    }
    
    // Get documents directory
    // On iOS, the archive is already in Documents/runanywhere-models/
    // We'll extract to Documents/sherpa-models/<model-name>/
    std::string docsPath;
    size_t modelsPos = archivePath.find("/Documents/");
    if (modelsPos != std::string::npos) {
        docsPath = archivePath.substr(0, modelsPos + 11); // Include "/Documents/"
    } else {
        // Fallback - use parent directory of archive
        if (lastSlash != std::string::npos) {
            docsPath = archivePath.substr(0, lastSlash + 1);
        } else {
            return archivePath; // Can't determine path
        }
    }
    
    std::string extractDir = docsPath + "sherpa-models/" + modelName;
    
    // Check if already extracted
    struct stat st;
    if (stat(extractDir.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
        // Already extracted - find the actual model directory
        printf("[RA_MODEL] Already extracted to: %s\n", extractDir.c_str());
        return findModelDirectory(extractDir);
    }
    
    // Extract the archive
    printf("[RA_MODEL] Extracting to: %s\n", extractDir.c_str());
    ra_result_code result = ra_extract_archive(archivePath.c_str(), extractDir.c_str());
    if (result != RA_SUCCESS) {
        // Extraction failed, return original path (will likely fail to load)
        printf("[RA_MODEL] Extraction failed!\n");
        return archivePath;
    }
    
    printf("[RA_MODEL] Extraction successful, finding model directory...\n");
    return findModelDirectory(extractDir);
}

// ============================================================================
// Speech-to-Text Implementation
// ============================================================================

bool RunAnywhereModule::loadSTTModel(jsi::Runtime& rt, const std::string& path,
                                      const std::string& modelType,
                                      const std::optional<std::string>& configJson) {
    printf("[RA_STT] loadSTTModel called with path: %s, type: %s\n", path.c_str(), modelType.c_str());

    // STT requires the ONNX backend, create it if not exists
    if (!onnxBackend_) {
        printf("[RA_STT] Creating ONNX backend for STT...\n");
        onnxBackend_ = ra_create_backend("onnx");
        if (!onnxBackend_) {
            printf("[RA_STT] Failed to create ONNX backend!\n");
            return false;
        }
        
        // Initialize the ONNX backend
        ra_result_code initResult = ra_initialize(onnxBackend_, nullptr);
        if (initResult != RA_SUCCESS) {
            printf("[RA_STT] Failed to initialize ONNX backend: %d\n", initResult);
            ra_destroy(onnxBackend_);
            onnxBackend_ = nullptr;
            return false;
        }
        printf("[RA_STT] ONNX backend created and initialized successfully\n");
    }

    // Handle archive extraction if needed (like Swift SDK does)
    std::string modelPath = extractArchiveIfNeeded(path);
    printf("[RA_STT] Using model path: %s\n", modelPath.c_str());

    ra_result_code result = ra_stt_load_model(
        onnxBackend_,  // Use ONNX backend for STT
        modelPath.c_str(),
        modelType.c_str(),
        configJson.has_value() ? configJson->c_str() : nullptr);

    printf("[RA_STT] ra_stt_load_model result: %d\n", result);
    return result == RA_SUCCESS;
}

bool RunAnywhereModule::isSTTModelLoaded(jsi::Runtime& rt) {
    if (!onnxBackend_) return false;
    return ra_stt_is_model_loaded(onnxBackend_);
}

bool RunAnywhereModule::unloadSTTModel(jsi::Runtime& rt) {
    if (!onnxBackend_) return false;
    return ra_stt_unload_model(onnxBackend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::transcribe(jsi::Runtime& rt, const std::string& audioBase64,
                                           int sampleRate,
                                           const std::optional<std::string>& language) {
    if (!backend_) return "{\"error\": \"Backend not initialized\"}";

    // Decode base64 audio
    std::vector<float> samples = decodeBase64Audio(audioBase64);
    if (samples.empty()) {
        return "{\"error\": \"Failed to decode audio\"}";
    }

    char* resultJson = nullptr;
    ra_result_code result = ra_stt_transcribe(
        backend_,
        samples.data(),
        samples.size(),
        sampleRate,
        language.has_value() ? language->c_str() : nullptr,
        &resultJson);

    if (result != RA_SUCCESS || !resultJson) {
        return "{\"error\": \"Transcription failed\"}";
    }

    std::string resultStr(resultJson);
    ra_free_string(resultJson);
    return resultStr;
}

// Forward declaration of iOS audio decoder (defined in AudioDecoder.m)
#if defined(__APPLE__)
extern "C" {
    int ra_decode_audio_file(const char* filePath, float** samples, size_t* numSamples, int* sampleRate);
    void ra_free_audio_samples(float* samples);
}
#endif

std::string RunAnywhereModule::transcribeFile(jsi::Runtime& rt, const std::string& filePath,
                                               const std::optional<std::string>& language) {
    printf("[RA_STT] transcribeFile called with path: %s\n", filePath.c_str());
    
    if (!onnxBackend_) {
        printf("[RA_STT] ONNX backend not initialized\n");
        return "{\"error\": \"ONNX backend not initialized\", \"text\": \"\"}";
    }
    
    if (!ra_stt_is_model_loaded(onnxBackend_)) {
        printf("[RA_STT] STT model not loaded\n");
        return "{\"error\": \"STT model not loaded\", \"text\": \"\"}";
    }
    
    // Remove file:// prefix if present
    std::string actualPath = filePath;
    if (actualPath.find("file://") == 0) {
        actualPath = actualPath.substr(7);
    }
    
    printf("[RA_STT] Actual file path: %s\n", actualPath.c_str());
    
    // Check if file exists
    struct stat path_stat;
    if (stat(actualPath.c_str(), &path_stat) != 0) {
        printf("[RA_STT] File not found: %s\n", actualPath.c_str());
        return "{\"error\": \"File not found\", \"text\": \"\"}";
    }
    
    float* samples = nullptr;
    size_t numSamples = 0;
    int sampleRate = 16000;
    
#if defined(__APPLE__)
    // Use iOS AudioToolbox to decode any audio format to 16kHz mono float32 PCM
    printf("[RA_STT] Using iOS AudioDecoder to convert audio...\n");
    
    int success = ra_decode_audio_file(actualPath.c_str(), &samples, &numSamples, &sampleRate);
    if (!success || !samples || numSamples == 0) {
        printf("[RA_STT] Failed to decode audio file\n");
        if (samples) ra_free_audio_samples(samples);
        return "{\"error\": \"Failed to decode audio file\", \"text\": \"\"}";
    }
    
    printf("[RA_STT] Decoded %zu samples at %d Hz\n", numSamples, sampleRate);
#else
    // Android/other platforms - try to read as WAV
    printf("[RA_STT] Non-iOS platform - attempting WAV parsing\n");
    
    FILE* file = fopen(actualPath.c_str(), "rb");
    if (!file) {
        printf("[RA_STT] Failed to open file\n");
        return "{\"error\": \"Failed to open file\", \"text\": \"\"}";
    }
    
    fseek(file, 0, SEEK_END);
    long fileSize = ftell(file);
    fseek(file, 0, SEEK_SET);
    
    std::vector<unsigned char> fileData(fileSize);
    size_t bytesRead = fread(fileData.data(), 1, fileSize, file);
    fclose(file);
    
    if (bytesRead != (size_t)fileSize) {
        return "{\"error\": \"Failed to read file\", \"text\": \"\"}";
    }
    
    // Check for WAV header
    if (fileSize < 44 || fileData[0] != 'R' || fileData[1] != 'I' || 
        fileData[2] != 'F' || fileData[3] != 'F') {
        return "{\"error\": \"Unsupported audio format. Please use WAV format.\", \"text\": \"\"}";
    }
    
    // Simple WAV parsing (for Android fallback)
    std::vector<float> sampleVec;
    // ... (WAV parsing code would go here for Android)
    return "{\"error\": \"Android WAV parsing not yet implemented\", \"text\": \"\"}";
#endif
    
    printf("[RA_STT] Transcribing %zu samples at %d Hz\n", numSamples, sampleRate);
    
    // Call the transcription API
    char* resultJson = nullptr;
    ra_result_code result = ra_stt_transcribe(
        onnxBackend_,
        samples,
        numSamples,
        sampleRate,
        language.has_value() ? language->c_str() : nullptr,
        &resultJson);
    
    // Free the samples
#if defined(__APPLE__)
    ra_free_audio_samples(samples);
#endif
    
    if (result != RA_SUCCESS) {
        printf("[RA_STT] Transcription failed with code: %d\n", result);
        return "{\"error\": \"Transcription failed\", \"text\": \"\"}";
    }
    
    if (!resultJson) {
        printf("[RA_STT] No result returned\n");
        return "{\"error\": \"No result returned\", \"text\": \"\"}";
    }
    
    std::string resultStr(resultJson);
    ra_free_string(resultJson);
    
    printf("[RA_STT] Transcription result: %s\n", resultStr.c_str());
    return resultStr;
}

bool RunAnywhereModule::supportsSTTStreaming(jsi::Runtime& rt) {
    // STT uses ONNX backend
    if (!onnxBackend_) return false;
    return ra_stt_supports_streaming(onnxBackend_);
}

int RunAnywhereModule::createSTTStream(jsi::Runtime& rt,
                                        const std::optional<std::string>& configJson) {
    if (!onnxBackend_) return -1;

    ra_stream_handle stream = ra_stt_create_stream(
        onnxBackend_,  // Use ONNX backend for STT streams
        configJson.has_value() ? configJson->c_str() : nullptr);

    if (!stream) return -1;

    int id = nextStreamId_++;
    sttStreams_[id] = stream;
    return id;
}

bool RunAnywhereModule::feedSTTAudio(jsi::Runtime& rt, int streamHandle,
                                      const std::string& audioBase64, int sampleRate) {
    if (!onnxBackend_) return false;

    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return false;

    std::vector<float> samples = decodeBase64Audio(audioBase64);
    if (samples.empty()) return false;

    ra_result_code result = ra_stt_feed_audio(
        onnxBackend_, it->second, samples.data(), samples.size(), sampleRate);

    return result == RA_SUCCESS;
}

std::string RunAnywhereModule::decodeSTT(jsi::Runtime& rt, int streamHandle) {
    if (!onnxBackend_) return "{}";

    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return "{}";

    char* resultJson = nullptr;
    ra_result_code result = ra_stt_decode(onnxBackend_, it->second, &resultJson);

    if (result != RA_SUCCESS || !resultJson) return "{}";

    std::string resultStr(resultJson);
    ra_free_string(resultJson);
    return resultStr;
}

bool RunAnywhereModule::isSTTReady(jsi::Runtime& rt, int streamHandle) {
    if (!onnxBackend_) return false;
    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return false;
    return ra_stt_is_ready(onnxBackend_, it->second);
}

bool RunAnywhereModule::isSTTEndpoint(jsi::Runtime& rt, int streamHandle) {
    if (!onnxBackend_) return false;
    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return false;
    return ra_stt_is_endpoint(onnxBackend_, it->second);
}

void RunAnywhereModule::finishSTTInput(jsi::Runtime& rt, int streamHandle) {
    if (!onnxBackend_) return;
    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return;
    ra_stt_input_finished(onnxBackend_, it->second);
}

void RunAnywhereModule::resetSTTStream(jsi::Runtime& rt, int streamHandle) {
    if (!onnxBackend_) return;
    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return;
    ra_stt_reset_stream(onnxBackend_, it->second);
}

void RunAnywhereModule::destroySTTStream(jsi::Runtime& rt, int streamHandle) {
    if (!onnxBackend_) return;
    auto it = sttStreams_.find(streamHandle);
    if (it == sttStreams_.end()) return;

    ra_stt_destroy_stream(onnxBackend_, it->second);
    sttStreams_.erase(it);
}

// ============================================================================
// Text-to-Speech Implementation
// ============================================================================

bool RunAnywhereModule::loadTTSModel(jsi::Runtime& rt, const std::string& path,
                                      const std::string& modelType,
                                      const std::optional<std::string>& configJson) {
    printf("[RA_TTS] loadTTSModel called with path: %s, type: %s\n", path.c_str(), modelType.c_str());

    // TTS requires the ONNX backend, create it if not exists
    if (!onnxBackend_) {
        printf("[RA_TTS] Creating ONNX backend for TTS...\n");
        onnxBackend_ = ra_create_backend("onnx");
        if (!onnxBackend_) {
            printf("[RA_TTS] Failed to create ONNX backend!\n");
            return false;
        }
        
        // Initialize the ONNX backend
        ra_result_code initResult = ra_initialize(onnxBackend_, nullptr);
        if (initResult != RA_SUCCESS) {
            printf("[RA_TTS] Failed to initialize ONNX backend: %d\n", initResult);
            ra_destroy(onnxBackend_);
            onnxBackend_ = nullptr;
            return false;
        }
        printf("[RA_TTS] ONNX backend created and initialized successfully\n");
    }

    // Handle archive extraction if needed (like Swift SDK does)
    std::string modelPath = extractArchiveIfNeeded(path);
    printf("[RA_TTS] Using model path: %s\n", modelPath.c_str());

    ra_result_code result = ra_tts_load_model(
        onnxBackend_,  // Use ONNX backend for TTS
        modelPath.c_str(),
        modelType.c_str(),
        configJson.has_value() ? configJson->c_str() : nullptr);

    printf("[RA_TTS] ra_tts_load_model result: %d\n", result);
    return result == RA_SUCCESS;
}

bool RunAnywhereModule::isTTSModelLoaded(jsi::Runtime& rt) {
    if (!onnxBackend_) return false;
    return ra_tts_is_model_loaded(onnxBackend_);
}

bool RunAnywhereModule::unloadTTSModel(jsi::Runtime& rt) {
    if (!onnxBackend_) return false;
    return ra_tts_unload_model(onnxBackend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::synthesize(jsi::Runtime& rt, const std::string& text,
                                           const std::optional<std::string>& voiceId,
                                           double speedRate, double pitchShift) {
    if (!onnxBackend_) return "{\"error\": \"ONNX Backend not initialized for TTS\"}";

    float* audioSamples = nullptr;
    size_t numSamples = 0;
    int sampleRate = 0;

    ra_result_code result = ra_tts_synthesize(
        onnxBackend_,
        text.c_str(),
        voiceId.has_value() ? voiceId->c_str() : nullptr,
        static_cast<float>(speedRate),
        static_cast<float>(pitchShift),
        &audioSamples,
        &numSamples,
        &sampleRate);

    if (result != RA_SUCCESS || !audioSamples) {
        return "{\"error\": \"Synthesis failed\"}";
    }

    // Encode audio to base64
    std::string audioBase64 = encodeBase64Audio(audioSamples, numSamples);
    ra_free_audio(audioSamples);

    std::ostringstream oss;
    oss << "{\"audio\": \"" << audioBase64 << "\", \"sampleRate\": " << sampleRate
        << ", \"numSamples\": " << numSamples << "}";
    return oss.str();
}

bool RunAnywhereModule::supportsTTSStreaming(jsi::Runtime& rt) {
    if (!onnxBackend_) return false;
    return ra_tts_supports_streaming(onnxBackend_);
}

void RunAnywhereModule::synthesizeStream(jsi::Runtime& rt, const std::string& text,
                                          const std::optional<std::string>& voiceId,
                                          double speedRate, double pitchShift) {
    // TODO: Implement streaming TTS with callbacks
    emitEvent(rt, "onTTSError", "{\"error\": \"Streaming TTS not yet implemented\"}");
}

std::string RunAnywhereModule::getTTSVoices(jsi::Runtime& rt) {
    if (!backend_) return "[]";

    char* voices = ra_tts_get_voices(onnxBackend_);
    if (!voices) return "[]";

    std::string result(voices);
    ra_free_string(voices);
    return result;
}

void RunAnywhereModule::cancelTTS(jsi::Runtime& rt) {
    if (backend_) {
        ra_tts_cancel(onnxBackend_);
    }
}

// ============================================================================
// VAD Implementation
// ============================================================================

bool RunAnywhereModule::loadVADModel(jsi::Runtime& rt, const std::string& path,
                                      const std::optional<std::string>& configJson) {
    if (!backend_) return false;

    ra_result_code result = ra_vad_load_model(
        backend_,
        path.c_str(),
        configJson.has_value() ? configJson->c_str() : nullptr);

    return result == RA_SUCCESS;
}

bool RunAnywhereModule::isVADModelLoaded(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_vad_is_model_loaded(backend_);
}

bool RunAnywhereModule::unloadVADModel(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_vad_unload_model(backend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::processVAD(jsi::Runtime& rt, const std::string& audioBase64,
                                           int sampleRate) {
    if (!backend_) return "{\"isSpeech\": false, \"probability\": 0}";

    std::vector<float> samples = decodeBase64Audio(audioBase64);
    if (samples.empty()) {
        return "{\"isSpeech\": false, \"probability\": 0}";
    }

    bool isSpeech = false;
    float probability = 0.0f;

    ra_result_code result = ra_vad_process(
        backend_,
        samples.data(),
        samples.size(),
        sampleRate,
        &isSpeech,
        &probability);

    if (result != RA_SUCCESS) {
        return "{\"isSpeech\": false, \"probability\": 0}";
    }

    std::ostringstream oss;
    oss << "{\"isSpeech\": " << (isSpeech ? "true" : "false")
        << ", \"probability\": " << probability << "}";
    return oss.str();
}

std::string RunAnywhereModule::detectVADSegments(jsi::Runtime& rt,
                                                  const std::string& audioBase64,
                                                  int sampleRate) {
    if (!backend_) return "[]";

    std::vector<float> samples = decodeBase64Audio(audioBase64);
    if (samples.empty()) return "[]";

    char* resultJson = nullptr;
    ra_result_code result = ra_vad_detect_segments(
        backend_,
        samples.data(),
        samples.size(),
        sampleRate,
        &resultJson);

    if (result != RA_SUCCESS || !resultJson) return "[]";

    std::string resultStr(resultJson);
    ra_free_string(resultJson);
    return resultStr;
}

void RunAnywhereModule::resetVAD(jsi::Runtime& rt) {
    if (backend_) {
        ra_vad_reset(backend_);
    }
}

// ============================================================================
// Embeddings Implementation (Stubs - to be completed)
// ============================================================================

bool RunAnywhereModule::loadEmbeddingsModel(jsi::Runtime& rt, const std::string& path,
                                             const std::optional<std::string>& configJson) {
    if (!backend_) return false;
    return ra_embed_load_model(backend_, path.c_str(),
                               configJson.has_value() ? configJson->c_str() : nullptr) == RA_SUCCESS;
}

bool RunAnywhereModule::isEmbeddingsModelLoaded(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_embed_is_model_loaded(backend_);
}

bool RunAnywhereModule::unloadEmbeddingsModel(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_embed_unload_model(backend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::embedText(jsi::Runtime& rt, const std::string& text) {
    if (!backend_) return "{\"error\": \"Backend not initialized\"}";

    float* embedding = nullptr;
    int dimensions = 0;

    ra_result_code result = ra_embed_text(backend_, text.c_str(), &embedding, &dimensions);

    if (result != RA_SUCCESS || !embedding) {
        return "{\"error\": \"Embedding failed\"}";
    }

    // Build JSON array
    std::ostringstream oss;
    oss << "{\"embedding\": [";
    for (int i = 0; i < dimensions; i++) {
        if (i > 0) oss << ",";
        oss << embedding[i];
    }
    oss << "], \"dimensions\": " << dimensions << "}";

    ra_free_embedding(embedding);
    return oss.str();
}

std::string RunAnywhereModule::embedBatch(jsi::Runtime& rt,
                                           const std::vector<std::string>& texts) {
    if (!backend_) {
        return "{\"error\": \"Backend not initialized\"}";
    }

    if (texts.empty()) {
        return "{\"error\": \"No texts provided for embedding\"}";
    }

    // Convert std::vector<std::string> to const char** array
    std::vector<const char*> textPtrs;
    textPtrs.reserve(texts.size());
    for (const auto& text : texts) {
        textPtrs.push_back(text.c_str());
    }

    float** embeddings = nullptr;
    int dimensions = 0;

    ra_result_code result = ra_embed_batch(backend_, textPtrs.data(), texts.size(), &embeddings, &dimensions);

    if (result != RA_SUCCESS || !embeddings) {
        return std::string("{\"error\": \"") + (ra_get_last_error() ? ra_get_last_error() : "Batch embedding failed") + "\"}";
    }

    // Build JSON array of embeddings
    std::ostringstream json;
    json << "{\"embeddings\": [";

    for (int i = 0; i < static_cast<int>(texts.size()); i++) {
        json << "[";
        for (int j = 0; j < dimensions; j++) {
            json << embeddings[i][j];
            if (j < dimensions - 1) json << ",";
        }
        json << "]";
        if (i < static_cast<int>(texts.size()) - 1) json << ",";
    }

    json << "], \"dimensions\": " << dimensions << "}";

    // Free memory
    ra_free_embeddings(embeddings, texts.size());

    return json.str();
}

int RunAnywhereModule::getEmbeddingDimensions(jsi::Runtime& rt) {
    if (!backend_) return 0;
    return ra_embed_get_dimensions(backend_);
}

// ============================================================================
// Diarization Implementation (Stubs - to be completed)
// ============================================================================

bool RunAnywhereModule::loadDiarizationModel(jsi::Runtime& rt, const std::string& path,
                                              const std::optional<std::string>& configJson) {
    if (!backend_) return false;
    return ra_diarize_load_model(backend_, path.c_str(),
                                 configJson.has_value() ? configJson->c_str() : nullptr) == RA_SUCCESS;
}

bool RunAnywhereModule::isDiarizationModelLoaded(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_diarize_is_model_loaded(backend_);
}

bool RunAnywhereModule::unloadDiarizationModel(jsi::Runtime& rt) {
    if (!backend_) return false;
    return ra_diarize_unload_model(backend_) == RA_SUCCESS;
}

std::string RunAnywhereModule::diarize(jsi::Runtime& rt, const std::string& audioBase64,
                                        int sampleRate, int minSpeakers, int maxSpeakers) {
    if (!backend_) return "{\"error\": \"Backend not initialized\"}";

    std::vector<float> samples = decodeBase64Audio(audioBase64);
    if (samples.empty()) return "{\"error\": \"Failed to decode audio\"}";

    char* resultJson = nullptr;
    ra_result_code result = ra_diarize(
        backend_,
        samples.data(),
        samples.size(),
        sampleRate,
        minSpeakers,
        maxSpeakers,
        &resultJson);

    if (result != RA_SUCCESS || !resultJson) {
        return "{\"error\": \"Diarization failed\"}";
    }

    std::string resultStr(resultJson);
    ra_free_string(resultJson);
    return resultStr;
}

void RunAnywhereModule::cancelDiarization(jsi::Runtime& rt) {
    if (backend_) {
        ra_diarize_cancel(backend_);
    }
}

// ============================================================================
// Utility Implementation
// ============================================================================

std::string RunAnywhereModule::getLastError(jsi::Runtime& rt) {
    const char* error = ra_get_last_error();
    return error ? std::string(error) : "";
}

std::string RunAnywhereModule::getVersion(jsi::Runtime& rt) {
    const char* version = ra_get_version();
    return version ? std::string(version) : "unknown";
}

bool RunAnywhereModule::extractArchive(jsi::Runtime& rt, const std::string& archivePath,
                                        const std::string& destDir) {
    return ra_extract_archive(archivePath.c_str(), destDir.c_str()) == RA_SUCCESS;
}

// ============================================================================
// Event System Implementation
// ============================================================================

void RunAnywhereModule::addListener(jsi::Runtime& rt, const std::string& eventName) {
    listenerCount_++;
}

void RunAnywhereModule::removeListeners(jsi::Runtime& rt, int count) {
    listenerCount_ = std::max(0, listenerCount_ - count);
}

void RunAnywhereModule::emitEvent(jsi::Runtime& rt, const std::string& eventName,
                                   const std::string& eventData) {
    if (listenerCount_ <= 0) return;

    // FIXED: Thread-safe event queuing pattern
    // Instead of capturing jsi::Runtime& by reference (which causes use-after-free),
    // we queue the event and let JS poll for it on its own thread.
    // This avoids any issues with RT lifetime and async callbacks.
    {
        std::lock_guard<std::mutex> lock(eventQueueMutex_);
        eventQueue_.push_back(PendingEvent{eventName, eventData});
    }
}

std::string RunAnywhereModule::pollEvents(jsi::Runtime& rt) {
    std::lock_guard<std::mutex> lock(eventQueueMutex_);

    // Build JSON array of queued events
    std::ostringstream oss;
    oss << "[";

    for (size_t i = 0; i < eventQueue_.size(); i++) {
        if (i > 0) oss << ",";
        const auto& event = eventQueue_[i];

        // Escape event name for JSON
        oss << "{\"eventName\":\"" << event.eventName << "\",\"eventData\":" << event.eventData << "}";
    }

    oss << "]";

    // Clear the queue after draining
    eventQueue_.clear();

    return oss.str();
}

void RunAnywhereModule::clearEventQueue(jsi::Runtime& rt) {
    std::lock_guard<std::mutex> lock(eventQueueMutex_);
    eventQueue_.clear();
}

// ============================================================================
// Helper Methods
// ============================================================================

std::vector<float> RunAnywhereModule::decodeBase64Audio(const std::string& base64) {
    std::vector<unsigned char> decoded = base64Decode(base64);
    if (decoded.empty()) return {};

    // Assume float32 audio samples
    size_t numSamples = decoded.size() / sizeof(float);
    std::vector<float> samples(numSamples);
    std::memcpy(samples.data(), decoded.data(), decoded.size());
    return samples;
}

std::string RunAnywhereModule::encodeBase64Audio(const float* samples, size_t count) {
    const unsigned char* data = reinterpret_cast<const unsigned char*>(samples);
    return base64Encode(data, count * sizeof(float));
}

ra_stream_handle RunAnywhereModule::getStreamHandle(int id) {
    auto it = sttStreams_.find(id);
    return (it != sttStreams_.end()) ? it->second : nullptr;
}

} // namespace facebook::react

// NOTE: C++ TurboModule registration is done in RunAnywhereTurboModuleProvider.mm
// via ObjC +load method, which is guaranteed to run before main().
