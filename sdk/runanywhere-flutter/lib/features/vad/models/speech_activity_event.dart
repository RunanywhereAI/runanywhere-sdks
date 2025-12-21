/// Events representing speech activity state changes
/// Matches iOS SpeechActivityEvent from Features/VAD/Models/SpeechActivityEvent.swift
enum SpeechActivityEvent {
  /// Speech has started
  started,

  /// Speech has ended
  ended;

  /// Get string representation
  String get value {
    switch (this) {
      case SpeechActivityEvent.started:
        return 'started';
      case SpeechActivityEvent.ended:
        return 'ended';
    }
  }

  /// Create from string
  static SpeechActivityEvent? fromValue(String value) {
    switch (value.toLowerCase()) {
      case 'started':
        return SpeechActivityEvent.started;
      case 'ended':
        return SpeechActivityEvent.ended;
      default:
        return null;
    }
  }
}
