package com.runanywhere.runanywhereai.presentation.rag

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Chat
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.presentation.components.ConfigureTopBar
import com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import com.runanywhere.sdk.public.extensions.RAG.RAGConfiguration
import java.io.File

/**
 * Document Q&A Screen — Compose port of iOS DocumentRAGView.swift
 *
 * Layout (top to bottom, matching iOS):
 * 1. Model Setup Section — embedding model + LLM model picker rows
 * 2. Document Status Bar — no-document / loading / loaded states
 * 3. Error Banner — dismissible error row
 * 4. Messages Area — LazyColumn with user/assistant bubbles
 * 5. Input Bar — question field + send button
 */
@Composable
fun DocumentRAGScreen(
    onBack: () -> Unit = {},
    viewModel: RAGViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    // Sheet visibility state
    var showEmbeddingPicker by remember { mutableStateOf(false) }
    var showLLMPicker by remember { mutableStateOf(false) }

    // Selected models
    var selectedEmbeddingModel by remember { mutableStateOf<ModelInfo?>(null) }
    var selectedLLMModel by remember { mutableStateOf<ModelInfo?>(null) }

    // Error banner visibility
    var isErrorBannerVisible by remember { mutableStateOf(false) }

    // Mirrors iOS areModelsReady
    val areModelsReady = selectedEmbeddingModel?.localPath != null && selectedLLMModel?.localPath != null

    // Show / hide error banner when error changes
    LaunchedEffect(uiState.error) {
        isErrorBannerVisible = uiState.error != null
    }

    // File picker launcher — accepts PDF and JSON
    val documentPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
    ) { uri: Uri? ->
        if (uri != null) {
            val config = buildRAGConfiguration(selectedEmbeddingModel, selectedLLMModel)
            if (config != null) {
                viewModel.loadDocument(context, uri, config)
            }
        }
    }

    ConfigureTopBar(title = "Document Q&A", showBack = true, onBack = onBack)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.backgroundGrouped),
    ) {
            // 1. Model Setup Section
            ModelSetupSection(
                selectedEmbeddingModel = selectedEmbeddingModel,
                selectedLLMModel = selectedLLMModel,
                onEmbeddingPickerTap = { showEmbeddingPicker = true },
                onLLMPickerTap = { showLLMPicker = true },
            )

            // 2. Document Status Bar
            DocumentStatusBar(
                uiState = uiState,
                areModelsReady = areModelsReady,
                onSelectDocument = { documentPickerLauncher.launch(arrayOf("application/pdf", "application/json")) },
                onChangeDocument = {
                    viewModel.clearDocument()
                    documentPickerLauncher.launch(arrayOf("application/pdf", "application/json"))
                },
            )

            // 3. Error Banner
            if (isErrorBannerVisible && uiState.error != null) {
                ErrorBanner(
                    errorMessage = uiState.error!!,
                    onDismiss = { isErrorBannerVisible = false },
                )
            }

            // 4. Messages Area (takes remaining space)
            MessagesArea(
                uiState = uiState,
                areModelsReady = areModelsReady,
                modifier = Modifier.weight(1f),
            )

            // 5. Input Bar
            InputBar(
                currentQuestion = uiState.currentQuestion,
                canAskQuestion = uiState.canAskQuestion,
                isQuerying = uiState.isQuerying,
                isDocumentLoaded = uiState.isDocumentLoaded,
                onQuestionChange = viewModel::updateQuestion,
                onSend = viewModel::askQuestion,
            )
    }

    // Embedding model picker sheet
    if (showEmbeddingPicker) {
        ModelSelectionBottomSheet(
            context = ModelSelectionContext.RAG_EMBEDDING,
            onDismiss = { showEmbeddingPicker = false },
            onModelSelected = { model ->
                selectedEmbeddingModel = model
            },
        )
    }

    // LLM model picker sheet
    if (showLLMPicker) {
        ModelSelectionBottomSheet(
            context = ModelSelectionContext.RAG_LLM,
            onDismiss = { showLLMPicker = false },
            onModelSelected = { model ->
                selectedLLMModel = model
            },
        )
    }
}

