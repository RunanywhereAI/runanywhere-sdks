//
//  ModelCatalogBootstrap.swift
//  RunAnywhereAI
//

import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime
import os

// MARK: - Model Catalog Bootstrap
//
// Mirrors Android `ModelBootstrap.seedCuratedCatalog` and Flutter
// `_registerModulesAndModels()`. Uses the canonical `RunAnywhere.registerModel`
// async public API including multi-file and archive-with-structure overloads.
// Safe to re-run on every cold launch — commons merges runtime fields on
// re-registration (see `register_model_from_url.cpp` header).
enum ModelCatalogBootstrap {
    private static let logger = Logger(
        subsystem: "com.runanywhere.RunAnywhereAI",
        category: "ModelCatalogBootstrap"
    )

    static func registerAll() async {
        logger.info("Registering modules with their models...")

        // --- LLM models (LlamaCpp backend) ------------------------------------
        await registerLLM(
            id: "smollm2-360m-q8_0",
            name: "SmolLM2 360M Q8_0",
            url: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            framework: .llamaCpp,
            memoryRequirement: 386_404_416
        )
        await registerLLM(
            id: "llama-2-7b-chat-q4_k_m",
            name: "Llama 2 7B Chat Q4_K_M",
            url: "https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 4_000_000_000
        )
        await registerLLM(
            id: "mistral-7b-instruct-q4_k_m",
            name: "Mistral 7B Instruct Q4_K_M",
            url: "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 4_000_000_000
        )
        await registerLLM(
            id: "qwen2.5-0.5b-instruct-q6_k",
            name: "Qwen 2.5 0.5B Instruct Q6_K",
            url: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
            framework: .llamaCpp,
            memoryRequirement: 600_000_000
        )
        await registerLLM(
            id: "qwen2.5-1.5b-instruct-q4_k_m",
            name: "Qwen 2.5 1.5B Instruct Q4_K_M",
            url: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
            framework: .llamaCpp,
            memoryRequirement: 2_500_000_000,
            supportsLora: true
        )
        await registerLLM(
            id: "lfm2-350m-q4_k_m",
            name: "LiquidAI LFM2 350M Q4_K_M",
            url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 250_000_000
        )
        await registerLLM(
            id: "lfm2-350m-q8_0",
            name: "LiquidAI LFM2 350M Q8_0",
            url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
            framework: .llamaCpp,
            memoryRequirement: 400_000_000
        )
        await registerLLM(
            id: "lfm2-1.2b-tool-q4_k_m",
            name: "LiquidAI LFM2 1.2B Tool Q4_K_M",
            url: "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 800_000_000
        )
        await registerLLM(
            id: "lfm2-1.2b-tool-q8_0",
            name: "LiquidAI LFM2 1.2B Tool Q8_0",
            url: "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf",
            framework: .llamaCpp,
            memoryRequirement: 1_400_000_000
        )
        await registerLLM(
            id: "qwen3-0.6b-q4_k_m",
            name: "Qwen3 0.6B Q4_K_M",
            url: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 500_000_000,
            supportsThinking: true
        )
        await registerLLM(
            id: "qwen3-1.7b-q4_k_m",
            name: "Qwen3 1.7B Q4_K_M",
            url: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 1_200_000_000,
            supportsThinking: true
        )
        await registerLLM(
            id: "qwen3-4b-q4_k_m",
            name: "Qwen3 4B Q4_K_M",
            url: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 2_800_000_000,
            supportsThinking: true
        )
        logger.info("LLM models registered")

        // --- VLM models (multi-modal, multi-file) -----------------------------
        await registerArchive(
            id: "smolvlm-500m-instruct-q8_0",
            name: "SmolVLM 500M Instruct",
            url: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz",
            framework: .llamaCpp,
            modality: .multimodal,
            archive: .tarGz,
            structure: .directoryBased,
            memoryRequirement: 600_000_000
        )
        await registerMultiFile(
            id: "qwen2-vl-2b-instruct-q4_k_m",
            name: "Qwen2-VL 2B Instruct",
            files: [
                ("https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf",
                 "Qwen2-VL-2B-Instruct-Q4_K_M.gguf"),
                ("https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf",
                 "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf")
            ],
            framework: .llamaCpp,
            modality: .multimodal,
            memoryRequirement: 1_800_000_000
        )
        await registerMultiFile(
            id: "lfm2-vl-450m-q8_0",
            name: "LFM2-VL 450M",
            files: [
                ("https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf",
                 "LFM2-VL-450M-Q8_0.gguf"),
                ("https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf",
                 "mmproj-LFM2-VL-450M-Q8_0.gguf")
            ],
            framework: .llamaCpp,
            modality: .multimodal,
            memoryRequirement: 600_000_000
        )
        logger.info("VLM models registered")

        // --- STT models (Sherpa-ONNX) -----------------------------------------
        await registerArchive(
            id: "sherpa-onnx-whisper-tiny.en",
            name: "Sherpa Whisper Tiny (ONNX)",
            url: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
            framework: .sherpa,
            modality: .speechRecognition,
            archive: .tarGz,
            structure: .nestedDirectory,
            memoryRequirement: 75_000_000
        )

        // --- TTS models (Sherpa-ONNX Piper VITS) ------------------------------
        await registerArchive(
            id: "vits-piper-en_US-lessac-medium",
            name: "Piper TTS (US English - Medium)",
            url: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
            framework: .sherpa,
            modality: .speechSynthesis,
            archive: .tarGz,
            structure: .nestedDirectory,
            memoryRequirement: 65_000_000
        )
        await registerArchive(
            id: "vits-piper-en_GB-alba-medium",
            name: "Piper TTS (British English)",
            url: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz",
            framework: .sherpa,
            modality: .speechSynthesis,
            archive: .tarGz,
            structure: .nestedDirectory,
            memoryRequirement: 65_000_000
        )

        // --- VAD (Silero, ONNX) -----------------------------------------------
        await registerLLM(
            id: "silero-vad",
            name: "Silero VAD",
            url: "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx",
            framework: .onnx,
            modality: .voiceActivityDetection,
            memoryRequirement: 5_000_000
        )
        logger.info("Sherpa STT/TTS + Silero VAD models registered")

        // --- ONNX Embedding (RAG) ---------------------------------------------
        // MiniLM needs model.onnx + vocab.txt in the same folder for the C++
        // RAG pipeline to find its vocab next to the model.
        await registerMultiFile(
            id: "all-minilm-l6-v2",
            name: "All MiniLM L6 v2 (Embedding)",
            files: [
                ("https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx", "model.onnx"),
                ("https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt", "vocab.txt")
            ],
            framework: .onnx,
            modality: .embedding,
            memoryRequirement: 25_500_000
        )
        logger.info("ONNX Embedding models registered")

        // MetalRT, WhisperKit, and Diffusion (CoreML) backends are deferred
        // scope for Swift v1. Their model catalog entries are intentionally
        // omitted. See `thoughts/shared/plans/curious-greeting-panda.md`.

        logger.info("All modules and models registered")
    }

