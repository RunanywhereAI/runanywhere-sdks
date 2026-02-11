/// Cloud Provider
///
/// Abstract interface for cloud AI providers (OpenAI-compatible APIs).
/// Mirrors Swift CloudProvider protocol from Public/Extensions/Cloud/CloudProvider.swift
library cloud_provider;

import 'package:runanywhere/features/cloud/cloud_types.dart';

// MARK: - Cloud Provider Interface

/// Interface for cloud AI inference providers.
///
/// Implement this to add a custom cloud provider for hybrid routing.
/// The SDK ships with [OpenAICompatibleProvider] which works with any
/// OpenAI-compatible API (OpenAI, Groq, Together, Ollama, etc.).
///
/// Example:
/// ```dart
/// final provider = OpenAICompatibleProvider(
///   apiKey: 'sk-...',
///   model: 'gpt-4o-mini',
/// );
/// CloudProviderManager.shared.register(provider);
/// ```
abstract class CloudProvider {
  /// Unique identifier for this provider
  String get providerId;

  /// Human-readable display name
  String get displayName;

  /// Generate text (non-streaming)
  Future<CloudGenerationResult> generate(
    String prompt,
    CloudGenerationOptions options,
  );

  /// Generate text with streaming
  Stream<String> generateStream(
    String prompt,
    CloudGenerationOptions options,
  );

  /// Check if the provider is available and configured
  Future<bool> isAvailable();
}

// MARK: - Cloud Provider Errors

/// Errors from cloud provider operations.
///
/// Matches Swift CloudProviderError enum.
enum CloudProviderErrorType {
  invalidURL,
  httpError,
  noProviderRegistered,
  providerNotFound,
  providerUnavailable,
  decodingError,
  budgetExceeded,
  latencyTimeout,
}

/// Exception thrown by cloud provider operations
class CloudProviderException implements Exception {
  final CloudProviderErrorType type;
  final String message;
  final int? statusCode;

  const CloudProviderException(this.type, this.message, {this.statusCode});

  factory CloudProviderException.invalidURL() =>
      const CloudProviderException(
        CloudProviderErrorType.invalidURL,
        'Invalid cloud provider URL',
      );

  factory CloudProviderException.httpError(int statusCode) =>
      CloudProviderException(
        CloudProviderErrorType.httpError,
        'Cloud API returned HTTP $statusCode',
        statusCode: statusCode,
      );

  factory CloudProviderException.noProviderRegistered() =>
      const CloudProviderException(
        CloudProviderErrorType.noProviderRegistered,
        'No cloud provider registered',
      );

  factory CloudProviderException.providerNotFound(String id) =>
      CloudProviderException(
        CloudProviderErrorType.providerNotFound,
        'Cloud provider not found: $id',
      );

  factory CloudProviderException.providerUnavailable(String id) =>
      CloudProviderException(
        CloudProviderErrorType.providerUnavailable,
        'Cloud provider unavailable: $id',
      );

  factory CloudProviderException.decodingError(String detail) =>
      CloudProviderException(
        CloudProviderErrorType.decodingError,
        'Failed to decode cloud response: $detail',
      );

  factory CloudProviderException.budgetExceeded({
    required double currentUSD,
    required double capUSD,
  }) =>
      CloudProviderException(
        CloudProviderErrorType.budgetExceeded,
        'Cloud budget exceeded: current \$${currentUSD.toStringAsFixed(4)} >= cap \$${capUSD.toStringAsFixed(4)}',
      );

  factory CloudProviderException.latencyTimeout({
    required int maxMs,
    required double actualMs,
  }) =>
      CloudProviderException(
        CloudProviderErrorType.latencyTimeout,
        'Local latency timeout: ${actualMs.toStringAsFixed(1)}ms exceeded ${maxMs}ms limit',
      );

  @override
  String toString() => 'CloudProviderException($type): $message';
}
