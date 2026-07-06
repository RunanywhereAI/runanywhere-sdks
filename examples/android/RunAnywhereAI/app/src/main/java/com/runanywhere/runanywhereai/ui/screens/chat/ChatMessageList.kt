package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme

@Composable
fun ChatMessageList(
    messages: List<ChatMessage>,
    listState: LazyListState,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current

    if (messages.isEmpty()) {
        Box(modifier = modifier, contentAlignment = Alignment.Center) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
            ) {
                Icon(
                    imageVector = RACIcons.Outline.Robot,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                )
                Text(
                    text = "Start a conversation",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        return
    }

    LazyColumn(
        modifier = modifier,
        state = listState,
        contentPadding = PaddingValues(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        items(messages) { message ->
            if (message.isUser) UserBubble(message) else AssistantMessage(message)
        }
    }
}

@Composable
private fun UserBubble(message: ChatMessage) {
    val dimens = LocalDimens.current
    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
        Box(
            modifier = Modifier
                .widthIn(max = 320.dp)
                .clip(RoundedCornerShape(dimens.radiusMd))
                .background(MaterialTheme.colorScheme.primary)
                .padding(horizontal = dimens.spacingMd, vertical = dimens.spacingSm),
            contentAlignment = Alignment.CenterStart
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
                message.attachment?.let { AttachmentCard(it) }
                Text(
                    text = message.text,
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onPrimary,
                )
            }
        }
    }
}

@Composable
private fun AttachmentCard(attachment: ChatAttachment) {
    val dimens = LocalDimens.current
    Surface(
        shape = RoundedCornerShape(dimens.radiusSm),
        color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.14f),
        contentColor = MaterialTheme.colorScheme.onPrimary,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = dimens.spacingSm, vertical = dimens.spacingXs),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Icon(
                imageVector = when (attachment.kind) {
                    ChatAttachmentKind.IMAGE -> RACIcons.Outline.Eye
                    ChatAttachmentKind.DOCUMENT -> RACIcons.Outline.FileText
                },
                contentDescription = null,
                modifier = Modifier.size(dimens.iconSm),
            )
            Column {
                Text(
                    text = attachment.name,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                attachment.detail?.let {
                    Text(
                        text = it,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.82f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

@Composable
private fun AssistantMessage(message: ChatMessage) {
    val dimens = LocalDimens.current
    var showToolSheet by remember { mutableStateOf(false) }
    val isWaiting = message.text.isEmpty() && message.thinking == null && message.tool == null && message.stats == null
    val hasBubble = message.text.isNotEmpty() || message.tool != null || isWaiting

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
    ) {
        message.thinking?.let {
            ThinkingSection(thinking = it, inProgress = message.text.isEmpty() && message.stats == null)
        }

        if (hasBubble) {
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(dimens.radiusMd))
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                    .padding(horizontal = dimens.spacingMd, vertical = dimens.spacingSm),
            ) {
                Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
                    message.tool?.let { tool ->
                        ToolCallChip(tool = tool, onClick = { showToolSheet = true })
                    }
                    when {
                        isWaiting -> TypingDots()
                        message.text.isNotEmpty() -> MarkdownText(
                            markdown = message.text,
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                    if (message.sources.isNotEmpty()) {
                        SourceStrip(sources = message.sources)
                    }
                }
            }
        }

        message.stats?.let { AnalyticsFooter(stats = it, modifier = Modifier.padding(start = dimens.spacingXs)) }
    }

    if (showToolSheet) {
        message.tool?.let { ToolCallDetailSheet(tool = it, onDismiss = { showToolSheet = false }) }
    }
}

@Composable
private fun SourceStrip(sources: List<ChatSource>) {
    val dimens = LocalDimens.current
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
        Text(
            text = "Sources",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = FontWeight.SemiBold,
        )
        sources.take(3).forEach { source ->
            Surface(
                shape = RoundedCornerShape(dimens.radiusSm),
                color = MaterialTheme.colorScheme.surfaceContainerHighest,
                contentColor = MaterialTheme.colorScheme.onSurface,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = dimens.spacingSm, vertical = dimens.spacingXs),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                ) {
                    Icon(
                        imageVector = RACIcons.Outline.FileText,
                        contentDescription = null,
                        modifier = Modifier.size(dimens.iconSm),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                    Column {
                        Text(
                            text = source.document.ifBlank { "Document" },
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = source.text,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TypingDots() {
    val transition = rememberInfiniteTransition(label = "typing")
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        repeat(3) { index ->
            val alpha by transition.animateFloat(
                initialValue = 0.3f,
                targetValue = 1f,
                animationSpec = infiniteRepeatable(
                    animation = tween(durationMillis = 600, delayMillis = index * 150),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "dot$index",
            )
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = alpha)),
            )
        }
    }
}

private val previewMessages = listOf(
    ChatMessage(
        text = "What is this image showing?",
        isUser = true,
        attachment = ChatAttachment(ChatAttachmentKind.IMAGE, "demo-photo.jpg", "Image model: Qwen VL"),
    ),
    ChatMessage(
        text = "Here's a quick rundown.\n\n" +
            "## Markdown\n" +
            "It renders **bold**, *italic*, and `inline code`.\n\n" +
            "- First point\n" +
            "- Second point\n\n" +
            "```kotlin\nfun greet(name: String) = \"Hello, \$name\"\n```\n\n" +
            "> And the occasional blockquote.",
        isUser = false,
        thinking = "Two asks: weather (a tool) and a markdown demo. I'll show markdown features compactly.",
        stats = GenerationStats(tokens = 142, tokensPerSecond = 38.5, timeToFirstTokenMs = 120, totalTimeMs = 3700),
    ),
    ChatMessage(
        text = "It's currently **18°C** and partly cloudy in Tokyo, Japan.",
        isUser = false,
        tool = ToolCallInfo(
            name = "get_weather",
            arguments = "{\n  \"location\": \"Tokyo\"\n}",
            result = "{\n  \"temperature\": \"18°C\",\n  \"conditions\": \"Partly cloudy\"\n}",
            success = true,
            error = null,
        ),
        stats = GenerationStats(tokens = 24, tokensPerSecond = 41.2, timeToFirstTokenMs = 95, totalTimeMs = 600),
    ),
    ChatMessage(text = "", isUser = false),
)

@Composable
private fun ChatMessageListPreview(darkTheme: Boolean) {
    RunAnywhereAITheme(darkTheme = darkTheme) {
        Surface(color = MaterialTheme.colorScheme.background) {
            ChatMessageList(
                messages = previewMessages,
                listState = rememberLazyListState(),
                modifier = Modifier.fillMaxSize(),
            )
        }
    }
}

@Preview(name = "Chat – light", showBackground = true, heightDp = 760)
@Composable
private fun ChatMessageListLightPreview() = ChatMessageListPreview(darkTheme = false)

@Preview(name = "Chat – dark", showBackground = true, heightDp = 760)
@Composable
private fun ChatMessageListDarkPreview() = ChatMessageListPreview(darkTheme = true)
