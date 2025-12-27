import 'package:runanywhere/core/protocols/component/component_configuration.dart';
import 'package:runanywhere/features/tts/models/tts_options.dart';

/// Input for TTS synthesis
/// Matches iOS TTSInput from Features/TTS/Models/TTSInput.swift
class TTSInput implements ComponentInput {
  /// Text to synthesize (optional if SSML is provided)
  final String? text;

  /// Optional SSML markup (overrides text if provided)
  final String? ssml;

  /// Voice ID override
  final String? voiceId;

  /// Language override
  final String? language;

  /// Custom options override
  final TTSOptions? options;

  const TTSInput({
    this.text,
    this.ssml,
    this.voiceId,
    this.language,
    this.options,
  });

  /// Create input from plain text
  factory TTSInput.plainText(String text, {String? voiceId, String? language}) {
    return TTSInput(text: text, voiceId: voiceId, language: language);
  }

  /// Create input from SSML
  factory TTSInput.fromSSML(String ssml, {String? voiceId, String? language}) {
    return TTSInput(ssml: ssml, voiceId: voiceId, language: language);
  }

  @override
  void validate() {
    if ((text == null || text!.isEmpty) && (ssml == null || ssml!.isEmpty)) {
      throw ArgumentError('TTSInput must contain either text or SSML');
    }
  }
}
