/**
 * @file VADBridge.hpp
 * @brief VAD (Voice Activity Detection) capability bridge for React Native
 *
 * Matches Swift's CppBridge+VAD.swift pattern, providing:
 * - Model lifecycle (load/unload)
 * - Voice activity detection
 */

#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

#ifdef HAS_RACOMMONS
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_types.h"
#else
typedef void* rac_handle_t;
typedef int rac_result_t;
#define RAC_SUCCESS 0
#endif

namespace runanywhere {
namespace bridges {

/**
 * @brief VAD detection result
 */
struct VADResult {
    bool isSpeech = false;
    float probability = 0.0f;
    double durationMs = 0.0;
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
