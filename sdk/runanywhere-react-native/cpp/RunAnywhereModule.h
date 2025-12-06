/**
 * RunAnywhereModule.h
 *
 * Pure C++ TurboModule for RunAnywhere React Native SDK.
 * This module directly interfaces with runanywhere-core C API.
 *
 * Cross-platform: Same code runs on both iOS and Android.
 */

#pragma once

#include <memory>
#include <string>
#include <unordered_map>
#include <optional>
#include <vector>
#include <mutex>

#include <jsi/jsi.h>
#include <ReactCommon/TurboModule.h>
#include <ReactCommon/CallInvoker.h>
#include <ReactCommon/CxxTurboModuleUtils.h>

// Include runanywhere-core C API
// The header path is configured in CMake/Xcode build settings
extern "C" {
#include "RunAnywhereCore/ra_core.h"
}

// Include codegen-generated spec
// This is generated in ios/build/generated/ios/RunAnywhereSpecJSI.h
#if __has_include("RunAnywhereSpecJSI.h")
#include "RunAnywhereSpecJSI.h"
#endif

namespace facebook::react {

/**
 * RunAnywhereModule - Pure C++ TurboModule
 *
 * This class implements the TurboModule interface defined in NativeRunAnywhere.ts.
 * It directly calls runanywhere-core C API functions for all AI operations.
 *
 * Key features:
 * - Single codebase for iOS and Android
 * - Direct C API access (no Swift/Kotlin wrappers)
 * - Synchronous JSI calls for low latency
 * - Event emission for streaming operations
 * - React Native New Architecture only (TurboModules)
 *
 * Inherits from NativeRunAnywhereCxxSpec<RunAnywhereModule> which is the
 * codegen-generated base class using CRTP (Curiously Recurring Template Pattern).
 */
#if __has_include("RunAnywhereSpecJSI.h")
class RunAnywhereModule : public NativeRunAnywhereCxxSpec<RunAnywhereModule> {
#else
class RunAnywhereModule : public TurboModule {
#endif
public:
    /**
     * Constructor
     * @param jsInvoker CallInvoker for thread-safe JS calls
     */
    explicit RunAnywhereModule(std::shared_ptr<CallInvoker> jsInvoker);

    /**
     * Destructor - cleans up all native resources
     */
    ~RunAnywhereModule() override;

    // ============================================================================
    // TurboModule interface
    // ============================================================================
    // NOTE: The base class NativeRunAnywhereCxxSpec<RunAnywhereModule> already implements
    // get() to forward to the delegate, so we don't need to override it

    // ============================================================================
    // Backend Lifecycle
    // ============================================================================
    // NOTE: These methods must be public for codegen delegate to call them via CRTP

    std::vector<std::string> getAvailableBackends(jsi::Runtime& rt);
    bool createBackend(jsi::Runtime& rt, const std::string& name);
    bool initialize(jsi::Runtime& rt, const std::optional<std::string>& configJson);
    void destroy(jsi::Runtime& rt);
    bool isInitialized(jsi::Runtime& rt);
    std::string getBackendInfo(jsi::Runtime& rt);

    // ============================================================================
    // Capability Query
    // ============================================================================

    bool supportsCapability(jsi::Runtime& rt, int capability);
    std::vector<int> getCapabilities(jsi::Runtime& rt);
    int getDeviceType(jsi::Runtime& rt);
    double getMemoryUsage(jsi::Runtime& rt);

    // ============================================================================
    // Text Generation
    // ============================================================================

    bool loadTextModel(jsi::Runtime& rt, const std::string& path,
                       const std::optional<std::string>& configJson);
    bool isTextModelLoaded(jsi::Runtime& rt);
    bool unloadTextModel(jsi::Runtime& rt);
    std::string generate(jsi::Runtime& rt, const std::string& prompt,
                         const std::optional<std::string>& systemPrompt,
                         int maxTokens, double temperature);
    void generateStream(jsi::Runtime& rt, const std::string& prompt,
                        const std::optional<std::string>& systemPrompt,
                        int maxTokens, double temperature);
    void cancelGeneration(jsi::Runtime& rt);

    // ============================================================================
    // Speech-to-Text
    // ============================================================================

    bool loadSTTModel(jsi::Runtime& rt, const std::string& path,
                      const std::string& modelType,
                      const std::optional<std::string>& configJson);
    bool isSTTModelLoaded(jsi::Runtime& rt);
    bool unloadSTTModel(jsi::Runtime& rt);
    std::string transcribe(jsi::Runtime& rt, const std::string& audioBase64,
                           int sampleRate, const std::optional<std::string>& language);
    std::string transcribeFile(jsi::Runtime& rt, const std::string& filePath,
                              const std::optional<std::string>& language);
    bool supportsSTTStreaming(jsi::Runtime& rt);
    int createSTTStream(jsi::Runtime& rt, const std::optional<std::string>& configJson);
    bool feedSTTAudio(jsi::Runtime& rt, int streamHandle,
                      const std::string& audioBase64, int sampleRate);
    std::string decodeSTT(jsi::Runtime& rt, int streamHandle);
    bool isSTTReady(jsi::Runtime& rt, int streamHandle);
    bool isSTTEndpoint(jsi::Runtime& rt, int streamHandle);
    void finishSTTInput(jsi::Runtime& rt, int streamHandle);
    void resetSTTStream(jsi::Runtime& rt, int streamHandle);
    void destroySTTStream(jsi::Runtime& rt, int streamHandle);

