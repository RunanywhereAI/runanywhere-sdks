package ai.runanywhere.sdk.qhexrt

import android.content.Context
import android.content.pm.PackageInfo
import android.os.Build
import android.util.Log
import java.io.File

/** Installs FastRPC DSP skels from APK assets into an app-private directory. */
internal object QHexRTSkelInstaller {
    private const val ASSET_ROOT = "runanywhere/qhexrt/skels"
    private const val ABI_ARM64 = "arm64-v8a"
    private const val LOG_TAG = "QHexRT"

    private val lock = Any()

    @Volatile
    private var installedPath: String? = null

    fun installIfAvailable(context: Context): String? {
        if (Build.SUPPORTED_ABIS.none { it == ABI_ARM64 }) return null

        synchronized(lock) {
            installedPath?.let { path ->
                if (File(path).containsSkel()) return path
            }

            val applicationContext = context.applicationContext
            val assetDir = "$ASSET_ROOT/$ABI_ARM64"
            val skelNames =
                applicationContext.assets
                    .list(assetDir)
                    ?.filter { it.startsWith("libQnnHtpV") && it.endsWith("Skel.so") }
                    .orEmpty()
                    .sorted()
            if (skelNames.isEmpty()) {
                Log.w(LOG_TAG, "QHexRT DSP skel assets missing at $assetDir")
                return null
            }

            val outputDir =
                File(
                    applicationContext.codeCacheDir,
                    "runanywhere/qhexrt/skels/${applicationContext.applicationInfoVersionKey()}/$ABI_ARM64",
                )
            if (!outputDir.exists() && !outputDir.mkdirs()) {
                Log.w(LOG_TAG, "Unable to create QHexRT skel directory: ${outputDir.absolutePath}")
                return null
            }

            for (name in skelNames) {
                val assetPath = "$assetDir/$name"
                val output = File(outputDir, name)
                applicationContext.assets.open(assetPath).use { input ->
                    val expectedBytes = input.available().toLong()
                    if (output.isFile && output.length() == expectedBytes) return@use

                    val temporary = File(outputDir, "$name.tmp")
                    temporary.outputStream().use { input.copyTo(it) }
                    if (output.exists() && !output.delete()) {
                        Log.w(LOG_TAG, "Unable to replace QHexRT skel: ${output.absolutePath}")
                    }
                    if (!temporary.renameTo(output)) {
                        temporary.copyTo(output, overwrite = true)
                        temporary.delete()
                    }
                }
            }

            return outputDir.absolutePath.also {
                installedPath = it
                Log.i(LOG_TAG, "QHexRT DSP skels installed to $it")
            }
        }
    }

    private fun File.containsSkel(): Boolean =
        isDirectory &&
            listFiles()?.any {
                it.name.startsWith("libQnnHtpV") && it.name.endsWith("Skel.so")
            } == true

    private fun Context.applicationInfoVersionKey(): String =
        runCatching {
            val packageInfo = packageManager.getPackageInfo(packageName, 0)
            "${packageInfo.safeVersionCode()}-${packageInfo.lastUpdateTime}"
        }.getOrElse {
            "current"
        }

    @Suppress("DEPRECATION")
    private fun PackageInfo.safeVersionCode(): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            longVersionCode
        } else {
            versionCode.toLong()
        }
}
