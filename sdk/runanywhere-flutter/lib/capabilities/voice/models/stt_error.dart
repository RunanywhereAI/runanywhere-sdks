/// STT Error
class STTError implements Exception {
  final String message;

  STTError(this.message);

  factory STTError.noVoiceServiceAvailable() {
    return STTError('No voice service available');
  }

  @override
  String toString() => 'STTError: $message';
}

