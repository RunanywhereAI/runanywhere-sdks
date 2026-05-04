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

import 'dart:typed_data';

import 'package:runanywhere/adapters/voice_agent_stream_adapter.dart';
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/vad_options.pb.dart'
    show VADConfiguration;
import 'package:runanywhere/generated/voice_agent_service.pb.dart'
    as voice_agent_proto;
import 'package:runanywhere/generated/voice_events.pb.dart' show VoiceEvent;
import 'package:runanywhere/generated/voice_events.pb.dart'
    as voice_event_proto;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';
import 'package:runanywhere/public/capabilities/runanywhere_stt.dart';
import 'package:runanywhere/public/capabilities/runanywhere_tts.dart';
import 'package:runanywhere/public/capabilities/runanywhere_vad.dart';

typedef VoiceAgentConfiguration = voice_agent_proto.VoiceAgentComposeConfig;

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
  Future<voice_event_proto.VoiceAgentComponentStates> componentStates() =>
      DartBridge.voiceAgent.componentStatesProto();

  /// Initialize the voice agent against currently-loaded STT/LLM/TTS
  /// models. Must be called before [eventStream] (or before manually
  /// constructing a `VoiceAgentStreamAdapter` for advanced use cases).
  Future<void> initializeWithLoadedModels() async {
    final logger = SDKLogger('RunAnywhere.VoiceAgent');

    if (!isReady) {
      throw SDKException.voiceAgentNotReady(
        'Voice agent components not ready. Load STT, LLM, and TTS models first.',
      );
    }

    try {
      await DartBridge.voiceAgent.initializeProto(
        voice_agent_proto.VoiceAgentComposeConfig(),
      );
      logger.info('Voice agent initialized with loaded models');
    } catch (e) {
      logger.error('Failed to initialize voice agent: $e');
      rethrow;
    }
  }

  /// Initialize the voice agent from a [VoiceAgentConfiguration]. Loads
  /// the STT/LLM/TTS models referenced by the config, optionally
  /// initializes VAD, then performs the standard handle init. Mirrors
  /// Swift's `RunAnywhere.initializeVoiceAgent(_ config:)`.
  Future<void> initializeVoiceAgent(VoiceAgentConfiguration config) async {
    final logger = SDKLogger('RunAnywhere.VoiceAgent');

    if (config.hasSttModelId()) {
      await RunAnywhereSTT.shared.load(config.sttModelId);
    }
    if (config.hasLlmModelId()) {
      await RunAnywhereLLM.shared.load(config.llmModelId);
    }
    if (config.hasTtsVoiceId()) {
      await RunAnywhereTTS.shared.loadVoice(config.ttsVoiceId);
    }
    if (config.hasVadSampleRate() ||
        config.hasVadFrameLength() ||
        config.hasVadEnergyThreshold()) {
      await RunAnywhereVAD.shared.initializeVAD(
        VADConfiguration(
          sampleRate: config.hasVadSampleRate() ? config.vadSampleRate : 16000,
          frameLengthMs: config.hasVadFrameLength()
              ? (config.vadFrameLength * 1000).round()
              : 30,
          threshold: config.hasVadEnergyThreshold()
              ? config.vadEnergyThreshold
              : 0.015,
        ),
      );
    }

    await DartBridge.voiceAgent.initializeProto(config);
    logger.info('Voice agent initialized from configuration');
  }

  /// True once the voice-agent C handle is ready. Async to allow the
  /// underlying handle bootstrap to complete. Mirrors Swift's
  /// `isVoiceAgentReady`.
  Future<bool> get isAgentReady async {
    if (!isReady) return false;
    try {
      await DartBridge.voiceAgent.getHandle();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Cleanup voice agent native resources.
  void cleanup() => DartBridge.voiceAgent.cleanup();

  /// Synchronous one-shot voice turn (audio in → triple-result out).
  /// Mirrors Swift's `processVoiceTurn(_:)`.
  Future<voice_agent_proto.VoiceAgentResult> processVoiceTurn(
    Uint8List audioData,
  ) =>
      DartBridge.voiceAgent.processVoiceTurnProto(audioData);

  /// Decomposed verb: transcribe via the voice agent. Mirrors Swift's
  /// `voiceAgentTranscribe(_:)`.
  Future<String> transcribe(Uint8List audioData) =>
      DartBridge.voiceAgent.transcribe(audioData);

  /// Decomposed verb: generate response via the voice agent. Mirrors
  /// Swift's `voiceAgentGenerateResponse(_:)`.
  Future<String> generateResponse(String prompt) =>
      DartBridge.voiceAgent.generateResponse(prompt);

  /// Decomposed verb: synthesize speech via the voice agent. Mirrors
  /// Swift's `voiceAgentSynthesizeSpeech(_:)`.
  Future<Float32List> synthesizeSpeech(String text) =>
      DartBridge.voiceAgent.synthesizeSpeech(text);

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
