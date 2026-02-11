/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Manages cloud provider registration and selection.
 * Thread-safe singleton using Mutex.
 *
 * Mirrors Swift CloudProviderManager.swift exactly.
 */

package com.runanywhere.sdk.features.cloud

import com.runanywhere.sdk.public.extensions.Cloud.CloudProvider
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// MARK: - Cloud Provider Manager

/**
 * Central manager for cloud AI providers.
 *
 * Handles provider registration, selection, and lifecycle.
 * Thread-safe via Mutex (Kotlin equivalent of Swift actor isolation).
 *
 * Mirrors Swift CloudProviderManager actor exactly.
 */
object CloudProviderManager {

    // MARK: - State

    private val mutex = Mutex()
    private val providers = mutableMapOf<String, CloudProvider>()
    private var defaultProviderId: String? = null

    // MARK: - Registration

    /**
     * Register a cloud provider.
     */
    suspend fun register(provider: CloudProvider) {
        mutex.withLock {
            providers[provider.providerId] = provider

            // First registered provider becomes the default
            if (defaultProviderId == null) {
                defaultProviderId = provider.providerId
            }
        }
    }

    /**
     * Unregister a cloud provider.
     */
    suspend fun unregister(providerId: String) {
        mutex.withLock {
            providers.remove(providerId)

            if (defaultProviderId == providerId) {
                defaultProviderId = providers.keys.firstOrNull()
            }
        }
    }

    /**
     * Set the default provider.
     *
     * @throws CloudProviderError.ProviderNotFound if the provider is not registered
     */
    suspend fun setDefault(providerId: String) {
        mutex.withLock {
            if (!providers.containsKey(providerId)) {
                throw CloudProviderError.ProviderNotFound(providerId)
            }
            defaultProviderId = providerId
        }
    }

    // MARK: - Provider Access

    /**
     * Get the default cloud provider.
     *
     * @throws CloudProviderError.NoProviderRegistered if no providers are registered
     */
    suspend fun getDefault(): CloudProvider {
        mutex.withLock {
            val id = defaultProviderId
            val provider = if (id != null) providers[id] else null
            return provider ?: throw CloudProviderError.NoProviderRegistered()
        }
    }

    /**
     * Get a specific cloud provider by ID.
     *
     * @throws CloudProviderError.ProviderNotFound if the provider is not registered
     */
    suspend fun get(providerId: String): CloudProvider {
        mutex.withLock {
            return providers[providerId]
                ?: throw CloudProviderError.ProviderNotFound(providerId)
        }
    }

    /**
     * Get all registered provider IDs.
     */
    suspend fun getRegisteredProviderIds(): List<String> {
        mutex.withLock {
            return providers.keys.toList()
        }
    }

    /**
     * Check if any providers are registered.
     */
    suspend fun hasProviders(): Boolean {
        mutex.withLock {
            return providers.isNotEmpty()
        }
    }

    /**
     * Remove all registered providers.
     */
    suspend fun removeAll() {
        mutex.withLock {
            providers.clear()
            defaultProviderId = null
        }
    }
}
