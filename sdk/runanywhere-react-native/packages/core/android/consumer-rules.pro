# Keep ArchiveUtility for JNI access
-keep class com.margelo.nitro.runanywhere.ArchiveUtility { *; }
-keepclassmembers class com.margelo.nitro.runanywhere.ArchiveUtility {
    public static *** extract(java.lang.String, java.lang.String);
}
