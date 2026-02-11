//
//  CloudCostTracker.swift
//  RunAnywhere SDK
//
//  Tracks cumulative cloud API costs across requests.
//

import Foundation

// MARK: - Cloud Cost Tracker

/// Tracks cumulative cloud API costs for budget monitoring.
///
/// Usage:
/// ```swift
/// let costs = await RunAnywhere.cloudCostTracker.summary
/// print("Total cloud cost: $\(costs.totalCostUSD)")
/// print("Requests: \(costs.totalRequests)")
/// ```
public actor CloudCostTracker {

    /// Shared singleton
    public static let shared = CloudCostTracker()

    // MARK: - State

    private var totalCostUSD: Double = 0.0
    private var totalInputTokens: Int = 0
    private var totalOutputTokens: Int = 0
    private var totalRequests: Int = 0
    private var requestsByProvider: [String: Int] = [:]
    private var costByProvider: [String: Double] = [:]

    // MARK: - Recording

    /// Record a cloud request cost
    func recordRequest(
        providerId: String,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double
    ) {
        totalCostUSD += costUSD
        totalInputTokens += inputTokens
        totalOutputTokens += outputTokens
        totalRequests += 1
        requestsByProvider[providerId, default: 0] += 1
        costByProvider[providerId, default: 0.0] += costUSD
    }

    // MARK: - Querying

    /// Get cost summary
    public var summary: CloudCostSummary {
        CloudCostSummary(
            totalCostUSD: totalCostUSD,
            totalInputTokens: totalInputTokens,
            totalOutputTokens: totalOutputTokens,
            totalRequests: totalRequests,
            requestsByProvider: requestsByProvider,
            costByProvider: costByProvider
        )
    }

    /// Reset all tracked costs
    public func reset() {
        totalCostUSD = 0
        totalInputTokens = 0
        totalOutputTokens = 0
        totalRequests = 0
        requestsByProvider.removeAll()
        costByProvider.removeAll()
    }

    /// Check if adding a cost would exceed a budget
    func wouldExceedBudget(costUSD: Double, budgetUSD: Double) -> Bool {
        guard budgetUSD > 0 else { return false }
        return (totalCostUSD + costUSD) > budgetUSD
    }
}

// MARK: - Cloud Cost Summary

/// Summary of cloud API costs
public struct CloudCostSummary: Sendable {
    /// Total cost across all providers
    public let totalCostUSD: Double

    /// Total input tokens sent to cloud
    public let totalInputTokens: Int

    /// Total output tokens received from cloud
    public let totalOutputTokens: Int

    /// Total number of cloud requests
    public let totalRequests: Int

    /// Number of requests per provider
    public let requestsByProvider: [String: Int]

    /// Cost per provider in USD
    public let costByProvider: [String: Double]
}