    // ============================================================================
    // Text-to-Speech
    // ============================================================================

    bool loadTTSModel(jsi::Runtime& rt, const std::string& path,
                      const std::string& modelType,
                      const std::optional<std::string>& configJson);
    bool isTTSModelLoaded(jsi::Runtime& rt);
    bool unloadTTSModel(jsi::Runtime& rt);
    std::string synthesize(jsi::Runtime& rt, const std::string& text,
                           const std::optional<std::string>& voiceId,
                           double speedRate, double pitchShift);
    bool supportsTTSStreaming(jsi::Runtime& rt);
    void synthesizeStream(jsi::Runtime& rt, const std::string& text,
                          const std::optional<std::string>& voiceId,
                          double speedRate, double pitchShift);
    std::string getTTSVoices(jsi::Runtime& rt);
    void cancelTTS(jsi::Runtime& rt);

    // ============================================================================
    // Voice Activity Detection
    // ============================================================================

    bool loadVADModel(jsi::Runtime& rt, const std::string& path,
                      const std::optional<std::string>& configJson);
    bool isVADModelLoaded(jsi::Runtime& rt);
    bool unloadVADModel(jsi::Runtime& rt);
    std::string processVAD(jsi::Runtime& rt, const std::string& audioBase64,
                           int sampleRate);
    std::string detectVADSegments(jsi::Runtime& rt, const std::string& audioBase64,
                                  int sampleRate);
    void resetVAD(jsi::Runtime& rt);

    // ============================================================================
    // Embeddings
    // ============================================================================

    bool loadEmbeddingsModel(jsi::Runtime& rt, const std::string& path,
                             const std::optional<std::string>& configJson);
    bool isEmbeddingsModelLoaded(jsi::Runtime& rt);
    bool unloadEmbeddingsModel(jsi::Runtime& rt);
    std::string embedText(jsi::Runtime& rt, const std::string& text);
    std::string embedBatch(jsi::Runtime& rt, const std::vector<std::string>& texts);
    int getEmbeddingDimensions(jsi::Runtime& rt);

    // ============================================================================
    // Speaker Diarization
    // ============================================================================

    bool loadDiarizationModel(jsi::Runtime& rt, const std::string& path,
                              const std::optional<std::string>& configJson);
    bool isDiarizationModelLoaded(jsi::Runtime& rt);
    bool unloadDiarizationModel(jsi::Runtime& rt);
    std::string diarize(jsi::Runtime& rt, const std::string& audioBase64,
                        int sampleRate, int minSpeakers, int maxSpeakers);
    void cancelDiarization(jsi::Runtime& rt);

    // ============================================================================
    // Utilities
    // ============================================================================

    std::string getLastError(jsi::Runtime& rt);
    std::string getVersion(jsi::Runtime& rt);
    bool extractArchive(jsi::Runtime& rt, const std::string& archivePath,
                        const std::string& destDir);

    // ============================================================================
    // Event System
    // ============================================================================

    void addListener(jsi::Runtime& rt, const std::string& eventName);
    void removeListeners(jsi::Runtime& rt, int count);
    std::string pollEvents(jsi::Runtime& rt);
    void clearEventQueue(jsi::Runtime& rt);

private:

    /**
     * Emit an event to JavaScript.
     * @param rt JSI runtime
     * @param eventName Name of the event
     * @param eventData JSON string with event data
     */
    void emitEvent(jsi::Runtime& rt, const std::string& eventName,
                   const std::string& eventData);

    // ============================================================================
    // Helper Methods
    // ============================================================================

    /**
     * Create a JSI function that wraps a C++ method.
     */
    template <typename Func>
    jsi::Function createFunction(jsi::Runtime& rt, const char* name, Func&& func);

    /**
     * Decode base64 audio to float32 samples.
     */
    std::vector<float> decodeBase64Audio(const std::string& base64);

    /**
     * Encode float32 audio samples to base64.
     */
    std::string encodeBase64Audio(const float* samples, size_t count);

    /**
     * Get stream handle from map.
     */
    ra_stream_handle getStreamHandle(int id);

    // ============================================================================
    // Member Variables
    // ============================================================================

    /// runanywhere-core backend handle
    ra_backend_handle backend_ = nullptr;

    /// CallInvoker for thread-safe JS calls
    std::shared_ptr<CallInvoker> jsInvoker_;

    /// Map of stream IDs to native stream handles
    std::unordered_map<int, ra_stream_handle> sttStreams_;

    /// Counter for generating unique stream IDs
    int nextStreamId_ = 1;

    /// Number of active event listeners
    int listenerCount_ = 0;

    // ============================================================================
    // Event Queue System (Thread-Safe)
    // ============================================================================

    /// Represents a pending event to emit to JavaScript
    struct PendingEvent {
        std::string eventName;
        std::string eventData;
    };

    /// Queue of events pending emission to JS (protected by mutex)
    std::vector<PendingEvent> eventQueue_;

    /// Mutex for thread-safe access to eventQueue_
    std::mutex eventQueueMutex_;
};

} // namespace facebook::react
