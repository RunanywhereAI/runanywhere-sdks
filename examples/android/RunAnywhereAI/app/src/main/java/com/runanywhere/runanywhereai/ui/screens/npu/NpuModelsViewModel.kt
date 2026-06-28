package com.runanywhere.runanywhereai.ui.screens.npu

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelSource
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.modelInfoForCategory
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

/** Lifecycle phase of a single NPU model row. */
enum class NpuModelStatus { NotDownloaded, Downloading, Downloaded, Loading, Loaded }

data class NpuModelsState(
    /** Hexagon arch probed on the device ("v75"/"v79"/"v81"); null while detecting. */
    val deviceArch: String? = null,
    /** Ids of NPU models present on disk. */
    val downloadedIds: Set<String> = emptySet(),
    /** Currently-resident model id per modality (NPU memory). */
    val loadedByModality: Map<NpuModality, String?> = emptyMap(),
    /** Model id currently downloading or loading (only one at a time). */
    val busyId: String? = null,
    /** 0..1 download progress for [busyId] while downloading; null while loading. */
    val progress: Float? = null,
    val error: String? = null,
)

/**
 * Owns NPU model selection, download and load for the whole NPU section.
 *
 * Scoped to the NPU section's nav entry (one instance shared by every screen),
 * so an in-flight download survives navigation between Chat/Vision/STT/TTS —
 * the work runs on [viewModelScope], not a composable's scope. The catalog is
 * filtered to the device's Hexagon arch ([catalogFor]) so each modality screen
 * only ever offers bundles that can actually load on this chip.
 */
class NpuModelsViewModel : ViewModel() {

    var state by mutableStateOf(NpuModelsState())
        private set

    /** Supplied once the NPU probe completes; refreshes the registry view. */
    fun setDeviceArch(arch: String?) {
        if (state.deviceArch == arch) return
        state = state.copy(deviceArch = arch)
        refresh()
    }

    /** Catalog entries for [modality] that match the detected device arch. */
    fun catalogFor(modality: NpuModality): List<NpuModel> =
        NPU_MODELS.filter { it.modality == modality && it.arch == state.deviceArch }

    /** Whether any modality has an arch-matching model for this device. */
    fun hasAnyForDevice(): Boolean =
        state.deviceArch != null && NPU_MODELS.any { it.arch == state.deviceArch }

    fun statusFor(model: NpuModel): NpuModelStatus = when {
        state.loadedByModality[model.modality] == model.id -> NpuModelStatus.Loaded
        state.busyId == model.id && state.progress != null -> NpuModelStatus.Downloading
        state.busyId == model.id -> NpuModelStatus.Loading
        state.downloadedIds.contains(model.id) -> NpuModelStatus.Downloaded
        else -> NpuModelStatus.NotDownloaded
    }

    /** Loaded model id for [modality], or null if nothing is resident. */
    fun loadedId(modality: NpuModality): String? = state.loadedByModality[modality]

    fun refresh() {
        viewModelScope.launch { reload() }
    }

    private suspend fun reload() {
        try {
            val downloaded = RunAnywhere.listModels().models?.models
                ?.filter { it.local_path.isNotBlank() }
                ?.map { it.id }
                ?.toSet()
                .orEmpty()
            val loaded = NpuModality.entries.associateWith { m ->
                runCatching { RunAnywhere.modelInfoForCategory(m.category())?.id }.getOrNull()
            }
            state = state.copy(downloadedIds = downloaded, loadedByModality = loaded)
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // Registry unreachable — keep the last known state.
        }
    }

    /** Registers (if needed), downloads, then loads the model. */
    fun download(model: NpuModel) {
        if (state.busyId != null) return
        viewModelScope.launch {
            state = state.copy(busyId = model.id, progress = 0f, error = null)
            try {
                val registered = register(model)
                RunAnywhere.downloadModel(registered) { p ->
                    state = state.copy(progress = p.stage_progress.coerceIn(0f, 1f))
                }
                state = state.copy(progress = null)
                reload()
                loadInternal(model)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.e("npu download failed: ${model.id}", e)
                state = state.copy(busyId = null, progress = null, error = e.message ?: "Download failed")
            }
        }
    }

    /** Loads an already-downloaded model into NPU memory for its modality. */
    fun load(model: NpuModel) {
        if (state.busyId != null) return
        viewModelScope.launch { loadInternal(model) }
    }

    private suspend fun loadInternal(model: NpuModel) {
        state = state.copy(busyId = model.id, progress = null, error = null)
        try {
            val result = RunAnywhere.loadModel(RAModelLoadRequest(model_id = model.id))
            if (result.success) {
                state = state.copy(busyId = null)
                reload()
            } else {
                state = state.copy(
                    busyId = null,
                    error = result.error_message.ifBlank { "Failed to load ${model.name}" },
                )
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            RACLog.e("npu load failed: ${model.id}", e)
            state = state.copy(busyId = null, error = e.message ?: "Failed to load ${model.name}")
        }
    }

    private suspend fun register(model: NpuModel) =
        if (model.files.isNotEmpty()) {
            RunAnywhere.registerModel(
                multiFile = model.files.mapIndexed { idx, f ->
                    ModelFileDescriptor(
                        url = f.url,
                        filename = f.filename,
                        is_required = true,
                        role = if (idx == 0) {
                            ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
                        } else {
                            ModelFileRole.MODEL_FILE_ROLE_COMPANION
                        },
                    )
                },
                id = model.id,
                name = model.name,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                modality = model.modality.category(),
                contextLength = null,
                supportsThinking = false,
                source = ModelSource.MODEL_SOURCE_REMOTE,
            )
        } else {
            RunAnywhere.registerModel(
                archiveUrl = model.resolvedArchiveUrl,
                structure = ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
                id = model.id,
                name = model.name,
                framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                modality = model.modality.category(),
                archiveType = ArchiveType.ARCHIVE_TYPE_ZIP,
            )
        }

    fun clearError() {
        state = state.copy(error = null)
    }
}
