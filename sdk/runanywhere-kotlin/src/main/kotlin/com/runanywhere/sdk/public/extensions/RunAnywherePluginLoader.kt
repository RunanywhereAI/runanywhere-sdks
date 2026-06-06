/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Runtime plugin loader — namespaced as `RunAnywhere.pluginLoader.*`
 * per CANONICAL_API.md §12.
 *
 * Round 2 KOTLIN: Replaced flat API (loadPlugin, unloadPlugin, etc.)
 * with the canonical `RunAnywhere.pluginLoader: PluginLoader` namespace,
 * matching Swift, Flutter, RN and Web SDK surfaces.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.PluginInfo
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// PluginLoader — namespaced capability class
// PluginInfo is the proto-generated descriptor (ai.runanywhere.proto.v1.PluginInfo);
// `path` is "" for plugins the native registry reports by name only.

// RunAnywhere.pluginLoader accessor

class PluginLoader {
    val apiVersion: UInt
        get() = RunAnywhereBridge.racRegistryGetPluginApiVersion().toUInt()

    val registeredCount: Int
        get() = RunAnywhereBridge.racRegistryGetPluginCount()

    suspend fun load(path: String): PluginInfo =
        withContext(Dispatchers.IO) {
            // The C loader stores the plugin under vt->metadata.name (e.g. "llamacpp"
            // for the in-tree librunanywhere_llamacpp.so), which is what
            // rac_registry_unload_plugin expects. Deriving the name from the file
            // stem locally is fragile because the C++ loader also strips an optional
            // `runanywhere_` infix, and third-party plugins may set metadata.name to
            // anything they choose. Snapshot registry keys before/after the load and
            // use the diff to identify the newly registered name (mirrors Swift's
            // `RunAnywhere+PluginLoader.swift:72-89`).
            val before = registeredNames().toSet()

            val rc = RunAnywhereBridge.racRegistryLoadPlugin(path)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_registry_load_plugin failed with rc=$rc")
            }

            val after = registeredNames()
            val registeredName = after.firstOrNull { it !in before } ?: deriveStemName(path)
            PluginInfo(name = registeredName, path = path)
        }

    /**
     * Mirror the C loader's stem derivation (strip directory, the optional `lib`
     * prefix, the file extension, and the optional `runanywhere_` infix). Used as
     * a last-resort fallback when the registry-diff is empty — e.g. when an
     * already-loaded plugin's entry is idempotently re-registered and
     * [registeredNames] returns the same set.
     */
    private fun deriveStemName(path: String): String {
        var stem = path.substringAfterLast('/').substringBeforeLast('.')
        if (stem.startsWith("lib")) {
            stem = stem.removePrefix("lib")
        }
        if (stem.startsWith("runanywhere_")) {
            stem = stem.removePrefix("runanywhere_")
        }
        return stem
    }

    suspend fun unload(name: String) =
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racRegistryUnloadPlugin(name)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_registry_unload_plugin failed with rc=$rc")
            }
        }

    suspend fun registeredNames(): List<String> =
        withContext(Dispatchers.IO) {
            RunAnywhereBridge.racRegistryGetRegisteredNames()?.toList() ?: emptyList()
        }

    suspend fun listLoaded(): List<PluginInfo> =
        registeredNames().map { PluginInfo(name = it, path = "") }
}

// Singleton instance — one per SDK singleton.
private val pluginLoaderInstance = PluginLoader()

val RunAnywhere.pluginLoader: PluginLoader
    get() = pluginLoaderInstance
