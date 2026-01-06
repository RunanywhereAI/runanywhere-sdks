/**
 * @file VADBridge.hpp
 * @brief VAD (Voice Activity Detection) capability bridge for React Native
 *
 * Matches Swift's CppBridge+VAD.swift pattern, providing:
 * - Model lifecycle (load/unload)
 * - Voice activity detection
 *
 * Aligned with rac_vad_component.h and rac_vad_types.h API.
 * RACommons is REQUIRED - no stub implementations.
 */

#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

// RACommons VAD headers - REQUIRED
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_types.h"

namespace runanywhere {
namespace bridges {

/**
 * @brief VAD detection result
 */
struct VADResult {
    bool isSpeech = false;
    float probability = 0.0f;
    float speechProbability = 0.0f;  // Alias for probability (for API compatibility)
    double durationMs = 0.0;
    double startTime = 0.0;          // Start time of speech segment (ms)
    double endTime = 0.0;            // End time of speech segment (ms)
};

/**
 * @brief VAD processing options
 */
struct VADOptions {
    float threshold = 0.5f;
    int windowSizeMs = 30;
    int sampleRate = 16000;
};

/**
 * @brief VAD capability bridge singleton
 *
 * Matches CppBridge+VAD.swift API.
 * NOTE: RACommons is REQUIRED. All methods will throw std::runtime_error if
 * the underlying C API calls fail.
 */
class VADBridge {
public:
    static VADBridge& shared();

    // Lifecycle
    bool isLoaded() const;
    std::string currentModelId() const;
    rac_result_t loadModel(const std::string& modelId);
    rac_result_t unload();
    void cleanup();
    void reset();  // Reset VAD state without unloading model

    // Detection
    VADResult process(const void* audioData, size_t audioSize, const VADOptions& options);

private:
    VADBridge();
    ~VADBridge();

    // Disable copy/move
    VADBridge(const VADBridge&) = delete;
    VADBridge& operator=(const VADBridge&) = delete;

    rac_handle_t handle_ = nullptr;
    std::string loadedModelId_;
};

} // namespace bridges
} // namespace runanywhere
