package com.runanywhere.runanywhereai.presentation.chat

import android.content.ClipData
import android.os.Build
import android.widget.Toast
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.data.ConversationStore
import com.runanywhere.runanywhereai.domain.models.ChatMessage
import com.runanywhere.runanywhereai.domain.models.Conversation
import com.runanywhere.runanywhereai.domain.models.MessageRole
import com.runanywhere.runanywhereai.presentation.settings.ToolSettingsViewModel
import com.runanywhere.runanywhereai.presentation.chat.components.MarkdownText
import com.runanywhere.runanywhereai.presentation.chat.components.ModelLoadedToast
import com.runanywhere.runanywhereai.presentation.chat.components.ModelRequiredOverlay
import com.runanywhere.runanywhereai.util.getModelLogoResIdForName
import com.runanywhere.runanywhereai.ui.theme.AppColors
import android.app.Application
import com.runanywhere.runanywhereai.ui.theme.AppTypography
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(viewModel: ChatViewModel = viewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    var showingConversationList by remember { mutableStateOf(false) }
    var showingModelSelection by remember { mutableStateOf(false) }
    var showingChatDetails by remember { mutableStateOf(false) }
    var showDebugAlert by remember { mutableStateOf(false) }
    var debugMessage by remember { mutableStateOf("") }

    var showModelLoadedToast by remember { mutableStateOf(false) }
    var loadedModelToastName by remember { mutableStateOf("") }

    LaunchedEffect(uiState.messages.size, uiState.isGenerating) {
        if (uiState.messages.isNotEmpty()) {
            scope.launch {
                listState.animateScrollToItem(uiState.messages.size - 1)
            }
        }
    }

    Scaffold(
        topBar = {
            if (uiState.isModelLoaded) {
                ChatTopBar(
                    hasMessages = uiState.messages.isNotEmpty(),
                    modelName = uiState.loadedModelName,
                    supportsStreaming = uiState.useStreaming,
                    onHistoryClick = {
                        viewModel.ensureCurrentConversationInHistory()
                        showingConversationList = true
                    },
                    onInfoClick = { showingChatDetails = true },
                    onModelClick = { showingModelSelection = true },
                )
            }
        },
    ) { padding ->
        Box(
            modifier =
                Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.background),
        ) {
            Column(modifier = Modifier.fillMaxSize()) {
                if (uiState.isModelLoaded) {
                    if (uiState.messages.isEmpty() && !uiState.isGenerating) {
                        EmptyStateView(modifier = Modifier.weight(1f))
                    } else {
                        LazyColumn(
                            state = listState,
                            modifier = Modifier.weight(1f),
                            contentPadding = PaddingValues(Dimensions.large),
                            verticalArrangement = Arrangement.spacedBy(Dimensions.messageSpacingBetween),
                        ) {
                            item {
                                Spacer(modifier = Modifier.height(20.dp))
                            }

                            items(uiState.messages, key = { it.id }) { message ->
                                MessageBubbleView(
                                    message = message,
                                    isGenerating = uiState.isGenerating,
                                    modifier = Modifier.animateItem(),
                                )
                            }

                            if (uiState.isGenerating) {
                                item {
                                    TypingIndicatorView()
                                }
                            }

                            item {
                                Spacer(modifier = Modifier.height(20.dp))
                            }
                        }
                    }
                }

                if (uiState.isModelLoaded) {
                    HorizontalDivider(
                        thickness = Dimensions.strokeThin,
                        color = MaterialTheme.colorScheme.outline,
                    )
                    ChatInputView(
                        value = uiState.currentInput,
                        onValueChange = viewModel::updateInput,
                        onSend = viewModel::sendMessage,
                        isGenerating = uiState.isGenerating,
                        isModelLoaded = true,
                    )
                }
            }

            // Tool calling indicator - matching iOS
            val toolContext = LocalContext.current
            val application = toolContext.applicationContext as Application
            val toolSettingsViewModel = remember { ToolSettingsViewModel.getInstance(application) }
            val toolState by toolSettingsViewModel.uiState.collectAsStateWithLifecycle()

            AnimatedVisibility(
                visible = toolState.toolCallingEnabled && toolState.registeredTools.isNotEmpty(),
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically(),
            ) {
                ToolCallingBadge(toolCount = toolState.registeredTools.size)
            }

            if (!uiState.isModelLoaded && !uiState.isGenerating) {
                ModelRequiredOverlay(
                    onSelectModel = { showingModelSelection = true },
                    modifier = Modifier.matchParentSize(),
                )
            }

            ModelLoadedToast(
                modelName = loadedModelToastName,
                isVisible = showModelLoadedToast,
                onDismiss = { showModelLoadedToast = false },
                modifier = Modifier.align(Alignment.TopCenter),
            )
        }
    }

    if (showingModelSelection) {
        com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet(
            onDismiss = { showingModelSelection = false },
            onModelSelected = { model ->
                scope.launch {
                    viewModel.setLoadedModelName(model.name)
                    viewModel.checkModelStatus()
                    loadedModelToastName = model.name
                    showModelLoadedToast = true
                }
            },
        )
    }

    if (showingConversationList) {
        val context = LocalContext.current
        val conversationStore = remember { ConversationStore.getInstance(context) }
        val conversations by conversationStore.conversations.collectAsStateWithLifecycle()

        ConversationListSheet(
            conversations = conversations,
            currentConversationId = uiState.currentConversation?.id,
            onDismiss = { showingConversationList = false },
            onConversationSelected = { conversation ->
                viewModel.loadConversation(conversation)
                showingConversationList = false
            },
            onNewConversation = {
                viewModel.createNewConversation()
                showingConversationList = false
            },
            onDeleteConversation = { conversation ->
                conversationStore.deleteConversation(conversation)
            },
        )
    }

    if (showingChatDetails) {
        ChatDetailsSheet(
            messages = uiState.messages,
            conversationTitle = uiState.currentConversation?.title ?: "Chat",
            modelName = uiState.loadedModelName,
            onDismiss = { showingChatDetails = false },
        )
    }

    LaunchedEffect(uiState.error) {
        if (uiState.error != null) {
            debugMessage = "Error occurred: ${uiState.error?.localizedMessage}"
            showDebugAlert = true
        }
    }

    if (showDebugAlert) {
        AlertDialog(
            onDismissRequest = {
                showDebugAlert = false
                viewModel.clearError()
            },
            title = { Text("Debug Info") },
            text = { Text(debugMessage) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDebugAlert = false
                        viewModel.clearError()
                    },
                ) {
                    Text("OK")
                }
            },
        )
    }
}

