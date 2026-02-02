//
//  ModelInfo+Logo.swift
//  RunAnywhereAI
//
//  Model logo asset name mapping extension
//

import RunAnywhere

extension ModelInfo {
    /// Returns the asset name for the model's logo
    /// Falls back to Hugging Face logo if no specific logo is available
    var logoAssetName: String {
        let modelName = name.lowercased()

        // Check framework first for built-in models
        if framework == .foundationModels || framework == .systemTTS {
            return "foundation_models_logo"
        }

        // Check for vendor-specific logos
        if modelName.contains("llama") {
            return "llama_logo"
        } else if modelName.contains("mistral") {
            return "mistral_logo"
        } else if modelName.contains("qwen") {
            return "qwen_logo"
        } else if modelName.contains("liquid") {
            return "liquid_ai_logo"
        } else if modelName.contains("piper") {
            return "hugging_face_logo"
        } else if modelName.contains("whisper") {
            return "hugging_face_logo"
        } else if modelName.contains("sherpa") {
            return "hugging_face_logo"
        }

        // Default fallback for all other models
        return "hugging_face_logo"
    }
}
