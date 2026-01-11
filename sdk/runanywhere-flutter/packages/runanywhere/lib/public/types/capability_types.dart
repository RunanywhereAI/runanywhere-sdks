/// Capability Types
///
/// Metadata types for loaded STT/TTS capabilities.
/// Mirrors Swift STTCapability and TTSCapability.
library capability_types;

/// Speech-to-Text capability information
class STTCapability {
  final String modelId;
  final String? modelName;

  const STTCapability({
    required this.modelId,
    this.modelName,
  });
}

/// Text-to-Speech capability information
class TTSCapability {
  final String voiceId;
  final String? voiceName;

  const TTSCapability({
    required this.voiceId,
    this.voiceName,
  });
}
