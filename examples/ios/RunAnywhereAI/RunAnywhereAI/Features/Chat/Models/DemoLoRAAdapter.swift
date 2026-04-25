//
//  DemoLoRAAdapter.swift
//  RunAnywhereAI
//
//  Registers LoRA adapters into the SDK's global LoRA registry at startup.
//  Uses the SDK's LoraAdapterCatalogEntry — same type and registry that Android uses.

import Foundation
import os
import RunAnywhere

enum LoRAAdapterCatalog {
    private static let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "LoRAAdapterCatalog")

    /// Register all known LoRA adapters into the SDK's C++ registry.
    /// Call once at startup, after SDK initialization.
    static func registerAll() async {
        for entry in adapters {
            do {
                try await RunAnywhere.registerLoraAdapter(entry)
            } catch {
                logger.error("Failed to register adapter \(entry.id): \(error)")
            }
        }
    }

    // Helper that builds a `LoraAdapterCatalogEntry` from a string URL.
    // Returns `nil` on malformed URL — the entry is then dropped from the catalog.
    // swiftlint:disable:next function_parameter_count
    private static func entry(
        id: String,
        name: String,
        description: String,
        urlString: String,
        filename: String,
        compatibleModelIds: [String],
        fileSize: Int64,
        defaultScale: Float = 1.0
    ) -> LoraAdapterCatalogEntry? {
        guard let url = URL(string: urlString) else { return nil }
        return LoraAdapterCatalogEntry(
            id: id,
            name: name,
            description: description,
            downloadURL: url,
            filename: filename,
            compatibleModelIds: compatibleModelIds,
            fileSize: fileSize,
            defaultScale: defaultScale
        )
    }

    /// All hardcoded adapters (matches Android's ModelList.kt)
    /// All adapters are from Void2377/Qwen HuggingFace repo — trained on Qwen 2.5 0.5B.
    static let adapters: [LoraAdapterCatalogEntry] = [
        // --- Adapters matching Android's ModelList.kt ---
        entry(
            id: "code-assistant-lora",
            name: "Code Assistant",
            description: "Enhances code generation and programming assistance",
            urlString: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/code-assistant-Q8_0.gguf",
            filename: "code-assistant-Q8_0.gguf",
            compatibleModelIds: ["qwen2.5-0.5b-instruct-q6_k"],
            fileSize: 765_952
        ),
        entry(
            id: "reasoning-logic-lora",
            name: "Reasoning Logic",
            description: "Improves logical reasoning and step-by-step problem solving",
            urlString: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/reasoning-logic-Q8_0.gguf",
            filename: "reasoning-logic-Q8_0.gguf",
            compatibleModelIds: ["qwen2.5-0.5b-instruct-q6_k"],
            fileSize: 765_952
        ),
        entry(
            id: "medical-qa-lora",
            name: "Medical QA",
            description: "Enhances medical question answering and health-related responses",
            urlString: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/medical-qa-Q8_0.gguf",
            filename: "medical-qa-Q8_0.gguf",
            compatibleModelIds: ["qwen2.5-0.5b-instruct-q6_k"],
            fileSize: 765_952
        ),
        entry(
            id: "creative-writing-lora",
            name: "Creative Writing",
            description: "Improves creative writing, storytelling, and literary style",
            urlString: "https://huggingface.co/Void2377/Qwen/resolve/main/lora/creative-writing-Q8_0.gguf",
            filename: "creative-writing-Q8_0.gguf",
            compatibleModelIds: ["qwen2.5-0.5b-instruct-q6_k"],
            fileSize: 765_952
        ),
        // --- Abliterated adapter (uncensored fine-tune for Qwen 2.5 0.5B base) ---
        entry(
            id: "abliterated-lora",
            name: "Abliterated (Uncensored)",
            description: "Removes content restrictions for unrestricted responses",
            urlString: "https://huggingface.co/Void2377/qwen-lora-gguf/resolve/main/qwen2.5-0.5b-abliterated-lora-f16.gguf",
            filename: "qwen2.5-0.5b-abliterated-lora-f16.gguf",
            compatibleModelIds: ["qwen2.5-0.5b-base-q8_0"],
            fileSize: 17_620_224
        )
    ].compactMap { $0 }
}
