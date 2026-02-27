package com.runanywhere.runanywhereai.data

/**
 * Example prompts for each LoRA adapter, keyed by adapter filename.
 * These are shown in the active LoRA card so users can quickly test the adapter.
 */
object LoraExamplePrompts {

    private val promptsByFilename: Map<String, List<String>> = mapOf(
        "code-assistant-Q8_0.gguf" to listOf(
            "Write a Python function to reverse a linked list",
            "Explain the difference between a stack and a queue with code examples",
        ),
        "reasoning-logic-Q8_0.gguf" to listOf(
            "If all roses are flowers and some flowers fade quickly, can we conclude some roses fade quickly?",
            "A farmer has 17 sheep. All but 9 die. How many are left?",
        ),
        "medical-qa-Q8_0.gguf" to listOf(
            "What are the common symptoms of vitamin D deficiency?",
            "Explain the difference between Type 1 and Type 2 diabetes",
        ),
        "creative-writing-Q8_0.gguf" to listOf(
            "Write a short story about a robot discovering emotions for the first time",
            "Describe a sunset over the ocean using vivid sensory language",
        ),
    )

    /**
     * Get example prompts for a loaded adapter by its file path.
     * Extracts the filename from the path and looks up prompts.
     */
    fun forAdapterPath(path: String): List<String> {
        val filename = path.substringAfterLast("/")
        return promptsByFilename[filename] ?: emptyList()
    }
}
