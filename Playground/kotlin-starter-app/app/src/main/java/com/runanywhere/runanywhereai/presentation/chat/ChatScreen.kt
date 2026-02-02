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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.data.ConversationStore
import com.runanywhere.runanywhereai.domain.models.ChatMessage
import com.runanywhere.runanywhereai.domain.models.Conversation
import com.runanywhere.runanywhereai.domain.models.MessageRole
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppTypography
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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
fun ChatScreen(viewModel: ChatViewModel = viewModel()) {
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
                        text =
                            if (uiState.isModelLoaded) {
                                uiState.loadedModelName ?: "Chat"
                            } else {
                                "Chat"
                            },
                        style = MaterialTheme.typography.headlineMedium,
                    )
                },
                navigationIcon = {
                    // Conversation list button - matching iOS
                    IconButton(onClick = { showingConversationList = true }) {
                        Icon(
                            imageVector = Icons.Default.List,
                            contentDescription = "Conversations",
                        )
                    }
                },
                actions = {
                    // Info button for chat details - matching iOS
                    IconButton(
                        onClick = { showingChatDetails = true },
                        enabled = uiState.messages.isNotEmpty(),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Info,
                            contentDescription = "Info",
                            tint =
                                if (uiState.messages.isNotEmpty()) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                                },
                        )
                    }

                    Spacer(modifier = Modifier.width(Dimensions.toolbarButtonSpacing))

                    // Model selection button - matching iOS
                    TextButton(
                        onClick = { showingModelSelection = true },
                    ) {
                        Icon(
                            imageVector = Icons.Default.ViewInAr,
                            contentDescription = null,
                            modifier = Modifier.size(Dimensions.iconRegular),
                        )
                        Spacer(modifier = Modifier.width(Dimensions.xSmall))
                        Text(
                            text = if (uiState.isModelLoaded) "Switch Model" else "Select Model",
                            style = AppTypography.caption,
                        )
                    }

                    Spacer(modifier = Modifier.width(Dimensions.toolbarButtonSpacing))

                    // Clear chat button - matching iOS
                    IconButton(
                        onClick = { viewModel.clearChat() },
                        enabled = uiState.messages.isNotEmpty(),
                    ) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = "Clear Chat",
                            tint =
                                if (uiState.messages.isNotEmpty()) {
                                    MaterialTheme.colorScheme.error
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                                },
                        )
                    }
                },
                colors =
                    TopAppBarDefaults.topAppBarColors(
                        containerColor = MaterialTheme.colorScheme.surface,
                    ),
            )
        },
    ) { padding ->
        Column(
            modifier =
                Modifier
                    .fillMaxSize()
                    .padding(padding)
                    .background(MaterialTheme.colorScheme.background),
        ) {
            // Model info bar (conditional) - matching iOS
            AnimatedVisibility(
                visible = uiState.isModelLoaded && uiState.loadedModelName != null,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically(),
            ) {
                ModelInfoBar(modelName = uiState.loadedModelName ?: "", framework = "KMP")
            }

            // Messages list or empty state - matching iOS
            if (uiState.messages.isEmpty() && !uiState.isGenerating) {
                EmptyStateView(
                    isModelLoaded = uiState.isModelLoaded,
                    modelName = uiState.loadedModelName,
                )
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(Dimensions.large),
                    verticalArrangement = Arrangement.spacedBy(Dimensions.messageSpacingBetween),
                ) {
                    // Add spacer at top for better scrolling - matching iOS
                    item {
                        Spacer(modifier = Modifier.height(20.dp))
                    }

                    items(uiState.messages, key = { it.id }) { message ->
                        MessageBubbleView(
                            message = message,
                            isGenerating = uiState.isGenerating,
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
                color = MaterialTheme.colorScheme.outline,
            )

            // Model selection prompt (when no model loaded) - matching iOS
            AnimatedVisibility(
                visible = !uiState.isModelLoaded,
                enter = fadeIn() + expandVertically(),
                exit = fadeOut() + shrinkVertically(),
            ) {
                ModelSelectionPrompt(
                    onSelectModel = { showingModelSelection = true },
                )
            }

            // Input area
            ChatInputView(
                value = uiState.currentInput,
                onValueChange = viewModel::updateInput,
                onSend = viewModel::sendMessage,
                enabled = uiState.canSend,
                isGenerating = uiState.isGenerating,
                isModelLoaded = uiState.isModelLoaded,
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
            },
        )
    }

    // Conversation List Bottom Sheet - Matching iOS ConversationListView
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

    // Chat Details Bottom Sheet - Matching iOS ChatDetailsView
    if (showingChatDetails) {
        ChatDetailsSheet(
            messages = uiState.messages,
            conversationTitle = uiState.currentConversation?.title ?: "Chat",
            modelName = uiState.loadedModelName,
            onDismiss = { showingChatDetails = false },
        )
    }

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
                    },
                ) {
                    Text("OK")
                }
            },
        )
    }
}

