package com.runanywhere.runanywhereai.ui.screens.models

/**
 * Which downloaded LLM to auto-load into an empty chat slot, best-first. Kept pure (no ViewModel /
 * lifecycle deps) so the default-load ordering is unit-testable. The order mirrors
 * [ModelRecommendation.npuLLMs] so the auto-load default and the picker's "Top pick" agree.
 */
internal object ModelAutoLoadPolicy {
    // Best-first. Qwen3.5-0.8B is the default (best on-device multi-turn recall); then the other
    // strong NPU chat models. Keep in sync with ModelRecommendation.npuLLMs.
    val PREFERENCE: List<String> = listOf("qwen3_5_0_8b", "lfm2_5_350m", "qwen3_0_6b", "lfm2_5_230m")

    /**
     * The highest-preference ready model id — matched exactly or as an arch-suffixed "<id>_v79"
     * variant, never as an arbitrary substring — else the first ready id. Returns null if none.
     */
    fun preferredCandidateId(readyIds: List<String>, preference: List<String> = PREFERENCE): String? {
        for (pref in preference) {
            readyIds.firstOrNull { it == pref || it.startsWith("${pref}_") }?.let { return it }
        }
        return readyIds.firstOrNull()
    }
}