// MARK: - Model Setup Section

/**
 * Top section with two clickable model picker rows.
 * Mirrors iOS modelSetupSection exactly.
 */
@Composable
private fun ModelSetupSection(
    selectedEmbeddingModel: ModelInfo?,
    selectedLLMModel: ModelInfo?,
    onEmbeddingPickerTap: () -> Unit,
    onLLMPickerTap: () -> Unit,
) {
    Column {
        Surface(
            modifier = Modifier.fillMaxWidth(),
            color = MaterialTheme.colorScheme.surface,
        ) {
            Column(
                modifier = Modifier.padding(
                    horizontal = Dimensions.large,
                    vertical = Dimensions.mediumLarge,
                ),
                verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
            ) {
                ModelPickerRow(
                    label = "Embedding Model",
                    icon = { Icon(Icons.Outlined.Psychology, contentDescription = null, modifier = Modifier.size(20.dp), tint = AppColors.textSecondary) },
                    selectedModel = selectedEmbeddingModel,
                    onClick = onEmbeddingPickerTap,
                )
                ModelPickerRow(
                    label = "LLM Model",
                    icon = { Icon(Icons.AutoMirrored.Outlined.Chat, contentDescription = null, modifier = Modifier.size(20.dp), tint = AppColors.textSecondary) },
                    selectedModel = selectedLLMModel,
                    onClick = onLLMPickerTap,
                )
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
    }
}

@Composable
private fun ModelPickerRow(
    label: String,
    icon: @Composable () -> Unit,
    selectedModel: ModelInfo?,
    onClick: () -> Unit,
) {
    TextButton(
        onClick = onClick,
        contentPadding = PaddingValues(0.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Dimensions.mediumLarge),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            icon()

            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textSecondary,
            )

            Spacer(modifier = Modifier.weight(1f))

            if (selectedModel != null) {
                Text(
                    text = selectedModel.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 1,
                    overflow = TextOverflow.MiddleEllipsis,
                )
                Spacer(modifier = Modifier.width(Dimensions.xSmall))
                Icon(
                    imageVector = Icons.Filled.CheckCircle,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    tint = AppColors.primaryGreen,
                )
            } else {
                Text(
                    text = "Not selected",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.primaryAccent,
                )
                Spacer(modifier = Modifier.width(Dimensions.xSmall))
                Icon(
                    imageVector = Icons.Default.ChevronRight,
                    contentDescription = null,
                    modifier = Modifier.size(14.dp),
                    tint = AppColors.textTertiary,
                )
            }
        }
    }
}

// MARK: - Document Status Bar

/**
 * Shows one of three states: no document, loading, or loaded.
 * Mirrors iOS documentStatusBar exactly.
 */
