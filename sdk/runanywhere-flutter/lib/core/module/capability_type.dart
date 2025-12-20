//
// capability_type.dart
// RunAnywhere Flutter SDK
//
// Types of capabilities that modules can provide.
// Matches iOS CapabilityType from Core/Module/RunAnywhereModule.swift
//

/// Types of capabilities that modules can provide.
///
/// These represent the core AI capabilities exposed by the SDK.
/// Modules register with specific capability types to indicate what services they provide.
enum CapabilityType {
  /// Speech-to-Text capability
  stt('STT'),

  /// Text-to-Speech capability
  tts('TTS'),

  /// Large Language Model capability
  llm('LLM'),

  /// Voice Activity Detection capability
  vad('VAD'),

  /// Speaker Diarization capability
  speakerDiarization('SpeakerDiarization');

  /// Raw string value for serialization (matches iOS rawValue)
  final String rawValue;

  const CapabilityType(this.rawValue);

  /// Create from raw string value
  static CapabilityType? fromRawValue(String value) {
    for (final type in CapabilityType.values) {
      if (type.rawValue == value) {
        return type;
      }
    }
    return null;
  }
}
