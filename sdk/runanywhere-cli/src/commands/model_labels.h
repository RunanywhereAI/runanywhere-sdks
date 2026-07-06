#pragma once

#include "model_types.pb.h"

namespace rcli::commands::model_labels {

namespace v1 = runanywhere::v1;

inline const char* category(v1::ModelCategory category) {
    switch (category) {
        case v1::MODEL_CATEGORY_LANGUAGE:
            return "llm";
        case v1::MODEL_CATEGORY_MULTIMODAL:
        case v1::MODEL_CATEGORY_VISION:
            return "vlm";
        case v1::MODEL_CATEGORY_SPEECH_RECOGNITION:
            return "stt";
        case v1::MODEL_CATEGORY_SPEECH_SYNTHESIS:
            return "tts";
        case v1::MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
            return "vad";
        case v1::MODEL_CATEGORY_EMBEDDING:
            return "embedding";
        case v1::MODEL_CATEGORY_IMAGE_GENERATION:
            return "diffusion";
        case v1::MODEL_CATEGORY_AUDIO:
            return "audio";
        default:
            return "?";
    }
}

inline const char* backend(v1::InferenceFramework framework) {
    switch (framework) {
        case v1::INFERENCE_FRAMEWORK_ONNX:
            return "ONNX Runtime";
        case v1::INFERENCE_FRAMEWORK_LLAMA_CPP:
            return "llama.cpp";
        case v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS:
            return "Apple Foundation";
        case v1::INFERENCE_FRAMEWORK_SYSTEM_TTS:
            return "System TTS";
        case v1::INFERENCE_FRAMEWORK_FLUID_AUDIO:
            return "Fluid Audio";
        case v1::INFERENCE_FRAMEWORK_COREML:
            return "Core ML";
        case v1::INFERENCE_FRAMEWORK_MLX:
            return "MLX";
        case v1::INFERENCE_FRAMEWORK_METALRT:
            return "MetalRT";
        case v1::INFERENCE_FRAMEWORK_GENIE:
            return "Qualcomm Genie";
        case v1::INFERENCE_FRAMEWORK_TFLITE:
            return "TensorFlow Lite";
        case v1::INFERENCE_FRAMEWORK_EXECUTORCH:
            return "ExecuTorch";
        case v1::INFERENCE_FRAMEWORK_MEDIAPIPE:
            return "MediaPipe";
        case v1::INFERENCE_FRAMEWORK_MLC:
            return "MLC";
        case v1::INFERENCE_FRAMEWORK_PICO_LLM:
            return "Pico LLM";
        case v1::INFERENCE_FRAMEWORK_PIPER_TTS:
            return "Piper TTS";
        case v1::INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS:
            return "Swift Transformers";
        case v1::INFERENCE_FRAMEWORK_BUILT_IN:
            return "Built-in";
        case v1::INFERENCE_FRAMEWORK_NONE:
            return "None";
        case v1::INFERENCE_FRAMEWORK_UNKNOWN:
            return "Unknown";
        case v1::INFERENCE_FRAMEWORK_SHERPA:
            return "Sherpa-ONNX";
        case v1::INFERENCE_FRAMEWORK_QHEXRT:
            return "QHexRT";
        case v1::INFERENCE_FRAMEWORK_UNSPECIFIED:
            return "Unspecified";
        default:
            return "?";
    }
}

}  // namespace rcli::commands::model_labels
