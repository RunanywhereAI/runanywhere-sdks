package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.screens.models.brand
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import com.runanywhere.sdk.public.types.RAModelInfo

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatTopBar(
    model: RAModelInfo?,
    conversationModelName: String?,
    generating: Boolean,
    loraActive: Boolean,
    hasMessages: Boolean,
    onModelClick: () -> Unit,
    onNewChat: () -> Unit,
    onHistory: () -> Unit,
    onLora: () -> Unit,
    onDetails: () -> Unit,
    onMenu: () -> Unit,
    showMenu: Boolean,
    modifier: Modifier = Modifier,
) {
    var overflowExpanded by remember { mutableStateOf(false) }

    TopAppBar(
        modifier = modifier,
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        navigationIcon = {
            if (showMenu) {
                IconButton(onClick = onMenu) {
                    Icon(RACIcons.Outline.Menu, contentDescription = "Open menu")
                }
            }
        },
        title = {
            ModelCard(
                model = model,
                fallbackModelName = conversationModelName,
                generating = generating,
                onClick = onModelClick,
            )
        },
        actions = {
            IconButton(onClick = onHistory) {
                Icon(RACIcons.Outline.History, contentDescription = "Saved chats")
            }
            IconButton(onClick = onNewChat) {
                Icon(RACIcons.Outline.Plus, contentDescription = "New chat")
            }
            if (hasMessages || model?.supports_lora == true) {
                IconButton(onClick = { overflowExpanded = true }) {
                    Icon(RACIcons.Outline.DotsVertical, contentDescription = "More chat actions")
                }
                DropdownMenu(
                    expanded = overflowExpanded,
                    onDismissRequest = { overflowExpanded = false },
                ) {
                    if (hasMessages) {
                        DropdownMenuItem(
                            text = { Text("Chat details") },
                            leadingIcon = { Icon(RACIcons.Outline.InfoCircle, contentDescription = null) },
                            onClick = {
                                overflowExpanded = false
                                onDetails()
                            },
                        )
                    }
                    if (model?.supports_lora == true) {
                        DropdownMenuItem(
                            text = { Text(if (loraActive) "Adapters active" else "Adapters") },
                            leadingIcon = { Icon(RACIcons.Outline.Adjustments, contentDescription = null) },
                            onClick = {
                                overflowExpanded = false
                                onLora()
                            },
                        )
                    }
                }
            }
        },
    )
}

@Composable
private fun ModelCard(
    model: RAModelInfo?,
    fallbackModelName: String?,
    generating: Boolean,
    onClick: () -> Unit,
) {
    val dimens = LocalDimens.current
    val brand = model?.brand()
    // Mirrors iOS loadConversation restore: with no model loaded, the
    // conversation's recorded model is shown as a preselection (not loaded).
    val statusText = when {
        generating -> "Generating…"
        model != null -> "Ready"
        fallbackModelName != null -> "Not loaded"
        else -> "Tap to choose"
    }
    val dotColor = when {
        generating -> MaterialTheme.colorScheme.primary
        model != null -> primaryGreen
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    val dotAlpha = if (generating) {
        val transition = rememberInfiniteTransition(label = "generating")
        val alpha by transition.animateFloat(
            initialValue = 0.3f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(700), RepeatMode.Reverse),
            label = "generatingDot",
        )
        alpha
    } else {
        1f
    }

    Card(modifier = Modifier.clickable(onClick = onClick).widthIn(max = 200.dp)) {
        Row(
            modifier = Modifier.padding(dimens.spacingXs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = brand?.icon ?: RACIcons.Outline.Bolt,
                contentDescription = "Model",
                tint = brand?.color ?: MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(dimens.spacingSm),
            )

            Column(modifier = Modifier.padding(end = dimens.spacingSm)) {
                Text(
                    text = model?.name ?: fallbackModelName ?: "Select Model",
                    overflow = TextOverflow.Ellipsis,
                    maxLines = 1,
                    style = MaterialTheme.typography.titleMedium,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                ) {
                    Spacer(
                        Modifier
                            .size(dimens.spacingSm)
                            .alpha(dotAlpha)
                            .background(dotColor, CircleShape),
                    )
                    Text(
                        text = statusText,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }
        }
    }
}
