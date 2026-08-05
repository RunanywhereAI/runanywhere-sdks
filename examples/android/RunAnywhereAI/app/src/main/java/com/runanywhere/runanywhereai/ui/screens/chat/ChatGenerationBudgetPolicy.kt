package com.runanywhere.runanywhereai.ui.screens.chat

/** Effective output budget for one normal (non-tool) chat response. */
internal data class ChatGenerationBudget(
    val requestedMaxTokens: Int,
    val effectiveMaxTokens: Int,
    val modelContextTokens: Int?,
) {
    val isCapped: Boolean get() = effectiveMaxTokens < requestedMaxTokens

    fun explanation(modelName: String?): String {
        val subject = modelName?.takeIf { it.isNotBlank() } ?: "Chat"
        return when {
            !isCapped && modelContextTokens != null ->
                "Chat reserves at least half of the model context for your prompt and system instructions."
            !isCapped ->
                "Chat uses your saved maximum and will reserve input space when the model reports its context size."
            modelContextTokens != null ->
                "$subject will use up to $effectiveMaxTokens output tokens with its " +
                    "$modelContextTokens-token context. Your $requestedMaxTokens-token preference stays saved."
            else ->
                "$subject will use up to $effectiveMaxTokens output tokens until it reports a context size. " +
                    "Your $requestedMaxTokens-token preference stays saved."
        }
    }
}

/**
 * Production response-budget policy for normal chat.
 *
 * The saved setting remains the user's preference. Each request independently
 * reserves half of a known context window for input/template overhead and caps
 * consumer chat output at 512 tokens. This prevents 512/1K QHexRT models from
 * inheriting a 4K-token multi-minute decode while leaving the setting intact for
 * other consumers and future larger-budget modes.
 */
internal object ChatGenerationBudgetPolicy {
    // Global ceiling for one normal chat response. Raised 512 -> 1024 so sliding-window NPU models can produce
    // longer answers (a ~7 tok/s NPU reaches this in ~2.5 min worst case; EOS usually stops it much sooner).
    const val MAX_NORMAL_OUTPUT_TOKENS: Int = 1024

    fun resolve(
        requestedMaxTokens: Int,
        modelContextTokens: Int,
        // QHexRT NPU decoders use a KV RING (sliding window): they keep generating coherently PAST the context
        // size — the ring just forgets the oldest tokens, it never corrupts (verified: LFM2.5-2.6B streams
        // 600+ coherent tokens on a 512 window). So their output is NOT bounded by the context. Only
        // context-bound decoders (llama.cpp n_ctx, cloud) reserve half the window for the prompt.
        slidingWindow: Boolean = false,
    ): ChatGenerationBudget {
        val requested = requestedMaxTokens.coerceAtLeast(1)
        val context = modelContextTokens.takeIf { it > 0 }
        val contextOutputLimit =
            if (slidingWindow) null else context?.let { (it / 2).coerceAtLeast(1) }
        val effective = minOf(
            requested,
            MAX_NORMAL_OUTPUT_TOKENS,
            contextOutputLimit ?: Int.MAX_VALUE,
        )
        return ChatGenerationBudget(
            requestedMaxTokens = requested,
            effectiveMaxTokens = effective,
            modelContextTokens = context,
        )
    }
}
