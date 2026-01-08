package com.runanywhere.sdk.storage

import android.content.Context
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgePlatformAdapter
import com.runanywhere.sdk.security.AndroidSecureStorage

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
}
