# RunAnywhere SDK ProGuard Rules
# Keep native method signatures
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep RunAnywhere plugin classes
-keep class ai.runanywhere.sdk.** { *; }
