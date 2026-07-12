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
-keep,allowobfuscation interface kotlinx.coroutines.DelayWithTimeoutDiagnostics {
    java.lang.String timeoutMessage-LRDsOJo(long);
}
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
-keep interface androidx.compose.ui.unit.Density {
    float getFontScale();
    int roundToPx--R2X_6o(long);
    androidx.compose.ui.geometry.Rect toRect(androidx.compose.ui.unit.DpRect);
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
-keep,allowobfuscation class kotlinx.coroutines.channels.ChannelKt {
    kotlinx.coroutines.channels.Channel Channel$default(int, kotlinx.coroutines.channels.BufferOverflow, kotlin.jvm.functions.Function1, int, java.lang.Object);
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

# The release test APK is minified separately with the target APK's mapping.
# Preserve the exact non-platform linkage closure reached from its 24 test
# methods. These rules intentionally retain only measured types and members.

# Types removed completely from the target by R8.
-keep,allowobfuscation class kotlin.coroutines.CoroutineContext$Element$DefaultImpls {
    java.lang.Object fold(kotlin.coroutines.CoroutineContext$Element, java.lang.Object, kotlin.jvm.functions.Function2);
    kotlin.coroutines.CoroutineContext$Element get(kotlin.coroutines.CoroutineContext$Element, kotlin.coroutines.CoroutineContext$Key);
    kotlin.coroutines.CoroutineContext minusKey(kotlin.coroutines.CoroutineContext$Element, kotlin.coroutines.CoroutineContext$Key);
    kotlin.coroutines.CoroutineContext plus(kotlin.coroutines.CoroutineContext$Element, kotlin.coroutines.CoroutineContext);
}
-keep,allowobfuscation class kotlin.jvm.internal.PropertyReference1 {
    java.lang.Object invoke(java.lang.Object);
}
-keep,allowobfuscation class kotlin.jvm.internal.PropertyReference1Impl {
    <init>(java.lang.Class, java.lang.String, java.lang.String, int);
    java.lang.Object get(java.lang.Object);
}
-keep,allowobfuscation class kotlin.time.AbstractLongTimeSource {
    <init>(kotlin.time.DurationUnit);
}
-keep,allowobfuscation interface kotlin.time.TimeSource$WithComparableMarks
-keep,allowobfuscation class kotlinx.coroutines.CancellableContinuationKt {
    void disposeOnCancellation(kotlinx.coroutines.CancellableContinuation, kotlinx.coroutines.DisposableHandle);
}
-keep,allowobfuscation class kotlinx.coroutines.DebugKt {
    boolean getRECOVER_STACK_TRACES();
}
-keep,allowobfuscation class kotlinx.coroutines.ExecutorsKt {
    kotlinx.coroutines.CoroutineDispatcher from(java.util.concurrent.Executor);
}
-keep,allowobfuscation class kotlinx.coroutines.YieldContext$Key
-keep,allowobfuscation class kotlinx.coroutines.YieldKt {
    java.lang.Object yield(kotlin.coroutines.Continuation);
}
-keep,allowobfuscation class kotlinx.coroutines.debug.internal.DebugProbesImpl {
    void dumpCoroutines(java.io.PrintStream);
    void install$kotlinx_coroutines_core();
    boolean isInstalled$kotlinx_coroutines_debug();
    void uninstall$kotlinx_coroutines_core();
    kotlinx.coroutines.debug.internal.DebugProbesImpl INSTANCE;
}
-keep,allowobfuscation class kotlinx.coroutines.internal.ExceptionSuccessfullyProcessed {
    kotlinx.coroutines.internal.ExceptionSuccessfullyProcessed INSTANCE;
}
-keep,allowobfuscation class kotlinx.coroutines.internal.MainDispatchersKt {
    boolean isMissing(kotlinx.coroutines.MainCoroutineDispatcher);
    kotlinx.coroutines.MainCoroutineDispatcher tryCreateDispatcher(kotlinx.coroutines.internal.MainDispatcherFactory, java.util.List);
}
-keep,allowobfuscation class kotlinx.coroutines.internal.MissingMainCoroutineDispatcherFactory {
    kotlinx.coroutines.internal.MissingMainCoroutineDispatcherFactory INSTANCE;
}
-keep,allowobfuscation interface kotlinx.coroutines.internal.ThreadSafeHeapNode
-keep,allowobfuscation class kotlinx.coroutines.selects.OnTimeoutKt {
    void onTimeout-8Mi8wO0(kotlinx.coroutines.selects.SelectBuilder, long, kotlin.jvm.functions.Function1);
}
-keep,allowobfuscation interface kotlinx.coroutines.selects.SelectBuilder {
    void invoke(kotlinx.coroutines.selects.SelectClause0, kotlin.jvm.functions.Function1);
    void invoke(kotlinx.coroutines.selects.SelectClause1, kotlin.jvm.functions.Function2);
}
-keep,allowobfuscation interface kotlinx.coroutines.selects.SelectClause1
-keep,allowobfuscation class kotlinx.coroutines.selects.SelectImplementation {
    <init>(kotlin.coroutines.CoroutineContext);
    java.lang.Object doSelect(kotlin.coroutines.Continuation);
}

# Members removed, renamed without an applicable external mapping, or changed
# incompatibly on target classes that survive shrinking.
-keep,allowobfuscation class androidx.compose.runtime.Composer$Companion {
    java.lang.Object getEmpty();
}
-keep,allowobfuscation class androidx.compose.runtime.ComposerKt {
    boolean isTraceInProgress();
    void traceEventEnd();
}
-keep,allowobfuscation class androidx.compose.runtime.Recomposer {
    boolean getHasPendingWork();
}
-keep,allowobfuscation class androidx.compose.runtime.saveable.SaveableStateRegistryKt {
    androidx.compose.runtime.ProvidableCompositionLocal getLocalSaveableStateRegistry();
}
-keep,allowobfuscation class androidx.compose.runtime.snapshots.Snapshot {
    boolean hasPendingChanges();
}
-keep,allowobfuscation class androidx.compose.ui.geometry.Offset {
    long unbox-impl();
}
-keep,allowobfuscation class androidx.compose.ui.geometry.Rect {
    float getBottom();
    float getLeft();
    float getRight();
    float getTop();
}
-keep,allowobfuscation class androidx.compose.ui.input.key.Key {
    long unbox-impl();
}
-keep,allowobfuscation class androidx.compose.ui.layout.Placeable {
    int getHeight();
    int getWidth();
}
-keep,allowobfuscation class androidx.compose.ui.node.ComposeUiNode$Companion {
    kotlin.jvm.functions.Function1 getApplyOnDeactivatedNodeAssertion();
    kotlin.jvm.functions.Function0 getConstructor();
    kotlin.jvm.functions.Function2 getSetCompositeKeyHash();
    kotlin.jvm.functions.Function2 getSetMeasurePolicy();
    kotlin.jvm.functions.Function2 getSetModifier();
    kotlin.jvm.functions.Function2 getSetResolvedCompositionLocals();
}
-keep,allowobfuscation interface androidx.compose.ui.node.RootForTest {
    androidx.compose.ui.semantics.SemanticsOwner getSemanticsOwner();
}
-keep,allowobfuscation class androidx.compose.ui.platform.AndroidCompositionLocals_androidKt {
    androidx.compose.runtime.ProvidableCompositionLocal getLocalConfiguration();
    androidx.compose.runtime.ProvidableCompositionLocal getLocalContext();
}
-keep,allowobfuscation class androidx.compose.ui.platform.CompositionLocalsKt {
    androidx.compose.runtime.ProvidableCompositionLocal getLocalDensity();
    androidx.compose.runtime.ProvidableCompositionLocal getLocalFontFamilyResolver();
    androidx.compose.runtime.ProvidableCompositionLocal getLocalLayoutDirection();
    androidx.compose.runtime.ProvidableCompositionLocal getLocalProvidableLocaleList();
    androidx.compose.runtime.ProvidableCompositionLocal getLocalWindowInfo();
}
-keep,allowobfuscation interface androidx.compose.ui.platform.ViewConfiguration {
    long getDoubleTapMinTimeMillis();
}
# ViewRootForTest is already retained as a complete exact owner above. Its
# synthesized method mapping is not applicable to the separately minified APK,
# so this one interface entry point must retain its source owner and name.
-keep interface androidx.compose.ui.platform.ViewRootForTest {
    void measureAndLayoutForTest();
}
-keep,allowobfuscation interface androidx.compose.ui.platform.WindowInfo {
    int getKeyboardModifiers-k7X9c1A();
    boolean isWindowFocused();
}
-keep,allowobfuscation class androidx.compose.ui.semantics.AccessibilityAction {
    kotlin.Function getAction();
}
-keep,allowobfuscation class androidx.compose.ui.semantics.ScrollAxisRange {
    kotlin.jvm.functions.Function0 getMaxValue();
    boolean getReverseScrolling();
    kotlin.jvm.functions.Function0 getValue();
}
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsActions {
    androidx.compose.ui.semantics.SemanticsPropertyKey getCustomActions();
    androidx.compose.ui.semantics.SemanticsPropertyKey getGetTextLayoutResult();
    androidx.compose.ui.semantics.SemanticsPropertyKey getInsertTextAtCursor();
    androidx.compose.ui.semantics.SemanticsPropertyKey getOnClick();
    androidx.compose.ui.semantics.SemanticsPropertyKey getOnImeAction();
    androidx.compose.ui.semantics.SemanticsPropertyKey getRequestFocus();
    androidx.compose.ui.semantics.SemanticsPropertyKey getScrollBy();
    androidx.compose.ui.semantics.SemanticsPropertyKey getScrollToIndex();
    androidx.compose.ui.semantics.SemanticsPropertyKey getSetSelection();
    androidx.compose.ui.semantics.SemanticsPropertyKey getSetText();
}
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsConfiguration {
    boolean isClearingSemantics();
    boolean isMergingSemanticsOfDescendants();
}
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsNode {
    java.util.List getChildren();
    int getId();
    androidx.compose.ui.layout.LayoutInfo getLayoutInfo();
    long getPositionInRoot-F1C5BW0();
    long getPositionInWindow-F1C5BW0();
    androidx.compose.ui.node.RootForTest getRoot();
    long getSize-YbymL2g();
    boolean isRoot();
}
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsOwner {
    androidx.compose.ui.semantics.SemanticsNode getRootSemanticsNode();
}
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsProperties {
    androidx.compose.ui.semantics.SemanticsPropertyKey getContentDescription();
    androidx.compose.ui.semantics.SemanticsPropertyKey getDisabled();
    androidx.compose.ui.semantics.SemanticsPropertyKey getEditableText();
    androidx.compose.ui.semantics.SemanticsPropertyKey getFocused();
    androidx.compose.ui.semantics.SemanticsPropertyKey getHeading();
    androidx.compose.ui.semantics.SemanticsPropertyKey getHideFromAccessibility();
    androidx.compose.ui.semantics.SemanticsPropertyKey getHorizontalScrollAxisRange();
    androidx.compose.ui.semantics.SemanticsPropertyKey getImeAction();
    androidx.compose.ui.semantics.SemanticsPropertyKey getIndexForKey();
    androidx.compose.ui.semantics.SemanticsPropertyKey getInputText();
    androidx.compose.ui.semantics.SemanticsPropertyKey getIsDialog();
    androidx.compose.ui.semantics.SemanticsPropertyKey getIsEditable();
    androidx.compose.ui.semantics.SemanticsPropertyKey getIsPopup();
    androidx.compose.ui.semantics.SemanticsPropertyKey getLinkTestMarker();
    androidx.compose.ui.semantics.SemanticsPropertyKey getProgressBarRangeInfo();
    androidx.compose.ui.semantics.SemanticsPropertyKey getSelected();
    androidx.compose.ui.semantics.SemanticsPropertyKey getStateDescription();
    androidx.compose.ui.semantics.SemanticsPropertyKey getTestTag();
    androidx.compose.ui.semantics.SemanticsPropertyKey getText();
    androidx.compose.ui.semantics.SemanticsPropertyKey getToggleableState();
    androidx.compose.ui.semantics.SemanticsPropertyKey getVerticalScrollAxisRange();
}
-keep,allowobfuscation class androidx.compose.ui.semantics.SemanticsPropertyKey {
    java.lang.String getName();
}
-keep,allowobfuscation class androidx.compose.ui.text.AnnotatedString {
    java.util.List getParagraphStyles();
    java.util.List getSpanStyles();
    java.lang.String getText();
}
-keep,allowobfuscation class androidx.compose.ui.text.AnnotatedString$Range {
    int getEnd();
    int getStart();
}
-keep,allowobfuscation class androidx.compose.ui.text.TextLayoutInput {
    androidx.compose.ui.text.AnnotatedString getText();
}
-keep,allowobfuscation class androidx.compose.ui.text.TextLayoutResult {
    androidx.compose.ui.text.TextLayoutInput getLayoutInput();
}
-keep,allowobfuscation class androidx.compose.ui.text.intl.Locale {
    java.lang.String toLanguageTag();
}
-keep,allowobfuscation class androidx.compose.ui.text.intl.LocaleList {
    java.util.List getLocaleList();
}
-keep,allowobfuscation class androidx.compose.ui.unit.Constraints {
    long unbox-impl();
}
-keep interface androidx.compose.ui.unit.FontScaling {
    float toDp-GaN1DYA(long);
    long toSp-0xMU5do(float);
}
-keep,allowobfuscation class androidx.compose.ui.unit.Dp {
    float unbox-impl();
}
-keep,allowobfuscation class androidx.compose.ui.unit.DpSize {
    long unbox-impl();
}
-keep,allowobfuscation class androidx.compose.ui.unit.IntSize {
    long unbox-impl();
}
-keep,allowobfuscation class androidx.core.os.LocaleListCompat {
    int size();
}
-keep,allowobfuscation class com.runanywhere.runanywhereai.ui.navigation.Vision {
    boolean getOpenLiveCamera();
}
-keep,allowobfuscation class kotlin.collections.AbstractIterator {
    <init>();
    void done();
    void setNext(java.lang.Object);
}
-keep,allowobfuscation class kotlin.collections.ArrayDeque {
    java.lang.Object removeFirstOrNull();
}
-keep,allowobfuscation class kotlin.collections.SetsKt__SetsKt {
    java.util.Set setOf(java.lang.Object[]);
}
-keep,allowobfuscation class kotlin.collections.SetsKt___SetsKt {
    java.util.Set emptySet();
}
# These synthesized Kotlin default/debug methods are absent from the externally
# applicable mapping; retain only their source member names. The
# existing exact-class rules keep their implementations while still allowing
# the class owners themselves to consume the target mapping.
-keepclassmembernames class kotlin.coroutines.ContinuationInterceptor$DefaultImpls {
    void releaseInterceptedContinuation(kotlin.coroutines.ContinuationInterceptor, kotlin.coroutines.Continuation);
}
-keepclassmembernames class kotlin.coroutines.jvm.internal.DebugProbesKt {
    void probeCoroutineSuspended(kotlin.coroutines.Continuation);
}
-keep,allowobfuscation class kotlin.jvm.internal.Ref$BooleanRef {
    <init>();
}
-keep,allowobfuscation class kotlin.jvm.internal.Ref$FloatRef {
    <init>();
}
-keep,allowobfuscation class kotlin.jvm.internal.Ref$ObjectRef {
    <init>();
}
-keep,allowobfuscation class kotlin.ranges.LongProgression {
    long getFirst();
    long getLast();
}
-keep,allowobfuscation interface kotlin.reflect.KClass {
    java.lang.String getSimpleName();
}
-keep,allowobfuscation class kotlin.time.Duration {
    kotlin.time.Duration box-impl(long);
    long getInWholeMilliseconds-impl(long);
    boolean isNegative-impl(long);
    long unbox-impl();
}
-keep,allowobfuscation class kotlinx.coroutines.AbstractCoroutine {
    <init>(kotlin.coroutines.CoroutineContext, boolean, boolean);
    void start(kotlinx.coroutines.CoroutineStart, java.lang.Object, kotlin.jvm.functions.Function2);
}
-keep,allowobfuscation interface kotlinx.coroutines.CancellableContinuation {
    void resume(java.lang.Object, kotlin.jvm.functions.Function1);
    void resumeUndispatched(kotlinx.coroutines.CoroutineDispatcher, java.lang.Object);
}
-keep,allowobfuscation class kotlinx.coroutines.CoroutineName {
    <init>(java.lang.String);
}
-keep,allowobfuscation class kotlinx.coroutines.DefaultExecutorKt {
    kotlinx.coroutines.Delay getDefaultDelay();
}
-keep,allowobfuscation class kotlinx.coroutines.Dispatchers {
    kotlinx.coroutines.CoroutineDispatcher getDefault();
}
-keep,allowobfuscation interface kotlinx.coroutines.Job {
    kotlinx.coroutines.DisposableHandle invokeOnCompletion$default(kotlinx.coroutines.Job, boolean, boolean, kotlin.jvm.functions.Function1, int, java.lang.Object);
}
-keep,allowobfuscation class kotlinx.coroutines.JobSupport {
    java.lang.Throwable getCompletionCause();
    java.lang.Throwable getCompletionExceptionOrNull();
    java.lang.String toString();
}
-keep,allowobfuscation interface kotlinx.coroutines.channels.ReceiveChannel {
    kotlinx.coroutines.selects.SelectClause1 getOnReceive();
    java.lang.Object receive(kotlin.coroutines.Continuation);
}
-keep,allowobfuscation class kotlinx.coroutines.internal.CoroutineExceptionHandlerImplKt {
    void ensurePlatformExceptionHandlerLoaded(kotlinx.coroutines.CoroutineExceptionHandler);
}
-keep,allowobfuscation class kotlinx.coroutines.internal.StackTraceRecoveryKt {
    java.lang.Throwable unwrapImpl(java.lang.Throwable);
}
-keep,allowobfuscation class kotlinx.coroutines.internal.ThreadSafeHeap {
    <init>();
    void addLast(kotlinx.coroutines.internal.ThreadSafeHeapNode);
    kotlinx.coroutines.internal.ThreadSafeHeapNode find(kotlin.jvm.functions.Function1);
    kotlinx.coroutines.internal.ThreadSafeHeapNode firstImpl();
    boolean isEmpty();
    boolean remove(kotlinx.coroutines.internal.ThreadSafeHeapNode);
    kotlinx.coroutines.internal.ThreadSafeHeapNode removeAtImpl(int);
    kotlinx.coroutines.internal.ThreadSafeHeapNode removeFirstOrNull();
}
-keep,allowobfuscation class kotlin.jvm.internal.StringCompanionObject {
    kotlin.jvm.internal.StringCompanionObject INSTANCE;
}
-keep,allowobfuscation class kotlinx.coroutines.YieldContext {
    kotlinx.coroutines.YieldContext$Key Key;
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
