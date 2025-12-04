import '../../models/configuration/configuration_data.dart';

/// Protocol for configuration services.
/// Matches iOS ConfigurationServiceProtocol from Core/Protocols/Configuration/ConfigurationServiceProtocol.swift
///
/// In Dart, we use abstract interface classes instead of Swift protocols with Actor.
/// Async operations use Future instead of async functions on actors.
abstract interface class ConfigurationServiceProtocol {
  /// Get the current configuration
  ConfigurationData? getConfiguration();

  /// Ensure configuration is loaded before use
  Future<void> ensureConfigurationLoaded();

  /// Update configuration with a transformer function
  Future<void> updateConfiguration(
    ConfigurationData Function(ConfigurationData current) updater,
  );

  /// Sync configuration to cloud
  Future<void> syncToCloud();

  /// Load configuration on app launch
  Future<ConfigurationData> loadConfigurationOnLaunch({required String apiKey});

  /// Set consumer-provided configuration
  Future<void> setConsumerConfiguration(ConfigurationData config);

  /// Load configuration with fallback to defaults
  Future<ConfigurationData> loadConfigurationWithFallback({required String apiKey});

  /// Clear cached configuration
  Future<void> clearCache();

  /// Start background sync process
  Future<void> startBackgroundSync({required String apiKey});
}

/// Error types for configuration service operations
sealed class ConfigurationServiceError implements Exception {
  const ConfigurationServiceError();
}

/// Configuration not found error
class ConfigurationNotFoundError extends ConfigurationServiceError {
  final String message;

  const ConfigurationNotFoundError([this.message = 'Configuration not found']);

  @override
  String toString() => 'ConfigurationNotFoundError: $message';
}

/// Configuration sync failed error
class ConfigurationSyncError extends ConfigurationServiceError {
  final String message;
  final Object? underlyingError;

  const ConfigurationSyncError(this.message, [this.underlyingError]);

  @override
  String toString() => 'ConfigurationSyncError: $message';
}

/// Invalid configuration error
class InvalidConfigurationError extends ConfigurationServiceError {
  final String message;
  final List<String> validationErrors;

  const InvalidConfigurationError(this.message, [this.validationErrors = const []]);

  @override
  String toString() => 'InvalidConfigurationError: $message';
}
