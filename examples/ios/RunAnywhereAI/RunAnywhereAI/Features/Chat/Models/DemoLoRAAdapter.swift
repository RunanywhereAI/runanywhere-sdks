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
    /// All adapters are from Void2377/Qwen HuggingFace repo — trained on Qwen 2.5 0.5B.
    static let adapters: [LoraAdapterCatalogEntry] = [
        // --- Adapters matching Android's ModelList.kt ---
        LoraAdapterCatalogEntry(
            id: "code-assistant-lora",
            name: "Code Assistant",
            description: "Enhances code generation and programming assistance",
            downloadURL: URL(string: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/code-assistant-Q8_0.gguf")!,
            filename: "code-assistant-Q8_0.gguf",
            compatibleModelIds: ["qwen2.5-0.5b-instruct-q6_k"],
            fileSize: 765_952,
            defaultScale: 1.0
        ),
        LoraAdapterCatalogEntry(
            id: "reasoning-logic-lora",
            name: "Reasoning Logic",
            description: "Improves logical reasoning and step-by-step problem solving",
            downloadURL: URL(string: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/reasoning-logic-Q8_0.gguf")!,
            filename: "reasoning-logic-Q8_0.gguf",
            compatibleModelIds: ["qwen2.5-0.5b-instruct-q6_k"],
            fileSize: 765_952,
            defaultScale: 1.0
        ),
        LoraAdapterCatalogEntry(
            id: "medical-qa-lora",
            name: "Medical QA",
            description: "Enhances medical question answering and health-related responses",
            downloadURL: URL(string: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/medical-qa-Q8_0.gguf")!,
            filename: "medical-qa-Q8_0.gguf",
            compatibleModelIds: ["qwen2.5-0.5b-instruct-q6_k"],
            fileSize: 765_952,
            defaultScale: 1.0
        ),
        LoraAdapterCatalogEntry(
            id: "creative-writing-lora",
            name: "Creative Writing",
            description: "Improves creative writing, storytelling, and literary style",
            downloadURL: URL(string: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/creative-writing-Q8_0.gguf")!,
            filename: "creative-writing-Q8_0.gguf",
            compatibleModelIds: ["qwen2.5-0.5b-instruct-q6_k"],
            fileSize: 765_952,
            defaultScale: 1.0
        ),
    ]
}
