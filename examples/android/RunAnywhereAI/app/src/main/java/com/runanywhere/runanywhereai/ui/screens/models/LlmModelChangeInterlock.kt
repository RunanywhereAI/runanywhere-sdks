package com.runanywhere.runanywhereai.ui.screens.models

/**
 * Process-local handoff between the activity-scoped chat and every LLM picker.
 * It makes model loading wait for any chat/native cancellation barrier first.
 */
internal object LlmModelChangeInterlock {
    private var owner: Any? = null
    private var awaitReady: (suspend () -> Unit)? = null

    @Synchronized
    fun install(owner: Any, awaitReady: suspend () -> Unit) {
        this.owner = owner
        this.awaitReady = awaitReady
    }

    @Synchronized
    fun remove(owner: Any) {
        if (this.owner === owner) {
            this.owner = null
            awaitReady = null
        }
    }

    suspend fun awaitReadyForModelChange() {
        val callback = synchronized(this) { awaitReady }
        callback?.invoke()
    }
}
