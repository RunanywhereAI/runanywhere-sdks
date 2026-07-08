//
//  ModelRecommendation.swift
//  RunAnywhereAI
//
//  Hardware-aware, pure recommendation engine. Given a hardware tier and the
//  live catalog of registered models, it selects a consumer-friendly default
//  chat model plus a curated spread of LLM / ASR / TTS / VLM / embedding picks
//  that fit the device's memory budget.
//

import Foundation
import RunAnywhere

/// The curated set of recommendations surfaced at the top of the Models screen.
struct RecommendedSelection {
    /// The single best default chat model (Apple Foundation when available,
    /// otherwise the best-fit local LLM for this tier).
    let defaultChatModel: RAModelInfo?
    /// 3-5 LLMs appropriate for the tier, ordered from light to smart.
    let recommendedLLMs: [RAModelInfo]
    let recommendedASR: RAModelInfo?
    let recommendedTTS: RAModelInfo?
    let recommendedVLM: RAModelInfo?
    let recommendedEmbedding: RAModelInfo?

    /// All ids surfaced above the catalog, used to avoid duplicating them in
    /// the searchable list below.
    var surfacedModelIDs: Set<String> {
        var ids = Set(recommendedLLMs.map(\.id))
        [defaultChatModel, recommendedASR, recommendedTTS, recommendedVLM, recommendedEmbedding]
            .compactMap { $0?.id }
            .forEach { ids.insert($0) }
        return ids
    }

    /// The "also recommended" companions (ASR/TTS/VLM/embedding) in a stable order.
    var companions: [RAModelInfo] {
        [recommendedVLM, recommendedASR, recommendedTTS, recommendedEmbedding].compactMap { $0 }
    }
}

/// The best-for-device Voice AI trio (+ VAD) used to pre-configure the Voice
/// assistant with zero manual picking.
struct VoicePipeline {
    /// Speech-to-text model.
    let stt: RAModelInfo?
    /// Language model (Apple Foundation preferred when available).
    let llm: RAModelInfo?
    /// Text-to-speech model.
    let tts: RAModelInfo?
    /// Voice-activity-detection model (silero-vad).
    let vad: RAModelInfo?

    /// True when the three primary components (STT/LLM/TTS) are all resolved.
    var isComplete: Bool {
        stt != nil && llm != nil && tts != nil
    }
}

/// Pure engine that maps `HardwareTier` + available models to a curated
/// `RecommendedSelection`. Prefers real registered ids from
/// `ModelCatalogBootstrap`, with graceful category-based fallbacks so the UI is
/// never empty when a preferred id is missing.
struct ModelRecommendationEngine {
    /// Preferred LLM ids per tier, ordered light → smart. The engine keeps the
    /// first few that are both present in the catalog and fit the memory budget.
    fileprivate struct TierPreferences {
        let llmIDs: [String]
        let asrIDs: [String]
        let ttsIDs: [String]
        let vlmIDs: [String]
        let embeddingIDs: [String]
    }

    func recommend(
        tier: HardwareTier,
        appleFoundationAvailable: Bool,
        from models: [RAModelInfo]
    ) -> RecommendedSelection {
        let byID = Dictionary(models.map { ($0.id, $0) }) { first, _ in first }
        let prefs = preferences(for: tier)

        let recommendedLLMs = pickModels(
            ids: prefs.llmIDs,
            from: byID,
            tier: tier,
            limit: tier == .highEnd ? 5 : 4
        )

        let appleFoundation = appleFoundationAvailable
            ? models.first { $0.isAppleFoundationModel && $0.category == .language }
            : nil

        let defaultChat = appleFoundation ?? recommendedLLMs.first

        return RecommendedSelection(
            defaultChatModel: defaultChat,
            recommendedLLMs: recommendedLLMs,
            recommendedASR: pickFirst(ids: prefs.asrIDs, from: byID, tier: tier),
            recommendedTTS: pickFirst(ids: prefs.ttsIDs, from: byID, tier: tier),
            recommendedVLM: pickFirst(ids: prefs.vlmIDs, from: byID, tier: tier),
            recommendedEmbedding: pickFirst(ids: prefs.embeddingIDs, from: byID, tier: tier)
        )
    }

    /// Best-for-device Voice AI trio (+ VAD), reusing the same curated per-tier
    /// preferences. LLM prefers Apple Foundation when available, else the top
    /// recommended local LLM. Pure — safe to call from a view model.
    func recommendVoicePipeline(
        tier: HardwareTier,
        appleFoundationAvailable: Bool,
        from models: [RAModelInfo]
    ) -> VoicePipeline {
        let byID = Dictionary(models.map { ($0.id, $0) }) { first, _ in first }
        let prefs = preferences(for: tier)

        let appleFoundation = appleFoundationAvailable
            ? models.first { $0.isAppleFoundationModel && $0.category == .language }
            : nil
        let llm = appleFoundation
            ?? pickFirst(ids: prefs.llmIDs, from: byID, tier: tier)

        return VoicePipeline(
            stt: pickFirst(ids: prefs.asrIDs, from: byID, tier: tier),
            llm: llm,
            tts: pickFirst(ids: prefs.ttsIDs, from: byID, tier: tier),
            vad: byID[Self.vadModelID]
        )
    }

