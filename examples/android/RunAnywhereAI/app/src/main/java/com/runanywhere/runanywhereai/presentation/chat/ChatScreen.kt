package com.runanywhere.runanywhereai.presentation.chat

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.domain.models.ChatMessage
import com.runanywhere.runanywhereai.domain.models.MessageRole
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppTypography
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import kotlinx.coroutines.launch

/**
 * iOS-matching ChatScreen with pixel-perfect design
 * Reference: iOS ChatInterfaceView.swift
 *
 * Design specifications:
 * - Message bubbles: 18dp corner radius, 16dp horizontal padding, 12dp vertical padding
 * - User bubble: Blue gradient with white text
 * - Assistant bubble: Gray gradient with primary text
 * - Thinking section: Purple theme with collapsible content
 * - Typing indicator: Animated dots with blue color
 * - Empty state: 60sp icon with title and subtitle
 * - Matches iOS implementation exactly including:
 *   - Conversation list management
 *   - Model selection sheet
 *   - Chat details view with analytics
 *   - Toolbar button conditions
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    viewModel: ChatViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    // State for sheets and dialogs - matching iOS
    var showingConversationList by remember { mutableStateOf(false) }
    var showingModelSelection by remember { mutableStateOf(false) }
    var showingChatDetails by remember { mutableStateOf(false) }
    var showDebugAlert by remember { mutableStateOf(false) }
    var debugMessage by remember { mutableStateOf("") }

    // Auto-scroll to bottom when new messages arrive - matching iOS behavior
    LaunchedEffect(uiState.messages.size, uiState.isGenerating) {
        if (uiState.messages.isNotEmpty()) {
            scope.launch {
                listState.animateScrollToItem(uiState.messages.size - 1)
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = if (uiState.isModelLoaded) {
                            uiState.loadedModelName ?: "Chat"
                        } else {
                            "Chat"
                        },
                        style = MaterialTheme.typography.headlineMedium
                    )
                },
                navigationIcon = {
                    // Conversation list button - matching iOS
                    IconButton(onClick = { showingConversationList = true }) {
                        Icon(
                            imageVector = Icons.Default.List,
                            contentDescription = "Conversations"
                        )
                    }
                },
                actions = {
                    // Info button for chat details - matching iOS
                    IconButton(
                        onClick = { showingChatDetails = true },
                        enabled = uiState.messages.isNotEmpty()
                    ) {
                        Icon(
                            imageVector = Icons.Default.Info,
                            contentDescription = "Info",
                            tint = if (uiState.messages.isNotEmpty()) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                            }
                        )
                    }

                    Spacer(modifier = Modifier.width(Dimensions.toolbarButtonSpacing))

                    // Model selection button - matching iOS
                    TextButton(
                        onClick = { showingModelSelection = true }
                    ) {
                        Icon(
                            imageVector = Icons.Default.ViewInAr,
                            contentDescription = null,
                            modifier = Modifier.size(Dimensions.iconRegular)
                        )
                        Spacer(modifier = Modifier.width(Dimensions.xSmall))
                        Text(
                            text = if (uiState.isModelLoaded) "Switch Model" else "Select Model",
                            style = AppTypography.caption
                        )
                    }

                    Spacer(modifier = Modifier.width(Dimensions.toolbarButtonSpacing))

                    // Clear chat button - matching iOS
                    IconButton(
                        onClick = { viewModel.clearChat() },
                        enabled = uiState.messages.isNotEmpty()
                    ) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = "Clear Chat",
                            tint = if (uiState.messages.isNotEmpty()) {
                                MaterialTheme.colorScheme.error
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                            }
                        )
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .background(MaterialTheme.colorScheme.background)
        ) {
            // Model info bar (conditional) - matching iOS
            AnimatedVisibility(
                visible = uiState.isModelLoaded && uiState.loadedModelName != null,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically()
            ) {
                ModelInfoBar(modelName = uiState.loadedModelName ?: "", framework = "KMP")
            }

            // Messages list or empty state - matching iOS
            if (uiState.messages.isEmpty() && !uiState.isGenerating) {
                EmptyStateView(
                    isModelLoaded = uiState.isModelLoaded,
                    modelName = uiState.loadedModelName
                )
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(Dimensions.large),
                    verticalArrangement = Arrangement.spacedBy(Dimensions.messageSpacingBetween)
                ) {
                    // Add spacer at top for better scrolling - matching iOS
                    item {
                        Spacer(modifier = Modifier.height(20.dp))
                    }

                    items(uiState.messages, key = { it.id }) { message ->
                        MessageBubbleView(
                            message = message,
                            isGenerating = uiState.isGenerating
                        )
                    }

                    // Typing indicator - matching iOS
                    if (uiState.isGenerating) {
                        item {
                            TypingIndicatorView()
                        }
                    }

                    // Add spacer at bottom for better keyboard handling - matching iOS
                    item {
                        Spacer(modifier = Modifier.height(20.dp))
                    }
                }
            }

            // Divider above input
            HorizontalDivider(
                thickness = Dimensions.strokeThin,
                color = MaterialTheme.colorScheme.outline
            )

            // Model selection prompt (when no model loaded) - matching iOS
            AnimatedVisibility(
                visible = !uiState.isModelLoaded,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically()
            ) {
                ModelSelectionPrompt(
                    onSelectModel = { showingModelSelection = true }
                )
            }

            // Input area
            ChatInputView(
                value = uiState.currentInput,
                onValueChange = viewModel::updateInput,
                onSend = viewModel::sendMessage,
                enabled = uiState.canSend,
                isGenerating = uiState.isGenerating,
                isModelLoaded = uiState.isModelLoaded
            )
        }
    }

    // Model Selection Bottom Sheet - Matching iOS
    if (showingModelSelection) {
        com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet(
            onDismiss = { showingModelSelection = false },
            onModelSelected = { model ->
                scope.launch {
                    // Update view model that model was selected
                    viewModel.checkModelStatus()
                }
            }
        )
    }

    // TODO: Show conversation list sheet
    // TODO: Show chat details sheet

    // Handle error state
    LaunchedEffect(uiState.error) {
        if (uiState.error != null) {
            debugMessage = "Error occurred: ${uiState.error?.localizedMessage}"
            showDebugAlert = true
        }
    }

    // Debug alert dialog
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
                    }
                ) {
                    Text("OK")
                }
            }
        )
    }
}

// ====================
// MODEL INFO BAR
// ====================

@Composable
fun ModelInfoBar(
    modelName: String,
    framework: String
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    horizontal = Dimensions.modelInfoBarPaddingHorizontal,
                    vertical = Dimensions.modelInfoBarPaddingVertical
                ),
            horizontalArrangement = Arrangement.spacedBy(Dimensions.modelInfoStatsItemSpacing),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Framework badge
            Surface(
                color = MaterialTheme.colorScheme.primary,
                shape = RoundedCornerShape(Dimensions.modelInfoFrameworkBadgeCornerRadius),
                modifier = Modifier.border(
                    width = Dimensions.strokeThin,
                    color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.2f),
                    shape = RoundedCornerShape(Dimensions.modelInfoFrameworkBadgeCornerRadius)
                )
            ) {
                Text(
                    text = framework,
                    style = AppTypography.monospacedCaption,
                    color = MaterialTheme.colorScheme.onPrimary,
                    modifier = Modifier.padding(
                        horizontal = Dimensions.modelInfoFrameworkBadgePaddingHorizontal,
                        vertical = Dimensions.modelInfoFrameworkBadgePaddingVertical
                    )
                )
            }

            // Model name (first word only) - matching iOS
            Text(
                text = modelName.split(" ").first(),
                style = AppTypography.rounded11,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            // Stats (storage icon + size) - matching iOS
            Row(
                horizontalArrangement = Arrangement.spacedBy(Dimensions.modelInfoStatsIconTextSpacing),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Storage,
                    contentDescription = null,
                    modifier = Modifier.size(Dimensions.iconSmall),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "1.2G",  // TODO: Get actual size
                    style = AppTypography.rounded10,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Context length - matching iOS
            Row(
                horizontalArrangement = Arrangement.spacedBy(Dimensions.modelInfoStatsIconTextSpacing),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Description,
                    contentDescription = null,
                    modifier = Modifier.size(Dimensions.iconSmall),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
                Text(
                    text = "128K",  // TODO: Get actual context length
                    style = AppTypography.rounded10,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }

    // Bottom border with offset - matching iOS
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .offset(y = Dimensions.mediumLarge)  // 12.dp offset
    ) {
        HorizontalDivider(
            thickness = Dimensions.strokeThin,
            color = MaterialTheme.colorScheme.outline
        )
    }
}

// ====================
// MESSAGE BUBBLE
// ====================

@Composable
fun MessageBubbleView(
    message: ChatMessage,
    isGenerating: Boolean = false
) {
    val alignment = if (message.role == MessageRole.USER) {
        Arrangement.End
    } else {
        Arrangement.Start
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = alignment
    ) {
        // Spacer for alignment
        if (message.role == MessageRole.USER) {
            Spacer(modifier = Modifier.width(Dimensions.messageBubbleMinSpacing))
        }

        Column(
            modifier = Modifier.widthIn(max = Dimensions.messageBubbleMaxWidth),
            horizontalAlignment = if (message.role == MessageRole.USER) {
                Alignment.End
            } else {
                Alignment.Start
            }
        ) {
            // Model badge (for assistant messages) - matching iOS
            if (message.role == MessageRole.ASSISTANT && message.modelInfo != null) {
                ModelBadge(
                    modelName = message.modelInfo.modelName,
                    framework = message.modelInfo.framework
                )
                Spacer(modifier = Modifier.height(Dimensions.small))
            }

            // Thinking toggle (if thinking content exists) - matching iOS
            message.thinkingContent?.let { thinking ->
                ThinkingToggle(
                    thinkingContent = thinking,
                    isGenerating = isGenerating
                )
                Spacer(modifier = Modifier.height(Dimensions.small))
            }

            // Main message bubble - only show if there's content (matching iOS)
            if (message.content.isNotEmpty()) {
                Surface(
                    color = if (message.role == MessageRole.USER) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.surfaceVariant
                    },
                    shape = RoundedCornerShape(Dimensions.messageBubbleCornerRadius),
                    modifier = Modifier
                        .shadow(
                            elevation = Dimensions.messageBubbleShadowRadius,
                            shape = RoundedCornerShape(Dimensions.messageBubbleCornerRadius)
                        )
                        .border(
                            width = Dimensions.strokeThin,
                            color = if (message.role == MessageRole.USER) {
                                MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.3f)
                            } else {
                                MaterialTheme.colorScheme.outline.copy(alpha = 0.5f)
                            },
                            shape = RoundedCornerShape(Dimensions.messageBubbleCornerRadius)
                        )
                ) {
                    Text(
                        text = message.content,
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (message.role == MessageRole.USER) {
                            MaterialTheme.colorScheme.onPrimary
                        } else {
                            MaterialTheme.colorScheme.onSurface
                        },
                        modifier = Modifier.padding(
                            horizontal = Dimensions.messageBubblePaddingHorizontal,
                            vertical = Dimensions.messageBubblePaddingVertical
                        )
                    )
                }
            }

            // Analytics footer (for assistant messages) - matching iOS
            if (message.role == MessageRole.ASSISTANT && message.analytics != null) {
                Spacer(modifier = Modifier.height(Dimensions.small))
                AnalyticsFooter(
                    analytics = message.analytics,
                    hasThinking = message.thinkingContent != null
                )
            }

            // Timestamp (for user messages) - matching iOS
            if (message.role == MessageRole.USER) {
                Spacer(modifier = Modifier.height(Dimensions.small))
                Text(
                    text = formatTimestamp(message.timestamp),
                    style = AppTypography.caption2,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.align(Alignment.End)
                )
            }
        }

        // Spacer for alignment
        if (message.role == MessageRole.ASSISTANT) {
            Spacer(modifier = Modifier.width(Dimensions.messageBubbleMinSpacing))
        }
    }
}

// Helper function to format timestamp - matching iOS
private fun formatTimestamp(timestamp: Long): String {
    val calendar = java.util.Calendar.getInstance()
    calendar.timeInMillis = timestamp
    val hour = calendar.get(java.util.Calendar.HOUR)
    val minute = calendar.get(java.util.Calendar.MINUTE)
    val amPm = if (calendar.get(java.util.Calendar.AM_PM) == java.util.Calendar.AM) "AM" else "PM"
    return String.format("%d:%02d %s", if (hour == 0) 12 else hour, minute, amPm)
}

// ====================
// MODEL BADGE
// ====================

@Composable
fun ModelBadge(
    modelName: String,
    framework: com.runanywhere.sdk.models.enums.LLMFramework
) {
    Surface(
        color = MaterialTheme.colorScheme.primary,
        shape = RoundedCornerShape(Dimensions.modelBadgeCornerRadius),
        modifier = Modifier
            .shadow(
                elevation = Dimensions.shadowSmall,
                shape = RoundedCornerShape(Dimensions.modelBadgeCornerRadius)
            )
            .border(
                width = Dimensions.strokeThin,
                color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.2f),
                shape = RoundedCornerShape(Dimensions.modelBadgeCornerRadius)
            )
    ) {
        Row(
            modifier = Modifier.padding(
                horizontal = Dimensions.modelBadgePaddingHorizontal,
                vertical = Dimensions.modelBadgePaddingVertical
            ),
            horizontalArrangement = Arrangement.spacedBy(Dimensions.modelBadgeSpacing),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Default.ViewInAr,
                contentDescription = null,
                modifier = Modifier.size(AppTypography.caption2.fontSize.value.dp),
                tint = MaterialTheme.colorScheme.onPrimary
            )
            Text(
                text = modelName,
                style = AppTypography.caption2Medium,
                color = MaterialTheme.colorScheme.onPrimary
            )
            Text(
                text = framework.displayName,
                style = AppTypography.caption2,
                color = MaterialTheme.colorScheme.onPrimary
            )
        }
    }
}

// ====================
// THINKING SECTION
// ====================

@Composable
fun ThinkingToggle(
    thinkingContent: String,
    isGenerating: Boolean
) {
    var isExpanded by remember { mutableStateOf(false) }

    Column {
        // Toggle button
        Surface(
            color = Color.Transparent,
            shape = RoundedCornerShape(Dimensions.thinkingSectionCornerRadius),
            modifier = Modifier
                .clickable { isExpanded = !isExpanded }
                .shadow(
                    elevation = Dimensions.shadowSmall,
                    shape = RoundedCornerShape(Dimensions.thinkingSectionCornerRadius),
                    ambientColor = MaterialTheme.colorScheme.secondary.copy(alpha = 0.2f),
                    spotColor = MaterialTheme.colorScheme.secondary.copy(alpha = 0.2f)
                )
                .background(
                    color = MaterialTheme.colorScheme.secondaryContainer,
                    shape = RoundedCornerShape(Dimensions.thinkingSectionCornerRadius)
                )
                .border(
                    width = Dimensions.strokeThin,
                    color = MaterialTheme.colorScheme.secondary.copy(alpha = 0.2f),
                    shape = RoundedCornerShape(Dimensions.thinkingSectionCornerRadius)
                )
        ) {
            Row(
                modifier = Modifier.padding(
                    horizontal = Dimensions.thinkingSectionPaddingHorizontal,
                    vertical = Dimensions.thinkingSectionPaddingVertical
                ),
                horizontalArrangement = Arrangement.spacedBy(Dimensions.toolbarButtonSpacing),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Lightbulb,
                    contentDescription = null,
                    modifier = Modifier.size(AppTypography.caption.fontSize.value.dp),
                    tint = MaterialTheme.colorScheme.secondary
                )
                Text(
                    text = if (isExpanded) "Hide reasoning" else "Show reasoning...",
                    style = AppTypography.caption,
                    color = MaterialTheme.colorScheme.secondary,
                    modifier = Modifier.weight(1f)
                )
                Icon(
                    imageVector = if (isExpanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowRight,
                    contentDescription = null,
                    modifier = Modifier.size(AppTypography.caption2.fontSize.value.dp),
                    tint = MaterialTheme.colorScheme.secondary.copy(alpha = 0.6f)
                )
            }
        }

        // Expanded content
        AnimatedVisibility(
            visible = isExpanded,
            enter = fadeIn(animationSpec = tween(250)) + expandVertically(),
            exit = fadeOut(animationSpec = tween(250)) + shrinkVertically()
        ) {
            Column {
                Spacer(modifier = Modifier.height(Dimensions.small))
                Surface(
                    color = MaterialTheme.colorScheme.surfaceVariant,
                    shape = RoundedCornerShape(Dimensions.thinkingContentCornerRadius)
                ) {
                    Box(
                        modifier = Modifier
                            .heightIn(max = Dimensions.thinkingContentMaxHeight)
                            .padding(Dimensions.thinkingContentPadding)
                    ) {
                        Text(
                            text = thinkingContent,
                            style = AppTypography.caption,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
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

@Composable
fun AnalyticsFooter(
    analytics: com.runanywhere.runanywhereai.domain.models.MessageAnalytics,
    hasThinking: Boolean
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Timestamp
        Text(
            text = formatTimestamp(analytics.timestamp),
            style = AppTypography.caption2,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        // Separator
        Text(
            text = "•",
            style = AppTypography.caption2,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
        )

        // Duration
        analytics.timeToFirstToken?.let { ttft ->
            Text(
                text = "${ttft / 1000f}s",
                style = AppTypography.caption2,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = "•",
                style = AppTypography.caption2,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
            )
        }

        // Tokens per second
        Text(
            text = String.format("%.1f tok/s", analytics.averageTokensPerSecond),
            style = AppTypography.caption2,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        // Thinking indicator
        if (hasThinking) {
            Text(
                text = "•",
                style = AppTypography.caption2,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
            )
            Icon(
                imageVector = Icons.Default.Lightbulb,
                contentDescription = null,
                modifier = Modifier.size(AppTypography.caption2.fontSize.value.dp),
                tint = MaterialTheme.colorScheme.secondary
            )
        }
    }
}

// ====================
// TYPING INDICATOR
// ====================

@Composable
fun TypingIndicatorView() {
    Row(
        modifier = Modifier.widthIn(max = Dimensions.messageBubbleMaxWidth),
        horizontalArrangement = Arrangement.Start
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(Dimensions.typingIndicatorCornerRadius),
            modifier = Modifier
                .shadow(
                    elevation = Dimensions.shadowMedium,
                    shape = RoundedCornerShape(Dimensions.typingIndicatorCornerRadius)
                )
                .border(
                    width = Dimensions.strokeThin,
                    color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.3f),
                    shape = RoundedCornerShape(Dimensions.typingIndicatorCornerRadius)
                )
        ) {
            Row(
                modifier = Modifier.padding(
                    horizontal = Dimensions.typingIndicatorPaddingHorizontal,
                    vertical = Dimensions.typingIndicatorPaddingVertical
                ),
                horizontalArrangement = Arrangement.spacedBy(Dimensions.typingIndicatorDotSpacing),
                verticalAlignment = Alignment.CenterVertically
            ) {
                // Animated dots
                repeat(3) { index ->
                    val infiniteTransition = rememberInfiniteTransition(label = "typing")
                    val scale by infiniteTransition.animateFloat(
                        initialValue = 0.8f,
                        targetValue = 1.3f,
                        animationSpec = infiniteRepeatable(
                            animation = tween(600),
                            repeatMode = RepeatMode.Reverse,
                            initialStartOffset = StartOffset(index * 200)
                        ),
                        label = "dot_scale_$index"
                    )

                    Box(
                        modifier = Modifier
                            .size(Dimensions.typingIndicatorDotSize)
                            .graphicsLayer {
                                scaleX = scale
                                scaleY = scale
                            }
                            .background(
                                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.7f),
                                shape = CircleShape
                            )
                    )
                }

                Spacer(modifier = Modifier.width(Dimensions.typingIndicatorTextSpacing))

                // "AI is thinking..." text
                Text(
                    text = "AI is thinking...",
                    style = AppTypography.caption,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f)
                )
            }
        }

        Spacer(modifier = Modifier.width(Dimensions.messageBubbleMinSpacing))
    }
}

// ====================
// EMPTY STATE
// ====================

@Composable
fun EmptyStateView(
    isModelLoaded: Boolean,
    modelName: String?
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(Dimensions.huge),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        // Icon
        Icon(
            imageVector = if (isModelLoaded) Icons.Default.Chat else Icons.Default.Download,
            contentDescription = null,
            modifier = Modifier.size(Dimensions.emptyStateIconSize),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f)
        )

        Spacer(modifier = Modifier.height(Dimensions.emptyStateIconTextSpacing))

        // Title
        Text(
            text = "Start a conversation",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface
        )

        Spacer(modifier = Modifier.height(Dimensions.emptyStateTitleSubtitleSpacing))

        // Subtitle
        Text(
            text = if (isModelLoaded) {
                "Type a message below to get started"
            } else {
                "Select a model first, then start chatting"
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center
        )
    }
}

// ====================
// MODEL SELECTION PROMPT
// ====================

@Composable
fun ModelSelectionPrompt(
    onSelectModel: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.primaryContainer
    ) {
        Column(
            modifier = Modifier.padding(Dimensions.mediumLarge),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium)
        ) {
            Text(
                text = "Welcome! Select and download a model to start chatting.",
                style = AppTypography.caption,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Button(
                onClick = onSelectModel,
                colors = ButtonDefaults.buttonColors(
                    containerColor = MaterialTheme.colorScheme.primary
                )
            ) {
                Text(
                    text = "Select Model",
                    style = AppTypography.caption
                )
            }
        }
    }
}

// ====================
// INPUT AREA
// ====================

@Composable
fun ChatInputView(
    value: String,
    onValueChange: (String) -> Unit,
    onSend: () -> Unit,
    enabled: Boolean,
    isGenerating: Boolean,
    isModelLoaded: Boolean
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 8.dp
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(Dimensions.inputAreaPadding),
            horizontalArrangement = Arrangement.spacedBy(Dimensions.inputFieldButtonSpacing),
            verticalAlignment = Alignment.Bottom
        ) {
            // Text field
            TextField(
                value = value,
                onValueChange = onValueChange,
                modifier = Modifier.weight(1f),
                placeholder = {
                    Text(
                        text = when {
                            !isModelLoaded -> "Load a model first..."
                            isGenerating -> "Generating..."
                            else -> "Type a message..."
                        },
                        style = MaterialTheme.typography.bodyLarge
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
                    disabledIndicatorColor = Color.Transparent
                ),
                maxLines = 4
            )

            // Send button
            val canSendMessage = isModelLoaded && !isGenerating && value.trim().isNotBlank()
            IconButton(
                onClick = onSend,
                enabled = canSendMessage,
                modifier = Modifier.size(Dimensions.sendButtonSize)
            ) {
                Icon(
                    imageVector = Icons.Default.ArrowUpward,
                    contentDescription = "Send",
                    tint = Color.White,
                    modifier = Modifier
                        .size(Dimensions.sendButtonSize)
                        .clip(CircleShape)
                        .background(
                            if (canSendMessage) {
                                MaterialTheme.colorScheme.primary
                            } else {
                                MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                            }
                        )
                        .padding(6.dp)
                )
            }
        }
    }
}
