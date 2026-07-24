//
//  ModelOrg.swift
//  RunAnywhereAI
//
//  Organisation (publisher) grouping for the model picker — NVIDIA, Meta,
//  Alibaba, … — matching the Android ModelTaxonomy. No family/series cards.
//

import Foundation
import RunAnywhere

/// Organisation (publisher) for a model. Declaration order is the picker's
/// org ordering and matches Android's `ModelOrg`.
enum ModelOrg: String, CaseIterable, Identifiable, Comparable {
    case nvidia
    case meta
    case alibaba
    case google
    case microsoft
    case deepseek
    case liquid
    case mistral
    case prism
    case openAI
    case huggingFace
    case apple
    case openSource

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nvidia: return "NVIDIA"
        case .meta: return "Meta"
        case .alibaba: return "Alibaba"
        case .google: return "Google"
        case .microsoft: return "Microsoft"
        case .deepseek: return "DeepSeek"
        case .liquid: return "Liquid AI"
        case .mistral: return "Mistral AI"
        case .prism: return "Prism"
        case .openAI: return "OpenAI"
        case .huggingFace: return "Hugging Face"
        case .apple: return "Apple"
        case .openSource: return "Open source"
        }
    }

    var systemImage: String {
        switch self {
        case .nvidia: return "square.stack.3d.up.fill"
        case .meta: return "m.circle.fill"
        case .alibaba: return "q.circle.fill"
        case .google: return "g.circle.fill"
        case .microsoft: return "m.square.fill"
        case .deepseek: return "brain.head.profile"
        case .liquid: return "drop.fill"
        case .mistral: return "wind"
        case .prism: return "triangle.fill"
        case .openAI: return "waveform"
        case .huggingFace: return "face.smiling.fill"
        case .apple: return "apple.logo"
        case .openSource: return "shippingbox.fill"
        }
    }

    static func < (lhs: ModelOrg, rhs: ModelOrg) -> Bool {
        (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
    }
}

/// One organisation and every model it publishes in the current picker scope.
struct ModelOrgGroup: Identifiable {
    let org: ModelOrg
    /// Variants ordered smaller/faster → larger/smarter.
    let models: [RAModelInfo]

    var id: String { org.id }
    var displayName: String { org.displayName }
    var optionCount: Int { models.count }
    var category: RAModelCategory { models.first?.category ?? .unspecified }

    var hasReadyVariant: Bool {
        models.contains { $0.isBuiltIn || $0.localPathURL != nil }
    }

    var hasNpuVariant: Bool {
        models.contains { $0.framework == .qhexrt }
    }
}

/// Id/name tokens → org. First match wins (nemotron before llama, deepseek before qwen).
private struct OrgRule {
    let org: ModelOrg
    let patterns: [String]
}

enum ModelOrgCatalog {
    private static let rules: [OrgRule] = [
        OrgRule(org: .nvidia, patterns: [
            "nemotron", "nemoguard", "cosmos", "canary", "parakeet",
            "nv_embed", "nv-embed", "nv_rerank", "nvidia",
        ]),
        OrgRule(org: .deepseek, patterns: ["deepseek"]),
        OrgRule(org: .prism, patterns: ["bonsai"]),
        OrgRule(org: .microsoft, patterns: ["phi"]),
        OrgRule(org: .google, patterns: ["gemma", "embeddinggemma", "siglip"]),
        OrgRule(org: .meta, patterns: ["llama"]),
        OrgRule(org: .alibaba, patterns: ["qwen"]),
        OrgRule(org: .liquid, patterns: ["lfm2"]),
        OrgRule(org: .mistral, patterns: ["mistral"]),
        OrgRule(org: .huggingFace, patterns: ["smollm", "smolvlm"]),
        OrgRule(org: .openAI, patterns: ["whisper"]),
        OrgRule(org: .openSource, patterns: [
            "internvl", "lama_dilated", "moonshine", "melo", "kokoro",
            "kitten", "piper", "silero", "minilm", "soprano", "pocket-tts", "glm-asr",
        ]),
    ]

    static func org(for model: RAModelInfo) -> ModelOrg {
        if isPlatformBuiltIn(model) { return .apple }
        let haystack = "\(model.id) \(model.name)".lowercased()
        return rules.first { rule in
            rule.patterns.contains { haystack.contains($0) }
        }?.org ?? .openSource
    }

    /// Group models by organisation. Models smaller → larger within an org;
    /// orgs follow declaration order. Ready orgs are not re-ordered here —
    /// the sheet partitions "On this device" vs the rest.
    static func groups(from models: [RAModelInfo]) -> [ModelOrgGroup] {
        var buckets: [ModelOrg: [RAModelInfo]] = [:]

        for model in models where !model.isLoRAAdapterArtifact {
            let org = org(for: model)
            buckets[org, default: []].append(model)
        }

        return ModelOrg.allCases.compactMap { org in
            guard let members = buckets[org], !members.isEmpty else { return nil }
            let sorted = members.sorted { $0.consumerSizeBytes < $1.consumerSizeBytes }
            return ModelOrgGroup(org: org, models: sorted)
        }
    }

    private static func isPlatformBuiltIn(_ model: RAModelInfo) -> Bool {
        model.framework == .foundationModels || model.framework == .systemTts
            || model.id.lowercased().contains("foundation")
            || model.id.lowercased().contains("diffusion")
    }
}

extension RAModelInfo {
    /// Friendly "smaller · faster" ↔ "larger · smarter" label for a variant
    /// within an org's list. Never exposes quant strings.
    func variantFeelLabel(position: Int, count: Int) -> String {
        guard count > 1 else { return "Recommended size" }
        switch position {
        case 0: return "Smaller · faster"
        case count - 1: return "Larger · smarter"
        default: return "Balanced"
        }
    }
}
