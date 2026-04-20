// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Model catalog — registerModel, registerMultiFileModel, registerLoraAdapter,
// availableModels, getCurrentModelId, etc. Backed by a process-wide
// in-memory registry; the C++ ModelRegistry is the source of truth at
// runtime, this Swift-style catalog mirrors entries to drive the UI.

package com.runanywhere.sdk.`public`

import java.io.File

enum class InferenceFramework(val raw: String) {
    LLAMACPP("llamacpp"),
    ONNX("onnx"),
    WHISPERKIT("whisperkit"),
    METALRT("metalrt"),
    GENIE("genie"),
    FOUNDATION_MODELS("foundation_models"),
    COREML("coreml"),
    MLX("mlx"),
    SHERPA("sherpa"),
    UNKNOWN("unknown"),
}

enum class ModelCategory { LLM, STT, TTS, VAD, EMBEDDING, VLM, DIFFUSION, RERANK, WAKEWORD, UNKNOWN }

sealed class ModelArtifactType {
    object SingleFile                    : ModelArtifactType()
    data class Archive(val format: String): ModelArtifactType()
    object MultiFile                     : ModelArtifactType()
}

data class ModelFileDescriptor(
    val url: String,
    val relativePath: String,
    val sha256: String? = null,
    val sizeBytes: Long? = null,
)

data class ModelInfo(
    val id: String,
    val name: String,
    val url: String? = null,
    val framework: InferenceFramework = InferenceFramework.LLAMACPP,
    val category: ModelCategory = ModelCategory.LLM,
    val artifactType: ModelArtifactType = ModelArtifactType.SingleFile,
    val memoryRequirement: Long? = null,
    val supportsThinking: Boolean = false,
    val modality: String? = null,
    val localPath: String? = null,
    val files: List<ModelFileDescriptor>? = null,
)

data class LoRAAdapterConfig(
    val id: String,
    val name: String,
    val localPath: String,
    val baseModelId: String,
    val scale: Float = 1.0f,
)

data class LoraAdapterCatalogEntry(
    val id: String,
    val name: String,
    val url: String,
    val baseModelId: String,
    val sha256: String? = null,
    val sizeBytes: Long? = null,
)

data class LoRAAdapterInfo(val config: LoRAAdapterConfig, val loaded: Boolean)
data class LoraCompatibilityResult(val compatible: Boolean, val reason: String? = null)

sealed class DownloadState {
    object NotStarted                       : DownloadState()
    data class Downloading(val progress: Double) : DownloadState()
    data class Completed(val localPath: String)  : DownloadState()
    data class Failed(val message: String)       : DownloadState()
    object Cancelled                         : DownloadState()
}

data class StorageInfo(
    val totalBytes: Long = 0,
    val freeBytes: Long = 0,
    val modelsBytes: Long = 0,
    val cacheBytes: Long = 0,
)

data class ModelCompanionFile(val url: String, val relativePath: String, val sha256: String? = null)

data class DeviceInfo(
    val model: String = "",
    val osVersion: String = "",
    val totalRamBytes: Long = 0,
    val availableRamBytes: Long = 0,
    val cpuCores: Int = 0,
    val chipName: String? = null,
)

enum class NPUChip { SNAPDRAGON_8_GEN_3, SNAPDRAGON_8_GEN_2, MEDIATEK_DIMENSITY_9300, GOOGLE_TENSOR_G3, NONE, UNKNOWN }

fun getChip(): NPUChip = NPUChip.UNKNOWN

fun getNPUDownloadUrl(chip: NPUChip): String? = null

fun collectDeviceInfo(): DeviceInfo = DeviceInfo()

internal object ModelCatalog {
    private val entries = mutableMapOf<String, ModelInfo>()
    private val loraEntries = mutableMapOf<String, LoraAdapterCatalogEntry>()
    private val loadedLoraAdapters = mutableMapOf<String, LoRAAdapterConfig>()
    private val pendingFlush = mutableListOf<() -> Unit>()

    fun register(info: ModelInfo) { entries[info.id] = info }
    fun registerLora(entry: LoraAdapterCatalogEntry) { loraEntries[entry.id] = entry }

    fun all(): List<ModelInfo> = entries.values.toList()
    fun get(id: String): ModelInfo? = entries[id]
    fun allLora(): List<LoraAdapterCatalogEntry> = loraEntries.values.toList()
    fun allRegisteredLora(): List<LoRAAdapterConfig> = loadedLoraAdapters.values.toList()
    fun setLoraLoaded(c: LoRAAdapterConfig) { loadedLoraAdapters[c.id] = c }
    fun setLoraUnloaded(id: String) { loadedLoraAdapters.remove(id) }
    fun clearLora() { loadedLoraAdapters.clear() }
    fun adaptersFor(modelId: String): List<LoRAAdapterConfig> =
        loadedLoraAdapters.values.filter { it.baseModelId == modelId }

