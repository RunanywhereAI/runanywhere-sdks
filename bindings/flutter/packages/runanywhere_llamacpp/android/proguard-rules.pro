# RunAnywhere LlamaCPP SDK ProGuard Rules
# Keep native method signatures
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep LlamaCPP plugin classes
-keep class ai.runanywhere.sdk.llamacpp.** { *; }
