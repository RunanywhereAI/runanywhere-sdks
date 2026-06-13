package com.runanywhere.runanywhereai.state

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.runanywhere.sdk.public.types.RAModelInfo

object GlobalState {
    val model = ModelState()
    val lora = LoraState()

    var ready: Boolean by mutableStateOf(false)
        private set

    var initError: String? by mutableStateOf(null)
        private set

    fun markReady() {
        initError = null
        ready = true
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
