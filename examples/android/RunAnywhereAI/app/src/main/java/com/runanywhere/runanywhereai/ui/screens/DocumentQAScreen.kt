package com.runanywhere.runanywhereai.ui.screens

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.models.DocumentInfo
import com.runanywhere.runanywhereai.models.RAGEvent
import com.runanywhere.runanywhereai.models.RAGMessage
import com.runanywhere.runanywhereai.models.RAGUiState
import com.runanywhere.runanywhereai.ui.components.ChatInputBar
import com.runanywhere.runanywhereai.ui.components.MarkdownText
import com.runanywhere.runanywhereai.ui.components.RAButton
import com.runanywhere.runanywhereai.ui.components.RAButtonStyle
import com.runanywhere.runanywhereai.ui.components.RACard
import com.runanywhere.runanywhereai.ui.components.RACardVariant
import com.runanywhere.runanywhereai.ui.components.RAProgressBar
import com.runanywhere.runanywhereai.ui.icons.RAIcons
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.viewmodels.RAGViewModel
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import kotlinx.collections.immutable.ImmutableList
import kotlinx.coroutines.launch

// -- File picker MIME types --
private val SUPPORTED_MIME_TYPES = arrayOf("application/pdf", "application/json")

@Composable
fun DocumentRagScreen(
    onBack: () -> Unit,
    viewModel: RAGViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val listState = rememberLazyListState()
    var input by rememberSaveable { mutableStateOf("") }
    val snackbarHostState = remember { SnackbarHostState() }

    // Model picker state
    var showEmbeddingPicker by remember { mutableStateOf(false) }
    var showLLMPicker by remember { mutableStateOf(false) }

    // Document management sheet
    var showDocumentSheet by remember { mutableStateOf(false) }

    // File picker
    val documentPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? ->
        if (uri != null) {
            viewModel.loadDocument(context, uri)
        }
    }

    // Collect one-shot events
    LaunchedEffect(Unit) {
        viewModel.events.collect { event ->
            when (event) {
                is RAGEvent.ScrollToBottom -> {
                    val state = uiState as? RAGUiState.Ready
                    val count = state?.messages?.size ?: 0
                    if (count > 0) {
                        listState.animateScrollToItem(count - 1)
                    }
                }
                is RAGEvent.ShowSnackbar -> {
                    snackbarHostState.showSnackbar(event.message)
                }
            }
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        containerColor = MaterialTheme.colorScheme.background,
    ) { _ ->

    when (val state = uiState) {
        is RAGUiState.Ready -> {
            DocumentQAContent(
                state = state,
                input = input,
                onInputChange = { input = it },
                listState = listState,
                onSend = {
                    val text = input.trim()
                    if (text.isNotBlank()) {
                        viewModel.askQuestion(text)
                        input = ""
                    }
                },
                onAddDocument = { documentPickerLauncher.launch(SUPPORTED_MIME_TYPES) },
                onSelectEmbeddingModel = { showEmbeddingPicker = true },
                onSelectLLMModel = { showLLMPicker = true },
                onManageDocuments = { showDocumentSheet = true },
                onClearError = { viewModel.clearError() },
            )
        }
    }

    // Embedding model picker
    if (showEmbeddingPicker) {
        RAGModelPickerSheet(
            context = ModelSelectionContext.RAG_EMBEDDING,
            onDismiss = { showEmbeddingPicker = false },
            onModelSelected = { model ->
                viewModel.onEmbeddingModelSelected(model)
                showEmbeddingPicker = false
            },
        )
    }

    // LLM model picker
    if (showLLMPicker) {
        RAGModelPickerSheet(
            context = ModelSelectionContext.RAG_LLM,
            onDismiss = { showLLMPicker = false },
            onModelSelected = { model ->
                viewModel.onLLMModelSelected(model)
                showLLMPicker = false
            },
        )
    }

    // Document management sheet
    if (showDocumentSheet) {
        val state = uiState as? RAGUiState.Ready
        if (state != null) {
            DocumentManagementSheet(
                documents = state.documents,
                onDismiss = { showDocumentSheet = false },
                onClearAll = {
                    viewModel.clearAllDocuments()
                    showDocumentSheet = false
                },
                onAddMore = {
                    documentPickerLauncher.launch(SUPPORTED_MIME_TYPES)
                    showDocumentSheet = false
                },
            )
        }
    }

    } // Scaffold
}

