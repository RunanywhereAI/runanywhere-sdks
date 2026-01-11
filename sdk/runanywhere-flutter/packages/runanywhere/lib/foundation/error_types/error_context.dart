/// Context information captured when an error occurs
/// Includes stack trace, source location, and timing information
/// Matches iOS ErrorContext from Foundation/ErrorTypes/ErrorContext.swift
class ErrorContext {
  /// The stack trace at the point of error capture
  final StackTrace? stackTrace;

  /// The file where the error was captured
  final String file;

  /// The line number where the error was captured
  final int line;

  /// The function where the error was captured
  final String function;

  /// Timestamp when the error was captured
  final DateTime timestamp;

  /// Thread name/ID where the error occurred
  final String threadInfo;

  /// Initialize with automatic capture of current context
  ErrorContext({
    this.stackTrace,
    this.file = '',
    this.line = 0,
    this.function = '',
    DateTime? timestamp,
    String? threadInfo,
  })  : timestamp = timestamp ?? DateTime.now(),
        threadInfo = threadInfo ?? 'main';

  /// Create context from stack trace
  factory ErrorContext.capture() {
    final trace = StackTrace.current;
    return ErrorContext(
      stackTrace: trace,
      timestamp: DateTime.now(),
      threadInfo: 'main',
    );
  }

  /// Initialize with explicit values (for testing or deserialization)
  factory ErrorContext.explicit({
    required StackTrace? stackTrace,
    required String file,
    required int line,
    required String function,
    required DateTime timestamp,
    required String threadInfo,
  }) {
    return ErrorContext(
      stackTrace: stackTrace,
      file: file,
      line: line,
      function: function,
      timestamp: timestamp,
      threadInfo: threadInfo,
    );
  }

  /// A formatted string representation of the stack trace
  String get formattedStackTrace {
    if (stackTrace == null) return '';

    final lines = stackTrace.toString().split('\n');
    final relevantFrames = lines
        .where(
            (frame) => frame.contains('runanywhere') || frame.contains('lib/'))
        .take(15)
        .toList();

    if (relevantFrames.isEmpty) {
      return lines.take(10).join('\n');
    }

    return relevantFrames
        .asMap()
        .entries
        .map((e) => '  ${e.key}. ${e.value}')
        .join('\n');
  }

  /// A compact single-line location string
  String get locationString => '$file:$line in $function';

  /// Full formatted context for logging
  String get formattedContext => '''
Location: $locationString
Thread: $threadInfo
Time: ${timestamp.toIso8601String()}
Stack Trace:
$formattedStackTrace
''';

  /// Convert to map for serialization
  Map<String, dynamic> toJson() => {
        'file': file,
        'line': line,
        'function': function,
        'timestamp': timestamp.toIso8601String(),
        'threadInfo': threadInfo,
        'stackTrace': stackTrace?.toString(),
      };

  /// Create from map
  factory ErrorContext.fromJson(Map<String, dynamic> json) {
    return ErrorContext(
      file: json['file'] as String? ?? '',
      line: json['line'] as int? ?? 0,
      function: json['function'] as String? ?? '',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
      threadInfo: json['threadInfo'] as String? ?? 'main',
    );
  }
}

/// Global function to capture error context at the call site
/// Use this when throwing errors to capture the stack trace
ErrorContext captureErrorContext() => ErrorContext.capture();

/// A wrapper that attaches context to any error
class ContextualError implements Exception {
  /// The underlying error
  final Object error;

  /// The captured context
  final ErrorContext context;

  /// Initialize with an error and automatically capture context
  ContextualError(this.error, {ErrorContext? context})
      : context = context ?? ErrorContext.capture();

  @override
  String toString() {
    final errorDesc =
        error is Exception ? (error as Exception).toString() : error.toString();
    return errorDesc;
  }

  /// Get error description
  String? get errorDescription {
    if (error is Exception) {
      return error.toString();
    }
    return error.toString();
  }
}

/// Extension to add context to any error
extension ErrorContextExtension on Object {
  /// Wrap this error with context information
  ContextualError withContext() => ContextualError(this);

  /// Extract context if this is a ContextualError
  ErrorContext? get errorContext {
    if (this is ContextualError) {
      return (this as ContextualError).context;
    }
    return null;
  }

  /// Get the underlying error if wrapped
  Object get underlyingErrorValue {
    if (this is ContextualError) {
      return (this as ContextualError).error;
    }
    return this;
  }
}
