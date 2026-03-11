package com.runanywhere.runanywhereai.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.models.ChatMessage
import com.runanywhere.runanywhereai.models.MessageRole
import kotlinx.collections.immutable.ImmutableList

@Composable
fun ChatMessageList(
    messages: ImmutableList<ChatMessage>,
    listState: LazyListState,
    modifier: Modifier = Modifier,
) {
    val maxBubbleWidth = (LocalConfiguration.current.screenWidthDp * 0.8f).dp

    LazyColumn(
        modifier = modifier,
        state = listState,
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(
            items = messages,
            key = { it.id },
            contentType = { it.role },
        ) { message ->
            when (message.role) {
                MessageRole.USER -> UserMessageBubble(
                    message = message,
                    maxWidth = maxBubbleWidth,
                )

                MessageRole.ASSISTANT -> AssistantMessageBubble(
                    message = message,
                    maxWidth = maxBubbleWidth,
                )

                MessageRole.SYSTEM -> SystemMessageRow(message = message)
            }
        }
    }
}

@Composable
private fun UserMessageBubble(
    message: ChatMessage,
    maxWidth: androidx.compose.ui.unit.Dp,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.End,
    ) {
        Surface(
            modifier = Modifier.widthIn(max = maxWidth),
            shape = RoundedCornerShape(16.dp, 4.dp, 16.dp, 16.dp),
            color = MaterialTheme.colorScheme.primaryContainer,
        ) {
            Text(
                text = message.content,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onPrimaryContainer,
                modifier = Modifier.padding(12.dp),
            )
        }
    }
}

@Composable
private fun AssistantMessageBubble(
    message: ChatMessage,
    maxWidth: androidx.compose.ui.unit.Dp,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start,
    ) {
        Column(modifier = Modifier.widthIn(max = maxWidth)) {
            // Thinking content (expandable)
            if (!message.thinkingContent.isNullOrBlank()) {
                ThinkingSection(thinkingContent = message.thinkingContent)
                Spacer(modifier = Modifier.height(4.dp))
            }

            // Main content — no card, clean like ChatGPT
            Column(modifier = Modifier.padding(horizontal = 4.dp)) {
                MarkdownText(
                    text = message.content,
                    style = MaterialTheme.typography.bodyLarge,
                )

                // Analytics badge
                val tokensPerSecond = message.analytics?.averageTokensPerSecond
                if (tokensPerSecond != null && tokensPerSecond > 0) {
                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = "%.1f tokens/s".format(tokensPerSecond),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    )
                }
            }
        }
    }
}

@Composable
private fun ThinkingSection(thinkingContent: String) {
    var expanded by rememberSaveable { mutableStateOf(false) }

    Surface(
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
    ) {
        Column(modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) {
            TextButton(onClick = { expanded = !expanded }) {
                Text(
                    text = if (expanded) "Thinking... (hide)" else "Thinking... (show)",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            AnimatedVisibility(
                visible = expanded,
                enter = expandVertically(),
                exit = shrinkVertically(),
            ) {
                Text(
                    text = thinkingContent,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                    modifier = Modifier.padding(bottom = 8.dp),
                )
            }
        }
    }
}

@Composable
private fun SystemMessageRow(message: ChatMessage) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
    ) {
        Text(
            text = message.content,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
            modifier = Modifier.padding(vertical = 4.dp),
        )
    }
}
