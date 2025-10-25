package com.runanywhere.sdk.llm.llamacpp

import com.runanywhere.sdk.foundation.SDKLogger

/**
 * Bridge to native llama.cpp grammar functions
 *
 * Provides grammar-based constrained generation support for tool calling.
 */
object GrammarBridge {

    private val logger = SDKLogger("GrammarBridge")

    init {
        try {
            System.loadLibrary("llama-android")
            logger.info("Native library loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            logger.error("Failed to load native library", e)
            throw e
        }
    }

    /**
     * Convert JSON schema to GBNF (GGML BNF) grammar rules
     *
     * @param jsonSchema JSON schema string (e.g., generated from tool definitions)
     * @return GBNF grammar rules string
     * @throws RuntimeException if conversion fails
     */
    external fun jsonSchemaToGBNF(jsonSchema: String): String

    /**
     * Create grammar instance from GBNF rules
     *
     * @param modelPointer Pointer to loaded llama model
     * @param gbnfRules GBNF grammar rules string
     * @return Grammar handle (pointer) for use in sampling
     * @throws RuntimeException if grammar creation fails
     */
    external fun createGrammar(modelPointer: Long, gbnfRules: String): Long

    /**
     * Free grammar instance
     *
     * @param grammarPointer Grammar handle to free
     */
    external fun freeGrammar(grammarPointer: Long)

    /**
     * High-level convenience method: Create grammar directly from JSON schema
     *
     * @param modelPointer Pointer to loaded llama model
     * @param jsonSchema JSON schema string
     * @return Grammar handle (pointer)
     */
    fun createGrammarFromSchema(modelPointer: Long, jsonSchema: String): Long {
        logger.debug("Creating grammar from JSON schema")

        return try {
            // Step 1: Convert schema to GBNF
            val gbnfRules = jsonSchemaToGBNF(jsonSchema)
            logger.debug("GBNF conversion successful, rules length: ${gbnfRules.length}")

            // Step 2: Create grammar from GBNF
            val grammar = createGrammar(modelPointer, gbnfRules)
            logger.info("Grammar created successfully, handle: $grammar")

            grammar
        } catch (e: Exception) {
            logger.error("Failed to create grammar from schema", e)
            throw RuntimeException("Grammar creation failed: ${e.message}", e)
        }
    }
}

/**
 * RAII wrapper for grammar lifetime management
 *
 * Automatically frees grammar when disposed.
 */
class Grammar(
    private val modelPointer: Long,
    val handle: Long
) : AutoCloseable {

    private val logger = SDKLogger("Grammar")
    private var freed = false

    override fun close() {
        if (!freed && handle != 0L) {
            try {
                GrammarBridge.freeGrammar(handle)
                logger.debug("Grammar freed: $handle")
                freed = true
            } catch (e: Exception) {
                logger.error("Error freeing grammar", e)
            }
        }
    }

    companion object {
        /**
         * Create grammar from JSON schema with automatic cleanup
         *
         * @param modelPointer Pointer to loaded llama model
         * @param jsonSchema JSON schema string
         * @return Grammar instance with automatic cleanup
         */
        fun fromSchema(modelPointer: Long, jsonSchema: String): Grammar {
            val handle = GrammarBridge.createGrammarFromSchema(modelPointer, jsonSchema)
            return Grammar(modelPointer, handle)
        }

        /**
         * Create grammar from GBNF rules with automatic cleanup
         *
         * @param modelPointer Pointer to loaded llama model
         * @param gbnfRules GBNF grammar rules
         * @return Grammar instance with automatic cleanup
         */
        fun fromGBNF(modelPointer: Long, gbnfRules: String): Grammar {
            val handle = GrammarBridge.createGrammar(modelPointer, gbnfRules)
            return Grammar(modelPointer, handle)
        }
    }
}
