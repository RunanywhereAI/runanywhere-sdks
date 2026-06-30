package com.runanywhere.sdk.npu.qhexrt

import com.runanywhere.sdk.foundation.security.AndroidPlatformContext
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject

/**
 * Detected Hexagon NPU capability (pre-flight; no QNN load required).
 *
 * @property socModel  Vendor SoC model (e.g. "SM8750"); empty if unknown.
 * @property socId     /sys/devices/soc0/soc_id, or -1 when unavailable.
 * @property arch      Hexagon arch name ("v73", "v79", "v81", "unknown").
 * @property supported True when [arch] is one QHexRT runs on (v79/v81).
 */
data class NpuInfo(
    val socModel: String,
    val socId: Int,
    val arch: String,
    val supported: Boolean,
)

/**
 * QHexRT module — RunAnywhere's private Qualcomm Hexagon NPU backend.
 *
 * Runs prebuilt QNN context binaries on Snapdragon NPUs (v79/v81), serving LLM,
 * VLM, STT and TTS through the standard SDK APIs once registered. A thin wrapper
 * over C++ backend registration; all inference lives in the C++ commons layer.
 *
 * ## Pre-flight
 * ```kotlin
 * val npu = QHexRT.probeNpu()
 * if (!npu.supported) { /* warn; fall back to CPU engines */ }
 * ```
 *
 * ## Registration
 * ```kotlin
 * QHexRT.register()   // once during bootstrap, on a v79/v81 device
 * ```
 */
object QHexRT {
    private val logger = SDKLogger("QHexRT")

    /** Current version of the QHexRT module. */
    const val version = "0.1.0"

    /** Human-readable module name. */
    const val moduleName: String = "QHexRT"

    @Volatile
    private var isRegistered = false
    private val registrationMutex = Mutex()
    private val registrationLock = Any()

    /**
     * Probe the device's Hexagon NPU without loading QNN. Safe to call on any
     * device; returns [NpuInfo.supported] = false on unsupported/unknown parts.
     */
    fun probeNpu(): NpuInfo {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
        if (!QHexRTBridge.ensureNativeLibraryLoaded()) {
            logger.error("QHexRT native library unavailable; reporting unsupported NPU")
            return NpuInfo(socModel = "", socId = -1, arch = "unknown", supported = false)
        }
        return try {
            val json = JSONObject(QHexRTBridge.nativeProbeNpu())
            NpuInfo(
                socModel = json.optString("soc_model", ""),
                socId = json.optInt("soc_id", -1),
                arch = json.optString("arch", "unknown"),
                supported = json.optBoolean("supported", false),
            )
        } catch (e: Exception) {
            logger.error("Failed to parse NPU probe result: ${e.message}", throwable = e)
            NpuInfo(socModel = "", socId = -1, arch = "unknown", supported = false)
        }
    }

    /**
     * Register the QHexRT backend with the C++ plugin registry. Suspend so
     * callers can await module bootstrap from a coroutine scope. Safe to call on
     * unsupported devices — registration is rejected and the app falls back to
     * CPU engines.
     */
    suspend fun register() {
        registrationMutex.withLock { registerInternal() }
    }

    /** Unregister the QHexRT backend from the C++ registry. */
    suspend fun unregister() {
        registrationMutex.withLock {
            if (!isRegistered) return
            unregisterNative()
            isRegistered = false
            logger.info("QHexRT backend unregistered")
        }
    }

    private fun registerInternal() {
        if (isRegistered) {
            logger.debug("QHexRT already registered, returning")
            return
        }
        logger.info("Registering QHexRT backend with C++ registry...")
        val result = registerNative()
        // 0 = RAC_SUCCESS, -4 = RAC_ERROR_MODULE_ALREADY_REGISTERED.
        if (result != 0 && result != -4) {
            logger.error("QHexRT registration failed with code: $result (likely no v79/v81 NPU)")
            return
        }
        isRegistered = true
        logger.info("QHexRT backend registered successfully (LLM/VLM/STT/TTS)")
    }

    /**
     * Enable auto-registration. Access this property to trigger C++ backend
     * registration once.
     */
    val autoRegister: Unit by lazy {
        synchronized(registrationLock) { registerInternal() }
    }
}

private val logger = SDKLogger("QHexRT")

internal fun QHexRT.registerNative(): Int {
    RunAnywhereBridge.ensureNativeLibraryLoaded()
    if (!QHexRTBridge.ensureNativeLibraryLoaded()) {
        logger.error("Failed to load QHexRT native library")
        throw UnsatisfiedLinkError("Failed to load QHexRT native library")
    }
    configureAdspLibraryPath()
    return QHexRTBridge.nativeRegister()
}

/**
 * QNN loads Hexagon DSP skels (e.g. libQnnHtpV81Skel.so) over FastRPC. The skels
 * ship in the app's nativeLibraryDir; [libcdsprpc.so] must be visible to the
 * stub (declare `<uses-native-library android:name="libcdsprpc.so" />` in the
 * app manifest). Point ADSP_LIBRARY_PATH at the native lib dir before any QNN
 * context is created.
 */
private fun configureAdspLibraryPath() {
    if (!AndroidPlatformContext.isInitialized()) {
        logger.warning("AndroidPlatformContext not initialized — skipping ADSP_LIBRARY_PATH")
        return
    }
    runCatching {
        val nativeLibDir = AndroidPlatformContext.applicationContext.applicationInfo.nativeLibraryDir
            ?: return
        val existing = System.getenv("ADSP_LIBRARY_PATH").orEmpty()
        val path =
            listOf(nativeLibDir, existing, "/vendor/dsp/cdsp", "/vendor/lib/rfsa/adsp")
                .filter { it.isNotBlank() }
                .joinToString(";")
        android.system.Os.setenv("ADSP_LIBRARY_PATH", path, true)
        logger.info("ADSP_LIBRARY_PATH set to $path")
    }.onFailure { e ->
        logger.error("Failed to set ADSP_LIBRARY_PATH: ${e.message}", throwable = e)
    }
}

internal fun QHexRT.unregisterNative(): Int = QHexRTBridge.nativeUnregister()
