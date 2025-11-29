import 'dart:async';

/// Base protocol for VAD (Voice Activity Detection) services
abstract class VADService {
  /// Energy threshold for voice detection
  double get energyThreshold;
  set energyThreshold(double value);

  /// Sample rate of the audio
  int get sampleRate;

  /// Frame length in seconds
  double get frameLength;

  /// Whether speech is currently active
  bool get isSpeechActive;

  /// Speech activity callback
  void Function(SpeechActivityEvent)? get onSpeechActivity;
  set onSpeechActivity(void Function(SpeechActivityEvent)? callback);

  /// Audio buffer callback
  void Function(List<int>)? get onAudioBuffer;
  set onAudioBuffer(void Function(List<int>)? callback);

  /// Initialize the service
  Future<void> initialize();

  /// Start processing
  void start();

  /// Stop processing
  void stop();

  /// Reset state
  void reset();

  /// Process audio buffer (16-bit PCM samples)
  void processAudioBuffer(List<int> buffer);

  /// Process audio samples (Float32 format)
  /// Returns whether speech is detected
  bool processAudioData(List<double> audioData);

  /// Pause VAD processing (optional, not all implementations may support)
  void pause();

  /// Resume VAD processing (optional, not all implementations may support)
  void resume();
}

/// Speech activity events
enum SpeechActivityEvent {
  started,
  ended;

  String get value {
    switch (this) {
      case SpeechActivityEvent.started:
        return 'started';
      case SpeechActivityEvent.ended:
        return 'ended';
    }
  }
}
