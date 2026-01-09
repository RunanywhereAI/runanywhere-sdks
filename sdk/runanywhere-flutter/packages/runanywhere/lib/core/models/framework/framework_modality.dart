/// Framework Modality
///
/// Defines the input/output modality of a framework capability.
library framework_modality;

/// Framework modality types
enum FrameworkModality {
  textToText('text_to_text', 'Text to Text'),
  textToSpeech('text_to_speech', 'Text to Speech'),
  speechToText('speech_to_text', 'Speech to Text'),
  imageToText('image_to_text', 'Image to Text'),
  textToImage('text_to_image', 'Text to Image'),
  audioProcessing('audio_processing', 'Audio Processing');

  final String rawValue;
  final String displayName;

  const FrameworkModality(this.rawValue, this.displayName);

  /// Create from raw string value
  static FrameworkModality fromRawValue(String value) {
    final lowercased = value.toLowerCase();
    return FrameworkModality.values.firstWhere(
      (m) => m.rawValue == lowercased,
      orElse: () => FrameworkModality.textToText,
    );
  }
}
