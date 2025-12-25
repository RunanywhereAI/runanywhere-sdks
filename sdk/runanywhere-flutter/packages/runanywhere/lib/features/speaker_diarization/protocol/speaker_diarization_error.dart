/// Speaker diarization error types
/// Matches iOS SpeakerDiarizationError from Features/SpeakerDiarization/Protocol/SpeakerDiarizationError.swift
class SpeakerDiarizationError implements Exception {
  final String message;
  final SpeakerDiarizationErrorType type;

  SpeakerDiarizationError(this.message, this.type);

  factory SpeakerDiarizationError.notInitialized() {
    return SpeakerDiarizationError(
      'Speaker diarization service not initialized',
      SpeakerDiarizationErrorType.notInitialized,
    );
  }

  factory SpeakerDiarizationError.invalidMaxSpeakers(int value) {
    return SpeakerDiarizationError(
      'Invalid max speakers value: $value. Must be between 1 and 100.',
      SpeakerDiarizationErrorType.invalidMaxSpeakers,
    );
  }

  factory SpeakerDiarizationError.invalidThreshold(double value) {
    return SpeakerDiarizationError(
      'Invalid threshold value: $value. Must be between 0 and 1.',
      SpeakerDiarizationErrorType.invalidThreshold,
    );
  }

  factory SpeakerDiarizationError.invalidConfiguration(String reason) {
    return SpeakerDiarizationError(
      'Invalid configuration: $reason',
      SpeakerDiarizationErrorType.invalidConfiguration,
    );
  }

  factory SpeakerDiarizationError.processingFailed(String reason) {
    return SpeakerDiarizationError(
      'Processing failed: $reason',
      SpeakerDiarizationErrorType.processingFailed,
    );
  }

  factory SpeakerDiarizationError.speakerNotFound(String speakerId) {
    return SpeakerDiarizationError(
      'Speaker not found: $speakerId',
      SpeakerDiarizationErrorType.speakerNotFound,
    );
  }

  @override
  String toString() => 'SpeakerDiarizationError($type): $message';
}

/// Speaker diarization error types
enum SpeakerDiarizationErrorType {
  notInitialized,
  invalidMaxSpeakers,
  invalidThreshold,
  invalidConfiguration,
  processingFailed,
  speakerNotFound,
}
