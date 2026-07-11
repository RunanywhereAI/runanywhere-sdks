package com.margelo.nitro.runanywhere.qhexrt

import android.content.Context
import android.os.Build
import com.margelo.nitro.runanywhere.SDKLogger
import java.io.File

internal object QHexRTSkelInstaller {
    private const val ASSET_ROOT = "runanywhere/qhexrt/skels"
    private const val ABI_ARM64 = "arm64-v8a"

    private val log = SDKLogger("NPU.QHexRT")
    private val lock = Any()

    @Volatile
    private var installedPath: String? = null

    fun install(context: Context): String? {
        if (Build.SUPPORTED_ABIS.none { it == ABI_ARM64 }) {
            return null
        }

        synchronized(lock) {
            installedPath?.let { path ->
                if (File(path).containsSkel()) {
                    return path
                }
            }

            val assetDirectory = "$ASSET_ROOT/$ABI_ARM64"
            val skelNames =
                context.assets
                    .list(assetDirectory)
                    ?.filter { it.startsWith("libQnnHtpV") && it.endsWith("Skel.so") }
                    .orEmpty()
                    .sorted()
            if (skelNames.isEmpty()) {
                log.warning("QHexRT DSP skel assets missing at $assetDirectory")
                return null
            }

            val outputDirectory =
                File(
                    context.codeCacheDir,
                    "runanywhere/qhexrt/skels/${context.applicationVersionKey()}/$ABI_ARM64",
                )
            if (!outputDirectory.exists() && !outputDirectory.mkdirs()) {
                log.warning("Unable to create QHexRT skel directory: ${outputDirectory.absolutePath}")
                return null
            }

            for (name in skelNames) {
                val output = File(outputDirectory, name)
                context.assets.open("$assetDirectory/$name").use { input ->
                    val expectedBytes = input.available().toLong()
                    if (output.isFile && output.length() == expectedBytes) {
                        return@use
                    }

                    val temporary = File(outputDirectory, "$name.tmp")
                    temporary.outputStream().use { input.copyTo(it) }
                    if (output.exists() && !output.delete()) {
                        log.warning("Unable to replace QHexRT skel: ${output.absolutePath}")
                    }
                    if (!temporary.renameTo(output)) {
                        temporary.copyTo(output, overwrite = true)
                        temporary.delete()
                    }
                }
            }

            return outputDirectory.absolutePath.also { path ->
                installedPath = path
                log.info("QHexRT DSP skels installed to $path")
            }
        }
    }

    private fun File.containsSkel(): Boolean =
        isDirectory &&
            listFiles()?.any {
                it.name.startsWith("libQnnHtpV") && it.name.endsWith("Skel.so")
            } == true

    private fun Context.applicationVersionKey(): String =
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
