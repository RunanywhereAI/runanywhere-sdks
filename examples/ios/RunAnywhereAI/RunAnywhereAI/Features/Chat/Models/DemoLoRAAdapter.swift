//
//  DemoLoRAAdapter.swift
//  RunAnywhereAI
//
//  Registers LoRA adapters into the SDK's global LoRA registry at startup.
//  Uses the SDK's LoraAdapterCatalogEntry — same type and registry that Android uses.
//
//  TODO: [Portal Integration] Replace hardcoded adapters with portal-provided catalog.

import Foundation
import RunAnywhere

enum LoRAAdapterCatalog {

    /// Register all known LoRA adapters into the SDK's C++ registry.
    /// Call once at startup, after SDK initialization.
    static func registerAll() async {
        for entry in adapters {
            do {
                try await RunAnywhere.registerLoraAdapter(entry)
            } catch {
                print("[LoRA] Failed to register adapter \(entry.id): \(error)")
            }
        }
    }

    /// All hardcoded adapters (matches Android's ModelList.kt)
    static let adapters: [LoraAdapterCatalogEntry] = [
        LoraAdapterCatalogEntry(
            id: "chat-assistant-lora",
            name: "Chat Assistant",
            description: "Enhances conversational chat ability",
            downloadURL: URL(string: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/chat_assistant-lora-Q8_0.gguf")!,
            filename: "chat_assistant-lora-Q8_0.gguf",
            compatibleModelIds: ["lfm2-350m-q4_k_m", "lfm2-350m-q8_0"],
            fileSize: 690_176,
            defaultScale: 1.0
        ),
        LoraAdapterCatalogEntry(
            id: "summarizer-lora",
            name: "Summarizer",
            description: "Specialized for text summarization tasks",
            downloadURL: URL(string: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/summarizer-lora-Q8_0.gguf")!,
            filename: "summarizer-lora-Q8_0.gguf",
            compatibleModelIds: ["lfm2-350m-q4_k_m", "lfm2-350m-q8_0"],
            fileSize: 690_176,
            defaultScale: 1.0
        ),
        LoraAdapterCatalogEntry(
            id: "translator-lora",
            name: "Translator",
            description: "Improves translation between languages",
            downloadURL: URL(string: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/translator-lora-Q8_0.gguf")!,
            filename: "translator-lora-Q8_0.gguf",
            compatibleModelIds: ["lfm2-350m-q4_k_m", "lfm2-350m-q8_0"],
            fileSize: 690_176,
            defaultScale: 1.0
        ),
        LoraAdapterCatalogEntry(
            id: "sentiment-lora",
            name: "Sentiment Analysis",
            description: "Fine-tuned for sentiment analysis tasks",
            downloadURL: URL(string: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/sentiment-lora-Q8_0.gguf")!,
            filename: "sentiment-lora-Q8_0.gguf",
            compatibleModelIds: ["lfm2-350m-q4_k_m", "lfm2-350m-q8_0"],
            fileSize: 690_176,
            defaultScale: 1.0
        ),
    ]
}
