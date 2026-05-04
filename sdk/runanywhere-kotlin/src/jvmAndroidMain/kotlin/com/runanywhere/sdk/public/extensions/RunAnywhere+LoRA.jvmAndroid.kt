/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for LoRA adapter management.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.DownloadProgress
import ai.runanywhere.proto.v1.DownloadStage
import ai.runanywhere.proto.v1.DownloadState
import ai.runanywhere.proto.v1.LoRAAdapterConfig
import ai.runanywhere.proto.v1.LoRAAdapterInfo
import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import ai.runanywhere.proto.v1.LoraCompatibilityResult
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDownload
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLoraProto
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLoraRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.native.bridge.NativeDownloadProgressListener
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.RunAnywhere
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import java.io.File
import java.net.URI
import java.util.concurrent.atomic.AtomicBoolean

private val loraLogger = SDKLogger("LoRA")

actual suspend fun RunAnywhere.loadLoraAdapter(config: LoRAAdapterConfig) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    loraLogger.info("Loading LoRA adapter: ${config.adapter_path} (scale=${config.scale})")
    CppBridgeLoraProto.load(config)
}

actual suspend fun RunAnywhere.removeLoraAdapter(path: String) {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    CppBridgeLoraProto.remove(LoRAAdapterConfig(adapter_path = path))
}

actual suspend fun RunAnywhere.clearLoraAdapters() {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    CppBridgeLoraProto.clear()
}

actual suspend fun RunAnywhere.getLoadedLoraAdapters(): List<LoRAAdapterInfo> {
    if (!isInitialized) {
        throw SDKException.notInitialized("SDK not initialized")
    }

    return CppBridgeLoraProto.getLoaded()
}

// MARK: - LoRA Compatibility Check
//
// Round 1 KOTLIN (G-B2 / Task 5): returns proto-generated type directly.

actual fun RunAnywhere.checkLoraCompatibility(loraPath: String): ai.runanywhere.proto.v1.LoraCompatibilityResult {
    if (!isInitialized) {
        return ai.runanywhere.proto.v1.LoraCompatibilityResult(
            is_compatible = false,
            error_message = "SDK not initialized",
        )
    }
    return CppBridgeLoraProto.compatibility(LoRAAdapterConfig(adapter_path = loraPath))
}

// MARK: - LoRA Adapter Catalog

actual fun RunAnywhere.registerLoraAdapter(entry: LoraAdapterCatalogEntry) {
    if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")
    CppBridgeLoraProto.register(entry)
}

actual fun RunAnywhere.loraAdaptersForModel(modelId: String): List<LoraAdapterCatalogEntry> {
    if (!isInitialized) return emptyList()
    return CppBridgeLoraRegistry.getForModel(modelId).map { it.toCatalogEntry() }
}

actual fun RunAnywhere.allRegisteredLoraAdapters(): List<LoraAdapterCatalogEntry> {
    if (!isInitialized) return emptyList()
    return CppBridgeLoraRegistry.getAll().map { it.toCatalogEntry() }
}

private fun CppBridgeLoraRegistry.LoraEntry.toCatalogEntry() =
    LoraAdapterCatalogEntry(
        id = id,
        name = name,
        description = description,
        url = downloadUrl,
        filename = filename,
        compatible_models = compatibleModelIds,
        size_bytes = fileSize,
        default_scale = defaultScale,
        checksum_sha256 = checksumSha256,
    )

// MARK: - LoRA Adapter Downloads

// Computed each time to avoid caching a wrong path captured before pathProvider is set
private fun getLoraDownloadDir(): File =
    File(CppBridgeModelPaths.getBaseDirectory(), "lora_adapters").also { it.mkdirs() }

