/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Runtime plugin loader — Kotlin equivalent of Swift's RunAnywhere.PluginLoader.
 *
 * Wave 2 KOTLIN: Added missing namespace extension to align with Swift.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.public.RunAnywhere

/**
 * Compile-time plugin API version this build of `racommons` was built
 * against. Plugin libraries must report a matching version or `dlopen`
 * is rejected with `ABI_VERSION_MISMATCH`.
 */
expect val RunAnywhere.pluginApiVersion: UInt

/**
 * Load a plugin library at runtime. On platforms that ship statically
 * linked plugins (iOS, WASM) this throws `SDKException.notImplemented`.
 *
 * @param path Absolute path to the shared library (.so / .dylib / .dll).
 */
expect suspend fun RunAnywhere.loadPlugin(path: String)

/**
 * Unregister a previously-loaded plugin.
 *
 * @param name Plugin name (without `librunanywhere_` prefix or extension).
 */
expect suspend fun RunAnywhere.unloadPlugin(name: String)

/**
 * Snapshot of currently-registered plugin names.
 */
expect suspend fun RunAnywhere.registeredPluginNames(): List<String>

/**
 * Total number of plugins currently registered (one count per plugin).
 */
expect suspend fun RunAnywhere.registeredPluginCount(): Int
