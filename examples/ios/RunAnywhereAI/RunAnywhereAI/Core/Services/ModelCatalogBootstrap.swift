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
        await registerLLM(
            id: "llama-3.2-3b-instruct-q4_k_m",
            name: "Llama 3.2 3B Instruct Q4_K_M (Tool Calling)",
            url: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 2_000_000_000
        )
        logger.info("LLM models registered")

        // --- MLX models (Apple Metal, Hugging Face repo-folder bundles) -------
        await registerLLM(
            id: "mlx-qwen3-0.6b-4bit",
            name: "MLX Qwen3 0.6B 4bit",
            url: "https://huggingface.co/mlx-community/Qwen3-0.6B-4bit",
            framework: .mlx,
            memoryRequirement: 650_000_000,
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
        await registerLLM(
            id: "mlx-gemma-4-e2b-it-4bit",
            name: "MLX Gemma 4 E2B IT 4bit (Experimental)",
            url: "https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit",
            framework: .mlx,
            modality: .multimodal,
            memoryRequirement: 2_200_000_000
        )
        await registerLLM(
            id: "mlx-gemma-4-e4b-it-4bit",
            name: "MLX Gemma 4 E4B IT 4bit (Experimental)",
            url: "https://huggingface.co/mlx-community/gemma-4-e4b-it-4bit",
            framework: .mlx,
            modality: .multimodal,
            memoryRequirement: 4_000_000_000
        )
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
        logger.info("MLX models registered")

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

        // --- STT models (MLX, Apple Metal) -----------------------------------
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

        // --- TTS models (MLX, Apple Metal) -----------------------------------
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
        await registerLoraAdapters()
        logger.info("LoRA adapters registered")

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