@Composable
private fun DocumentStatusBar(
    uiState: RAGUiState,
    areModelsReady: Boolean,
    onSelectDocument: () -> Unit,
    onChangeDocument: () -> Unit,
) {
    Column {
        Surface(
            modifier = Modifier.fillMaxWidth(),
            color = MaterialTheme.colorScheme.surface,
        ) {
            when {
                uiState.isLoadingDocument -> {
                    // Loading state
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(Dimensions.large),
                        horizontalArrangement = Arrangement.spacedBy(Dimensions.mediumLarge),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        Text(
                            text = "Loading document...",
                            style = MaterialTheme.typography.bodyMedium,
                            color = AppColors.textSecondary,
                        )
                    }
                }
                uiState.isDocumentLoaded && uiState.documentName != null -> {
                    // Loaded state
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = Dimensions.large, vertical = Dimensions.mediumLarge),
                        horizontalArrangement = Arrangement.spacedBy(Dimensions.mediumLarge),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Filled.CheckCircle,
                            contentDescription = null,
                            tint = AppColors.primaryGreen,
                            modifier = Modifier.size(22.dp),
                        )
                        Text(
                            text = uiState.documentName,
                            style = MaterialTheme.typography.bodyMedium,
                            fontWeight = FontWeight.Medium,
                            color = MaterialTheme.colorScheme.onSurface,
                            maxLines = 1,
                            overflow = TextOverflow.MiddleEllipsis,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = onChangeDocument) {
                            Text(
                                text = "Change",
                                style = MaterialTheme.typography.labelSmall,
                                color = AppColors.primaryAccent,
                            )
                        }
                    }
                }
                else -> {
                    // No document state
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(Dimensions.large),
                        horizontalArrangement = Arrangement.Center,
                    ) {
                        Button(
                            onClick = onSelectDocument,
                            enabled = areModelsReady,
                            colors = ButtonDefaults.buttonColors(
                                containerColor = AppColors.primaryAccent,
                                disabledContainerColor = AppColors.statusGray,
                            ),
                            shape = RoundedCornerShape(Dimensions.cornerRadiusXLarge),
                        ) {
                            Icon(
                                imageVector = Icons.Outlined.Add,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                            )
                            Spacer(modifier = Modifier.width(Dimensions.smallMedium))
                            Text(
                                text = "Select Document",
                                style = MaterialTheme.typography.titleSmall,
                                color = Color.White,
                            )
                        }
                    }
                }
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
    }
}

// MARK: - Error Banner

/**
 * Dismissible error banner shown when uiState.error != null.
 * Mirrors iOS errorBanner with red tint background.
 */
@Composable
private fun ErrorBanner(
    errorMessage: String,
    onDismiss: () -> Unit,
) {
    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(AppColors.primaryRed.copy(alpha = 0.1f))
                .padding(horizontal = Dimensions.large, vertical = Dimensions.smallMedium),
            horizontalArrangement = Arrangement.spacedBy(Dimensions.mediumLarge),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = AppColors.primaryRed,
                modifier = Modifier.size(16.dp),
            )
            Text(
                text = errorMessage,
                style = MaterialTheme.typography.labelMedium,
                color = AppColors.primaryRed,
                maxLines = 2,
                modifier = Modifier.weight(1f),
            )
            IconButton(
                onClick = onDismiss,
                modifier = Modifier.size(24.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.Close,
                    contentDescription = "Dismiss",
                    tint = AppColors.textSecondary,
                    modifier = Modifier.size(14.dp),
                )
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
    }
}

// MARK: - Messages Area

/**
 * Main content area with empty state or message list.
 * Mirrors iOS messagesArea with LazyVStack replaced by LazyColumn.
 */