    // MARK: - Registration helpers

    private static func registerLLM(
        id: String,
        name: String,
        url: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        memoryRequirement: Int64,
        supportsThinking: Bool = false,
        supportsLora: Bool = false
    ) async {
        do {
            _ = try await RunAnywhere.registerModel(
                id: id,
                name: name,
                url: url,
                framework: framework,
                modality: modality,
                memoryRequirement: memoryRequirement,
                supportsThinking: supportsThinking,
                supportsLora: supportsLora
            )
        } catch {
            logger.warning("Failed to register model \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func registerArchive(
        id: String,
        name: String,
        url: String,
        framework: InferenceFramework,
        modality: ModelCategory,
        archive: ArchiveType,
        structure: ArchiveStructure,
        memoryRequirement: Int64
    ) async {
        do {
            _ = try await RunAnywhere.registerModel(
                archive: url,
                structure: structure,
                id: id,
                name: name,
                framework: framework,
                modality: modality,
                archiveType: archive,
                memoryRequirement: memoryRequirement
            )
        } catch {
            logger.warning("Failed to register archive model \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func registerMultiFile(
        id: String,
        name: String,
        files: [(url: String, filename: String)],
        framework: InferenceFramework,
        modality: ModelCategory,
        memoryRequirement: Int64
    ) async {
        let descriptors: [RAModelFileDescriptor] = files.compactMap { file in
            guard let fileURL = URL(string: file.url) else { return nil }
            var descriptor = RAModelFileDescriptor(url: fileURL, filename: file.filename, isRequired: true)
            descriptor.role = RunAnywhere.inferModelFileRole(filename: file.filename, modality: modality)
            return descriptor
        }
        guard descriptors.count == files.count else {
            logger.warning("Invalid multi-file URL list for model \(id, privacy: .public)")
            return
        }
        do {
            _ = try await RunAnywhere.registerModel(
                multiFile: descriptors,
                id: id,
                name: name,
                framework: framework,
                modality: modality,
                memoryRequirement: memoryRequirement
            )
        } catch {
            logger.warning("Failed to register multi-file model \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