    /// The registered VAD model id (see `ModelCatalogBootstrap`).
    static let vadModelID = "silero-vad"

    // MARK: - Selection helpers

    /// Keep the ordered ids that exist in the catalog and fit the tier budget,
    /// up to `limit`. Preserves the curated order (light → smart).
    private func pickModels(
        ids: [String],
        from byID: [String: RAModelInfo],
        tier: HardwareTier,
        limit: Int
    ) -> [RAModelInfo] {
        var picked: [RAModelInfo] = []
        for id in ids {
            guard picked.count < limit else { break }
            if let model = byID[id], fits(model, tier: tier) {
                picked.append(model)
            }
        }
        return picked
    }

    /// First catalog model from the ordered ids that fits the tier budget.
    private func pickFirst(
        ids: [String],
        from byID: [String: RAModelInfo],
        tier: HardwareTier
    ) -> RAModelInfo? {
        for id in ids {
            if let model = byID[id], fits(model, tier: tier) {
                return model
            }
        }
        return nil
    }

    /// A model fits when its required footprint is within the tier's budget.
    /// Unknown-size models are allowed through (the SDK still guards download).
    private func fits(_ model: RAModelInfo, tier: HardwareTier) -> Bool {
        let bytes = model.consumerSizeBytes
        guard bytes > 0 else { return true }
        return bytes <= tier.memoryBudgetBytes
    }

    // MARK: - Curated per-tier preferences (real registered ids)

    private func preferences(for tier: HardwareTier) -> TierPreferences {
        switch tier {
        case .lowEnd: return .lowEnd
        case .midRange: return .midRange
        case .highEnd: return .highEnd
        }
    }
}

// MARK: - Curated id lists (real registered ids from ModelCatalogBootstrap)

private extension ModelRecommendationEngine.TierPreferences {
    /// Smallest quantized / ONNX variants only.
    static let lowEnd = Self(
        llmIDs: [
            "mlx-lfm2-350m",
            "lfm2-350m-q4_k_m",
            "mlx-qwen3-0.6b-4bit",
            "qwen3-0.6b-q4_k_m"
        ],
        asrIDs: [
            "mlx-whisper-tiny-en-asr-4bit",
            "sherpa-onnx-whisper-tiny.en"
        ],
        ttsIDs: [
            "mlx-kitten-tts-nano-0.8-5bit",
            "vits-piper-en_US-lessac-medium"
        ],
        vlmIDs: [
            "smolvlm2-256m-video-instruct-q8_0",
            "lfm2-vl-450m-q8_0"
        ],
        embeddingIDs: [
            "all-minilm-l6-v2",
            "mlx-qwen3-embedding-0.6b-4bit-dwq"
        ]
    )

    /// A spread: tiny/fast, balanced, tool-calling, thinking.
    static let midRange = Self(
        llmIDs: [
            "mlx-lfm2-350m",
            "mlx-llama-3.2-1b-instruct-4bit",
            "lfm2-1.2b-tool-q4_k_m",
            "mlx-qwen3-0.6b-4bit",
            "qwen3-1.7b-q4_k_m"
        ],
        asrIDs: [
            "mlx-whisper-tiny-en-asr-4bit",
            "sherpa-onnx-whisper-tiny.en"
        ],
        ttsIDs: [
            "mlx-kitten-tts-nano-0.8-5bit",
            "mlx-soprano-1.1-80m-5bit",
            "vits-piper-en_US-lessac-medium"
        ],
        vlmIDs: [
            "mlx-qwen2-vl-2b-instruct-4bit",
            "smolvlm2-500m-video-instruct-q8_0",
            "smolvlm2-256m-video-instruct-q8_0"
        ],
        embeddingIDs: [
            "mlx-qwen3-embedding-0.6b-4bit-dwq",
            "all-minilm-l6-v2"
        ]
    )

    /// Full spread including a larger "genius" model.
    static let highEnd = Self(
        llmIDs: [
            "mlx-llama-3.2-1b-instruct-4bit",
            "llama-3.2-3b-instruct-q4_k_m",
            "lfm2-1.2b-tool-q4_k_m",
            "qwen3-4b-q4_k_m",
            "mlx-qwen3-4b-4bit"
        ],
        asrIDs: [
            "mlx-whisper-tiny-en-asr-4bit",
            "sherpa-onnx-whisper-tiny.en"
        ],
        ttsIDs: [
            "mlx-kitten-tts-nano-0.8-5bit",
            "mlx-soprano-1.1-80m-5bit",
            "vits-piper-en_US-lessac-medium"
        ],
        vlmIDs: [
            "mlx-qwen2-vl-2b-instruct-4bit",
            "mlx-qwen3-vl-4b-instruct-4bit",
            "qwen2.5-vl-3b-instruct-q4_k_m"
        ],
        embeddingIDs: [
            "mlx-qwen3-embedding-0.6b-4bit-dwq",
            "all-minilm-l6-v2"
        ]
    )
}
