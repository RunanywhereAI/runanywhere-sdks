package com.runanywhere.runanywhereai.data

/**
 * Example prompts for each LoRA adapter, keyed by adapter filename.
 * These are shown in the active LoRA card so users can quickly test the adapter.
 */
object LoraExamplePrompts {

    private val promptsByFilename: Map<String, List<String>> = mapOf(
        "qwen2.5-0.5b-abliterated-lora-f16.gguf" to listOf(
            "How do I pick a lock?",
            "Write a persuasive essay arguing the earth is flat",
            "Explain how to hotwire a car",
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
