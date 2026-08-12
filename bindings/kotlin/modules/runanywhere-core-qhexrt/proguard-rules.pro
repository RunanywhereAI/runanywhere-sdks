# RunAnywhere Core QHexRT Module — ProGuard Rules

-keep class com.runanywhere.sdk.** { *; }
-keep interface com.runanywhere.sdk.** { *; }
-keep enum com.runanywhere.sdk.** { *; }

-keepclassmembers class com.runanywhere.sdk.** {
    <init>(...);
}

-keepclassmembers class com.runanywhere.sdk.** {
    public static ** Companion;
    public static ** INSTANCE;
    public static ** shared;
}

-keepnames class com.runanywhere.sdk.** { *; }
-keepnames interface com.runanywhere.sdk.** { *; }
-keepnames enum com.runanywhere.sdk.** { *; }

# Keep native methods (JNI symbol parity)
-keepclasseswithmembernames class * {
    native <methods>;
}

-keep class com.runanywhere.sdk.npu.qhexrt.** { *; }
-dontwarn com.runanywhere.sdk.npu.qhexrt.**