@Composable
private fun DocumentQAContent(
    state: RAGUiState.Ready,
    input: String,
    onInputChange: (String) -> Unit,
    listState: LazyListState,
    onSend: () -> Unit,
    onAddDocument: () -> Unit,
    onSelectEmbeddingModel: () -> Unit,
    onSelectLLMModel: () -> Unit,
    onManageDocuments: () -> Unit,
    onClearError: () -> Unit,
) {
    val density = LocalDensity.current
    var inputBarHeightPx by remember { mutableIntStateOf(0) }
    val inputBarHeightDp = remember(inputBarHeightPx) {
        with(density) { inputBarHeightPx.toDp() }
    }

    val coroutineScope = rememberCoroutineScope()

    val canSend = input.isNotBlank() && state.canAskQuestion

    val isAtBottom by remember {
        derivedStateOf {
            val layoutInfo = listState.layoutInfo
            val lastVisibleItem = layoutInfo.visibleItemsInfo.lastOrNull()
            lastVisibleItem == null || lastVisibleItem.index >= layoutInfo.totalItemsCount - 1
        }
    }

    // Auto-scroll during streaming answer
    val lastMessage = state.messages.lastOrNull()
    LaunchedEffect(state.messages.size, lastMessage?.answer) {
        if (state.messages.isNotEmpty()) {
            listState.animateScrollToItem(state.messages.size - 1)
        }
    }

    // Auto-scroll when keyboard opens
    @OptIn(ExperimentalLayoutApi::class)
    val isImeVisible = WindowInsets.isImeVisible
    LaunchedEffect(isImeVisible) {
        if (isImeVisible && isAtBottom && state.messages.isNotEmpty()) {
            listState.animateScrollToItem(state.messages.size - 1)
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // Main content
        if (!state.areModelsReady) {
            ModelSetupView(
                state = state,
                onSelectEmbeddingModel = onSelectEmbeddingModel,
                onSelectLLMModel = onSelectLLMModel,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(bottom = inputBarHeightDp),
            )
        } else if (!state.hasDocuments && state.messages.isEmpty()) {
            EmptyDocumentView(
                state = state,
                onAddDocument = onAddDocument,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(bottom = inputBarHeightDp),
            )
        } else {
            QAConversationView(
                state = state,
                listState = listState,
                onManageDocuments = onManageDocuments,
                onAddDocument = onAddDocument,
                onClearError = onClearError,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(bottom = inputBarHeightDp),
            )
        }

        // Scroll-to-bottom FAB
        AnimatedVisibility(
            visible = !isAtBottom && state.messages.isNotEmpty(),
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 16.dp, bottom = inputBarHeightDp + 12.dp),
        ) {
            SmallFloatingActionButton(
                onClick = {
                    coroutineScope.launch {
                        if (state.messages.isNotEmpty()) {
                            listState.animateScrollToItem(state.messages.size - 1)
                        }
                    }
                },
                shape = CircleShape,
                containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                contentColor = MaterialTheme.colorScheme.onSurface,
            ) {
                Icon(
                    imageVector = RAIcons.ChevronDown,
                    contentDescription = "Scroll to bottom",
                    modifier = Modifier.size(20.dp),
                )
            }
        }

        // Input bar pinned to bottom
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .imePadding(),
        ) {
            Column(modifier = Modifier.onSizeChanged { inputBarHeightPx = it.height }) {
                HorizontalDivider(
                    thickness = 0.5.dp,
                    color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                )
                ChatInputBar(
                    input = input,
                    onInputChange = onInputChange,
                    onSend = onSend,
                    canSend = canSend,
                    isGenerating = state.isQuerying,
                    onCancel = { /* RAG queries are not cancellable */ },
                )
            }
        }
    }
}

// ============================================================================
// State 1: Model Setup (no models selected)
// ============================================================================

