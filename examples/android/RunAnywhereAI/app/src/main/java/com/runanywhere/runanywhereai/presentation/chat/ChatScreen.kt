package com.runanywhere.runanywhereai.presentation.chat

import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.domain.model.ChatMessage
import com.runanywhere.runanywhereai.domain.model.MessageRole
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppSpacing
import kotlinx.coroutines.launch

/**
 * iOS-matching ChatScreen with full feature parity
 * - Streaming generation with real-time updates
 * - Analytics display (tokens/sec, TTFT, total tokens)
 * - Thinking content (collapsible)
 * - Message bubbles matching iOS design
 * - Proper scrolling behavior
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    viewModel: ChatViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    // Auto-scroll to bottom when new messages arrive
    LaunchedEffect(uiState.messages.size) {
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
                    Column {
                        Text("Chat")
                        uiState.loadedModelName?.let { modelName ->
                            Text(
                                text = modelName,
                                style = MaterialTheme.typography.labelSmall,
                                color = AppColors.textSecondary
                            )
                        }
                    }
                },
                actions = {
                    // Stop generation button (only show when generating)
                    if (uiState.isGenerating) {
                        IconButton(onClick = viewModel::stopGeneration) {
                            Icon(
                                Icons.Default.Stop,
                                contentDescription = "Stop Generation",
                                tint = AppColors.primaryRed
                            )
                        }
                    }

                    // New conversation button
                    IconButton(onClick = viewModel::clearChat) {
                        Icon(Icons.Default.Edit, contentDescription = "New Chat")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = AppColors.backgroundPrimary
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            // Messages list
            if (uiState.messages.isEmpty() && !uiState.isGenerating) {
                EmptyChatState(
                    isModelLoaded = uiState.isModelLoaded,
                    modelName = uiState.loadedModelName
                )
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.weight(1f),
                    contentPadding = PaddingValues(AppSpacing.large)
                ) {
                    items(uiState.messages, key = { it.id }) { message ->
                        AnimatedMessageBubble(message = message)
                        Spacer(modifier = Modifier.height(AppSpacing.medium))
                    }

                    // Typing indicator
                    if (uiState.isGenerating && uiState.messages.lastOrNull()?.content?.isEmpty() == true) {
                        item {
                            TypingIndicator()
                        }
                    }
                }
            }

            // Error message
            uiState.error?.let { error ->
                Surface(
                    modifier = Modifier.fillMaxWidth(),
                    color = AppColors.primaryRed.copy(alpha = 0.1f)
                ) {
                    Row(
                        modifier = Modifier.padding(AppSpacing.medium),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text(
                            text = error.message ?: "An error occurred",
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.primaryRed,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(onClick = viewModel::clearError) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Dismiss",
                                tint = AppColors.primaryRed
                            )
                        }
                    }
                }
            }

            // Input field
            ChatInputField(
                value = uiState.currentInput,
                onValueChange = viewModel::updateInput,
                onSend = viewModel::sendMessage,
                enabled = uiState.canSend,
                isGenerating = uiState.isGenerating,
                isModelLoaded = uiState.isModelLoaded
            )
        }
    }
}

@Composable
fun AnimatedMessageBubble(message: ChatMessage) {
    var visible by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        visible = true
    }

    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(animationSpec = tween(AppSpacing.animationNormal)) +
                slideInVertically(
                    animationSpec = tween(AppSpacing.animationNormal),
                    initialOffsetY = { it / 4 }
                )
    ) {
        MessageBubble(message = message)
    }
}

@Composable
fun MessageBubble(message: ChatMessage) {
    val alignment = if (message.role == MessageRole.USER) {
        Arrangement.End
    } else {
        Arrangement.Start
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = alignment
    ) {
        Card(
            modifier = Modifier.widthIn(max = AppSpacing.messageBubbleMaxWidth),
            colors = CardDefaults.cardColors(
                containerColor = when (message.role) {
                    MessageRole.USER -> AppColors.messageBubbleUser
                    MessageRole.ASSISTANT -> AppColors.messageBubbleAssistant
                    else -> AppColors.backgroundSecondary
                }
            ),
            shape = RoundedCornerShape(AppSpacing.cornerRadiusLarge)
        ) {
            Column(
                modifier = Modifier.padding(AppSpacing.medium)
            ) {
                // Thinking content (collapsible)
                message.thinkingContent?.let { thinking ->
                    ThinkingSection(thinkingContent = thinking)
                    Spacer(modifier = Modifier.height(AppSpacing.small))
                }

                // Message text
                if (message.content.isNotEmpty()) {
                    Text(
                        text = message.content,
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (message.role == MessageRole.USER) {
                            Color.White
                        } else {
                            AppColors.textPrimary
                        }
                    )
                }

                // Analytics row (for assistant messages)
                message.analytics?.let { analytics ->
                    Spacer(modifier = Modifier.height(AppSpacing.small))
                    AnalyticsRow(analytics = analytics)
                }
            }
        }
    }
}

@Composable
fun ThinkingSection(thinkingContent: String) {
    var isExpanded by remember { mutableStateOf(false) }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = AppColors.thinkingBackground
        ),
        shape = RoundedCornerShape(AppSpacing.cornerRadiusSmall)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { isExpanded = !isExpanded }
                .padding(AppSpacing.small)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    imageVector = Icons.Default.Psychology,
                    contentDescription = "Thinking",
                    tint = AppColors.primaryBlue,
                    modifier = Modifier.size(AppSpacing.iconSizeSmall)
                )
                Spacer(modifier = Modifier.width(AppSpacing.xSmall))
                Text(
                    text = "Thinking",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = AppColors.primaryBlue
                )
                Spacer(modifier = Modifier.weight(1f))
                Icon(
                    imageVector = if (isExpanded) {
                        Icons.Default.ExpandLess
                    } else {
                        Icons.Default.ExpandMore
                    },
                    contentDescription = if (isExpanded) "Collapse" else "Expand",
                    tint = AppColors.primaryBlue
                )
            }

            AnimatedVisibility(visible = isExpanded) {
                Text(
                    text = thinkingContent,
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                    modifier = Modifier.padding(top = AppSpacing.small)
                )
            }
        }
    }
}

@Composable
fun AnalyticsRow(analytics: com.runanywhere.runanywhereai.domain.model.MessageAnalytics) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(AppSpacing.medium)
    ) {
        // Tokens per second
        Text(
            text = String.format("%.1f tok/s", analytics.averageTokensPerSecond),
            style = MaterialTheme.typography.labelSmall,
            color = AppColors.textSecondary
        )

        // Time to first token
        analytics.timeToFirstToken?.let { ttft ->
            Text(
                text = "TTFT: ${ttft}ms",
                style = MaterialTheme.typography.labelSmall,
                color = AppColors.textSecondary
            )
        }

        // Total tokens
        Text(
            text = "${analytics.outputTokens} tokens",
            style = MaterialTheme.typography.labelSmall,
            color = AppColors.textSecondary
        )
    }
}

@Composable
fun ChatInputField(
    value: String,
    onValueChange: (String) -> Unit,
    onSend: () -> Unit,
    enabled: Boolean,
    isGenerating: Boolean,
    isModelLoaded: Boolean
) {
    Surface(
        shadowElevation = 8.dp,
        color = AppColors.backgroundPrimary
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(AppSpacing.large),
            verticalAlignment = Alignment.CenterVertically
        ) {
            OutlinedTextField(
                value = value,
                onValueChange = onValueChange,
                modifier = Modifier.weight(1f),
                placeholder = {
                    Text(
                        when {
                            !isModelLoaded -> "Load a model first..."
                            isGenerating -> "Generating..."
                            else -> "Message..."
                        }
                    )
                },
                enabled = enabled && !isGenerating,
                shape = RoundedCornerShape(AppSpacing.cornerRadiusXLarge),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Sentences,
                    imeAction = ImeAction.Send
                ),
                keyboardActions = KeyboardActions(
                    onSend = { if (value.isNotBlank() && enabled) onSend() }
                ),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = AppColors.primaryBlue,
                    unfocusedBorderColor = AppColors.divider
                )
            )

            Spacer(modifier = Modifier.width(AppSpacing.small))

            IconButton(
                onClick = onSend,
                enabled = enabled && value.isNotBlank() && !isGenerating
            ) {
                Icon(
                    imageVector = Icons.Default.Send,
                    contentDescription = "Send",
                    tint = if (enabled && value.isNotBlank() && !isGenerating) {
                        AppColors.primaryBlue
                    } else {
                        AppColors.textTertiary
                    }
                )
            }
        }
    }
}

@Composable
fun TypingIndicator() {
    Row(
        horizontalArrangement = Arrangement.spacedBy(AppSpacing.xSmall)
    ) {
        repeat(3) { index ->
            val infiniteTransition = rememberInfiniteTransition(label = "typing")
            val alpha by infiniteTransition.animateFloat(
                initialValue = 0.3f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = tween(600),
                    repeatMode = RepeatMode.Reverse,
                    initialStartOffset = StartOffset(index * 200)
                ),
                label = "dot_${index}"
            )

            Box(
                modifier = Modifier
                    .size(8.dp)
                    .alpha(alpha)
                    .background(
                        color = AppColors.textSecondary,
                        shape = CircleShape
                    )
            )
        }
    }
}

@Composable
fun EmptyChatState(
    isModelLoaded: Boolean,
    modelName: String?
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(AppSpacing.huge),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = if (isModelLoaded) Icons.Default.Chat else Icons.Default.Download,
            contentDescription = null,
            modifier = Modifier.size(64.dp),
            tint = AppColors.textTertiary
        )

        Spacer(modifier = Modifier.height(AppSpacing.large))

        if (isModelLoaded) {
            Text(
                text = "Start a conversation",
                style = MaterialTheme.typography.titleMedium,
                color = AppColors.textSecondary
            )

            modelName?.let {
                Spacer(modifier = Modifier.height(AppSpacing.small))
                Text(
                    text = "Using $it",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textTertiary,
                    textAlign = TextAlign.Center
                )
            }
        } else {
            Text(
                text = "No model loaded",
                style = MaterialTheme.typography.titleMedium,
                color = AppColors.textSecondary
            )

            Spacer(modifier = Modifier.height(AppSpacing.small))

            Text(
                text = "Go to Models tab to download and load a model",
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textTertiary,
                textAlign = TextAlign.Center
            )
        }
    }
}
