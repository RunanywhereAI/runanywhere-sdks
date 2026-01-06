/**
 * @file STTBridge.hpp
 * @brief STT (Speech-to-Text) capability bridge for React Native
 *
 * Matches Swift's CppBridge+STT.swift pattern, providing:
 * - Model lifecycle (load/unload)
 * - Transcription (batch and streaming)
 */

#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

#ifdef HAS_RACOMMONS
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_types.h"
#else
typedef void* rac_handle_t;
typedef int rac_result_t;
#define RAC_SUCCESS 0
#endif

namespace runanywhere {
namespace bridges {

/**
 * @brief STT transcription result
 */
struct STTResult {
    std::string text;
    double durationMs = 0.0;
    double confidence = 0.0;
    bool isFinal = true;
};

/**
 * @brief STT transcription options
 */
struct STTOptions {
    std::string language = "en";
    bool enableTimestamps = false;
    bool enablePunctuation = true;
};

/**
 * @brief STT streaming callbacks
 */
struct STTStreamCallbacks {
    std::function<void(const STTResult&)> onPartialResult;
    std::function<void(const STTResult&)> onFinalResult;
    std::function<void(int, const std::string&)> onError;
};

/**
 * @brief STT capability bridge singleton
 *
 * Matches CppBridge+STT.swift API.
 */
class STTBridge {
public:
    static STTBridge& shared();

    // Lifecycle
    bool isLoaded() const;
    std::string currentModelId() const;
    rac_result_t loadModel(const std::string& modelId);
    rac_result_t unload();
    void cleanup();

    // Transcription
    STTResult transcribe(const void* audioData, size_t audioSize,
                         const STTOptions& options);

    void transcribeStream(const void* audioData, size_t audioSize,
                          const STTOptions& options,
                          const STTStreamCallbacks& callbacks);

private:
    STTBridge();
    ~STTBridge();

    // Disable copy/move
    STTBridge(const STTBridge&) = delete;
    STTBridge& operator=(const STTBridge&) = delete;

    rac_handle_t handle_ = nullptr;
    std::string loadedModelId_;
};

} // namespace bridges
} // namespace runanywhere
