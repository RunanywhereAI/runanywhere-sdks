package com.runanywhere.runanywhereai.ui.screens.chat

/** Opaque claim for one chat inference. Claims are never reused. */
internal class ChatGenerationRequest internal constructor(val id: Long)

internal data class ChatGenerationWorkerFinish(
    /** True only when this worker still owned the visible conversation at completion. */
    val ownedAtFinish: Boolean,
    /** True when no generation or cancellation barrier remains. */
    val isIdle: Boolean,
)

/**
 * Small, thread-safe ownership state machine behind [ChatViewModel].
 *
 * Cancellation immediately revokes the worker's mutation claim, but deliberately
 * keeps the lifecycle busy. A replacement request is admitted only after both
 * the native cancel call has returned and the revoked worker has terminated.
 */
internal class ChatGenerationOwnership {
    private data class Cancellation(
        val request: ChatGenerationRequest,
        var nativeCancellationIssued: Boolean = false,
        var workerFinished: Boolean = false,
    )

    private var nextId = 0L
    private var active: ChatGenerationRequest? = null
    private var cancellation: Cancellation? = null

    @Synchronized
    fun tryStart(): ChatGenerationRequest? {
        if (active != null || cancellation != null) return null
        return ChatGenerationRequest(++nextId).also { active = it }
    }

    @Synchronized
    fun owns(request: ChatGenerationRequest): Boolean = active == request

    @Synchronized
    fun isBusy(): Boolean = active != null || cancellation != null

    /** Revoke the active worker. Repeated calls return the existing cancellation claim. */
    @Synchronized
    fun requestCancellation(): ChatGenerationRequest? {
        cancellation?.let { return it.request }
        val request = active ?: return null
        active = null
        cancellation = Cancellation(request)
        return request
    }

    /** Called exactly once from the generation worker's `finally` block. */
    @Synchronized
    fun finishWorker(request: ChatGenerationRequest): ChatGenerationWorkerFinish {
        if (active == request) {
            active = null
            return ChatGenerationWorkerFinish(ownedAtFinish = true, isIdle = true)
        }
        cancellation?.takeIf { it.request == request }?.workerFinished = true
        return ChatGenerationWorkerFinish(
            ownedAtFinish = false,
            isIdle = active == null && cancellation == null,
        )
    }

    @Synchronized
    fun markNativeCancellationIssued(request: ChatGenerationRequest) {
        cancellation?.takeIf { it.request == request }?.nativeCancellationIssued = true
    }

    /**
     * Release the replacement barrier. Returning false means one of the two
     * required terminal conditions has not happened yet.
     */
    @Synchronized
    fun completeCancellation(request: ChatGenerationRequest): Boolean {
        val state = cancellation?.takeIf { it.request == request } ?: return !isBusy()
        if (!state.nativeCancellationIssued || !state.workerFinished) return false
        cancellation = null
        return active == null
    }
}
