package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

data class ComposerAttachment(
    val name: String,
    val description: String,
    val icon: ImageVector,
)

private data class AttachmentAction(
    val label: String,
    val description: String,
    val icon: ImageVector,
    val onClick: () -> Unit,
)

@Composable
fun ChatInputBar(
    input: String,
    onInputChange: (String) -> Unit,
    onSend: () -> Unit,
    canSend: Boolean,
    isGenerating: Boolean,
    isStopping: Boolean,
    onStop: () -> Unit,
    toolsEnabled: Boolean,
    toolsUnavailableMessage: String?,
    onToggleTools: () -> Unit,
    onAttachDocument: () -> Unit,
    onAttachImage: () -> Unit,
    onOpenLive: () -> Unit,
    onOpenTalk: () -> Unit,
    onOpenAdvanced: () -> Unit,
    modifier: Modifier = Modifier,
    pendingAttachment: ComposerAttachment? = null,
    onClearAttachment: () -> Unit = {},
) {
    val dimens = LocalDimens.current
    var menuExpanded by remember { mutableStateOf(false) }
    val actions = listOf(
        AttachmentAction("Document", "Ask questions with sources", RACIcons.Outline.FileText, onAttachDocument),
        AttachmentAction("Image", "Ask about a photo", RACIcons.Outline.Eye, onAttachImage),
        AttachmentAction("Live camera", "Look around with vision", RACIcons.Outline.DeviceMobile, onOpenLive),
        AttachmentAction("Advanced tools", "SDK demos and diagnostics", RACIcons.Outline.Stack, onOpenAdvanced),
    )

    Column(
        modifier = modifier.background(MaterialTheme.colorScheme.surface),
    ) {
        HorizontalDivider(
            thickness = 0.5.dp,
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
        )
        AnimatedVisibility(
            visible = pendingAttachment != null,
            enter = fadeIn() + expandVertically(),
            exit = fadeOut() + shrinkVertically(),
        ) {
            pendingAttachment?.let {
                AttachmentStatusPill(
                    attachment = it,
                    onClear = onClearAttachment,
                    modifier = Modifier.padding(
                        start = dimens.spacingMd,
                        top = dimens.spacingSm,
                        end = dimens.spacingMd,
                    ),
                )
            }
        }
        AnimatedVisibility(
            visible = toolsEnabled || toolsUnavailableMessage != null,
            enter = fadeIn() + expandVertically(),
            exit = fadeOut() + shrinkVertically(),
        ) {
            ToolStatusPill(
                unavailableMessage = toolsUnavailableMessage,
                modifier = Modifier.padding(
                    start = dimens.spacingMd,
                    top = dimens.spacingSm,
                    end = dimens.spacingMd,
                ),
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = dimens.spacingMd, vertical = dimens.spacingSm),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Box {
                IconButton(
                    onClick = { menuExpanded = true },
                    modifier = Modifier.size(dimens.inputBarMinHeight),
                    colors = IconButtonDefaults.iconButtonColors(
                        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    ),
                ) {
                    Icon(
                        imageVector = RACIcons.Outline.Plus,
                        contentDescription = "Attach or open a mode",
                        modifier = Modifier.size(dimens.iconMd),
                    )
                }
                DropdownMenu(
                    expanded = menuExpanded,
                    onDismissRequest = { menuExpanded = false },
                ) {
                    actions.forEach { action ->
                        DropdownMenuItem(
                            text = {
                                Column {
                                    Text(action.label, fontWeight = FontWeight.SemiBold)
                                    Text(
                                        action.description,
                                        style = MaterialTheme.typography.labelSmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            },
                            leadingIcon = {
                                Icon(action.icon, contentDescription = null)
                            },
                            onClick = {
                                menuExpanded = false
                                action.onClick()
                            },
                        )
                    }
                }
            }

            IconButton(
                onClick = onToggleTools,
                modifier = Modifier.size(dimens.inputBarMinHeight),
                colors = IconButtonDefaults.iconButtonColors(
                    containerColor = if (toolsEnabled) {
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                    } else {
                        MaterialTheme.colorScheme.surfaceContainerHigh
                    },
                    contentColor = if (toolsEnabled) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                ),
            ) {
                Icon(
                    imageVector = RACIcons.Outline.Cloud,
                    contentDescription = when {
                        toolsEnabled -> "Disable web and tools"
                        toolsUnavailableMessage != null -> "Web and tools unavailable for current model"
                        else -> "Enable web and tools"
                    },
                    modifier = Modifier.size(dimens.iconMd),
                )
            }

            Box(
                modifier = Modifier
                    .weight(1f)
                    .clip(RoundedCornerShape(dimens.radiusLg))
                    .background(MaterialTheme.colorScheme.surfaceContainerHigh)
                    .heightIn(min = dimens.inputBarMinHeight)
                    .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
                contentAlignment = Alignment.CenterStart,
            ) {
                if (input.isEmpty()) {
                    Text(
                        text = if (toolsEnabled) "Ask with web and tools..." else "Ask anything...",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                    )
                }
                BasicTextField(
                    value = input,
                    onValueChange = onInputChange,
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = "Message input" },
                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                        color = MaterialTheme.colorScheme.onSurface,
                    ),
                    cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    maxLines = 5,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences,
                        imeAction = ImeAction.Default,
                    ),
                )
            }

            IconButton(
                onClick = onOpenTalk,
                modifier = Modifier.size(dimens.inputBarMinHeight),
                colors = IconButtonDefaults.iconButtonColors(
                    containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                    contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
                ),
            ) {
                Icon(
                    imageVector = RACIcons.Outline.Microphone,
                    contentDescription = "Talk mode",
                    modifier = Modifier.size(dimens.iconMd),
                )
            }

            val haptics = androidx.compose.ui.platform.LocalHapticFeedback.current
            IconButton(
                onClick = {
                    haptics.performHapticFeedback(androidx.compose.ui.hapticfeedback.HapticFeedbackType.LongPress)
                    if (isGenerating) onStop() else onSend()
                },
                enabled = isGenerating || canSend,
                modifier = Modifier.size(dimens.inputBarMinHeight),
                colors = IconButtonDefaults.iconButtonColors(
                    containerColor = MaterialTheme.colorScheme.primary,
                    contentColor = MaterialTheme.colorScheme.onPrimary,
                    disabledContainerColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f),
                ),
            ) {
                Icon(
                    imageVector = if (isGenerating) RACIcons.Outline.PlayerStop else RACIcons.Outline.Send,
                    contentDescription = if (isGenerating) "Stop" else "Send message",
                    modifier = Modifier.size(dimens.iconMd),
                )
            }
        }
        AnimatedVisibility(
            visible = isStopping,
            enter = fadeIn() + expandVertically(),
            exit = fadeOut() + shrinkVertically(),
        ) {
            StoppingStatusPill(
                modifier = Modifier.padding(
                    start = dimens.spacingMd,
                    top = dimens.spacingSm,
                    end = dimens.spacingMd,
                ),
            )
        }
    }
}

