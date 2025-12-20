import 'dart:async';
import 'dart:typed_data';

import '../../models/voice/voice_audio_chunk.dart';
import '../../models/voice/wake_word_detection.dart';

/// Protocol for wake word detection in audio streams
///
/// Corresponds to iOS SDK's WakeWordDetector protocol in WakeWordDetector.swift
abstract class WakeWordDetector {
  /// Initialize the detector with specific wake words
  ///
  /// [wakeWords] - Array of wake words to detect
  Future<void> initialize(List<String> wakeWords);

  /// Start listening for wake words
  Future<void> startListening();

  /// Stop listening for wake words
  Future<void> stopListening();

  /// Process an audio buffer for wake word detection
  ///
  /// [audio] - Audio data to analyze
  /// Returns detection result if wake word found
  Future<WakeWordDetection?> processAudio(Uint8List audio);

  /// Process streaming audio for wake word detection
  ///
  /// [audioStream] - Stream of audio chunks
  /// Returns stream of wake word detections
  Stream<WakeWordDetection> processStream(Stream<VoiceAudioChunk> audioStream);

  /// Whether the detector is currently listening
  bool get isListening;

  /// Current wake words being detected
  List<String> get wakeWords;

  /// Sensitivity level for detection (0.0 to 1.0)
  double get sensitivity;
  set sensitivity(double value);

  /// Callback when wake word is detected
  void Function(WakeWordDetection)? get onWakeWordDetected;
  set onWakeWordDetected(void Function(WakeWordDetection)? callback);

  /// Callback when listening state changes
  void Function(bool)? get onListeningStateChanged;
  set onListeningStateChanged(void Function(bool)? callback);

  /// Add a new wake word to detection
  ///
  /// [word] - Wake word to add
  Future<void> addWakeWord(String word);

  /// Remove a wake word from detection
  ///
  /// [word] - Wake word to remove
  Future<void> removeWakeWord(String word);

  /// Clear all wake words
  Future<void> clearWakeWords();
}

/// Mock implementation of WakeWordDetector for testing and development
///
/// TODO: Replace with actual native implementation when FFI bridge is ready
class MockWakeWordDetector implements WakeWordDetector {
  final List<String> _wakeWords = [];
  bool _isListening = false;
  double _sensitivity = 0.7;

  void Function(WakeWordDetection)? _onWakeWordDetected;
  void Function(bool)? _onListeningStateChanged;

  @override
  Future<void> initialize(List<String> wakeWords) async {
    _wakeWords.clear();
    _wakeWords.addAll(wakeWords);
  }

  @override
  Future<void> startListening() async {
    if (!_isListening) {
      _isListening = true;
      _onListeningStateChanged?.call(_isListening);
    }
  }

  @override
  Future<void> stopListening() async {
    if (_isListening) {
      _isListening = false;
      _onListeningStateChanged?.call(_isListening);
    }
  }

  @override
  Future<WakeWordDetection?> processAudio(Uint8List audio) async {
    // Mock implementation - in a real implementation, this would use
    // native wake word detection (e.g., Picovoice Porcupine)
    return null;
  }

  @override
  Stream<WakeWordDetection> processStream(Stream<VoiceAudioChunk> audioStream) {
    // Mock implementation - returns empty stream
    // In a real implementation, this would process the audio stream
    // and emit detections when wake words are found
    return const Stream.empty();
  }

  @override
  bool get isListening => _isListening;

  @override
  List<String> get wakeWords => List.unmodifiable(_wakeWords);

  @override
  double get sensitivity => _sensitivity;

  @override
  set sensitivity(double value) {
    _sensitivity = value.clamp(0.0, 1.0);
  }

  @override
  void Function(WakeWordDetection)? get onWakeWordDetected =>
      _onWakeWordDetected;

  @override
  set onWakeWordDetected(void Function(WakeWordDetection)? callback) {
    _onWakeWordDetected = callback;
  }

  @override
  void Function(bool)? get onListeningStateChanged => _onListeningStateChanged;

  @override
  set onListeningStateChanged(void Function(bool)? callback) {
    _onListeningStateChanged = callback;
  }

  @override
  Future<void> addWakeWord(String word) async {
    if (!_wakeWords.contains(word)) {
      _wakeWords.add(word);
    }
  }

  @override
  Future<void> removeWakeWord(String word) async {
    _wakeWords.remove(word);
  }

  @override
  Future<void> clearWakeWords() async {
    _wakeWords.clear();
  }
}
