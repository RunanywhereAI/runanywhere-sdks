/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for LoRA adapter management.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDownload
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLoraRegistry
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeModelPaths
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterConfig
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterInfo
import com.runanywhere.sdk.public.extensions.Models.DownloadProgress
import com.runanywhere.sdk.public.extensions.Models.DownloadState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.float
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.net.HttpURLConnection
import java.net.URI
import kotlin.coroutines.coroutineContext

private val loraLogger = SDKLogger("LoRA")

private val loraJson = Json { ignoreUnknownKeys = true }

actual suspend fun RunAnywhere.loadLoraAdapter(config: LoRAAdapterConfig) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    loraLogger.info("Loading LoRA adapter: ${config.path} (scale=${config.scale})")

    val result = CppBridgeLLM.loadLoraAdapter(config.path, config.scale)
    if (result != 0) {
        throw SDKError.llm("Failed to load LoRA adapter: error $result")
    }
}

actual suspend fun RunAnywhere.removeLoraAdapter(path: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val result = CppBridgeLLM.removeLoraAdapter(path)
    if (result != 0) {
        throw SDKError.llm("Failed to remove LoRA adapter: error $result")
    }
}

actual suspend fun RunAnywhere.clearLoraAdapters() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val result = CppBridgeLLM.clearLoraAdapters()
    if (result != 0) {
        throw SDKError.llm("Failed to clear LoRA adapters: error $result")
    }
}

actual suspend fun RunAnywhere.getLoadedLoraAdapters(): List<LoRAAdapterInfo> {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val jsonStr = CppBridgeLLM.getLoraInfo() ?: return emptyList()

    return try {
        val jsonArray = loraJson.parseToJsonElement(jsonStr) as? JsonArray ?: return emptyList()
        jsonArray.map { element ->
            val obj = element.jsonObject
            LoRAAdapterInfo(
                path = obj["path"]?.jsonPrimitive?.content ?: "",
                scale = obj["scale"]?.jsonPrimitive?.float ?: 1.0f,
                applied = obj["applied"]?.jsonPrimitive?.boolean ?: false,
            )
        }
    } catch (e: Exception) {
        loraLogger.error("Failed to parse LoRA info JSON: ${e.message}")
        emptyList()
    }
}

// MARK: - LoRA Compatibility Check

actual fun RunAnywhere.checkLoraCompatibility(loraPath: String): LoraCompatibilityResult {
    if (!isInitialized) return LoraCompatibilityResult(isCompatible = false, error = "SDK not initialized")
    val error = CppBridgeLLM.checkLoraCompatibility(loraPath)
    return if (error == null) {
        LoraCompatibilityResult(isCompatible = true)
    } else {
        LoraCompatibilityResult(isCompatible = false, error = error)
    }
}

// MARK: - LoRA Adapter Catalog

actual fun RunAnywhere.registerLoraAdapter(entry: LoraAdapterCatalogEntry) {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")
    CppBridgeLoraRegistry.register(
        CppBridgeLoraRegistry.LoraEntry(
            id = entry.id,
            name = entry.name,
            description = entry.description,
            downloadUrl = entry.downloadUrl,
            filename = entry.filename,
            compatibleModelIds = entry.compatibleModelIds,
            fileSize = entry.fileSize,
            defaultScale = entry.defaultScale,
        ),
    )
}

actual fun RunAnywhere.loraAdaptersForModel(modelId: String): List<LoraAdapterCatalogEntry> {
    if (!isInitialized) return emptyList()
    return CppBridgeLoraRegistry.getForModel(modelId).map { it.toCatalogEntry() }
}

actual fun RunAnywhere.allRegisteredLoraAdapters(): List<LoraAdapterCatalogEntry> {
    if (!isInitialized) return emptyList()
    return CppBridgeLoraRegistry.getAll().map { it.toCatalogEntry() }
}

private fun CppBridgeLoraRegistry.LoraEntry.toCatalogEntry() = LoraAdapterCatalogEntry(
    id = id,
    name = name,
    description = description,
    downloadUrl = downloadUrl,
    filename = filename,
    compatibleModelIds = compatibleModelIds,
    fileSize = fileSize,
    defaultScale = defaultScale,
)

// MARK: - LoRA Adapter Downloads

