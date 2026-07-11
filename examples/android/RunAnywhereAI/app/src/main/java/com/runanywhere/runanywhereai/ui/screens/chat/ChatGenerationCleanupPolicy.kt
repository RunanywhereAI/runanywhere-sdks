package com.runanywhere.runanywhereai.ui.screens.chat

/** Finalizes the active assistant row when the user stops generation. */
internal object ChatGenerationCleanupPolicy {
    fun afterStop(reply: ChatMessage): ChatMessage {
        val split = ChatToolResultNormalizer.splitThinking(reply.text)
        val normalized = reply.copy(
            text = split.visibleText,
            thinking = reply.thinking ?: split.thinking.takeIf { it.isNotBlank() },
        )
        val hasNoVisibleAnswer = normalized.text.isBlank() &&
            normalized.stats == null &&
            normalized.sources.isEmpty()
        val isToolProgress = normalized.text == ToolCallingExecutionPolicy.PROGRESS_MESSAGE &&
            reply.thinking == null && reply.tool == null && reply.stats == null

        // Keep the row in place so a slow native cancellation cannot resume a
        // callback against a shifted list index. A static terminal label also
        // removes the typing animation and its idle CPU usage immediately.
        return if (hasNoVisibleAnswer || isToolProgress) normalized.copy(text = "Stopped.") else normalized
    }
}
