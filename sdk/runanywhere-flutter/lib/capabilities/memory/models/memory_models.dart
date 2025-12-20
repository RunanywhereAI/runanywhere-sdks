import '../../../core/models/common/memory_priority.dart';
import '../../../core/models/framework/llm_framework.dart';

// Re-export MemoryPriority for convenience
export '../../../core/models/common/memory_priority.dart';

/// Memory pressure levels
enum MemoryPressureLevel {
  low,
  medium,
  high,
  warning,
  critical,
}

/// Memory threshold definitions
enum MemoryThreshold {
  warning,
  critical,
  low,
  veryLow;

  int threshold(
      {required int memoryThreshold, required int criticalThreshold}) {
    switch (this) {
      case MemoryThreshold.warning:
        return memoryThreshold;
      case MemoryThreshold.critical:
        return criticalThreshold;
      case MemoryThreshold.low:
        return memoryThreshold ~/ 2;
      case MemoryThreshold.veryLow:
        return criticalThreshold ~/ 2;
    }
  }
}

/// Memory loaded model representation
class MemoryLoadedModel {
  final String id;
  final String name;
  final int size;
  final LLMFramework framework;

  MemoryLoadedModel({
    required this.id,
    required this.name,
    required this.size,
    required this.framework,
  });
}

/// Memory-specific information about a loaded model
/// Matches iOS MemoryLoadedModelInfo
class MemoryLoadedModelInfo {
  final MemoryLoadedModel model;
  final int size;
  DateTime lastUsed;
  final dynamic service; // weak reference not available in Dart
  final MemoryPriority priority;

  MemoryLoadedModelInfo({
    required this.model,
    required this.size,
    DateTime? lastUsed,
    this.service,
    this.priority = MemoryPriority.normal,
  }) : lastUsed = lastUsed ?? DateTime.now();
}

/// Memory monitoring statistics
/// Matches iOS MemoryMonitoringStats
class MemoryMonitoringStats {
  final int totalMemory;
  final int availableMemory;
  final int usedMemory;
  final MemoryPressureLevel? pressureLevel;
  final DateTime timestamp;

  MemoryMonitoringStats({
    required this.totalMemory,
    required this.availableMemory,
    required this.usedMemory,
    this.pressureLevel,
    required this.timestamp,
  });

  double get usedMemoryPercentage {
    return (usedMemory / totalMemory) * 100;
  }

  double get availableMemoryPercentage {
    return (availableMemory / totalMemory) * 100;
  }
}

/// Memory usage trend information
/// Matches iOS MemoryUsageTrend
class MemoryUsageTrend {
  final TrendDirection direction;
  final double rate; // bytes per second
  final double confidence; // 0.0 to 1.0

  MemoryUsageTrend({
    required this.direction,
    required this.rate,
    required this.confidence,
  });

  String get rateString {
    final bytesPerSecond = rate.abs().round();
    return '${_formatBytes(bytesPerSecond)}/s';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Trend direction for memory usage
enum TrendDirection {
  increasing,
  decreasing,
  stable,
}

/// Memory statistics
/// Matches iOS MemoryStatistics
class MemoryStatistics {
  final int totalMemory;
  final int availableMemory;
  final int modelMemory;
  final int loadedModelCount;
  final bool memoryPressure;

  MemoryStatistics({
    required this.totalMemory,
    required this.availableMemory,
    required this.modelMemory,
    required this.loadedModelCount,
    required this.memoryPressure,
  });

  double get usedMemoryPercentage {
    final used = totalMemory - availableMemory;
    return (used / totalMemory) * 100;
  }

  double get modelMemoryPercentage {
    return (modelMemory / totalMemory) * 100;
  }
}

/// Statistics about eviction state
/// Matches iOS EvictionStatistics
class EvictionStatistics {
  final int totalModels;
  final int totalMemory;
  final Map<MemoryPriority, int> modelsByPriority;
  final DateTime averageLastUsed;
  final DateTime oldestModel;
  final int largestModel;

  EvictionStatistics({
    required this.totalModels,
    required this.totalMemory,
    required this.modelsByPriority,
    required this.averageLastUsed,
    required this.oldestModel,
    required this.largestModel,
  });

  String get totalMemoryString => _formatBytes(totalMemory);
  String get largestModelString => _formatBytes(largestModel);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Record of a threshold crossing event
/// Matches iOS ThresholdEvent
class ThresholdEvent {
  final MemoryThreshold threshold;
  final bool crossed; // true = crossed, false = uncrossed
  final int availableMemory;
  final DateTime timestamp;

  ThresholdEvent({
    required this.threshold,
    required this.crossed,
    required this.availableMemory,
    required this.timestamp,
  });

  String get availableMemoryString => _formatBytes(availableMemory);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Statistics about threshold behavior
/// Matches iOS ThresholdStatistics
class ThresholdStatistics {
  final List<MemoryThreshold> currentlyCrossedThresholds;
  final Map<MemoryThreshold, int> crossingsLast24Hours;
  final int totalEventsRecorded;
  final DateTime lastCheckTime;

  ThresholdStatistics({
    required this.currentlyCrossedThresholds,
    required this.crossingsLast24Hours,
    required this.totalEventsRecorded,
    required this.lastCheckTime,
  });

  bool get hasActiveCrossings => currentlyCrossedThresholds.isNotEmpty;

  MemoryThreshold? get mostFrequentThreshold {
    if (crossingsLast24Hours.isEmpty) return null;
    return crossingsLast24Hours.entries
        .reduce((a, b) => a.value > b.value ? a : b)
        .key;
  }
}

/// Information for threshold crossing notifications
/// Matches iOS ThresholdNotificationInfo
class ThresholdNotificationInfo {
  final MemoryThreshold threshold;
  final bool crossed;
  final int availableMemory;
  final DateTime timestamp;

  ThresholdNotificationInfo({
    required this.threshold,
    required this.crossed,
    required this.availableMemory,
    required this.timestamp,
  });

  String get availableMemoryString => _formatBytes(availableMemory);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Information about memory pressure response
/// Matches iOS MemoryPressureResponse
class MemoryPressureResponse {
  final MemoryPressureLevel level;
  final int freedMemory;
  final Duration duration;
  final List<String> modelsEvicted;
  final bool success;

  MemoryPressureResponse({
    required this.level,
    required this.freedMemory,
    required this.duration,
    required this.modelsEvicted,
    required this.success,
  });

  String get freedMemoryString => _formatBytes(freedMemory);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// Information about memory pressure notification
/// Matches iOS MemoryPressureNotificationInfo
class MemoryPressureNotificationInfo {
  final MemoryPressureLevel level;
  final int freedMemory;
  final Duration duration;

  MemoryPressureNotificationInfo({
    required this.level,
    required this.freedMemory,
    required this.duration,
  });

  String get freedMemoryString => _formatBytes(freedMemory);

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
