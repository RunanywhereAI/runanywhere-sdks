//
//  ModelCatalogBootstrap.swift
//  RunAnywhereAI
//

import Foundation
import RunAnywhere
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
    @TaskLocal private static var mlxCatalogEnabled = false

    static func registerAll(mlxRegistered: Bool) async {
        await $mlxCatalogEnabled.withValue(mlxRegistered) {
            await registerCatalog()
        }
    }

    private static func registerCatalog() async {
        logger.info("Registering modules with their models...")

        #if canImport(LlamaCPPRuntime)
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
            memoryRequirement: 600_000_000,
            // Base model of the seeded abliterated adapter
            // (qwen2.5-0.5b-abliterated-lora-f16.gguf) — matches Android.
            supportsLora: true
        )
        await registerLLM(
            id: "qwen2.5-1.5b-instruct-q4_k_m",
            name: "Qwen 2.5 1.5B Instruct Q4_K_M",
            url: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
            framework: .llamaCpp,
            memoryRequirement: 2_500_000_000
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
            id: "lfm2.5-1.2b-instruct-q4_k_m",
            name: "LiquidAI LFM2.5 1.2B Instruct Q4_K_M",
            url: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/main/LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 900_000_000
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
            id: "qwen3.5-0.8b-q4_k_m",
            name: "Qwen3.5 0.8B Q4_K_M",
            url: "https://huggingface.co/bartowski/Qwen_Qwen3.5-0.8B-GGUF/resolve/main/Qwen3.5-0.8B-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 620_000_000,
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
        // PrismML Bonsai family at 1.125-bit (custom Q1_0 quant, qwen3_5
        // GatedDeltaNet arch). Requires the PrismML llama.cpp fork pinned in
        // sdk/runanywhere-commons/VERSIONS — stock upstream cannot load it.
        await registerLLM(
            id: "bonsai-1.7b-q1_0",
            name: "Bonsai-1.7B 1-bit Q1_0 (CPU)",
            url: "https://huggingface.co/prism-ml/Bonsai-1.7B-gguf/resolve/main/Bonsai-1.7B-Q1_0.gguf",
            framework: .llamaCpp,
            memoryRequirement: 248_302_272,
            supportsThinking: true
        )
        await registerLLM(
            id: "bonsai-4b-q1_0",
            name: "Bonsai-4B 1-bit Q1_0 (CPU)",
            url: "https://huggingface.co/prism-ml/Bonsai-4B-gguf/resolve/main/Bonsai-4B-Q1_0.gguf",
            framework: .llamaCpp,
            memoryRequirement: 572_270_624,
            supportsThinking: true
        )
        await registerLLM(
            id: "bonsai-8b-q1_0",
            name: "Bonsai-8B 1-bit Q1_0 (CPU)",
            url: "https://huggingface.co/prism-ml/Bonsai-8B-gguf/resolve/main/Bonsai-8B-Q1_0.gguf",
            framework: .llamaCpp,
            memoryRequirement: 1_158_654_496,
            supportsThinking: true
        )
        await registerLLM(
            id: "bonsai-27b-q1_0",
            name: "Bonsai-27B 1-bit Q1_0 (CPU)",
            url: "https://huggingface.co/prism-ml/Bonsai-27B-gguf/resolve/main/Bonsai-27B-Q1_0.gguf",
            framework: .llamaCpp,
            memoryRequirement: 3_803_452_480,
            supportsThinking: true
        )
        // NOTE: Ternary-Bonsai GGUF (Q2_0/PQ2_0) is intentionally NOT registered.
        // Verified via rcli this session: the pinned PrismML llama.cpp fork
        // (prism-b9591-62061f9) rejects it — "invalid ggml type 142" — it only
        // added Q1_0 (plain Bonsai) support, not Ternary-Bonsai's tensor encoding.
        // Re-enable once the fork adds it. Ternary-Bonsai MLX (below) works fine.
        await registerLLM(
            id: "llama-3.2-3b-instruct-q4_k_m",
            name: "Llama 3.2 3B Instruct Q4_K_M (Tool Calling)",
            url: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 2_000_000_000
        )
        logger.info("LLM models registered")
        #endif

        // --- MLX models (Apple Metal, Hugging Face repo-folder bundles) -------
        await registerLLM(
            id: "mlx-qwen3-0.6b-4bit",
            name: "MLX Qwen3 0.6B 4bit",
            url: "https://huggingface.co/mlx-community/Qwen3-0.6B-4bit",
            framework: .mlx,
            memoryRequirement: 650_000_000,
            supportsThinking: true
        )
        // PrismML Bonsai family 1-bit MLX. Needs the PrismML mlx-swift fork
        // (bits=1 quantization support) pinned in Package.swift/Package.resolved.
        await registerLLM(
            id: "mlx-bonsai-1.7b-1bit",
            name: "MLX Bonsai-1.7B 1-bit",
            url: "https://huggingface.co/prism-ml/Bonsai-1.7B-mlx-1bit",
            framework: .mlx,
            memoryRequirement: 269_060_904,
            supportsThinking: true
        )
        await registerLLM(
            id: "mlx-bonsai-4b-1bit",
            name: "MLX Bonsai-4B 1-bit",
            url: "https://huggingface.co/prism-ml/Bonsai-4B-mlx-1bit",
            framework: .mlx,
            memoryRequirement: 628_865_840,
            supportsThinking: true
        )
        await registerLLM(
            id: "mlx-bonsai-8b-1bit",
            name: "MLX Bonsai-8B 1-bit",
            url: "https://huggingface.co/prism-ml/Bonsai-8B-mlx-1bit",
            framework: .mlx,
            memoryRequirement: 1_280_131_424,
            supportsThinking: true
        )
        // PrismML Bonsai-27B 1-bit MLX (~5.1 GB). Experimental — needs
        // mlx-swift-lm support for qwen3_5 / 1-bit Bonsai.
        await registerLLM(
            id: "mlx-bonsai-27b-1bit",
            name: "MLX Bonsai-27B 1-bit",
            url: "https://huggingface.co/prism-ml/Bonsai-27B-mlx-1bit",
            framework: .mlx,
            memoryRequirement: 5_129_115_752,
            supportsThinking: true
        )
        // PrismML Ternary-Bonsai family at ternary/2-bit MLX. Same PrismML
        // mlx-swift fork (bits=2 quantization support already covered by
        // upstream MLX 0.31.6 — no additional patch needed beyond bits=1).
        await registerLLM(
            id: "mlx-ternary-bonsai-1.7b-2bit",
            name: "MLX Ternary-Bonsai-1.7B 2-bit",
            url: "https://huggingface.co/prism-ml/Ternary-Bonsai-1.7B-mlx-2bit",
            framework: .mlx,
            memoryRequirement: 484_049_216,
            supportsThinking: true
        )
        await registerLLM(
            id: "mlx-ternary-bonsai-4b-2bit",
            name: "MLX Ternary-Bonsai-4B 2-bit",
            url: "https://huggingface.co/prism-ml/Ternary-Bonsai-4B-mlx-2bit",
            framework: .mlx,
            memoryRequirement: 1_131_565_944,
            supportsThinking: true
        )
        await registerLLM(
            id: "mlx-ternary-bonsai-8b-2bit",
            name: "MLX Ternary-Bonsai-8B 2-bit",
            url: "https://huggingface.co/prism-ml/Ternary-Bonsai-8B-mlx-2bit",
            framework: .mlx,
            memoryRequirement: 2_303_661_704,
            supportsThinking: true
        )
        await registerLLM(
            id: "mlx-ternary-bonsai-27b-2bit",
            name: "MLX Ternary-Bonsai-27B 2-bit",
            url: "https://huggingface.co/prism-ml/Ternary-Bonsai-27B-mlx-2bit",
            framework: .mlx,
            memoryRequirement: 8_490_785_104,
            supportsThinking: true
        )
        await registerLLM(
            id: "mlx-qwen3.5-0.8b-mlx-4bit",
            name: "MLX Qwen3.5 0.8B 4bit",
            url: "https://huggingface.co/mlx-community/Qwen3.5-0.8B-MLX-4bit",
            framework: .mlx,
            memoryRequirement: 622_000_000,
            supportsThinking: true
        )
        await registerLLM(
            id: "mlx-llama-3.2-1b-instruct-4bit",
            name: "MLX Llama 3.2 1B Instruct 4bit",
            url: "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit",
            framework: .mlx,
            memoryRequirement: 900_000_000
        )
        await registerLLM(
            id: "mlx-lfm2-350m",
            name: "MLX LFM2 350M",
            url: "https://huggingface.co/mlx-community/LFM2-350M-MLX",
            framework: .mlx,
            memoryRequirement: 709_000_000
        )
        await registerLLM(
            id: "mlx-lfm2.5-1.2b-instruct-4bit",
            name: "MLX LFM2.5 1.2B Instruct 4bit",
            url: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-MLX-4bit",
            framework: .mlx,
            memoryRequirement: 628_000_000
        )
        await registerLLM(
            id: "mlx-qwen3-4b-4bit",
            name: "MLX Qwen3 4B 4bit",
            url: "https://huggingface.co/mlx-community/Qwen3-4B-4bit",
            framework: .mlx,
            memoryRequirement: 2_400_000_000,
            supportsThinking: true
        )
        // NOTE: The MLX Gemma 4 (E2B/E4B) checkpoints are intentionally NOT
        // registered. Their attention layers use an asymmetric QK-norm (some
        // layers ship `self_attn.q_norm` without a matching `self_attn.k_norm`),
        // but mlx-swift-lm 3.31.4's `Gemma4TextAttention` unconditionally loads
        // `self_attn.k_norm.weight` and aborts with `keyNotFound` on the first
        // such layer — so they download fully and then fail to load. Re-enable
        // once mlx-swift-lm makes per-layer k_norm optional. The GGUF (llama.cpp)
        // Gemma 4 variants below load fine and remain available.
        await registerLLM(
            id: "mlx-qwen2-vl-2b-instruct-4bit",
            name: "MLX Qwen2-VL 2B Instruct 4bit",
            url: "https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit",
            framework: .mlx,
            modality: .multimodal,
            memoryRequirement: 2_200_000_000
        )
        await registerLLM(
            id: "mlx-qwen3-vl-4b-instruct-4bit",
            name: "MLX Qwen3-VL 4B Instruct 4bit",
            url: "https://huggingface.co/lmstudio-community/Qwen3-VL-4B-Instruct-MLX-4bit",
            framework: .mlx,
            modality: .multimodal,
            memoryRequirement: 4_000_000_000
        )
        await registerLLM(
            id: "mlx-fara1.5-4b",
            name: "MLX Fara1.5 4B Computer-Use Agent 4bit",
            url: "https://huggingface.co/runanywhere/Fara1.5-4B-mlx-4bit",
            framework: .mlx,
            modality: .multimodal,
            memoryRequirement: 4_000_000_000
        )
        if mlxCatalogEnabled {
            logger.info("MLX models registered")
        } else {
            logger.info("Skipping MLX models because this target cannot execute the runtime")
        }

        #if canImport(LlamaCPPRuntime)
        // --- VLM models (multi-modal, multi-file) -----------------------------
        await registerMultiFile(
            id: "smolvlm2-256m-video-instruct-q8_0",
            name: "SmolVLM2 256M Video Instruct Q8_0",
            files: [
                ("https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/SmolVLM2-256M-Video-Instruct-Q8_0.gguf",
                 "SmolVLM2-256M-Video-Instruct-Q8_0.gguf"),
                ("https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf",
                 "mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf")
            ],
            framework: .llamaCpp,
            modality: .multimodal,
            memoryRequirement: 450_000_000
        )
        await registerMultiFile(
            id: "smolvlm2-500m-video-instruct-q8_0",
            name: "SmolVLM2 500M Video Instruct Q8_0",
            files: [
                ("https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/SmolVLM2-500M-Video-Instruct-Q8_0.gguf",
                 "SmolVLM2-500M-Video-Instruct-Q8_0.gguf"),
                ("https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf",
                 "mmproj-SmolVLM2-500M-Video-Instruct-Q8_0.gguf")
            ],
            framework: .llamaCpp,
            modality: .multimodal,
            memoryRequirement: 800_000_000
        )
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
            id: "qwen2.5-vl-3b-instruct-q4_k_m",
            name: "Qwen2.5-VL 3B Instruct Q4_K_M",
            files: [
                ("https://huggingface.co/ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/resolve/main/Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf",
                 "Qwen2.5-VL-3B-Instruct-Q4_K_M.gguf"),
                ("https://huggingface.co/ggml-org/Qwen2.5-VL-3B-Instruct-GGUF/resolve/main/mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf",
                 "mmproj-Qwen2.5-VL-3B-Instruct-Q8_0.gguf")
            ],
            framework: .llamaCpp,
            modality: .multimodal,
            memoryRequirement: 2_800_000_000
        )
        await registerMultiFile(
            id: "gemma-4-e2b-it-q8_0",
            name: "Gemma 4 E2B IT Q8_0 (Experimental)",
            files: [
                ("https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it-Q8_0.gguf",
                 "gemma-4-E2B-it-Q8_0.gguf"),
                ("https://huggingface.co/ggml-org/gemma-4-E2B-it-GGUF/resolve/main/mmproj-gemma-4-E2B-it-Q8_0.gguf",
                 "mmproj-gemma-4-E2B-it-Q8_0.gguf")
            ],
            framework: .llamaCpp,
            modality: .multimodal,
            memoryRequirement: 3_000_000_000
        )
        await registerMultiFile(
            id: "gemma-4-e4b-it-q4_k_m",
            name: "Gemma 4 E4B IT Q4_K_M (Experimental)",
            files: [
                ("https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/gemma-4-E4B-it-Q4_K_M.gguf",
                 "gemma-4-E4B-it-Q4_K_M.gguf"),
                ("https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/main/mmproj-gemma-4-E4B-it-Q8_0.gguf",
                 "mmproj-gemma-4-E4B-it-Q8_0.gguf")
            ],
            framework: .llamaCpp,
            modality: .multimodal,
            memoryRequirement: 5_500_000_000
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
        #endif

        #if canImport(ONNXRuntime)
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
        #endif

        // --- STT models (MLX, Apple Metal) -----------------------------------
        // Keep the iOS example on the same MLX speech bundles that are proven
        // to load in the local DevTools CLI. Several repo-style Whisper
        // bundles previously registered here fail against the current
        // MLXAudioSTT loader at runtime, so we intentionally do not surface
        // them in the example catalog.
        await registerMultiFile(
            id: "mlx-qwen3-asr-0.6b-8bit",
            name: "MLX Qwen3-ASR 0.6B 8bit",
            files: [
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/chat_template.json",
                    filename: "chat_template.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/config.json",
                    filename: "config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/generation_config.json",
                    filename: "generation_config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/merges.txt",
                    filename: "merges.txt"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/model.safetensors",
                    filename: "model.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/model.safetensors.index.json",
                    filename: "model.safetensors.index.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/preprocessor_config.json",
                    filename: "preprocessor_config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/tokenizer_config.json",
                    filename: "tokenizer_config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/vocab.json",
                    filename: "vocab.json"
                )
            ],
            framework: .mlx,
            modality: .speechRecognition,
            memoryRequirement: 1_010_773_761
        )
        await registerMultiFile(
            id: "mlx-glm-asr-nano-2512-4bit",
            name: "MLX GLM-ASR Nano 2512 4bit",
            files: [
                .init(
                    url: "https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/config.json",
                    filename: "config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/configuration_glmasr.py",
                    filename: "configuration_glmasr.py",
                    isRequired: false
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/inference.py",
                    filename: "inference.py",
                    isRequired: false
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/model.safetensors",
                    filename: "model.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/model.safetensors.index.json",
                    filename: "model.safetensors.index.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/modeling_audio.py",
                    filename: "modeling_audio.py",
                    isRequired: false
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/modeling_glmasr.py",
                    filename: "modeling_glmasr.py",
                    isRequired: false
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/tokenizer.json",
                    filename: "tokenizer.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/tokenizer_config.json",
                    filename: "tokenizer_config.json"
                )
            ],
            framework: .mlx,
            modality: .speechRecognition,
            memoryRequirement: 1_288_437_789
        )

        #if canImport(ONNXRuntime)
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
        #endif

        // --- TTS models (MLX, Apple Metal) -----------------------------------
        // Match the MLX TTS bundles we verified locally through the DevTools
        // CLI on macOS. Keep only models that completed a real load/synthesis
        // pass with the current MLXAudioTTS runtime.
        await registerMultiFile(
            id: "mlx-soprano-1.1-80m-5bit",
            name: "MLX Soprano 1.1 80M 5bit",
            files: [
                .init(
                    url: "https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/config.json",
                    filename: "config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/generation_config.json",
                    filename: "generation_config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/model.safetensors",
                    filename: "model.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/model.safetensors.index.json",
                    filename: "model.safetensors.index.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/special_tokens_map.json",
                    filename: "special_tokens_map.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/tokenizer.json",
                    filename: "tokenizer.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/tokenizer_config.json",
                    filename: "tokenizer_config.json"
                )
            ],
            framework: .mlx,
            modality: .speechSynthesis,
            memoryRequirement: 82_220_814
        )
        await registerLLM(
            id: "mlx-kokoro-82m-6bit",
            name: "MLX Kokoro 82M 6bit",
            url: "https://huggingface.co/mlx-community/Kokoro-82M-6bit",
            framework: .mlx,
            modality: .speechSynthesis,
            memoryRequirement: 309_640_166
        )
        await registerMultiFile(
            id: "mlx-pocket-tts",
            name: "MLX Pocket TTS",
            files: [
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/config.json",
                    filename: "config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/model.safetensors",
                    filename: "model.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/special_tokens_map.json",
                    filename: "special_tokens_map.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/tokenizer.json",
                    filename: "tokenizer.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/tokenizer_config.json",
                    filename: "tokenizer_config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/embeddings/alba.safetensors",
                    filename: "embeddings/alba.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/embeddings/azelma.safetensors",
                    filename: "embeddings/azelma.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/embeddings/cosette.safetensors",
                    filename: "embeddings/cosette.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/embeddings/eponine.safetensors",
                    filename: "embeddings/eponine.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/embeddings/fantine.safetensors",
                    filename: "embeddings/fantine.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/embeddings/javert.safetensors",
                    filename: "embeddings/javert.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/embeddings/jean.safetensors",
                    filename: "embeddings/jean.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/pocket-tts/resolve/main/embeddings/marius.safetensors",
                    filename: "embeddings/marius.safetensors"
                )
            ],
            framework: .mlx,
            modality: .speechSynthesis,
            memoryRequirement: 420_000_000
        )
        await registerMultiFile(
            id: "mlx-kitten-tts-nano-0.8-5bit",
            name: "MLX Kitten TTS Nano 0.8 5bit",
            files: [
                .init(
                    url: "https://huggingface.co/mlx-community/kitten-tts-nano-0.8-5bit/resolve/main/config.json",
                    filename: "config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/kitten-tts-nano-0.8-5bit/resolve/main/model.safetensors",
                    filename: "model.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/kitten-tts-nano-0.8-5bit/resolve/main/model.safetensors.index.json",
                    filename: "model.safetensors.index.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/kitten-tts-nano-0.8/resolve/1a06939883365626208c9cd832133f36fbc6fe82/voices.safetensors",
                    filename: "voices.safetensors"
                )
            ],
            framework: .mlx,
            modality: .speechSynthesis,
            memoryRequirement: 120_000_000
        )
        await registerLLM(
            id: "mlx-qwen3-tts-12hz-0.6b-base-4bit",
            name: "MLX Qwen3-TTS 12Hz 0.6B Base 4bit",
            url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-4bit",
            framework: .mlx,
            modality: .speechSynthesis,
            memoryRequirement: 1_711_328_624
        )
        await registerMultiFile(
            id: "mlx-qwen3-tts-12hz-0.6b-base-8bit",
            name: "MLX Qwen3-TTS 12Hz 0.6B Base 8bit",
            files: [
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/config.json",
                    filename: "config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/generation_config.json",
                    filename: "generation_config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/merges.txt",
                    filename: "merges.txt"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/model.safetensors",
                    filename: "model.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/model.safetensors.index.json",
                    filename: "model.safetensors.index.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/preprocessor_config.json",
                    filename: "preprocessor_config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/speech_tokenizer/config.json",
                    filename: "speech_tokenizer/config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/speech_tokenizer/configuration.json",
                    filename: "speech_tokenizer/configuration.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/speech_tokenizer/model.safetensors",
                    filename: "speech_tokenizer/model.safetensors"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/speech_tokenizer/preprocessor_config.json",
                    filename: "speech_tokenizer/preprocessor_config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/tokenizer_config.json",
                    filename: "tokenizer_config.json"
                ),
                .init(
                    url: "https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/vocab.json",
                    filename: "vocab.json"
                )
            ],
            framework: .mlx,
            modality: .speechSynthesis,
            memoryRequirement: 1_991_299_138
        )

        #if canImport(ONNXRuntime)
        // --- VAD (Silero, ONNX) -----------------------------------------------
        await registerLLM(
            id: "silero-vad",
            name: "Silero VAD",
            url: "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx",
            framework: .onnx,
            modality: .voiceActivityDetection,
            // Actual silero_vad.onnx artifact size (verified Content-Length).
            // memoryRequirement doubles as downloadSizeBytes (see
            // RunAnywhere+Storage.swift), which feeds the post-finalize download
            // size guard. An over-stated 5 MB tripped the guard on a
            // valid ~2.3 MB download.
            memoryRequirement: 2_327_524
        )
        logger.info("Sherpa STT/TTS + Silero VAD models registered")
        #endif

        #if canImport(ONNXRuntime)
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
        #endif
        await registerLLM(
            id: "mlx-qwen3-embedding-0.6b-4bit-dwq",
            name: "MLX Qwen3 Embedding 0.6B 4bit DWQ",
            url: "https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ",
            framework: .mlx,
            modality: .embedding,
            memoryRequirement: 350_000_000
        )
        logger.info("Embedding models registered")

        // QHexRT/HNPU bundles are Qualcomm-Android-only and are intentionally
        // not registered on Apple platforms.

        // --- LoRA adapters ------------------------------------------------------
        // Mirrors Android `ModelBootstrap.seedLora` / `ModelCatalog.loraAdapters`.
        #if canImport(LlamaCPPRuntime)
        await registerLoraAdapters()
        logger.info("LoRA adapters registered")
        #endif

        // Diffusion (CoreML) backend is deferred scope for
        // Swift v1. Their model catalog entries are intentionally omitted.

        logger.info("All modules and models registered")
    }

    /// Seed the curated LoRA adapter catalog. `registerArtifact` registers the
    /// catalog entry plus its downloadable artifact record (no bytes fetched);
    /// safe to re-run on every cold launch.
    private static func registerLoraAdapters() async {
        var adapter = RALoraAdapterCatalogEntry()
        adapter.id = "abliterated-lora"
        adapter.name = "Abliterated LoRA (F16)"
        adapter.description_p = "Removes refusal behavior — model answers directly without disclaimers"
        adapter.url = "https://huggingface.co/Void2377/qwen-lora-gguf/resolve/main/qwen2.5-0.5b-abliterated-lora-f16.gguf"
        adapter.filename = "qwen2.5-0.5b-abliterated-lora-f16.gguf"
        adapter.compatibleModels = ["qwen2.5-0.5b-instruct-q6_k"]
        adapter.sizeBytes = 17_620_224
        adapter.defaultScale = 1.0

        do {
            _ = try await RunAnywhere.lora.registerArtifact(adapter)
        } catch {
            logger.warning(
                "Failed to register LoRA adapter: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Registration helpers

    private struct CatalogModelFile {
        let url: String
        let filename: String
        let isRequired: Bool

        init(url: String, filename: String, isRequired: Bool = true) {
            self.url = url
            self.filename = filename
            self.isRequired = isRequired
        }
    }

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
        guard framework != .mlx || mlxCatalogEnabled else { return }
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
        guard framework != .mlx || mlxCatalogEnabled else { return }
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
        await registerMultiFile(
            id: id,
            name: name,
            files: files.map { CatalogModelFile(url: $0.url, filename: $0.filename) },
            framework: framework,
            modality: modality,
            memoryRequirement: memoryRequirement
        )
    }

    private static func registerMultiFile(
        id: String,
        name: String,
        files: [CatalogModelFile],
        framework: InferenceFramework,
        modality: ModelCategory,
        memoryRequirement: Int64
    ) async {
        guard framework != .mlx || mlxCatalogEnabled else { return }
        let descriptors: [RAModelFileDescriptor] = files.compactMap { file in
            guard let fileURL = URL(string: file.url) else { return nil }
            var descriptor = RAModelFileDescriptor(url: fileURL, filename: file.filename, isRequired: file.isRequired)
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
