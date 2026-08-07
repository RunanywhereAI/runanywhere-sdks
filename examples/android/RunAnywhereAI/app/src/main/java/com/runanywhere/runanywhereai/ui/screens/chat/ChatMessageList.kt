package com.runanywhere.runanywhereai.ui.screens.chat

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.BitmapFactory
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme
import java.io.File
import kotlinx.coroutines.delay

/**
 * What a reader can do with one turn, by transcript position.
 *
 * A value of nullable callbacks rather than a [ChatViewModel] reference: the
 * transcript stays a pure function of its messages, so a token landing in the
 * tail cannot invalidate every earlier row. A null callback means the action is
 * withheld — which is how a running generation hides everything that would
 * renumber the list under an in-flight turn. Copy is not here because it mutates
 * nothing and the row owns it outright.
 *
 * Positions, not identities: [ChatMessage] has no id, so the transcript is
 * addressed by index exactly as `ChatViewModel` is.
 */
data class ChatMessageActions(
    val onRegenerate: ((Int) -> Unit)? = null,
    val onEdit: ((Int) -> Unit)? = null,
    val onDelete: ((Int) -> Unit)? = null,
)

@Composable
fun ChatMessageList(
    messages: List<ChatMessage>,
    listState: LazyListState,
    modifier: Modifier = Modifier,
    isGenerating: Boolean = false,
    actions: ChatMessageActions = ChatMessageActions(),
) {
    val dimens = LocalDimens.current

    if (messages.isEmpty()) {
        EmptyChatHero(modifier = modifier)
        return
    }

    // The newest turn shows its actions unprompted — it is the one a reader wants
    // to copy or retry — and any older turn reveals them on tap. Android has no
    // hover to lean on, and a long press on a wall of text is undiscoverable, so
    // tap-to-reveal is the affordance rather than a hidden context menu.
    var revealedIndex by remember { mutableStateOf(-1) }

    LazyColumn(
        modifier = modifier,
        state = listState,
        contentPadding = PaddingValues(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
    ) {
        itemsIndexed(messages) { index, message ->
            val isStreamingTail = isGenerating && index == messages.lastIndex
            Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
                if (message.isUser) {
                    UserBubble(
                        message = message,
                        onToggleActions = {
                            revealedIndex = if (revealedIndex == index) -1 else index
                        },
                    )
                } else {
                    AssistantMessage(
                        message = message,
                        isStreamingTail = isStreamingTail,
                        onToggleActions = {
                            revealedIndex = if (revealedIndex == index) -1 else index
                        },
                    )
                }
                // A turn still receiving tokens has nothing settled to act on: its
                // text is moving and regenerating it would renumber the list the
                // stream is writing into.
                MessageActionRow(
                    message = message,
                    index = index,
                    actions = actions,
                    visible = !isStreamingTail &&
                        (index == messages.lastIndex || revealedIndex == index) &&
                        (message.text.isNotEmpty() || message.attachment != null),
                )
            }
        }
    }
}

/**
 * Copy, plus whichever of retry / edit / delete [actions] offers for this turn.
 *
 * Copy reports itself in place: the clipboard gives no feedback of its own, and
 * a Toast would duplicate the one Android 13+ already shows. The tick reverts
 * after two seconds so the row stops claiming a copy from minutes ago is still
 * what is on the clipboard.
 */
@Composable
private fun MessageActionRow(
    message: ChatMessage,
    index: Int,
    actions: ChatMessageActions,
    visible: Boolean,
) {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    var didCopy by remember { mutableStateOf(false) }

    LaunchedEffect(didCopy) {
        if (didCopy) {
            delay(2_000)
            didCopy = false
        }
    }

    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(AppMotion.tweenShort()),
        exit = fadeOut(AppMotion.tweenExit()),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = if (message.isUser) Arrangement.End else Arrangement.Start,
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
                MessageActionButton(
                    icon = if (didCopy) RACIcons.Outline.Check else RACIcons.Outline.Copy,
                    label = if (didCopy) "Copied" else "Copy",
                ) {
                    val clipboard =
                        context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("Message", message.text))
                    didCopy = true
                }
                if (!message.isUser) {
                    actions.onRegenerate?.let { regenerate ->
                        MessageActionButton(RACIcons.Outline.Refresh, "Regenerate") { regenerate(index) }
                    }
                }
                if (message.isUser) {
                    actions.onEdit?.let { edit ->
                        MessageActionButton(RACIcons.Outline.Pencil, "Edit and resend") { edit(index) }
                    }
                }
                actions.onDelete?.let { delete ->
                    MessageActionButton(
                        icon = RACIcons.Outline.Trash,
                        label = if (message.isUser) "Delete exchange" else "Delete reply",
                    ) { delete(index) }
                }
            }
        }
    }
}

@Composable
private fun MessageActionButton(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit,
) {
    val dimens = LocalDimens.current
    val haptics = LocalHapticFeedback.current
    Box(
        modifier = Modifier
            .size(36.dp)
            .clip(RoundedCornerShape(dimens.radiusSm))
            .clickable(role = Role.Button, onClickLabel = label) {
                haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                onClick()
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconSm),
        )
    }
}

private fun greeting(hour: Int): String = when (hour) {
    in 0..4 -> "Working late?"
    in 5..11 -> "Good morning"
    in 12..17 -> "Good afternoon"
    else -> "Good evening"
}

