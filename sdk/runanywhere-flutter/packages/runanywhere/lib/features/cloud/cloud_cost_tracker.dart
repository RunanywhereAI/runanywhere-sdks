/// Cloud Cost Tracker
///
/// Tracks cumulative cloud API costs across requests.
/// Mirrors Swift CloudCostTracker actor from Features/Cloud/CloudCostTracker.swift
library cloud_cost_tracker;

// MARK: - Cloud Cost Summary

/// Summary of cloud API costs.
///
/// Matches Swift CloudCostSummary struct.
class CloudCostSummary {
  /// Total cost across all providers
  final double totalCostUSD;

  /// Total input tokens sent to cloud
  final int totalInputTokens;

  /// Total output tokens received from cloud
  final int totalOutputTokens;

  /// Total number of cloud requests
  final int totalRequests;

  /// Number of requests per provider
  final Map<String, int> requestsByProvider;

  /// Cost per provider in USD
  final Map<String, double> costByProvider;

  const CloudCostSummary({
    required this.totalCostUSD,
    required this.totalInputTokens,
    required this.totalOutputTokens,
    required this.totalRequests,
    required this.requestsByProvider,
    required this.costByProvider,
  });
}

// MARK: - Cloud Cost Tracker

/// Tracks cumulative cloud API costs for budget monitoring.
///
/// Matches Swift CloudCostTracker actor.
///
/// Usage:
/// ```dart
/// final costs = CloudCostTracker.shared.summary;
/// print('Total cloud cost: \$${costs.totalCostUSD}');
/// print('Requests: ${costs.totalRequests}');
/// ```
class CloudCostTracker {
  /// Shared singleton
  static final CloudCostTracker shared = CloudCostTracker._();

  CloudCostTracker._();

  // MARK: - State

  double _totalCostUSD = 0;
  int _totalInputTokens = 0;
  int _totalOutputTokens = 0;
  int _totalRequests = 0;
  final Map<String, int> _requestsByProvider = {};
  final Map<String, double> _costByProvider = {};

  // MARK: - Recording

  /// Record a cloud request cost
  void recordRequest({
    required String providerId,
    required int inputTokens,
    required int outputTokens,
    required double costUSD,
  }) {
    _totalCostUSD += costUSD;
    _totalInputTokens += inputTokens;
    _totalOutputTokens += outputTokens;
    _totalRequests += 1;
    _requestsByProvider[providerId] =
        (_requestsByProvider[providerId] ?? 0) + 1;
    _costByProvider[providerId] =
        (_costByProvider[providerId] ?? 0) + costUSD;
  }

  // MARK: - Querying

  /// Get cost summary
  CloudCostSummary get summary => CloudCostSummary(
        totalCostUSD: _totalCostUSD,
        totalInputTokens: _totalInputTokens,
        totalOutputTokens: _totalOutputTokens,
        totalRequests: _totalRequests,
        requestsByProvider: Map.unmodifiable(_requestsByProvider),
        costByProvider: Map.unmodifiable(_costByProvider),
      );

  /// Reset all tracked costs
  void reset() {
    _totalCostUSD = 0;
    _totalInputTokens = 0;
    _totalOutputTokens = 0;
    _totalRequests = 0;
    _requestsByProvider.clear();
    _costByProvider.clear();
  }

  /// Check if adding a cost would exceed a budget
  bool wouldExceedBudget(double costUSD, double budgetUSD) {
    if (budgetUSD <= 0) return false;
    return (_totalCostUSD + costUSD) > budgetUSD;
  }
}