private fun shortModelName(name: String, maxLength: Int = 13): String {
    val cleaned = name.replace(Regex("\\s*\\([^)]*\\)"), "").trim()
    return if (cleaned.length > maxLength) {
        cleaned.take(maxLength - 1) + "\u2026"
    } else {
        cleaned
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatTopBar(
    hasMessages: Boolean,
    modelName: String?,
    supportsStreaming: Boolean,
    onHistoryClick: () -> Unit,
    onInfoClick: () -> Unit,
    onModelClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    TopAppBar(
        modifier = modifier,
        title = {
            Text(
                text = "Chat",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
        },
        actions = {
            Surface(
                shape = RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(4.dp),
                ) {
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                                onClick = onHistoryClick,
                            ),
                    ) {
                        Icon(
                            imageVector = Icons.Default.History,
                            contentDescription = "History",
                            modifier = Modifier.size(20.dp),
                            tint = MaterialTheme.colorScheme.onSurface,
                        )
                    }

                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .size(34.dp)
                            .clip(CircleShape)
                            .then(
                                if (hasMessages) {
                                    Modifier
                                        .background(AppColors.primaryAccent, CircleShape)
                                        .clickable(
                                            interactionSource = remember { MutableInteractionSource() },
                                            indication = null,
                                            onClick = onInfoClick,
                                        )
                                } else {
                                    Modifier
                                }
                            ),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Info,
                            contentDescription = "Info",
                            modifier = Modifier.size(20.dp),
                            tint = if (hasMessages) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.width(8.dp))

            Surface(
                onClick = onModelClick,
                shape = RoundedCornerShape(50),
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(
                        start = 6.dp,
                        end = 12.dp,
                        top = 6.dp,
                        bottom = 6.dp,
                    ),
                ) {
                    if (modelName != null) {
                        Box(
                            modifier = Modifier
                                .size(30.dp)
                                .clip(RoundedCornerShape(6.dp)),
                        ) {
                            Image(
                                painter = painterResource(id = getModelLogoResIdForName(modelName)),
                                contentDescription = null,
                                modifier = Modifier.fillMaxSize(),
                                contentScale = ContentScale.Fit,
                            )
                        }

                        Spacer(modifier = Modifier.width(8.dp))

                        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                            Text(
                                text = shortModelName(modelName, maxLength = 12),
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(3.dp),
                            ) {
                                Icon(
                                    imageVector = if (supportsStreaming) Icons.Default.Bolt else Icons.Default.Stop,
                                    contentDescription = null,
                                    modifier = Modifier.size(10.dp),
                                    tint = if (supportsStreaming) AppColors.primaryGreen else AppColors.primaryOrange,
                                )
                                Text(
                                    text = if (supportsStreaming) "Streaming" else "Batch",
                                    style = MaterialTheme.typography.labelSmall.copy(
                                        fontSize = 10.sp,
                                        fontWeight = FontWeight.Medium,
                                    ),
                                    color = if (supportsStreaming) AppColors.primaryGreen else AppColors.primaryOrange,
                                )
                            }
                        }
                    } else {
                        Icon(
                            imageVector = Icons.Default.ViewInAr,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = AppColors.primaryAccent,
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            text = "Select Model",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.width(4.dp))
        },
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MessageBubbleView(
    message: ChatMessage,
    isGenerating: Boolean = false,
    modifier: Modifier = Modifier,
) {
    var showToolCallSheet by remember { mutableStateOf(false) }
    
    val alignment =
        if (message.role == MessageRole.USER) {
            Arrangement.End
        } else {
            Arrangement.Start
        }

    // context menu state
    var showDialog by remember { mutableStateOf(false) }
    var showTextSelectionDialog by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = alignment,
    ) {
        if (message.role == MessageRole.USER) {
            Spacer(modifier = Modifier.width(Dimensions.messageBubbleMinSpacing))
        }

        Column(
            modifier = Modifier.widthIn(max = Dimensions.messageBubbleMaxWidth),
            horizontalAlignment =
                if (message.role == MessageRole.USER) {
                    Alignment.End
                } else {
                    Alignment.Start
                },
        ) {
            // Model badge (for assistant messages)
            if (message.role == MessageRole.ASSISTANT && message.modelInfo != null) {
                ModelBadge(
                    modelName = message.modelInfo.modelName,
                    framework = message.modelInfo.framework,
                )
                Spacer(modifier = Modifier.height(Dimensions.small))
            }

            // Tool call indicator (for assistant messages with tool calls) - matching iOS
            if (message.role == MessageRole.ASSISTANT && message.toolCallInfo != null) {
                com.runanywhere.runanywhereai.presentation.chat.components.ToolCallIndicator(
                    toolCallInfo = message.toolCallInfo,
                    onTap = { showToolCallSheet = true },
                )
                Spacer(modifier = Modifier.height(Dimensions.small))
            }

            message.thinkingContent?.let { thinking ->
                ThinkingToggle(
                    thinkingContent = thinking,
                )
                Spacer(modifier = Modifier.height(Dimensions.small))
            }

            if (message.role == MessageRole.ASSISTANT &&
                message.content.isEmpty() &&
                message.thinkingContent != null &&
                isGenerating
            ) {
                ThinkingProgressIndicator()
            }

            if (message.content.isNotEmpty()) {
                val bubbleShape = RoundedCornerShape(Dimensions.messageBubbleCornerRadius)
                val isUserMessage = message.role == MessageRole.USER

                if (showDialog) {
                    BasicAlertDialog(
                        onDismissRequest = { showDialog = false },
                        modifier = Modifier
                            .clip(RoundedCornerShape(Dimensions.cornerRadiusModal))
                            .background(MaterialTheme.colorScheme.surface)
                            .widthIn(max = Dimensions.contextMenuMaxWidth)
                    ) {
                        Column(
                            modifier = Modifier.padding(vertical = Dimensions.padding8)
                        ) {
                            TextButton(
                                onClick = {
                                    scope.launch {
                                        val clipEntry = ClipEntry(ClipData.newPlainText("chat_msg", message.content))
                                        clipboard.setClipEntry(clipEntry)
                                        showDialog = false
                                        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2) {
                                            Toast.makeText(context, "Message copied to clipboard", Toast.LENGTH_SHORT).show()
                                        }
                                    }
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = Dimensions.padding16)
                            ) {
                                Text("Copy", style = MaterialTheme.typography.bodyLarge)
                            }
                            TextButton(
                                onClick = {
                                    showDialog = false
                                    showTextSelectionDialog = true
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = Dimensions.padding16)
                            ) {
                                Text("Select Text", style = MaterialTheme.typography.bodyLarge)
                            }
                        }
                    }
                }

                if (showTextSelectionDialog) {
                    SelectableTextDialog(
                        text = message.content,
                        onDismiss = { showTextSelectionDialog = false }
                    )
                }

                Box(
                    modifier =
                        Modifier
                            .shadow(
                                elevation = Dimensions.messageBubbleShadowRadius,
                                shape = bubbleShape,
                            )
                            .clip(bubbleShape)
                            .background(
                                brush =
                                    if (isUserMessage) {
                                        AppColors.userBubbleGradient()
                                    } else {
                                        AppColors.assistantBubbleGradientThemed()
                                    },
                            )
                            .border(
                                width = Dimensions.strokeThin,
                                color =
                                    if (isUserMessage) {
                                        AppColors.borderLight
                                    } else {
                                        AppColors.borderMedium
                                    },
                                shape = bubbleShape,
                            )
                            .combinedClickable(
                                onClick = { /* No-op */ },
                                onLongClick = { showDialog = true },
                            ),
                ) {
                    if (isUserMessage) {
                        Text(
                            text = message.content,
                            style = MaterialTheme.typography.bodyLarge,
                            color = AppColors.textWhite,
                            modifier =
                                Modifier.padding(
                                    horizontal = Dimensions.messageBubblePaddingHorizontal,
                                    vertical = Dimensions.messageBubblePaddingVertical,
                                ),
                        )
                    } else {
                        Box {
                            Column(
                                modifier = Modifier.padding(
                                    horizontal = Dimensions.messageBubblePaddingHorizontal,
                                    vertical = Dimensions.messageBubblePaddingVertical,
                                ),
                            ) {
                                MarkdownText(
                                    markdown = message.content,
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = AppColors.assistantBubbleTextColor(),
                                )

                                if (message.modelInfo != null) {
                                    Spacer(modifier = Modifier.height(Dimensions.large))
                                }
                            }

                            if (message.modelInfo != null) {
                                Row(
                                    modifier = Modifier
                                        .align(Alignment.BottomEnd)
                                        .padding(
                                            end = Dimensions.mediumLarge,
                                            bottom = Dimensions.small,
                                        ),
                                    horizontalArrangement = Arrangement.spacedBy(3.dp),
                                    verticalAlignment = Alignment.CenterVertically,
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.ViewInAr,
                                        contentDescription = null,
                                        modifier = Modifier.size(8.dp),
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                                    )
                                    Text(
                                        text = message.modelInfo.modelName,
                                        style = MaterialTheme.typography.labelSmall.copy(
                                            fontSize = 9.sp,
                                            fontWeight = FontWeight.Medium,
                                        ),
                                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                                    )
                                }
                            }
                        }
                    }
                }
            }

            if (message.role == MessageRole.ASSISTANT &&
                message.content.isNotEmpty() &&
                !isGenerating
            ) {
                Spacer(modifier = Modifier.height(Dimensions.small))
                AnalyticsFooter(
                    message = message,
                    hasThinking = message.thinkingContent != null,
                )
            }
        }

        if (message.role == MessageRole.ASSISTANT) {
            Spacer(modifier = Modifier.width(Dimensions.messageBubbleMinSpacing))
        }
    }
    
    // Tool call detail sheet - matching iOS
    if (showToolCallSheet && message.toolCallInfo != null) {
        com.runanywhere.runanywhereai.presentation.chat.components.ToolCallDetailSheet(
            toolCallInfo = message.toolCallInfo,
            onDismiss = { showToolCallSheet = false },
        )
    }
}

private fun formatTimestamp(timestamp: Long): String {
    val calendar = java.util.Calendar.getInstance()
    calendar.timeInMillis = timestamp
    val hour = calendar.get(java.util.Calendar.HOUR)
    val minute = calendar.get(java.util.Calendar.MINUTE)
    val amPm = if (calendar.get(java.util.Calendar.AM_PM) == java.util.Calendar.AM) "AM" else "PM"
    return String.format("%d:%02d %s", if (hour == 0) 12 else hour, minute, amPm)
}

@Composable
fun ModelBadge(
    modelName: String,
    framework: String? = null,
) {
    Surface(
        color = MaterialTheme.colorScheme.primary,
        shape = RoundedCornerShape(Dimensions.modelBadgeCornerRadius),
        modifier =
            Modifier
                .shadow(
                    elevation = Dimensions.shadowSmall,
                    shape = RoundedCornerShape(Dimensions.modelBadgeCornerRadius),
                )
                .border(
                    width = Dimensions.strokeThin,
                    color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.2f),
                    shape = RoundedCornerShape(Dimensions.modelBadgeCornerRadius),
                ),
    ) {
        Row(
            modifier =
                Modifier.padding(
                    horizontal = Dimensions.modelBadgePaddingHorizontal,
                    vertical = Dimensions.modelBadgePaddingVertical,
                ),
            horizontalArrangement = Arrangement.spacedBy(Dimensions.modelBadgeSpacing),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Default.ViewInAr,
                contentDescription = null,
                modifier = Modifier.size(AppTypography.caption2.fontSize.value.dp),
                tint = MaterialTheme.colorScheme.onPrimary,
            )
            Text(
                text = modelName,
                style = AppTypography.caption2Medium,
                color = MaterialTheme.colorScheme.onPrimary,
            )
            if (framework != null) {
                Text(
                    text = framework,
                    style = AppTypography.caption2,
                    color = MaterialTheme.colorScheme.onPrimary,
                )
            }
        }
    }
}

