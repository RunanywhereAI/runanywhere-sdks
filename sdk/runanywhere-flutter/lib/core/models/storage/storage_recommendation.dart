/// Storage recommendation type.
/// Matches iOS StorageRecommendation.RecommendationType from Data/Models/Storage/StorageRecommendation.swift
enum RecommendationType {
  critical,
  warning,
  suggestion;

  String get rawValue => name;

  static RecommendationType? fromRawValue(String value) {
    return RecommendationType.values.cast<RecommendationType?>().firstWhere(
          (t) => t?.name == value,
          orElse: () => null,
        );
  }
}

/// Storage recommendation.
/// Matches iOS StorageRecommendation from Data/Models/Storage/StorageRecommendation.swift
class StorageRecommendation {
  /// Type of recommendation
  final RecommendationType type;

  /// Recommendation message
  final String message;

  /// Recommended action
  final String action;

  const StorageRecommendation({
    required this.type,
    required this.message,
    required this.action,
  });

  /// Create from JSON map
  factory StorageRecommendation.fromJson(Map<String, dynamic> json) {
    return StorageRecommendation(
      type: RecommendationType.fromRawValue(json['type'] as String? ?? 'suggestion') ??
          RecommendationType.suggestion,
      message: json['message'] as String? ?? '',
      action: json['action'] as String? ?? '',
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'type': type.rawValue,
      'message': message,
      'action': action,
    };
  }
}
