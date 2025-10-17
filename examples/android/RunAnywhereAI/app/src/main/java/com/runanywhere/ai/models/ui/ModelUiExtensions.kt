package com.runanywhere.ai.models.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.ui.graphics.vector.ImageVector
import com.runanywhere.sdk.models.enums.LLMFramework
import com.runanywhere.sdk.models.enums.ModelFormat

/**
 * Extension properties and functions for UI display of SDK enums
 */

// Framework extensions
fun LLMFramework.getIcon(): ImageVector {
    return when (this) {
        LLMFramework.LLAMA_CPP, LLMFramework.LLAMACPP -> Icons.Default.Computer
        LLMFramework.ONNX -> Icons.Default.Memory
        LLMFramework.TENSOR_FLOW_LITE -> Icons.Default.Android
        LLMFramework.FOUNDATION_MODELS -> Icons.Default.PhoneAndroid
        LLMFramework.WHISPER_CPP -> Icons.Default.Mic
        LLMFramework.WHISPER_KIT -> Icons.Default.Mic
        LLMFramework.OPEN_AI_WHISPER -> Icons.Default.Mic
        LLMFramework.CORE_ML -> Icons.Default.PhoneAndroid
        LLMFramework.MLX -> Icons.Default.Memory
        LLMFramework.MLC -> Icons.Default.Memory
        LLMFramework.SWIFT_TRANSFORMERS -> Icons.Default.Computer
        LLMFramework.EXECU_TORCH -> Icons.Default.Computer
        LLMFramework.PICO_LLM -> Icons.Default.Computer
        LLMFramework.MEDIA_PIPE -> Icons.Default.Extension
    }
}

val LLMFramework.description: String
    get() = when (this) {
        LLMFramework.LLAMA_CPP, LLMFramework.LLAMACPP -> "High-performance C++ inference"
        LLMFramework.ONNX -> "Cross-platform ML inference"
        LLMFramework.TENSOR_FLOW_LITE -> "Mobile-optimized ML framework"
        LLMFramework.FOUNDATION_MODELS -> "Built-in system models"
        LLMFramework.WHISPER_CPP -> "Speech recognition (Whisper.cpp)"
        LLMFramework.WHISPER_KIT -> "Speech recognition (WhisperKit)"
        LLMFramework.OPEN_AI_WHISPER -> "OpenAI Whisper models"
        LLMFramework.CORE_ML -> "Apple's Core ML framework"
        LLMFramework.MLX -> "Apple MLX framework"
        LLMFramework.MLC -> "Machine Learning Compilation"
        LLMFramework.SWIFT_TRANSFORMERS -> "Swift Transformers"
        LLMFramework.EXECU_TORCH -> "PyTorch mobile runtime"
        LLMFramework.PICO_LLM -> "Lightweight LLM framework"
        LLMFramework.MEDIA_PIPE -> "Google MediaPipe"
    }

// ModelFormat extensions
val ModelFormat.extension: String
    get() = when (this) {
        ModelFormat.GGUF -> ".gguf"
        ModelFormat.GGML -> ".ggml"
        ModelFormat.ONNX -> ".onnx"
        ModelFormat.ORT -> ".ort"
        ModelFormat.MLMODEL -> ".mlmodel"
        ModelFormat.MLPACKAGE -> ".mlpackage"
        ModelFormat.TFLITE -> ".tflite"
        ModelFormat.SAFETENSORS -> ".safetensors"
        ModelFormat.MLX -> ".mlx"
        ModelFormat.PTE -> ".pte"
        ModelFormat.BIN -> ".bin"
        ModelFormat.WEIGHTS -> ".weights"
        ModelFormat.CHECKPOINT -> ".ckpt"
        ModelFormat.UNKNOWN -> ""
    }

val ModelFormat.displayName: String
    get() = when (this) {
        ModelFormat.GGUF -> "GGUF"
        ModelFormat.GGML -> "GGML"
        ModelFormat.ONNX -> "ONNX"
        ModelFormat.ORT -> "ONNX Runtime"
        ModelFormat.MLMODEL -> "Core ML"
        ModelFormat.MLPACKAGE -> "Core ML Package"
        ModelFormat.TFLITE -> "TensorFlow Lite"
        ModelFormat.SAFETENSORS -> "SafeTensors"
        ModelFormat.MLX -> "MLX"
        ModelFormat.PTE -> "PyTorch"
        ModelFormat.BIN -> "Binary"
        ModelFormat.WEIGHTS -> "Weights"
        ModelFormat.CHECKPOINT -> "Checkpoint"
        ModelFormat.UNKNOWN -> "Unknown"
    }
