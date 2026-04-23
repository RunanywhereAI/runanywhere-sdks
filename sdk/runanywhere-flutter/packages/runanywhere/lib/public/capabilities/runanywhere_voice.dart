// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_voice.dart — v4.0 Voice Agent capability instance API.

// ignore_for_file: deprecated_member_use_from_same_package
import 'package:runanywhere/public/runanywhere.dart' as legacy;

/// Voice Agent (full STT → LLM → TTS pipeline) capability surface.
///
/// Access via `RunAnywhere.instance.voice`.
///
/// Note: streaming voice events are consumed via
/// `VoiceAgentStreamAdapter(handle).stream()` (see the runanywhere
/// package barrel exports). This class only manages the lifecycle.
class RunAnywhereVoice {
  RunAnywhereVoice._();
  static final RunAnywhereVoice _instance = RunAnywhereVoice._();
  static RunAnywhereVoice get shared => _instance;

  /// True when STT + LLM + TTS are all loaded + voice agent is initialized.
  bool get isReady => legacy.RunAnywhere.isVoiceAgentReady;

  /// Initialize the voice agent against currently-loaded STT/LLM/TTS models.
  /// Call BEFORE `DartBridgeVoiceAgent.shared.getHandle()` +
  /// `VoiceAgentStreamAdapter(handle).stream()`.
  Future<void> initializeWithLoadedModels() =>
      legacy.RunAnywhere.initializeVoiceAgentWithLoadedModels();

  /// Cleanup voice agent native resources.
  void cleanup() => legacy.RunAnywhere.cleanupVoiceAgent();
}
