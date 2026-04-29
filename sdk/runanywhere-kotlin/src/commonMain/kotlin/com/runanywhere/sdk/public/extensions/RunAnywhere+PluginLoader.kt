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

import com.runanywhere.sdk.public.RunAnywhere

// ---------------------------------------------------------------------------
// PluginInfo — lightweight descriptor for a loaded plugin.
// ---------------------------------------------------------------------------

/**
 * Descriptor for a plugin loaded at runtime.
 *
 * @param id Plugin name / identifier (without `librunanywhere_` prefix or extension)
 * @param path Absolute path to the shared library on disk, if known
 */
data class PluginInfo(
    val id: String,
    val path: String? = null,
)

// ---------------------------------------------------------------------------
// PluginLoader — namespaced capability class
// ---------------------------------------------------------------------------

/**
 * Provides runtime plugin management: load, unload, and enumerate
 * native extension plugins.
 *
 * Access via `RunAnywhere.pluginLoader`.
 *
 * On platforms that ship statically linked plugins (iOS, WASM) the
 * mutating operations throw `SDKException.notImplemented`.
 */
expect class PluginLoader {
    /**
     * Compile-time plugin API version this build of `racommons` was built
     * against. Plugin libraries must report a matching version.
     *
     * Type is UInt per §12 of CANONICAL_API.md (uint32).
     */
    val apiVersion: UInt

    /**
     * Total number of plugins currently registered.
     */
    val registeredCount: Int

    /**
     * Load a plugin library at runtime.
     *
     * @param path Absolute path to the shared library (.so / .dylib / .dll)
     * @return [PluginInfo] describing the loaded plugin
     */
    suspend fun load(path: String): PluginInfo

    /**
     * Unregister a previously-loaded plugin.
     *
     * @param id Plugin name (without `librunanywhere_` prefix or extension)
     */
    suspend fun unload(id: String)

    /**
     * Names of all currently registered plugins.
     *
     * Per §12 of CANONICAL_API.md: `registeredNames() → String[]`.
     *
     * @return List of plugin name strings (without path or extension)
     */
    suspend fun registeredNames(): List<String>
}

// ---------------------------------------------------------------------------
// RunAnywhere.pluginLoader accessor
// ---------------------------------------------------------------------------

/**
 * Namespace accessor for plugin-loader operations.
 *
 * Example:
 * ```kotlin
 * val info = RunAnywhere.pluginLoader.load("/data/lib/my_plugin.so")
 * val count = RunAnywhere.pluginLoader.registeredCount
 * ```
 */
expect val RunAnywhere.pluginLoader: PluginLoader
