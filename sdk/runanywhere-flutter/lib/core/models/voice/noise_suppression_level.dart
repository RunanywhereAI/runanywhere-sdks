/// Noise suppression levels for wake word detection
///
/// Corresponds to iOS SDK's NoiseSuppressionLevel enum in WakeWordDetector.swift
enum NoiseSuppressionLevel {
  /// No noise suppression
  none,

  /// Light noise suppression
  low,

  /// Moderate noise suppression
  medium,

  /// Aggressive noise suppression
  high,
}

/// Extension methods for NoiseSuppressionLevel
extension NoiseSuppressionLevelExtension on NoiseSuppressionLevel {
  /// Get the suppression factor (0.0 to 1.0)
  double get factor {
    switch (this) {
      case NoiseSuppressionLevel.none:
        return 0.0;
      case NoiseSuppressionLevel.low:
        return 0.25;
      case NoiseSuppressionLevel.medium:
        return 0.5;
      case NoiseSuppressionLevel.high:
        return 0.75;
    }
  }

  /// Get a human-readable description
  String get description {
    switch (this) {
      case NoiseSuppressionLevel.none:
        return 'No noise suppression';
      case NoiseSuppressionLevel.low:
        return 'Light noise suppression';
      case NoiseSuppressionLevel.medium:
        return 'Moderate noise suppression';
      case NoiseSuppressionLevel.high:
        return 'Aggressive noise suppression';
    }
  }
}
