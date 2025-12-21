/// Input for TTS synthesis
/// Matches iOS TTSInput from Features/TTS/Models/TTSInput.swift
class TTSInput {
  /// Text to synthesize
  final String text;

  /// Optional SSML markup
  final String? ssml;

  /// Voice override for this input
  final String? voice;

  /// Rate override for this input
  final double? rate;

  /// Pitch override for this input
  final double? pitch;

  const TTSInput({
    required this.text,
    this.ssml,
    this.voice,
    this.rate,
    this.pitch,
  });

  /// Create input from plain text
  factory TTSInput.plainText(String text) {
    return TTSInput(text: text);
  }

  /// Create input from SSML
  factory TTSInput.fromSSML(String ssml) {
    return TTSInput(text: '', ssml: ssml);
  }

  /// Validate the input
  void validate() {
    if (text.isEmpty && (ssml == null || ssml!.isEmpty)) {
      throw ArgumentError('Either text or SSML must be provided');
    }
  }
}