private fun extractThinkingSummary(thinking: String): String {
    val trimmed = thinking.trim()
    if (trimmed.isEmpty()) return "Show reasoning..."

    val sentences =
        trimmed.split(Regex("[.!?]"))
            .map { it.trim() }
            .filter { it.length > 20 }

    if (sentences.size >= 2 && sentences[0].length > 20) {
        return sentences[0] + "..."
    }

    // Fallback to truncated version
    if (trimmed.length > 80) {
        val truncated = trimmed.take(80)
        val lastSpace = truncated.lastIndexOf(' ')
        return if (lastSpace > 0) {
            truncated.substring(0, lastSpace) + "..."
        } else {
            truncated + "..."
        }
    }

    return trimmed
}

/**
 * Thinking Progress Indicator -  pattern
 * Shows "Thinking..." with animated dots when message is empty but thinking content exists
 */
@Composable
fun ThinkingProgressIndicator() {
    val thinkingShape = RoundedCornerShape(Dimensions.medium)

    // : purple gradient background with purple border
    Box(
        modifier =
            Modifier
                .clip(thinkingShape)
                .background(
                    brush = Brush.linearGradient(
                        colors = listOf(
                            AppColors.primaryPurple.copy(alpha = 0.12f),
                            AppColors.primaryPurple.copy(alpha = 0.06f),
                        ),
                    ),
                )
                .border(
                    width = Dimensions.strokeThin,
                    color = AppColors.primaryPurple.copy(alpha = 0.3f),
                    shape = thinkingShape,
                )
                .padding(
                    horizontal = Dimensions.mediumLarge,
                    vertical = Dimensions.smallMedium,
                ),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(Dimensions.xSmall),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Animated dots
            repeat(3) { index ->
                val infiniteTransition = rememberInfiniteTransition(label = "thinking_progress")
                val scale by infiniteTransition.animateFloat(
                    initialValue = 0.5f,
                    targetValue = 1.0f,
                    animationSpec =
                        infiniteRepeatable(
                            animation = tween(600),
                            repeatMode = RepeatMode.Reverse,
                            initialStartOffset = StartOffset(index * 200),
                        ),
                    label = "thinking_dot_$index",
                )

                Box(
                    modifier =
                        Modifier
                            .size(Dimensions.small)
                            .graphicsLayer {
                                scaleX = scale
                                scaleY = scale
                            }
                            .background(
                                color = AppColors.primaryPurple,
                                shape = CircleShape,
                            ),
                )
            }

            Spacer(modifier = Modifier.width(Dimensions.smallMedium))

            Text(
                text = "Thinking...",
                style = AppTypography.caption,
                color = AppColors.primaryPurple.copy(alpha = 0.8f),
            )
        }
    }
}

