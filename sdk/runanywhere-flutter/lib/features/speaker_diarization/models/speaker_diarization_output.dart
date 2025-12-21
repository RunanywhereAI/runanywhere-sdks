import 'speaker_diarization_segment.dart';
import 'speaker_diarization_profile.dart';
import 'speaker_diarization_labeled_transcription.dart';
import 'speaker_diarization_metadata.dart';

/// Output from speaker diarization processing (conforms to ComponentOutput protocol)
/// Matches iOS SpeakerDiarizationOutput from Features/SpeakerDiarization/Models/SpeakerDiarizationOutput.swift
class SpeakerDiarizationOutput {
  /// Speaker segments with timing information
  final List<SpeakerDiarizationSegment> segments;

  /// Speaker profiles with statistics
  final List<SpeakerDiarizationProfile> speakers;

  /// Labeled transcription (if STT output was provided)
  final SpeakerDiarizationLabeledTranscription? labeledTranscription;

  /// Processing metadata
  final SpeakerDiarizationMetadata metadata;

  /// Timestamp (required by ComponentOutput)
  final DateTime timestamp;

  SpeakerDiarizationOutput({
    required this.segments,
    required this.speakers,
    this.labeledTranscription,
    required this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Create from map
  factory SpeakerDiarizationOutput.fromJson(Map<String, dynamic> json) {
    return SpeakerDiarizationOutput(
      segments: (json['segments'] as List)
          .map((e) =>
              SpeakerDiarizationSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
      speakers: (json['speakers'] as List)
          .map((e) =>
              SpeakerDiarizationProfile.fromJson(e as Map<String, dynamic>))
          .toList(),
      labeledTranscription: json['labeledTranscription'] != null
          ? SpeakerDiarizationLabeledTranscription.fromJson(
              json['labeledTranscription'] as Map<String, dynamic>)
          : null,
      metadata: SpeakerDiarizationMetadata.fromJson(
          json['metadata'] as Map<String, dynamic>),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
    );
  }

  /// Convert to map
  Map<String, dynamic> toJson() => {
        'segments': segments.map((e) => e.toJson()).toList(),
        'speakers': speakers.map((e) => e.toJson()).toList(),
        if (labeledTranscription != null)
          'labeledTranscription': labeledTranscription!.toJson(),
        'metadata': metadata.toJson(),
        'timestamp': timestamp.toIso8601String(),
      };
}
