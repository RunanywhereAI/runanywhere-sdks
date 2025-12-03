# ========================================================================================
# RunAnywhere SDK - ProGuard Rules
# ========================================================================================
# These rules ensure the SDK works correctly in release builds with R8/ProGuard enabled.

# ========================================================================================
# MASTER RULE: Keep ALL SDK classes
# ========================================================================================
# The SDK uses dynamic registration, reflection-like patterns, and JNI callbacks.
# We must keep ALL classes, interfaces, enums, and their members.

-keep class com.runanywhere.sdk.** { *; }
-keep interface com.runanywhere.sdk.** { *; }
-keep enum com.runanywhere.sdk.** { *; }

# Keep all constructors (critical for JNI object creation like NativeTTSSynthesisResult)
-keepclassmembers class com.runanywhere.sdk.** {
    <init>(...);
}

# Keep companion objects and their members (Kotlin singletons like LlamaCppAdapter.shared)
-keepclassmembers class com.runanywhere.sdk.** {
    public static ** Companion;
    public static ** INSTANCE;
    public static ** shared;
}

# Prevent obfuscation of class names (important for JNI, logging, and debugging)
-keepnames class com.runanywhere.sdk.** { *; }
-keepnames interface com.runanywhere.sdk.** { *; }
-keepnames enum com.runanywhere.sdk.** { *; }

# Keep Kotlin metadata for reflection
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-keep class kotlin.Metadata { *; }

# ========================================================================================
# Native Methods (JNI)
# ========================================================================================

-keepclasseswithmembernames class * {
    native <methods>;
}

# ========================================================================================
# Third-party Dependencies
# ========================================================================================

# Whisper JNI
-keep class io.github.givimad.whisperjni.** { *; }
-dontwarn io.github.givimad.whisperjni.**

# VAD classes
-keep class com.konovalov.vad.** { *; }
-dontwarn com.konovalov.vad.**

# ONNX Runtime
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# Suppress warnings for optional dependencies
-dontwarn org.slf4j.**
-dontwarn ch.qos.logback.**
