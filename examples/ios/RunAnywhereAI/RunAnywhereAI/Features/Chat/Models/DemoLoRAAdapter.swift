//
//  DemoLoRAAdapter.swift
//  RunAnywhereAI
//
//  TODO: [Portal Integration] Remove this entire file once adapters are delivered OTA from portal.
//

import Foundation

// MARK: - Demo LoRA Adapter Registry

/// Represents a pre-registered LoRA adapter available for OTA download.
/// TODO: [Portal Integration] Replace with portal-provided adapter catalog model.
struct DemoLoRAAdapter: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let downloadURL: URL
    let fileName: String
    let compatibleModelIds: Set<String>
    let fileSize: Int64
    let defaultScale: Float

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - Demo Adapter Catalog

/// TODO: [Portal Integration] Remove once adapters are delivered OTA from portal.
enum DemoLoRAAdapterCatalog {
    static let adapters: [DemoLoRAAdapter] = [
        DemoLoRAAdapter(
            id: "qwen2.5-1.5b-abliterated-lora",
            name: "Abliterated (Uncensored)",
            description: "Removes refusal behavior from Qwen2.5-1.5B. From ggml-org.",
            downloadURL: URL(string: "https://huggingface.co/ggml-org/LoRA-Qwen2.5-1.5B-Instruct-abliterated-F16-GGUF/resolve/main/LoRA-Qwen2.5-1.5B-Instruct-abliterated-f16.gguf")!,
            fileName: "LoRA-Qwen2.5-1.5B-Instruct-abliterated-f16.gguf",
            compatibleModelIds: ["qwen2.5-1.5b-instruct-q4_k_m"],
            fileSize: 374_000_000,
            defaultScale: 1.0
        )
    ]

    static func adapters(forModelId modelId: String) -> [DemoLoRAAdapter] {
        adapters.filter { $0.compatibleModelIds.contains(modelId) }
    }
}
