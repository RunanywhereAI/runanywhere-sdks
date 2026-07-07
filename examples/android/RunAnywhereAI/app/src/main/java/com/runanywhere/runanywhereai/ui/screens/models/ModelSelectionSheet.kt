package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.launch

private val recommendedModelIds = setOf(
    "qwen3-0.6b-q4_k_m",
    "lfm2-350m-q4_k_m",
    "lfm2-350m-q8_0",
    "lfm2.5-1.2b-instruct-q4_k_m",
    "qwen2.5-0.5b-instruct-q6_k",
    "qwen3-1.7b-q4_k_m",
    "qwen3.5-0.8b-q4_k_m",
    "smolvlm2-256m-video-instruct-q8_0",
    "smolvlm2-500m-video-instruct-q8_0",
    "qwen2-vl-2b-instruct-q4_k_m",
    "sherpa-onnx-whisper-tiny.en",
    "vits-piper-en_US-lessac-medium",
    "all-minilm-l6-v2",
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelSelectionSheet(
    viewModel: ModelSelectionViewModel,
    onDismiss: () -> Unit,
) {
    val dimens = LocalDimens.current
    val state = viewModel.state
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val device = remember { runCatching { DeviceInfo.current() }.getOrNull() }
    var pendingDelete by remember { mutableStateOf<RAModelInfo?>(null) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = dimens.radiusLg, topEnd = dimens.radiusLg),
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        dragHandle = null,
        contentWindowInsets = { WindowInsets.systemBars },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(bottom = dimens.spacingXl),
        ) {
            Header(title = viewModel.title, onCancel = onDismiss)

            device?.let {
                SectionLabel("Device")
                Spacer(Modifier.height(dimens.spacingSm))
                DeviceStatusCard(it, Modifier.padding(horizontal = dimens.spacingLg))
                Spacer(Modifier.height(dimens.spacingLg))
            }

            when {
                state.isLoading -> CenterNote("Loading models…", showSpinner = true)
                state.models.isEmpty() -> CenterNote("No models available")
                else -> ModelList(viewModel, state, scope, onDismiss, onDelete = { pendingDelete = it })
            }

            Spacer(Modifier.height(dimens.spacingMd))
            Text(
                "All models run privately on your device.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = dimens.spacingLg),
            )
        }
    }

    state.error?.let { message ->
        AlertDialog(
            onDismissRequest = viewModel::clearError,
            confirmButton = { TextButton(onClick = viewModel::clearError) { Text("OK") } },
            title = { Text("Error") },
            text = { Text(message) },
        )
    }

    pendingDelete?.let { model ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.delete(model)
                        pendingDelete = null
                    },
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text("Cancel") }
            },
            title = { Text("Delete model") },
            text = { Text("Delete ${model.name} from this device? You can download it again later.") },
        )
    }
}

@Composable
private fun ModelList(
    viewModel: ModelSelectionViewModel,
    state: ModelSelectionState,
    scope: kotlinx.coroutines.CoroutineScope,
    onDismiss: () -> Unit,
    onDelete: (RAModelInfo) -> Unit,
) {
    val dimens = LocalDimens.current
    var query by remember { mutableStateOf("") }
    var backendFilter by remember { mutableStateOf(ModelBackendFilter.ALL) }

    val sorted = state.models.sortedWith(
        compareBy({ if (viewModel.isReady(it)) 0 else 1 }, { it.name }),
    )
    val filtered = sorted.filter {
        it.matchesQuery(query) &&
            backendFilter.matches(it)
    }
    val recommended = filtered.filter { it.id in recommendedModelIds }
    val grouped = filtered.filterNot { it.id in recommendedModelIds }.groupBy { it.consumerGroup() }

    FilterSection(
        query = query,
        onQueryChange = { query = it },
        backendFilter = backendFilter,
        onBackendFilter = { backendFilter = it },
        shownCount = filtered.size,
        totalCount = sorted.size,
    )
    Spacer(Modifier.height(dimens.spacingLg))

    if (filtered.isEmpty()) {
        CenterNote("No models match these filters")
        return
    }

    if (recommended.isNotEmpty()) {
        SectionLabel("Recommended")
        Spacer(Modifier.height(dimens.spacingSm))
        recommended.forEach { model ->
            PickerModelRow(viewModel, state, scope, model, onDismiss, onDelete)
            Spacer(Modifier.height(dimens.spacingSm))
        }
        Text(
            "Consumer-friendly defaults for chat, vision, voice, and documents.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = dimens.spacingLg),
        )
        Spacer(Modifier.height(dimens.spacingLg))
    }

    SectionLabel("Available Models")
    Spacer(Modifier.height(dimens.spacingSm))

    ConsumerModelGroup.entries.forEach { group ->
        val models = grouped[group].orEmpty()
        if (models.isEmpty()) return@forEach
        SectionLabel(group.title)
        Spacer(Modifier.height(dimens.spacingSm))
        models.forEach { model ->
            PickerModelRow(viewModel, state, scope, model, onDismiss, onDelete)
            Spacer(Modifier.height(dimens.spacingSm))
        }
        Text(
            group.footer,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = dimens.spacingLg),
        )
        Spacer(Modifier.height(dimens.spacingLg))
    }

    if (filtered.any { it.supports_lora }) {
        SectionLabel("LoRA & Adapters")
        Spacer(Modifier.height(dimens.spacingSm))
        Text(
            "Adapters customize a loaded base chat model. Open Adapters from the drawer after choosing a LoRA-ready chat model.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = dimens.spacingLg),
        )
    }
}

