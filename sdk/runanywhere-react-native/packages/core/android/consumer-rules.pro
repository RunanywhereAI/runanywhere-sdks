# PlatformAdapterBridge is resolved by literal JNI class/method names in
# cpp-adapter.cpp. Keep only that exact bridge contract; the rest of the SDK
# remains available for ordinary R8 shrinking and obfuscation.
-keep,allowoptimization class com.margelo.nitro.runanywhere.PlatformAdapterBridge {
    public static boolean secureSet(java.lang.String, java.lang.String);
    public static java.lang.String secureGet(java.lang.String);
    public static boolean secureDelete(java.lang.String);
    public static java.lang.String getModelBaseDirectory();
    public static java.lang.String getDeviceModel();
    public static java.lang.String getOSVersion();
    public static java.lang.String getChipName();
    public static long getTotalMemory();
    public static long getAvailableMemory();
    public static int getCoreCount();
    public static java.lang.String getArchitecture();
    public static java.lang.String getGPUFamily();
    public static boolean isTablet();
    public static java.lang.String getAppIdentifier();
    public static java.lang.String getAppName();
    public static java.lang.String getAppVersion();
    public static java.lang.String getAppBuild();
    public static java.lang.String getLocaleIdentifier();
    public static java.lang.String getTimezoneIdentifier();
    public static int httpDownload(java.lang.String, java.lang.String, java.lang.String);
    public static boolean httpDownloadCancel(java.lang.String);
    public static com.margelo.nitro.runanywhere.PlatformAdapterBridge$RacDirectoryEntry[] fileListDirectory(java.lang.String);
    public static boolean isNonEmptyDirectory(java.lang.String);
    private static native int nativeHttpDownloadReportProgress(java.lang.String, long, long);
    private static native int nativeHttpDownloadReportComplete(java.lang.String, int, java.lang.String);
}

# InitBridge.cpp resolves this binary class name and its backing fields with
# FindClass/GetFieldID; access visibility does not matter to JNI.
-keep,allowoptimization class com.margelo.nitro.runanywhere.PlatformAdapterBridge$RacDirectoryEntry {
    java.lang.String name;
    boolean isDir;
    long sizeBytes;
}

# okhttp_transport_adapter.cpp resolves this exact transport class, methods,
# response types, and backing fields with FindClass/GetStaticMethodID/GetFieldID.
-keep,allowoptimization class com.runanywhere.sdk.httptransport.OkHttpHttpTransport {
    public static com.runanywhere.sdk.httptransport.OkHttpHttpTransport$HttpResponse executeRequest(java.lang.String, java.lang.String, java.lang.String[], byte[], long, boolean);
    public static com.runanywhere.sdk.httptransport.OkHttpHttpTransport$StreamResponse executeStreamingRequest(java.lang.String, java.lang.String, java.lang.String[], byte[], long, long, long, boolean);
    public static com.runanywhere.sdk.httptransport.OkHttpHttpTransport$StreamResponse executeResumeRequest(java.lang.String, java.lang.String, java.lang.String[], byte[], long, long, long, long, boolean);
    private static native boolean deliverChunkNative(long, long, byte[], int, long, long);
}

-keep,allowoptimization class com.runanywhere.sdk.httptransport.OkHttpHttpTransport$HttpResponse {
    int statusCode;
    java.lang.String[] headers;
    byte[] bodyBytes;
    java.lang.String errorMessage;
}

-keep,allowoptimization class com.runanywhere.sdk.httptransport.OkHttpHttpTransport$StreamResponse {
    int statusCode;
    java.lang.String[] headers;
    java.lang.String errorMessage;
    boolean cancelled;
}

# These exact native declarations bind to exported long-form JNI symbols in
# commons' okhttp_transport_adapter.cpp.
-keep,allowoptimization class com.runanywhere.sdk.native.bridge.RunAnywhereBridge {
    public static native int racHttpTransportRegisterOkHttp();
    public static native int racHttpTransportUnregisterOkHttp();
}
