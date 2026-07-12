package com.runanywhere.sdk.npu.qhexrt

import android.os.Build
import com.runanywhere.sdk.foundation.security.AndroidPlatformContext
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import java.io.File

internal object QHexRTSkelInstaller {
    private const val ASSET_ROOT = "runanywhere/qhexrt/skels"
    private const val ABI_ARM64 = "arm64-v8a"

    private val logger = SDKLogger("QHexRT")
    private val lock = Any()

    @Volatile
    private var installedPath: String? = null

    fun installIfAvailable(): String? {
        if (!AndroidPlatformContext.isInitialized()) {
            logger.warning("AndroidPlatformContext is not initialized; QHexRT skels are not installed")
            return null
        }
        if (Build.SUPPORTED_ABIS.none { it == ABI_ARM64 }) {
            return null
        }

        synchronized(lock) {
            installedPath?.let { path ->
                if (File(path).containsSkel()) {
                    return path
                }
            }

            val context = AndroidPlatformContext.applicationContext
            val assetDir = "$ASSET_ROOT/$ABI_ARM64"
            val skelNames =
                context.assets
                    .list(assetDir)
                    ?.filter { it.startsWith("libQnnHtpV") && it.endsWith("Skel.so") }
                    .orEmpty()
                    .sorted()
            if (skelNames.isEmpty()) {
                logger.warning("QHexRT DSP skel assets missing at $assetDir")
                return null
            }

            val outputDir =
                File(
                    context.codeCacheDir,
                    "runanywhere/qhexrt/skels/${context.applicationInfoVersionKey()}/$ABI_ARM64",
                )
            if (!outputDir.exists() && !outputDir.mkdirs()) {
                logger.warning("Unable to create QHexRT skel directory: ${outputDir.absolutePath}")
                return null
            }

            for (name in skelNames) {
                val assetPath = "$assetDir/$name"
                val output = File(outputDir, name)
                context.assets.open(assetPath).use { input ->
                    val expectedBytes = input.available().toLong()
                    if (output.isFile && output.length() == expectedBytes) {
                        return@use
                    }
                    val tmp = File(outputDir, "$name.tmp")
                    tmp.outputStream().use { input.copyTo(it) }
                    if (output.exists() && !output.delete()) {
                        logger.warning("Unable to replace QHexRT skel: ${output.absolutePath}")
                    }
                    if (!tmp.renameTo(output)) {
                        tmp.copyTo(output, overwrite = true)
                        tmp.delete()
                    }
                }
            }

            return outputDir.absolutePath.also {
                installedPath = it
                logger.info("QHexRT DSP skels installed to $it")
            }
        }
    }

    private fun File.containsSkel(): Boolean =
        isDirectory &&
            listFiles()?.any {
                it.name.startsWith("libQnnHtpV") && it.name.endsWith("Skel.so")
            } == true

    private fun android.content.Context.applicationInfoVersionKey(): String =
        runCatching {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            "${packageInfo.safeVersionCode()}-${packageInfo.lastUpdateTime}"
        }.getOrElse {
            "current"
        }

    @Suppress("DEPRECATION")
    private fun android.content.pm.PackageInfo.safeVersionCode(): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            longVersionCode
        } else {
            versionCode.toLong()
        }
}