    fun enqueueFlush(work: () -> Unit) { pendingFlush.add(work) }
    fun runFlushes() { pendingFlush.toList().also { pendingFlush.clear() }.forEach { it() } }
}

// MARK: - RunAnywhere extensions ------------------------------------------

fun RunAnywhere.registerModel(
    id: String, name: String, url: String,
    framework: InferenceFramework,
    category: ModelCategory = ModelCategory.LLM,
    artifactType: ModelArtifactType = ModelArtifactType.SingleFile,
    memoryRequirement: Long? = null,
    supportsThinking: Boolean = false,
    modality: String? = null,
) {
    ModelCatalog.register(ModelInfo(
        id = id, name = name, url = url, framework = framework,
        category = category, artifactType = artifactType,
        memoryRequirement = memoryRequirement,
        supportsThinking = supportsThinking, modality = modality
    ))
}

fun RunAnywhere.registerMultiFileModel(
    id: String, name: String, files: List<ModelFileDescriptor>,
    framework: InferenceFramework, category: ModelCategory = ModelCategory.LLM,
    memoryRequirement: Long? = null,
) {
    ModelCatalog.register(ModelInfo(
        id = id, name = name, url = null, framework = framework,
        category = category, artifactType = ModelArtifactType.MultiFile,
        memoryRequirement = memoryRequirement, files = files
    ))
}

fun RunAnywhere.registerLoraAdapter(entry: LoraAdapterCatalogEntry) =
    ModelCatalog.registerLora(entry)

suspend fun RunAnywhere.flushPendingRegistrations() = ModelCatalog.runFlushes()

suspend fun RunAnywhere.discoverDownloadedModels(): Int =
    ModelCatalog.all().count { info ->
        val path = modelsRoot().resolve(info.framework.raw).resolve(info.id)
        path.exists()
    }

val RunAnywhere.availableModels: List<ModelInfo> get() = ModelCatalog.all()

fun RunAnywhere.getModelsForFramework(framework: InferenceFramework): List<ModelInfo> =
    ModelCatalog.all().filter { it.framework == framework }

fun RunAnywhere.getModelsForCategory(category: ModelCategory): List<ModelInfo> =
    ModelCatalog.all().filter { it.category == category }

fun RunAnywhere.getRegisteredFrameworks(): List<InferenceFramework> =
    ModelCatalog.all().map { it.framework }.distinct()

fun RunAnywhere.modelInfo(id: String): ModelInfo? = ModelCatalog.get(id)

// --- Storage / cleanup -----------------------------------------------------

fun RunAnywhere.getStorageInfo(): StorageInfo {
    val root = modelsRoot()
    val cache = cacheRoot()
    val totalUsable = root.usableSpace
    val totalCapacity = root.totalSpace
    return StorageInfo(
        totalBytes = totalCapacity,
        freeBytes = totalUsable,
        modelsBytes = if (root.exists()) directorySize(root) else 0L,
        cacheBytes = if (cache.exists()) directorySize(cache) else 0L,
    )
}

// Property accessor used by the sample app — duplicate of getStorageInfo()
// reachable as `RunAnywhere.storageInfo`. JvmName needed because Kotlin
// generates the same JVM getter name otherwise.
val RunAnywhere.storageInfo: StorageInfo
    @JvmName("storageInfoProperty")
    get() = getStorageInfo()

fun RunAnywhere.clearCache(): Long {
    val before = directorySize(cacheRoot())
    cacheRoot().deleteRecursively()
    return before
}

fun RunAnywhere.cleanTempFiles(): Long {
    val tmp = tmpRoot()
    val before = directorySize(tmp)
    tmp.deleteRecursively()
    return before
}

fun RunAnywhere.deleteStoredModel(modelId: String, framework: InferenceFramework): Boolean {
    val path = modelsRoot().resolve(framework.raw).resolve(modelId)
    return path.deleteRecursively()
}

fun RunAnywhere.deleteModel(modelId: String): Boolean {
    val info = ModelCatalog.get(modelId) ?: return false
    return deleteStoredModel(modelId, info.framework)
}

fun RunAnywhere.getDownloadedModelsWithInfo(): List<ModelInfo> =
    ModelCatalog.all().filter { info ->
        modelsRoot().resolve(info.framework.raw).resolve(info.id).exists()
    }

fun RunAnywhere.getDownloadedModels(): List<ModelInfo> = getDownloadedModelsWithInfo()

internal fun modelsRoot(): File =
    File(System.getProperty("user.home") ?: ".",
         ".runanywhere/models")

internal fun cacheRoot(): File =
    File(System.getProperty("user.home") ?: ".",
         ".runanywhere/cache")

internal fun tmpRoot(): File =
    File(System.getProperty("java.io.tmpdir") ?: "/tmp", "runanywhere")

private fun directorySize(dir: File): Long =
    if (!dir.exists()) 0L
    else dir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