@Composable
fun ThinkingToggle(
    thinkingContent: String,
) {
    var isExpanded by remember { mutableStateOf(false) }

    // Extract intelligent summary
    val thinkingSummary =
        remember(thinkingContent) {
            extractThinkingSummary(thinkingContent)
        }

    Column {
        // Toggle button with gradient background
        val toggleShape = RoundedCornerShape(Dimensions.thinkingSectionCornerRadius)

        // : purple gradient background with purple border and shadow
        Box(
            modifier =
                Modifier
                    .clickable { isExpanded = !isExpanded }
                    .shadow(
                        elevation = Dimensions.shadowSmall,
                        shape = toggleShape,
                        ambientColor = AppColors.primaryPurple.copy(alpha = 0.2f),
                        spotColor = AppColors.primaryPurple.copy(alpha = 0.2f),
                    )
                    .clip(toggleShape)
                    .background(
                        brush = Brush.linearGradient(
                            colors = listOf(
                                AppColors.primaryPurple.copy(alpha = 0.1f),
                                AppColors.primaryPurple.copy(alpha = 0.05f),
                            ),
                        ),
                    )
                    .border(
                        width = Dimensions.strokeThin,
                        color = AppColors.primaryPurple.copy(alpha = 0.2f),
                        shape = toggleShape,
                    ),
        ) {
            Row(
                modifier =
                    Modifier.padding(
                        horizontal = Dimensions.thinkingSectionPaddingHorizontal,
                        vertical = Dimensions.thinkingSectionPaddingVertical,
                    ),
                horizontalArrangement = Arrangement.spacedBy(Dimensions.toolbarButtonSpacing),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Default.Lightbulb,
                    contentDescription = null,
                    modifier = Modifier.size(AppTypography.caption.fontSize.value.dp),
                    tint = AppColors.primaryPurple,
                )
                Text(
                    text = if (isExpanded) "Hide reasoning" else thinkingSummary,
                    style = AppTypography.caption,
                    color = AppColors.primaryPurple,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Icon(
                    imageVector = if (isExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowRight,
                    contentDescription = null,
                    modifier = Modifier.size(AppTypography.caption2.fontSize.value.dp),
                    tint = AppColors.primaryPurple.copy(alpha = 0.6f),
                )
            }
        }

        // Expanded content
        AnimatedVisibility(
            visible = isExpanded,
            enter = fadeIn(animationSpec = tween(250)) + expandVertically(),
            exit = fadeOut(animationSpec = tween(250)) + shrinkVertically(),
        ) {
            Column {
                Spacer(modifier = Modifier.height(Dimensions.small))
                Surface(
                    color = AppColors.thinkingContentBackground,
                    shape = RoundedCornerShape(Dimensions.thinkingContentCornerRadius),
                ) {
                    Box(
                        modifier =
                            Modifier
                                .heightIn(max = Dimensions.thinkingContentMaxHeight)
                                .padding(Dimensions.thinkingContentPadding),
                    ) {
                        Text(
                            text = thinkingContent,
                            style = AppTypography.caption,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        }
    }
}

// ====================
// ANALYTICS FOOTER
// ====================

// Matches iOS timestampAndAnalyticsSection - right-aligned, timestamp always shown + optional analytics
@Composable
fun AnalyticsFooter(
    message: ChatMessage,
    hasThinking: Boolean,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(Dimensions.small),
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(start = Dimensions.mediumLarge),
        ) {
            // Timestamp - always shown ( Text(message.timestamp, style: .time))
            Text(
                text = formatTimestamp(message.timestamp),
                style = AppTypography.caption2,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Analytics (optional)
            message.analytics?.let { analytics ->
                // Separator
                Text(
                    text = "\u2022",
                    style = AppTypography.caption2,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                )

                // Generation time
                Text(
                    text = String.format("%.1fs", analytics.totalGenerationTime / 1000.0),
                    style = AppTypography.caption2,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                // Tokens per second (only if > 0, )
                if (analytics.averageTokensPerSecond > 0) {
                    Text(
                        text = "\u2022",
                        style = AppTypography.caption2,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                    )

                    Text(
                        text = "${analytics.averageTokensPerSecond.toInt()} tok/s",
                        style = AppTypography.caption2,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                // Thinking indicator ( lightbulb.min icon)
                if (analytics.wasThinkingMode) {
                    Icon(
                        imageVector = Icons.Default.Lightbulb,
                        contentDescription = null,
                        modifier = Modifier.size(AppTypography.caption2.fontSize.value.dp),
                        tint = AppColors.primaryPurple.copy(alpha = 0.7f),
                    )
                }
            }
        }
    }
}

// ====================
// TYPING INDICATOR
// ====================

// Typing indicator - : dots in separate bubble, text outside, centered with spacers
@Composable
fun TypingIndicatorView() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Spacer(modifier = Modifier.width(Dimensions.messageBubbleMinSpacing))

        Row(
            horizontalArrangement = Arrangement.spacedBy(Dimensions.mediumLarge),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Dots in their own bubble background - 
            Box(
                modifier = Modifier
                    .shadow(
                        elevation = Dimensions.shadowMedium,
                        shape = RoundedCornerShape(Dimensions.large),
                        ambientColor = AppColors.shadowLight,
                        spotColor = AppColors.shadowLight,
                    )
                    .clip(RoundedCornerShape(Dimensions.large))
                    .background(AppColors.typingIndicatorBackground)
                    .border(
                        width = Dimensions.strokeThin,
                        color = AppColors.typingIndicatorBorder,
                        shape = RoundedCornerShape(Dimensions.large),
                    )
                    .padding(
                        horizontal = Dimensions.typingIndicatorPaddingHorizontal,
                        vertical = Dimensions.typingIndicatorPaddingVertical,
                    ),
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(Dimensions.typingIndicatorDotSpacing),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    repeat(3) { index ->
                        val infiniteTransition = rememberInfiniteTransition(label = "typing")
                        val scale by infiniteTransition.animateFloat(
                            initialValue = 0.8f,
                            targetValue = 1.3f,
                            animationSpec =
                                infiniteRepeatable(
                                    animation = tween(600),
                                    repeatMode = RepeatMode.Reverse,
                                    initialStartOffset = StartOffset(index * 200),
                                ),
                            label = "dot_scale_$index",
                        )

                        Box(
                            modifier =
                                Modifier
                                    .size(Dimensions.typingIndicatorDotSize)
                                    .graphicsLayer {
                                        scaleX = scale
                                        scaleY = scale
                                    }
                                    .background(
                                        color = AppColors.typingIndicatorDots,
                                        shape = CircleShape,
                                    ),
                        )
                    }
                }
            }

            // Text outside the bubble - 
            Text(
                text = "AI is thinking...",
                style = AppTypography.caption,
                color = AppColors.typingIndicatorText,
            )
        }

        Spacer(modifier = Modifier.width(Dimensions.messageBubbleMinSpacing))
    }
}

// ====================
// EMPTY STATE - : centered logo with title and subtitle
// ====================

@Composable
fun EmptyStateView(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Spacer(modifier = Modifier.weight(1f))

        // App logo -  runanywhere_logo 80x80
        Image(
            painter = painterResource(id = com.runanywhere.runanywhereai.R.drawable.runanywhere_logo),
            contentDescription = "RunAnywhere Logo",
            modifier = Modifier.size(80.dp),
            contentScale = ContentScale.Fit,
        )

        Spacer(modifier = Modifier.height(Dimensions.large))

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
        ) {
            Text(
                text = "Start a conversation",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )

            Text(
                text = "Type a message below to get started",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}

// ====================
// MODEL SELECTION PROMPT
// ====================

/**
 * Tool calling indicator badge - matching iOS ChatInterfaceView toolCallingBadge
 */
@Composable
fun ToolCallingBadge(toolCount: Int) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Dimensions.mediumLarge, vertical = Dimensions.small),
        horizontalArrangement = Arrangement.Center,
    ) {
        Row(
            modifier = Modifier
                .background(
                    color = AppColors.primaryAccent.copy(alpha = 0.1f),
                    shape = RoundedCornerShape(6.dp)
                )
                .padding(horizontal = 10.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(
                imageVector = Icons.Default.Build,
                contentDescription = "Tools enabled",
                modifier = Modifier.size(10.dp),
                tint = AppColors.primaryAccent,
            )
            Text(
                text = "Tools enabled ($toolCount)",
                style = AppTypography.caption2,
                color = AppColors.primaryAccent,
            )
        }
    }
}

@Composable
fun ModelSelectionPrompt(onSelectModel: () -> Unit) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.primaryContainer,
    ) {
        Column(
            modifier = Modifier.padding(Dimensions.mediumLarge),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
        ) {
            Text(
                text = "Welcome! Select and download a model to start chatting.",
                style = AppTypography.caption,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )

            Button(
                onClick = onSelectModel,
                colors =
                    ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary,
                    ),
            ) {
                Text(
                    text = "Select Model",
                    style = AppTypography.caption,
                )
            }
        }
    }
}

