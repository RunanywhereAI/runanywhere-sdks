# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# ========================================================================================
# RunAnywhere AI LLM Sample App - ProGuard Configuration
# ========================================================================================

# Keep line numbers for debugging
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod

# ========================================================================================
# LLM Framework Rules - Keep all LLM service implementations
# ========================================================================================

# Keep all LLM service classes and their methods
-keep class com.runanywhere.runanywhereai.llm.frameworks.** { *; }
-keep interface com.runanywhere.runanywhereai.llm.LLMService { *; }
-keep class com.runanywhere.runanywhereai.llm.** { *; }

# Keep UnifiedLLMManager
-keep class com.runanywhere.runanywhereai.manager.UnifiedLLMManager { *; }

# ========================================================================================
# Data Models and DTOs
# ========================================================================================

# Keep all data classes used for serialization/deserialization
-keep @kotlinx.serialization.Serializable class ** { *; }
-keep class com.runanywhere.runanywhereai.data.** { *; }

# Keep Room database entities and DAOs
-keep class com.runanywhere.runanywhereai.data.database.** { *; }
-keep @androidx.room.Entity class ** { *; }
-keep @androidx.room.Database class ** { *; }
-keep @androidx.room.Dao class ** { *; }

# ========================================================================================
# Native Libraries and JNI
# ========================================================================================

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep classes that are used by native code
-keep class * {
    native <methods>;
}

# ========================================================================================
# RunAnywhere SDK - KEEP ENTIRE SDK (CRITICAL)
# ========================================================================================
# The SDK uses dynamic registration, reflection-like patterns, and JNI callbacks.
# We must keep ALL classes, interfaces, enums, and their members to prevent R8/ProGuard
# from obfuscating or removing them.

# MASTER RULE: Keep ALL classes in com.runanywhere.sdk package and all subpackages
-keep class com.runanywhere.sdk.** { *; }
-keep interface com.runanywhere.sdk.** { *; }
-keep enum com.runanywhere.sdk.** { *; }

# Keep all constructors (critical for JNI object creation)
-keepclassmembers class com.runanywhere.sdk.** {
    <init>(...);
}

# Keep companion objects and their members (Kotlin singletons like LlamaCppAdapter.shared)
-keepclassmembers class com.runanywhere.sdk.** {
    public static ** Companion;
    public static ** INSTANCE;
    public static ** shared;
}

# Keep Kotlin metadata for reflection
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-keep class kotlin.Metadata { *; }

# Prevent obfuscation of class names (important for logging and debugging)
-keepnames class com.runanywhere.sdk.** { *; }
-keepnames interface com.runanywhere.sdk.** { *; }
-keepnames enum com.runanywhere.sdk.** { *; }

# ========================================================================================
# TensorFlow Lite
# ========================================================================================

# Keep TensorFlow Lite classes
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.support.** { *; }
-dontwarn org.tensorflow.lite.**

# ========================================================================================
# ONNX Runtime
# ========================================================================================

# Keep ONNX Runtime classes
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# ========================================================================================
# MediaPipe
# ========================================================================================

# Keep MediaPipe classes
-keep class com.google.mediapipe.** { *; }
-dontwarn com.google.mediapipe.**

# ========================================================================================
# Llama.cpp (via JNI)
# ========================================================================================

# Keep llama.cpp JNI interfaces
-keep class ai.djl.llama.jni.** { *; }
-dontwarn ai.djl.llama.jni.**

# ========================================================================================
# ExecuTorch
# ========================================================================================

# Keep ExecuTorch classes when available
-keep class org.pytorch.executorch.** { *; }
-dontwarn org.pytorch.executorch.**

# ========================================================================================
# MLC-LLM
# ========================================================================================

# Keep MLC-LLM classes
-keep class ai.mlc.mlcllm.** { *; }
-dontwarn ai.mlc.mlcllm.**

# ========================================================================================
# picoLLM
# ========================================================================================

# Keep picoLLM classes when available
-keep class ai.picovoice.picollm.** { *; }
-dontwarn ai.picovoice.picollm.**

# ========================================================================================
# Android AI Core
# ========================================================================================

# Keep Android AI Core classes
-keep class com.google.android.aicore.** { *; }
-dontwarn com.google.android.aicore.**

# ========================================================================================
# Kotlin Coroutines
# ========================================================================================

# Keep coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# ========================================================================================
# Compose and UI
# ========================================================================================

# Keep Compose runtime classes
-keep class androidx.compose.** { *; }
-dontwarn androidx.compose.**

# Keep ViewModel classes
-keep class androidx.lifecycle.ViewModel { *; }
-keep class * extends androidx.lifecycle.ViewModel { *; }

# ========================================================================================
# Hilt/Dagger
# ========================================================================================

# Keep Hilt generated classes
-keep class dagger.hilt.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ApplicationComponentManager { *; }
-keep class **_HiltModules { *; }
-keep class **_HiltComponents { *; }
-keep class **_Factory { *; }
-keep class **_MembersInjector { *; }

# ========================================================================================
# Security and Encryption
# ========================================================================================

# Keep encryption classes
-keep class com.runanywhere.runanywhereai.security.** { *; }
-keep class androidx.security.crypto.** { *; }

# Keep Android Keystore classes
-keep class android.security.keystore.** { *; }
-dontwarn android.security.keystore.**

