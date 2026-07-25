/**
 * PlatformAdapterBridge.kt
 *
 * JNI bridge for platform-specific operations (secure storage, device info,
 * and platform-adapter download fallback).
 * Called from C++ via JNI.
 *
 * Reference: sdk/runanywhere-kotlin/src/main/kotlin/com/runanywhere/sdk/security/SecureStorage.kt
 */

package com.margelo.nitro.runanywhere

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import com.margelo.nitro.NitroModules
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.atomic.AtomicBoolean

/**
 * JNI bridge that C++ code calls for platform operations.
 * All methods are static and called via JNI from InitBridge.cpp
 */
object PlatformAdapterBridge {
    private const val TAG = "PlatformAdapterBridge"

    private const val RAC_SUCCESS = 0
    private const val RAC_ERROR_INVALID_PARAMETER = -106
    private const val RAC_ERROR_DOWNLOAD_FAILED = -153
    private const val RAC_ERROR_CANCELLED = -380

    private data class HttpDownloadTask(
        val taskId: String,
        val url: String,
        val destinationPath: String,
        val cancelFlag: AtomicBoolean = AtomicBoolean(false),
    ) {
        @Volatile
        var connection: HttpURLConnection? = null

        @Volatile
        var future: Future<*>? = null
    }

    private val httpDownloadTasks = ConcurrentHashMap<String, HttpDownloadTask>()

    private val httpDownloadExecutor =
        Executors.newFixedThreadPool(2) { runnable ->
            Thread(runnable, "runanywhere-http-download").apply {
                isDaemon = true
            }
        }

    private fun applicationContext(): Context? {
        SecureStorageManager.getContext()?.let { return it }
        val context = NitroModules.applicationContext ?: return null
        SecureStorageManager.initialize(context.applicationContext)
        return SecureStorageManager.getContext()
    }

    /**
     * Called from C++ to set a secure value
     */
    @JvmStatic
    fun secureSet(key: String, value: String): Boolean {
        applicationContext()
        return SecureStorageManager.set(key, value)
    }

    /**
     * Called from C++ to get a secure value
     */
    @JvmStatic
    fun secureGet(key: String): String? {
        applicationContext()
        return SecureStorageManager.get(key)
    }

    /**
     * Called from C++ to delete a secure value
     */
    @JvmStatic
    fun secureDelete(key: String): Boolean {
        applicationContext()
        return SecureStorageManager.delete(key)
    }

    /**
     * Return the native app files directory used as the model-path base.
     */
    @JvmStatic
    fun getModelBaseDirectory(): String? {
        val context = applicationContext()
        val path = context?.filesDir?.absolutePath
        Log.d(TAG, "getModelBaseDirectory path=$path")
        return path
    }

    // ========================================================================
    // HTTP Download (Async, Platform Adapter Fallback)
    // ========================================================================

    /**
     * Start an HTTP download for RACommons platform-adapter-only callers.
     * Public RN model downloads use native C++ rac_http_download_execute.
     */
    @JvmStatic
    fun httpDownload(url: String, destinationPath: String, taskId: String): Int {
        if (url.isBlank() || destinationPath.isBlank() || taskId.isBlank()) {
            Log.e(TAG, "httpDownload invalid args (taskId=$taskId)")
            return RAC_ERROR_INVALID_PARAMETER
        }

        val task = HttpDownloadTask(taskId = taskId, url = url, destinationPath = destinationPath)
        if (httpDownloadTasks.putIfAbsent(taskId, task) != null) {
            Log.w(TAG, "httpDownload duplicate taskId=$taskId")
            return RAC_ERROR_INVALID_PARAMETER
        }

        return try {
            val future = httpDownloadExecutor.submit {
                performHttpDownload(task)
            }
            task.future = future
            RAC_SUCCESS
        } catch (e: Exception) {
            httpDownloadTasks.remove(taskId)
            Log.e(TAG, "httpDownload schedule failed: ${e.message}")
            RAC_ERROR_DOWNLOAD_FAILED
        }
    }

