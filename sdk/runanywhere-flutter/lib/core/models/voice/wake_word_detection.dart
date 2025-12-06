import 'dart:typed_data';

/// Result of wake word detection
///
/// Corresponds to iOS SDK's WakeWordDetection struct in WakeWordDetector.swift
class WakeWordDetection {
  /// The detected wake word
  final String wakeWord;

  /// Confidence score of the detection (0.0 to 1.0)
  final double confidence;

  /// Timestamp when the wake word was detected
  final Duration timestamp;

  /// Audio segment containing the wake word
  final Uint8List? audioSegment;

  /// Start time of the wake word in the audio
  final Duration startTime;

  /// End time of the wake word in the audio
  final Duration endTime;

  /// Whether this is a confirmed detection (above threshold)
  final bool isConfirmed;

  const WakeWordDetection({
    required this.wakeWord,
    required this.confidence,
    required this.timestamp,
    this.audioSegment,
    required this.startTime,
    required this.endTime,
    this.isConfirmed = true,
  });

  /// Duration of the wake word
  Duration get duration => endTime - startTime;

  /// Create a copy with updated values
  WakeWordDetection copyWith({
    String? wakeWord,
    double? confidence,
    Duration? timestamp,
    Uint8List? audioSegment,
    Duration? startTime,
    Duration? endTime,
    bool? isConfirmed,
  }) {
    return WakeWordDetection(
      wakeWord: wakeWord ?? this.wakeWord,
      confidence: confidence ?? this.confidence,
      timestamp: timestamp ?? this.timestamp,
      audioSegment: audioSegment ?? this.audioSegment,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isConfirmed: isConfirmed ?? this.isConfirmed,
    );
  }

  @override
  String toString() =>
      'WakeWordDetection(wakeWord: $wakeWord, confidence: $confidence, '
      'timestamp: $timestamp, startTime: $startTime, endTime: $endTime, '
      'isConfirmed: $isConfirmed)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WakeWordDetection &&
          runtimeType == other.runtimeType &&
          wakeWord == other.wakeWord &&
          confidence == other.confidence &&
          timestamp == other.timestamp &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          isConfirmed == other.isConfirmed;

  @override
  int get hashCode =>
      Object.hash(wakeWord, confidence, timestamp, startTime, endTime, isConfirmed);
}