# ========================================================================================
# JSON and Serialization
# ========================================================================================

# Keep JSON classes
-keep class org.json.** { *; }
-dontwarn org.json.**

# Keep Gson classes if used
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# ========================================================================================
# Model Files and Assets
# ========================================================================================

# Keep model files in assets
# Note: -keepresourcefiles is not supported in R8, resources are kept by default
# -keepresourcefiles assets/models/**
# -keepresourcefiles assets/tokenizers/**

# Don't obfuscate model loading code
-keep class com.runanywhere.runanywhereai.data.repository.ModelRepository { *; }

# ========================================================================================
# Performance and Monitoring
# ========================================================================================

# Keep performance monitoring classes
-keep class com.runanywhere.runanywhereai.monitoring.** { *; }

# ========================================================================================
# Reflection
# ========================================================================================

# Keep classes that use reflection
-keepattributes *Annotation*
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# ========================================================================================
# Common Android Rules
# ========================================================================================

# Keep custom views
-keep public class * extends android.view.View {
    public <init>(android.content.Context);
    public <init>(android.content.Context, android.util.AttributeSet);
    public <init>(android.content.Context, android.util.AttributeSet, int);
}

# Keep Parcelable implementations
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# ========================================================================================
# Warnings to Ignore
# ========================================================================================

# Ignore warnings for optional dependencies
-dontwarn java.awt.**
-dontwarn javax.swing.**
-dontwarn sun.misc.**
-dontwarn java.lang.management.**
-dontwarn org.slf4j.**
-dontwarn ch.qos.logback.**

# Ignore warnings for reflection-based libraries
-dontwarn kotlin.reflect.**
-dontwarn org.jetbrains.annotations.**

# ========================================================================================
# R8 Generated Missing Rules
# ========================================================================================

# Apache Commons Lang3 (uses Java 8+ reflection API not available on Android)
-dontwarn java.lang.reflect.AnnotatedType

# Zstd compression library
-dontwarn com.github.luben.zstd.ZstdInputStream
-dontwarn com.github.luben.zstd.ZstdOutputStream

# Google API Client HTTP library
-dontwarn com.google.api.client.http.GenericUrl
-dontwarn com.google.api.client.http.HttpHeaders
-dontwarn com.google.api.client.http.HttpRequest
-dontwarn com.google.api.client.http.HttpRequestFactory
-dontwarn com.google.api.client.http.HttpResponse
-dontwarn com.google.api.client.http.HttpTransport
-dontwarn com.google.api.client.http.javanet.NetHttpTransport$Builder
-dontwarn com.google.api.client.http.javanet.NetHttpTransport

# Apache Commons codec
-dontwarn org.apache.commons.codec.digest.PureJavaCrc32C
-dontwarn org.apache.commons.codec.digest.XXHash32

# Brotli decompression
-dontwarn org.brotli.dec.BrotliInputStream

# Joda time
-dontwarn org.joda.time.Instant

# ASM (bytecode manipulation)
-dontwarn org.objectweb.asm.AnnotationVisitor
-dontwarn org.objectweb.asm.Attribute
-dontwarn org.objectweb.asm.ClassReader
-dontwarn org.objectweb.asm.ClassVisitor
-dontwarn org.objectweb.asm.FieldVisitor
-dontwarn org.objectweb.asm.MethodVisitor

# XZ compression library
-dontwarn org.tukaani.xz.ARMOptions
-dontwarn org.tukaani.xz.ARMThumbOptions
-dontwarn org.tukaani.xz.DeltaOptions
-dontwarn org.tukaani.xz.FilterOptions
-dontwarn org.tukaani.xz.FinishableOutputStream
-dontwarn org.tukaani.xz.FinishableWrapperOutputStream
-dontwarn org.tukaani.xz.IA64Options
-dontwarn org.tukaani.xz.LZMA2InputStream
-dontwarn org.tukaani.xz.LZMA2Options
-dontwarn org.tukaani.xz.LZMAInputStream
-dontwarn org.tukaani.xz.LZMAOutputStream
-dontwarn org.tukaani.xz.MemoryLimitException
-dontwarn org.tukaani.xz.PowerPCOptions
-dontwarn org.tukaani.xz.SPARCOptions
-dontwarn org.tukaani.xz.UnsupportedOptionsException
-dontwarn org.tukaani.xz.X86Options
-dontwarn org.tukaani.xz.XZ
-dontwarn org.tukaani.xz.XZOutputStream

# ========================================================================================
# Debug Information (Comment out for release builds)
# ========================================================================================

# Keep debug information for crash reporting
-keepattributes SourceFile,LineNumberTable

# ========================================================================================
# Logging - Keep Log statements for debugging release builds
# ========================================================================================

# Keep all android.util.Log methods (do NOT strip logs in release for debugging)
-assumenosideeffects class android.util.Log {
    # Comment out these lines to KEEP logs in release builds
    # public static int v(...);
    # public static int d(...);
    # public static int i(...);
    # public static int w(...);
    # public static int e(...);
}

# Keep Timber logging if used
-keep class timber.log.Timber { *; }
-keep class timber.log.Timber$* { *; }

# Print configuration for debugging (remove in final release)
#-printconfiguration proguard-config.txt
#-printusage proguard-usage.txt
#-printmapping proguard-mapping.txt
