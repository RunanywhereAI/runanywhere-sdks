# ProGuard / R8 rules for the RunAnywhere AI React Native app (release).
#
# React Native + Hermes: JS is shrunk by Metro/Hermes, not R8. R8 only touches
# the Java/Kotlin native side here. React Native's own libraries ship consumer
# rules; the app-specific keeps below cover the RunAnywhere SDK + Nitro + the
# QHexRT JNI/native bridges, which are resolved by name across the JNI boundary
# and must NOT be renamed or stripped.

# Readable release crash traces.
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod
-keep class kotlin.Metadata { *; }

# RunAnywhere SDK (core + qhexrt/llamacpp/onnx engines) + Wire protos: JNI,
# dynamic backend registration, reflective lookups.
-keep class com.runanywhere.** { *; }
-keep interface com.runanywhere.** { *; }
-keep class ai.runanywhere.** { *; }
-keepnames class com.runanywhere.** { *; }

# Nitro Modules — HybridObjects (incl. RunAnywhereQHexRT) are registered and
# resolved by class name from C++ via JNI.
-keep class com.margelo.nitro.** { *; }
-keep class com.facebook.jni.** { *; }
-keep @com.facebook.proguard.annotations.DoNotStrip class * { *; }
-keepclassmembers class * {
    @com.facebook.proguard.annotations.DoNotStrip *;
}

# App-local native package (DocumentService) registered in MainApplication.
-keep class com.runanywhereaI.** { *; }

# JNI: native methods and the classes that declare them.
-keepclasseswithmembernames class * {
    native <methods>;
}

# Enums accessed via values()/valueOf() (framework/category proto enums).
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Optional transitive deps referenced but not bundled.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
# JPEG2000 decoder for pdfbox-android (RAG/DocumentService); we don't decode JP2.
-dontwarn com.gemalto.jp2.**
