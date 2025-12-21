// Reusable async retry utility for network operations.
// Matches iOS NetworkRetry from Foundation/Utilities/NetworkRetry.swift.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import '../error_types/sdk_error.dart';
import '../logging/sdk_logger.dart';

/// Configuration for retry behavior.
/// Matches iOS RetryConfig.
class RetryConfig {
  /// Maximum number of attempts (including initial attempt)
  final int maxAttempts;

  /// Delay between retries in seconds
  final double delaySeconds;

  /// Whether to use exponential backoff
  final bool exponentialBackoff;

  /// Default retry configuration
  static const RetryConfig defaultConfig = RetryConfig(
    maxAttempts: 3,
    delaySeconds: 2.0,
    exponentialBackoff: false,
  );

  /// Aggressive retry configuration with exponential backoff
  static const RetryConfig aggressive = RetryConfig(
    maxAttempts: 5,
    delaySeconds: 1.0,
    exponentialBackoff: true,
  );

  const RetryConfig({
    this.maxAttempts = 3,
    this.delaySeconds = 2.0,
    this.exponentialBackoff = false,
  });
}

/// Reusable retry utility for async operations.
/// Matches iOS NetworkRetry enum pattern.
class NetworkRetry {
  static final SDKLogger _logger = SDKLogger(category: 'NetworkRetry');

  NetworkRetry._();

  /// Execute an async operation with retry logic.
  ///
  /// [config] - Retry configuration
  /// [operation] - The async operation to execute
  ///
  /// Returns the result of the operation.
  /// Throws the last error if all retries fail.
  static Future<T> execute<T>({
    RetryConfig config = RetryConfig.defaultConfig,
    required Future<T> Function() operation,
  }) async {
    Object? lastError;

    for (int attempt = 1; attempt <= config.maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;

        // Don't retry non-retryable errors
        if (!isRetryable(error)) {
          rethrow;
        }

        // Don't wait after the last attempt
        if (attempt >= config.maxAttempts) {
          break;
        }

        final delay = config.exponentialBackoff
            ? config.delaySeconds * math.pow(2.0, attempt - 1)
            : config.delaySeconds;

        _logger.debug('Attempt $attempt failed, retrying in ${delay}s: $error');
        await Future<void>.delayed(
            Duration(milliseconds: (delay * 1000).round()));
      }
    }

    if (lastError != null) {
      throw lastError;
    }

    throw SDKError.networkError(
        'Operation failed after ${config.maxAttempts} attempts');
  }

  /// Execute an async operation with retry, returning null on failure instead
  /// of throwing.
  static Future<T?> executeOptional<T>({
    RetryConfig config = RetryConfig.defaultConfig,
    required Future<T> Function() operation,
  }) async {
    try {
      return await execute(config: config, operation: operation);
    } catch (_) {
      return null;
    }
  }

  /// Check if an error is retryable.
  static bool isRetryable(Object error) {
    // SDK errors
    if (error is SDKError) {
      switch (error.type) {
        case SDKErrorType.networkError:
        case SDKErrorType.timeout:
        case SDKErrorType.serverError:
        case SDKErrorType.networkUnavailable:
          return true;
        default:
          return false;
      }
    }

    // SocketException (network connection issues)
    if (error is SocketException) {
      return true;
    }

    // HttpException (HTTP-level errors that might be transient)
    if (error is HttpException) {
      return true;
    }

    // TimeoutException
    if (error is TimeoutException) {
      return true;
    }

    return false;
  }
}
