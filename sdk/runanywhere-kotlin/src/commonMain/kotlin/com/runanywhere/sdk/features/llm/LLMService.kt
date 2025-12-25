package com.runanywhere.sdk.features.llm

import com.runanywhere.sdk.models.LLMGenerationOptions

/**
 * Protocol for Language Model services - matches iOS LLMService protocol exactly
 *
 * iOS Source: Features/LLM/LLMCapability.swift
 *
 * This interface defines the core LLM service operations. Utility methods like
 * process(), streamProcess(), cancelCurrent(), getTokenCount(), and fitsInContext()
 * are provided by LLMCapability, not the service interface, matching iOS architecture.
 */
interface LLMService {
    /** Initialize the LLM service with optional model path */
    suspend fun initialize(modelPath: String?)

    /** Generate text from prompt */
    suspend fun generate(
        prompt: String,
        options: LLMGenerationOptions,
    ): String

    /** Stream generation token by token */
    suspend fun streamGenerate(
        prompt: String,
        options: LLMGenerationOptions,
        onToken: (String) -> Unit,
    )

    /** Check if service is ready */
    val isReady: Boolean

    /** Get current model identifier */
    val currentModel: String?

    /** Cleanup resources */
    suspend fun cleanup()
}

// Service providers have been replaced with factory-based registration in ModuleRegistry
// Use ModuleRegistry.registerLLMFactory() to register LLM service implementations
