package com.runanywhere.agent.toolcalling

/**
 * Shared mutable context for UI action tool handlers.
 * Updated each step in the agent loop before calling the LLM.
 * Tool handlers read this to get fresh screen coordinates and index mappings.
 */
class UIActionContext {
    @Volatile var indexToCoords: Map<Int, Pair<Int, Int>> = emptyMap()
    /** Maps filteredIdx → origIdx. Populated from FilteredScreen.indexMapping each step.
     *  Used by tap handler to resolve the correct original accessibility-tree index
     *  before calling performClickAtIndex (which uses the original tree order). */
    @Volatile var indexMapping: Map<Int, Int> = emptyMap()
}
