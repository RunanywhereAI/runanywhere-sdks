/// Information about a detected speaker
/// Matches iOS SpeakerDiarizationSpeakerInfo from
/// Features/SpeakerDiarization/Models/SpeakerDiarizationSpeakerInfo.swift
class SpeakerInfo {
  /// Unique identifier for the speaker
  final String id;

  /// Optional display name for the speaker
  String? name;

  /// Confidence score for the speaker identification (0.0-1.0)
  final double? confidence;

  /// Speaker embedding vector (for comparison)
  final List<double>? embedding;

  SpeakerInfo({
    required this.id,
    this.name,
    this.confidence,
    this.embedding,
  });

  /// JSON serialization
  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        if (confidence != null) 'confidence': confidence,
        if (embedding != null) 'embedding': embedding,
      };

  factory SpeakerInfo.fromJson(Map<String, dynamic> json) {
    return SpeakerInfo(
      id: json['id'] as String,
      name: json['name'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      embedding: (json['embedding'] as List<dynamic>?)
          ?.map((e) => (e as num).toDouble())
          .toList(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SpeakerInfo &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SpeakerInfo(id: $id, name: $name)';
}

/// Type alias for iOS parity
/// iOS uses SpeakerDiarizationSpeakerInfo as the full name
typedef SpeakerDiarizationSpeakerInfo = SpeakerInfo;
