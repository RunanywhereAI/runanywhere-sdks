package com.runanywhere.sdk.public.errors

/**
 * Error categories for logical grouping and filtering.
 *
 * Aligned with iOS: `RunAnywhere/Foundation/ErrorTypes/ErrorCategory.swift`
 */
enum class ErrorCategory {
    INITIALIZATION,
    MODEL,
    GENERATION,
    NETWORK,
    STORAGE,
    MEMORY,
    HARDWARE,
    VALIDATION,
    AUTHENTICATION,
    COMPONENT,
    FRAMEWORK,
    UNKNOWN;

    companion object {
        /**
         * Categorize based on error description keywords.
         */
        fun fromDescription(description: String): ErrorCategory {
            val lowercased = description.lowercase()

            return when {
                lowercased.contains("memory") || lowercased.contains("out of memory") -> MEMORY
                lowercased.contains("download") || lowercased.contains("network") || lowercased.contains("connection") -> NETWORK
                lowercased.contains("validation") || lowercased.contains("invalid") || lowercased.contains("checksum") -> VALIDATION
                lowercased.contains("hardware") || lowercased.contains("device") || lowercased.contains("thermal") -> HARDWARE
                lowercased.contains("auth") || lowercased.contains("credential") || lowercased.contains("api key") -> AUTHENTICATION
                lowercased.contains("model") || lowercased.contains("load") -> MODEL
                lowercased.contains("storage") || lowercased.contains("disk") || lowercased.contains("space") -> STORAGE
                lowercased.contains("initialize") || lowercased.contains("not initialized") -> INITIALIZATION
                lowercased.contains("component") -> COMPONENT
                lowercased.contains("framework") -> FRAMEWORK
                lowercased.contains("generation") || lowercased.contains("generate") -> GENERATION
                else -> UNKNOWN
            }
        }
    }
}
