/// A time-stamped segment of speech from a speaker
/// Matches iOS SpeakerDiarizationSegment from Features/SpeakerDiarization/Models/SpeakerDiarizationSegment.swift
class SpeakerDiarizationSegment {
  /// ID of the speaker for this segment
  final String speakerId;

  /// Start time of the segment (seconds)
  final double startTime;

  /// End time of the segment (seconds)
  final double endTime;

  /// Confidence score for speaker identification
  final double confidence;

  const SpeakerDiarizationSegment({
    required this.speakerId,
    required this.startTime,
    required this.endTime,
    required this.confidence,
  });

  /// Duration of the segment
  double get duration => endTime - startTime;

  /// Create from map
  factory SpeakerDiarizationSegment.fromJson(Map<String, dynamic> json) {
    return SpeakerDiarizationSegment(
      speakerId: json['speakerId'] as String,
      startTime: (json['startTime'] as num).toDouble(),
      endTime: (json['endTime'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }

  /// Convert to map
  Map<String, dynamic> toJson() => {
        'speakerId': speakerId,
        'startTime': startTime,
        'endTime': endTime,
        'confidence': confidence,
      };
}
