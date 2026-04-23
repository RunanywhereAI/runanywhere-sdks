// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_voice.dart — v4 Voice Agent (STT → LLM → TTS) capability.
//
// Streaming voice events are still consumed via
// `VoiceAgentStreamAdapter(handle).stream()` (see the runanywhere
// package barrel). This class manages the lifecycle only.

import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/public/types/voice_agent_types.dart';

/// Voice Agent capability surface.
///
/// Access via `RunAnywhereSDK.instance.voice`.
class RunAnywhereVoice {
  RunAnywhereVoice._();
  static final RunAnywhereVoice _instance = RunAnywhereVoice._();
  static RunAnywhereVoice get shared => _instance;

  /// True when STT + LLM + TTS are all loaded.
  bool get isReady =>
      DartBridge.stt.isLoaded &&
      DartBridge.llm.isLoaded &&
      DartBridge.tts.isLoaded;

  /// Snapshot of STT/LLM/TTS load state — useful to surface readiness
  /// in voice-agent UI without firing off three separate getters.
  VoiceAgentComponentStates componentStates() {
    final sttId = DartBridge.stt.currentModelId;
    final llmId = DartBridge.llm.currentModelId;
    final ttsId = DartBridge.tts.currentVoiceId;

    return VoiceAgentComponentStates(
      stt: sttId != null
          ? ComponentLoadState.loaded(modelId: sttId)
          : const ComponentLoadState.notLoaded(),
      llm: llmId != null
          ? ComponentLoadState.loaded(modelId: llmId)
          : const ComponentLoadState.notLoaded(),
      tts: ttsId != null
          ? ComponentLoadState.loaded(modelId: ttsId)
          : const ComponentLoadState.notLoaded(),
    );
  }

  /// Initialize the voice agent against currently-loaded STT/LLM/TTS
  /// models. Call BEFORE `DartBridgeVoiceAgent.shared.getHandle()` +
  /// `VoiceAgentStreamAdapter(handle).stream()`.
  Future<void> initializeWithLoadedModels() async {
    final logger = SDKLogger('RunAnywhere.VoiceAgent');

    if (!isReady) {
      throw SDKError.voiceAgentNotReady(
        'Voice agent components not ready. Load STT, LLM, and TTS models first.',
      );
    }

    try {
      await DartBridge.voiceAgent.initializeWithLoadedModels();
      logger.info('Voice agent initialized with loaded models');
    } catch (e) {
      logger.error('Failed to initialize voice agent: $e');
      rethrow;
    }
  }

  /// Cleanup voice agent native resources.
  void cleanup() => DartBridge.voiceAgent.cleanup();
}
