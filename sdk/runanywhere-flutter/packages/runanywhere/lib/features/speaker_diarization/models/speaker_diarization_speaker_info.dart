/// Information about a detected speaker
/// Matches iOS SpeakerDiarizationSpeakerInfo from Features/SpeakerDiarization/Models/SpeakerDiarizationSpeakerInfo.swift
class SpeakerDiarizationSpeakerInfo {
  /// Unique identifier for the speaker
  final String id;

  /// Optional display name for the speaker
  String? name;

  /// Confidence score for the speaker identification (0.0-1.0)
  final double? confidence;

  /// Speaker embedding vector (for comparison)
  final List<double>? embedding;

  SpeakerDiarizationSpeakerInfo({
    required this.id,
    this.name,
    this.confidence,
    this.embedding,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SpeakerDiarizationSpeakerInfo && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  /// Create from map
  factory SpeakerDiarizationSpeakerInfo.fromJson(Map<String, dynamic> json) {
    return SpeakerDiarizationSpeakerInfo(
      id: json['id'] as String,
      name: json['name'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      embedding: (json['embedding'] as List?)?.cast<double>(),
    );
  }

  /// Convert to map
  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        if (confidence != null) 'confidence': confidence,
        if (embedding != null) 'embedding': embedding,
      };
}

/// Deprecated typealias for backward compatibility
@Deprecated('Use SpeakerDiarizationSpeakerInfo instead')
typedef SpeakerInfo = SpeakerDiarizationSpeakerInfo;
