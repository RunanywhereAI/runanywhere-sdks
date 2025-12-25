/// TTS error types
/// Matches iOS TTSError from Features/TTS/Protocol/TTSError.swift
class TTSError implements Exception {
  final String message;
  final TTSErrorType type;

  TTSError(this.message, this.type);

  factory TTSError.synthesizeFailed(String reason) {
    return TTSError('Synthesis failed: $reason', TTSErrorType.synthesizeFailed);
  }

  factory TTSError.voiceNotAvailable(String voiceId) {
    return TTSError(
        'Voice not available: $voiceId', TTSErrorType.voiceNotAvailable);
  }

  factory TTSError.invalidInput(String reason) {
    return TTSError('Invalid input: $reason', TTSErrorType.invalidInput);
  }

  factory TTSError.modelNotLoaded() {
    return TTSError('TTS model not loaded', TTSErrorType.modelNotLoaded);
  }

  factory TTSError.playbackFailed(String reason) {
    return TTSError('Playback failed: $reason', TTSErrorType.playbackFailed);
  }

  factory TTSError.cancelled() {
    return TTSError('TTS operation cancelled', TTSErrorType.cancelled);
  }

  @override
  String toString() => 'TTSError($type): $message';
}

/// TTS error types
enum TTSErrorType {
  synthesizeFailed,
  voiceNotAvailable,
  invalidInput,
  modelNotLoaded,
  playbackFailed,
  cancelled,
}
