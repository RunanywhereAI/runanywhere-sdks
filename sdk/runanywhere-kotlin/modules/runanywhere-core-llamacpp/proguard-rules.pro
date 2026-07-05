# ========================================================================================
# RunAnywhere Core LlamaCPP Module - ProGuard Rules
# ========================================================================================

# Keep ALL SDK classes (inherited from main SDK rules, but explicit for safety)
-keep class com.runanywhere.sdk.** { *; }
-keep interface com.runanywhere.sdk.** { *; }
-keep enum com.runanywhere.sdk.** { *; }

# Keep all constructors (critical for JNI)
-keepclassmembers class com.runanywhere.sdk.** {
    <init>(...);
}

# Keep companion objects and singletons
-keepclassmembers class com.runanywhere.sdk.** {
    public static ** Companion;
    public static ** INSTANCE;
    public static ** shared;
}

# Prevent obfuscation (class, interface, and enum names for consistency)
-keepnames class com.runanywhere.sdk.** { *; }
-keepnames interface com.runanywhere.sdk.** { *; }
-keepnames enum com.runanywhere.sdk.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# LlamaCPP Runtime
-keep class com.runanywhere.sdk.core.llamacpp.** { *; }
-dontwarn com.runanywhere.sdk.core.llamacpp.**