@Composable
private fun StoppingStatusPill(modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(dimens.radiusFull),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = MaterialTheme.colorScheme.onSurfaceVariant,
    ) {
        Text(
            text = "Stopping the previous response… You can keep typing.",
            style = MaterialTheme.typography.labelMedium,
            modifier = Modifier.padding(horizontal = dimens.spacingMd, vertical = dimens.spacingXs),
        )
    }
}

@Composable
private fun AttachmentStatusPill(
    attachment: ComposerAttachment,
    onClear: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(dimens.radiusLg),
        color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.75f),
        contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
    ) {
        Row(
            modifier = Modifier.padding(
                start = dimens.spacingMd,
                end = dimens.spacingXs,
                top = dimens.spacingXs,
                bottom = dimens.spacingXs,
            ),
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(attachment.icon, contentDescription = null, modifier = Modifier.size(dimens.iconSm))
            Column(modifier = Modifier.weight(1f, fill = false)) {
                Text(
                    attachment.name,
                    style = MaterialTheme.typography.labelLarge,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    attachment.description,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            IconButton(onClick = onClear, modifier = Modifier.size(32.dp)) {
                Icon(RACIcons.Outline.Close, contentDescription = "Remove attachment", modifier = Modifier.size(dimens.iconSm))
            }
        }
    }
}

@Composable
private fun ToolStatusPill(
    unavailableMessage: String?,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    val unavailable = unavailableMessage != null
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(if (unavailable) dimens.radiusLg else dimens.radiusFull),
        color = if (unavailable) {
            MaterialTheme.colorScheme.errorContainer
        } else {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
        },
        contentColor = if (unavailable) {
            MaterialTheme.colorScheme.onErrorContainer
        } else {
            MaterialTheme.colorScheme.primary
        },
    ) {
        Row(
            modifier = Modifier.padding(horizontal = dimens.spacingMd, vertical = dimens.spacingXs),
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = if (unavailable) RACIcons.Outline.AlertTriangle else RACIcons.Outline.Cloud,
                contentDescription = null,
                modifier = Modifier.size(dimens.iconSm),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (unavailable) "Web & tools unavailable" else "Web & tools on",
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = unavailableMessage ?: "Trace appears in replies",
                    style = MaterialTheme.typography.labelSmall,
                    color = if (unavailable) {
                        MaterialTheme.colorScheme.onErrorContainer
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    maxLines = if (unavailable) 2 else 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}