actual fun RunAnywhere.downloadLoraAdapter(adapterId: String): Flow<DownloadProgress> =
    callbackFlow {
        if (!isInitialized) throw SDKException.notInitialized("SDK not initialized")

        val entry =
            CppBridgeLoraRegistry
                .getAll()
                .find { it.id == adapterId }
                ?: throw SDKException.download("LoRA adapter '$adapterId' not found in registry")

        val uri =
            try {
                URI(entry.downloadUrl)
            } catch (e: Exception) {
                throw SDKException.download("Invalid download URL for adapter '$adapterId': ${e.message}")
            }
        if (uri.scheme?.lowercase() != "https") {
            throw SDKException.download("Only HTTPS download URLs are allowed")
        }

        val (isNetworkAvailable, _) = CppBridgeDownload.checkNetworkStatus()
        if (!isNetworkAvailable) {
            throw SDKException.networkUnavailable(IllegalStateException("No internet connection"))
        }

        val loraDir = getLoraDownloadDir()
        val destFile = File(loraDir, entry.filename)
        val tmpFile = File(loraDir, "${entry.filename}.tmp")

        if (!destFile.canonicalPath.startsWith(loraDir.canonicalPath + File.separator)) {
            throw SDKException.download("Invalid adapter filename (path traversal): ${entry.filename}")
        }

        // Already downloaded — emit COMPLETED and return.
        if (destFile.exists() && destFile.length() > 0) {
            loraLogger.info("LoRA adapter already downloaded: ${destFile.absolutePath}")
            trySend(
                DownloadProgress(
                    model_id = adapterId,
                    stage = DownloadStage.DOWNLOAD_STAGE_COMPLETED,
                    bytes_downloaded = destFile.length(),
                    total_bytes = destFile.length(),
                    stage_progress = 1f,
                    state = DownloadState.DOWNLOAD_STATE_COMPLETED,
                ),
            )
            close()
            return@callbackFlow
        }

        trySend(
            DownloadProgress(
                model_id = adapterId,
                stage = DownloadStage.DOWNLOAD_STAGE_DOWNLOADING,
                bytes_downloaded = 0,
                total_bytes = entry.fileSize,
                stage_progress = 0f,
                state = DownloadState.DOWNLOAD_STATE_PENDING,
            ),
        )

        loraLogger.info("Starting LoRA download: ${entry.name} from ${entry.downloadUrl}")

        // v2 close-out Phase H: HTTP transport (HttpURLConnection) was
        // removed from Kotlin; commons' libcurl runner handles request,
        // redirects, TLS, range resume, and checksum. The Kotlin layer
        // just relays progress from the native callback into this flow.
        val cancellation = AtomicBoolean(false)
        val totalHint = entry.fileSize.takeIf { it > 0 } ?: 0L
        val listener =
            NativeDownloadProgressListener { bytes, total ->
                val effectiveTotal = if (total > 0) total else totalHint
                val progress =
                    if (effectiveTotal > 0) {
                        (bytes.toFloat() / effectiveTotal.toFloat()).coerceIn(0f, 1f)
                    } else {
                        0f
                    }
                trySend(
                    DownloadProgress(
                        model_id = adapterId,
                        stage = DownloadStage.DOWNLOAD_STAGE_DOWNLOADING,
                        bytes_downloaded = bytes,
                        total_bytes = effectiveTotal,
                        stage_progress = progress,
                        state = DownloadState.DOWNLOAD_STATE_DOWNLOADING,
                    ),
                )
                !cancellation.get()
            }

        val outStatus = IntArray(1)
        val rc =
            RunAnywhereBridge.racHttpDownloadExecute(
                url = entry.downloadUrl,
                destPath = tmpFile.absolutePath,
                expectedSha256Hex = entry.checksumSha256,
                resumeFromByte = 0L,
                timeoutMs = 120_000,
                listener = listener,
                outHttpStatus = outStatus,
            )

        if (rc != CppBridgeDownload.DownloadError.NONE) {
            runCatching { tmpFile.delete() }
            val errorName = CppBridgeDownload.DownloadError.getName(rc)
            throw SDKException.download(
                "LoRA download failed for '${entry.filename}': $errorName (http_status=${outStatus[0]})",
            )
        }

        // Promote .tmp → final filename (preserves the same atomic swap the
        // old HttpURLConnection path had).
        destFile.delete()
        if (!tmpFile.renameTo(destFile)) {
            tmpFile.copyTo(destFile, overwrite = true)
            tmpFile.delete()
        }

        // Validate GGUF magic bytes (matches iOS validation).
        val isValidGguf =
            destFile.inputStream().use { stream ->
                val bytes = ByteArray(4)
                if (stream.read(bytes) != 4) return@use false
                val magic =
                    (bytes[0].toUInt() and 0xFFu) or
                        ((bytes[1].toUInt() and 0xFFu) shl 8) or
                        ((bytes[2].toUInt() and 0xFFu) shl 16) or
                        ((bytes[3].toUInt() and 0xFFu) shl 24)
                magic == 0x46554747u
            }
        if (!isValidGguf) {
            destFile.delete()
            throw SDKException.download("Downloaded LoRA adapter is not a valid GGUF file: ${entry.filename}")
        }

        loraLogger.info("LoRA download completed: ${destFile.absolutePath}")
        trySend(
            DownloadProgress(
                model_id = adapterId,
                stage = DownloadStage.DOWNLOAD_STAGE_COMPLETED,
                bytes_downloaded = destFile.length(),
                total_bytes = destFile.length(),
                stage_progress = 1f,
                state = DownloadState.DOWNLOAD_STATE_COMPLETED,
            ),
        )

        awaitClose { cancellation.set(true) }
    }.flowOn(Dispatchers.IO)

