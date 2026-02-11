/// Cloud Provider Manager
///
/// Manages cloud provider registration and selection.
/// Mirrors Swift CloudProviderManager actor from Features/Cloud/CloudProviderManager.swift
library cloud_provider_manager;

import 'package:runanywhere/features/cloud/cloud_provider.dart';

// MARK: - Cloud Provider Manager

/// Central manager for cloud AI providers.
///
/// Handles provider registration, selection, and lifecycle.
///
/// Matches Swift CloudProviderManager actor.
class CloudProviderManager {
  /// Shared singleton instance
  static final CloudProviderManager shared = CloudProviderManager._();

  CloudProviderManager._();

  // MARK: - State

  final Map<String, CloudProvider> _providers = {};
  String? _defaultProviderId;

  // MARK: - Registration

  /// Register a cloud provider
  void register(CloudProvider provider) {
    _providers[provider.providerId] = provider;

    // First registered provider becomes the default
    _defaultProviderId ??= provider.providerId;
  }

  /// Unregister a cloud provider
  void unregister(String providerId) {
    _providers.remove(providerId);

    if (_defaultProviderId == providerId) {
      _defaultProviderId = _providers.keys.firstOrNull;
    }
  }

  /// Set the default provider
  void setDefault(String providerId) {
    if (!_providers.containsKey(providerId)) {
      throw CloudProviderException.providerNotFound(providerId);
    }
    _defaultProviderId = providerId;
  }

  // MARK: - Provider Access

  /// Get the default cloud provider
  CloudProvider getDefault() {
    final id = _defaultProviderId;
    if (id == null || !_providers.containsKey(id)) {
      throw CloudProviderException.noProviderRegistered();
    }
    return _providers[id]!;
  }

  /// Get a specific cloud provider by ID
  CloudProvider get(String providerId) {
    final provider = _providers[providerId];
    if (provider == null) {
      throw CloudProviderException.providerNotFound(providerId);
    }
    return provider;
  }

  /// Get all registered provider IDs
  List<String> get registeredProviderIds => List.unmodifiable(_providers.keys);

  /// Check if any providers are registered
  bool get hasProviders => _providers.isNotEmpty;

  /// Remove all registered providers
  void removeAll() {
    _providers.clear();
    _defaultProviderId = null;
  }
}
