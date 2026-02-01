//
//  ModelLogoHelper.swift
//  RunAnywhereAI
//
//  Helper function for getting model logo when only model name is available
//

import Foundation

/// Returns the asset name for a model logo based on model name
/// Falls back to Hugging Face logo if no specific logo is available
/// - Parameter modelName: The name of the model
/// - Returns: Asset name for the model logo
func getModelLogo(for modelName: String) -> String {
    let name = modelName.lowercased()

    // Check for system/platform models
    if name.contains("system") || name.contains("platform") || name.contains("foundation") {
        return "foundation_models_logo"
    }

    // Check for vendor-specific logos
    if name.contains("llama") {
        return "llama_logo"
    } else if name.contains("mistral") {
        return "mistral_logo"
    } else if name.contains("qwen") {
        return "qwen_logo"
    } else if name.contains("liquid") {
        return "liquid_ai_logo"
    } else if name.contains("piper") {
        return "hugging_face_logo"
    } else if name.contains("whisper") {
        return "hugging_face_logo"
    } else if name.contains("sherpa") {
        return "hugging_face_logo"
    }

    // Default fallback for all other models
    return "hugging_face_logo"
}
