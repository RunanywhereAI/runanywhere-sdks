package com.runanywhere.runanywhereai.ui.screens.models.huggingface

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.data.hf.HfModelSummary
import com.runanywhere.runanywhereai.data.hf.HfRepoFile
import com.runanywhere.runanywhereai.ui.screens.models.formatModelSize
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HuggingFaceSearchSheet(
    onDismiss: () -> Unit,
    onModelAdded: () -> Unit,
    viewModel: HuggingFaceSearchViewModel = viewModel(),
) {
    val dimens = LocalDimens.current
    val state by viewModel.state.collectAsState()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // A completed download refreshes the host picker exactly once.
    LaunchedEffect(state.addedModelId) {
        if (state.addedModelId != null) {
            onModelAdded()
            viewModel.clearAdded()
        }
    }

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
                .fillMaxHeight(SHEET_HEIGHT_FRACTION)
                .padding(bottom = dimens.spacingLg),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Header(
                title = state.selectedRepo?.substringAfterLast('/') ?: "Add from Hugging Face",
                showBack = state.selectedRepo != null,
                onBack = viewModel::backToResults,
                onCancel = onDismiss,
            )

            if (state.selectedRepo == null) {
                SearchField(
                    query = state.query,
                    onQueryChange = viewModel::onQueryChange,
                    onSearch = viewModel::search,
                )
            }

            state.error?.let { message ->
                Text(
                    message,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(horizontal = dimens.spacingLg),
                )
            }

            Box(modifier = Modifier
                .weight(1f)
                .fillMaxWidth()) {
                when (state.phase) {
                    HuggingFacePhase.IDLE ->
                        CenterNote("Search Hugging Face for downloadable GGUF models.")
                    HuggingFacePhase.SEARCHING ->
                        CenterNote("Searching…", showSpinner = true)
                    HuggingFacePhase.LOADING_FILES ->
                        CenterNote("Loading files…", showSpinner = true)
                    HuggingFacePhase.RESULTS ->
                        ResultsList(state.results, onSelect = viewModel::openRepo)
                    HuggingFacePhase.REPO_DETAIL ->
                        FilesList(
                            files = state.files,
                            downloadingPath = state.downloadingPath,
                            progress = state.downloadProgress,
                            onDownload = { file -> viewModel.download(state.selectedRepo.orEmpty(), file) },
                        )
                }
            }

            Text(
                "Files download and run privately on your device.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = dimens.spacingLg),
            )
        }
    }
}

@Composable
private fun ResultsList(results: List<HfModelSummary>, onSelect: (String) -> Unit) {
    val dimens = LocalDimens.current
    if (results.isEmpty()) {
        CenterNote("No models match your search.")
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(
            horizontal = dimens.spacingLg,
            vertical = dimens.spacingXs,
        ),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
    ) {
        items(results, key = { it.id }) { repo -> RepoRow(repo, onSelect) }
    }
}

@Composable
private fun RepoRow(repo: HfModelSummary, onSelect: (String) -> Unit) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onSelect(repo.id) }
            .padding(vertical = dimens.spacingSm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                repo.id,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                "${formatCount(repo.downloads)} downloads · ${formatCount(repo.likes)} likes",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            RACIcons.Outline.ChevronRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun FilesList(
    files: List<HfRepoFile>,
    downloadingPath: String?,
    progress: Int?,
    onDownload: (HfRepoFile) -> Unit,
) {
    val dimens = LocalDimens.current
    if (files.isEmpty()) {
        CenterNote("No GGUF files in this repository.")
        return
    }
    LazyColumn(
        modifier = Modifier.fillMaxWidth(),
        contentPadding = PaddingValues(
            horizontal = dimens.spacingLg,
            vertical = dimens.spacingXs,
        ),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
    ) {
        items(files, key = { it.path }) { file ->
            FileRow(
                file = file,
                isDownloading = downloadingPath == file.path,
                anyDownloading = downloadingPath != null,
                progress = progress,
                onDownload = { onDownload(file) },
            )
        }
    }
}

@Composable
private fun FileRow(
    file: HfRepoFile,
    isDownloading: Boolean,
    anyDownloading: Boolean,
    progress: Int?,
    onDownload: () -> Unit,
) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = dimens.spacingSm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                file.quantLabel,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            Text(
                formatModelSize(file.sizeBytes),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Spacer(Modifier.width(dimens.spacingSm))
        when {
            isDownloading -> Row(verticalAlignment = Alignment.CenterVertically) {
                LinearProgressIndicator(
                    progress = { (progress ?: 0) / 100f },
                    modifier = Modifier.width(DOWNLOAD_BAR_WIDTH.dp),
                )
                Spacer(Modifier.width(dimens.spacingSm))
                Text("${progress ?: 0}%", style = MaterialTheme.typography.bodySmall)
            }
            else -> Button(onClick = onDownload, enabled = !anyDownloading) {
                Icon(
                    RACIcons.Outline.Download,
                    contentDescription = null,
                    modifier = Modifier.size(dimens.iconSm),
                )
                Spacer(Modifier.width(dimens.spacingXs))
                Text("Get")
            }
        }
    }
}

@Composable
private fun Header(title: String, showBack: Boolean, onBack: () -> Unit, onCancel: () -> Unit) {
    val dimens = LocalDimens.current
    Box(modifier = Modifier
        .fillMaxWidth()
        .padding(vertical = dimens.spacingMd)) {
        if (showBack) {
            IconButton(onClick = onBack, modifier = Modifier.align(Alignment.CenterStart)) {
                Icon(RACIcons.Outline.ArrowLeft, contentDescription = "Back")
            }
        } else {
            TextButton(onClick = onCancel, modifier = Modifier.align(Alignment.CenterStart)) {
                Text("Cancel", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Text(
            title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .padding(horizontal = 72.dp),
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SearchField(query: String, onQueryChange: (String) -> Unit, onSearch: () -> Unit) {
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
        placeholder = { Text("Search Hugging Face — e.g. Qwen3 GGUF") },
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { onSearch() }),
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
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

private const val SHEET_HEIGHT_FRACTION = 0.92f
private const val DOWNLOAD_BAR_WIDTH = 96

// Compact download/like counts: 12345 -> "12.3k", 2_100_000 -> "2.1M".
private fun formatCount(value: Long): String = when {
    value >= 1_000_000 -> "%.1fM".format(value / 1_000_000.0)
    value >= 1_000 -> "%.1fk".format(value / 1_000.0)
    else -> value.toString()
}