@Composable
private fun PickerModelRow(
    viewModel: ModelSelectionViewModel,
    state: ModelSelectionState,
    scope: kotlinx.coroutines.CoroutineScope,
    model: RAModelInfo,
    onDismiss: () -> Unit,
    onDelete: (RAModelInfo) -> Unit,
) {
    val dimens = LocalDimens.current
    ModelRow(
        model = model,
        isCurrent = state.currentModelId == model.id,
        isReady = viewModel.isReady(model),
        isBusy = state.busyModelId == model.id,
        progressPercent = if (state.busyModelId == model.id) state.progressPercent else null,
        onSelect = {
            scope.launch {
                if (viewModel.select(model)) onDismiss()
            }
        },
        onDownload = { viewModel.download(model) },
        onDelete = if (viewModel.isDeletable(model)) ({ onDelete(model) }) else null,
        modifier = Modifier.padding(horizontal = dimens.spacingLg),
    )
}

@Composable
private fun FilterSection(
    query: String,
    onQueryChange: (String) -> Unit,
    backendFilter: ModelBackendFilter,
    onBackendFilter: (ModelBackendFilter) -> Unit,
    shownCount: Int,
    totalCount: Int,
) {
    val dimens = LocalDimens.current
    Column(
        modifier = Modifier.padding(horizontal = dimens.spacingLg),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) {
        OutlinedTextField(
            value = query,
            onValueChange = onQueryChange,
            modifier = Modifier.fillMaxWidth(),
            singleLine = true,
            shape = RoundedCornerShape(dimens.radiusLg),
            leadingIcon = {
                Icon(RACIcons.Outline.Search, contentDescription = null)
            },
            trailingIcon = {
                if (query.isNotBlank()) {
                    IconButton(onClick = { onQueryChange("") }) {
                        Icon(RACIcons.Outline.Close, contentDescription = "Clear search")
                    }
                }
            },
            placeholder = { Text("Search models, backends, private access") },
        )

        FilterRow("Backend") {
            ModelBackendFilter.entries.forEach { filter ->
                FilterChip(text = filter.title, selected = backendFilter == filter) { onBackendFilter(filter) }
            }
        }
        Text(
            "$shownCount of $totalCount models shown",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun FilterRow(label: String, content: @Composable () -> Unit) {
    val dimens = LocalDimens.current
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
        ) {
            content()
        }
    }
}

@Composable
private fun FilterChip(text: String, selected: Boolean, onClick: () -> Unit) {
    if (selected) {
        AssistChip(onClick = onClick, label = { Text(text) })
    } else {
        SuggestionChip(onClick = onClick, label = { Text(text) })
    }
}

private fun RAModelInfo.matchesQuery(query: String): Boolean {
    val trimmed = query.trim().lowercase()
    if (trimmed.isEmpty()) return true
    return listOf(
        id,
        name,
        framework.consumerBackendLabel(),
        framework.shortLabel(),
        consumerGroup().title,
        quantizationLabel(),
        if (requiresHfAuth()) "private hf auth hugging face" else "",
    ).joinToString(" ").lowercase().contains(trimmed)
}

@Composable
private fun Header(title: String, onCancel: () -> Unit) {
    val dimens = LocalDimens.current
    Box(modifier = Modifier
        .fillMaxWidth()
        .padding(vertical = dimens.spacingMd)) {
        TextButton(
            onClick = onCancel,
            modifier = Modifier.align(Alignment.CenterStart),
            colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.primary)
        ) {
            Text("Cancel", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.align(Alignment.Center),
        )
    }
}

@Composable
private fun SectionLabel(text: String) {
    val dimens = LocalDimens.current
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        fontWeight = FontWeight.Medium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = dimens.spacingLg),
    )
}

@Composable
private fun CenterNote(text: String, showSpinner: Boolean = false) {
    val dimens = LocalDimens.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(dimens.spacingXl),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (showSpinner) {
            CircularProgressIndicator()
            Spacer(Modifier.height(dimens.spacingMd))
        }
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
