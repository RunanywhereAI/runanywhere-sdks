//
//  ModelFamily.swift
//  RunAnywhereAI
//
//  Pure, testable grouping of `RAModelInfo` into consumer-facing model families
//  (Qwen3, LFM2, Llama 3.2, Whisper, …). Families let the Models screen show one
//  clean card per family, then a detail listing that family's variants. No SDK
//  protos are constructed — this operates purely on `RAModelInfo` values.
//

import Foundation
import RunAnywhere

/// A consumer-facing family of related model variants (e.g. all Qwen3 builds).
struct ModelFamily: Identifiable {
    let id: String
    let displayName: String
    let tagline: String
    /// Variants ordered smaller/faster → larger/smarter.
    let variants: [RAModelInfo]

    /// Category used for section grouping and iconography (from the primary variant).
    var category: RAModelCategory { variants.first?.category ?? .unspecified }

    /// The cleanest single tag to show on the family row (feel for chat models,
    /// else the capability), taken from the primary variant.
    var headlineTag: ModelCapabilityBadge? {
        guard let primary = variants.first else { return nil }
        return primary.category == .language
            ? primary.consumerTags.first
            : primary.notableCapabilityBadge
    }

    /// Number of downloadable/usable options in this family.
    var optionCount: Int { variants.count }

    /// True when any variant is already downloaded or built in.
    var hasReadyVariant: Bool {
        variants.contains { $0.isBuiltIn || $0.localPathURL != nil }
    }
}

/// Declarative family rule: an ordered match against a model's id/name.
private struct FamilyRule {
    let key: String
    let displayName: String
    let tagline: String
    /// Lowercased substrings; a model matches if any is contained in `id`/`name`.
    let patterns: [String]
}

/// Pure grouping engine. Order of `rules` matters — the first matching rule wins,
/// so more specific families must precede more general ones.
enum ModelFamilyCatalog {
    /// Ordered so specific variants (e.g. SmolVLM2) match before broader ones.
    private static let rules: [FamilyRule] = [
        FamilyRule(key: "smolvlm", displayName: "SmolVLM",
                   tagline: "Tiny models that can see images",
                   patterns: ["smolvlm"]),
        FamilyRule(key: "smollm", displayName: "SmolLM",
                   tagline: "Ultra-compact chat models",
                   patterns: ["smollm"]),
        FamilyRule(key: "qwen3-vl", displayName: "Qwen3-VL",
                   tagline: "Newest Qwen models that understand images",
                   patterns: ["qwen3-vl"]),
        FamilyRule(key: "qwen2-vl", displayName: "Qwen2-VL",
                   tagline: "Qwen models that understand images",
                   patterns: ["qwen2-vl", "qwen2.5-vl"]),
        FamilyRule(key: "qwen3-asr", displayName: "Qwen3 Voice",
                   tagline: "Qwen speech-to-text",
                   patterns: ["qwen3-asr"]),
        FamilyRule(key: "qwen3-tts", displayName: "Qwen3 Speech",
                   tagline: "Qwen text-to-speech voices",
                   patterns: ["qwen3-tts"]),
        FamilyRule(key: "qwen3-embedding", displayName: "Qwen3 Embeddings",
                   tagline: "Understands documents for search & Q&A",
                   patterns: ["qwen3-embedding"]),
        FamilyRule(key: "qwen3", displayName: "Qwen3",
                   tagline: "Fast, capable everyday assistants",
                   patterns: ["qwen3", "qwen3.5"]),
        FamilyRule(key: "qwen2", displayName: "Qwen2.5",
                   tagline: "Reliable general-purpose chat",
                   patterns: ["qwen2.5", "qwen2"]),
        FamilyRule(key: "llama-3.2", displayName: "Llama 3.2",
                   tagline: "Meta's versatile assistants",
                   patterns: ["llama-3.2"]),
        FamilyRule(key: "llama-2", displayName: "Llama 2",
                   tagline: "Meta's classic chat models",
                   patterns: ["llama-2"]),
        FamilyRule(key: "lfm2-vl", displayName: "LFM2 Vision",
                   tagline: "Compact models that can see",
                   patterns: ["lfm2-vl"]),
        FamilyRule(key: "lfm2", displayName: "LFM2",
                   tagline: "Efficient assistants, great for tools",
                   patterns: ["lfm2"]),
        FamilyRule(key: "mistral", displayName: "Mistral",
                   tagline: "Strong open chat models",
                   patterns: ["mistral"]),
        FamilyRule(key: "gemma", displayName: "Gemma",
                   tagline: "Google's on-device models",
                   patterns: ["gemma"]),
        FamilyRule(key: "whisper", displayName: "Whisper",
                   tagline: "Accurate speech-to-text",
                   patterns: ["whisper"]),
        FamilyRule(key: "parakeet", displayName: "Parakeet",
                   tagline: "Fast streaming speech-to-text",
                   patterns: ["parakeet"]),
        FamilyRule(key: "glm-asr", displayName: "GLM Voice",
                   tagline: "Compact speech-to-text",
                   patterns: ["glm-asr"]),
        FamilyRule(key: "piper", displayName: "Piper",
                   tagline: "Natural read-aloud voices",
                   patterns: ["piper", "vits-piper"]),
        FamilyRule(key: "kokoro", displayName: "Kokoro",
                   tagline: "Expressive text-to-speech",
                   patterns: ["kokoro"]),
        FamilyRule(key: "kitten", displayName: "Kitten",
                   tagline: "Tiny text-to-speech",
                   patterns: ["kitten"]),
        FamilyRule(key: "soprano", displayName: "Soprano",
                   tagline: "Lightweight read-aloud voices",
                   patterns: ["soprano"]),
        FamilyRule(key: "pocket-tts", displayName: "Pocket Speech",
                   tagline: "Pocket-sized text-to-speech",
                   patterns: ["pocket-tts"]),
        FamilyRule(key: "silero", displayName: "Silero",
                   tagline: "Detects when someone is speaking",
                   patterns: ["silero"]),
        FamilyRule(key: "minilm", displayName: "MiniLM",
                   tagline: "Understands documents for search & Q&A",
                   patterns: ["minilm"]),
        FamilyRule(key: "diffusion", displayName: "Image Generation",
                   tagline: "Apple on-device image generation",
                   patterns: ["diffusion"]),
        FamilyRule(key: "apple-foundation", displayName: "Apple Intelligence",
                   tagline: "Built into this device — no download",
                   patterns: ["foundation"])
    ]