// ====================
// MODEL INFO BAR
// ====================

@Composable
fun ModelInfoBar(
    modelName: String,
    framework: String,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.95f),
    ) {
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(
                        horizontal = Dimensions.modelInfoBarPaddingHorizontal,
                        vertical = Dimensions.modelInfoBarPaddingVertical,
                    ),
            horizontalArrangement = Arrangement.spacedBy(Dimensions.modelInfoStatsItemSpacing),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Framework badge
            Surface(
                color = MaterialTheme.colorScheme.primary,
                shape = RoundedCornerShape(Dimensions.modelInfoFrameworkBadgeCornerRadius),
                modifier =
                    Modifier.border(
                        width = Dimensions.strokeThin,
                        color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.2f),
                        shape = RoundedCornerShape(Dimensions.modelInfoFrameworkBadgeCornerRadius),
                    ),
            ) {
                Text(
                    text = framework,
                    style = AppTypography.monospacedCaption,
                    color = MaterialTheme.colorScheme.onPrimary,
                    modifier =
                        Modifier.padding(
                            horizontal = Dimensions.modelInfoFrameworkBadgePaddingHorizontal,
                            vertical = Dimensions.modelInfoFrameworkBadgePaddingVertical,
                        ),
                )
            }

            // Model name (first word only) - matching iOS
            Text(
                text = modelName.split(" ").first(),
                style = AppTypography.rounded11,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            // Stats (storage icon + size) - matching iOS
            Row(
                horizontalArrangement = Arrangement.spacedBy(Dimensions.modelInfoStatsIconTextSpacing),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Default.Storage,
                    contentDescription = null,
                    modifier = Modifier.size(Dimensions.iconSmall),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                // TODO: Get actual size
                Text(
                    text = "1.2G",
                    style = AppTypography.rounded10,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            // Context length - matching iOS
            Row(
                horizontalArrangement = Arrangement.spacedBy(Dimensions.modelInfoStatsIconTextSpacing),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Default.Description,
                    contentDescription = null,
                    modifier = Modifier.size(Dimensions.iconSmall),
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                // TODO: Get actual context length
                Text(
                    text = "128K",
                    style = AppTypography.rounded10,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }

    // Bottom border with offset - matching iOS (12.dp offset)
    Box(
        modifier =
            Modifier
                .fillMaxWidth()
                .offset(y = Dimensions.mediumLarge),
    ) {
        HorizontalDivider(
            thickness = Dimensions.strokeThin,
            color = MaterialTheme.colorScheme.outline,
        )
    }
}

// ====================
// MESSAGE BUBBLE
// ====================

@Composable
fun MessageBubbleView(
    message: ChatMessage,
    isGenerating: Boolean = false,
) {
    val alignment =
        if (message.role == MessageRole.USER) {
            Arrangement.End
        } else {
            Arrangement.Start
        }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = alignment,
    ) {
        // Spacer for alignment
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
            // Model badge (for assistant messages) - matching iOS
            if (message.role == MessageRole.ASSISTANT && message.modelInfo != null) {
                ModelBadge(
                    modelName = message.modelInfo.modelName,
                    framework = message.modelInfo.framework,
                )
                Spacer(modifier = Modifier.height(Dimensions.small))
            }

            // Thinking toggle (if thinking content exists) - matching iOS
            message.thinkingContent?.let { thinking ->
                ThinkingToggle(
                    thinkingContent = thinking,
                    isGenerating = isGenerating,
                )
                Spacer(modifier = Modifier.height(Dimensions.small))
            }

            // Thinking progress indicator - matching iOS pattern
            // Shows "Thinking..." when message is empty but thinking content exists during generation
            if (message.role == MessageRole.ASSISTANT &&
                message.content.isEmpty() &&
                message.thinkingContent != null &&
                isGenerating
            ) {
                ThinkingProgressIndicator()
            }

            // Main message bubble - only show if there's content (matching iOS)
            if (message.content.isNotEmpty()) {
                // Use gradient backgrounds matching iOS exactly
                val bubbleShape = RoundedCornerShape(Dimensions.messageBubbleCornerRadius)
                val isUserMessage = message.role == MessageRole.USER

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
                            ),
                ) {
                    Text(
                        text = message.content,
                        style = MaterialTheme.typography.bodyLarge,
                        color =
                            if (isUserMessage) {
                                AppColors.textWhite
                            } else {
                                AppColors.assistantBubbleTextColor()
                            },
                        modifier =
                            Modifier.padding(
                                horizontal = Dimensions.messageBubblePaddingHorizontal,
                                vertical = Dimensions.messageBubblePaddingVertical,
                            ),
                    )
                }
            }

            // Analytics footer (for assistant messages) - matching iOS
            if (message.role == MessageRole.ASSISTANT && message.analytics != null) {
                Spacer(modifier = Modifier.height(Dimensions.small))
                AnalyticsFooter(
                    analytics = message.analytics,
                    hasThinking = message.thinkingContent != null,
                )
            }

            // Timestamp (for user messages) - matching iOS
            if (message.role == MessageRole.USER) {
                Spacer(modifier = Modifier.height(Dimensions.small))
                Text(
                    text = formatTimestamp(message.timestamp),
                    style = AppTypography.caption2,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.align(Alignment.End),
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

// ====================
// THINKING SECTION
// ====================

/**
 * Extract intelligent thinking summary - matching iOS thinkingSummary computed property
 * Extracts first meaningful sentence from thinking content instead of showing raw text
 */
private fun extractThinkingSummary(thinking: String): String {
    val trimmed = thinking.trim()
    if (trimmed.isEmpty()) return "Show reasoning..."

    // Extract first meaningful sentence
    val sentences =
        trimmed.split(Regex("[.!?]"))
            .map { it.trim() }
            .filter { it.length > 20 }

    // If we have at least 2 sentences and first is meaningful, use it
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
 * Thinking Progress Indicator - matching iOS pattern
 * Shows "Thinking..." with animated dots when message is empty but thinking content exists
 */
@Composable
fun ThinkingProgressIndicator() {
    val thinkingShape = RoundedCornerShape(Dimensions.thinkingSectionCornerRadius)

    Box(
        modifier =
            Modifier
                .clip(thinkingShape)
                .background(brush = AppColors.thinkingProgressGradient())
                .border(
                    width = Dimensions.strokeThin,
                    color = AppColors.thinkingBorder,
                    shape = thinkingShape,
                )
                .padding(
                    horizontal = Dimensions.thinkingSectionPaddingHorizontal,
                    vertical = Dimensions.thinkingSectionPaddingVertical,
                ),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(Dimensions.xSmall),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Animated dots (matching iOS)
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
    @Suppress("UNUSED_PARAMETER") isGenerating: Boolean,
) {
    var isExpanded by remember { mutableStateOf(false) }

    // Extract intelligent summary like iOS
    val thinkingSummary =
        remember(thinkingContent) {
            extractThinkingSummary(thinkingContent)
        }

    Column {
        // Toggle button with gradient background matching iOS
        val toggleShape = RoundedCornerShape(Dimensions.thinkingSectionCornerRadius)

        Box(
            modifier =
                Modifier
                    .clickable { isExpanded = !isExpanded }
                    .shadow(
                        elevation = Dimensions.shadowSmall,
                        shape = toggleShape,
                        ambientColor = AppColors.shadowThinking,
                        spotColor = AppColors.shadowThinking,
                    )
                    .clip(toggleShape)
                    .background(brush = AppColors.thinkingBackgroundGradient())
                    .border(
                        width = Dimensions.strokeThin,
                        color = AppColors.thinkingBorder,
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

@Composable
fun AnalyticsFooter(
    analytics: com.runanywhere.runanywhereai.domain.models.MessageAnalytics,
    hasThinking: Boolean,
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Timestamp
        Text(
            text = formatTimestamp(analytics.timestamp),
            style = AppTypography.caption2,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        // Separator
        Text(
            text = "•",
            style = AppTypography.caption2,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
        )

        // Duration
        analytics.timeToFirstToken?.let { ttft ->
            Text(
                text = "${ttft / 1000f}s",
                style = AppTypography.caption2,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = "•",
                style = AppTypography.caption2,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )
        }

        // Tokens per second
        Text(
            text = String.format("%.1f tok/s", analytics.averageTokensPerSecond),
            style = AppTypography.caption2,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        // Thinking indicator
        if (hasThinking) {
            Text(
                text = "•",
                style = AppTypography.caption2,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )
            Icon(
                imageVector = Icons.Default.Lightbulb,
                contentDescription = null,
                modifier = Modifier.size(AppTypography.caption2.fontSize.value.dp),
                tint = MaterialTheme.colorScheme.secondary,
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
        horizontalArrangement = Arrangement.Start,
    ) {
        Surface(
            color = MaterialTheme.colorScheme.surfaceVariant,
            shape = RoundedCornerShape(Dimensions.typingIndicatorCornerRadius),
            modifier =
                Modifier
                    .shadow(
                        elevation = Dimensions.shadowMedium,
                        shape = RoundedCornerShape(Dimensions.typingIndicatorCornerRadius),
                    )
                    .border(
                        width = Dimensions.strokeThin,
                        color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.3f),
                        shape = RoundedCornerShape(Dimensions.typingIndicatorCornerRadius),
                    ),
        ) {
            Row(
                modifier =
                    Modifier.padding(
                        horizontal = Dimensions.typingIndicatorPaddingHorizontal,
                        vertical = Dimensions.typingIndicatorPaddingVertical,
                    ),
                horizontalArrangement = Arrangement.spacedBy(Dimensions.typingIndicatorDotSpacing),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // Animated dots
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
                                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.7f),
                                    shape = CircleShape,
                                ),
                    )
                }

                Spacer(modifier = Modifier.width(Dimensions.typingIndicatorTextSpacing))

                // "AI is thinking..." text
                Text(
                    text = "AI is thinking...",
                    style = AppTypography.caption,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.8f),
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
    @Suppress("UNUSED_PARAMETER") modelName: String?,
) {
    Column(
        modifier =
            Modifier
                .fillMaxSize()
                .padding(Dimensions.huge),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        // Icon
        Icon(
            imageVector = if (isModelLoaded) Icons.Default.Chat else Icons.Default.Download,
            contentDescription = null,
            modifier = Modifier.size(Dimensions.emptyStateIconSize),
            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
        )

        Spacer(modifier = Modifier.height(Dimensions.emptyStateIconTextSpacing))

        // Title
        Text(
            text = "Start a conversation",
            style = MaterialTheme.typography.titleMedium,
            color = MaterialTheme.colorScheme.onSurface,
        )

        Spacer(modifier = Modifier.height(Dimensions.emptyStateTitleSubtitleSpacing))

        // Subtitle
        Text(
            text =
                if (isModelLoaded) {
                    "Type a message below to get started"
                } else {
                    "Select a model first, then start chatting"
                },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

// ====================
// MODEL SELECTION PROMPT
// ====================

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

@Composable
fun ChatInputView(
    value: String,
    onValueChange: (String) -> Unit,
    onSend: () -> Unit,
    @Suppress("UNUSED_PARAMETER") enabled: Boolean,
    isGenerating: Boolean,
    isModelLoaded: Boolean,
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface,
        shadowElevation = 8.dp,
    ) {
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(Dimensions.inputAreaPadding),
            horizontalArrangement = Arrangement.spacedBy(Dimensions.inputFieldButtonSpacing),
            verticalAlignment = Alignment.Bottom,
        ) {
            // Text field
            TextField(
                value = value,
                onValueChange = onValueChange,
                modifier = Modifier.weight(1f),
                placeholder = {
                    Text(
                        text =
                            when {
                                !isModelLoaded -> "Load a model first..."
                                isGenerating -> "Generating..."
                                else -> "Type a message..."
                            },
                        style = MaterialTheme.typography.bodyLarge,
                    )
                },
                enabled = isModelLoaded && !isGenerating,
                textStyle = MaterialTheme.typography.bodyLarge,
                colors =
                    TextFieldDefaults.colors(
                        focusedContainerColor = Color.Transparent,
                        unfocusedContainerColor = Color.Transparent,
                        disabledContainerColor = Color.Transparent,
                        focusedIndicatorColor = Color.Transparent,
                        unfocusedIndicatorColor = Color.Transparent,
                        disabledIndicatorColor = Color.Transparent,
                    ),
                maxLines = 4,
            )

            // Send button
            val canSendMessage = isModelLoaded && !isGenerating && value.trim().isNotBlank()
            IconButton(
                onClick = onSend,
                enabled = canSendMessage,
                modifier = Modifier.size(Dimensions.sendButtonSize),
            ) {
                Icon(
                    imageVector = Icons.Default.ArrowUpward,
                    contentDescription = "Send",
                    tint = Color.White,
                    modifier =
                        Modifier
                            .size(Dimensions.sendButtonSize)
                            .clip(CircleShape)
                            .background(
                                if (canSendMessage) {
                                    MaterialTheme.colorScheme.primary
                                } else {
                                    MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                                },
                            )
                            .padding(6.dp),
                )
            }
        }
    }
}

// ====================
// CONVERSATION LIST SHEET
// Matching iOS ConversationListView
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
// Matching iOS ChatDetailsView
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
            // Header
            Row(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onDismiss) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Close",
                    )
                }

                Text(
                    text = "Chat Details",
                    style = MaterialTheme.typography.titleMedium,
                )

                Spacer(modifier = Modifier.width(48.dp)) // Balance the back button
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
