# ProGuard / R8 rules for the RunAnywhere AI Flutter app (release).
#
# The Dart app is AOT-compiled and not processed by R8. R8 only shrinks the
# Android Java/Kotlin shell, so these keeps target the Flutter embedding and the
# RunAnywhere / QHexRT plugin classes (JNI / System.loadLibrary; resolved by
# name) plus native methods. Broad -dontwarn entries keep R8's missing-class
# check from failing on optional transitive deps pulled by the plugins.

# Flutter embedding + generated plugin registrant.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.**

# RunAnywhere SDK + QHexRT plugin (ai.runanywhere.sdk.qhexrt.*) — JNI / dynamic
# native registration; must not be renamed or stripped.
-keep class ai.runanywhere.** { *; }
-keep class com.runanywhere.** { *; }
-keepnames class ai.runanywhere.** { *; }

# JNI native methods + their declaring classes.
-keepclasseswithmembernames class * {
    native <methods>;
}

# Enums via values()/valueOf().
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod

# Optional deps referenced by plugins (camera/pdf/secure-storage/etc.) but not
# always present; silence R8's missing-class errors so the build stays clean.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn com.google.android.play.core.**
