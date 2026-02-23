//
//  ModelRegistry.swift
//  YapRun
//
//  Centralized ASR model definitions shared across iOS and macOS.
//

import Foundation
import RunAnywhere

enum ModelRegistry {

    struct ASRModel {
        let id: String
        let name: String
        let description: String
        let url: URL
        let archiveType: ArchiveType
        let framework: InferenceFramework
        let sizeBytes: Int64
    }

    /// Default model used during onboarding.
    static let defaultModelId = "whisperkit-tiny.en"

    /// Curated ASR models with consumer-friendly names (tar.gz for fast native gzip extraction on iOS/macOS).
    static let asrModels: [ASRModel] = [
        // ─── WhisperKit (Apple Neural Engine via Core ML) ───────────────
        ASRModel(
            id: "whisperkit-tiny.en",
            name: "Fast",
            description: "Fastest transcription on Apple Neural Engine — low battery and memory. Best for quick notes.",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/whisperkit-tiny.en.tar.gz")!,
            archiveType: .tarGz,
            framework: .whisperKitCoreML,
            sizeBytes: 70_000_000
        ),
        ASRModel(
            id: "whisperkit-base.en",
            name: "Accurate",
            description: "Higher accuracy on Neural Engine. Uses more memory. Best for longer dictation.",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/whisperkit-base.en.tar.gz")!,
            archiveType: .tarGz,
            framework: .whisperKitCoreML,
            sizeBytes: 134_000_000
        ),

        // ─── ONNX (CPU via sherpa-onnx) ────────────────────────────────
        ASRModel(
            id: "asr-moonshine-tiny-en-int8",
            name: "Compact (CPU)",
            description: "Quantized int8 model on CPU. Good if Neural Engine is busy.",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/sherpa-onnx-moonshine-tiny-en-int8.tar.gz")!,
            archiveType: .tarGz,
            framework: .onnx,
            sizeBytes: 118_000_000
        ),
        ASRModel(
            id: "sherpa-onnx-whisper-tiny.en",
            name: "Whisper CPU",
            description: "Standard Whisper on CPU. Maximum device compatibility.",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/sherpa-onnx-whisper-tiny.en.tar.gz")!,
            archiveType: .tarGz,
            framework: .onnx,
            sizeBytes: 75_000_000
        ),

        // ─── Commented out: too heavy or niche for consumer use ────────
        // ASRModel(
        //     id: "asr-moonshine-base-en-int8",
        //     name: "Moonshine Base EN (int8)",
        //     description: "Larger Moonshine model. 273 MB — heavy for most devices.",
        //     url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/sherpa-onnx-moonshine-base-en-int8.tar.gz")!,
        //     archiveType: .tarGz,
        //     framework: .onnx,
        //     sizeBytes: 273_000_000
        // ),
        // ASRModel(
        //     id: "asr-parakeet-tdt-ctc-110m-en-int8",
        //     name: "Parakeet TDT-CTC 110M EN (int8)",
        //     description: "Niche NVIDIA Parakeet model.",
        //     url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8.tar.gz")!,
        //     archiveType: .tarGz,
        //     framework: .onnx,
        //     sizeBytes: 126_000_000
        // ),
    ]

    /// Look up the consumer-facing description for a model ID.
    static func description(for modelId: String) -> String? {
        asrModels.first { $0.id == modelId }?.description
    }

    /// Register all ASR models with the RunAnywhere SDK.
    static func registerAll() {
        for model in asrModels {
            RunAnywhere.registerModel(
                id: model.id,
                name: model.name,
                url: model.url,
                framework: model.framework,
                modality: .speechRecognition,
                artifactType: .archive(model.archiveType, structure: .nestedDirectory),
                memoryRequirement: model.sizeBytes
            )
        }
    }
}
