# RunAnywhere AI - ProGuard Rules

# Keep line numbers for crash reporting
-keepattributes SourceFile,LineNumberTable

# RunAnywhere SDK - keep all (uses JNI and dynamic registration)
-keep class com.runanywhere.sdk.** { *; }
-keep interface com.runanywhere.sdk.** { *; }
-keep enum com.runanywhere.sdk.** { *; }
-keepclassmembers class com.runanywhere.sdk.** {
    <init>(...);
}

# Native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# Compose
-dontwarn androidx.compose.**

# ViewModel
-keep class * extends androidx.lifecycle.ViewModel { *; }

# Enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Parcelable
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
