import 'dart:async';
import '../../../foundation/logging/sdk_logger.dart';
import '../models/memory_models.dart';
import '../memory_monitor.dart';

/// Watches memory thresholds and triggers callbacks when crossed
/// Matches iOS ThresholdWatcher
class ThresholdWatcher {
  final SDKLogger _logger = SDKLogger(category: 'ThresholdWatcher');

  int _memoryThreshold = 500 * 1024 * 1024; // 500MB
  int _criticalThreshold = 200 * 1024 * 1024; // 200MB
  MemoryMonitor? _memoryMonitor;

  // Threshold state tracking
  final Map<MemoryThreshold, bool> _thresholdStates = {};
  final Map<MemoryThreshold, void Function()> _thresholdCallbacks = {};
  DateTime _lastThresholdCheck = DateTime.now();
  bool _isWatching = false;

  // Hysteresis to prevent threshold flapping
  final double _thresholdHysteresis = 0.1; // 10% buffer

  // Threshold history
  final List<ThresholdEvent> _thresholdEvents = [];
  final int _maxHistoryEntries = 100;

  // Stream controller for threshold notifications
  final StreamController<ThresholdNotificationInfo> _thresholdNotifications =
      StreamController<ThresholdNotificationInfo>.broadcast();

  /// Stream of threshold notifications
  Stream<ThresholdNotificationInfo> get thresholdNotifications =>
      _thresholdNotifications.stream;

  ThresholdWatcher() {
    // Initialize all thresholds as not crossed
    for (final threshold in MemoryThreshold.values) {
      _thresholdStates[threshold] = false;
    }
  }

  void configure(
      {required int memoryThreshold, required int criticalThreshold}) {
    _memoryThreshold = memoryThreshold;
    _criticalThreshold = criticalThreshold;
  }

  void setMemoryMonitor(MemoryMonitor monitor) {
    _memoryMonitor = monitor;
  }

  // MARK: - Threshold Watching

  void startWatching() {
    if (_isWatching) {
      _logger.warning('Threshold watching already active');
      return;
    }

    _isWatching = true;
    _logger.info('Started threshold watching');

    // Reset threshold states
    for (final threshold in MemoryThreshold.values) {
      _thresholdStates[threshold] = false;
    }
  }

  void stopWatching() {
    if (!_isWatching) return;

    _isWatching = false;
    _logger.info('Stopped threshold watching');
  }

  void setThresholdCallback(
      MemoryThreshold threshold, void Function() callback) {
    _thresholdCallbacks[threshold] = callback;
    _logger.debug('Set callback for threshold: $threshold');
  }

  void removeThresholdCallback(MemoryThreshold threshold) {
    _thresholdCallbacks.remove(threshold);
    _logger.debug('Removed callback for threshold: $threshold');
  }

  // MARK: - Threshold Checking

  void checkThresholds(MemoryMonitoringStats stats) {
    if (!_isWatching) return;

    final checkTime = DateTime.now();

    for (final threshold in MemoryThreshold.values) {
      _checkThreshold(threshold, stats: stats, checkTime: checkTime);
    }

    _lastThresholdCheck = checkTime;
  }

  void _checkThreshold(
    MemoryThreshold threshold, {
    required MemoryMonitoringStats stats,
    required DateTime checkTime,
  }) {
    final thresholdValue = threshold.threshold(
      memoryThreshold: _memoryThreshold,
      criticalThreshold: _criticalThreshold,
    );
    final currentState = _thresholdStates[threshold] ?? false;
    final hysteresisBuffer = (thresholdValue * _thresholdHysteresis).round();

    final bool isAboveThreshold;
    if (currentState) {
      // If already crossed, use hysteresis buffer to prevent flapping
      isAboveThreshold =
          stats.availableMemory < (thresholdValue + hysteresisBuffer);
    } else {
      // If not crossed, check against raw threshold
      isAboveThreshold = stats.availableMemory < thresholdValue;
    }

    // Check for threshold crossing
    if (isAboveThreshold && !currentState) {
      // Threshold crossed (available memory dropped below threshold)
      _thresholdStates[threshold] = true;
      _handleThresholdCrossed(threshold, stats: stats, checkTime: checkTime);
    } else if (!isAboveThreshold && currentState) {
      // Threshold uncrossed (available memory rose above threshold + hysteresis)
      _thresholdStates[threshold] = false;
      _handleThresholdUncrossed(threshold, stats: stats, checkTime: checkTime);
    }
  }

  // MARK: - Threshold Events

