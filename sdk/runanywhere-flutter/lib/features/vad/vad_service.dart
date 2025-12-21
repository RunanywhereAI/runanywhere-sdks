import 'dart:async';

import 'models/speech_activity_event.dart';
export 'models/speech_activity_event.dart';

/// VAD detection result
class VADResult {
  final bool hasSpeech;
  final double confidence;
  VADResult({required this.hasSpeech, required this.confidence});
}

/// Base protocol for VAD (Voice Activity Detection) services
/// Matches iOS VADService protocol from VADComponent.swift
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

  /// Whether the service is ready
  bool get isReady;

  /// Speech activity callback
  void Function(SpeechActivityEvent)? get onSpeechActivity;
  set onSpeechActivity(void Function(SpeechActivityEvent)? callback);

  /// Audio buffer callback
  void Function(List<int>)? get onAudioBuffer;
  set onAudioBuffer(void Function(List<int>)? callback);

  /// Initialize the service
  Future<void> initialize({String? modelPath});

  /// Detect speech in audio data and return result
  /// This is a convenience method that wraps processAudioBuffer
  Future<VADResult> detect({required List<int> audioData});

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

  /// Cleanup resources
  Future<void> cleanup();
}
