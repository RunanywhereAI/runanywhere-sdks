/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM equivalent of AndroidPlatformContext. Installs the AES-GCM file-based
 * PlatformSecureStorage implementation on the shared platform adapter so that
 * JVM desktop consumers have a persistent, encrypted backing store for auth
 * tokens and device identity without needing to pass in an android.Context.
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatformAdapter
import com.runanywhere.sdk.foundation.bridge.extensions.JvmSecureStorage
import com.runanywhere.sdk.foundation.bridge.extensions.installJvmSecureStorage
import java.io.File

/**
 * JVM-specific context holder. Optional on JVM — [CppBridgePlatformAdapter]
 * will auto-install [JvmSecureStorage] on first secure-storage access if no
 * explicit configuration happens — but consumers may call [initialize] during
 * app startup to surface any permission/filesystem issues eagerly rather than
 * on the first C++ callback.
 */
object JvmPlatformContext {
    @Volatile
    private var initialized: Boolean = false

    /**
     * Initialize the JVM platform adapter with a file-backed secure storage
     * under `~/.runanywhere/secure/` (or [baseDirectory] if provided).
     *
     * Safe to call multiple times; subsequent calls are no-ops.
     */
    fun initialize(baseDirectory: File = JvmSecureStorage.defaultBaseDirectory()) {
        if (initialized) {
            return
        }
        synchronized(this) {
            if (initialized) {
                return
            }
            CppBridgePlatformAdapter.installJvmSecureStorage(baseDirectory)
            initialized = true
        }
    }

    fun isInitialized(): Boolean = initialized
}
