/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for framework discovery and querying.
 *
 * Mirrors Swift sdk/runanywhere-swift/.../Models/RunAnywhere+Frameworks.swift.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.core.types.SDKComponent
import com.runanywhere.sdk.public.RunAnywhere

/**
 * Get all registered frameworks derived from available models.
 *
 * Mirrors Swift's `RunAnywhere.getRegisteredFrameworks()`.
 *
 * @return The sorted (by display name) list of inference frameworks that
 *         currently have at least one registered model.
 */
expect suspend fun RunAnywhere.getRegisteredFrameworks(): List<InferenceFramework>

/**
 * Get all registered frameworks that provide a specific capability.
 *
 * Mirrors Swift's `RunAnywhere.getFrameworks(for: SDKComponent)`.
 *
 * @param capability The SDK component to filter by.
 * @return The sorted (by display name) list of frameworks supporting the
 *         requested capability via at least one registered model.
 */
expect suspend fun RunAnywhere.getFrameworks(capability: SDKComponent): List<InferenceFramework>

/**
 * Flush any pending model-registration writes to the C++ registry.
 *
 * Mirrors Swift's `RunAnywhere.flushPendingRegistrations()`. The Kotlin
 * `registerModel` API performs a synchronous save into the C++ registry,
 * so this is effectively a no-op today; the symbol is kept for API parity
 * with Swift / RN / Web.
 */
expect suspend fun RunAnywhere.flushPendingRegistrations()

/**
 * Discover models that have been downloaded to disk but not yet
 * registered with the SDK at this session boot.
 *
 * Mirrors Swift's `RunAnywhere.discoverDownloadedModels()`. Triggers the
 * filesystem-scan-and-restore code path eagerly (otherwise it runs
 * lazily on first `availableModels()` call).
 */
expect suspend fun RunAnywhere.discoverDownloadedModels()
