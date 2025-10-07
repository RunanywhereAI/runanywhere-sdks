package com.runanywhere.ai.models.data

enum class ModelFormat(val extension: String, val displayName: String) {
    GGUF(".gguf", "GGUF"),
    ONNX(".onnx", "ONNX"),
    COREML(".mlmodel", "Core ML"),
    TFLITE(".tflite", "TensorFlow Lite"),
    PYTORCH(".pt", "PyTorch"),
    SAFETENSORS(".safetensors", "SafeTensors"),
    UNKNOWN("", "Unknown")
}
