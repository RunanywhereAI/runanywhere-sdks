package com.runanywhere.runanywhereai.llm.tokenizer

import com.runanywhere.runanywhereai.llm.frameworks.LlamaCppService

/**
 * Llama tokenizer that delegates to the native llama.cpp implementation
 *
 * This tokenizer uses the tokenization built into the llama.cpp library,
 * ensuring perfect compatibility with GGUF models.
 */
class LlamaTokenizer(private val modelPath: String) : Tokenizer {
    private var modelPtr: Long = 0
    private val specialTokens = mapOf(
        "<s>" to 1,      // Beginning of sentence
        "</s>" to 2,     // End of sentence
        "<unk>" to 0,    // Unknown token
        "<pad>" to -1    // Padding (not typically used in Llama)
    )

    init {
        // Load the model for tokenization
        // In a real implementation, we might want to share the model pointer
        // with LlamaCppService to avoid loading the model twice
        modelPtr = LlamaCppService.nativeLoadModel(modelPath)
        if (modelPtr == 0L) {
            throw RuntimeException("Failed to load Llama model for tokenization")
        }
    }

    override fun encode(text: String): List<Int> {
        if (modelPtr == 0L) {
            throw IllegalStateException("Tokenizer not initialized")
        }

        // Use native tokenization
        val tokenArray = LlamaCppService.nativeTokenize(modelPtr, text)
        return tokenArray.toList()
    }

    override fun decode(tokens: List<Int>): String {
        if (modelPtr == 0L) {
            throw IllegalStateException("Tokenizer not initialized")
        }

        // Use native detokenization
        return LlamaCppService.nativeDetokenize(modelPtr, tokens.toIntArray())
    }

    override fun vocabSize(): Int {
        if (modelPtr == 0L) {
            throw IllegalStateException("Tokenizer not initialized")
        }

        return LlamaCppService.nativeGetVocabSize(modelPtr).toInt()
    }

    override fun getSpecialTokens(): Map<String, Int> = specialTokens

    override fun getBosToken(): Int = specialTokens["<s>"]!!

    override fun getEosToken(): Int = specialTokens["</s>"]!!

    override fun getUnkToken(): Int = specialTokens["<unk>"]!!

    /**
     * Clean up native resources
     */
    fun release() {
        if (modelPtr != 0L) {
            LlamaCppService.nativeFreeModel(modelPtr)
            modelPtr = 0
        }
    }

    protected fun finalize() {
        release()
    }
}