  void _handleThresholdCrossed(
    MemoryThreshold threshold, {
    required MemoryMonitoringStats stats,
    required DateTime checkTime,
  }) {
    final thresholdValue = threshold.threshold(
      memoryThreshold: _memoryThreshold,
      criticalThreshold: _criticalThreshold,
    );
    final availableString = _formatBytes(stats.availableMemory);
    final thresholdString = _formatBytes(thresholdValue);

    _logger.warning(
      'Memory threshold crossed: $threshold (available: $availableString, threshold: $thresholdString)',
    );

    // Record threshold event
    _recordThresholdEvent(
      threshold: threshold,
      crossed: true,
      stats: stats,
      timestamp: checkTime,
    );

    // Trigger callback
    _thresholdCallbacks[threshold]?.call();

    // Post notification
    _postThresholdNotification(
        threshold: threshold, crossed: true, stats: stats);
  }

  void _handleThresholdUncrossed(
    MemoryThreshold threshold, {
    required MemoryMonitoringStats stats,
    required DateTime checkTime,
  }) {
    final thresholdValue = threshold.threshold(
      memoryThreshold: _memoryThreshold,
      criticalThreshold: _criticalThreshold,
    );
    final availableString = _formatBytes(stats.availableMemory);
    final thresholdString = _formatBytes(thresholdValue);

    _logger.info(
      'Memory threshold uncrossed: $threshold (available: $availableString, threshold: $thresholdString)',
    );

    // Record threshold event
    _recordThresholdEvent(
      threshold: threshold,
      crossed: false,
      stats: stats,
      timestamp: checkTime,
    );

    // Post notification
    _postThresholdNotification(
        threshold: threshold, crossed: false, stats: stats);
  }

  // MARK: - Threshold State

  bool isThresholdCrossed(MemoryThreshold threshold) {
    return _thresholdStates[threshold] ?? false;
  }

  List<MemoryThreshold> getCrossedThresholds() {
    return _thresholdStates.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
  }

  int? getThresholdMargin(MemoryThreshold threshold) {
    final monitor = _memoryMonitor;
    if (monitor == null) return null;

    final thresholdValue = threshold.threshold(
      memoryThreshold: _memoryThreshold,
      criticalThreshold: _criticalThreshold,
    );
    final availableMemory = monitor.getAvailableMemory();

    return availableMemory - thresholdValue;
  }

  // MARK: - Threshold History

  void _recordThresholdEvent({
    required MemoryThreshold threshold,
    required bool crossed,
    required MemoryMonitoringStats stats,
    required DateTime timestamp,
  }) {
    final event = ThresholdEvent(
      threshold: threshold,
      crossed: crossed,
      availableMemory: stats.availableMemory,
      timestamp: timestamp,
    );

    _thresholdEvents.add(event);

    // Limit history size
    if (_thresholdEvents.length > _maxHistoryEntries) {
      _thresholdEvents.removeAt(0);
    }
  }

  List<ThresholdEvent> getThresholdHistory({
    MemoryThreshold? threshold,
    DateTime? since,
  }) {
    var filtered = _thresholdEvents.toList();

    if (threshold != null) {
      filtered = filtered.where((e) => e.threshold == threshold).toList();
    }

    if (since != null) {
      filtered = filtered
          .where((e) =>
              e.timestamp.isAfter(since) || e.timestamp.isAtSameMomentAs(since))
          .toList();
    }

    return filtered;
  }

  ThresholdEvent? getLastThresholdCrossing(MemoryThreshold threshold) {
    final crossings = _thresholdEvents
        .where((e) => e.threshold == threshold && e.crossed)
        .toList();
    return crossings.isEmpty ? null : crossings.last;
  }

  // MARK: - Statistics

  ThresholdStatistics getThresholdStatistics() {
    final now = DateTime.now();
    final last24Hours = now.subtract(const Duration(hours: 24));
    final recentEvents = _thresholdEvents
        .where((e) => e.timestamp.isAfter(last24Hours))
        .toList();

    final crossingsByThreshold = <MemoryThreshold, List<ThresholdEvent>>{};
    for (final event in recentEvents.where((e) => e.crossed)) {
      crossingsByThreshold.putIfAbsent(event.threshold, () => []).add(event);
    }
    final crossingCounts = crossingsByThreshold.map(
      (key, value) => MapEntry(key, value.length),
    );

    final currentlyCrossed = getCrossedThresholds();

    return ThresholdStatistics(
      currentlyCrossedThresholds: currentlyCrossed,
      crossingsLast24Hours: crossingCounts,
      totalEventsRecorded: _thresholdEvents.length,
      lastCheckTime: _lastThresholdCheck,
    );
  }

  // MARK: - Notifications

  void _postThresholdNotification({
    required MemoryThreshold threshold,
    required bool crossed,
    required MemoryMonitoringStats stats,
  }) {
    final thresholdInfo = ThresholdNotificationInfo(
      threshold: threshold,
      crossed: crossed,
      availableMemory: stats.availableMemory,
      timestamp: DateTime.now(),
    );

    _thresholdNotifications.add(thresholdInfo);
  }

  // MARK: - Cleanup

  void dispose() {
    _thresholdNotifications.close();
  }

  // MARK: - Helper

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
