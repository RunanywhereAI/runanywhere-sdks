package com.runanywhere.runanywhereai.ui.screens.rag

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.data.rag.DocumentExtractor
import com.runanywhere.runanywhereai.util.isExpandedScreen
import com.runanywhere.runanywhereai.ui.screens.chat.MarkdownText
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import kotlin.math.roundToInt

@Composable
fun RagScreen() {
    val dimens = LocalDimens.current
    val ragVm: RagViewModel = viewModel()
    val embeddingVm: ModelSelectionViewModel =
        viewModel(key = "rag-embedding", factory = ModelSelectionViewModel.Factory(ModelSelectionContext.RAG_EMBEDDING))
    val llmVm: ModelSelectionViewModel =
        viewModel(key = "rag-llm", factory = ModelSelectionViewModel.Factory(ModelSelectionContext.RAG_LLM))
    var sheet by remember { mutableStateOf<ModelSelectionViewModel?>(null) }

    val embeddingId = embeddingVm.state.currentModelId
    val llmId = llmVm.state.currentModelId
    val embeddingName = embeddingVm.state.models.firstOrNull { it.id == embeddingId }?.name
    val llmName = llmVm.state.models.firstOrNull { it.id == llmId }?.name
    val ready = embeddingId != null && llmId != null

    LaunchedEffect(embeddingId, llmId) { ragVm.onModelsChanged(embeddingId, llmId) }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null && embeddingId != null && llmId != null) ragVm.addDocument(uri, embeddingId, llmId)
    }

    val listState = rememberLazyListState()
    LaunchedEffect(ragVm.messages.size) {
        if (ragVm.messages.isNotEmpty()) listState.animateScrollToItem(ragVm.messages.size - 1)
    }

    var question by remember { mutableStateOf("") }

    // Once both models and at least one document are loaded, the setup card folds
    // into a compact bar to hand the screen over to the conversation. Tapping the
    // bar (or changing a model, which resets the pipeline) brings the full card back.
    var setupExpanded by remember { mutableStateOf(true) }
    LaunchedEffect(ready, ragVm.hasDocuments) {
        if (ready && ragVm.hasDocuments) setupExpanded = false
    }
    val collapsible = ready && ragVm.hasDocuments
    val showFullSetup = setupExpanded || !collapsible

    val onAdd = { picker.launch(DocumentExtractor.acceptedMimeTypes) }

    if (isExpandedScreen()) {
        // Wide screens: setup on the left, the Q&A conversation on the right.
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(dimens.screenPadding),
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Column(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .verticalScroll(rememberScrollState()),
            ) {
                SetupCard(
                    embeddingName = embeddingName,
                    llmName = llmName,
                    documents = ragVm.documents,
                    chunkCount = ragVm.chunkCount,
                    ready = ready,
                    isIngesting = ragVm.isIngesting,
                    collapsible = false,
                    onCollapse = {},
                    onPickEmbedding = { sheet = embeddingVm },
                    onPickLlm = { sheet = llmVm },
                    onAdd = onAdd,
                    onClear = ragVm::clearAll,
                )
            }
            VerticalDivider()
            ConversationPane(
                ragVm = ragVm,
                listState = listState,
                question = question,
                onQuestionChange = { question = it },
                onSend = { ragVm.ask(question); question = "" },
                ready = ready,
                modifier = Modifier
                    .weight(1.3f)
                    .fillMaxHeight()
                    .imePadding(),
            )
        }
    } else {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .imePadding()
                .padding(dimens.screenPadding),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            if (showFullSetup) {
                SetupCard(
                    embeddingName = embeddingName,
                    llmName = llmName,
                    documents = ragVm.documents,
                    chunkCount = ragVm.chunkCount,
                    ready = ready,
                    isIngesting = ragVm.isIngesting,
                    collapsible = collapsible,
                    onCollapse = { setupExpanded = false },
                    onPickEmbedding = { sheet = embeddingVm },
                    onPickLlm = { sheet = llmVm },
                    onAdd = onAdd,
                    onClear = ragVm::clearAll,
                )
            } else {
                CompactSetupBar(
                    documentCount = ragVm.documents.size,
                    chunkCount = ragVm.chunkCount,
                    isIngesting = ragVm.isIngesting,
                    onAdd = onAdd,
                    onExpand = { setupExpanded = true },
                )
            }
            ConversationPane(
                ragVm = ragVm,
                listState = listState,
                question = question,
                onQuestionChange = { question = it },
                onSend = { ragVm.ask(question); question = "" },
                ready = ready,
                modifier = Modifier.weight(1f),
            )
        }
    }

    sheet?.let { active -> ModelSelectionSheet(viewModel = active, onDismiss = { sheet = null }) }
}

