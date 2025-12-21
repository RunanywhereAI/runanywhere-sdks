import 'speaker_diarization_segment.dart';
import 'speaker_diarization_speaker_info.dart';

/// Output from speaker diarization processing
/// Matches iOS SpeakerDiarizationOutput from Features/SpeakerDiarization/Models/SpeakerDiarizationOutput.swift
class SpeakerDiarizationOutput {
  /// All detected segments with speaker assignments
  final List<SpeakerDiarizationSegment> segments;

  /// All unique speakers detected
  final List<SpeakerDiarizationSpeakerInfo> speakers;

  /// Total audio duration processed
  final double totalDuration;

  const SpeakerDiarizationOutput({
    required this.segments,
    required this.speakers,
    required this.totalDuration,
  });

  /// Number of unique speakers detected
  int get speakerCount => speakers.length;

  /// Create from map
  factory SpeakerDiarizationOutput.fromJson(Map<String, dynamic> json) {
    return SpeakerDiarizationOutput(
      segments: (json['segments'] as List)
          .map((e) =>
              SpeakerDiarizationSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
      speakers: (json['speakers'] as List)
          .map((e) =>
              SpeakerDiarizationSpeakerInfo.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalDuration: (json['totalDuration'] as num).toDouble(),
    );
  }

  /// Convert to map
  Map<String, dynamic> toJson() => {
        'segments': segments.map((e) => e.toJson()).toList(),
        'speakers': speakers.map((e) => e.toJson()).toList(),
        'totalDuration': totalDuration,
      };
}