@Composable
private fun ModelSetupView(
    state: RAGUiState.Ready,
    onSelectEmbeddingModel: () -> Unit,
    onSelectLLMModel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = RAIcons.FileText,
            contentDescription = null,
            modifier = Modifier.size(48.dp),
            tint = MaterialTheme.colorScheme.primary,
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Document Q&A",
            style = MaterialTheme.typography.headlineSmall,
            color = MaterialTheme.colorScheme.onSurface,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Select models to start asking questions about your documents",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Model selection cards
        ModelSelectionCard(
            label = "Embedding Model",
            selectedName = state.embeddingModelName,
            isSelected = state.hasEmbeddingModel,
            onClick = onSelectEmbeddingModel,
        )

        Spacer(modifier = Modifier.height(12.dp))

        ModelSelectionCard(
            label = "LLM Model",
            selectedName = state.llmModelName,
            isSelected = state.hasLLMModel,
            onClick = onSelectLLMModel,
        )
    }
}

@Composable
private fun ModelSelectionCard(
    label: String,
    selectedName: String?,
    isSelected: Boolean,
    onClick: () -> Unit,
) {
    RACard(
        modifier = Modifier.clickable(onClick = onClick),
        variant = if (isSelected) RACardVariant.Standard else RACardVariant.Outlined,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = label,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(modifier = Modifier.height(2.dp))
                Text(
                    text = selectedName ?: "Tap to select",
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = if (isSelected) FontWeight.Medium else FontWeight.Normal,
                    color = if (isSelected) {
                        MaterialTheme.colorScheme.onSurface
                    } else {
                        MaterialTheme.colorScheme.primary
                    },
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            if (isSelected) {
                Icon(
                    imageVector = RAIcons.CircleCheck,
                    contentDescription = "Selected",
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(22.dp),
                )
            } else {
                Icon(
                    imageVector = RAIcons.ChevronRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                    modifier = Modifier.size(20.dp),
                )
            }
        }
    }
}

// ============================================================================
// State 2: Empty Document (models selected, no docs)
// ============================================================================

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun EmptyDocumentView(
    state: RAGUiState.Ready,
    onAddDocument: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = RAIcons.FileText,
            contentDescription = null,
            modifier = Modifier.size(56.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
        )

        Spacer(modifier = Modifier.height(20.dp))

        Text(
            text = "Add a Document",
            style = MaterialTheme.typography.titleLarge,
            color = MaterialTheme.colorScheme.onSurface,
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Upload a document to ask questions about its content. Your data stays on-device.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(24.dp))

        // Processing indicator
        AnimatedVisibility(
            visible = state.isProcessingDocument,
            enter = expandVertically(AppMotion.springSnappy()) + fadeIn(AppMotion.tweenMedium()),
            exit = shrinkVertically(AppMotion.springSnappy()) + fadeOut(AppMotion.tweenShort()),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                if (state.processingProgress != null) {
                    RAProgressBar(
                        progress = state.processingProgress,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 32.dp),
                    )
                } else {
                    CircularProgressIndicator(
                        modifier = Modifier.size(24.dp),
                        strokeWidth = 2.dp,
                    )
                }
                if (state.processingStatus != null) {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = state.processingStatus,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        RAButton(
            text = "Choose Document",
            onClick = onAddDocument,
            icon = RAIcons.Plus,
            enabled = !state.isProcessingDocument,
        )

        Spacer(modifier = Modifier.height(20.dp))

        // Supported formats
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
        ) {
            FormatChip("PDF")
            FormatChip("JSON")
        }
    }
}

@Composable
private fun FormatChip(label: String) {
    Surface(
        shape = RoundedCornerShape(6.dp),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 10.dp, vertical = 4.dp),
        )
    }
}

// ============================================================================
// State 3: Q&A Conversation (documents loaded)
// ============================================================================

