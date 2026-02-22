/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Temporary hardcoded LoRA adapter catalog for quick testing.
 * This will be replaced by a remote catalog in the future.
 */

package com.runanywhere.sdk.temp

import kotlinx.serialization.Serializable

/**
 * Describes a LoRA adapter available for download.
 */
@Serializable
data class LoraAdapterEntry(
    /** Unique identifier for this adapter */
    val id: String,
    /** Human-readable name */
    val name: String,
    /** Short description of what this adapter does */
    val description: String,
    /** Direct download URL (.gguf file) */
    val url: String,
    /** Expected file size in bytes (0 if unknown) */
    val sizeBytes: Long = 0,
    /** Filename to save as (derived from id if not set) */
    val filename: String = "$id.gguf",
)

/**
 * Hardcoded catalog of LoRA adapters for quick testing.
 *
 * Usage:
 * ```kotlin
 * val adapters = LoraAdapterCatalog.adapters
 * // Show list to user, then download selected entry
 * ```
 */
object LoraAdapterCatalog {

    val adapters: List<LoraAdapterEntry> = listOf(
        LoraAdapterEntry(
            id = "chat-assistant-lora",
            name = "Chat Assistant",
            description = "Fine-tuned for conversational chat assistance (Qwen, Q8_0)",
            url = "https://huggingface.co/Void2377/Qwen/resolve/main/lora/chat_assistant-lora-Q8_0.gguf",
            sizeBytes = 674_000,
            filename = "chat_assistant-lora-Q8_0.gguf",
        ),
        LoraAdapterEntry(
            id = "sentiment-lora",
            name = "Sentiment Analysis",
            description = "Fine-tuned for sentiment analysis tasks (Qwen, Q8_0)",
            url = "https://huggingface.co/Void2377/Qwen/resolve/main/lora/sentiment-lora-Q8_0.gguf",
            sizeBytes = 674_000,
            filename = "sentiment-lora-Q8_0.gguf",
        ),
        LoraAdapterEntry(
            id = "summarizer-lora",
            name = "Summarizer",
            description = "Fine-tuned for text summarization (Qwen, Q8_0)",
            url = "https://huggingface.co/Void2377/Qwen/resolve/main/lora/summarizer-lora-Q8_0.gguf",
            sizeBytes = 674_000,
            filename = "summarizer-lora-Q8_0.gguf",
        ),
        LoraAdapterEntry(
            id = "translator-lora",
            name = "Translator",
            description = "Fine-tuned for text translation (Qwen, Q8_0)",
            url = "https://huggingface.co/Void2377/Qwen/resolve/main/lora/translator-lora-Q8_0.gguf",
            sizeBytes = 674_000,
            filename = "translator-lora-Q8_0.gguf",
        ),
        LoraAdapterEntry(
            id = "uncensored-chat-lora",
            name = "Uncensored Chat",
            description = "Fine-tuned for uncensored conversational chat (Qwen, Q8_0)",
            url = "https://huggingface.co/Void2377/Qwen/resolve/main/lora/uncensored_chat-lora-Q8_0.gguf",
            sizeBytes = 1_340_000,
            filename = "uncensored_chat-lora-Q8_0.gguf",
        ),
    )

    /**
     * Find adapter by ID.
     */
    fun findById(id: String): LoraAdapterEntry? = adapters.find { it.id == id }
}
