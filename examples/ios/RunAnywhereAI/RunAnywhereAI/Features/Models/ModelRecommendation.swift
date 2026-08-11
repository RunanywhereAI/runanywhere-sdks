//
//  ModelRecommendation.swift
//  RunAnywhereAI
//
//  Curated catalog picks for the Models / Voice screens. Model-fit decisions
//  consume SDK/commons `RAModelCompatibilityResult.canRun` when supplied; the
//  app never invents a per-tier memory budget.
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

/// Pure engine that maps curated preference ids + optional commons
/// compatibility verdicts to a `RecommendedSelection`.
struct ModelRecommendationEngine {
    /// Preferred LLM ids per tier, ordered light → smart. The engine keeps the
    /// first few that are both present in the catalog and allowed by can_run.
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
        from models: [RAModelInfo],
        canRunByModelID: [String: Bool] = [:]
    ) -> RecommendedSelection {
        let byID = Dictionary(models.map { ($0.id, $0) }) { first, _ in first }
        let prefs = preferences(for: tier)

        let recommendedLLMs = pickModels(
            ids: prefs.llmIDs,
            from: byID,
            canRunByModelID: canRunByModelID,
            limit: tier == .highEnd ? 5 : 4
        )

        let appleFoundation = appleFoundationAvailable
            ? models.first { $0.isAppleFoundationModel && $0.category == .language }
            : nil

        let defaultChat = appleFoundation ?? recommendedLLMs.first

        return RecommendedSelection(
            defaultChatModel: defaultChat,
            recommendedLLMs: recommendedLLMs,
            recommendedASR: pickFirst(ids: prefs.asrIDs, from: byID, canRunByModelID: canRunByModelID),
            recommendedTTS: pickFirst(ids: prefs.ttsIDs, from: byID, canRunByModelID: canRunByModelID),
            recommendedVLM: pickFirst(ids: prefs.vlmIDs, from: byID, canRunByModelID: canRunByModelID),
            recommendedEmbedding: pickFirst(ids: prefs.embeddingIDs, from: byID, canRunByModelID: canRunByModelID)
        )
    }

    /// Best-for-device Voice AI trio (+ VAD), reusing the same curated per-tier
    /// preferences. LLM prefers Apple Foundation when available, else the top
    /// recommended local LLM. Pure — safe to call from a view model.
    func recommendVoicePipeline(
        tier: HardwareTier,
        appleFoundationAvailable: Bool,
        from models: [RAModelInfo],
        canRunByModelID: [String: Bool] = [:]
    ) -> VoicePipeline {
        let byID = Dictionary(models.map { ($0.id, $0) }) { first, _ in first }
        let prefs = preferences(for: tier)

        let appleFoundation = appleFoundationAvailable
            ? models.first { $0.isAppleFoundationModel && $0.category == .language }
            : nil
        let llm = appleFoundation
            ?? pickFirst(ids: prefs.llmIDs, from: byID, canRunByModelID: canRunByModelID)

        return VoicePipeline(
            stt: pickFirst(ids: prefs.asrIDs, from: byID, canRunByModelID: canRunByModelID),
            llm: llm,
            tts: pickFirst(ids: prefs.ttsIDs, from: byID, canRunByModelID: canRunByModelID),
            vad: byID[Self.vadModelID]
        )
    }

    /// The registered VAD model id (see `ModelCatalogBootstrap`).
    static let vadModelID = "silero-vad"

    // MARK: - Selection helpers

    /// Keep the ordered ids that exist in the catalog and pass can_run (when
    /// known), up to `limit`. Preserves the curated order (light → smart).
    private func pickModels(
        ids: [String],
        from byID: [String: RAModelInfo],
        canRunByModelID: [String: Bool],
        limit: Int
    ) -> [RAModelInfo] {
        var picked: [RAModelInfo] = []
        for id in ids {
            guard picked.count < limit else { break }
            if let model = byID[id], isRunnable(model, canRunByModelID: canRunByModelID) {
                picked.append(model)
            }
        }
        return picked
    }

    /// First catalog model from the ordered ids that passes can_run when known.
    private func pickFirst(
        ids: [String],
        from byID: [String: RAModelInfo],
        canRunByModelID: [String: Bool]
    ) -> RAModelInfo? {
        for id in ids {
            if let model = byID[id], isRunnable(model, canRunByModelID: canRunByModelID) {
                return model
            }
        }
        return nil
    }

    /// Prefer commons `can_run`. When the SDK has not returned a verdict for
    /// this id, allow the catalog entry through — never invent a local byte
    /// budget in place of typed compatibility.
    private func isRunnable(_ model: RAModelInfo, canRunByModelID: [String: Bool]) -> Bool {
        canRunByModelID[model.id] ?? true
    }

    // MARK: - Curated per-tier preferences (real registered ids)

    private func preferences(for tier: HardwareTier) -> TierPreferences {
        switch tier {
        case .unknown, .midRange: return .midRange
        case .lowEnd: return .lowEnd
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
            "sherpa-onnx-whisper-tiny.en",
            "mlx-qwen3-asr-0.6b-8bit"
        ],
        ttsIDs: [
            "mlx-soprano-1.1-80m-5bit",
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
            "mlx-qwen3-asr-0.6b-8bit",
            "sherpa-onnx-whisper-tiny.en"
        ],
        ttsIDs: [
            "mlx-soprano-1.1-80m-5bit",
            "vits-piper-en_US-lessac-medium"
        ],
        // No MLX Qwen2-VL. Measured on this Mac (M4 Max, MLX 4-bit): every vision
        // turn decoded its opening token and then repeated only that token —
        // 23 × "The" for "what colour is the circle?", the same for a photograph
        // and for a synthetic card, on a first turn and on later ones. The prompt
        // was sized correctly (418 tokens, image tokens included) and the MLX
        // *text* path answered normally with identical sampler settings, so this
        // is the model on this runtime, not our image or generation plumbing.
        // The web SDK already forces Qwen2-VL off WebGPU for an f16 M-RoPE
        // overflow; this is the same family failing the same way on Metal.
        // LFM2-VL through llama.cpp answers the same camera correctly (128 tokens
        // at 32 tok/s), so it leads instead. Qwen2-VL stays in the catalog —
        // pickable, just never the recommendation.
        vlmIDs: [
            "lfm2-vl-450m-q8_0",
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
            "mlx-qwen3-asr-0.6b-8bit",
            "sherpa-onnx-whisper-tiny.en"
        ],
        ttsIDs: [
            "mlx-soprano-1.1-80m-5bit",
            "vits-piper-en_US-lessac-medium"
        ],
        // Same reason as `midRange`: MLX Qwen2-VL answers with one repeated
        // token. Qwen2.5-VL is a different generation on a different runtime
        // (llama.cpp) and leads here; the MLX Qwen3-VL stays as the second
        // choice rather than the default no one chose.
        vlmIDs: [
            "qwen2.5-vl-3b-instruct-q4_k_m",
            "mlx-qwen3-vl-4b-instruct-4bit"
        ],
        embeddingIDs: [
            "mlx-qwen3-embedding-0.6b-4bit-dwq",
            "all-minilm-l6-v2"
        ]
    )
}
