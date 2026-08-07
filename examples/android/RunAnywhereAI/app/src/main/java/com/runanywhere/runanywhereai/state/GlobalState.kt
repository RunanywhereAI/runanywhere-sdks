package com.runanywhere.runanywhereai.state

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first

object GlobalState {
    val model = ModelState()
    val lora = LoraState()

    private val catalogSeeded = MutableStateFlow(false)

    /**
     * The SDK is up and the app is usable. Gates the launch splash.
     *
     * Deliberately *not* the same thing as [awaitBootstrapComplete]. Seeding the
     * 105-row model catalog takes ~13.4 s of sequential JNI registration on a
     * Snapdragon 8 Elite, while `RunAnywhere.initialize()` returns in ~0.6 s and
     * the window itself draws in ~0.5 s. Holding the splash for the catalog put
     * fourteen wordless seconds in front of every cold start to prepare a list
     * only the model picker reads. Chat, voice, and vision all work without it.
     */
    var ready: Boolean by mutableStateOf(false)
        private set

    var initError: String? by mutableStateOf(null)
        private set

    fun markReady() {
        initError = null
        ready = true
    }

    fun markCatalogSeeded() {
        catalogSeeded.value = true
    }

    /**
     * Suspend until the model catalog has been seeded into the native registry.
     *
     * Only callers that read the catalog should wait on this — listing models
     * before it completes returns a partial registry. Everything else should
     * gate on [ready] instead, which lands ~13 s earlier.
     */
    suspend fun awaitBootstrapComplete() {
        catalogSeeded.first { it }
    }

    fun markInitFailed(message: String) {
        initError = message
    }

    fun clearInitError() {
        initError = null
    }

    // Force snapshot-state creation on the main thread before composition starts, so the
    // backing records live in the global snapshot (avoids "state created after the snapshot
    // was taken" when background coroutines and composition touch GlobalState concurrently).
    fun warmUp() {
        model.isLoaded
        lora.isActive
        ready
        initError
    }
}

class LoraState {
    var activeAdapterId: String? by mutableStateOf(null)
        private set

    val isActive: Boolean get() = activeAdapterId != null

    fun set(id: String?) {
        activeAdapterId = id
    }
}

class ModelState {
    var loaded: RAModelInfo? by mutableStateOf(null)
        private set

    val isLoaded: Boolean get() = loaded != null

    fun set(model: RAModelInfo?) {
        loaded = model
    }

    fun clear() {
        loaded = null
    }
}
