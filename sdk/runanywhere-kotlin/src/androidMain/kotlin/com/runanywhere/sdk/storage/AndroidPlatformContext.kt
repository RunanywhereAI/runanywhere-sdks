package com.runanywhere.sdk.storage

import android.content.Context
import android.util.Log
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatformAdapter
import com.runanywhere.sdk.foundation.bridge.extensions.setContext
import com.runanywhere.sdk.security.AndroidSecureStorage
import java.io.File

/**
 * Android-specific context holder - should be initialized by the app
 * This is shared across all Android platform implementations
 */
object AndroidPlatformContext {
    private var _applicationContext: Context? = null

    val applicationContext: Context
        get() =
            _applicationContext ?: throw IllegalStateException(
                "AndroidPlatformContext must be initialized with Context before use",
            )

    fun initialize(context: Context) {
        _applicationContext = context.applicationContext
        // Also initialize secure storage so DeviceIdentity can access it
        AndroidSecureStorage.initialize(context.applicationContext)

        // Initialize CppBridgePlatformAdapter with context for persistent secure storage
        // This ensures device ID and registration status persist across app restarts
        CppBridgePlatformAdapter.setContext(context.applicationContext)

        // Stage Mozilla's CA bundle from APK assets onto the filesystem so the
        // mbedTLS-backed libcurl in librac_commons can verify HTTPS peers.
        // Cached path is pushed to native once CppBridge.initialize() loads
        // the JNI library and registers the platform adapter.
        stageCaBundle(context.applicationContext)

        // Debug-build escape hatch: mbedTLS rejects portions of the bundled
        // Mozilla cacert.pem (CURLE_SSL_CACERT_BADFILE = 77), which blocks all
        // HTTPS in a fresh `.debug` install. Disable peer/host verification on
        // debuggable APKs so model downloads can proceed; release builds (where
        // FLAG_DEBUGGABLE is not set) leave verification enforced.
        val isDebuggable = (
            context.applicationContext.applicationInfo.flags and
                android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE
        ) != 0
        if (isDebuggable) {
            Log.i(
                "AndroidPlatformContext",
                "Debuggable APK detected — disabling native TLS verification (debug-only escape hatch)",
            )
        }
        CppBridgePlatformAdapter.setSkipTlsVerification(isDebuggable)

        // Set up the model path provider for CppBridgeModelPaths
        // This ensures models are stored in the app's internal storage on Android
        CppBridgeModelPaths.pathProvider =
            object : CppBridgeModelPaths.ModelPathProvider {
                override fun getFilesDirectory(): String {
                    return context.applicationContext.filesDir.absolutePath
                }

                override fun getCacheDirectory(): String {
                    return context.applicationContext.cacheDir.absolutePath
                }

                override fun getExternalStorageDirectory(): String? {
                    return context.applicationContext.getExternalFilesDir(null)?.absolutePath
                }

                override fun isPathWritable(path: String): Boolean {
                    return try {
                        val file = java.io.File(path)
                        file.canWrite() || (file.mkdirs() && file.canWrite())
                    } catch (e: Exception) {
                        false
                    }
                }
            }
    }

    fun isInitialized(): Boolean = _applicationContext != null

    /**
     * Get the application context (alias for applicationContext for compatibility)
     */
    fun getContext(): Context = applicationContext

    private const val CA_BUNDLE_ASSET_NAME = "cacert.pem"
    private const val CA_BUNDLE_FILE_NAME = "cacert.pem"

    private fun stageCaBundle(context: Context) {
        val target = File(context.filesDir, CA_BUNDLE_FILE_NAME)
        try {
            // Always overwrite — cheap (~226 KB), and avoids stale bundles if
            // the SDK ships an updated cacert.pem in a future release.
            context.assets.open(CA_BUNDLE_ASSET_NAME).use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            Log.i("AndroidPlatformContext", "Staged CA bundle: ${target.absolutePath} (${target.length()} bytes)")
            CppBridgePlatformAdapter.setCaBundlePath(target.absolutePath)
        } catch (e: Exception) {
            Log.e("AndroidPlatformContext", "Failed to stage CA bundle from assets: ${e.message}", e)
        }
    }
}
