# ProGuard / R8 rules for RunAnywhere.
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

# Optional JPEG2000 decoder referenced by pdfbox-android; this app does not decode JP2.
-dontwarn com.gemalto.jp2.**
# Required only when the exact minified release APK is instrumented for device
# acceptance. AndroidJUnitRunner calls this class before any test method runs.
-keep class androidx.tracing.Trace { *; }

# The separately packaged navigation test links these Compose types while
# reflecting its test method. Keep only those cross-APK types in the target APK.
-keep class androidx.compose.animation.AnimatedContentScope { *; }
-keep class androidx.compose.runtime.Composer { *; }

# AndroidX Test's TestDirCalculator calls kotlin.LazyKt.lazy(Function0), whose
# implementation lives on the LazyKt multifile facade's superclass. Keeping
# only the facade lets R8 merge the hierarchy, rename lazy(), and strengthen
# its return type; releaseAndroidTest's -applymapping cannot rewrite that
# inherited-method call consistently. Keep this tiny facade hierarchy intact.
-keep class kotlin.LazyKt** { *; }

# The separately minified test APK also reads Duration.Companion. Prevent R8
# from vertically merging that one field type into an unrelated Compose class.
-keep class kotlin.time.Duration$Companion { *; }

# Release instrumentation calls these coroutine entry-point facades directly
# (runBlocking/launch/withContext and withTimeout). The release app can inline
# and remove them otherwise, leaving the separately packaged test APK with
# unresolved calls after -applymapping. Keep only the two referenced families.
-keep class kotlinx.coroutines.BuildersKt** { *; }
-keep class kotlinx.coroutines.TimeoutKt** { *; }

# The release NPU/Web acceptance tests are compiled into a separate APK. Their
# generated Kotlin bytecode calls this small, statically-audited API closure
# directly; keep the facade families intact so target R8 cannot merge/remove an
# owner that releaseAndroidTest must resolve at runtime.
-keep class com.runanywhere.runanywhereai.data.ModelCatalog { *; }
-keep class com.runanywhere.runanywhereai.data.SingleFileModel { *; }
-keep class com.runanywhere.runanywhereai.state.GlobalState { *; }
-keep class com.runanywhere.runanywhereai.tools.WebSearchTool { *; }
-keep class com.runanywhere.runanywhereai.util.RACLog { *; }

# Security acceptance tests run against the exact minified release APK. Keep
# only the app-private stores, top-level factory facade, and repositories those
# tests call directly; the separate test APK cannot invoke members R8 removes
# from the target even when it consumes the target mapping file.
-keep class com.runanywhere.runanywhereai.data.security.NoBackupCiphertextStore { *; }
-keep class com.runanywhere.runanywhereai.data.security.SecureStringPreferences { *; }
-keep class com.runanywhere.runanywhereai.data.security.SecurePreferencesKt { *; }
-keep class com.runanywhere.runanywhereai.data.cloud.CloudProviderRepository { *; }
-keep class com.runanywhere.runanywhereai.data.settings.SettingsRepository { *; }
-keepclassmembers class com.runanywhere.runanywhereai.data.settings.AppSettings {
    java.lang.String getHfToken();
}

-keep class kotlin.Unit { *; }
-keep class kotlin.Result** { *; }
-keep class kotlin.ResultKt { *; }
-keep class kotlin.TuplesKt { *; }
-keep class kotlin.comparisons.ComparisonsKt** { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt** { *; }
-keep class kotlin.coroutines.jvm.internal.Boxing { *; }
-keep class kotlin.coroutines.jvm.internal.SpillingKt { *; }
-keep class kotlin.io.ByteStreamsKt** { *; }
-keep class kotlin.io.CloseableKt { *; }
-keep class kotlin.jvm.internal.Intrinsics** { *; }
-keep class kotlin.jvm.internal.Ref$DoubleRef { *; }
-keep class kotlin.jvm.internal.Ref$IntRef { *; }
-keep class kotlin.jvm.internal.Ref$LongRef { *; }
-keep class kotlin.Pair { *; }
-keep class kotlin.ranges.IntRange { *; }
-keep class kotlin.ranges.RangesKt** { *; }
-keep class kotlin.text.MatchResult** { *; }
-keep class kotlin.text.StringsKt** { *; }
-keep class kotlin.collections.ArraysKt** { *; }
-keep class kotlin.collections.CollectionsKt** { *; }
-keep class kotlin.collections.MapsKt** { *; }
-keep class kotlin.io.FilesKt** { *; }
-keep class kotlin.sequences.SequencesKt** { *; }
-keep class kotlin.text.Regex** { *; }