    /**
     * Cancel an HTTP download.
     */
    @JvmStatic
    fun httpDownloadCancel(taskId: String): Boolean {
        val task = httpDownloadTasks[taskId] ?: return false
        task.cancelFlag.set(true)
        task.connection?.disconnect()
        return true
    }

    private fun performHttpDownload(task: HttpDownloadTask) {
        var result = RAC_ERROR_DOWNLOAD_FAILED
        var finalPath: String? = null
        var tempFile: File? = null

        try {
            if (task.cancelFlag.get()) {
                result = RAC_ERROR_CANCELLED
                return
            }

            val connection = URL(task.url).openConnection() as HttpURLConnection
            task.connection = connection
            connection.instanceFollowRedirects = true
            connection.connectTimeout = 30_000
            connection.readTimeout = 60_000
            connection.requestMethod = "GET"
            connection.connect()

            val status = connection.responseCode
            if (status !in 200..299) {
                Log.e(TAG, "httpDownload failed status=$status url=${task.url}")
                result = RAC_ERROR_DOWNLOAD_FAILED
                return
            }

            val totalBytes = connection.contentLengthLong.let { if (it > 0) it else 0L }
            val destFile = File(task.destinationPath)
            val parentDir = destFile.parentFile
            parentDir?.mkdirs()
            val temp = if (parentDir != null) {
                File(parentDir, destFile.name + ".part")
            } else {
                File(destFile.path + ".part")
            }
            tempFile = temp
            if (temp.exists()) {
                temp.delete()
            }

            var downloaded = 0L
            var lastReported = 0L
            val reportThreshold = 256 * 1024L

            connection.inputStream.use { input ->
                FileOutputStream(temp).use { output ->
                    val buffer = ByteArray(8192)
                    while (true) {
                        if (task.cancelFlag.get()) {
                            result = RAC_ERROR_CANCELLED
                            return
                        }
                        val read = input.read(buffer)
                        if (read <= 0) break
                        output.write(buffer, 0, read)
                        downloaded += read
                        if (downloaded - lastReported >= reportThreshold) {
                            nativeHttpDownloadReportProgress(task.taskId, downloaded, totalBytes)
                            lastReported = downloaded
                        }
                    }
                }
            }

            if (task.cancelFlag.get()) {
                result = RAC_ERROR_CANCELLED
                return
            }

            if (temp.exists()) {
                if (destFile.exists()) {
                    destFile.delete()
                }
                val moved = temp.renameTo(destFile)
                if (!moved) {
                    temp.copyTo(destFile, overwrite = true)
                    temp.delete()
                }
            }

            nativeHttpDownloadReportProgress(task.taskId, downloaded, totalBytes)
            finalPath = destFile.absolutePath
            result = RAC_SUCCESS
        } catch (e: Exception) {
            result = if (task.cancelFlag.get()) {
                RAC_ERROR_CANCELLED
            } else {
                Log.e(TAG, "httpDownload failed for ${task.url}: ${e.message}")
                RAC_ERROR_DOWNLOAD_FAILED
            }
        } finally {
            task.connection?.disconnect()
            task.connection = null
            httpDownloadTasks.remove(task.taskId)

            if (result != RAC_SUCCESS) {
                tempFile?.let {
                    if (it.exists()) {
                        it.delete()
                    }
                }
            }

            nativeHttpDownloadReportComplete(task.taskId, result, finalPath)
        }
    }

    @JvmStatic
    private external fun nativeHttpDownloadReportProgress(
        taskId: String,
        downloadedBytes: Long,
        totalBytes: Long,
    ): Int

