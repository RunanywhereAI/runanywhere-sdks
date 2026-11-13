/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Runtime plugin loader — namespaced as `RunAnywhere.pluginLoader.*`
 * per CANONICAL_API.md §12.
 *
 * Round 2 KOTLIN: Replaced flat API (loadPlugin, unloadPlugin, etc.)
 * with the canonical `RunAnywhere.pluginLoader: PluginLoaderNamespace` namespace,
 * matching Swift, Flutter, RN and Web SDK surfaces.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.PluginInfo
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

// PluginLoaderNamespace — namespaced capability class
// PluginInfo is the proto-generated descriptor (ai.runanywhere.proto.v1.PluginInfo);
// `path` is "" for plugins the native registry reports by name only.

// RunAnywhere.pluginLoader accessor

class PluginLoaderNamespace {
    val apiVersion: UInt
        get() = RunAnywhereBridge.racRegistryGetPluginApiVersion().toUInt()

    val registeredCount: Int
        get() = RunAnywhereBridge.racRegistryGetPluginCount()

    suspend fun load(path: String): PluginInfo =
        withContext(Dispatchers.IO) {
            // Commons returns the exact registry key (vt->metadata.name) and
            // normalizes DUPLICATE/BUSY to success. Do not derive a name from the
            // file stem: a third-party plugin may register under any key.
            val result =
                RunAnywhereBridge.racRegistryLoadPluginNamed(path)
                    ?: throw SDKException.operation("rac_registry_load_plugin_named returned null")
            if (result.resultCode != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation(
                    "rac_registry_load_plugin_named failed with rc=${result.resultCode}",
                )
            }
            PluginInfo(name = result.name, path = path)
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
private val pluginLoaderInstance = PluginLoaderNamespace()

val RunAnywhere.pluginLoader: PluginLoaderNamespace
    get() = pluginLoaderInstance
