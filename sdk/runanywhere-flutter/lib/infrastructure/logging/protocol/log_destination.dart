import '../../../foundation/logging/models/log_entry.dart';
import '../../../foundation/logging/models/log_level.dart';

/// Protocol for log output destinations
/// Implementations handle writing logs to specific backends (Console, File, etc.)
/// Matches iOS LogDestination from Infrastructure/Logging/Protocol/LogDestination.swift
abstract class LogDestination {
  /// Unique identifier for this destination
  String get identifier;

  /// Human-readable name for this destination
  String get name;

  /// Whether this destination is currently available for writing
  bool get isAvailable;

  /// Write a log entry to this destination
  void write(LogEntry entry);

  /// Flush any pending writes
  void flush();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LogDestination && other.identifier == identifier;
  }

  @override
  int get hashCode => identifier.hashCode;
}

/// Console log destination - writes to stdout
class ConsoleLogDestination extends LogDestination {
  @override
  final String identifier = 'console';

  @override
  final String name = 'Console';

  @override
  bool get isAvailable => true;

  @override
  void write(LogEntry entry) {
    final levelPrefix = _levelPrefix(entry.level);
    final timestamp = entry.timestamp.toIso8601String();
    // ignore: avoid_print
    print('$timestamp [$levelPrefix] [${entry.category}] ${entry.message}');
  }

  @override
  void flush() {
    // Console output is immediate, no buffering
  }

  String _levelPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.fault:
        return 'FAULT';
    }
  }
}

/// File log destination - writes to a file
class FileLogDestination extends LogDestination {
  @override
  final String identifier = 'file';

  @override
  final String name = 'File';

  final String filePath;
  final List<String> _buffer = [];
  final int bufferSize;

  FileLogDestination({
    required this.filePath,
    this.bufferSize = 100,
  });

  @override
  bool get isAvailable => true;

  @override
  void write(LogEntry entry) {
    final line = '${entry.timestamp.toIso8601String()} [${entry.level.name}] [${entry.category}] ${entry.message}';
    _buffer.add(line);

    if (_buffer.length >= bufferSize) {
      flush();
    }
  }

  @override
  void flush() {
    if (_buffer.isEmpty) return;

    // In a real implementation, this would write to the file
    // For now, we just clear the buffer
    _buffer.clear();
  }
}
