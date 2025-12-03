# RunAnywhere SDK Consumer ProGuard Rules
# These rules are automatically applied to apps that depend on the SDK

# ========================================================================================
# JNI Native Bridge - CRITICAL: These classes are accessed from native code
# ========================================================================================

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep the unified JNI bridge class and all its methods
-keep class com.runanywhere.sdk.native.bridge.RunAnywhereBridge {
    *;
}

# Keep result types used by JNI - constructors must be preserved for JNI instantiation
-keep class com.runanywhere.sdk.native.bridge.NativeTTSSynthesisResult {
    <init>(...);
    <fields>;
    *;
}
-keep class com.runanywhere.sdk.native.bridge.NativeVADResult {
    <init>(...);
    <fields>;
    *;
}
-keep class com.runanywhere.sdk.native.bridge.NativeBridgeException {
    *;
}

# Keep all classes and enums in native.bridge package
-keep class com.runanywhere.sdk.native.bridge.** {
    *;
}
-keep enum com.runanywhere.sdk.native.bridge.** {
    *;
}

# ========================================================================================
# SDK Public API
# ========================================================================================

# Keep model classes
-keep class com.runanywhere.sdk.models.** { *; }

# Keep public API
-keep class com.runanywhere.sdk.public.** { *; }
-keep class com.runanywhere.sdk.components.** { *; }

# ========================================================================================
# Third-party JNI Libraries used by SDK
# ========================================================================================

# Keep Whisper JNI classes
-keep class io.github.givimad.whisperjni.** { *; }

# Keep VAD classes
-keep class com.konovalov.vad.** { *; }