    @JvmStatic
    private external fun nativeHttpDownloadReportComplete(
        taskId: String,
        result: Int,
        downloadedPath: String?,
    ): Int

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
     * Get user-visible device name (Settings.Global.DEVICE_NAME on API 25+,
     * falling back to bluetooth_name, then "MANUFACTURER MODEL").
     */
    @JvmStatic
    fun getDeviceName(): String {
        val context = applicationContext()
        if (context != null) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                    Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
                        ?.takeIf { it.isNotBlank() }
                        ?.let { return it }
                }
                Settings.Secure.getString(context.contentResolver, "bluetooth_name")
                    ?.takeIf { it.isNotBlank() }
                    ?.let { return it }
            } catch (e: Exception) {
                Log.w(TAG, "getDeviceName failed: ${e.message}")
            }
        }
        return "${Build.MANUFACTURER} ${Build.MODEL}"
    }

    /**
     * Get battery level as 0.0..1.0, or -1.0 when unknown
     */
    @JvmStatic
    fun getBatteryLevel(): Float {
        val context = applicationContext() ?: return -1.0f
        return try {
            val batteryManager =
                context.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
                    ?: return -1.0f
            val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            if (level in 0..100) level / 100.0f else -1.0f
        } catch (e: Exception) {
            Log.w(TAG, "getBatteryLevel failed: ${e.message}")
            -1.0f
        }
    }

    /**
     * Get battery state: "charging", "full", "unplugged", or "" when unknown
     */
    @JvmStatic
    fun getBatteryState(): String {
        val context = applicationContext() ?: return ""
        return try {
            val intent = context.registerReceiver(
                null,
                IntentFilter(Intent.ACTION_BATTERY_CHANGED),
            ) ?: return ""
            when (
                intent.getIntExtra(
                    BatteryManager.EXTRA_STATUS,
                    BatteryManager.BATTERY_STATUS_UNKNOWN,
                )
            ) {
                BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
                BatteryManager.BATTERY_STATUS_FULL -> "full"
                BatteryManager.BATTERY_STATUS_DISCHARGING,
                BatteryManager.BATTERY_STATUS_NOT_CHARGING,
                -> "unplugged"
                else -> ""
            }
        } catch (e: Exception) {
            Log.w(TAG, "getBatteryState failed: ${e.message}")
            ""
        }
    }

    /**
     * Check if battery saver (low power mode) is enabled
     */
    @JvmStatic
    fun isLowPowerMode(): Boolean {
        val context = applicationContext() ?: return false
        return try {
            val powerManager =
                context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            powerManager?.isPowerSaveMode ?: false
        } catch (e: Exception) {
            Log.w(TAG, "isLowPowerMode failed: ${e.message}")
            false
        }
    }

    /**
     * Check if the SoC ships a dedicated NPU/DSP usable through NNAPI.
     * Mirrors HybridRunAnywhereDeviceInfo.hasNPU().
     */
    @JvmStatic
    fun hasNPU(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O_MR1) {
            return false
        }
        val hardware = Build.HARDWARE.lowercase()
        val soc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Build.SOC_MODEL.lowercase()
        } else {
            ""
        }
        return listOf(
            "qcom",
            "exynos",
            "tensor",
            "kirin",
            "dimensity",
            "mtk",
        ).any { hardware.contains(it) || soc.contains(it) }
    }

    /**
     * Get OS version (e.g., "14")
     */
    @JvmStatic
    fun getOSVersion(): String {
        return android.os.Build.VERSION.RELEASE
    }

    /**
     * Get chip name (e.g., "SM8750")
     */
    @JvmStatic
    fun getChipName(): String {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            val socModel = android.os.Build.SOC_MODEL
            if (!socModel.isNullOrEmpty() && socModel != "unknown") {
                return socModel
            }
        }
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

    // ========================================================================
    // App / Client Info
    // ========================================================================

    @JvmStatic
    fun getAppIdentifier(): String? {
        return applicationContext()?.packageName
    }

    @JvmStatic
    fun getAppName(): String? {
        val context = applicationContext() ?: return null
        return try {
            context.applicationInfo.loadLabel(context.packageManager).toString()
                .ifBlank { null }
        } catch (e: Exception) {
            Log.w(TAG, "getAppName failed: ${e.message}")
            null
        }
    }

    @JvmStatic
    fun getAppVersion(): String? {
        val context = applicationContext() ?: return null
        return try {
            readPackageInfo(context)?.versionName?.ifBlank { null }
        } catch (e: Exception) {
            Log.w(TAG, "getAppVersion failed: ${e.message}")
            null
        }
    }

    @JvmStatic
    fun getAppBuild(): String? {
        val context = applicationContext() ?: return null
        return try {
            readPackageInfo(context)?.let { readVersionCode(it).toString() }
        } catch (e: Exception) {
            Log.w(TAG, "getAppBuild failed: ${e.message}")
            null
        }
    }

    private fun readPackageInfo(context: Context): PackageInfo? {
        val packageManager = context.packageManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getPackageInfo(
                context.packageName,
                PackageManager.PackageInfoFlags.of(0),
            )
        } else {
            val method = PackageManager::class.java.getMethod(
                "getPackageInfo",
                String::class.java,
                Int::class.javaPrimitiveType,
            )
            method.invoke(packageManager, context.packageName, 0) as? PackageInfo
        }
    }

    private fun readVersionCode(packageInfo: PackageInfo): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            val field = PackageInfo::class.java.getField("versionCode")
            field.getInt(packageInfo).toLong()
        }
    }

    @JvmStatic
    fun getLocaleIdentifier(): String {
        return Locale.getDefault().toLanguageTag()
    }

    @JvmStatic
    fun getTimezoneIdentifier(): String {
        return TimeZone.getDefault().id
    }

    // ========================================================================
    // Directory Enumeration (Platform Adapter Slots)
    //
    // Cross-SDK parity with the Kotlin SDK sibling and Swift / Flutter /
    // Web. The C++
    // model-registry refresh path (rescan_local) and
    // rac_model_info_make_proto's is_downloaded probe for multi-file
    // artifacts read these via JNI from InitBridge.cpp.
    // ========================================================================

    /**
     * Directory entry surface mirroring `rac_directory_entry_t` field-for-field
     * so the C++ side can populate `rac_directory_entry_t` arrays via FieldID
     * reflection without an additional marshalling layer.
     */
    data class RacDirectoryEntry(
        val name: String,
        val isDir: Boolean,
        val sizeBytes: Long,
    )

    /**
     * Maximum entry name length (incl. NUL) per `RAC_DIRECTORY_ENTRY_NAME_MAX`.
     * Oversized entries are skipped per the truncation contract in
     * `rac_platform_adapter.h::rac_directory_entry_t::name`.
     */
    private const val DIRECTORY_ENTRY_NAME_MAX = 512

    /**
     * Enumerate directory entries via java.io.File.listFiles().
     *
     * @return Array of RacDirectoryEntry or null if the path does not exist /
     *         is not a directory. Oversized names (UTF-8 + NUL > 512) are
     *         filtered out with a single WARN summary; the C++ layer enforces
     *         the same contract defensively.
     */
    @JvmStatic
    fun fileListDirectory(dirPath: String): Array<RacDirectoryEntry>? {
        val dir = File(dirPath)
        if (!dir.exists() || !dir.isDirectory) {
            return null
        }
        val children = dir.listFiles() ?: return emptyArray()

        var skipped = 0
        val entries = ArrayList<RacDirectoryEntry>(children.size)
        for (child in children) {
            val name = child.name
            val utf8Bytes = name.toByteArray(Charsets.UTF_8)
            if (utf8Bytes.size + 1 > DIRECTORY_ENTRY_NAME_MAX) {
                skipped++
                continue
            }
            entries.add(
                RacDirectoryEntry(
                    name = name,
                    isDir = child.isDirectory,
                    sizeBytes = if (child.isFile) child.length() else 0L,
                ),
            )
        }
        if (skipped > 0) {
            Log.w(TAG, "fileListDirectory: skipped $skipped oversized entry name(s) in $dirPath")
        }
        return entries.toTypedArray()
    }

    /**
     * Cheap directory-probe used by rac_model_info_make_proto's is_downloaded
     * gating for multi-file artifacts.
     */
    @JvmStatic
    fun isNonEmptyDirectory(path: String): Boolean {
        val dir = File(path)
        if (!dir.exists() || !dir.isDirectory) {
            return false
        }
        val children = dir.list() ?: return false
        return children.isNotEmpty()
    }
}
