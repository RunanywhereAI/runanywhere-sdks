package com.runanywhere.agent.kernel

import com.runanywhere.agent.accessibility.AgentAccessibilityService

class ScreenParser(private val accessibilityService: () -> AgentAccessibilityService?) {

    data class ParsedScreen(
        val compactText: String,
        val indexToCoords: Map<Int, Pair<Int, Int>>,
        val elementCount: Int
    )

    fun parse(maxElements: Int = 30, maxTextLength: Int = 50): ParsedScreen {
        val service = accessibilityService() ?: return ParsedScreen("(no screen access)", emptyMap(), 0)
        val state = service.getScreenState(maxElements, maxTextLength)
        return ParsedScreen(
            compactText = state.compactText,
            indexToCoords = state.indexToCoords,
            elementCount = state.elements.size
        )
    }

    fun getElementLabel(index: Int, maxElements: Int = 30): String? {
        val service = accessibilityService() ?: return null
        val state = service.getScreenState(maxElements, 50)
        return state.elements.getOrNull(index)?.label
    }
}
