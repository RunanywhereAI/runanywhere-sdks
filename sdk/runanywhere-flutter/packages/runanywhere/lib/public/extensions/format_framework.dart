// SPDX-License-Identifier: Apache-2.0
//
// format_framework.dart — human-readable display name for InferenceFramework.
//
// Pure-Dart proxy for the canonical `rac_inference_framework_display_name` C
// ABI mapping in runanywhere-commons (model_types.cpp). The C string table is
// not exposed through the proto bridge — it would cost a Dart↔native FFI call
// for a static label. Mirror the exact same table in Dart so consumers (UI
// banners, status labels) can resolve a human-readable display name
// synchronously.
//
// The mapping is the source-of-truth pair with:
//   • RN:    `@runanywhere/core/Public/Helpers/formatFramework.ts`
//   • Web:   `@runanywhere/core/Public/Helpers/formatFramework.ts`
//   • Swift: `RAInferenceFramework.displayName` (ModelTypes.swift)
//
// Keep in lock-step with commons when a new framework is added.

import 'package:runanywhere/generated/model_types.pbenum.dart';

const Map<InferenceFramework, String> _kFrameworkDisplayNames = {
  InferenceFramework.INFERENCE_FRAMEWORK_ONNX: 'ONNX Runtime',
  InferenceFramework.INFERENCE_FRAMEWORK_SHERPA: 'Sherpa-ONNX',
  InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP: 'llama.cpp',
  InferenceFramework.INFERENCE_FRAMEWORK_COREML: 'Core ML',
  InferenceFramework.INFERENCE_FRAMEWORK_MLX: 'MLX',
  InferenceFramework.INFERENCE_FRAMEWORK_FOUNDATION_MODELS: 'Foundation Models',
  InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS: 'System TTS',
  InferenceFramework.INFERENCE_FRAMEWORK_FLUID_AUDIO: 'FluidAudio',
  InferenceFramework.INFERENCE_FRAMEWORK_METALRT: 'MetalRT',
  InferenceFramework.INFERENCE_FRAMEWORK_GENIE: 'Qualcomm Genie',
  InferenceFramework.INFERENCE_FRAMEWORK_TFLITE: 'TensorFlow Lite',
  InferenceFramework.INFERENCE_FRAMEWORK_EXECUTORCH: 'ExecuTorch',
  InferenceFramework.INFERENCE_FRAMEWORK_MEDIAPIPE: 'MediaPipe',
  InferenceFramework.INFERENCE_FRAMEWORK_MLC: 'MLC',
  InferenceFramework.INFERENCE_FRAMEWORK_PICO_LLM: 'picoLLM',
  InferenceFramework.INFERENCE_FRAMEWORK_PIPER_TTS: 'Piper TTS',
  InferenceFramework.INFERENCE_FRAMEWORK_SWIFT_TRANSFORMERS:
      'Swift Transformers',
  InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN: 'Built-in',
  InferenceFramework.INFERENCE_FRAMEWORK_NONE: 'None',
};

/// Return the canonical human-readable display name for an [InferenceFramework].
///
/// Mirrors `rac_inference_framework_display_name` from commons
/// (model_types.cpp) so cross-platform UIs render the same label without each
/// app maintaining its own switch table.
///
/// Unknown / unspecified values resolve to `"Unknown"` to match the C default
/// branch, mirroring RN/Web `formatFramework` and Swift
/// `RAInferenceFramework.displayName`.
String formatFramework(InferenceFramework? framework) {
  if (framework == null ||
      framework == InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED ||
      framework == InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN) {
    return 'Unknown';
  }
  return _kFrameworkDisplayNames[framework] ?? 'Unknown';
}
