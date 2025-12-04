import '../../foundation/logging/sdk_logger.dart';
import 'models/memory_models.dart';

/// Provides memory usage statistics on-demand
/// Matches iOS MemoryMonitor
class MemoryMonitor {
  final SDKLogger _logger = SDKLogger(category: 'MemoryMonitor');

  int _memoryThreshold = 500 * 1024 * 1024; // 500MB
  int _criticalThreshold = 200 * 1024 * 1024; // 200MB

  // Memory history for trends
  final List<MemoryMonitoringStats> _memoryHistory = [];
  final int _maxHistoryEntries = 100;

  MemoryMonitor();

  void configure({required int memoryThreshold, required int criticalThreshold}) {
    _memoryThreshold = memoryThreshold;
    _criticalThreshold = criticalThreshold;
  }

  // MARK: - Memory Information

  /// Get total system memory
  int getTotalMemory() {
    // Placeholder - in production, use platform channels to get actual memory
    return 4 * 1024 * 1024 * 1024; // 4GB default
  }

  /// Get available memory
  int getAvailableMemory() {
    // Placeholder - in production, use platform channels to get actual memory
    // For now, return a conservative estimate
    final total = getTotalMemory();
    return (total * 0.3).round(); // Assume 30% available
  }

  /// Get used memory
  int getUsedMemory() {
    // Placeholder - would use platform channels in production
    final total = getTotalMemory();
    final available = getAvailableMemory();
    return total - available;
  }

  /// Get memory pressure level based on thresholds
  MemoryPressureLevel? getMemoryPressureLevel() {
    final available = getAvailableMemory();

    if (available < _criticalThreshold) {
      return MemoryPressureLevel.critical;
    } else if (available < _memoryThreshold) {
      return MemoryPressureLevel.warning;
    }

    return null;
  }

  /// Get current memory statistics
  MemoryMonitoringStats getCurrentStats() {
    final totalMemory = getTotalMemory();
    final availableMemory = getAvailableMemory();
    final usedMemory = getUsedMemory();
    final pressureLevel = getMemoryPressureLevel();

    final stats = MemoryMonitoringStats(
      totalMemory: totalMemory,
      availableMemory: availableMemory,
      usedMemory: usedMemory,
      pressureLevel: pressureLevel,
      timestamp: DateTime.now(),
    );

    // Record stats for history/trends
    _recordStats(stats);

    return stats;
  }

  // MARK: - Memory Trends

  /// Get memory trend over the specified duration
  MemoryUsageTrend? getMemoryTrend(Duration duration) {
    final cutoffTime = DateTime.now().subtract(duration);
    final recentHistory = _memoryHistory
        .where((s) => s.timestamp.isAfter(cutoffTime))
        .toList();

    if (recentHistory.length < 2) return null;

    final firstEntry = recentHistory.first;
    final lastEntry = recentHistory.last;

    final memoryDelta = lastEntry.availableMemory - firstEntry.availableMemory;
    final timeDelta = lastEntry.timestamp.difference(firstEntry.timestamp).inSeconds;

    if (timeDelta <= 0) return null;

    final rate = memoryDelta / timeDelta; // bytes per second

    return MemoryUsageTrend(
      direction: memoryDelta > 0 ? TrendDirection.increasing : TrendDirection.decreasing,
      rate: rate.abs(),
      confidence: _calculateTrendConfidence(recentHistory),
    );
  }

  /// Get average memory usage over duration
  double? getAverageMemoryUsage(Duration duration) {
    final cutoffTime = DateTime.now().subtract(duration);
    final recentHistory = _memoryHistory
        .where((s) => s.timestamp.isAfter(cutoffTime))
        .toList();

    if (recentHistory.isEmpty) return null;

    final totalUsage = recentHistory.map((s) => s.usedMemory).reduce((a, b) => a + b);
    return totalUsage / recentHistory.length;
  }

  // MARK: - Private Implementation

  void _recordStats(MemoryMonitoringStats stats) {
    // Store in history for trend analysis
    _memoryHistory.add(stats);
    if (_memoryHistory.length > _maxHistoryEntries) {
      _memoryHistory.removeAt(0);
    }

    // Log if there's memory pressure
    if (stats.pressureLevel != null) {
      _logMemoryStatus(stats);
    }
  }

  void _logMemoryStatus(MemoryMonitoringStats stats) {
    final availableString = _formatBytes(stats.availableMemory);
    final usedString = _formatBytes(stats.usedMemory);
    final usagePercent = stats.usedMemoryPercentage.toStringAsFixed(1);

    final pressureInfo = stats.pressureLevel != null ? ' [PRESSURE: ${stats.pressureLevel}]' : '';

    _logger.debug('Memory: $usedString used, $availableString available ($usagePercent%)$pressureInfo');

    if (stats.pressureLevel != null) {
      _logger.warning('Memory pressure detected: ${stats.pressureLevel}');
    }
  }

  double _calculateTrendConfidence(List<MemoryMonitoringStats> entries) {
    if (entries.length < 3) return 0.5;

    // Calculate consistency of trend direction
    int consistent = 0;
    int total = 0;

    for (int i = 1; i < entries.length; i++) {
      final delta = entries[i].availableMemory - entries[i - 1].availableMemory;
      final previousDelta = i > 1
          ? entries[i - 1].availableMemory - entries[i - 2].availableMemory
          : delta;

      if ((delta > 0 && previousDelta > 0) || (delta < 0 && previousDelta < 0)) {
        consistent++;
      }
      total++;
    }

    return total > 0 ? consistent / total : 0.5;
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
