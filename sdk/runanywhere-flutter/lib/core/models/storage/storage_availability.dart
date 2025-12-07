/// Storage availability check result.
/// Matches iOS StorageAvailability from Data/Models/Storage/StorageAvailability.swift
class StorageAvailability {
  /// Whether storage is available for the requested operation
  final bool isAvailable;

  /// Required space in bytes
  final int requiredSpace;

  /// Available space in bytes
  final int availableSpace;

  /// Whether there's a warning (e.g., low space)
  final bool hasWarning;

  /// Recommendation message (optional)
  final String? recommendation;

  const StorageAvailability({
    required this.isAvailable,
    required this.requiredSpace,
    required this.availableSpace,
    this.hasWarning = false,
    this.recommendation,
  });

  /// Create from JSON map
  factory StorageAvailability.fromJson(Map<String, dynamic> json) {
    return StorageAvailability(
      isAvailable: json['isAvailable'] as bool? ?? false,
      requiredSpace: (json['requiredSpace'] as num?)?.toInt() ?? 0,
      availableSpace: (json['availableSpace'] as num?)?.toInt() ?? 0,
      hasWarning: json['hasWarning'] as bool? ?? false,
      recommendation: json['recommendation'] as String?,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'isAvailable': isAvailable,
      'requiredSpace': requiredSpace,
      'availableSpace': availableSpace,
      'hasWarning': hasWarning,
      if (recommendation != null) 'recommendation': recommendation,
    };
  }
}
