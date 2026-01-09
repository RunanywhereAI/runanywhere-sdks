# RunAnywhere ONNX SDK ProGuard Rules
# Keep native method signatures
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep ONNX plugin classes
-keep class ai.runanywhere.sdk.onnx.** { *; }

# Keep ONNX Runtime classes
-keep class ai.onnxruntime.** { *; }
