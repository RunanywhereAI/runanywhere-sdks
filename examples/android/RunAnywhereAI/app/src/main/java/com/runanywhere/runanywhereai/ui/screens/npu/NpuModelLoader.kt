package com.runanywhere.runanywhereai.ui.screens.npu

import ai.runanywhere.proto.v1.ModelCategory
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.screens.npu.theme.RaSuccess
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.listModels
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.modelInfoForCategory
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import kotlinx.coroutines.launch

/** Proto model category backing a given NPU modality. */
private fun NpuModality.category(): ModelCategory =
    if (this == NpuModality.VLM) ModelCategory.MODEL_CATEGORY_MULTIMODAL
    else ModelCategory.MODEL_CATEGORY_LANGUAGE

/**
 * Model load bar shown at the top of each inference screen.
 *
 * Lists the downloaded NPU models for [modality], shows which one is currently
 * resident in NPU memory, and lets the user load any downloaded model with one
 * tap. Inference screens stay disabled until [onLoadedChange] reports a loaded
 * model, so generation never runs against an empty engine.
 *
 * All work is thin SDK calls — `listModels()` (downloaded set),
 * `modelInfoForCategory()` (what's resident) and `loadModel()` — the C++
 * lifecycle service remains the source of truth for "is this modality loaded".
 *
 * @param modality       which NPU models to surface (LLM vs VLM).
 * @param onLoadedChange invoked with the loaded model id (or null) on entry and
 *                       after every successful load, so the host screen can
 *                       enable/disable its run button.
 */
@Composable
fun NpuModelLoader(
    modality: NpuModality,
    onLoadedChange: (String?) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val downloadedIds = remember { mutableStateListOf<String>() }
    var loadedId by remember { mutableStateOf<String?>(null) }
    var loadingId by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    val candidates = NPU_MODELS.filter { it.modality == modality }

    suspend fun refresh() {
        try {
            val ids = RunAnywhere.listModels().models?.models
                ?.filter { it.local_path.isNotBlank() }
                ?.map { it.id }
                .orEmpty()
            downloadedIds.clear()
            downloadedIds.addAll(ids)
            loadedId = RunAnywhere.modelInfoForCategory(modality.category())?.id
            onLoadedChange(loadedId)
        } catch (_: Exception) {
            // Registry unreachable — leave rows as not-downloaded.
        }
    }

    LaunchedEffect(modality) { refresh() }

    SectionCard(title = "Model") {
        val available = candidates.filter { downloadedIds.contains(it.id) }
        when {
            available.isEmpty() -> Text(
                "No ${modality.name} model downloaded yet. Open the Models tab to download one.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            else -> Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                available.forEach { model ->
                    val isLoaded = loadedId == model.id
                    val isLoading = loadingId == model.id
                    Row(
                        Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(
                                model.name,
                                style = MaterialTheme.typography.titleSmall,
                                fontWeight = FontWeight.SemiBold,
                            )
                            Text(
                                model.detail,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        when {
                            isLoaded -> StatusPill(label = "Loaded", color = RaSuccess)
                            isLoading -> CircularProgressIndicator(modifier = Modifier.size(20.dp))
                            else -> Button(
                                onClick = {
                                    error = null
                                    loadingId = model.id
                                    scope.launch {
                                        try {
                                            val result = RunAnywhere.loadModel(
                                                RAModelLoadRequest(model_id = model.id),
                                            )
                                            if (result.success) {
                                                loadedId = model.id
                                                onLoadedChange(loadedId)
                                            } else {
                                                error = result.error_message.ifBlank { "Failed to load ${model.name}" }
                                            }
                                        } catch (e: Exception) {
                                            error = e.message ?: "Failed to load ${model.name}"
                                        } finally {
                                            loadingId = null
                                        }
                                    }
                                },
                                enabled = loadingId == null,
                            ) { Text("Load") }
                        }
                    }
                }
            }
        }
        error?.let {
            Text(
                it,
                color = MaterialTheme.colorScheme.error,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.padding(top = Spacing.sm),
            )
        }
    }
}
