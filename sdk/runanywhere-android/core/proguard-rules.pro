# Add project specific ProGuard rules here.

# Keep Whisper JNI classes
-keep class io.github.givimad.whisperjni.** { *; }

# Keep VAD classes
-keep class com.konovalov.vad.** { *; }

# Keep model classes
-keep class com.runanywhere.sdk.models.** { *; }

# Keep public API
-keep class com.runanywhere.sdk.public.** { *; }
-keep class com.runanywhere.sdk.components.** { *; }