@Composable
private fun Divider() {
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
}

// The model + documents setup surface, shared by the compact and two-pane layouts.
@Composable
private fun SetupCard(
    embeddingName: String?,
    llmName: String?,
    documents: List<String>,
    chunkCount: Int,
    ready: Boolean,
    isIngesting: Boolean,
    collapsible: Boolean,
    onCollapse: () -> Unit,
    onPickEmbedding: () -> Unit,
    onPickLlm: () -> Unit,
    onAdd: () -> Unit,
    onClear: () -> Unit,
) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column {
            if (collapsible) {
                CollapseHeader(onCollapse = onCollapse)
                Divider()
            }
            SetupRow(RACIcons.Outline.Database, "Embedding model", embeddingName, onPickEmbedding)
            Divider()
            SetupRow(RACIcons.Outline.MessageCircle, "Language model", llmName, onPickLlm)
            Divider()
            DocumentsSection(
                documents = documents,
                chunkCount = chunkCount,
                ready = ready,
                isIngesting = isIngesting,
                onAdd = onAdd,
                onClear = onClear,
            )
        }
    }
}

// Messages list + error + input bar. Self-contained Column so the messages area
// can take the flexible space in whatever parent (stacked or side-by-side) hosts it.
@Composable
private fun ConversationPane(
    ragVm: RagViewModel,
    listState: LazyListState,
    question: String,
    onQuestionChange: (String) -> Unit,
    onSend: () -> Unit,
    ready: Boolean,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        Box(modifier = Modifier.weight(1f)) {
            if (ragVm.messages.isEmpty()) {
                EmptyState(ready = ready, hasDocuments = ragVm.hasDocuments)
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
                ) {
                    items(ragVm.messages) { message -> MessageBubble(message) }
                    if (ragVm.isQuerying) {
                        item { SearchingRow() }
                    }
                }
            }
        }
        ragVm.error?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.fillMaxWidth(),
            )
        }
        InputBar(
            value = question,
            onValueChange = onQuestionChange,
            enabled = ragVm.hasDocuments && !ragVm.isQuerying,
            onSend = onSend,
        )
    }
}

// Compact stand-in for the setup card once models + a document are loaded: a one-line
// summary that reclaims the screen for chat and expands back on tap.
@Composable
private fun CompactSetupBar(
    documentCount: Int,
    chunkCount: Int,
    isIngesting: Boolean,
    onAdd: () -> Unit,
    onExpand: () -> Unit,
) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onExpand)
                .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = RACIcons.Outline.FileText,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconSm),
            )
            Text(
                text = "$documentCount document${if (documentCount == 1) "" else "s"} · $chunkCount chunks",
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            if (isIngesting) {
                CircularProgressIndicator(modifier = Modifier.size(dimens.iconSm), strokeWidth = 2.dp)
            } else {
                Icon(
                    imageVector = RACIcons.Outline.Plus,
                    contentDescription = "Add document",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier
                        .size(dimens.iconMd)
                        .clickable(onClick = onAdd)
                        .padding(2.dp),
                )
            }
            Icon(
                imageVector = RACIcons.Outline.ChevronDown,
                contentDescription = "Expand setup",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(dimens.iconSm),
            )
        }
    }
}

// Collapse affordance shown at the top of the full setup card once it's collapsible.
@Composable
private fun CollapseHeader(onCollapse: () -> Unit) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onCollapse)
            .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingSm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "Setup",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        Icon(
            imageVector = RACIcons.Outline.ChevronUp,
            contentDescription = "Collapse setup",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconSm),
        )
    }
}

@Composable
private fun SetupRow(icon: ImageVector, label: String, value: String?, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    val selected = value != null
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconMd),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                text = value ?: "Tap to select",
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Icon(
            imageVector = RACIcons.Outline.ChevronRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconSm),
        )
    }
}