// Computed each time to avoid caching a wrong path captured before pathProvider is set
private fun getLoraDownloadDir(): File =
    File(CppBridgeModelPaths.getBaseDirectory(), "lora_adapters").also { it.mkdirs() }

actual fun RunAnywhere.downloadLoraAdapter(adapterId: String): Flow<DownloadProgress> = flow {
    if (!isInitialized) throw SDKError.notInitialized("SDK not initialized")

    val entry = CppBridgeLoraRegistry.getAll()
        .find { it.id == adapterId }
        ?: throw SDKError.download("LoRA adapter '$adapterId' not found in registry")

    val uri = try { URI(entry.downloadUrl) } catch (e: Exception) {
        throw SDKError.download("Invalid download URL for adapter '$adapterId': ${e.message}")
    }
    if (uri.scheme?.lowercase() != "https") {
        throw SDKError.download("Only HTTPS download URLs are allowed")
    }

    val (isNetworkAvailable, _) = CppBridgeDownload.checkNetworkStatus()
    if (!isNetworkAvailable) {
        throw SDKError.networkUnavailable(IllegalStateException("No internet connection"))
    }

    val loraDir = getLoraDownloadDir()
    val destFile = File(loraDir, entry.filename)
    val tmpFile = File(loraDir, "${entry.filename}.tmp")

    if (!destFile.canonicalPath.startsWith(loraDir.canonicalPath + File.separator)) {
        throw SDKError.download("Invalid adapter filename (path traversal): ${entry.filename}")
    }

    // Already downloaded — emit COMPLETED and return
    if (destFile.exists() && destFile.length() > 0) {
        loraLogger.info("LoRA adapter already downloaded: ${destFile.absolutePath}")
        emit(DownloadProgress(
            modelId = adapterId, progress = 1f,
            bytesDownloaded = destFile.length(), totalBytes = destFile.length(),
            state = DownloadState.COMPLETED,
        ))
        return@flow
    }

    emit(DownloadProgress(
        modelId = adapterId, progress = 0f,
        bytesDownloaded = 0, totalBytes = entry.fileSize,
        state = DownloadState.PENDING,
    ))

    loraLogger.info("Starting LoRA download: ${entry.name} from ${entry.downloadUrl}")

    val connection = uri.toURL().openConnection() as HttpURLConnection
    connection.connectTimeout = 30_000
    connection.readTimeout = 120_000
    connection.setRequestProperty("User-Agent", "RunAnywhere-SDK/1.0")

    try {
        val responseCode = connection.responseCode
        if (responseCode != HttpURLConnection.HTTP_OK) {
            throw SDKError.download("HTTP $responseCode downloading LoRA adapter '${entry.filename}'")
        }

        val totalSize = connection.contentLengthLong.takeIf { it > 0 } ?: entry.fileSize
        var downloaded = 0L
        var lastEmitTime = 0L
        val buffer = ByteArray(8192)

        connection.inputStream.buffered().use { input ->
            tmpFile.outputStream().buffered().use { output ->
                var bytesRead: Int
                while (input.read(buffer).also { bytesRead = it } != -1) {
                    coroutineContext.ensureActive()
                    output.write(buffer, 0, bytesRead)
                    downloaded += bytesRead

                    val now = System.currentTimeMillis()
                    if (now - lastEmitTime >= 200) {
                        lastEmitTime = now
                        val progress = if (totalSize > 0)
                            (downloaded.toFloat() / totalSize).coerceIn(0f, 1f) else 0f
                        emit(DownloadProgress(
                            modelId = adapterId, progress = progress,
                            bytesDownloaded = downloaded, totalBytes = totalSize,
                            state = DownloadState.DOWNLOADING,
                        ))
                    }
                }
            }
        }

        destFile.delete()
        if (!tmpFile.renameTo(destFile)) {
            tmpFile.copyTo(destFile, overwrite = true)
            tmpFile.delete()
        }
    } catch (e: Exception) {
        tmpFile.delete()
        throw e
    } finally {
        connection.disconnect()
    }

    loraLogger.info("LoRA download completed: ${destFile.absolutePath}")
    emit(DownloadProgress(
        modelId = adapterId, progress = 1f,
        bytesDownloaded = destFile.length(), totalBytes = destFile.length(),
        state = DownloadState.COMPLETED,
    ))
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
