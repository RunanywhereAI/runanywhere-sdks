package com.runanywhere.runanywhereai.config

import com.runanywhere.sdk.public.models.ModelRegistration
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.FrameworkModality
import com.runanywhere.sdk.models.enums.ModelFormat


/**
 * Central registry for all model definitions used in the application.
 * Separates model data from initialization logic for better maintainability.
 *
 * Matches iOS pattern of centralizing model configurations.
 */
object AppModelRegistry {

    /**
     * Get all LlamaCPP models (TEXT_TO_TEXT modality).
     * Matches iOS: RunAnywhere.registerFramework(LlamaCPPCoreAdapter(), models: [...])
     * These models provide native C++ llama.cpp performance.
     */
    fun getLlamaCppModels(): List<ModelRegistration> = listOf(
        // Qwen 2.5 0.5B Instruct Q6_K - Small but capable (~600MB)
        // Matches iOS: qwen-2.5-0.5b-instruct-q6-k
        ModelRegistration(
            id = "qwen-2.5-0.5b-instruct-q6-k",
            name = "Qwen 2.5 0.5B Instruct Q6_K",
            url = "https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
            framework = LLMFramework.LLAMA_CPP,
            modality = FrameworkModality.TEXT_TO_TEXT,
            format = ModelFormat.GGUF,
            memoryRequirement = 600_000_000L
        ),
        // LiquidAI LFM2 350M Q4_K_M - Smallest and fastest (~250MB)
        // Matches iOS: lfm2-350m-q4-k-m
        ModelRegistration(
            id = "lfm2-350m-q4-k-m",
            name = "LiquidAI LFM2 350M Q4_K_M",
            url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
            framework = LLMFramework.LLAMA_CPP,
            modality = FrameworkModality.TEXT_TO_TEXT,
            format = ModelFormat.GGUF,
            memoryRequirement = 250_000_000L
        ),
        // LiquidAI LFM2 350M Q8_0 - Highest quality small model (~400MB)
        // Matches iOS: lfm2-350m-q8-0
        ModelRegistration(
            id = "lfm2-350m-q8-0",
            name = "LiquidAI LFM2 350M Q8_0",
            url = "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
            framework = LLMFramework.LLAMA_CPP,
            modality = FrameworkModality.TEXT_TO_TEXT,
            format = ModelFormat.GGUF,
            memoryRequirement = 400_000_000L
        )
    )

    /**
     * Get all ONNX models (VOICE_TO_TEXT and TEXT_TO_VOICE modalities).
     * Includes Sherpa ONNX Whisper for STT and Piper for TTS.
     *
     * Note: WhisperKit is iOS-only (CoreML), ONNX Sherpa serves the same purpose on Android.
     */
    fun getOnnxModels(): List<ModelRegistration> = listOf(
        // STT Models (VOICE_TO_TEXT modality)
        // NOTE: tar.bz2 extraction is supported on Android via Commons Compress
        // Sherpa ONNX Whisper Tiny English (~75MB)
        // Matches iOS: sherpa-whisper-tiny-onnx
        ModelRegistration(
            id = "sherpa-whisper-tiny-onnx",
            name = "Sherpa Whisper Tiny (ONNX)",
            url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.en.tar.bz2",
            framework = LLMFramework.ONNX,
            modality = FrameworkModality.VOICE_TO_TEXT,
            format = ModelFormat.ONNX,
            memoryRequirement = 75_000_000L
        ),
        // Sherpa ONNX Whisper Small (~250MB)
        // Matches iOS: sherpa-whisper-small-onnx
        ModelRegistration(
            id = "sherpa-whisper-small-onnx",
            name = "Sherpa Whisper Small (ONNX)",
            url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-small.en.tar.bz2",
            framework = LLMFramework.ONNX,
            modality = FrameworkModality.VOICE_TO_TEXT,
            format = ModelFormat.ONNX,
            memoryRequirement = 250_000_000L
        ),
        // TTS Models (TEXT_TO_VOICE modality)
        // Using sherpa-onnx tar.bz2 packages (includes model, tokens, and espeak-ng-data)
        // Piper TTS - US English Lessac Medium (~65MB)
        // Matches iOS: piper-en-us-lessac-medium
        ModelRegistration(
            id = "piper-en-us-lessac-medium",
            name = "Piper TTS (US English - Medium)",
            url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_US-lessac-medium.tar.bz2",
            framework = LLMFramework.ONNX,
            modality = FrameworkModality.TEXT_TO_VOICE,
            format = ModelFormat.ONNX,
            memoryRequirement = 65_000_000L
        ),
        // Piper TTS - British English Alba Medium (~65MB)
        // Matches iOS: piper-en-gb-alba-medium
        ModelRegistration(
            id = "piper-en-gb-alba-medium",
            name = "Piper TTS (British English)",
            url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-en_GB-alba-medium.tar.bz2",
            framework = LLMFramework.ONNX,
            modality = FrameworkModality.TEXT_TO_VOICE,
            format = ModelFormat.ONNX,
            memoryRequirement = 65_000_000L
        )
    )
}