@Composable
private fun EmptyChatHero(modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    val hour = remember { java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY) }
    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = RACIcons.Outline.Bolt,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(32.dp),
                )
            }
            Text(
                text = greeting(hour),
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "Ask anything — AI runs locally on your device by default.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.widthIn(max = 280.dp),
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

@Composable
private fun UserBubble(message: ChatMessage, onToggleActions: () -> Unit = {}) {
    val dimens = LocalDimens.current
    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
        Box(
            modifier = Modifier
                .widthIn(max = dimens.bubbleMaxWidth)
                .clip(
                    RoundedCornerShape(
                        topStart = dimens.radiusLg,
                        topEnd = dimens.radiusLg,
                        bottomStart = dimens.radiusLg,
                        bottomEnd = dimens.radiusSm,
                    )
                )
                .background(MaterialTheme.colorScheme.primary)
                .clickable(
                    onClickLabel = "Show message actions",
                    onClick = onToggleActions,
                )
                .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
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
    var showPreview by remember { mutableStateOf(false) }
    Surface(
        shape = RoundedCornerShape(dimens.radiusSm),
        color = MaterialTheme.colorScheme.onPrimary.copy(alpha = 0.14f),
        contentColor = MaterialTheme.colorScheme.onPrimary,
    ) {
        Row(
            modifier = Modifier
                .clickable { showPreview = true }
                .padding(horizontal = dimens.spacingSm, vertical = dimens.spacingXs),
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

    if (showPreview) {
        AttachmentPreviewDialog(attachment = attachment, onDismiss = { showPreview = false })
    }
}

@Composable
private fun AttachmentPreviewDialog(attachment: ChatAttachment, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { TextButton(onClick = onDismiss) { Text("Done") } },
        title = { Text(attachment.name, maxLines = 2, overflow = TextOverflow.Ellipsis) },
        text = {
            when (attachment.kind) {
                ChatAttachmentKind.IMAGE -> ImageAttachmentPreview(attachment)
                ChatAttachmentKind.DOCUMENT -> DocumentAttachmentPreview(attachment)
            }
        },
    )
}

@Composable
private fun ImageAttachmentPreview(attachment: ChatAttachment) {
    val bitmap = remember(attachment.localPath) {
        attachment.localPath?.let { path ->
            runCatching { BitmapFactory.decodeFile(path) }.getOrNull()
        }
    }
    if (bitmap != null) {
        Image(
            bitmap = bitmap.asImageBitmap(),
            contentDescription = attachment.name,
            contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxWidth(),
        )
    } else {
        Text(
            text = attachment.localPath ?: "Preview unavailable",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun DocumentAttachmentPreview(attachment: ChatAttachment) {
    val preview = remember(attachment.localPath, attachment.previewText) {
        attachment.previewText ?: attachment.localPath?.let { path ->
            runCatching { File(path).readText().take(4_000) }.getOrNull()
        }
    }
    Text(
        text = preview ?: "No document preview is available.",
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

@Composable
private fun AssistantMessage(
    message: ChatMessage,
    isStreamingTail: Boolean = false,
    onToggleActions: () -> Unit = {},
) {
    val dimens = LocalDimens.current
    var showToolSheet by remember { mutableStateOf(false) }
    val thinkingPresentation = message.thinkingPresentation(isStreamingTail)
    val isWaiting = message.text.isEmpty() &&
        thinkingPresentation == null &&
        message.tool == null &&
        message.stats == null

    // Assistant replies read as a document: full-width, no bubble — the
    // consumer chat idiom shared with the iOS and web examples.
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) {
        thinkingPresentation?.let { presentation ->
            ThinkingSection(thinking = presentation.text, phase = presentation.phase)
        }

        message.tool?.let { tool ->
            ToolCallChip(tool = tool, onClick = { showToolSheet = true })
        }

        when {
            isWaiting -> TypingDots()
            message.text.isNotEmpty() -> MarkdownText(
                markdown = message.text,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                // No indication: a ripple washing across a full-width wall of
                // prose reads as a mis-tap, not as feedback. Links inside the
                // markdown consume their own taps first, so following one never
                // also toggles the action row.
                modifier = Modifier.clickable(
                    interactionSource = null,
                    indication = null,
                    onClickLabel = "Show message actions",
                    onClick = onToggleActions,
                ),
            )
        }

        if (isStreamingTail && message.text.isNotEmpty()) {
            StreamingCursorDot()
        }

        if (message.sources.isNotEmpty()) {
            SourceStrip(sources = message.sources)
        }

        message.stats?.let { AnalyticsFooter(stats = it, modifier = Modifier.padding(start = dimens.spacingXs)) }
    }

    if (showToolSheet) {
        message.tool?.let { ToolCallDetailSheet(tool = it, onDismiss = { showToolSheet = false }) }
    }
}

private data class ThinkingPresentation(
    val text: String,
    val phase: ThinkingPhase,
)

private fun ChatMessage.thinkingPresentation(isStreamingTail: Boolean): ThinkingPresentation? = when {
    isStreamingTail -> ThinkingPresentation(
        text = thinking.orEmpty(),
        phase = ThinkingPhase.ACTIVE,
    )
    !thinking.isNullOrBlank() -> ThinkingPresentation(
        text = thinking,
        phase = ThinkingPhase.COMPLETE,
    )
    else -> null
}

@Composable
private fun StreamingCursorDot() {
    val transition = rememberInfiniteTransition(label = "cursor")
    val alpha by transition.animateFloat(
        initialValue = 1f,
        targetValue = 0.35f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 450),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "cursorAlpha",
    )
    Box(
        modifier = Modifier
            .size(9.dp)
            .clip(CircleShape)
            .background(MaterialTheme.colorScheme.primary.copy(alpha = alpha)),
    )
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
                    .background(MaterialTheme.colorScheme.primary.copy(alpha = alpha)),
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
                actions = ChatMessageActions(
                    onRegenerate = {},
                    onEdit = {},
                    onDelete = {},
                ),
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
