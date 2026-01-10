/**
 * PlatformAdapterBridge.kt
 *
 * JNI bridge for platform-specific operations (secure storage).
 * Called from C++ via JNI.
 *
 * Reference: sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/security/SecureStorage.kt
 */

package com.margelo.nitro.runanywhere

import android.util.Log

/**
 * JNI bridge that C++ code calls for platform operations.
 * All methods are static and called via JNI from InitBridge.cpp
 */
object PlatformAdapterBridge {
    private const val TAG = "PlatformAdapterBridge"

    /**
     * Called from C++ to set a secure value
     */
    @JvmStatic
    fun secureSet(key: String, value: String): Boolean {
        Log.d(TAG, "secureSet key=$key")
        return SecureStorageManager.set(key, value)
    }

    /**
     * Called from C++ to get a secure value
     */
    @JvmStatic
    fun secureGet(key: String): String? {
        Log.d(TAG, "secureGet key=$key")
        return SecureStorageManager.get(key)
    }

    /**
     * Called from C++ to delete a secure value
     */
    @JvmStatic
    fun secureDelete(key: String): Boolean {
        Log.d(TAG, "secureDelete key=$key")
        return SecureStorageManager.delete(key)
    }

    /**
     * Called from C++ to check if key exists
     */
    @JvmStatic
    fun secureExists(key: String): Boolean {
        return SecureStorageManager.exists(key)
    }

    /**
     * Called from C++ to get persistent device UUID
     */
    @JvmStatic
    fun getPersistentDeviceUUID(): String {
        Log.d(TAG, "getPersistentDeviceUUID")
        return SecureStorageManager.getPersistentDeviceUUID()
    }

    // ========================================================================
    // HTTP POST for Device Registration (Synchronous)
    // Matches Kotlin SDK's CppBridgeDevice.httpPost
    // ========================================================================

    /**
     * HTTP response data class
     */
    data class HttpResponse(
        val success: Boolean,
        val statusCode: Int,
        val responseBody: String?,
        val errorMessage: String?
    )

    /**
     * Synchronous HTTP POST for device registration
     * Called from C++ device manager callbacks via JNI
     *
     * @param url Full URL to POST to
     * @param jsonBody JSON body string
     * @param supabaseKey Supabase API key (for dev mode, can be null)
     * @return HttpResponse with result
     */
    @JvmStatic
    fun httpPostSync(url: String, jsonBody: String, supabaseKey: String?): HttpResponse {
        Log.d(TAG, "httpPostSync to: $url")

        // For Supabase device registration, add ?on_conflict=device_id for UPSERT
        // This matches Swift's HTTPService.swift logic
        var finalUrl = url
        if (url.contains("/rest/v1/sdk_devices") && !url.contains("on_conflict=")) {
            val separator = if (url.contains("?")) "&" else "?"
            finalUrl = "$url${separator}on_conflict=device_id"
            Log.d(TAG, "Added on_conflict for UPSERT: $finalUrl")
        }

        return try {
            val urlConnection = java.net.URL(finalUrl).openConnection() as java.net.HttpURLConnection
            urlConnection.requestMethod = "POST"
            urlConnection.connectTimeout = 30000
            urlConnection.readTimeout = 30000
            urlConnection.doOutput = true

            // Headers
            urlConnection.setRequestProperty("Content-Type", "application/json")
            urlConnection.setRequestProperty("Accept", "application/json")

            // Supabase headers (for device registration UPSERT)
            if (!supabaseKey.isNullOrEmpty()) {
                urlConnection.setRequestProperty("apikey", supabaseKey)
                urlConnection.setRequestProperty("Authorization", "Bearer $supabaseKey")
                urlConnection.setRequestProperty("Prefer", "resolution=merge-duplicates")
            }

            // Write body
            urlConnection.outputStream.use { os ->
                os.write(jsonBody.toByteArray(Charsets.UTF_8))
            }

            val statusCode = urlConnection.responseCode
            val responseBody = try {
                urlConnection.inputStream.bufferedReader().use { it.readText() }
            } catch (e: Exception) {
                urlConnection.errorStream?.bufferedReader()?.use { it.readText() }
            }

            // 2xx or 409 (conflict/already exists) = success for device registration
            val isSuccess = statusCode in 200..299 || statusCode == 409

            Log.d(TAG, "httpPostSync completed: status=$statusCode success=$isSuccess")

            HttpResponse(
                success = isSuccess,
                statusCode = statusCode,
                responseBody = responseBody,
                errorMessage = if (!isSuccess) "HTTP $statusCode" else null
            )
        } catch (e: Exception) {
            Log.e(TAG, "httpPostSync error", e)
            HttpResponse(
                success = false,
                statusCode = 0,
                responseBody = null,
                errorMessage = e.message ?: "Unknown error"
            )
        }
    }

    // ========================================================================
    // Device Info (Synchronous)
    // For device registration callback which must be synchronous
    // ========================================================================

    /**
     * Get device model name (e.g., "Pixel 8 Pro")
     */
    @JvmStatic
    fun getDeviceModel(): String {
        return android.os.Build.MODEL
    }

    /**
     * Get OS version (e.g., "14")
     */
    @JvmStatic
    fun getOSVersion(): String {
        return android.os.Build.VERSION.RELEASE
    }

    /**
     * Get chip name (e.g., "Tensor G3")
     */
    @JvmStatic
    fun getChipName(): String {
        return android.os.Build.HARDWARE
    }

    /**
     * Get total memory in bytes
     */
    @JvmStatic
    fun getTotalMemory(): Long {
        val context = SecureStorageManager.getContext()
        return if (context != null) {
            val activityManager = context.getSystemService(android.content.Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
            val memInfo = android.app.ActivityManager.MemoryInfo()
            activityManager?.getMemoryInfo(memInfo)
            memInfo.totalMem
        } else {
            0L
        }
    }

    /**
     * Get available memory in bytes
     */
    @JvmStatic
    fun getAvailableMemory(): Long {
        val context = SecureStorageManager.getContext()
        return if (context != null) {
            val activityManager = context.getSystemService(android.content.Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
            val memInfo = android.app.ActivityManager.MemoryInfo()
            activityManager?.getMemoryInfo(memInfo)
            memInfo.availMem
        } else {
            0L
        }
    }

    /**
     * Get CPU core count
     */
    @JvmStatic
    fun getCoreCount(): Int {
        return Runtime.getRuntime().availableProcessors()
    }

    /**
     * Get architecture (e.g., "arm64-v8a")
     */
    @JvmStatic
    fun getArchitecture(): String {
        return android.os.Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
    }
}

