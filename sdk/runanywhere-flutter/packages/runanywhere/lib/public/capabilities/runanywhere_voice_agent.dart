// SPDX-License-Identifier: Apache-2.0
//
// Wave 2: VoiceAgent namespace extension. Mirrors Swift's
// `RunAnywhere.VoiceAgent` aggregator for the orchestration surface.
// Re-exposes the existing `RunAnywhereVoice` capability methods under a
// VoiceAgent-themed name for parity with Swift / Kotlin.

import 'dart:typed_data';

import 'package:runanywhere/adapters/voice_agent_stream_adapter.dart';
import 'package:runanywhere/generated/voice_events.pb.dart' show VoiceEvent;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/public/capabilities/runanywhere_voice.dart';

/// Voice Agent capability surface (parity with Swift `RunAnywhere.VoiceAgent`).
///
/// Access via `RunAnywhereSDK.instance.voiceAgent`. Wraps the existing
/// [RunAnywhereVoice] singleton with VoiceAgent-themed aliases so apps
/// can write `instance.voiceAgent.processVoiceTurn(...)` / etc.
class RunAnywhereVoiceAgent {
  RunAnywhereVoiceAgent._();
  static final RunAnywhereVoiceAgent _instance = RunAnywhereVoiceAgent._();
  static RunAnywhereVoiceAgent get shared => _instance;

  /// True when STT + LLM + TTS are all loaded.
  bool get isReady => RunAnywhereVoice.shared.isReady;

  /// Component readiness snapshot.
  VoiceAgentComponentStates componentStates() =>
      RunAnywhereVoice.shared.componentStates();

  /// Initialize against currently-loaded STT/LLM/TTS models.
  Future<void> initializeWithLoadedModels() =>
      RunAnywhereVoice.shared.initializeWithLoadedModels();

  /// Initialize from a [VoiceAgentConfiguration].
  Future<void> initialize(VoiceAgentConfiguration config) =>
      RunAnywhereVoice.shared.initializeVoiceAgent(config);

  /// Cleanup voice agent native resources.
  void cleanup() => RunAnywhereVoice.shared.cleanup();

  /// Synchronous voice turn (audio in → triple-result out).
  Future<VoiceAgentResult> processVoiceTurn(Uint8List audioData) =>
      RunAnywhereVoice.shared.processVoiceTurn(audioData);

  /// Subscribe to canonical VoiceAgent proto events.
  Stream<VoiceEvent> eventStream() async* {
    final handle = await DartBridge.voiceAgent.getHandle();
    yield* VoiceAgentStreamAdapter(handle).stream();
  }
}