    /// Group models into families, preserving a stable, consumer-friendly order:
    /// chat first, then vision, voice, documents; families sorted by readiness
    /// then name. Variants within a family are ordered smaller → larger.
    static func families(from models: [RAModelInfo]) -> [ModelFamily] {
        var buckets: [String: [RAModelInfo]] = [:]
        var order: [String] = []

        // LoRA adapters customize a loaded base model; they are not standalone
        // downloads and would only surface as raw one-off families here.
        for model in models where !model.isLoRAAdapterArtifact {
            let rule = rule(for: model)
            let key = rule?.key ?? fallbackKey(for: model)
            if buckets[key] == nil {
                buckets[key] = []
                order.append(key)
            }
            buckets[key]?.append(model)
        }

        let families: [ModelFamily] = order.compactMap { key in
            guard let members = buckets[key], !members.isEmpty else { return nil }
            let sorted = members.sorted { $0.consumerSizeBytes < $1.consumerSizeBytes }
            let rule = rules.first { $0.key == key }
            return ModelFamily(
                id: key,
                displayName: rule?.displayName ?? sorted[0].consumerDisplayName,
                tagline: rule?.tagline ?? sorted[0].category.consumerCapabilityLabel,
                variants: sorted
            )
        }

        return families.sorted(by: familyOrder)
    }

    // MARK: - Helpers

    private static func rule(for model: RAModelInfo) -> FamilyRule? {
        let haystack = "\(model.id) \(model.name)".lowercased()
        return rules.first { rule in
            rule.patterns.contains { haystack.contains($0) }
        }
    }

    /// Models with no matching rule fall back to a per-model family so nothing
    /// is dropped from the catalog.
    private static func fallbackKey(for model: RAModelInfo) -> String {
        "model-\(model.id)"
    }

    /// Chat → vision → voice → documents → other; then ready families first,
    /// then alphabetical for a stable, scannable list.
    private static func familyOrder(_ lhs: ModelFamily, _ rhs: ModelFamily) -> Bool {
        let lhsRank = categoryRank(lhs.category)
        let rhsRank = categoryRank(rhs.category)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.hasReadyVariant != rhs.hasReadyVariant { return lhs.hasReadyVariant }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func categoryRank(_ category: RAModelCategory) -> Int {
        switch category {
        case .language: return 0
        case .multimodal, .vision, .imageGeneration: return 1
        case .speechRecognition, .speechSynthesis, .audio, .voiceActivityDetection: return 2
        case .embedding: return 3
        default: return 4
        }
    }
}

extension RAModelInfo {
    /// Friendly "smaller · faster" ↔ "larger · smarter" label for a variant,
    /// relative to the range of sizes within its family. Never exposes quant
    /// strings. `position` is the variant's index; `count` the family size.
    func variantFeelLabel(position: Int, count: Int) -> String {
        guard count > 1 else { return "Recommended size" }
        switch position {
        case 0: return "Smaller · faster"
        case count - 1: return "Larger · smarter"
        default: return "Balanced"
        }
    }
}
