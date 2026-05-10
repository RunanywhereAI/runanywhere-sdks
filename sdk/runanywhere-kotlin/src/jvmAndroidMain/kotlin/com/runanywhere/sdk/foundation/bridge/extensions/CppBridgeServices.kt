/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Services bridge extension for C++ interop.
 *
 * v3 Phase B10: mirrors Swift's `CppBridge+Services.swift`. After GAP 02
 * the legacy rac_service_* registry was retired in favour of the unified
 * rac_plugin_* registry; platform-service registration is owned by the
 * C++ side (rac_plugin_entry_platform.cpp). Kotlin therefore exposes
 * read-only queries against the registry rather than registering its
 * own service providers.
 *
 * Mirrors iOS source of truth:
 *   sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/
 *     CppBridge+Services.swift
 *
 * NOTE (B18): the existing service-registration helpers live inline in
 * `CppBridge.initialize()` / `initializeServices()`. This object is
 * introduced as a parallel namespace so future cleanup can migrate the
 * helpers here without churning consumers. The legacy duplication in
 * `CppBridge.kt` is retained on purpose — see the task notes.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.SDKComponent

/**
 * Bridge for querying the C++ plugin / module registry.
 *
 * Mirrors Swift's `CppBridge.Services` enum namespace one-to-one. The C
 * ABI surface required by these queries (`rac_plugin_list`,
 * `rac_module_list`, `rac_module_get_info`) is not yet exposed through
 * `RunAnywhereBridge` JNI declarations on Kotlin — every accessor below
 * either delegates to the closest available native call or returns an
 * empty result with a TODO marker pointing to the missing JNI binding.
 *
 * Thread safety: every method is read-only against the C++ registry,
 * which is itself synchronized internally; no Kotlin-side locking is
 * required.
 */
object CppBridgeServices {

    /**
     * Registered plugin info (name + metadata priority).
     *
     * Mirrors Swift's `CppBridge.Services.ProviderInfo` struct.
     */
    data class ProviderInfo(
        val name: String,
        val displayName: String?,
        val priority: Int,
    )

    /**
     * Registered module info.
     *
     * Mirrors Swift's `CppBridge.Services.ModuleInfo` struct.
     */
    data class ModuleInfo(
        val id: String,
        val name: String,
        val version: String,
        val capabilities: Set<SDKComponent>,
    )

    // ────────────────────────────────────────────────────────────────────────
    // Plugin Queries
    // ────────────────────────────────────────────────────────────────────────

    /**
     * List all plugin names registered for [capability], sorted by priority.
     *
     * TODO(KOT-B18): no `racPluginList` JNI binding exists yet. Once the
     * commons follow-up adds it, route through
     * `RunAnywhereBridge.racPluginList(primitive, …)` like the Swift
     * implementation does in `CppBridge+Services.swift`.
     */
    fun listProviders(capability: SDKComponent): List<String> = emptyList()

    /**
     * Whether any plugin is registered for [capability].
     *
     * Mirrors Swift's `Services.hasProvider(for:)`.
     */
    fun hasProvider(capability: SDKComponent): Boolean = listProviders(capability).isNotEmpty()

    /**
     * Whether a specific plugin (by metadata.name, e.g. "llamacpp") is
     * registered for [capability].
     *
     * Mirrors Swift's `Services.isProviderRegistered(_:for:)`.
     */
    fun isProviderRegistered(name: String, capability: SDKComponent): Boolean =
        listProviders(capability).contains(name)

    // ────────────────────────────────────────────────────────────────────────
    // Module Queries
    // ────────────────────────────────────────────────────────────────────────

    /**
     * List all registered modules.
     *
     * TODO(KOT-B18): no `racModuleList` JNI binding exists yet. Once the
     * commons follow-up adds it, route through
     * `RunAnywhereBridge.racModuleList(...)` like the Swift implementation
     * does in `CppBridge+Services.swift`.
     */
    fun listModules(): List<ModuleInfo> = emptyList()

    /**
     * Get info for a specific module by [moduleId], or null when not
     * registered.
     *
     * TODO(KOT-B18): see [listModules] — same JNI gap applies.
     */
    fun getModule(moduleId: String): ModuleInfo? = null

    /**
     * Whether a module with [moduleId] is registered.
     *
     * Mirrors Swift's `Services.isModuleRegistered(_:)`.
     */
    fun isModuleRegistered(moduleId: String): Boolean = getModule(moduleId) != null
}
