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
        // Log first 300 chars of JSON body for debugging
        Log.d(TAG, "httpPostSync body (first 300 chars): ${jsonBody.take(300)}")

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
            if (!isSuccess) {
                Log.e(TAG, "httpPostSync error response: $responseBody")
            }

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
        // Try ActivityManager first (needs Context)
        val context = SecureStorageManager.getContext()
        if (context != null) {
            try {
                val activityManager = context.getSystemService(android.content.Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
                val memInfo = android.app.ActivityManager.MemoryInfo()
                activityManager?.getMemoryInfo(memInfo)
                if (memInfo.totalMem > 0) {
                    return memInfo.totalMem
                }
            } catch (e: Exception) {
                Log.w(TAG, "getTotalMemory via ActivityManager failed: ${e.message}")
            }
        }
        
        // Fallback: Read from /proc/meminfo (works without Context)
        try {
            val memInfoFile = java.io.File("/proc/meminfo")
            if (memInfoFile.exists()) {
                memInfoFile.bufferedReader().use { reader ->
                    val line = reader.readLine() // First line: MemTotal: ...
                    if (line != null && line.startsWith("MemTotal:")) {
                        val parts = line.split("\\s+".toRegex())
                        if (parts.size >= 2) {
                            val kB = parts[1].toLongOrNull() ?: 0L
                            return kB * 1024 // Convert KB to bytes
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "getTotalMemory via /proc/meminfo failed: ${e.message}")
        }
        
        // Last resort: Return a reasonable default for modern phones (4GB)
        return 4L * 1024 * 1024 * 1024
    }

    /**
     * Get available memory in bytes
     */
    @JvmStatic
    fun getAvailableMemory(): Long {
        // Try ActivityManager first (needs Context)
        val context = SecureStorageManager.getContext()
        if (context != null) {
            try {
                val activityManager = context.getSystemService(android.content.Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
                val memInfo = android.app.ActivityManager.MemoryInfo()
                activityManager?.getMemoryInfo(memInfo)
                if (memInfo.availMem > 0) {
                    return memInfo.availMem
                }
            } catch (e: Exception) {
                Log.w(TAG, "getAvailableMemory via ActivityManager failed: ${e.message}")
            }
        }
        
        // Fallback: Read from /proc/meminfo (works without Context)
        try {
            val memInfoFile = java.io.File("/proc/meminfo")
            if (memInfoFile.exists()) {
                memInfoFile.bufferedReader().use { reader ->
                    var line = reader.readLine()
                    while (line != null) {
                        if (line.startsWith("MemAvailable:")) {
                            val parts = line.split("\\s+".toRegex())
                            if (parts.size >= 2) {
                                val kB = parts[1].toLongOrNull() ?: 0L
                                return kB * 1024 // Convert KB to bytes
                            }
                        }
                        line = reader.readLine()
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "getAvailableMemory via /proc/meminfo failed: ${e.message}")
        }
        
        // Last resort: Return half of total as estimate
        return getTotalMemory() / 2
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

    /**
     * Get GPU family based on chip name
     * Infers GPU vendor from known chip manufacturers:
     * - Google Tensor/Pixel → Mali
     * - Samsung Exynos → Mali
     * - Qualcomm Snapdragon → Adreno
     * - MediaTek → Mali (mostly)
     * - HiSilicon Kirin → Mali
     *
     * Aligned with Kotlin SDK's CppBridgeDevice.getDefaultGPUFamily()
     */
    @JvmStatic
    fun getGPUFamily(): String {
        val chipName = getChipName().lowercase()
        val manufacturer = android.os.Build.MANUFACTURER.lowercase()
        
        return when {
            // Google Pixel codenames (all use Mali GPUs from Samsung/Google Tensor)
            chipName == "bluejay" -> "mali"      // Pixel 6a (Tensor)
            chipName == "oriole" -> "mali"       // Pixel 6 (Tensor)
            chipName == "raven" -> "mali"        // Pixel 6 Pro (Tensor)
            chipName == "cheetah" -> "mali"      // Pixel 7 (Tensor G2)
            chipName == "panther" -> "mali"      // Pixel 7 Pro (Tensor G2)
            chipName == "lynx" -> "mali"         // Pixel 7a (Tensor G2)
            chipName == "tangorpro" -> "mali"    // Pixel Tablet (Tensor G2)
            chipName == "shiba" -> "mali"        // Pixel 8 (Tensor G3)
            chipName == "husky" -> "mali"        // Pixel 8 Pro (Tensor G3)
            chipName == "akita" -> "mali"        // Pixel 8a (Tensor G3)
            chipName == "caiman" -> "mali"       // Pixel 9 (Tensor G4)
            chipName == "komodo" -> "mali"       // Pixel 9 Pro (Tensor G4)
            chipName == "comet" -> "mali"        // Pixel 9 Pro XL (Tensor G4)
            chipName == "tokay" -> "mali"        // Pixel 9 Pro Fold (Tensor G4)
            
            // Google Tensor generic patterns
            chipName.contains("tensor") -> "mali"
            chipName.contains("gs1") -> "mali"   // GS101 (Tensor)
            chipName.contains("gs2") -> "mali"   // GS201 (Tensor G2)
            chipName.contains("zuma") -> "mali"  // Zuma (Tensor G3)
            manufacturer == "google" -> "mali"   // Default for Google devices
            
            // Samsung Exynos uses Mali GPUs
            chipName.contains("exynos") -> "mali"
            chipName.startsWith("s5e") -> "mali" // Samsung internal naming (e.g., s5e8535)
            chipName.contains("samsung") -> "mali"
            
            // Qualcomm Snapdragon uses Adreno GPUs
            chipName.contains("snapdragon") -> "adreno"
            chipName.contains("qualcomm") -> "adreno"
            chipName.contains("sdm") -> "adreno" // SDM845, SDM855, etc.
            chipName.contains("sm8") -> "adreno" // SM8150, SM8250, etc.
            chipName.contains("sm7") -> "adreno" // SM7150, etc.
            chipName.contains("sm6") -> "adreno" // SM6150, etc.
            chipName.contains("msm") -> "adreno" // Older MSM chips
            chipName.contains("kona") -> "adreno" // Snapdragon 865
            chipName.contains("lahaina") -> "adreno" // Snapdragon 888
            chipName.contains("taro") -> "adreno" // Snapdragon 8 Gen 1
            chipName.contains("kalama") -> "adreno" // Snapdragon 8 Gen 2
            chipName.contains("pineapple") -> "adreno" // Snapdragon 8 Gen 3
            manufacturer == "qualcomm" -> "adreno"
            
            // MediaTek uses Mali GPUs (mostly)
            chipName.contains("mediatek") -> "mali"
            chipName.contains("mt6") -> "mali"   // MT6xxx series
            chipName.contains("mt8") -> "mali"   // MT8xxx series
            chipName.contains("dimensity") -> "mali"
            chipName.contains("helio") -> "mali"
            
            // HiSilicon Kirin uses Mali GPUs
            chipName.contains("kirin") -> "mali"
            chipName.contains("hisilicon") -> "mali"
            
            // Intel/x86 GPUs
            chipName.contains("intel") -> "intel"
            
            // NVIDIA (rare on mobile)
            chipName.contains("nvidia") -> "nvidia"
            chipName.contains("tegra") -> "nvidia"
            
            else -> "unknown"
        }
    }

    /**
     * Check if device is a tablet
     * Uses screen size configuration to determine form factor
     * Matches Swift SDK: device.userInterfaceIdiom == .pad
     */
    @JvmStatic
    fun isTablet(): Boolean {
        val context = SecureStorageManager.getContext()
        if (context != null) {
            val screenLayout = context.resources.configuration.screenLayout and 
                android.content.res.Configuration.SCREENLAYOUT_SIZE_MASK
            return screenLayout >= android.content.res.Configuration.SCREENLAYOUT_SIZE_LARGE
        }
        // Fallback: Check display metrics if context unavailable
        return false
    }
}

