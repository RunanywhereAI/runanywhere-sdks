# ProGuard / R8 rules for RunAnywhere AI.
# Scoped to what this app actually uses — the SDK + Wire protos (JNI/reflection),
# reflectively-created ViewModels, and kotlinx.serialization. Library consumer
# rules (Compose, OkHttp, kotlinx.serialization, AndroidX) cover the rest.

# Readable release crash traces.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keep class kotlin.Metadata { *; }

# RunAnywhere SDK: JNI, dynamic backend registration, reflection-style lookups.
# Keep the whole SDK surface plus the Wire-generated proto types that cross the
# JNI / serialization boundary — R8 must not rename or strip these.
-keep class com.runanywhere.sdk.** { *; }
-keep interface com.runanywhere.sdk.** { *; }
-keep enum com.runanywhere.sdk.** { *; }
-keepnames class com.runanywhere.sdk.** { *; }
-keep class ai.runanywhere.proto.v1.** { *; }

# JNI: native methods and the classes that declare them.
-keepclasseswithmembernames class * {
    native <methods>;
}

# ViewModels are constructed reflectively by the viewModel() default factory.
-keep class * extends androidx.lifecycle.ViewModel { <init>(...); }
-keep class * extends androidx.lifecycle.AndroidViewModel { <init>(...); }

# kotlinx.serialization — generated serializers + companions for @Serializable types.
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault
-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> {
    static <1>$Companion Companion;
}
-if @kotlinx.serialization.Serializable class ** {
    static **$* *;
}
-keepclassmembers class <2>$<3> {
    kotlinx.serialization.KSerializer serializer(...);
}
-if @kotlinx.serialization.Serializable class ** {
    public static ** INSTANCE;
}
-keepclassmembers class <1> {
    public static <1> INSTANCE;
    kotlinx.serialization.KSerializer serializer(...);
}

# Enums accessed via values()/valueOf().
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Optional platform integrations referenced by OkHttp/Okio but not bundled.
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Optional deps referenced by libraries we use but don't bundle:
#  - JPEG2000 decoder for pdfbox-android (we don't decode JP2)
#  - errorprone annotations from Tink (androidx.security.crypto), compile-only
-dontwarn com.gemalto.jp2.**
-dontwarn com.google.errorprone.annotations.**