// ====================
// INPUT AREA
// ====================

// Input area : plain text field, no shadow, no rounded background, 16dp padding
@Composable
fun ChatInputView(
    value: String,
    onValueChange: (String) -> Unit,
    onSend: () -> Unit,
    isGenerating: Boolean,
    isModelLoaded: Boolean,
) {
    val canSendMessage = isModelLoaded && !isGenerating && value.trim().isNotBlank()

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(Dimensions.small),
            horizontalArrangement = Arrangement.spacedBy(Dimensions.mediumLarge),
            verticalAlignment = Alignment.Bottom,
    ) {
        // Plain text field -  .textFieldStyle(.plain)
        TextField(
            value = value,
            onValueChange = onValueChange,
            modifier = Modifier.weight(1f),
            placeholder = {
                Text(
                    text = "Type a message...",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                )
            },
            enabled = isModelLoaded && !isGenerating,
            textStyle = MaterialTheme.typography.bodyLarge,
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Color.Transparent,
                unfocusedContainerColor = Color.Transparent,
                disabledContainerColor = Color.Transparent,
                focusedIndicatorColor = Color.Transparent,
                unfocusedIndicatorColor = Color.Transparent,
                disabledIndicatorColor = Color.Transparent,
            ),
            maxLines = 4,
        )

        // Send button -  arrow.up.circle.fill 28pt
        IconButton(
            onClick = onSend,
            enabled = canSendMessage,
            modifier = Modifier.size(Dimensions.buttonHeightRegular),
        ) {
            Icon(
                imageVector = Icons.Filled.ArrowCircleUp,
                contentDescription = "Send",
                tint = if (canSendMessage) {
                    AppColors.primaryAccent
                } else {
                    AppColors.statusGray
                },
                modifier = Modifier.size(Dimensions.iconMedium),
            )
        }
    }
}

