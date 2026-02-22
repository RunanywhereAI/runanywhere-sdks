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
        let url: URL
        let archiveType: ArchiveType
        let framework: InferenceFramework
        let sizeBytes: Int64
    }

    /// Default model used during onboarding.
    static let defaultModelId = "asr-moonshine-tiny-en-int8"

    /// All available ASR models (tar.gz for fast native gzip extraction on iOS/macOS).
    static let asrModels: [ASRModel] = [
        // ONNX models (CPU via sherpa-onnx)
        ASRModel(
            id: "asr-moonshine-tiny-en-int8",
            name: "Moonshine Tiny EN (int8)",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/sherpa-onnx-moonshine-tiny-en-int8.tar.gz")!,
            archiveType: .tarGz,
            framework: .onnx,
            sizeBytes: 118_000_000
        ),
        ASRModel(
            id: "asr-moonshine-base-en-int8",
            name: "Moonshine Base EN (int8)",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/sherpa-onnx-moonshine-base-en-int8.tar.gz")!,
            archiveType: .tarGz,
            framework: .onnx,
            sizeBytes: 273_000_000
        ),
        ASRModel(
            id: "sherpa-onnx-whisper-tiny.en",
            name: "Whisper Tiny EN",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/sherpa-onnx-whisper-tiny.en.tar.gz")!,
            archiveType: .tarGz,
            framework: .onnx,
            sizeBytes: 75_000_000
        ),
        ASRModel(
            id: "asr-parakeet-tdt-ctc-110m-en-int8",
            name: "Parakeet TDT-CTC 110M EN (int8)",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/sherpa-onnx-nemo-parakeet_tdt_ctc_110m-en-36000-int8.tar.gz")!,
            archiveType: .tarGz,
            framework: .onnx,
            sizeBytes: 126_000_000
        ),

        // WhisperKit models (Apple Neural Engine via Core ML)
        ASRModel(
            id: "whisperkit-tiny.en",
            name: "Whisper Tiny EN (WhisperKit)",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/whisperkit-tiny.en.tar.gz")!,
            archiveType: .tarGz,
            framework: .whisperKitCoreML,
            sizeBytes: 70_000_000
        ),
        ASRModel(
            id: "whisperkit-base.en",
            name: "Whisper Base EN (WhisperKit)",
            url: URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v2/whisperkit-base.en.tar.gz")!,
            archiveType: .tarGz,
            framework: .whisperKitCoreML,
            sizeBytes: 134_000_000
        ),
    ]

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