actual fun RunAnywhere.loraAdapterLocalPath(adapterId: String): String? {
    if (!isInitialized) return null
    val entry = CppBridgeLoraRegistry.getAll().find { it.id == adapterId } ?: return null
    val loraDir = getLoraDownloadDir()
    val file = File(loraDir, entry.filename)
    if (!file.canonicalPath.startsWith(loraDir.canonicalPath + File.separator)) return null
    return if (file.exists() && file.length() > 0) file.absolutePath else null
}

actual fun RunAnywhere.deleteDownloadedLoraAdapter(adapterId: String): Boolean {
    if (!isInitialized) return false
    val path = loraAdapterLocalPath(adapterId) ?: return false
    return File(path).delete()
}

// ─────────────────────────────────────────────────────────────────────────────
// Round 1 KOTLIN (G-A7): canonical `RunAnywhere.lora.*` namespace actual.
//
// Routes through canonical `racLora*` JNI thunks. If the C++ side is missing
// (CPP-blocked), callers see UnsatisfiedLinkError at runtime — that's the
// C++ track's problem.
// ─────────────────────────────────────────────────────────────────────────────

actual class LoRA internal actual constructor() {
    actual suspend fun load(config: LoRAAdapterConfig): LoRAAdapterInfo =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.load(config)
        }

    actual suspend fun remove(adapterId: String): Unit =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.remove(LoRAAdapterConfig(adapter_path = adapterId, adapter_id = adapterId))
            Unit
        }

    actual suspend fun clear(): Unit =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.clear()
            Unit
        }

    actual suspend fun getLoaded(): List<LoRAAdapterInfo> =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.getLoaded()
        }

    actual suspend fun checkCompatibility(adapterId: String, modelId: String): LoraCompatibilityResult =
        withContext(Dispatchers.IO) {
            CppBridgeLoraProto.compatibility(LoRAAdapterConfig(adapter_path = adapterId, adapter_id = adapterId))
        }

    actual suspend fun register(config: LoRAAdapterConfig): Unit =
        withContext(Dispatchers.IO) {
            val resolvedId = config.adapter_id ?: config.adapter_path
            CppBridgeLoraProto.register(
                LoraAdapterCatalogEntry(
                    id = resolvedId,
                    name = resolvedId,
                    description = "",
                    url = "",
                    filename = config.adapter_path,
                    compatible_models = emptyList(),
                    size_bytes = 0L,
                    default_scale = config.scale,
                ),
            )
            Unit
        }

    actual suspend fun adaptersForModel(modelId: String): List<LoRAAdapterInfo> =
        withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.getForModel(modelId).map { entry ->
                LoRAAdapterInfo(
                    adapter_id = entry.id,
                    adapter_path = entry.filename,
                    scale = entry.defaultScale,
                    applied = false,
                )
            }
        }

    actual suspend fun allRegistered(): List<LoRAAdapterInfo> =
        withContext(Dispatchers.IO) {
            CppBridgeLoraRegistry.getAll().map { entry ->
                LoRAAdapterInfo(
                    adapter_id = entry.id,
                    adapter_path = entry.filename,
                    scale = entry.defaultScale,
                    applied = false,
                )
            }
        }
}

private val LoRASingleton = LoRA()

actual val RunAnywhere.lora: LoRA
    get() = LoRASingleton
