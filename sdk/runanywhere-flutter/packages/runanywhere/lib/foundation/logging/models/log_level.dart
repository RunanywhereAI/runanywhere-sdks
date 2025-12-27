/// Log severity levels
///
/// Aligned with iOS: Sources/RunAnywhere/Foundation/Logging/Models/LogLevel.swift
enum LogLevel implements Comparable<LogLevel> {
  /// Debug level - for development and debugging
  debug(0),

  /// Info level - general informational messages
  info(1),

  /// Warning level - potentially harmful situations
  warning(2),

  /// Error level - error events that might still allow the app to continue
  error(3),

  /// Fault level - severe errors that will prevent the app from continuing
  fault(4);

  const LogLevel(this.value);

  /// Numeric value for comparison
  final int value;

  @override
  int compareTo(LogLevel other) => value.compareTo(other.value);

  /// Check if this level is at least as severe as another
  bool operator >=(LogLevel other) => value >= other.value;

  /// Check if this level is more severe than another
  bool operator >(LogLevel other) => value > other.value;

  /// Check if this level is less severe than another
  bool operator <(LogLevel other) => value < other.value;

  /// Check if this level is at most as severe as another
  bool operator <=(LogLevel other) => value <= other.value;

  @override
  String toString() {
    switch (this) {
      case LogLevel.debug:
        return 'debug';
      case LogLevel.info:
        return 'info';
      case LogLevel.warning:
        return 'warning';
      case LogLevel.error:
        return 'error';
      case LogLevel.fault:
        return 'fault';
    }
  }
}
