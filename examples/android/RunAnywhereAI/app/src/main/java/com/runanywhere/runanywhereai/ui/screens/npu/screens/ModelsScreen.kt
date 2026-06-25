package com.runanywhere.runanywhereai.ui.screens.npu.screens

import ai.runanywhere.proto.v1.ArchiveStructure
import ai.runanywhere.proto.v1.ArchiveType
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.ModelCategory
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
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
    val progress = remember { mutableStateMapOf<String, Float>() }
    var status by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        try {
            RunAnywhere.listModels().models?.models
                ?.filter { it.local_path.isNotBlank() }
                ?.forEach { downloaded.add(it.id) }
        } catch (_: Exception) {
            // registry unreachable — rows render as not-downloaded.
        }
    }

    fun modalityCat(m: NpuModel) =
        if (m.modality == NpuModality.VLM) ModelCategory.MODEL_CATEGORY_MULTIMODAL
        else ModelCategory.MODEL_CATEGORY_LANGUAGE

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
                    progress = progress[m.id],
                    onDownload = {
                        scope.launch {
                            progress[m.id] = 0f
                            error = null
                            try {
                                val model = RunAnywhere.registerModel(
                                    archiveUrl = driveZipUrl(m.driveId),
                                    structure = ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
                                    id = m.id,
                                    name = m.name,
                                    framework = InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT,
                                    modality = modalityCat(m),
                                    archiveType = ArchiveType.ARCHIVE_TYPE_ZIP,
                                )
                                RunAnywhere.downloadModel(model) { p -> progress[m.id] = p.stage_progress }
                                progress.remove(m.id)
                                downloaded.add(m.id)
                                status = "Downloaded ${m.name}"
                                RunAnywhere.loadModel(RAModelLoadRequest(model_id = m.id))
                            } catch (e: Exception) {
                                progress.remove(m.id)
                                error = e.message ?: "download failed"
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
    progress: Float?,
    onDownload: () -> Unit,
) {
    val pending = model.driveId.isBlank()
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
                        downloaded -> "Downloaded"
                        pending -> "Link pending"
                        else -> model.modality.name
                    },
                    color = when {
                        downloaded -> RaSuccess
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
                downloaded -> Text("Ready", style = MaterialTheme.typography.labelLarge, color = RaSuccess)
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
