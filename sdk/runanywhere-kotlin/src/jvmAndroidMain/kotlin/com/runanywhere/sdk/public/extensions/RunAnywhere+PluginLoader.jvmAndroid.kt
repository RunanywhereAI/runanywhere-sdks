/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual for the runtime plugin loader.
 * Wave 2 KOTLIN: Stub pending C++ rac_registry_load_plugin JNI wiring.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

actual val RunAnywhere.pluginApiVersion: UInt
    get() = 1u

actual suspend fun RunAnywhere.loadPlugin(path: String) {
    throw SDKException.notImplemented("Dynamic plugin loading (rac_registry_load_plugin) is being wired up")
}

actual suspend fun RunAnywhere.unloadPlugin(name: String) {
    throw SDKException.notImplemented("Dynamic plugin unloading (rac_registry_unload_plugin) is being wired up")
}

actual suspend fun RunAnywhere.registeredPluginNames(): List<String> = emptyList()

actual suspend fun RunAnywhere.registeredPluginCount(): Int = 0
