# Add project specific ProGuard rules here.

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

# Keep all enums in native.bridge package
-keep enum com.runanywhere.sdk.native.bridge.** {
    *;
}

# ========================================================================================
# Third-party JNI Libraries
# ========================================================================================

# Keep Whisper JNI classes
-keep class io.github.givimad.whisperjni.** { *; }

# Keep VAD classes
-keep class com.konovalov.vad.** { *; }

# ========================================================================================
# SDK Public API
# ========================================================================================

# Keep model classes
-keep class com.runanywhere.sdk.models.** { *; }

# Keep public API
-keep class com.runanywhere.sdk.public.** { *; }
-keep class com.runanywhere.sdk.components.** { *; }
