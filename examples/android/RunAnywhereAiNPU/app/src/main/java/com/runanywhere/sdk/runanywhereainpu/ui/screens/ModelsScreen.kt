package com.runanywhere.sdk.runanywhereainpu.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.types.RAModelInfo
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import com.runanywhere.sdk.runanywhereainpu.ui.components.SectionCard
import com.runanywhere.sdk.runanywhereainpu.ui.theme.RaSuccess
import com.runanywhere.sdk.runanywhereainpu.ui.theme.Spacing
import kotlinx.coroutines.launch

@Composable
fun ModelsScreen() {
    val scope = rememberCoroutineScope()
    var models by remember { mutableStateOf<List<RAModelInfo>>(emptyList()) }
    var loading by remember { mutableStateOf(true) }
    var error by remember { mutableStateOf<String?>(null) }
    var status by remember { mutableStateOf<String?>(null) }
    val progress = remember { mutableStateMapOf<String, Float>() }

    suspend fun refresh() {
        loading = true; error = null
        try {
            val result = RunAnywhere.listModels()
            models = result.models?.models ?: emptyList()
        } catch (e: Exception) {
            error = e.message ?: "failed to list models"
        } finally {
            loading = false
        }
    }

    LaunchedEffect(Unit) { refresh() }

    Column(Modifier.fillMaxSize().padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        status?.let { Text(it, color = RaSuccess, style = MaterialTheme.typography.bodyMedium) }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }

        when {
            loading -> Row(Modifier.fillMaxWidth().padding(Spacing.lg), horizontalArrangement = Arrangement.Center) {
                CircularProgressIndicator()
            }
            models.isEmpty() -> SectionCard {
                Text(
                    "No models in the registry. Models are added via the SDK catalog or " +
                        "registerModel(); QHexRT bundles are arch-specific (v79/v81).",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                items(models, key = { it.id }) { model ->
                    ModelRow(
                        model = model,
                        progress = progress[model.id],
                        onDownload = {
                            scope.launch {
                                progress[model.id] = 0f
                                try {
                                    RunAnywhere.downloadModel(model) { p ->
                                        progress[model.id] = p.stage_progress
                                    }
                                    progress.remove(model.id)
                                    status = "Downloaded ${model.name}"
                                    refresh()
                                } catch (e: Exception) {
                                    progress.remove(model.id)
                                    error = e.message ?: "download failed"
                                }
                            }
                        },
                        onLoad = {
                            scope.launch {
                                try {
                                    val r = RunAnywhere.loadModel(RAModelLoadRequest(model_id = model.id))
                                    status = if (r.success) "Loaded ${model.name}" else (r.error_message ?: "load failed")
                                } catch (e: Exception) {
                                    error = e.message ?: "load failed"
                                }
                            }
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun ModelRow(
    model: RAModelInfo,
    progress: Float?,
    onDownload: () -> Unit,
    onLoad: () -> Unit,
) {
    val downloaded = model.local_path.isNotBlank()
    SectionCard {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(
                    model.name.ifBlank { model.id },
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    Chip(
                        model.framework.name.removePrefix("INFERENCE_FRAMEWORK_").lowercase(),
                        MaterialTheme.colorScheme.primary,
                    )
                    if (model.download_size_bytes > 0) {
                        Chip(formatBytes(model.download_size_bytes), MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            }
            // One control that morphs by state: Download -> (progress) -> Use.
            when {
                progress != null -> Text(
                    "${(progress.coerceIn(0f, 1f) * 100).toInt()}%",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                )
                downloaded -> Button(onClick = onLoad) { Text("Use") }
                else -> Button(onClick = onDownload) { Text("Download") }
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

@Composable
private fun Chip(label: String, color: androidx.compose.ui.graphics.Color) {
    Text(
        label,
        style = MaterialTheme.typography.labelSmall,
        color = color,
        modifier = Modifier
            .background(color.copy(alpha = 0.12f), RoundedCornerShape(Spacing.xs))
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

private fun formatBytes(bytes: Long): String {
    if (bytes <= 0) return "—"
    val units = arrayOf("B", "KB", "MB", "GB")
    var v = bytes.toDouble()
    var i = 0
    while (v >= 1024 && i < units.lastIndex) {
        v /= 1024; i++
    }
    return if (i == 0) "$bytes B" else "%.1f %s".format(v, units[i])
}
