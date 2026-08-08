package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppMotion
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
    input: String = "",
    onInputChange: (String) -> Unit = {},
    onSend: () -> Unit = {},
    canSend: Boolean = false,
    /**
     * Why the composer cannot send, or null when it can. Shown as an actionable
     * strip above the editor rather than left to the reader to infer from a grey
     * button. Null while a turn is in flight — the spinner already says that.
     */
    blockedReason: String? = null,
    /** Takes the user to whatever [blockedReason] is asking for. */
    onResolveBlocked: () -> Unit = {},
    isGenerating: Boolean = false,
    isStopping: Boolean = false,
    onStop: () -> Unit = {},
    toolsEnabled: Boolean = false,
    toolsUnavailableMessage: String?,
    onToggleTools: () -> Unit,
    onAttachDocument: () -> Unit,
    onAttachImage: () -> Unit,
    onOpenLive: () -> Unit,
    onOpenTalk: () -> Unit,
    onOpenAdvanced: () -> Unit,
    onToggleThinking: () -> Unit,
    thinkingEnabled: Boolean,
    thinkingSupported: Boolean,
    modifier: Modifier = Modifier,
    pendingAttachment: ComposerAttachment? = null,
    onClearAttachment: () -> Unit = {},
    /**
     * Why the last file the user chose was not attached, or null. Shown here rather than as a
     * dialog: the user is mid-compose and the remedy is to pick a different file, not to dismiss
     * something. Silently ignoring a rejected file is indistinguishable from the picker being broken.
     */
    attachmentRejection: String? = null,
    onDismissAttachmentRejection: () -> Unit = {},
    compact: Boolean = false,
    /**
     * Lets the caller put the cursor in the editor. Editing a sent question is
     * the case that needs it: the text arrives here from the transcript, and
     * without focus and a keyboard it reads as though the tap did nothing.
     */
    focusRequester: FocusRequester? = null,
) {
    val dimens = LocalDimens.current
    var menuExpanded by remember { mutableStateOf(false) }
    val actions = listOf(
        AttachmentAction(
            "Document",
            "Ask questions with sources",
            RACIcons.Outline.FileText,
            onAttachDocument
        ),
        // A still photo the app will hold, versus a live camera feed it will look through.
        // Both used to be an eye, which made the two rows of this menu near-identical.
        AttachmentAction("Image", "Ask about a photo", RACIcons.Outline.Image, onAttachImage),
        AttachmentAction(
            "Live camera",
            "Look around with vision",
            RACIcons.Outline.Eye,
            onOpenLive
        ),
        AttachmentAction(
            "Advanced tools",
            "SDK demos and diagnostics",
            RACIcons.Outline.Sliders,
            onOpenAdvanced
        ),
    )

    Column(
        modifier = modifier.background(MaterialTheme.colorScheme.surface),
    ) {
        HorizontalDivider(
            thickness = 0.5.dp,
            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
        )
        if (!compact) {
            AnimatedVisibility(
                visible = blockedReason != null,
                enter = fadeIn(AppMotion.standard()) + expandVertically(AppMotion.springDefault()),
                exit = fadeOut(AppMotion.exit()) + shrinkVertically(AppMotion.exit()),
            ) {
                BlockedReasonStrip(
                    reason = blockedReason.orEmpty(),
                    onResolve = onResolveBlocked,
                    modifier = Modifier.padding(
                        start = dimens.spacingMd,
                        top = dimens.spacingSm,
                        end = dimens.spacingMd,
                    ),
                )
            }
            AnimatedVisibility(
                visible = attachmentRejection != null,
                enter = fadeIn(AppMotion.standard()) + expandVertically(AppMotion.springDefault()),
                exit = fadeOut(AppMotion.exit()) + shrinkVertically(AppMotion.exit()),
            ) {
                AttachmentRejectionStrip(
                    reason = attachmentRejection.orEmpty(),
                    onDismiss = onDismissAttachmentRejection,
                    modifier = Modifier.padding(
                        start = dimens.spacingMd,
                        top = dimens.spacingSm,
                        end = dimens.spacingMd,
                    ),
                )
            }
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
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = dimens.spacingMd).padding(top = dimens.spacingSm),
            verticalAlignment = Alignment.CenterVertically,
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
                        imageVector = RACIcons.Outline.Menu,
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

            Spacer(modifier = Modifier.weight(1f))

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
                    // Globe, not Cloud: Cloud means "a hosted provider" in the Advanced hub
                    // and on the Transcribe screen, and one glyph cannot mean two things (§7).
                    imageVector = RACIcons.Outline.Globe,
                    contentDescription = when {
                        toolsEnabled -> "Disable web and tools"
                        toolsUnavailableMessage != null -> "Web and tools unavailable for current model"
                        else -> "Enable web and tools"
                    },
                    modifier = Modifier.size(dimens.iconMd),
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

            IconButton(
                onClick = onToggleThinking,
                enabled = thinkingSupported,
                modifier = Modifier.size(dimens.inputBarMinHeight),
                colors = IconButtonDefaults.iconButtonColors(
                    containerColor = if (thinkingEnabled) {
                        MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                    } else {
                        MaterialTheme.colorScheme.surfaceContainerHigh
                    },
                    contentColor = if (thinkingEnabled) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                    disabledContainerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
                    disabledContentColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.38f),
                ),
            ) {
                Icon(
                    imageVector = RACIcons.Outline.Brain,
                    contentDescription = when {
                        !thinkingSupported -> "Thinking not supported by current model"
                        thinkingEnabled -> "Disable thinking"
                        else -> "Enable thinking"
                    },
                    modifier = Modifier.size(dimens.iconMd),
                )
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = dimens.spacingMd, vertical = dimens.spacingSm),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
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
                        .semantics { contentDescription = "Message input" }
                        .then(focusRequester?.let { Modifier.focusRequester(it) } ?: Modifier),
                    textStyle = MaterialTheme.typography.bodyLarge.copy(
                        color = MaterialTheme.colorScheme.onSurface,
                    ),
                    cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                    maxLines = if (compact) 2 else 5,
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.Sentences,
                        imeAction = ImeAction.Default,
                    ),
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
        if (!compact) {
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
}

