/// Statistics for VAD debugging and monitoring
/// Matches iOS VADStatistics from Features/VAD/Models/VADStatistics.swift
class VADStatistics {
  /// Current energy level
  final double current;

  /// Energy threshold being used
  final double threshold;

  /// Ambient noise level (from calibration)
  final double ambient;

  /// Recent average energy level
  final double recentAvg;

  /// Recent maximum energy level
  final double recentMax;

  const VADStatistics({
    required this.current,
    required this.threshold,
    required this.ambient,
    required this.recentAvg,
    required this.recentMax,
  });

  @override
  String toString() => '''
VADStatistics:
  Current: ${current.toStringAsFixed(6)}
  Threshold: ${threshold.toStringAsFixed(6)}
  Ambient: ${ambient.toStringAsFixed(6)}
  Recent Avg: ${recentAvg.toStringAsFixed(6)}
  Recent Max: ${recentMax.toStringAsFixed(6)}
''';

  /// Create from map
  factory VADStatistics.fromJson(Map<String, dynamic> json) {
    return VADStatistics(
      current: (json['current'] as num).toDouble(),
      threshold: (json['threshold'] as num).toDouble(),
      ambient: (json['ambient'] as num).toDouble(),
      recentAvg: (json['recentAvg'] as num).toDouble(),
      recentMax: (json['recentMax'] as num).toDouble(),
    );
  }

  /// Convert to map
  Map<String, dynamic> toJson() => {
        'current': current,
        'threshold': threshold,
        'ambient': ambient,
        'recentAvg': recentAvg,
        'recentMax': recentMax,
      };
}
