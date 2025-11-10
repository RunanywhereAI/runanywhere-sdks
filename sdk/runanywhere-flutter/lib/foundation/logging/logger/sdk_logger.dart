import 'package:logger/logger.dart';

/// SDK Logger with category support
/// Similar to Swift SDK's SDKLogger
class SDKLogger {
  final String category;
  final Logger _logger;

  SDKLogger({required this.category})
    : _logger = Logger(
        printer: PrettyPrinter(
          methodCount: 0,
          errorMethodCount: 8,
          lineLength: 120,
          colors: true,
          printEmojis: true,
        ),
      );

  void debug(String message) {
    _logger.d('[$category] $message');
  }

  void info(String message) {
    _logger.i('[$category] $message');
  }

  void warning(String message) {
    _logger.w('[$category] $message');
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.e('[$category] $message', error: error, stackTrace: stackTrace);
  }

  void fatal(String message, [Object? error, StackTrace? stackTrace]) {
    _logger.f('[$category] $message', error: error, stackTrace: stackTrace);
  }
}
