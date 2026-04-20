// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Public Kotlin telemetry/auth/model/RAG helpers backed by the
// sdk/kotlin/src/main/cpp/jni_extensions.cpp bridge. Mirror of the
// Swift adapter so sample apps get identical APIs across platforms.

package com.runanywhere.sdk.`public`

import com.runanywhere.sdk.jni.AuthNative
import com.runanywhere.sdk.jni.ModelNative
import com.runanywhere.sdk.jni.RagNative
import com.runanywhere.sdk.jni.TelemetryNative

// MARK: - Telemetry

object Telemetry {
    /** Track a named event. propertiesJson is merged into the payload. */
    @JvmStatic
    fun track(event: String, propertiesJson: String = "{}"): Boolean =
        TelemetryNative.track(event, propertiesJson) == 0

    /** Flush the pending queue to the registered HTTP uploader. */
    @JvmStatic
    fun flush(): Boolean = TelemetryNative.flush() == 0

    /** Default platform-agnostic payload (sdk version + platform). */
    @JvmStatic
    fun defaultPayloadJson(): String = TelemetryNative.defaultPayloadJson()
}

// MARK: - Auth

object Auth {
    @JvmStatic
    val isAuthenticated: Boolean
        get() = AuthNative.isAuthenticated()

    @JvmStatic
    fun needsRefresh(horizonSeconds: Int = 60): Boolean =
        AuthNative.needsRefresh(horizonSeconds)

    @JvmStatic
    val accessToken: String get() = AuthNative.getAccessToken()

    @JvmStatic
    val refreshToken: String get() = AuthNative.getRefreshToken()

    @JvmStatic
    val deviceId: String get() = AuthNative.getDeviceId()

    @JvmStatic
    fun buildAuthenticateRequest(apiKey: String, deviceId: String): String =
        AuthNative.buildAuthenticateRequest(apiKey, deviceId)

    @JvmStatic
    fun handleAuthenticateResponse(body: String): Boolean =
        AuthNative.handleAuthenticateResponse(body) == 0

    @JvmStatic
    fun clear() { AuthNative.clear() }
}

// MARK: - Model helpers

object ModelHelpers {

    @JvmStatic
    fun frameworkSupports(framework: String, category: String): Boolean =
        ModelNative.frameworkSupports(framework, category)

    @JvmStatic
    fun detectFormat(urlOrPath: String): Int = ModelNative.detectFormat(urlOrPath)

    @JvmStatic
    fun inferCategory(modelId: String): Int = ModelNative.inferCategory(modelId)

    @JvmStatic
    fun isArchive(urlOrPath: String): Boolean = ModelNative.isArchive(urlOrPath)
}

// MARK: - RAG

/** In-memory vector store backed by the C ABI `ra_rag_*` surface. */
class RagStore internal constructor(private val handle: Long) : AutoCloseable {

    val size: Int get() = RagNative.storeSize(handle)

    /** Add a row. Embedding length must match the dim passed at create. */
    fun add(rowId: String, metadataJson: String = "{}", embedding: FloatArray): Boolean =
        RagNative.storeAdd(handle, rowId, metadataJson, embedding) == 0

    /** Top-k cosine-similarity search. */
    fun search(query: FloatArray, topK: Int = 6): List<SearchHit> {
        val flat = RagNative.storeSearch(handle, query, topK)
        val hits = mutableListOf<SearchHit>()
        var i = 0
        while (i + 2 < flat.size) {
            val score = flat[i + 2].toFloatOrNull() ?: 0f
            hits += SearchHit(id = flat[i], metadataJson = flat[i + 1], score = score)
            i += 3
        }
        return hits
    }

    override fun close() {
        RagNative.storeDestroy(handle)
    }

    data class SearchHit(val id: String, val metadataJson: String, val score: Float)

    companion object {
        /** Create a new in-memory vector store. `dim` is the embedding dimension. */
        @JvmStatic
        fun create(dim: Int): RagStore? {
            val h = RagNative.storeCreate(dim)
            return if (h == 0L) null else RagStore(h)
        }
    }
}
