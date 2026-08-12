# ProGuard / R8 rules for the RunAnywhere AI React Native app (release).
#
# React Native + Hermes: JS is shrunk by Metro/Hermes, not R8. R8 only touches
# the Java/Kotlin native side here. React Native's own libraries ship consumer
# rules, and each RunAnywhere package owns its exact JNI contracts. The broad
# app-level rules retained below cover only contracts that do not yet have a
# provably complete package-owned rule.

# Readable release crash traces.
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod
-keep class kotlin.Metadata { *; }

# Wire-generated protocol messages are created and adapted across package
# boundaries. Keep this until the generated reflection/adapter contract is
# represented by package-owned consumer rules.
-keep class ai.runanywhere.** { *; }

# React Android ships the fbjni and DoNotStrip consumer rules. RunAnywhere
# packages own their exact literal JNI contracts in their consumer rules.

# App-local classes include React packages/services registered from the
# manifest and MainApplication; keep until those entry points have exact rules.
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
