import 'dart:async';

import '../../core/models/configuration/configuration_data.dart';

/// Configuration-specific repository methods
/// ConfigurationRepositoryImpl will implement both this AND Repository<ConfigurationData>
/// Matches iOS ConfigurationRepository from ConfigurationRepository.swift
abstract class ConfigurationRepository {
  /// Fetch remote configuration using API key
  Future<ConfigurationData?> fetchRemoteConfiguration(String apiKey);

  /// Set consumer configuration
  Future<void> setConsumerConfiguration(ConfigurationData config);

  /// Get consumer configuration
  Future<ConfigurationData?> getConsumerConfiguration();

  /// Get SDK default configuration
  ConfigurationData getSDKDefaultConfiguration();
}
