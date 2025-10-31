package com.runanywhere.sdk.public.toolcalling

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Prevents infinite loops by tracking and detecting duplicate tool calls.
 *
 * This is critical for preventing the model from getting stuck in loops where
 * it repeatedly calls the same tool with the same arguments.
 *
 * Uses a hash-based approach to track unique tool calls within a conversation.
 */
class Deduplicator(
    private val maxHistorySize: Int = 50
) {
    private val logger = SDKLogger("Deduplicator")
    private val seenToolCalls = mutableSetOf<String>()

    /**
     * Check if a tool call is a duplicate.
     *
     * @param toolName Name of the tool being called
     * @param arguments Arguments for the tool call
     * @return true if this is a duplicate call, false if it's new
     */
    fun isDuplicate(toolName: String, arguments: Map<String, String>): Boolean {
        val hash = generateHash(toolName, arguments)

        val isDupe = hash in seenToolCalls

        if (isDupe) {
            logger.warn("🔄 Duplicate tool call detected: $toolName with args: $arguments")
        } else {
            logger.debug("✅ New tool call: $toolName")
            seenToolCalls.add(hash)

            // Prevent unbounded growth
            if (seenToolCalls.size > maxHistorySize) {
                // Remove oldest entries (though Set doesn't guarantee order,
                // this prevents memory issues in long conversations)
                val excess = seenToolCalls.size - maxHistorySize
                seenToolCalls.drop(excess).forEach { seenToolCalls.remove(it) }
            }
        }

        return isDupe
    }

    /**
     * Generate a hash for a tool call based on its name and arguments.
     *
     * The hash includes both the tool name and sorted arguments to ensure
     * identical calls are detected regardless of argument order.
     */
    private fun generateHash(toolName: String, arguments: Map<String, String>): String {
        // Sort arguments to ensure consistent hashing
        val sortedArgs = arguments.entries
            .sortedBy { it.key }
            .joinToString(",") { "${it.key}=${it.value}" }

        return "$toolName:$sortedArgs".hashCode().toString()
    }

    /**
     * Clear the deduplication history.
     * Useful when starting a new conversation or resetting state.
     */
    fun clear() {
        logger.debug("Clearing deduplication history (${seenToolCalls.size} entries)")
        seenToolCalls.clear()
    }

    /**
     * Get the current number of tracked tool calls.
     */
    fun size(): Int = seenToolCalls.size
}