@Composable
private fun QAConversationView(
    state: RAGUiState.Ready,
    listState: LazyListState,
    onManageDocuments: () -> Unit,
    onAddDocument: () -> Unit,
    onClearError: () -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyColumn(
        state = listState,
        modifier = modifier,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            start = 16.dp,
            end = 16.dp,
            top = 8.dp,
            bottom = 16.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Document info bar
        item(key = "doc_info", contentType = "header") {
            DocumentInfoBar(
                documents = state.documents,
                totalChunks = state.totalChunks,
                onManage = onManageDocuments,
                onAddMore = onAddDocument,
            )
        }

        // Processing indicator
        if (state.isProcessingDocument) {
            item(key = "processing", contentType = "processing") {
                ProcessingCard(
                    progress = state.processingProgress,
                    status = state.processingStatus,
                )
            }
        }

        // Error banner
        if (state.error != null) {
            item(key = "error", contentType = "error") {
                ErrorCard(
                    message = state.error,
                    onDismiss = onClearError,
                )
            }
        }

        // Empty prompt when docs loaded but no questions yet
        if (state.messages.isEmpty() && state.hasDocuments && !state.isProcessingDocument) {
            item(key = "prompt", contentType = "prompt") {
                DocumentPromptView()
            }
        }

        // Q&A messages
        itemsIndexed(
            items = state.messages,
            key = { _, msg -> msg.id },
            contentType = { _, _ -> "message" },
        ) { _, message ->
            QAMessageCard(message = message)
        }

        // Searching indicator (before answer starts streaming)
        if (state.isQuerying && (state.messages.lastOrNull()?.answer?.isEmpty() == true)) {
            item(key = "querying", contentType = "querying") {
                Row(
                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Text(
                        text = "Searching document...",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

// -- Document Info Bar --

@Composable
private fun DocumentInfoBar(
    documents: ImmutableList<DocumentInfo>,
    totalChunks: Int,
    onManage: () -> Unit,
    onAddMore: () -> Unit,
) {
    RACard(contentPadding = 12.dp) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = RAIcons.FileText,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(10.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (documents.size == 1) {
                        documents.first().name
                    } else {
                        "${documents.size} documents"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = "$totalChunks chunks indexed",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            RAButton(
                text = "Manage",
                onClick = onManage,
                style = RAButtonStyle.Tonal,
            )
        }
    }
}

// -- Processing Card --

@Composable
private fun ProcessingCard(
    progress: Float?,
    status: String?,
) {
    RACard(
        variant = RACardVariant.Outlined,
        contentPadding = 14.dp,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .animateContentSize(AppMotion.springDefault()),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp,
                )
                Text(
                    text = status ?: "Processing...",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (progress != null) {
                Spacer(modifier = Modifier.height(10.dp))
                RAProgressBar(progress = progress)
            }
        }
    }
}

// -- Error Card --

@Composable
private fun ErrorCard(
    message: String,
    onDismiss: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = MaterialTheme.shapes.medium,
        color = MaterialTheme.colorScheme.errorContainer,
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = RAIcons.AlertCircle,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.error,
            )
            Spacer(modifier = Modifier.width(10.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.weight(1f),
            )
            Spacer(modifier = Modifier.width(8.dp))
            Surface(
                modifier = Modifier
                    .size(24.dp)
                    .clickable(onClick = onDismiss),
                shape = CircleShape,
                color = MaterialTheme.colorScheme.error.copy(alpha = 0.1f),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(
                        imageVector = RAIcons.X,
                        contentDescription = "Dismiss",
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onErrorContainer,
                    )
                }
            }
        }
    }
}

// -- Document Prompt View --

@Composable
private fun DocumentPromptView() {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = RAIcons.Sparkles,
            contentDescription = null,
            modifier = Modifier.size(32.dp),
            tint = MaterialTheme.colorScheme.primary.copy(alpha = 0.6f),
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "Ready to answer questions",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
        Spacer(modifier = Modifier.height(6.dp))
        Text(
            text = "Ask anything about your document below",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ============================================================================
// Q&A Message Card
// ============================================================================

@Composable
private fun QAMessageCard(message: RAGMessage) {
    RACard(
        variant = RACardVariant.Outlined,
        contentPadding = 14.dp,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .animateContentSize(AppMotion.springDefault()),
        ) {
            // Question
            Row(verticalAlignment = Alignment.Top) {
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(24.dp),
                ) {
                    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                        Text(
                            text = "Q",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onPrimary,
                        )
                    }
                }
                Spacer(modifier = Modifier.width(10.dp))
                Text(
                    text = message.question,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f),
                )
            }

            Spacer(modifier = Modifier.height(12.dp))
            HorizontalDivider(
                color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f),
                thickness = 0.5.dp,
            )
            Spacer(modifier = Modifier.height(12.dp))

            // Answer
            Row(verticalAlignment = Alignment.Top) {
                Surface(
                    shape = CircleShape,
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    modifier = Modifier.size(24.dp),
                ) {
                    Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                        Icon(
                            imageVector = RAIcons.Sparkles,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.onSecondaryContainer,
                        )
                    }
                }
                Spacer(modifier = Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    if (message.isStreaming && message.answer.isEmpty()) {
                        Row(
                            horizontalArrangement = Arrangement.spacedBy(6.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(14.dp),
                                strokeWidth = 1.5.dp,
                            )
                            Text(
                                text = "Thinking...",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    } else {
                        MarkdownText(
                            text = message.answer,
                            style = MaterialTheme.typography.bodyMedium,
                        )
                    }

                    // Timing info
                    if (message.generationTimeMs != null) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "Generated in %.1fs".format(message.generationTimeMs / 1000.0),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                        )
                    }
                }
            }
        }
    }
}

