/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for the runtime plugin loader namespace.
 *
 * Round 2 KOTLIN: Replaced flat API with PluginLoader class.
 * Delegates to existing racRegistry* JNI thunks.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

actual class PluginLoader {
    actual val apiVersion: UInt
        get() = RunAnywhereBridge.racRegistryGetPluginApiVersion().toUInt()

    actual val registeredCount: Int
        get() = RunAnywhereBridge.racRegistryGetPluginCount()

    actual suspend fun load(path: String): PluginInfo =
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

    actual suspend fun unload(name: String) =
        withContext(Dispatchers.IO) {
            val rc = RunAnywhereBridge.racRegistryUnloadPlugin(name)
            if (rc != RunAnywhereBridge.RAC_SUCCESS) {
                throw SDKException.operation("rac_registry_unload_plugin failed with rc=$rc")
            }
        }

    actual suspend fun registeredNames(): List<String> =
        withContext(Dispatchers.IO) {
            RunAnywhereBridge.racRegistryGetRegisteredNames()?.toList() ?: emptyList()
        }

    actual suspend fun listLoaded(): List<PluginInfo> =
        registeredNames().map { PluginInfo(name = it, path = "") }
}

// Singleton instance — one per SDK singleton.
private val pluginLoaderInstance = PluginLoader()

actual val RunAnywhere.pluginLoader: PluginLoader
    get() = pluginLoaderInstance
