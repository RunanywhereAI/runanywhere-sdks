/// Provider Failover Chain
///
/// Provider failover chain with priority ordering and circuit breaker.
/// Mirrors Swift ProviderFailoverChain actor from Features/Cloud/ProviderFailoverChain.swift
library provider_failover_chain;

import 'package:runanywhere/features/cloud/cloud_provider.dart';
import 'package:runanywhere/features/cloud/cloud_types.dart';

// MARK: - Provider Health Status

/// Health status of a provider in the failover chain.
///
/// Matches Swift ProviderHealthStatus struct.
class ProviderHealthStatus {
  final String providerId;
  final String displayName;
  final int priority;
  final int consecutiveFailures;
  final bool isCircuitOpen;
  final DateTime? lastFailureTime;

  const ProviderHealthStatus({
    required this.providerId,
    required this.displayName,
    required this.priority,
    required this.consecutiveFailures,
    required this.isCircuitOpen,
    this.lastFailureTime,
  });
}

// MARK: - Provider Entry (internal)

class _ProviderEntry {
  final CloudProvider provider;
  final int priority;
  int consecutiveFailures;
  DateTime? lastFailureTime;
  bool isCircuitOpen;

  _ProviderEntry({
    required this.provider,
    required this.priority,
    this.consecutiveFailures = 0,
    this.lastFailureTime,
    this.isCircuitOpen = false,
  });
}

// MARK: - Provider Failover Chain

/// Manages a priority-ordered chain of cloud providers with automatic failover.
///
/// If the primary provider fails, the chain tries the next provider.
/// Includes a simple circuit breaker to avoid repeatedly calling unhealthy providers.
///
/// Matches Swift ProviderFailoverChain actor.
///
/// ```dart
/// final chain = ProviderFailoverChain();
/// chain.addProvider(openaiProvider, priority: 100);
/// chain.addProvider(groqProvider, priority: 50); // lower priority = fallback
/// ```
class ProviderFailoverChain {
  // MARK: - Configuration

  /// Number of consecutive failures before circuit opens
  final int circuitBreakerThreshold;

  /// How long to wait before trying an open circuit again
  final Duration circuitBreakerCooldown;

  // MARK: - State

  final List<_ProviderEntry> _entries = [];

  // MARK: - Init

  ProviderFailoverChain({
    this.circuitBreakerThreshold = 3,
    int circuitBreakerCooldownSeconds = 60,
  }) : circuitBreakerCooldown =
            Duration(seconds: circuitBreakerCooldownSeconds);

  // MARK: - Configuration

  /// Add a provider with a priority (higher = preferred)
  void addProvider(CloudProvider provider, {required int priority}) {
    _entries.add(_ProviderEntry(provider: provider, priority: priority));
    _entries.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Remove a provider by ID
  void removeProvider(String providerId) {
    _entries.removeWhere((e) => e.provider.providerId == providerId);
  }

  // MARK: - Execution

  /// Try generation across the provider chain with failover
  Future<CloudGenerationResult> generate(
    String prompt,
    CloudGenerationOptions options,
  ) async {
    Exception? lastError;

    for (final entry in _entries) {
      // Skip providers with open circuits (unless cooldown elapsed)
      if (entry.isCircuitOpen) {
        final lastFailure = entry.lastFailureTime;
        if (lastFailure != null) {
          final elapsed = DateTime.now().difference(lastFailure);
          if (elapsed < circuitBreakerCooldown) {
            continue;
          }
        }
        // Cooldown elapsed, try half-open
        entry.isCircuitOpen = false;
      }

      try {
        final result = await entry.provider.generate(prompt, options);

        // Success: reset failure count
        entry.consecutiveFailures = 0;
        entry.isCircuitOpen = false;

        return result;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());

        // Record failure
        entry.consecutiveFailures += 1;
        entry.lastFailureTime = DateTime.now();

        // Open circuit if threshold reached
        if (entry.consecutiveFailures >= circuitBreakerThreshold) {
          entry.isCircuitOpen = true;
        }
      }
    }

    throw lastError ?? CloudProviderException.noProviderRegistered();
  }

  /// Try streaming generation across the provider chain
  Stream<String> generateStream(
    String prompt,
    CloudGenerationOptions options,
  ) async* {
    for (final entry in _entries) {
      // Skip providers with open circuits (unless cooldown elapsed)
      if (entry.isCircuitOpen) {
        final lastFailure = entry.lastFailureTime;
        if (lastFailure != null) {
          final elapsed = DateTime.now().difference(lastFailure);
          if (elapsed < circuitBreakerCooldown) {
            continue;
          }
        }
        entry.isCircuitOpen = false;
      }

      // For streaming, return the first available provider's stream.
      // Failover during streaming is more complex and deferred to future.
      if (await entry.provider.isAvailable()) {
        entry.consecutiveFailures = 0;
        yield* entry.provider.generateStream(prompt, options);
        return;
      }
    }

    throw CloudProviderException.noProviderRegistered();
  }

  // MARK: - Health

  /// Get health status of all providers
  List<ProviderHealthStatus> get healthStatus => _entries
      .map((entry) => ProviderHealthStatus(
            providerId: entry.provider.providerId,
            displayName: entry.provider.displayName,
            priority: entry.priority,
            consecutiveFailures: entry.consecutiveFailures,
            isCircuitOpen: entry.isCircuitOpen,
            lastFailureTime: entry.lastFailureTime,
          ))
      .toList();
}
