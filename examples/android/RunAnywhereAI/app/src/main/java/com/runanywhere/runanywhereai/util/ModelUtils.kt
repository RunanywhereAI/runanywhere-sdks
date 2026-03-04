package com.runanywhere.runanywhereai.util

import com.runanywhere.runanywhereai.R

/**
 * Returns the appropriate logo drawable resource ID for a given model name.
 * This is a simplified version that works with just the model name string.
 *
 * @param name The model name to get logo for
 * @return Drawable resource ID for the model's logo
 */
fun getModelLogoResIdForName(name: String): Int {
    val lowercaseName = name.lowercase()
    return when {
        lowercaseName.contains("llama") -> R.drawable.llama_logo
        lowercaseName.contains("mistral") -> R.drawable.mistral_logo
        lowercaseName.contains("qwen") -> R.drawable.qwen_logo
        lowercaseName.contains("liquid") -> R.drawable.liquid_ai_logo
        lowercaseName.contains("piper") -> R.drawable.hugging_face_logo
        lowercaseName.contains("whisper") -> R.drawable.hugging_face_logo
        lowercaseName.contains("sherpa") -> R.drawable.hugging_face_logo
        lowercaseName.contains("foundation") -> R.drawable.foundation_models_logo
        lowercaseName.contains("system") -> R.drawable.foundation_models_logo
        else -> R.drawable.hugging_face_logo
    }
}
