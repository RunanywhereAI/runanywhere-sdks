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
import 'package:runanywhere/features/vad/vad_configuration.dart' show VADComponentConfig;
import 'package:runanywhere/foundation/error_types/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/voice_events.pb.dart' show VoiceEvent;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_voice_agent.dart'
    show VoiceTurnResult;
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';
import 'package:runanywhere/public/capabilities/runanywhere_stt.dart';
import 'package:runanywhere/public/capabilities/runanywhere_tts.dart';
import 'package:runanywhere/public/capabilities/runanywhere_vad.dart';

/// Snapshot of STT / LLM / TTS readiness for the voice agent.
class VoiceAgentComponentStates {
  /// True if an STT model is loaded.
  final bool sttLoaded;

  /// Currently-loaded STT model id (or null).
  final String? sttModelId;

  /// True if an LLM model is loaded.
  final bool llmLoaded;

  /// Currently-loaded LLM model id (or null).
  final String? llmModelId;

  /// True if a TTS voice is loaded.
  final bool ttsLoaded;

  /// Currently-loaded TTS voice id (or null).
  final String? ttsVoiceId;

  const VoiceAgentComponentStates({
    required this.sttLoaded,
    this.sttModelId,
    required this.llmLoaded,
    this.llmModelId,
    required this.ttsLoaded,
    this.ttsVoiceId,
  });

  bool get isFullyReady => sttLoaded && llmLoaded && ttsLoaded;

  bool get hasAnyLoaded => sttLoaded || llmLoaded || ttsLoaded;

  List<String> get missingComponents {
    final missing = <String>[];
    if (!sttLoaded) missing.add('stt');
    if (!llmLoaded) missing.add('llm');
    if (!ttsLoaded) missing.add('tts');
    return missing;
  }
}

/// Voice-agent configuration for the config-driven init path. Mirrors
/// Swift's `VoiceAgentConfiguration`.
class VoiceAgentConfiguration {
  /// STT model id to load before initializing the agent.
  final String? sttModelId;

  /// LLM model id to load before initializing the agent.
  final String? llmModelId;

  /// TTS voice id to load before initializing the agent.
  final String? ttsVoiceId;

  /// VAD configuration. When supplied, VAD is initialized before the
  /// agent starts processing audio.
  final VADComponentConfig? vadConfig;

  const VoiceAgentConfiguration({
    this.sttModelId,
    this.llmModelId,
    this.ttsVoiceId,
    this.vadConfig,
  });
}

/// Result of a synchronous voice-turn (audio in → transcript + response
/// + synthesized audio). Mirrors Swift's `VoiceAgentResult`.
class VoiceAgentResult {
  /// Transcribed user speech.
  final String transcription;

  /// Generated LLM response text.
  final String response;

  /// Synthesized response audio (WAV-encoded).
  final Uint8List audioWavData;

  /// Per-stage durations for telemetry / UI.
  final int sttDurationMs;
  final int llmDurationMs;
  final int ttsDurationMs;

  const VoiceAgentResult({
    required this.transcription,
    required this.response,
    required this.audioWavData,
    this.sttDurationMs = 0,
    this.llmDurationMs = 0,
    this.ttsDurationMs = 0,
  });

  int get totalDurationMs => sttDurationMs + llmDurationMs + ttsDurationMs;

  /// Build from the bridge-level [VoiceTurnResult].
  factory VoiceAgentResult.from(VoiceTurnResult result) {
    return VoiceAgentResult(
      transcription: result.transcription,
      response: result.response,
      audioWavData: result.audioWavData,
      sttDurationMs: result.sttDurationMs,
      llmDurationMs: result.llmDurationMs,
      ttsDurationMs: result.ttsDurationMs,
    );
  }
}

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
    return VoiceAgentComponentStates(
      sttLoaded: DartBridge.stt.isLoaded,
      sttModelId: DartBridge.stt.currentModelId,
      llmLoaded: DartBridge.llm.isLoaded,
      llmModelId: DartBridge.llm.currentModelId,
      ttsLoaded: DartBridge.tts.isLoaded,
      ttsVoiceId: DartBridge.tts.currentVoiceId,
    );
  }

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
      await DartBridge.voiceAgent.initializeWithLoadedModels();
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

    if (config.sttModelId != null) {
      await RunAnywhereSTT.shared.load(config.sttModelId!);
    }
    if (config.llmModelId != null) {
      await RunAnywhereLLM.shared.load(config.llmModelId!);
    }
    if (config.ttsVoiceId != null) {
      await RunAnywhereTTS.shared.loadVoice(config.ttsVoiceId!);
    }
    if (config.vadConfig != null) {
      await RunAnywhereVAD.shared.initializeVAD(config.vadConfig);
    }

    await initializeWithLoadedModels();
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
  Future<VoiceAgentResult> processVoiceTurn(Uint8List audioData) async {
    final result = await DartBridge.voiceAgent.processVoiceTurn(audioData);
    return VoiceAgentResult.from(result);
  }

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
