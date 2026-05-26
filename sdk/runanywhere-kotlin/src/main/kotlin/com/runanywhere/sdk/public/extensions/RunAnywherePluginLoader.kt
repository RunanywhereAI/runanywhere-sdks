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

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// ---------------------------------------------------------------------------
// PluginInfo — lightweight descriptor for a loaded plugin.
// ---------------------------------------------------------------------------

/**
 * Descriptor for a plugin loaded at runtime.
 *
 * @param name Plugin name / library stem (without `lib` prefix or extension, e.g. "runanywhere_acmevoice")
 * @param path Absolute path to the shared library on disk, if known
 */
data class PluginInfo(
    val name: String,
    val path: String? = null,
)

// ---------------------------------------------------------------------------
// PluginLoader — namespaced capability class
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// RunAnywhere.pluginLoader accessor
// ---------------------------------------------------------------------------

class PluginLoader {
    val apiVersion: UInt
        get() = RunAnywhereBridge.racRegistryGetPluginApiVersion().toUInt()

    val registeredCount: Int
        get() = RunAnywhereBridge.racRegistryGetPluginCount()

    suspend fun load(path: String): PluginInfo =
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racRegistryLoadPlugin(path)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_registry_load_plugin failed with rc=$rc")
            }
            // Derive the plugin name from the library stem, stripping `lib` prefix to match Swift.
            // e.g. "/opt/plugins/librunanywhere_acmevoice.so" → "runanywhere_acmevoice"
            val name = path.substringAfterLast('/').substringBeforeLast('.').removePrefix("lib")
            PluginInfo(name = name, path = path)
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
