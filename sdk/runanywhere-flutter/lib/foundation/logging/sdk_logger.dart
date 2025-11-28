import 'package:logger/logger.dart';

/// SDK logger for structured logging
class SDKLogger {
  final Logger _logger;
  final String? category;

  SDKLogger({this.category}) : _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      printTime: true,
    ),
  );

  /// Log debug message
  void debug(String message) {
    _logger.d('${category != null ? '[$category] ' : ''}$message');
  }

  /// Log info message
  void info(String message) {
    _logger.i('${category != null ? '[$category] ' : ''}$message');
  }

  /// Log warning message
  void warning(String message) {
    _logger.w('${category != null ? '[$category] ' : ''}$message');
  }

  /// Log error message
  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.e(
      '${category != null ? '[$category] ' : ''}$message',
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Log fatal error
  void fatal(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.f(
      '${category != null ? '[$category] ' : ''}$message',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

