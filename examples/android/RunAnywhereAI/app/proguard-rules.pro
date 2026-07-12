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

# The Compose navigation instrumentation test is packaged separately from the
# minified target APK. R8's target mapping cannot describe owners that target
# shrinking removes or vertically merges, so keep the exact mapped-DEX closure
# observed from that test and AndroidX Compose Test. Renaming remains allowed so
# the test APK can consume the target mapping; package-wide keeps are forbidden.
-keep,allowobfuscation class androidx.activity.ComponentActivity { *; }
-keep,allowobfuscation class androidx.collection.IntSet { *; }
-keep,allowobfuscation class androidx.compose.runtime.ComposablesKt { *; }
-keep,allowobfuscation class androidx.compose.runtime.CompositionLocalKt { *; }
-keep,allowobfuscation class androidx.compose.runtime.EffectsKt { *; }
-keep,allowobfuscation class androidx.compose.runtime.MonotonicFrameClock { *; }
-keep,allowobfuscation class androidx.compose.runtime.MonotonicFrameClock$DefaultImpls { *; }
-keep,allowobfuscation class androidx.compose.runtime.RecomposeScopeImplKt { *; }
-keep,allowobfuscation class androidx.compose.runtime.SnapshotMutationPolicy { *; }
-keep,allowobfuscation class androidx.compose.runtime.SnapshotStateKt { *; }
-keep,allowobfuscation class androidx.compose.runtime.Updater { *; }
-keep,allowobfuscation class androidx.compose.runtime.internal.ComposableLambda { *; }
-keep,allowobfuscation class androidx.compose.runtime.internal.ComposableLambdaKt { *; }
-keep,allowobfuscation class androidx.compose.runtime.snapshots.Snapshot$Companion { *; }
-keep,allowobfuscation class androidx.compose.ui.ComposedModifierKt { *; }
-keep,allowobfuscation class androidx.compose.ui.geometry.Offset$Companion { *; }
-keep,allowobfuscation class androidx.compose.ui.geometry.OffsetKt { *; }
-keep,allowobfuscation class androidx.compose.ui.geometry.RectKt { *; }
-keep,allowobfuscation class androidx.compose.ui.graphics.AndroidImageBitmap_androidKt { *; }
-keep,allowobfuscation class androidx.compose.ui.graphics.ImageBitmap { *; }
-keep,allowobfuscation class androidx.compose.ui.input.key.Key$Companion { *; }
-keep,allowobfuscation class androidx.compose.ui.input.key.KeyEvent_androidKt { *; }
-keep,allowobfuscation class androidx.compose.ui.input.key.Key_androidKt { *; }
-keep,allowobfuscation class androidx.compose.ui.layout.LayoutCoordinatesKt { *; }
-keep,allowobfuscation class androidx.compose.ui.layout.LayoutInfo { *; }
-keep,allowobfuscation class androidx.compose.ui.layout.LayoutModifierKt { *; }
-keep,allowobfuscation class androidx.compose.ui.layout.SubcomposeLayoutKt { *; }
-keep,allowobfuscation class androidx.compose.ui.platform.InfiniteAnimationPolicy { *; }
-keep,allowobfuscation class androidx.compose.ui.platform.InfiniteAnimationPolicy$DefaultImpls { *; }
-keep,allowobfuscation class androidx.compose.ui.platform.PlatformTextInputInterceptor { *; }
-keep,allowobfuscation class androidx.compose.ui.platform.PlatformTextInputMethodRequest { *; }
-keep,allowobfuscation class androidx.compose.ui.platform.PlatformTextInputSession { *; }
-keep,allowobfuscation class androidx.compose.ui.platform.ViewRootForTest { *; }
-keep,allowobfuscation class androidx.compose.ui.platform.ViewRootForTest$Companion { *; }
-keep,allowobfuscation class androidx.compose.ui.platform.WindowRecomposerFactory { *; }
-keep,allowobfuscation class androidx.compose.ui.semantics.CustomAccessibilityAction { *; }
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsConfigurationKt { *; }
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsOwnerKt { *; }
-keep,allowobfuscation class androidx.compose.ui.text.font.FontFamilyResolver_androidKt { *; }
-keep,allowobfuscation class androidx.compose.ui.text.input.ImeAction$Companion { *; }
-keep,allowobfuscation class androidx.compose.ui.unit.AndroidDensity_androidKt { *; }
-keep,allowobfuscation class androidx.compose.ui.unit.Constraints$Companion { *; }
-keep,allowobfuscation class androidx.compose.ui.unit.DensityKt { *; }
-keep,allowobfuscation class androidx.compose.ui.unit.Dp$Companion { *; }
-keep,allowobfuscation class androidx.compose.ui.unit.DpRect { *; }
-keep,allowobfuscation class androidx.compose.ui.unit.IntSizeKt { *; }
-keep,allowobfuscation class androidx.compose.ui.util.MathHelpersKt { *; }
-keep,allowobfuscation class androidx.compose.ui.viewinterop.AndroidView_androidKt { *; }
-keep,allowobfuscation class androidx.compose.ui.window.DialogWindowProvider { *; }
-keep,allowobfuscation class androidx.core.os.ConfigurationCompat { *; }
-keep,allowobfuscation class androidx.core.view.ViewGroupKt { *; }
-keep,allowobfuscation class androidx.lifecycle.Lifecycle { *; }
-keep,allowobfuscation class androidx.lifecycle.ViewTreeLifecycleOwner { *; }
-keep,allowobfuscation class androidx.navigation.NavBackStackEntryKt { *; }
-keep,allowobfuscation class androidx.navigation.compose.NavGraphBuilderKt { *; }
-keep,allowobfuscation class androidx.navigation.compose.NavHostControllerKt { *; }
-keep,allowobfuscation class androidx.navigation.compose.NavHostKt { *; }
-keep,allowobfuscation class com.runanywhere.runanywhereai.ui.navigation.DestinationsKt { *; }
-keep,allowobfuscation class kotlin.KotlinNothingValueException { *; }
-keep,allowobfuscation class kotlin.NoWhenBranchMatchedException { *; }
-keep,allowobfuscation class kotlin.coroutines.Continuation { *; }
-keep,allowobfuscation class kotlin.coroutines.ContinuationInterceptor { *; }
-keep,allowobfuscation class kotlin.coroutines.ContinuationInterceptor$DefaultImpls { *; }
-keep,allowobfuscation class kotlin.coroutines.ContinuationInterceptor$Key { *; }
-keep,allowobfuscation class kotlin.coroutines.jvm.internal.DebugProbesKt { *; }
-keep,allowobfuscation class kotlin.coroutines.jvm.internal.SuspendFunction { *; }
-keep,allowobfuscation class kotlin.jvm.functions.Function0 { *; }
-keep,allowobfuscation class kotlin.jvm.internal.InlineMarker { *; }
-keep,allowobfuscation class kotlin.time.DurationKt { *; }
-keep,allowobfuscation class kotlinx.coroutines.CompletableJob { *; }
-keep,allowobfuscation class kotlinx.coroutines.CoroutineExceptionHandler$Key { *; }
-keep,allowobfuscation class kotlinx.coroutines.CoroutineScopeKt { *; }
-keep,allowobfuscation class kotlinx.coroutines.DelayKt { *; }
-keep,allowobfuscation class kotlinx.coroutines.Job$Key { *; }
-keep,allowobfuscation class kotlinx.coroutines.JobKt { *; }
-keep,allowobfuscation class kotlinx.coroutines.MainCoroutineDispatcher { *; }
-keep,allowobfuscation class kotlinx.coroutines.internal.MainDispatcherFactory { *; }