@Composable
private fun MessagesArea(
    uiState: RAGUiState,
    areModelsReady: Boolean,
    modifier: Modifier = Modifier,
) {
    val listState = rememberLazyListState()

    // Auto-scroll to bottom when messages change
    LaunchedEffect(uiState.messages.size, uiState.isQuerying) {
        if (uiState.messages.isNotEmpty()) {
            listState.animateScrollToItem(uiState.messages.size - 1)
        }
    }

    if (uiState.messages.isEmpty() && !uiState.isQuerying) {
        // Empty state — contextual text matching iOS
        EmptyStateView(
            isDocumentLoaded = uiState.isDocumentLoaded,
            areModelsReady = areModelsReady,
            modifier = modifier,
        )
    } else {
        LazyColumn(
            state = listState,
            modifier = modifier.background(AppColors.backgroundGrouped),
            contentPadding = PaddingValues(vertical = Dimensions.large, horizontal = Dimensions.large),
            verticalArrangement = Arrangement.spacedBy(Dimensions.large),
        ) {
            itemsIndexed(uiState.messages) { index, message ->
                RAGMessageBubble(message = message)
            }

            // Querying indicator at bottom
            if (uiState.isQuerying) {
                item {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(16.dp),
                            strokeWidth = 2.dp,
                            color = AppColors.primaryAccent,
                        )
                        Text(
                            text = "Searching document...",
                            style = MaterialTheme.typography.labelMedium,
                            color = AppColors.textSecondary,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun EmptyStateView(
    isDocumentLoaded: Boolean,
    areModelsReady: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(AppColors.backgroundGrouped)
            .padding(Dimensions.large),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(modifier = Modifier.height(Dimensions.xxxLarge))
        Icon(
            imageVector = Icons.Outlined.Description,
            contentDescription = null,
            modifier = Modifier.size(60.dp),
            tint = AppColors.textTertiary,
        )
        Spacer(modifier = Modifier.height(Dimensions.large))

        when {
            isDocumentLoaded -> {
                Text(
                    text = "Document loaded",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(modifier = Modifier.height(Dimensions.smallMedium))
                Text(
                    text = "Ask a question below to get started",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
            }
            !areModelsReady -> {
                Text(
                    text = "Select models to get started",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(modifier = Modifier.height(Dimensions.smallMedium))
                Text(
                    text = "Choose an embedding model and an LLM model above, then pick a document",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
            }
            else -> {
                Text(
                    text = "No document selected",
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Spacer(modifier = Modifier.height(Dimensions.smallMedium))
                Text(
                    text = "Pick a PDF or JSON document to start asking questions",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
            }
        }
        Spacer(modifier = Modifier.height(Dimensions.xxxLarge))
    }
}

// MARK: - RAG Message Bubble

/**
 * A single message bubble.
 * - User: right-aligned, primaryAccent background, white text
 * - Assistant: left-aligned, surfaceVariant background, onSurface text
 *
 * Mirrors iOS RAGMessageBubble exactly.
 */
@Composable
private fun RAGMessageBubble(message: RAGMessage) {
    val isUser = message.role == RAGMessageRole.USER
    val bubbleShape = RoundedCornerShape(Dimensions.cornerRadiusBubble)

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        if (!isUser) {
            // Leave space on right for assistant
        } else {
            Spacer(modifier = Modifier.width(Dimensions.xxxLarge))
        }

        Surface(
            shape = bubbleShape,
            color = if (isUser) AppColors.messageBubbleUser else MaterialTheme.colorScheme.surfaceVariant,
            modifier = Modifier.widthIn(max = 300.dp),
        ) {
            Text(
                text = message.text,
                style = MaterialTheme.typography.bodyMedium,
                color = if (isUser) Color.White else MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(
                    horizontal = Dimensions.mediumLarge,
                    vertical = Dimensions.smallMedium,
                ),
            )
        }

        if (isUser) {
            // nothing extra
        } else {
            Spacer(modifier = Modifier.width(Dimensions.xxxLarge))
        }
    }
}

// MARK: - Input Bar

/**
 * Bottom input bar with question field and send button.
 * Mirrors iOS inputBar exactly.
 */
@Composable
private fun InputBar(
    currentQuestion: String,
    canAskQuestion: Boolean,
    isQuerying: Boolean,
    isDocumentLoaded: Boolean,
    onQuestionChange: (String) -> Unit,
    onSend: () -> Unit,
) {
    Column {
        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
        Surface(
            modifier = Modifier.fillMaxWidth(),
            color = MaterialTheme.colorScheme.surface,
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(Dimensions.large),
                horizontalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
                verticalAlignment = Alignment.Bottom,
            ) {
                OutlinedTextField(
                    value = currentQuestion,
                    onValueChange = onQuestionChange,
                    placeholder = {
                        Text(
                            text = "Ask a question...",
                            color = AppColors.textTertiary,
                        )
                    },
                    enabled = isDocumentLoaded && !isQuerying,
                    maxLines = 4,
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(Dimensions.cornerRadiusXLarge),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = AppColors.primaryAccent,
                        unfocusedBorderColor = MaterialTheme.colorScheme.outlineVariant,
                        disabledBorderColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
                    ),
                )

                if (isQuerying) {
                    CircularProgressIndicator(
                        modifier = Modifier
                            .size(44.dp)
                            .padding(Dimensions.smallMedium),
                        color = AppColors.primaryAccent,
                        strokeWidth = 2.dp,
                    )
                } else {
                    IconButton(
                        onClick = onSend,
                        enabled = canAskQuestion,
                        modifier = Modifier.size(44.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Filled.ArrowCircleUp,
                            contentDescription = "Send",
                            modifier = Modifier.size(32.dp),
                            tint = if (canAskQuestion) AppColors.primaryAccent else AppColors.statusGray,
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Model Path Resolution

/**
 * Resolve the actual embedding model file path.
 * If localPath is a directory, return `"$localPath/model.onnx"`.
 * Mirrors iOS resolveEmbeddingFilePath(localPath:) exactly.
 */
private fun resolveEmbeddingFilePath(localPath: String): String {
    val file = File(localPath)

    // 1. If it's already a file, we are good to go
    if (!file.isDirectory) return localPath

    val files = file.listFiles() ?: return localPath

    // 2. Try to find a file that explicitly has the .onnx extension
    val onnxFile = files.firstOrNull { it.extension.lowercase() == "onnx" }
    if (onnxFile != null) return onnxFile.absolutePath

    // 3. Fallback to conventional name
    return "$localPath/model.onnx"
}

/**
 * Resolve the actual LLM model file path.
 * If localPath is a directory, find first .gguf file inside, else return localPath.
 * Mirrors iOS resolveLLMFilePath(localPath:) exactly.
 */
private fun resolveLLMFilePath(localPath: String): String {
    val file = File(localPath)
    
    // 1. If it's already a file, we are good to go
    if (!file.isDirectory) return localPath
    
    val files = file.listFiles() ?: return localPath
    
    // 2. Try to find a file that explicitly has the .gguf extension
    val ggufFile = files.firstOrNull { it.extension.lowercase() == "gguf" }
    if (ggufFile != null) return ggufFile.absolutePath
    
    // 3. THE BULLETPROOF FALLBACK: 
    // If the downloader stripped the extension, grab the largest file in the directory.
    // The LLM weights will always be the largest file by a massive margin.
    val largestFile = files.filter { it.isFile }.maxByOrNull { it.length() }
    
    return largestFile?.absolutePath ?: localPath
}

/**
 * Resolve the vocab file path for the embedding model.
 * Multi-file models (directory): vocab.txt is inside the folder.
 * Single-file models: vocab.txt is a sibling of the model file.
 * Mirrors iOS resolveVocabPath(for:) exactly.
 */
private fun resolveVocabPath(embeddingLocalPath: String): String? {
    val file = File(embeddingLocalPath)
    return if (file.isDirectory) {
        "$embeddingLocalPath/vocab.txt"
    } else {
        "${file.parent}/vocab.txt"
    }
}

/**
 * Build a RAGConfiguration from selected models, injecting the vocab path.
 * Returns null if either model is not yet selected or has no local path.
 * Mirrors iOS ragConfig + handleFileImport vocab injection exactly.
 */
private fun buildRAGConfiguration(
    embeddingModel: ModelInfo?,
    llmModel: ModelInfo?,
): RAGConfiguration? {
    val embeddingLocalPath = embeddingModel?.localPath ?: return null
    val llmLocalPath = llmModel?.localPath ?: return null

    val resolvedEmbeddingPath = resolveEmbeddingFilePath(embeddingLocalPath)
    val resolvedLLMPath = resolveLLMFilePath(llmLocalPath)
    val vocabPath = resolveVocabPath(embeddingLocalPath)

    val embeddingConfigJson = if (vocabPath != null) {
        """{"vocab_path":"$vocabPath"}"""
    } else {
        null
    }

    return RAGConfiguration(
        embeddingModelPath = resolvedEmbeddingPath,
        llmModelPath = resolvedLLMPath,
        embeddingConfigJson = embeddingConfigJson,
    )
}
