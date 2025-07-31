package com.runanywhere.sdk

class RunAnywhereSDK {

    fun initialize(apiKey: String) {
        // SDK initialization logic
        println("RunAnywhereSDK initialized with API key: ${apiKey.take(5)}...")
    }

    fun execute(prompt: String): String {
        // Placeholder implementation
        return "Response for: $prompt"
    }

    companion object {
        const val VERSION = "0.1.0"
    }
}
