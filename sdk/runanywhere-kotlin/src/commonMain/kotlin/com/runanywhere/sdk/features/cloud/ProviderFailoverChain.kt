/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Provider failover chain with priority ordering and circuit breaker.
 * Mirrors Swift ProviderFailoverChain.swift exactly.
 */

package com.runanywhere.sdk.features.cloud

import com.runanywhere.sdk.public.extensions.Cloud.CloudGenerationOptions
import com.runanywhere.sdk.public.extensions.Cloud.CloudGenerationResult
import com.runanywhere.sdk.public.extensions.Cloud.CloudProvider
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlin.time.Duration.Companion.seconds

/**
 * Manages a priority-ordered chain of cloud providers with automatic failover.
 *
 * If the primary provider fails, the chain tries the next provider.
 * Includes a simple circuit breaker to avoid repeatedly calling unhealthy providers.
 */
class ProviderFailoverChain(
    private val circuitBreakerThreshold: Int = 3,
    private val circuitBreakerCooldownSeconds: Long = 60,
) {

    private data class ProviderEntry(
        val provider: CloudProvider,
        val priority: Int,
        var consecutiveFailures: Int = 0,
        var lastFailureTime: Instant? = null,
        var isCircuitOpen: Boolean = false,
    )

    private val mutex = Mutex()
    private val entries = mutableListOf<ProviderEntry>()

    /** Add a provider with a priority (higher = preferred) */
    suspend fun addProvider(provider: CloudProvider, priority: Int) {
        mutex.withLock {
            entries.add(ProviderEntry(provider = provider, priority = priority))
            entries.sortByDescending { it.priority }
        }
    }

    /** Remove a provider by ID */
    suspend fun removeProvider(providerId: String) {
        mutex.withLock {
            entries.removeAll { it.provider.providerId == providerId }
        }
    }

    /** Try generation across the provider chain with failover */
    suspend fun generate(
        prompt: String,
        options: CloudGenerationOptions,
    ): CloudGenerationResult {
        var lastError: Exception? = null

        // Reset half-open circuits where cooldown has elapsed
        mutex.withLock {
            for (i in entries.indices) {
                val entry = entries[i]
                if (entry.isCircuitOpen) {
                    val lastFailure = entry.lastFailureTime
                    if (lastFailure != null) {
                        val elapsed = Clock.System.now() - lastFailure
                        if (elapsed >= circuitBreakerCooldownSeconds.seconds) {
                            // Cooldown elapsed, try half-open
                            entries[i] = entry.copy(isCircuitOpen = false)
                        }
                    }
                }
            }
        }

        // Execute outside mutex to avoid holding lock during network calls
        val snapshot = mutex.withLock { entries.toList() }

        for (entry in snapshot) {
            if (entry.isCircuitOpen) continue

            try {
                val result = entry.provider.generate(prompt = prompt, options = options)

                // Success: reset failure count
                mutex.withLock {
                    val idx = entries.indexOfFirst { it.provider.providerId == entry.provider.providerId }
                    if (idx >= 0) {
                        entries[idx] = entries[idx].copy(consecutiveFailures = 0, isCircuitOpen = false)
                    }
                }

                return result
            } catch (e: Exception) {
                lastError = e

                mutex.withLock {
                    val idx = entries.indexOfFirst { it.provider.providerId == entry.provider.providerId }
                    if (idx >= 0) {
                        val updated = entries[idx].copy(
                            consecutiveFailures = entries[idx].consecutiveFailures + 1,
                            lastFailureTime = Clock.System.now(),
                        )
                        entries[idx] = if (updated.consecutiveFailures >= circuitBreakerThreshold) {
                            updated.copy(isCircuitOpen = true)
                        } else {
                            updated
                        }
                    }
                }
            }
        }

        throw lastError ?: CloudProviderError.NoProviderRegistered()
    }

    /** Try streaming generation across the provider chain */
    suspend fun generateStream(
        prompt: String,
        options: CloudGenerationOptions,
    ): Flow<String> {
        val snapshot = mutex.withLock { entries.toList() }

        for (entry in snapshot) {
            if (entry.isCircuitOpen) {
                val lastFailure = entry.lastFailureTime
                if (lastFailure != null) {
                    val elapsed = Clock.System.now() - lastFailure
                    if (elapsed < circuitBreakerCooldownSeconds.seconds) {
                        continue
                    }
                }
            }

            if (entry.provider.isAvailable()) {
                mutex.withLock {
                    val idx = entries.indexOfFirst { it.provider.providerId == entry.provider.providerId }
                    if (idx >= 0) {
                        entries[idx] = entries[idx].copy(consecutiveFailures = 0)
                    }
                }
                return entry.provider.generateStream(prompt = prompt, options = options)
            }
        }

        throw CloudProviderError.NoProviderRegistered()
    }

    /** Get health status of all providers */
    suspend fun healthStatus(): List<ProviderHealthStatus> {
        mutex.withLock {
            return entries.map { entry ->
                ProviderHealthStatus(
                    providerId = entry.provider.providerId,
                    displayName = entry.provider.displayName,
                    priority = entry.priority,
                    consecutiveFailures = entry.consecutiveFailures,
                    isCircuitOpen = entry.isCircuitOpen,
                    lastFailureTimeMs = entry.lastFailureTime?.toEpochMilliseconds(),
                )
            }
        }
    }
}

/** Health status of a provider in the failover chain */
data class ProviderHealthStatus(
    val providerId: String,
    val displayName: String,
    val priority: Int,
    val consecutiveFailures: Int,
    val isCircuitOpen: Boolean,
    val lastFailureTimeMs: Long?,
)
