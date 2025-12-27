# RunAnywhere ProGuard Rules
# Keep native method names for JNI

-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep the plugin class
-keep class ai.runanywhere.nativelibs.** { *; }
