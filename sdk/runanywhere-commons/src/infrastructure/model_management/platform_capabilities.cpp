/**
 * @file platform_capabilities.cpp
 * @brief Compile-time platform capability matrix for inference frameworks.
 *
 * See rac_platform_capabilities.h for the canonical matrix documentation.
 */

#include "rac/infrastructure/model_management/rac_platform_capabilities.h"

#ifdef RAC_HAVE_PROTOBUF
#include "model_types.pb.h"
#endif

namespace {

// Wire values of runanywhere.v1.InferenceFramework (idl/model_types.proto).
// Kept as plain constants so the boundary also works in non-protobuf builds;
// the static_asserts below pin them to the generated enum when available.
constexpr int32_t kFrameworkFoundationModels = 3;
constexpr int32_t kFrameworkFluidAudio = 5;
constexpr int32_t kFrameworkCoreML = 6;
constexpr int32_t kFrameworkMLX = 7;
constexpr int32_t kFrameworkSwiftTransformers = 19;
constexpr int32_t kFrameworkQHexRT = 24;

#ifdef RAC_HAVE_PROTOBUF
static_assert(kFrameworkFoundationModels == runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS);
static_assert(kFrameworkFluidAudio == runanywhere::v1::INFERENCE_FRAMEWORK_FLUID_AUDIO);
static_assert(kFrameworkCoreML == runanywhere::v1::INFERENCE_FRAMEWORK_COREML);
static_assert(kFrameworkMLX == runanywhere::v1::INFERENCE_FRAMEWORK_MLX);
static_assert(kFrameworkSwiftTransformers ==
              runanywhere::v1::INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS);
static_assert(kFrameworkQHexRT == runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT);
#endif

}  // namespace

rac_bool_t rac_framework_supported_on_platform(int32_t inference_framework) {
    switch (inference_framework) {
        // Apple-only frameworks: available on Apple targets (iOS/macOS/...),
        // excluded on Android, WASM/Emscripten, desktop Linux, and Windows.
        case kFrameworkFoundationModels:
        case kFrameworkFluidAudio:
        case kFrameworkCoreML:
        case kFrameworkMLX:
        case kFrameworkSwiftTransformers:
#if defined(__APPLE__)
            return RAC_TRUE;
#else
            return RAC_FALSE;
#endif

        // Qualcomm Hexagon NPU runtime: Android-only.
        case kFrameworkQHexRT:
#if defined(__ANDROID__)
            return RAC_TRUE;
#else
            return RAC_FALSE;
#endif

        // Everything else (LLAMA_CPP, ONNX, SHERPA, SYSTEM_TTS, BUILT_IN,
        // cloud, unknown/unspecified, future values) is unrestricted.
        default:
            return RAC_TRUE;
    }
}
