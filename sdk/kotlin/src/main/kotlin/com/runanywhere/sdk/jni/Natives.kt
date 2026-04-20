// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Kotlin-side companion to sdk/kotlin/src/main/cpp/jni_extensions.cpp.
// Thin classes whose members map 1:1 to JNI functions exposed by the
// ra_core_jni shared library.

package com.runanywhere.sdk.jni

object AuthNative {
    init { NativeLoader.ensure() }
    external fun isAuthenticated(): Boolean
    external fun needsRefresh(horizonSeconds: Int): Boolean
    external fun getAccessToken(): String
    external fun getRefreshToken(): String
    external fun getDeviceId(): String
    external fun buildAuthenticateRequest(apiKey: String, deviceId: String): String
    external fun handleAuthenticateResponse(body: String): Int
    external fun clear()
}

object TelemetryNative {
    init { NativeLoader.ensure() }
    external fun track(name: String, propertiesJson: String): Int
    external fun flush(): Int
    external fun defaultPayloadJson(): String
}

object ModelNative {
    init { NativeLoader.ensure() }
    external fun frameworkSupports(framework: String, category: String): Boolean
    external fun detectFormat(urlOrPath: String): Int
    external fun inferCategory(modelId: String): Int
    external fun isArchive(urlOrPath: String): Boolean
}

object RagNative {
    init { NativeLoader.ensure() }
    external fun storeCreate(dim: Int): Long
    external fun storeDestroy(handle: Long)
    external fun storeAdd(handle: Long, rowId: String, metadataJson: String,
                             embedding: FloatArray): Int
    external fun storeSize(handle: Long): Int

    /// Returns a flat [id0, meta0, score0, id1, meta1, score1, …] String[]
    /// Caller chunks into triples client-side.
    external fun storeSearch(handle: Long, query: FloatArray, topK: Int): Array<String>
}

/// Ensures libracommons_core.so is loaded exactly once per process.
/// RunAnywhere.kt already calls `System.loadLibrary(\"racommons_core\")`
/// in its companion init block; this is a fallback path for host apps
/// that import only specific session types.
internal object NativeLoader {
    @Volatile private var loaded = false
    private val lock = Any()

    fun ensure() {
        if (loaded) return
        synchronized(lock) {
            if (loaded) return
            System.loadLibrary("racommons_core")
            loaded = true
        }
    }
}
