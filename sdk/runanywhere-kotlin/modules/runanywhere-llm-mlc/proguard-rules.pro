# Keep MLC-LLM native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep TVM classes
-keep class org.apache.tvm.** { *; }

# Keep MLC classes
-keep class ai.mlc.mlcllm.** { *; }

# Keep Kotlin serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Keep SDK classes
-keep class com.runanywhere.sdk.llm.mlc.** { *; }
