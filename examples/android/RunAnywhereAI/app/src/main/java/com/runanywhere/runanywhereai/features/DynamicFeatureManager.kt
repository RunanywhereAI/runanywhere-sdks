package com.runanywhere.runanywhereai.features

import android.content.Context
import android.util.Log
import com.google.android.play.core.splitinstall.*
import com.google.android.play.core.splitinstall.model.SplitInstallSessionStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Manager for dynamic feature delivery and installation
 */
@Singleton
class DynamicFeatureManager @Inject constructor(
    private val context: Context
) {
    companion object {
        private const val TAG = "DynamicFeatureManager"
    }

    private val splitInstallManager = SplitInstallManagerFactory.create(context)
    private val listeners = mutableSetOf<FeatureInstallListener>()

    init {
        // Register for install state updates
        splitInstallManager.registerListener { state ->
            notifyListeners(state)
        }
    }

    /**
     * Get list of available dynamic features
     */
    suspend fun getAvailableFeatures(): List<DynamicFeature> = withContext(Dispatchers.IO) {
        listOf(
            DynamicFeature(
                name = "llamacpp",
                displayName = "llama.cpp Engine",
                description = "Native GGUF model inference with llama.cpp",
                sizeBytes = 50 * 1024 * 1024L, // 50MB
                requirements = FeatureRequirements(
                    minSdkVersion = 24,
                    requiredMemoryMB = 2048,
                    requiredStorageMB = 500,
                    requiredFeatures = listOf("android.hardware.ram"),
                    supportedAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64"),
                    description = "Native llama.cpp inference engine"
                ),
                isInstalled = isFeatureInstalled("llamacpp"),
                isSupported = checkFeatureSupport("llamacpp")
            ),
            DynamicFeature(
                name = "executorch",
                displayName = "ExecuTorch Engine",
                description = "PyTorch ExecuTorch with GPU acceleration",
                sizeBytes = 75 * 1024 * 1024L, // 75MB
                requirements = FeatureRequirements(
                    minSdkVersion = 26,
                    requiredMemoryMB = 1536,
                    requiredStorageMB = 300,
                    requiredFeatures = listOf("android.hardware.opengles.aep"),
                    supportedAbis = listOf("arm64-v8a", "armeabi-v7a"),
                    description = "PyTorch ExecuTorch inference engine"
                ),
                isInstalled = isFeatureInstalled("executorch"),
                isSupported = checkFeatureSupport("executorch")
            ),
            DynamicFeature(
                name = "mlcllm",
                displayName = "MLC-LLM Engine",
                description = "Machine Learning Compilation for LLMs",
                sizeBytes = 90 * 1024 * 1024L, // 90MB
                requirements = FeatureRequirements(
                    minSdkVersion = 25,
                    requiredMemoryMB = 3072,
                    requiredStorageMB = 800,
                    requiredFeatures = listOf("android.hardware.vulkan.level"),
                    supportedAbis = listOf("arm64-v8a"),
                    description = "MLC-LLM inference engine with TVM runtime"
                ),
                isInstalled = isFeatureInstalled("mlcllm"),
                isSupported = checkFeatureSupport("mlcllm")
            ),
            DynamicFeature(
                name = "onnxruntime",
                displayName = "ONNX Runtime",
                description = "Microsoft ONNX Runtime for cross-platform inference",
                sizeBytes = 60 * 1024 * 1024L, // 60MB
                requirements = FeatureRequirements(
                    minSdkVersion = 24,
                    requiredMemoryMB = 1024,
                    requiredStorageMB = 400,
                    requiredFeatures = listOf(),
                    supportedAbis = listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86"),
                    description = "ONNX Runtime inference engine"
                ),
                isInstalled = isFeatureInstalled("onnxruntime"),
                isSupported = checkFeatureSupport("onnxruntime")
            )
        )
    }

    /**
     * Install a dynamic feature
     */
    fun installFeature(featureName: String): Flow<FeatureInstallProgress> = callbackFlow {
        try {
            if (isFeatureInstalled(featureName)) {
                trySend(FeatureInstallProgress.Completed(featureName))
                close()
                return@callbackFlow
            }

            val request = SplitInstallRequest.newBuilder()
                .addModule(featureName)
                .build()

            splitInstallManager.startInstall(request)
                .addOnSuccessListener { sessionId ->
                    Log.d(TAG, "Started install for $featureName with session $sessionId")
                }
                .addOnFailureListener { exception ->
                    Log.e(TAG, "Failed to start install for $featureName", exception)
                    trySend(FeatureInstallProgress.Failed(featureName, exception.message ?: "Unknown error"))
                    close()
                }

            awaitClose {
                // Cleanup if needed
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error installing feature $featureName", e)
            trySend(FeatureInstallProgress.Failed(featureName, e.message ?: "Unknown error"))
            close()
        }
    }

    /**
     * Uninstall a dynamic feature
     */
    suspend fun uninstallFeature(featureName: String): Boolean = withContext(Dispatchers.IO) {
        try {
            if (!isFeatureInstalled(featureName)) {
                return@withContext true
            }

            val uninstallRequest = listOf(featureName)
            splitInstallManager.deferredUninstall(uninstallRequest)
                .addOnSuccessListener {
                    Log.d(TAG, "Successfully uninstalled $featureName")
                }
                .addOnFailureListener { exception ->
                    Log.e(TAG, "Failed to uninstall $featureName", exception)
                }

            true
        } catch (e: Exception) {
            Log.e(TAG, "Error uninstalling feature $featureName", e)
            false
        }
    }

    /**
     * Check if a feature is installed
     */
    fun isFeatureInstalled(featureName: String): Boolean {
        return splitInstallManager.installedModules.contains(featureName)
    }

    /**
     * Get installed features
     */
    fun getInstalledFeatures(): Set<String> {
        return splitInstallManager.installedModules
    }

    /**
     * Cancel ongoing installation
     */
    suspend fun cancelInstallation(sessionId: Int): Boolean = withContext(Dispatchers.IO) {
        try {
            splitInstallManager.cancelInstall(sessionId)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel installation $sessionId", e)
            false
        }
    }

    /**
     * Get session states for all active installations
     */
    suspend fun getSessionStates(): List<SplitInstallSessionState> = withContext(Dispatchers.IO) {
        try {
            val task = splitInstallManager.sessionStates
            if (task.isSuccessful) {
                task.result
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get session states", e)
            emptyList()
        }
    }

    /**
     * Add feature install listener
     */
    fun addListener(listener: FeatureInstallListener) {
        listeners.add(listener)
    }

    /**
     * Remove feature install listener
     */
    fun removeListener(listener: FeatureInstallListener) {
        listeners.remove(listener)
    }

    /**
     * Check device compatibility for feature
     */
    private fun checkFeatureSupport(featureName: String): Boolean {
        return when (featureName) {
            "llamacpp" -> checkLlamaCppSupport()
            "executorch" -> checkExecuTorchSupport()
            "mlcllm" -> checkMLCLLMSupport()
            "onnxruntime" -> checkONNXRuntimeSupport()
            else -> false
        }
    }

    private fun checkLlamaCppSupport(): Boolean {
        val memoryInfo = android.app.ActivityManager.MemoryInfo()
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        activityManager.getMemoryInfo(memoryInfo)

        val availableMemoryMB = memoryInfo.totalMem / (1024 * 1024)
        return availableMemoryMB >= 2048 // 2GB minimum
    }

    private fun checkExecuTorchSupport(): Boolean {
        val packageManager = context.packageManager
        val hasGPU = packageManager.hasSystemFeature("android.hardware.opengles.aep") ||
                    packageManager.hasSystemFeature("android.hardware.vulkan.level")

        val memoryInfo = android.app.ActivityManager.MemoryInfo()
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        activityManager.getMemoryInfo(memoryInfo)

        val availableMemoryMB = memoryInfo.totalMem / (1024 * 1024)
        return availableMemoryMB >= 1536 && hasGPU // 1.5GB minimum + GPU
    }

    private fun checkMLCLLMSupport(): Boolean {
        val packageManager = context.packageManager
        val hasVulkan = packageManager.hasSystemFeature("android.hardware.vulkan.level")

        val memoryInfo = android.app.ActivityManager.MemoryInfo()
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        activityManager.getMemoryInfo(memoryInfo)

        val availableMemoryMB = memoryInfo.totalMem / (1024 * 1024)
        return availableMemoryMB >= 3072 && hasVulkan && // 3GB minimum + Vulkan
               android.os.Build.SUPPORTED_64_BIT_ABIS.contains("arm64-v8a")
    }

    private fun checkONNXRuntimeSupport(): Boolean {
        val memoryInfo = android.app.ActivityManager.MemoryInfo()
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
        activityManager.getMemoryInfo(memoryInfo)

        val availableMemoryMB = memoryInfo.totalMem / (1024 * 1024)
        return availableMemoryMB >= 1024 // 1GB minimum
    }

    private fun notifyListeners(state: SplitInstallSessionState) {
        val progress = when (state.status()) {
            SplitInstallSessionStatus.PENDING -> {
                FeatureInstallProgress.Pending(state.moduleNames().first())
            }
            SplitInstallSessionStatus.DOWNLOADING -> {
                val downloadedBytes = state.bytesDownloaded()
                val totalBytes = state.totalBytesToDownload()
                val progressPercent = if (totalBytes > 0) {
                    (downloadedBytes.toFloat() / totalBytes * 100).toInt()
                } else 0

                FeatureInstallProgress.Downloading(
                    featureName = state.moduleNames().first(),
                    progress = progressPercent,
                    downloadedBytes = downloadedBytes,
                    totalBytes = totalBytes
                )
            }
            SplitInstallSessionStatus.INSTALLING -> {
                FeatureInstallProgress.Installing(state.moduleNames().first())
            }
            SplitInstallSessionStatus.INSTALLED -> {
                FeatureInstallProgress.Completed(state.moduleNames().first())
            }
            SplitInstallSessionStatus.FAILED -> {
                FeatureInstallProgress.Failed(
                    featureName = state.moduleNames().first(),
                    error = "Installation failed with error code: ${state.errorCode()}"
                )
            }
            SplitInstallSessionStatus.CANCELED -> {
                FeatureInstallProgress.Cancelled(state.moduleNames().first())
            }
            else -> {
                FeatureInstallProgress.Unknown(state.moduleNames().first(), state.status())
            }
        }

        listeners.forEach { listener ->
            try {
                listener.onProgressUpdate(progress)
            } catch (e: Exception) {
                Log.e(TAG, "Error notifying listener", e)
            }
        }
    }
}

// Data classes and interfaces

data class DynamicFeature(
    val name: String,
    val displayName: String,
    val description: String,
    val sizeBytes: Long,
    val requirements: FeatureRequirements,
    val isInstalled: Boolean,
    val isSupported: Boolean
)

data class FeatureRequirements(
    val minSdkVersion: Int,
    val requiredMemoryMB: Long,
    val requiredStorageMB: Long,
    val requiredFeatures: List<String>,
    val supportedAbis: List<String>,
    val description: String
)

sealed class FeatureInstallProgress {
    abstract val featureName: String

    data class Pending(override val featureName: String) : FeatureInstallProgress()

    data class Downloading(
        override val featureName: String,
        val progress: Int,
        val downloadedBytes: Long,
        val totalBytes: Long
    ) : FeatureInstallProgress()

    data class Installing(override val featureName: String) : FeatureInstallProgress()

    data class Completed(override val featureName: String) : FeatureInstallProgress()

    data class Failed(
        override val featureName: String,
        val error: String
    ) : FeatureInstallProgress()

    data class Cancelled(override val featureName: String) : FeatureInstallProgress()

    data class Unknown(
        override val featureName: String,
        val status: Int
    ) : FeatureInstallProgress()
}

interface FeatureInstallListener {
    fun onProgressUpdate(progress: FeatureInstallProgress)
}

// Extension functions

fun FeatureRequirements.isCompatibleWith(context: Context): Boolean {
    // Check SDK version
    if (android.os.Build.VERSION.SDK_INT < minSdkVersion) {
        return false
    }

    // Check memory
    val memoryInfo = android.app.ActivityManager.MemoryInfo()
    val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as android.app.ActivityManager
    activityManager.getMemoryInfo(memoryInfo)

    val availableMemoryMB = memoryInfo.totalMem / (1024 * 1024)
    if (availableMemoryMB < requiredMemoryMB) {
        return false
    }

    // Check ABI support
    val deviceAbis = android.os.Build.SUPPORTED_ABIS.toList()
    if (supportedAbis.none { it in deviceAbis }) {
        return false
    }

    // Check required features
    val packageManager = context.packageManager
    for (feature in requiredFeatures) {
        if (!packageManager.hasSystemFeature(feature)) {
            return false
        }
    }

    return true
}

fun DynamicFeature.formatSize(): String {
    val kb = sizeBytes / 1024.0
    val mb = kb / 1024.0
    val gb = mb / 1024.0

    return when {
        gb >= 1.0 -> "%.1f GB".format(gb)
        mb >= 1.0 -> "%.1f MB".format(mb)
        else -> "%.0f KB".format(kb)
    }
}
