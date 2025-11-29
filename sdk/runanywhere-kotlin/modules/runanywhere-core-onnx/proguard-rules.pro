# RunAnywhere Core ONNX Module - ProGuard Rules

# Keep JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep the JNI bridge class and all its methods
-keep class com.runanywhere.sdk.core.bridge.RunAnywhereBridge {
    *;
}

# Keep result types used by JNI
-keep class com.runanywhere.sdk.core.bridge.TTSSynthesisResult {
    *;
}
-keep class com.runanywhere.sdk.core.bridge.VADResult {
    *;
}

# Keep enums
-keep enum com.runanywhere.sdk.core.bridge.Capability {
    *;
}
-keep enum com.runanywhere.sdk.core.bridge.DeviceType {
    *;
}
-keep enum com.runanywhere.sdk.core.bridge.ResultCode {
    *;
}

# Keep public service API
-keep class com.runanywhere.sdk.core.bridge.ONNXCoreService {
    public *;
}
