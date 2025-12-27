/// SDK component types
enum SDKComponent {
  /// Speech-to-Text component
  stt,

  /// Text-to-Speech component
  tts,

  /// Language Model component
  llm,

  /// Voice Activity Detection component
  vad,

  /// Voice Agent component
  voiceAgent,

  /// Speaker Diarization component
  speakerDiarization,

  /// Vision Language Model component
  vlm,
}

extension SDKComponentExtension on SDKComponent {
  /// Get string representation
  String get value {
    switch (this) {
      case SDKComponent.stt:
        return 'stt';
      case SDKComponent.tts:
        return 'tts';
      case SDKComponent.llm:
        return 'llm';
      case SDKComponent.vad:
        return 'vad';
      case SDKComponent.voiceAgent:
        return 'voice_agent';
      case SDKComponent.speakerDiarization:
        return 'speaker_diarization';
      case SDKComponent.vlm:
        return 'vlm';
    }
  }
}
