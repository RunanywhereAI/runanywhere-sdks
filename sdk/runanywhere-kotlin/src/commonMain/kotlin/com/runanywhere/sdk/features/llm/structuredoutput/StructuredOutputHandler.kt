package com.runanywhere.sdk.features.llm.structuredoutput

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.Generatable
import com.runanywhere.sdk.models.StructuredOutputConfig
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json

/**
 * Handles structured output generation and validation
 * Aligned with iOS StructuredOutputHandler
 */
class StructuredOutputHandler {
    private val logger = SDKLogger("StructuredOutputHandler")

    @PublishedApi
    internal val json =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
            coerceInputValues = true
        }

    /**
     * Get system prompt for structured output generation
     * Matches iOS getSystemPrompt(for:) method
     */
    fun <T : Generatable> getSystemPrompt(schema: String): String {
        return """
            |You are a JSON generator that outputs ONLY valid JSON without any additional text.
            |
            |CRITICAL RULES:
            |1. Your entire response must be valid JSON that can be parsed
            |2. Start with { and end with }
            |3. No text before the opening {
            |4. No text after the closing }
            |5. Follow the provided schema exactly
            |6. Include all required fields
            |7. Use proper JSON syntax (quotes, commas, etc.)
            |
            |Expected JSON Schema:
            |$schema
            |
            |Remember: Output ONLY the JSON object, nothing else.
            """.trimMargin()
    }

    /**
     * Build user prompt for structured output (simplified without instructions)
     * Matches iOS buildUserPrompt(for:content:) method
     */
    fun buildUserPrompt(content: String): String {
        // Return clean user prompt without JSON instructions
        // The instructions are now in the system prompt
        return content
    }

    /**
     * Prepare prompt with structured output instructions
     * Matches iOS preparePrompt(originalPrompt:config:) method
     */
    fun preparePrompt(
        originalPrompt: String,
        config: StructuredOutputConfig,
    ): String {
        if (!config.includeSchemaInPrompt) {
            return originalPrompt
        }

        val schema = config.jsonSchema ?: return originalPrompt

        // Build structured output instructions with stronger emphasis
        val instructions =
            """
            |CRITICAL INSTRUCTION: You MUST respond with ONLY a valid JSON object. No other text is allowed.
            |
            |JSON Schema:
            |$schema
            |
            |RULES:
            |1. Start your response with { and end with }
            |2. Include NO text before the opening {
            |3. Include NO text after the closing }
            |4. Follow the schema exactly
            |5. All required fields must be present
            |6. Use exact field names from the schema
            |7. Ensure proper JSON syntax (quotes, commas, etc.)
            |
            |IMPORTANT: Your entire response must be valid JSON that can be parsed. Do not include any explanations, comments, or additional text.
            """.trimMargin()

        // Combine with system-like instruction at the beginning
        return """
            |System: You are a JSON generator. You must output only valid JSON.
            |
            |$originalPrompt
            |
            |$instructions
            |
            |Remember: Output ONLY the JSON object, nothing else.
            """.trimMargin()
    }

    /**
     * Parse and validate structured output from generated text
     * Matches iOS parseStructuredOutput(from:type:) method
     */
    inline fun <reified T : Generatable> parseStructuredOutput(text: String): T {
        // Extract JSON from the response
        val jsonString = extractJSONPublic(text)

        // Parse using kotlinx.serialization
        return try {
            json.decodeFromString<T>(jsonString)
        } catch (e: Exception) {
            throw StructuredOutputError.ValidationFailed("Strict validation failed: ${e.message}")
        }
    }

    /**
     * Extract JSON - published for inline function access
     */
    @PublishedApi
    internal fun extractJSONPublic(text: String): String = extractJSON(text)

    /**
     * Parse structured output using serializer
     * For cases where reified types aren't available
     */
    fun <T : Generatable> parseStructuredOutput(
        text: String,
        serializer: KSerializer<T>,
    ): T {
        val jsonString = extractJSON(text)

        return try {
            json.decodeFromString(serializer, jsonString)
        } catch (e: Exception) {
            throw StructuredOutputError.ValidationFailed("Strict validation failed: ${e.message}")
        }
    }

    /**
     * Extract JSON from potentially mixed text
     * Matches iOS extractJSON(from:) method
     */
    fun extractJSON(text: String): String {
        val trimmed = text.trim()

        // First, try to find a complete JSON object
        findCompleteJSON(trimmed)?.let { return it }

        // Fallback: Try to find JSON object boundaries
        val startBrace = trimmed.indexOf('{')
        if (startBrace >= 0) {
            findMatchingBrace(trimmed, startBrace)?.let { endIndex ->
                return trimmed.substring(startBrace, endIndex + 1)
            }
        }

        // Try to find JSON array boundaries
        val startBracket = trimmed.indexOf('[')
        if (startBracket >= 0) {
            findMatchingBracket(trimmed, startBracket)?.let { endIndex ->
                return trimmed.substring(startBracket, endIndex + 1)
            }
        }

        // If no clear JSON boundaries, check if the entire text might be JSON
        if (trimmed.startsWith("{") || trimmed.startsWith("[")) {
            return trimmed
        }

        // Log the text that couldn't be parsed
        logger.error("Failed to extract JSON from text: ${trimmed.take(200)}...")
        throw StructuredOutputError.ExtractionFailed("No valid JSON found in the response")
    }

    /**
     * Find a complete JSON object or array in the text
     * Matches iOS findCompleteJSON(in:) method
     */
    private fun findCompleteJSON(text: String): String? {
        for (startChar in listOf('{', '[')) {
            val startIndex = text.indexOf(startChar)
            if (startIndex >= 0) {
                var depth = 0
                var inString = false
                var escaped = false
                val endChar = if (startChar == '{') '}' else ']'

                for (i in startIndex until text.length) {
                    val char = text[i]

                    if (escaped) {
                        escaped = false
                        continue
                    }

                    if (char == '\\') {
                        escaped = true
                        continue
                    }

                    if (char == '"' && !escaped) {
                        inString = !inString
                        continue
                    }

                    if (!inString) {
                        when (char) {
                            startChar -> depth++
                            endChar -> {
                                depth--
                                if (depth == 0) {
                                    return text.substring(startIndex, i + 1)
                                }
                            }
                        }
                    }
                }
            }
        }
        return null
    }

    /**
     * Find matching closing brace for an opening brace
     * Matches iOS findMatchingBrace(in:startingFrom:) method
     */
    private fun findMatchingBrace(
        text: String,
        startIndex: Int,
    ): Int? {
        var depth = 0
        var inString = false
        var escaped = false

        for (i in startIndex until text.length) {
            val char = text[i]

            if (escaped) {
                escaped = false
                continue
            }

            if (char == '\\') {
                escaped = true
                continue
            }

            if (char == '"' && !escaped) {
                inString = !inString
                continue
            }

            if (!inString) {
                when (char) {
                    '{' -> depth++
                    '}' -> {
                        depth--
                        if (depth == 0) {
                            return i
                        }
                    }
                }
            }
        }
        return null
    }

    /**
     * Find matching closing bracket for an opening bracket
     * Matches iOS findMatchingBracket(in:startingFrom:) method
     */
    private fun findMatchingBracket(
        text: String,
        startIndex: Int,
    ): Int? {
        var depth = 0
        var inString = false
        var escaped = false

        for (i in startIndex until text.length) {
            val char = text[i]

            if (escaped) {
                escaped = false
                continue
            }

            if (char == '\\') {
                escaped = true
                continue
            }

            if (char == '"' && !escaped) {
                inString = !inString
                continue
            }

            if (!inString) {
                when (char) {
                    '[' -> depth++
                    ']' -> {
                        depth--
                        if (depth == 0) {
                            return i
                        }
                    }
                }
            }
        }
        return null
    }

    /**
     * Validate that generated text contains valid structured output
     * Matches iOS validateStructuredOutput(text:config:) method
     */
    @Suppress("UNUSED_PARAMETER")
    fun validateStructuredOutput(
        text: String,
        config: StructuredOutputConfig,
    ): StructuredOutputValidation {
        return try {
            extractJSON(text)
            StructuredOutputValidation(
                isValid = true,
                containsJSON = true,
                error = null,
            )
        } catch (e: Exception) {
            StructuredOutputValidation(
                isValid = false,
                containsJSON = false,
                error = e.message,
            )
        }
    }
}

/**
 * Structured output validation result
 * Matches iOS StructuredOutputValidation
 */
data class StructuredOutputValidation(
    val isValid: Boolean,
    val containsJSON: Boolean,
    val error: String?,
)

/**
 * Structured output errors
 * Matches iOS StructuredOutputError
 */
sealed class StructuredOutputError(
    message: String,
) : Exception(message) {
    data class InvalidJSON(
        val detail: String,
    ) : StructuredOutputError("Invalid JSON: $detail")

    data class ValidationFailed(
        val detail: String,
    ) : StructuredOutputError("Validation failed: $detail")

    data class ExtractionFailed(
        val detail: String,
    ) : StructuredOutputError("Failed to extract structured output: $detail")

    data class UnsupportedType(
        val typeName: String,
    ) : StructuredOutputError("Unsupported type for structured output: $typeName")
}
