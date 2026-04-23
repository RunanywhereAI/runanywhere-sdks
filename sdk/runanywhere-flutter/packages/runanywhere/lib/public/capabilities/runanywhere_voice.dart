// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_voice.dart — v4 Voice Agent (STT → LLM → TTS) capability.
//
// Symmetric with the LLM capability: this class owns both the
// lifecycle surface AND a `Stream<VoiceEvent>` factory
// (`eventStream()`) that wraps `VoiceAgentStreamAdapter` internally.
//
// Advanced callers who need fine-grained control over the
// adapter (e.g. multiple fan-out subscriptions, custom handles)
// can still construct `VoiceAgentStreamAdapter(handle)` directly —
// it remains exported from `package:runanywhere/runanywhere.dart`.

import 'package:runanywhere/adapters/voice_agent_stream_adapter.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/voice_events.pb.dart' show VoiceEvent;
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
  /// models. Must be called before [eventStream] (or before manually
  /// constructing a `VoiceAgentStreamAdapter` for advanced use cases).
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

  /// Subscribe to canonical voice-agent events.
  ///
  /// Symmetric with `RunAnywhereSDK.instance.llm.generateStream(...)`:
  /// the capability owns adapter construction so callers never touch
  /// `VoiceAgentStreamAdapter` directly. The handle is fetched from
  /// the internal `DartBridgeVoiceAgent` singleton — call
  /// [initializeWithLoadedModels] first.
  ///
  /// Cancellation propagates: cancelling the returned stream's
  /// subscription tears down the underlying C-side proto callback.
  ///
  /// Advanced callers needing multiple fan-out subscriptions or a
  /// custom handle can still construct `VoiceAgentStreamAdapter`
  /// directly (exported from `package:runanywhere/runanywhere.dart`).
  Stream<VoiceEvent> eventStream() async* {
    final handle = await DartBridge.voiceAgent.getHandle();
    yield* VoiceAgentStreamAdapter(handle).stream();
  }
}
