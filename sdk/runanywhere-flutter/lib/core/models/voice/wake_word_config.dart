import 'noise_suppression_level.dart';

/// Configuration for wake word detection
///
/// Corresponds to iOS SDK's WakeWordConfig struct in WakeWordDetector.swift
class WakeWordConfig {
  /// Wake words to detect
  final List<String> wakeWords;

  /// Minimum confidence threshold for detection
  final double confidenceThreshold;

  /// Whether to continue listening after detection
  final bool continuousListening;

  /// Audio preprocessing options
  final bool preprocessingEnabled;

  /// Noise suppression level
  final NoiseSuppressionLevel noiseSuppression;

  /// Model to use for wake word detection
  final String? modelPath;

  /// Buffer size for audio processing
  final int bufferSize;

  /// Sample rate for audio input
  final int sampleRate;

  const WakeWordConfig({
    required this.wakeWords,
    this.confidenceThreshold = 0.7,
    this.continuousListening = true,
    this.preprocessingEnabled = true,
    this.noiseSuppression = NoiseSuppressionLevel.medium,
    this.modelPath,
    this.bufferSize = 1024,
    this.sampleRate = 16000,
  });

  /// Create a copy with updated values
  WakeWordConfig copyWith({
    List<String>? wakeWords,
    double? confidenceThreshold,
    bool? continuousListening,
    bool? preprocessingEnabled,
    NoiseSuppressionLevel? noiseSuppression,
    String? modelPath,
    int? bufferSize,
    int? sampleRate,
  }) {
    return WakeWordConfig(
      wakeWords: wakeWords ?? this.wakeWords,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
      continuousListening: continuousListening ?? this.continuousListening,
      preprocessingEnabled: preprocessingEnabled ?? this.preprocessingEnabled,
      noiseSuppression: noiseSuppression ?? this.noiseSuppression,
      modelPath: modelPath ?? this.modelPath,
      bufferSize: bufferSize ?? this.bufferSize,
      sampleRate: sampleRate ?? this.sampleRate,
    );
  }

  @override
  String toString() =>
      'WakeWordConfig(wakeWords: $wakeWords, confidenceThreshold: $confidenceThreshold, '
      'continuousListening: $continuousListening, preprocessingEnabled: $preprocessingEnabled, '
      'noiseSuppression: $noiseSuppression, modelPath: $modelPath, '
      'bufferSize: $bufferSize, sampleRate: $sampleRate)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WakeWordConfig &&
          runtimeType == other.runtimeType &&
          _listEquals(wakeWords, other.wakeWords) &&
          confidenceThreshold == other.confidenceThreshold &&
          continuousListening == other.continuousListening &&
          preprocessingEnabled == other.preprocessingEnabled &&
          noiseSuppression == other.noiseSuppression &&
          modelPath == other.modelPath &&
          bufferSize == other.bufferSize &&
          sampleRate == other.sampleRate;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(wakeWords),
        confidenceThreshold,
        continuousListening,
        preprocessingEnabled,
        noiseSuppression,
        modelPath,
        bufferSize,
        sampleRate,
      );

  static bool _listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
