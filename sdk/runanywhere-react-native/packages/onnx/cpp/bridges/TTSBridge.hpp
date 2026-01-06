/**
 * @file TTSBridge.hpp
 * @brief TTS (Text-to-Speech) capability bridge for React Native
 *
 * Matches Swift's CppBridge+TTS.swift pattern, providing:
 * - Model lifecycle (load/unload)
 * - Speech synthesis
 *
 * Aligned with rac_tts_component.h and rac_tts_types.h API.
 * RACommons is REQUIRED - no stub implementations.
 */

#pragma once

#include <functional>
#include <memory>
#include <string>
#include <vector>

// RACommons TTS headers - REQUIRED
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_types.h"

namespace runanywhere {
namespace bridges {

/**
 * @brief TTS synthesis result
 */
struct TTSResult {
    std::vector<float> audioData;
    int sampleRate = 22050;
    double durationMs = 0.0;
};

/**
 * @brief TTS synthesis options
 */
struct TTSOptions {
    std::string voiceId;
    float speed = 1.0f;
    float pitch = 1.0f;
    int sampleRate = 22050;
};

/**
 * @brief TTS capability bridge singleton
 *
 * Matches CppBridge+TTS.swift API.
 * NOTE: RACommons is REQUIRED. All methods will throw std::runtime_error if
 * the underlying C API calls fail.
 */
class TTSBridge {
public:
    static TTSBridge& shared();

    // Lifecycle
    bool isLoaded() const;
    std::string currentModelId() const;
    rac_result_t loadModel(const std::string& modelId);
    rac_result_t unload();
    void cleanup();

    // Synthesis
    TTSResult synthesize(const std::string& text, const TTSOptions& options);

private:
    TTSBridge();
    ~TTSBridge();

    // Disable copy/move
    TTSBridge(const TTSBridge&) = delete;
    TTSBridge& operator=(const TTSBridge&) = delete;

    rac_handle_t handle_ = nullptr;
    std::string loadedModelId_;
};

} // namespace bridges
} // namespace runanywhere
