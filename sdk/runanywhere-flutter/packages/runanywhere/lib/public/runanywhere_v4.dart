// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_v4.dart — v4.0 RunAnywhere singleton entry point.
//
// New API shape per docs/migrations/v3_to_v4_flutter.md. Replaces the
// 2,607-LOC `RunAnywhere` god-class (which stays as a deprecated
// forwarding shim during the v4.0.x window; deleted in v4.1).
//
// Usage:
//   final ra = RunAnywhereSDK.instance;
//   await ra.initialize(environment: SDKEnvironment.development);
//   await ra.llm.load('llama-3-8b');
//   final response = await ra.llm.chat('Hello!');
//
// During v4.0.x, the legacy static API still works:
//   await RunAnywhere.initialize(...);   // @Deprecated → forwards to instance
//   await RunAnywhere.loadModel(...);    // @Deprecated → forwards to instance.llm.load
//
// The legacy shim emits @Deprecated warnings via the analyzer; v4.1
// removes the static surface entirely.

// ignore_for_file: deprecated_member_use_from_same_package
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/runanywhere.dart' as legacy;

import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/capabilities/runanywhere_stt.dart';
import 'package:runanywhere/public/capabilities/runanywhere_tts.dart';
import 'package:runanywhere/public/capabilities/runanywhere_vlm.dart';
import 'package:runanywhere/public/capabilities/runanywhere_voice.dart';

/// v4.0 RunAnywhere SDK entry point.
///
/// Singleton; access via [RunAnywhereSDK.instance]. Capability surfaces
/// are exposed as instance properties (e.g. `instance.llm`,
/// `instance.stt`). Each capability is a separate class under
/// `lib/public/capabilities/`.
///
/// During the v4.0.x deprecation window, the legacy `RunAnywhere`
/// static class also works (forwarders to this singleton). v4.1
/// deletes the static surface entirely.
class RunAnywhereSDK {
  RunAnywhereSDK._();

  /// Single shared instance.
  static final RunAnywhereSDK instance = RunAnywhereSDK._();

  // --- Lifecycle -----------------------------------------------------------

  /// True after [initialize] has succeeded.
  bool get isInitialized => legacy.RunAnywhere.isSDKInitialized;

  /// Initialization params (apiKey, baseURL, environment) — null until
  /// [initialize] runs.
  legacy.SDKInitParams? get initParams => legacy.RunAnywhere.initParams;

  /// Current SDK environment (development / staging / production).
  SDKEnvironment? get environment => legacy.RunAnywhere.environment;

  /// SDK semver string (e.g. "4.0.0").
  String get version => legacy.RunAnywhere.version;

  /// Event bus for cross-capability SDK events.
  EventBus get events => legacy.RunAnywhere.events;

  /// Initialize the SDK with API key + base URL.
  Future<void> initialize({
    String? apiKey,
    String? baseURL,
    SDKEnvironment environment = SDKEnvironment.development,
  }) =>
      legacy.RunAnywhere.initialize(
        apiKey: apiKey,
        baseURL: baseURL,
        environment: environment,
      );

  /// Reset all SDK state; clears registered models, cached configuration,
  /// loaded backends. Useful for tests.
  Future<void> reset() => legacy.RunAnywhere.reset();

  // --- Capability surfaces (lazy) ------------------------------------------

  /// LLM (text generation) — load, chat, generate, generate-stream, cancel.
  RunAnywhereLLM get llm => RunAnywhereLLM.shared;

  /// STT (speech-to-text) — load, transcribe.
  RunAnywhereSTT get stt => RunAnywhereSTT.shared;

  /// TTS (text-to-speech) — load voice, synthesize.
  RunAnywhereTTS get tts => RunAnywhereTTS.shared;

  /// VLM (vision-language model) — load, processImage, processImageStream,
  /// describe, askAbout.
  RunAnywhereVLM get vlm => RunAnywhereVLM.shared;

  /// Voice Agent (full STT → LLM → TTS pipeline) — initialize, cleanup,
  /// isReady. For streaming, use VoiceAgentStreamAdapter.
  RunAnywhereVoice get voice => RunAnywhereVoice.shared;

  /// Models registry — list available, refresh from remote.
  RunAnywhereModels get models => RunAnywhereModels.shared;

  /// Downloads — start, delete, storage info, list downloaded.
  RunAnywhereDownloads get downloads => RunAnywhereDownloads.shared;
}