// ====================
// CONVERSATION LIST SHEET
// Conversation List View
// ====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConversationListSheet(
    conversations: List<Conversation>,
    currentConversationId: String?,
    onDismiss: () -> Unit,
    onConversationSelected: (Conversation) -> Unit,
    onNewConversation: () -> Unit,
    onDeleteConversation: (Conversation) -> Unit,
) {
    var searchQuery by remember { mutableStateOf("") }
    var conversationToDelete by remember { mutableStateOf<Conversation?>(null) }

    val filteredConversations =
        remember(conversations, searchQuery) {
            if (searchQuery.isEmpty()) {
                conversations
            } else {
                conversations.filter { conversation ->
                    conversation.title?.lowercase()?.contains(searchQuery.lowercase()) == true ||
                            conversation.messages.any { it.content.lowercase().contains(searchQuery.lowercase()) }
                }
            }
        }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.85f),
        ) {
            // Header
            Row(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss) {
                    Text("Done")
                }

                Text(
                    text = "Conversations",
                    style = MaterialTheme.typography.titleMedium,
                )

                IconButton(onClick = onNewConversation) {
                    Icon(
                        imageVector = Icons.Default.Add,
                        contentDescription = "New Conversation",
                    )
                }
            }

            // Search bar
            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                placeholder = { Text("Search conversations") },
                leadingIcon = {
                    Icon(
                        imageVector = Icons.Default.Search,
                        contentDescription = null,
                    )
                },
                trailingIcon = {
                    if (searchQuery.isNotEmpty()) {
                        IconButton(onClick = { searchQuery = "" }) {
                            Icon(
                                imageVector = Icons.Default.Clear,
                                contentDescription = "Clear",
                            )
                        }
                    }
                },
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                singleLine = true,
                shape = RoundedCornerShape(12.dp),
            )

            // Conversation list
            if (filteredConversations.isEmpty()) {
                Box(
                    modifier =
                        Modifier
                            .fillMaxWidth()
                            .weight(1f),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = if (searchQuery.isEmpty()) "No conversations yet" else "No results found",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                ) {
                    items(filteredConversations, key = { it.id }) { conversation ->
                        ConversationRow(
                            conversation = conversation,
                            isSelected = conversation.id == currentConversationId,
                            onClick = { onConversationSelected(conversation) },
                            onDelete = { conversationToDelete = conversation },
                        )
                    }
                }
            }
        }
    }

    // Delete confirmation dialog
    conversationToDelete?.let { conversation ->
        AlertDialog(
            onDismissRequest = { conversationToDelete = null },
            title = { Text("Delete Conversation?") },
            text = { Text("This action cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        onDeleteConversation(conversation)
                        conversationToDelete = null
                    },
                ) {
                    Text("Delete", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { conversationToDelete = null }) {
                    Text("Cancel")
                }
            },
        )
    }
}

