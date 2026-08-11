package com.runanywhere.runanywhereai.ui.screens.chat

/** Finalizes the active assistant row when the user stops generation. */
internal object ChatGenerationCleanupPolicy {
    fun afterStop(reply: ChatMessage): ChatMessage {
        // reply.text / reply.thinking are already channel-split by commons.
        val hasNoVisibleAnswer = reply.text.isBlank() &&
            reply.stats == null &&
            reply.sources.isEmpty()
        val isToolProgress = reply.text == ToolCallingExecutionPolicy.PROGRESS_MESSAGE &&
            reply.thinking == null && reply.tool == null && reply.stats == null

        // Keep the row in place so a slow native cancellation cannot resume a
        // callback against a shifted list index. A static terminal label also
        // removes the typing animation and its idle CPU usage immediately.
        return if (hasNoVisibleAnswer || isToolProgress) reply.copy(text = "Stopped.") else reply
    }
}
