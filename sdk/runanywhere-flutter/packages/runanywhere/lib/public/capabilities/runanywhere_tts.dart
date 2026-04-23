// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_tts.dart — v4.0 TTS capability instance API.

// ignore_for_file: deprecated_member_use_from_same_package
import 'package:runanywhere/public/runanywhere.dart' as legacy;
import 'package:runanywhere/public/types/types.dart';

/// TTS (text-to-speech) capability surface.
///
/// Access via `RunAnywhere.instance.tts`.
class RunAnywhereTTS {
  RunAnywhereTTS._();
  static final RunAnywhereTTS _instance = RunAnywhereTTS._();
  static RunAnywhereTTS get shared => _instance;

  /// True when a TTS voice is currently loaded.
  bool get isLoaded => legacy.RunAnywhere.isTTSVoiceLoaded;

  /// Currently-loaded TTS voice ID, or null.
  String? get currentVoiceId => legacy.RunAnywhere.currentTTSVoiceId;

  /// Currently-loaded TTS voice as `ModelInfo`, or null.
  Future<ModelInfo?> currentVoice() => legacy.RunAnywhere.currentTTSVoice();

  /// Load a TTS voice by ID.
  Future<void> loadVoice(String voiceId) =>
      legacy.RunAnywhere.loadTTSVoice(voiceId);

  /// Unload the currently-loaded TTS voice.
  Future<void> unloadVoice() => legacy.RunAnywhere.unloadTTSVoice();

  /// Synthesize text to audio.
  Future<TTSResult> synthesize(
    String text, {
    TTSOptions? options,
  }) =>
      legacy.RunAnywhere.synthesize(text, options: options);
}
