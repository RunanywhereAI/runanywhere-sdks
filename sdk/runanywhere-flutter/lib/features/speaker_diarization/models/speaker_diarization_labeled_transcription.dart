/// Transcription with speaker information
/// Matches iOS SpeakerDiarizationLabeledTranscription from Features/SpeakerDiarization/Models/SpeakerDiarizationLabeledTranscription.swift
class SpeakerDiarizationLabeledTranscription {
  /// Labeled segments of transcription
  final List<SpeakerDiarizationLabeledSegment> segments;

  const SpeakerDiarizationLabeledTranscription({
    required this.segments,
  });

  /// Get full transcript as formatted text with speaker labels
  String get formattedTranscript {
    return segments
        .map((segment) => '[${segment.speakerId}]: ${segment.text}')
        .join('\n');
  }

  /// Create from map
  factory SpeakerDiarizationLabeledTranscription.fromJson(
      Map<String, dynamic> json) {
    return SpeakerDiarizationLabeledTranscription(
      segments: (json['segments'] as List)
          .map((e) => SpeakerDiarizationLabeledSegment.fromJson(
              e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Convert to map
  Map<String, dynamic> toJson() => {
        'segments': segments.map((e) => e.toJson()).toList(),
      };
}

/// A segment of transcription labeled with speaker info
/// Matches iOS SpeakerDiarizationLabeledTranscription.LabeledSegment
class SpeakerDiarizationLabeledSegment {
  /// ID of the speaker
  final String speakerId;

  /// Transcribed text
  final String text;

  /// Start time of the segment
  final double startTime;

  /// End time of the segment
  final double endTime;

  const SpeakerDiarizationLabeledSegment({
    required this.speakerId,
    required this.text,
    required this.startTime,
    required this.endTime,
  });

  /// Create from map
  factory SpeakerDiarizationLabeledSegment.fromJson(Map<String, dynamic> json) {
    return SpeakerDiarizationLabeledSegment(
      speakerId: json['speakerId'] as String,
      text: json['text'] as String,
      startTime: (json['startTime'] as num).toDouble(),
      endTime: (json['endTime'] as num).toDouble(),
    );
  }

  /// Convert to map
  Map<String, dynamic> toJson() => {
        'speakerId': speakerId,
        'text': text,
        'startTime': startTime,
        'endTime': endTime,
      };
}