// ============================================================================
// Document Management Sheet
// ============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DocumentManagementSheet(
    documents: ImmutableList<DocumentInfo>,
    onDismiss: () -> Unit,
    onClearAll: () -> Unit,
    onAddMore: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 32.dp),
        ) {
            Text(
                text = "Documents",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
            )

            Spacer(modifier = Modifier.height(16.dp))

            documents.forEach { doc ->
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    shape = RoundedCornerShape(12.dp),
                    color = MaterialTheme.colorScheme.surfaceContainer,
                ) {
                    Row(
                        modifier = Modifier.padding(14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = RAIcons.FileText,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(20.dp),
                        )
                        Spacer(modifier = Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = doc.name,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.Medium,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                text = "${doc.type.displayName} \u00B7 ${doc.chunkCount} chunks \u00B7 ${formatCharCount(doc.characterCount)}",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                RAButton(
                    text = "Clear All",
                    onClick = onClearAll,
                    style = RAButtonStyle.Outlined,
                    icon = RAIcons.Trash,
                    modifier = Modifier.weight(1f),
                )
                RAButton(
                    text = "Add More",
                    onClick = onAddMore,
                    icon = RAIcons.Plus,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

// ============================================================================
// RAG Model Picker Sheet (wraps the existing ModelSelectionSheet pattern)
// ============================================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RAGModelPickerSheet(
    context: ModelSelectionContext,
    onDismiss: () -> Unit,
    onModelSelected: (ModelInfo) -> Unit,
) {
    val viewModel: com.runanywhere.runanywhereai.viewmodels.ModelSelectionViewModel = viewModel()
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    LaunchedEffect(context) {
        viewModel.loadModels(context)
    }

    com.runanywhere.runanywhereai.ui.components.ModelSelectionSheet(
        state = state,
        onDismiss = onDismiss,
        onSelectModel = { modelId ->
            val model = state.models.find { it.id == modelId }
            if (model != null && model.isDownloaded) {
                onModelSelected(model)
            }
        },
        onDownloadModel = { modelId -> viewModel.downloadModel(modelId) },
        onCancelModelDownload = { viewModel.cancelModelDownload() },
        onLoadLora = {},
        onUnloadLora = {},
        onDownloadLora = {},
        onCancelLoraDownload = {},
        isLoraDownloaded = { false },
        isLoraLoaded = { false },
    )
}

// ============================================================================
// Utilities
// ============================================================================

private fun formatCharCount(chars: Int): String = when {
    chars >= 1_000_000 -> "%.1fM chars".format(chars / 1_000_000.0)
    chars >= 1_000 -> "%.0fK chars".format(chars / 1_000.0)
    else -> "$chars chars"
}