@Composable
private fun DocumentsSection(
    documents: List<String>,
    chunkCount: Int,
    ready: Boolean,
    isIngesting: Boolean,
    onAdd: () -> Unit,
    onClear: () -> Unit,
) {
    val dimens = LocalDimens.current
    Column(
        modifier = Modifier.padding(dimens.spacingLg),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = if (documents.isEmpty()) "Documents" else "${documents.size} document${if (documents.size == 1) "" else "s"} · $chunkCount chunks",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            if (documents.isNotEmpty()) {
                TextButton(onClick = onClear) { Text("Clear") }
            }
        }

        documents.forEach { name ->
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            ) {
                Icon(
                    imageVector = RACIcons.Outline.FileText,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(dimens.iconSm),
                )
                Text(
                    name,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }

        val addLabel = if (documents.isEmpty()) "Add document" else "Add another"
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHighest,
            shape = RoundedCornerShape(dimens.radiusMd),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(dimens.radiusMd))
                    .then(if (ready && !isIngesting) Modifier.clickable(onClick = onAdd) else Modifier)
                    .fillMaxWidth()
                    .padding(dimens.spacingMd),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (isIngesting) {
                    CircularProgressIndicator(modifier = Modifier.size(dimens.iconSm), strokeWidth = 2.dp)
                    Text(
                        "Reading…",
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(start = dimens.spacingSm),
                    )
                } else {
                    val tint =
                        if (ready) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
                    Icon(RACIcons.Outline.Plus, contentDescription = null, tint = tint, modifier = Modifier.size(dimens.iconSm))
                    Text(
                        text = if (ready) addLabel else "Pick models first",
                        style = MaterialTheme.typography.bodyMedium,
                        color = tint,
                        modifier = Modifier.padding(start = dimens.spacingSm),
                    )
                }
            }
        }
    }
}

@Composable
private fun EmptyState(ready: Boolean, hasDocuments: Boolean) {
    val dimens = LocalDimens.current
    val text = when {
        !ready -> "Pick an embedding model and an LLM to begin"
        !hasDocuments -> "Add a document, then ask a question about it"
        else -> "Ask a question about your documents"
    }
    Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = RACIcons.Outline.Database,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconLg),
            )
            Text(
                text = text,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun MessageBubble(message: RagMessage) {
    val dimens = LocalDimens.current
    if (message.isUser) {
        Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
            Box(
                modifier = Modifier
                    .widthIn(max = 320.dp)
                    .clip(RoundedCornerShape(dimens.radiusMd))
                    .background(MaterialTheme.colorScheme.primary)
                    .padding(horizontal = dimens.spacingMd, vertical = dimens.spacingSm),
            ) {
                Text(message.text, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onPrimary)
            }
        }
        return
    }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
    ) {
        Box(
            modifier = Modifier
                .clip(RoundedCornerShape(dimens.radiusMd))
                .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                .padding(horizontal = dimens.spacingMd, vertical = dimens.spacingSm),
        ) {
            MarkdownText(
                markdown = message.text,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
        if (message.sources.isNotEmpty()) {
            SourcesSection(sources = message.sources, elapsedMs = message.elapsedMs)
        }
    }
}

@Composable
private fun SourcesSection(sources: List<RagSource>, elapsedMs: Long) {
    val dimens = LocalDimens.current
    var expanded by remember { mutableStateOf(false) }
    Column(modifier = Modifier.padding(start = dimens.spacingXs)) {
        Row(
            modifier = Modifier.clickable { expanded = !expanded },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
        ) {
            Icon(
                imageVector = if (expanded) RACIcons.Outline.ChevronUp else RACIcons.Outline.ChevronDown,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(dimens.iconSm),
            )
            val timing = if (elapsedMs > 0) " · ${"%.1f".format(elapsedMs / 1000.0)}s" else ""
            Text(
                "${sources.size} source${if (sources.size == 1) "" else "s"}$timing",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        AnimatedVisibility(visible = expanded) {
            Column(
                modifier = Modifier.padding(top = dimens.spacingXs),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            ) {
                sources.forEach { source -> SourceCard(source) }
            }
        }
    }
}

@Composable
private fun SourceCard(source: RagSource) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainer,
        shape = RoundedCornerShape(dimens.radiusMd),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(dimens.spacingMd),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = source.document.ifBlank { "Document" },
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Text("${(source.score * 100).roundToInt()}%", style = RACTextStyles.Metric)
            }
            Text(
                text = source.text,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurface,
                maxLines = 4,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun SearchingRow() {
    val dimens = LocalDimens.current
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
        CircularProgressIndicator(modifier = Modifier.size(dimens.iconSm), strokeWidth = 2.dp)
        Text(
            "Searching your documents…",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun InputBar(
    value: String,
    onValueChange: (String) -> Unit,
    enabled: Boolean,
    onSend: () -> Unit,
) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) {
        OutlinedTextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.weight(1f),
            enabled = enabled,
            placeholder = { Text("Ask about your documents") },
            maxLines = 3,
            shape = RoundedCornerShape(dimens.radiusLg),
        )
        val canSend = enabled && value.isNotBlank()
        val tint = if (canSend) primaryGreen else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
        IconButton(onClick = onSend, enabled = canSend) {
            Icon(RACIcons.Outline.Send, contentDescription = "Send", tint = tint, modifier = Modifier.size(dimens.iconMd))
        }
    }
}
