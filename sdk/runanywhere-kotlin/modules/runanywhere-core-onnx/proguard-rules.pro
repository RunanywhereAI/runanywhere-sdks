# RunAnywhere Core ONNX Module - ProGuard Rules

# Keep JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep the unified JNI bridge class and all its methods
-keep class com.runanywhere.sdk.native.bridge.RunAnywhereBridge {
    *;
}

# Keep result types used by JNI (correct package: native.bridge)
-keep class com.runanywhere.sdk.native.bridge.NativeTTSSynthesisResult {
    <init>(...);
    *;
}
-keep class com.runanywhere.sdk.native.bridge.NativeVADResult {
    <init>(...);
    *;
}
-keep class com.runanywhere.sdk.native.bridge.NativeBridgeException {
    *;
}
-keep class com.runanywhere.sdk.native.bridge.NativeResultCode {
    *;
}

# Keep all enums in native.bridge package
-keep enum com.runanywhere.sdk.native.bridge.** {
    *;
}

# Keep public service API
-keep class com.runanywhere.sdk.core.onnx.ONNXCoreService {
    public *;
}
-keep class com.runanywhere.sdk.core.onnx.ONNXServiceProviderImpl {
    public *;
}
