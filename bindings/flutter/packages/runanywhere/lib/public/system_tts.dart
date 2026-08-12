// SPDX-License-Identifier: Apache-2.0
//
// system_tts.dart — Public constants for the built-in system TTS engine.
//
// Mirrors Kotlin `SystemTTSModule.MODEL_ID` and iOS `RAModelInfo.systemTTS`
// so callers no longer hard-code the `'system-tts'` magic string at the
// example layer.

/// Built-in System TTS module identifiers.
///
/// The SDK registers a synthetic `system-tts` `ModelInfo` into the proto
/// registry on every platform so the platform TTS provider (driven by C++
/// platform callbacks) participates in Model Selection alongside
/// downloadable voices. Callers that need to detect or load the built-in
/// engine should refer to [SystemTTS.modelId] rather than the literal.
abstract final class SystemTTS {
  /// Stable registry id for the built-in system TTS engine.
  ///
  /// Mirrors Kotlin `SystemTTSModule.MODEL_ID` and the literal accepted by
  /// commons `model_assignment.cpp` / `rac_backend_platform_register.cpp`.
  static const String modelId = 'system-tts';
}