# These owners survive target shrinking, but the separately optimized test APK
# calls members that target R8 previously removed or changed incompatibly.
# Preserve only the measured members and continue allowing mapped renaming.
-keep,allowobfuscation class androidx.collection.IntSetKt {
    androidx.collection.IntSet intSetOf(int[]);
}
-keep,allowobfuscation class androidx.compose.ui.platform.AbstractComposeView {
    <init>(android.content.Context, android.util.AttributeSet, int, int, kotlin.jvm.internal.DefaultConstructorMarker);
}
-keep,allowobfuscation class androidx.compose.ui.unit.IntSize {
    androidx.compose.ui.unit.IntSize box-impl(long);
    long constructor-impl(long);
}
-keep,allowobfuscation class kotlin.ExceptionsKt {
    void addSuppressed(java.lang.Throwable, java.lang.Throwable);
}
-keep,allowobfuscation class androidx.compose.runtime.ScopeUpdateScope {
    void updateScope(kotlin.jvm.functions.Function2);
}
-keep,allowobfuscation class androidx.compose.ui.text.input.ImeAction {
    androidx.compose.ui.text.input.ImeAction box-impl(int);
    androidx.compose.ui.text.input.ImeAction$Companion Companion;
}
-keep,allowobfuscation class kotlin.jvm.internal.Reflection {
    kotlin.reflect.KClass getOrCreateKotlinClass(java.lang.Class);
}
-keep,allowobfuscation class kotlin.jvm.internal.FunctionReferenceImpl {
    <init>(int, java.lang.Object, java.lang.Class, java.lang.String, java.lang.String, int);
}
-keep,allowobfuscation class androidx.compose.ui.text.TextLayoutResult {
    int getLineEnd$default(androidx.compose.ui.text.TextLayoutResult, int, boolean, int, java.lang.Object);
    int getLineForOffset(int);
}
-keep,allowobfuscation class androidx.compose.ui.layout.MeasureScope {
    androidx.compose.ui.layout.MeasureResult layout$default(androidx.compose.ui.layout.MeasureScope, int, int, java.util.Map, kotlin.jvm.functions.Function1, int, java.lang.Object);
}
-keep,allowobfuscation class kotlinx.coroutines.CoroutineDispatcher {
    kotlin.coroutines.Continuation interceptContinuation(kotlin.coroutines.Continuation);
}
-keep,allowobfuscation class kotlin.time.Duration {
    java.lang.String toString-impl(long);
}
-keep,allowobfuscation class androidx.core.os.LocaleListCompat {
    androidx.core.os.LocaleListCompat forLanguageTags(java.lang.String);
    java.util.Locale get(int);
}
-keep,allowobfuscation class com.runanywhere.runanywhereai.ui.navigation.Vision {
    <init>(boolean, int, kotlin.jvm.internal.DefaultConstructorMarker);
}
-keep,allowobfuscation class androidx.compose.ui.unit.Density {
    int roundToPx--R2X_6o(long);
    float toDp-GaN1DYA(long);
    androidx.compose.ui.geometry.Rect toRect(androidx.compose.ui.unit.DpRect);
    long toSp-0xMU5do(float);
    long toSp-kPz2Gy4(int);
}
-keep,allowobfuscation class androidx.core.view.ViewConfigurationCompat {
    float getScaledHorizontalScrollFactor(android.view.ViewConfiguration, android.content.Context);
    float getScaledVerticalScrollFactor(android.view.ViewConfiguration, android.content.Context);
}
-keep,allowobfuscation class androidx.compose.ui.layout.Placeable$PlacementScope {
    void placeRelative$default(androidx.compose.ui.layout.Placeable$PlacementScope, androidx.compose.ui.layout.Placeable, int, int, float, int, java.lang.Object);
}
-keep,allowobfuscation class androidx.compose.ui.platform.PlatformTextInputModifierNodeKt {
    void InterceptPlatformTextInput(androidx.compose.ui.platform.PlatformTextInputInterceptor, kotlin.jvm.functions.Function2, androidx.compose.runtime.Composer, int);
}
-keep,allowobfuscation class androidx.compose.ui.geometry.Offset {
    long copy-dBAh8RU$default(long, float, float, int, java.lang.Object);
    androidx.compose.ui.geometry.Offset box-impl(long);
    long constructor-impl(long);
    androidx.compose.ui.geometry.Offset$Companion Companion;
}
-keep,allowobfuscation class kotlin.math.MathKt {
    int roundToInt(float);
    long roundToLong(float);
}
-keep,allowobfuscation class kotlin.NotImplementedError {
    <init>(java.lang.String);
}
-keep,allowobfuscation class androidx.activity.compose.ComponentActivityKt {
    void setContent(androidx.activity.ComponentActivity, androidx.compose.runtime.CompositionContext, kotlin.jvm.functions.Function2);
}
-keep,allowobfuscation class kotlin.collections.SetsKt {
    java.util.Set minus(java.util.Set, java.lang.Iterable);
}
-keep,allowobfuscation class androidx.compose.ui.text.AnnotatedString {
    <init>(java.lang.String, java.util.List, int, kotlin.jvm.internal.DefaultConstructorMarker);
    java.util.List getLinkAnnotations(int, int);
    java.util.List getStringAnnotations(int, int);
}
-keep,allowobfuscation class androidx.compose.ui.unit.Dp {
    androidx.compose.ui.unit.Dp box-impl(float);
    float constructor-impl(float);
    androidx.compose.ui.unit.Dp$Companion Companion;
}
-keep,allowobfuscation class kotlin.enums.EnumEntriesKt {
    kotlin.enums.EnumEntries enumEntries(java.lang.Enum[]);
}
-keep,allowobfuscation class androidx.compose.ui.platform.WindowRecomposerPolicy {
    boolean compareAndSetFactory(androidx.compose.ui.platform.WindowRecomposerFactory, androidx.compose.ui.platform.WindowRecomposerFactory);
    androidx.compose.ui.platform.WindowRecomposerFactory getAndSetFactory(androidx.compose.ui.platform.WindowRecomposerFactory);
    androidx.compose.ui.platform.WindowRecomposerPolicy INSTANCE;
}
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsConfiguration {
    boolean contains(androidx.compose.ui.semantics.SemanticsPropertyKey);
    java.lang.Object getOrElseNullable(androidx.compose.ui.semantics.SemanticsPropertyKey, kotlin.jvm.functions.Function0);
}
-keep,allowobfuscation class androidx.compose.ui.input.key.Key {
    androidx.compose.ui.input.key.Key box-impl(long);
    boolean equals-impl(long, java.lang.Object);
    java.lang.String toString-impl(long);
    androidx.compose.ui.input.key.Key$Companion Companion;
}
-keep,allowobfuscation class androidx.compose.runtime.ComposerKt {
    void sourceInformation(androidx.compose.runtime.Composer, java.lang.String);
    void sourceInformationMarkerEnd(androidx.compose.runtime.Composer);
    void sourceInformationMarkerStart(androidx.compose.runtime.Composer, int, java.lang.String);
    void traceEventStart(int, int, int, java.lang.String);
}
-keep,allowobfuscation class androidx.compose.ui.unit.DpSize {
    androidx.compose.ui.unit.DpSize box-impl(long);
}
-keep,allowobfuscation class androidx.compose.ui.util.ListUtilsKt {
    java.lang.String fastJoinToString$default(java.util.List, java.lang.CharSequence, java.lang.CharSequence, java.lang.CharSequence, int, java.lang.CharSequence, kotlin.jvm.functions.Function1, int, java.lang.Object);
}
-keep,allowobfuscation class androidx.compose.runtime.Recomposer {
    java.lang.Object runRecomposeAndApplyChanges(kotlin.coroutines.Continuation);
}
-keep,allowobfuscation class kotlinx.coroutines.CancellableContinuation {
    void invokeOnCancellation(kotlin.jvm.functions.Function1);
}
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsNode {
    int getAlignmentLinePosition(androidx.compose.ui.layout.AlignmentLine);
}
-keep,allowobfuscation class kotlinx.coroutines.CancellableContinuationImpl {
    <init>(kotlin.coroutines.Continuation, int);
}
-keep,allowobfuscation class kotlin.coroutines.jvm.internal.SuspendLambda {
    <init>(int, kotlin.coroutines.Continuation);
}
-keep,allowobfuscation class kotlinx.coroutines.Dispatchers {
    kotlinx.coroutines.MainCoroutineDispatcher getMain();
}
-keep,allowobfuscation class kotlinx.coroutines.Delay {
    java.lang.Object delay(long, kotlin.coroutines.Continuation);
    void scheduleResumeAfterDelay(long, kotlinx.coroutines.CancellableContinuation);
}
-keep,allowobfuscation class androidx.compose.ui.node.RootForTest {
    boolean sendKeyEvent-ZmokQxo(android.view.KeyEvent);
}
-keep,allowobfuscation class androidx.compose.runtime.ProvidableCompositionLocal {
    androidx.compose.runtime.ProvidedValue provides(java.lang.Object);
}
-keep,allowobfuscation class androidx.compose.runtime.saveable.SaveableStateRegistryKt {
    androidx.compose.runtime.saveable.SaveableStateRegistry SaveableStateRegistry(java.util.Map, kotlin.jvm.functions.Function1);
}
-keep,allowobfuscation class androidx.compose.runtime.snapshots.Snapshot {
    androidx.compose.runtime.snapshots.Snapshot$Companion Companion;
}
-keep,allowobfuscation class androidx.compose.ui.unit.Constraints {
    androidx.compose.ui.unit.Constraints$Companion Companion;
}
-keep,allowobfuscation class androidx.compose.ui.Modifier {
    androidx.compose.ui.Modifier$Companion Companion;
}
-keep,allowobfuscation class kotlinx.coroutines.CoroutineExceptionHandler {
    kotlinx.coroutines.CoroutineExceptionHandler$Key Key;
}
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsActions {
    androidx.compose.ui.semantics.SemanticsActions INSTANCE;
}
-keep,allowobfuscation class kotlinx.coroutines.Job {
    kotlinx.coroutines.Job$Key Key;
}
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsProperties {
    androidx.compose.ui.semantics.SemanticsProperties INSTANCE;
}
-keep,allowobfuscation class androidx.compose.runtime.ProvidedValue {
    int $stable;
}

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
