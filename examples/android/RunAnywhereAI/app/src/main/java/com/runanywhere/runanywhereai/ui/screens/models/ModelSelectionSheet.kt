package com.runanywhere.runanywhereai.ui.screens.models

import android.Manifest
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.platform.LocalContext
import com.runanywhere.runanywhereai.download.ModelDownloadService
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

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
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Header(title = viewModel.title, onCancel = onDismiss)

            device?.let {
                SectionLabel("Your device")
                DeviceStatusCard(it, Modifier.padding(horizontal = dimens.spacingLg))
                Spacer(Modifier.height(dimens.spacingXs))
            }

            when {
                state.isLoading -> CenterNote("Loading models…", showSpinner = true)
                state.models.isEmpty() -> CenterNote("No models available")
                else -> PickerBody(viewModel, state, device, scope, onDismiss, onDelete = { pendingDelete = it })
            }

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
private fun PickerBody(
    viewModel: ModelSelectionViewModel,
    state: ModelSelectionState,
    device: DeviceInfo?,
    scope: CoroutineScope,
    onDismiss: () -> Unit,
    onDelete: (RAModelInfo) -> Unit,
) {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    var query by remember { mutableStateOf("") }
    val isSearching = query.isNotBlank()

    val onSelect: (RAModelInfo) -> Unit = { model -> scope.launch { if (viewModel.select(model)) onDismiss() } }

    // The download runs in a `dataSync` foreground service whose progress
    // notification Android 13+ silently suppresses unless POST_NOTIFICATIONS is
    // granted. Request it once, just-in-time, before the first download — but the
    // notification is a nicety, so proceed with the download whether the user
    // grants or denies (no re-prompt loop). On API < 33 `notificationsPermitted`
    // returns true, so we download straight through without ever launching.
    val pendingDownload = remember { mutableStateOf<RAModelInfo?>(null) }
    val notificationPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) {
        // Denied or granted: the notification is optional, so start the download.
        pendingDownload.value?.let { viewModel.download(it) }
        pendingDownload.value = null
    }
    val onDownload: (RAModelInfo) -> Unit = { model ->
        if (ModelDownloadService.notificationsPermitted(context)) {
            viewModel.download(model)
        } else {
            pendingDownload.value = model
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    val tier = device?.tier ?: HardwareTier.MID_RANGE
    val hasNpu = device?.hasNpu ?: false
    val isChat = viewModel.modality == ModelSelectionContext.LLM ||
        viewModel.modality == ModelSelectionContext.RAG_LLM

    // Chat pickers get the rich spread (default + a few LLMs + companions); every other
    // modality gets a single scoped "best for this device" highlight.
    val recommendation = remember(state.models, device) {
        if (isChat) ModelRecommendation.recommend(tier, hasNpu, state.models) else null
    }
    val scopedRecommended = remember(state.models, device) {
        if (isChat) null else ModelRecommendation.recommendedFor(viewModel.modality, tier, hasNpu, state.models)
    }
    val surfacedIds = recommendation?.allIds ?: setOfNotNull(scopedRecommended?.id)

    // Recommended section only in the default (non-search) view.
    if (!isSearching) {
        when {
            recommendation != null && recommendation.recommendedLLMs.isNotEmpty() -> {
                RecommendedSection(recommendation, device, viewModel, state, onSelect, onDownload, onDelete)
                Spacer(Modifier.height(dimens.spacingMd))
            }
            scopedRecommended != null -> {
                SectionLabel("Recommended for your device")
                PickerModelRow(
                    viewModel, state, scopedRecommended, onSelect, onDownload, onDelete,
                    highlightLabel = "Top pick",
                )
                Spacer(Modifier.height(dimens.spacingMd))
            }
        }
    }

    SectionLabel("Browse by model")
    SearchField(query = query, onQueryChange = { query = it })
    Spacer(Modifier.height(dimens.spacingXs))

    // Families to show. In the default view, hide models already surfaced above so the
    // list stays short. Search matches friendly family/variant names + tags only.
    val families = state.models
        .filter { isSearching || it.id !in surfacedIds }
        .toFamilyGroups()
        .mapNotNull { group ->
            if (!isSearching) return@mapNotNull group
            val matches = group.matchesQuery(query)
            when {
                group.family.matchesQuery(query) -> group
                matches.isNotEmpty() -> group.copy(variants = matches)
                else -> null
            }
        }

    if (families.isEmpty()) {
        CenterNote(if (isSearching) "No models match your search" else "No additional models")
        return
    }

    families.forEach { group ->
        FamilyCard(
            group = group,
            viewModel = viewModel,
            state = state,
            onSelect = onSelect,
            onDownload = onDownload,
            onDelete = onDelete,
            modifier = Modifier.padding(horizontal = dimens.spacingLg),
            // Auto-expand single-family search results so variants are visible immediately.
            initiallyExpanded = isSearching && families.size <= 2,
        )
    }
}

@Composable
private fun RecommendedSection(
    recommendation: RecommendedSelection,
    device: DeviceInfo?,
    viewModel: ModelSelectionViewModel,
    state: ModelSelectionState,
    onSelect: (RAModelInfo) -> Unit,
    onDownload: (RAModelInfo) -> Unit,
    onDelete: (RAModelInfo) -> Unit,
) {
    val dimens = LocalDimens.current
    SectionLabel("Recommended for your device")

    val defaultId = recommendation.defaultModel?.id
    recommendation.defaultModel?.let { model ->
        PickerModelRow(
            viewModel, state, model, onSelect, onDownload, onDelete,
            highlightLabel = "Top pick",
        )
    }
    recommendation.recommendedLLMs.filter { it.id != defaultId }.forEach { model ->
        PickerModelRow(viewModel, state, model, onSelect, onDownload, onDelete)
    }

    val companions = listOfNotNull(
        recommendation.vlm,
        recommendation.asr,
        recommendation.tts,
        recommendation.embedding,
    )
    if (companions.isNotEmpty()) {
        Spacer(Modifier.height(dimens.spacingXs))
        SectionLabel("Also recommended")
        companions.forEach { model ->
            PickerModelRow(viewModel, state, model, onSelect, onDownload, onDelete)
        }
    }
}

@Composable
private fun PickerModelRow(
    viewModel: ModelSelectionViewModel,
    state: ModelSelectionState,
    model: RAModelInfo,
    onSelect: (RAModelInfo) -> Unit,
    onDownload: (RAModelInfo) -> Unit,
    onDelete: (RAModelInfo) -> Unit,
    highlightLabel: String? = null,
) {
    val dimens = LocalDimens.current
    ModelRow(
        model = model,
        isCurrent = state.currentModelId == model.id,
        isReady = viewModel.isReady(model),
        isBusy = state.busyModelId == model.id,
        progressPercent = if (state.busyModelId == model.id) state.progressPercent else null,
        highlightLabel = highlightLabel,
        onSelect = { onSelect(model) },
        onDownload = { onDownload(model) },
        onCancel = { viewModel.cancelDownload(model.id) },
        onDelete = if (viewModel.isDeletable(model)) ({ onDelete(model) }) else null,
        modifier = Modifier.padding(horizontal = dimens.spacingLg),
    )
}

@Composable
private fun SearchField(query: String, onQueryChange: (String) -> Unit) {
    val dimens = LocalDimens.current
    OutlinedTextField(
        value = query,
        onValueChange = onQueryChange,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = dimens.spacingLg),
        singleLine = true,
        shape = RoundedCornerShape(dimens.radiusLg),
        leadingIcon = { Icon(RACIcons.Outline.Search, contentDescription = null) },
        trailingIcon = {
            if (query.isNotBlank()) {
                IconButton(onClick = { onQueryChange("") }) {
                    Icon(RACIcons.Outline.Close, contentDescription = "Clear search")
                }
            }
        },
        placeholder = { Text("Search models — chat, vision, voice…") },
    )
}

// Friendly-only search: family title/tagline. No quant, backend, or ids.
private fun ModelFamily.matchesQuery(query: String): Boolean {
    val q = query.trim().lowercase()
    if (q.isEmpty()) return true
    return "$title $tagline".lowercase().contains(q)
}

// Variant-level friendly search: name + clean tags only.
private fun FamilyGroup.matchesQuery(query: String): List<RAModelInfo> {
    val q = query.trim().lowercase()
    if (q.isEmpty()) return variants
    return variants.filter { variant ->
        val tags = variant.consumerTags().joinToString(" ") { it.label }
        "${variant.name} ${variant.variantFeelLabel()} $tags".lowercase().contains(q)
    }
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
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            maxLines = 2,
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .padding(start = 96.dp, end = 24.dp),
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