/**
 * The one blocker standing between a written message and an answer, plus the tap
 * that clears it.
 *
 * Deliberately not an error colour: nothing has gone wrong on a first launch, the
 * user simply has not chosen a model yet. Error red here would read as a fault
 * the user caused.
 */
@Composable
private fun BlockedReasonStrip(
    reason: String,
    onResolve: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(dimens.radiusLg),
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        contentColor = MaterialTheme.colorScheme.onSurface,
        onClick = onResolve,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = dimens.spacingMd, vertical = dimens.spacingSm),
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                // The blocker is always "no model chosen", so the strip wears the model mark
                // rather than a chip — the user is being sent to pick a file, not to inspect
                // their silicon.
                imageVector = RACIcons.Outline.Model,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconSm),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = reason,
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    text = "Tap to choose one — it downloads and runs on this device.",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                imageVector = RACIcons.Outline.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(dimens.iconSm),
            )
        }
    }
}

/**
 * The file the composer would not take, and why.
 *
 * Error-coloured, unlike [BlockedReasonStrip]: something the user did was refused, and softening
 * that into a neutral hint would leave them wondering whether the attachment went through.
 */
@Composable
private fun AttachmentRejectionStrip(
    reason: String,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(dimens.radiusLg),
        color = MaterialTheme.colorScheme.errorContainer,
        contentColor = MaterialTheme.colorScheme.onErrorContainer,
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
            Icon(
                imageVector = RACIcons.Outline.AlertTriangle,
                contentDescription = null,
                modifier = Modifier.size(dimens.iconSm),
            )
            Text(
                text = reason,
                style = MaterialTheme.typography.labelMedium,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = onDismiss, modifier = Modifier.size(REJECTION_DISMISS_SIZE)) {
                Icon(
                    RACIcons.Outline.Close,
                    contentDescription = "Dismiss",
                    modifier = Modifier.size(dimens.iconSm),
                )
            }
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
            Icon(
                attachment.icon,
                contentDescription = null,
                modifier = Modifier.size(dimens.iconSm)
            )
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
            IconButton(onClick = onClear, modifier = Modifier.size(REJECTION_DISMISS_SIZE)) {
                Icon(
                    RACIcons.Outline.Close,
                    contentDescription = "Remove attachment",
                    modifier = Modifier.size(dimens.iconSm)
                )
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
                imageVector = if (unavailable) RACIcons.Outline.AlertTriangle else RACIcons.Outline.Globe,
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

/**
 * Dismiss/clear affordances inside a pill. Larger than the 32 dp they used to be, which was under
 * the floor for a touch pointer sitting next to a text field people are already aiming at.
 */
private val REJECTION_DISMISS_SIZE = 44.dp
