/// Represents the different modalities (capabilities) a framework can support.
///
/// This is the Flutter equivalent of Swift's `FrameworkModality`.
enum FrameworkModality {
  /// Speech-to-text (STT) - voice input to text output
  voiceToText('voice_to_text'),

  /// Text-to-speech (TTS) - text input to voice output
  textToVoice('text_to_voice'),

  /// Text-to-text (LLM) - text generation
  textToText('text_to_text'),

  /// Vision-to-text (VLM) - image input to text output
  visionToText('vision_to_text'),

  /// Image-to-text - image understanding
  imageToText('image_to_text'),

  /// Text-to-image - image generation
  textToImage('text_to_image'),

  /// Multimodal - multiple input/output types
  multimodal('multimodal'),

  /// Voice activity detection (VAD)
  voiceActivityDetection('voice_activity_detection'),

  /// Speaker diarization - identify who is speaking
  speakerDiarization('speaker_diarization'),

  /// Wake word detection
  wakeWord('wake_word'),

  /// Text embeddings
  textEmbedding('text_embedding');

  const FrameworkModality(this.rawValue);

  /// The string representation of this modality.
  final String rawValue;

  /// Create from raw value string.
  static FrameworkModality? fromRawValue(String value) {
    for (final modality in values) {
      if (modality.rawValue == value) {
        return modality;
      }
    }
    return null;
  }
}
