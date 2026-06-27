package com.runanywhere.runanywhereai.ui.screens.npu.screens

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import ai.runanywhere.proto.v1.ModelFileDescriptor
import ai.runanywhere.proto.v1.ModelFileRole
import ai.runanywhere.proto.v1.ModelSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.screens.npu.NPU_MODELS
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModality
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModel
import com.runanywhere.runanywhereai.ui.screens.npu.SectionCard
import com.runanywhere.runanywhereai.ui.screens.npu.StatusPill
import com.runanywhere.runanywhereai.ui.screens.npu.driveZipUrl
import com.runanywhere.runanywhereai.ui.screens.npu.theme.RaSuccess
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.modelInfoForCategory
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import kotlinx.coroutines.launch

/**
 * NPU (QHexRT) catalog — Google-Drive-hosted ZIP bundles. Download registers
 * each as a ZIP archive (QHexRT framework); the SDK downloads + extracts it
 * into the standard model dir, then loads it like any other model.
 */
@Composable
fun ModelsScreen() {
    val scope = rememberCoroutineScope()
    val downloaded = remember { mutableStateListOf<String>() }
    val loaded = remember { mutableStateListOf<String>() }
    val progress = remember { mutableStateMapOf<String, Float>() }
    var loadingId by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    fun modalityCat(m: NpuModel) =
        if (m.modality == NpuModality.VLM) ModelCategory.MODEL_CATEGORY_MULTIMODAL
        else ModelCategory.MODEL_CATEGORY_LANGUAGE

    suspend fun refreshLoaded() {
        val ids = listOf(
            ModelCategory.MODEL_CATEGORY_LANGUAGE,
            ModelCategory.MODEL_CATEGORY_MULTIMODAL,
        ).mapNotNull { RunAnywhere.modelInfoForCategory(it)?.id }
        loaded.clear()
        loaded.addAll(ids)
    }

    LaunchedEffect(Unit) {
        try {
            RunAnywhere.listModels().models?.models
                ?.filter { it.local_path.isNotBlank() }
                ?.forEach { downloaded.add(it.id) }
            refreshLoaded()
        } catch (_: Exception) {
            // registry unreachable — rows render as not-downloaded.
        }
    }

    Column(Modifier.fillMaxSize().padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        Text(
            "${NPU_MODELS.size} NPU bundles",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        status?.let { Text(it, color = RaSuccess, style = MaterialTheme.typography.bodyMedium) }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            items(NPU_MODELS, key = { it.id }) { m ->
                ModelRow(
                    model = m,
                    downloaded = downloaded.contains(m.id),
                    loaded = loaded.contains(m.id),
                    loading = loadingId == m.id,
                    progress = progress[m.id],
                    onDownload = {
                        scope.launch {
                            progress[m.id] = 0f
                            error = null
                            try {
                                val model = if (m.files.isNotEmpty()) {
                                    RunAnywhere.registerModel(
                                        multiFile = m.files.mapIndexed { idx, f ->
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
                                        id = m.id,
                                        name = m.name,
                                        framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                                        modality = modalityCat(m),
                                        contextLength = null,
                                        supportsThinking = false,
                                        source = ModelSource.MODEL_SOURCE_REMOTE,
                                    )
                                } else {
                                    RunAnywhere.registerModel(
                                        archiveUrl = driveZipUrl(m.driveId),
                                        structure = ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
                                        id = m.id,
                                        name = m.name,
                                        framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                                        modality = modalityCat(m),
                                        archiveType = ArchiveType.ARCHIVE_TYPE_ZIP,
                                    )
                                }
                                RunAnywhere.downloadModel(model) { p -> progress[m.id] = p.stage_progress }
                                progress.remove(m.id)
                                downloaded.add(m.id)
                                status = "Downloaded ${m.name}"
                                loadingId = m.id
                                RunAnywhere.loadModel(RAModelLoadRequest(model_id = m.id))
                                refreshLoaded()
                                status = "Loaded ${m.name}"
                            } catch (e: Exception) {
                                progress.remove(m.id)
                                error = e.message ?: "download failed"
                            } finally {
                                loadingId = null
                            }
                        }
                    },
                    onLoad = {
                        scope.launch {
                            error = null
                            loadingId = m.id
                            try {
                                val result = RunAnywhere.loadModel(RAModelLoadRequest(model_id = m.id))
                                if (result.success) {
                                    refreshLoaded()
                                    status = "Loaded ${m.name}"
                                } else {
                                    error = result.error_message.ifBlank { "Failed to load ${m.name}" }
                                }
                            } catch (e: Exception) {
                                error = e.message ?: "Failed to load ${m.name}"
                            } finally {
                                loadingId = null
                            }
                        }
                    },
                )
            }
        }
    }
}

@Composable
private fun ModelRow(
    model: NpuModel,
    downloaded: Boolean,
    loaded: Boolean,
    loading: Boolean,
    progress: Float?,
    onDownload: () -> Unit,
    onLoad: () -> Unit,
) {
    val pending = model.driveId.isBlank() && model.files.isEmpty()
    SectionCard {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(model.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    model.detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                StatusPill(
                    label = when {
                        loaded -> "Loaded"
                        downloaded -> "Downloaded"
                        pending -> "Link pending"
                        else -> model.modality.name
                    },
                    color = when {
                        loaded || downloaded -> RaSuccess
                        pending -> MaterialTheme.colorScheme.tertiary
                        else -> MaterialTheme.colorScheme.primary
                    },
                )
            }
            when {
                progress != null -> Text(
                    "${(progress.coerceIn(0f, 1f) * 100).toInt()}%",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
                loading -> CircularProgressIndicator(modifier = Modifier.size(20.dp))
                loaded -> Text("In memory", style = MaterialTheme.typography.labelLarge, color = RaSuccess)
                downloaded -> Button(onClick = onLoad) { Text("Load") }
                else -> Button(onClick = onDownload, enabled = !pending) { Text("Download") }
            }
        }
        if (progress != null) {
            LinearProgressIndicator(
                progress = { progress.coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth().padding(top = Spacing.sm),
            )
        }
    }
}
