package com.runanywhere.agent.toolcalling

/**
 * Shared mutable context for UI action tool handlers.
 * Updated each step in the agent loop before calling the LLM.
 * Tool handlers read from this to get fresh screen coordinates.
 */
class UIActionContext {
    @Volatile var indexToCoords: Map<Int, Pair<Int, Int>> = emptyMap()
}
