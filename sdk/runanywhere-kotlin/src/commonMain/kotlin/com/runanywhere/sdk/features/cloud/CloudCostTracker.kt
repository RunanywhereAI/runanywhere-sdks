/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Tracks cumulative cloud API costs across requests.
 * Mirrors Swift CloudCostTracker.swift exactly.
 */

package com.runanywhere.sdk.features.cloud

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Tracks cumulative cloud API costs for budget monitoring.
 *
 * Usage:
 * ```kotlin
 * val costs = CloudCostTracker.summary()
 * println("Total cloud cost: $${costs.totalCostUSD}")
 * ```
 */
object CloudCostTracker {

    private val mutex = Mutex()

    private var totalCostUSD: Double = 0.0
    private var totalInputTokens: Int = 0
    private var totalOutputTokens: Int = 0
    private var totalRequests: Int = 0
    private var requestsByProvider: MutableMap<String, Int> = mutableMapOf()
    private var costByProvider: MutableMap<String, Double> = mutableMapOf()

    /** Record a cloud request cost */
    suspend fun recordRequest(
        providerId: String,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double,
    ) {
        mutex.withLock {
            totalCostUSD += costUSD
            totalInputTokens += inputTokens
            totalOutputTokens += outputTokens
            totalRequests += 1
            requestsByProvider[providerId] = (requestsByProvider[providerId] ?: 0) + 1
            costByProvider[providerId] = (costByProvider[providerId] ?: 0.0) + costUSD
        }
    }

    /** Get cost summary */
    suspend fun summary(): CloudCostSummary {
        mutex.withLock {
            return CloudCostSummary(
                totalCostUSD = totalCostUSD,
                totalInputTokens = totalInputTokens,
                totalOutputTokens = totalOutputTokens,
                totalRequests = totalRequests,
                requestsByProvider = requestsByProvider.toMap(),
                costByProvider = costByProvider.toMap(),
            )
        }
    }

    /** Reset all tracked costs */
    suspend fun reset() {
        mutex.withLock {
            totalCostUSD = 0.0
            totalInputTokens = 0
            totalOutputTokens = 0
            totalRequests = 0
            requestsByProvider.clear()
            costByProvider.clear()
        }
    }

    /** Check if adding a cost would exceed a budget */
    suspend fun wouldExceedBudget(costUSD: Double, budgetUSD: Double): Boolean {
        if (budgetUSD <= 0) return false
        mutex.withLock {
            return (totalCostUSD + costUSD) > budgetUSD
        }
    }
}

/** Summary of cloud API costs */
data class CloudCostSummary(
    val totalCostUSD: Double,
    val totalInputTokens: Int,
    val totalOutputTokens: Int,
    val totalRequests: Int,
    val requestsByProvider: Map<String, Int>,
    val costByProvider: Map<String, Double>,
)