@Composable
private fun ConversationRow(
    conversation: Conversation,
    isSelected: Boolean,
    onClick: () -> Unit,
    onDelete: () -> Unit,
) {
    val dateFormatter = remember { SimpleDateFormat("MMM d", Locale.getDefault()) }

    Surface(
        onClick = onClick,
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
        shape = RoundedCornerShape(12.dp),
        color =
            if (isSelected) {
                MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f)
            } else {
                Color.Transparent
            },
    ) {
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                // Title
                Text(
                    text = conversation.title ?: "New Chat",
                    style = MaterialTheme.typography.bodyLarge,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )

                Spacer(modifier = Modifier.height(4.dp))

                // Last message preview
                Text(
                    text =
                        conversation.messages.lastOrNull()?.content?.take(100)
                            ?: "Start a conversation",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )

                Spacer(modifier = Modifier.height(4.dp))

                // Summary and date
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val messageCount = conversation.messages.size
                    val userMessages = conversation.messages.count { it.role == MessageRole.USER }
                    val aiMessages = conversation.messages.count { it.role == MessageRole.ASSISTANT }

                    Text(
                        text = "$messageCount messages • $userMessages from you, $aiMessages from AI",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                    )

                    Spacer(modifier = Modifier.weight(1f))

                    Text(
                        text = dateFormatter.format(Date(conversation.updatedAt)),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                    )
                }
            }

            // Delete button
            IconButton(onClick = onDelete) {
                Icon(
                    imageVector = Icons.Default.Delete,
                    contentDescription = "Delete",
                    tint = MaterialTheme.colorScheme.error.copy(alpha = 0.7f),
                )
            }
        }
    }
}

// ====================
// CHAT DETAILS SHEET
// Chat Details View
// ====================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatDetailsSheet(
    messages: List<ChatMessage>,
    conversationTitle: String,
    modelName: String?,
    onDismiss: () -> Unit,
) {
    val analyticsMessages =
        remember(messages) {
            messages.filter { it.analytics != null }
        }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .fillMaxHeight(0.75f)
                    .padding(horizontal = 16.dp),
        ) {
            // Header - navigationTitle("Analytics"), toolbar Button("Done") { dismiss() }
            Row(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Spacer(modifier = Modifier.width(48.dp))

                Text(
                    text = "Analytics",
                    style = MaterialTheme.typography.titleMedium,
                )

                TextButton(onClick = onDismiss) {
                    Text("Done", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Medium)
                }
            }

            HorizontalDivider()

            LazyColumn(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                contentPadding = PaddingValues(vertical = 16.dp),
            ) {
                // Conversation Info Section
                item {
                    DetailsSection(title = "Conversation") {
                        DetailsRow(label = "Title", value = conversationTitle)
                        DetailsRow(label = "Messages", value = "${messages.size}")
                        DetailsRow(
                            label = "User Messages",
                            value = "${messages.count { it.role == MessageRole.USER }}",
                        )
                        DetailsRow(
                            label = "AI Responses",
                            value = "${messages.count { it.role == MessageRole.ASSISTANT }}",
                        )
                        modelName?.let {
                            DetailsRow(label = "Model", value = it)
                        }
                    }
                }

                // Performance Summary Section
                if (analyticsMessages.isNotEmpty()) {
                    item {
                        DetailsSection(title = "Performance Summary") {
                            val avgTTFT =
                                analyticsMessages
                                    .mapNotNull { it.analytics?.timeToFirstToken }
                                    .average()
                                    .takeIf { !it.isNaN() }

                            val avgSpeed =
                                analyticsMessages
                                    .mapNotNull { it.analytics?.averageTokensPerSecond }
                                    .average()
                                    .takeIf { !it.isNaN() }

                            val totalTokens =
                                analyticsMessages
                                    .mapNotNull { it.analytics }
                                    .sumOf { it.inputTokens + it.outputTokens }

                            val thinkingCount =
                                analyticsMessages
                                    .count { it.analytics?.wasThinkingMode == true }

                            avgTTFT?.let {
                                DetailsRow(
                                    label = "Avg Time to First Token",
                                    value = String.format("%.2fs", it / 1000.0),
                                )
                            }

                            avgSpeed?.let {
                                DetailsRow(
                                    label = "Avg Generation Speed",
                                    value = String.format("%.1f tok/s", it),
                                )
                            }

                            DetailsRow(label = "Total Tokens", value = "$totalTokens")

                            if (thinkingCount > 0) {
                                DetailsRow(
                                    label = "Thinking Mode Usage",
                                    value = "$thinkingCount/${analyticsMessages.size} responses",
                                )
                            }
                        }
                    }
                }

                // Individual Message Analytics
                if (analyticsMessages.isNotEmpty()) {
                    item {
                        Text(
                            text = "Message Analytics",
                            style = MaterialTheme.typography.titleSmall,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }

                    items(analyticsMessages.reversed()) { message ->
                        message.analytics?.let { analytics ->
                            MessageAnalyticsCard(
                                messagePreview = message.content.take(50) + if (message.content.length > 50) "..." else "",
                                analytics = analytics,
                                hasThinking = message.thinkingContent != null,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DetailsSection(
    title: String,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.primary,
            )
            content()
        }
    }
}

@Composable
private fun DetailsRow(
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun MessageAnalyticsCard(
    messagePreview: String,
    analytics: com.runanywhere.runanywhereai.domain.models.MessageAnalytics,
    hasThinking: Boolean,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surface,
        border =
            androidx.compose.foundation.BorderStroke(
                1.dp,
                MaterialTheme.colorScheme.outline.copy(alpha = 0.3f),
            ),
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // Message preview
            Text(
                text = messagePreview,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )

            HorizontalDivider()

            // Analytics grid
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Column {
                    Text(
                        text = "Tokens",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = "${analytics.outputTokens}",
                        style = MaterialTheme.typography.bodySmall,
                    )
                }

                Column {
                    Text(
                        text = "Speed",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = String.format("%.1f tok/s", analytics.averageTokensPerSecond),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }

                Column {
                    Text(
                        text = "Time",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = String.format("%.2fs", analytics.totalGenerationTime / 1000.0),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }

                if (hasThinking) {
                    Icon(
                        imageVector = Icons.Default.Lightbulb,
                        contentDescription = "Thinking mode",
                        modifier = Modifier.size(16.dp),
                        tint = MaterialTheme.colorScheme.secondary,
                    )
                }
            }
        }
    }
}

// ====================
// SELECTABLE TEXT DIALOG
// ====================

@Composable
private fun SelectableTextDialog(
    text: String,
    onDismiss: () -> Unit,
) {
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(
            usePlatformDefaultWidth = false,
            decorFitsSystemWindows = false,
        ),
    ) {
        Box(
            modifier =
                Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.surface),
        ) {
            Column(
                modifier = Modifier.fillMaxSize(),
            ) {
                Surface(
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    tonalElevation = Dimensions.padding4,
                ) {
                    Row(
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .padding(horizontal = Dimensions.padding16, vertical = Dimensions.padding12),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "Select Text",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        IconButton(onClick = onDismiss) {
                            Icon(
                                imageVector = Icons.Default.Close,
                                contentDescription = "Close",
                            )
                        }
                    }
                }

                // Selectable text content
                SelectionContainer {
                    Box(
                        modifier =
                            Modifier
                                .fillMaxSize()
                                .verticalScroll(rememberScrollState())
                                .padding(Dimensions.padding16),
                    ) {
                        Text(
                            text = text,
                            style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier.fillMaxWidth(),
                        )
                    }
                }
            }
        }
    }
}
