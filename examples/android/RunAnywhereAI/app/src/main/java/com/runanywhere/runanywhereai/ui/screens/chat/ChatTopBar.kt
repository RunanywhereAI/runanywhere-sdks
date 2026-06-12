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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
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
    generating: Boolean,
    loraActive: Boolean,
    onModelClick: () -> Unit,
    onNewChat: () -> Unit,
    onHistory: () -> Unit,
    onLora: () -> Unit,
    modifier: Modifier = Modifier,
) {
    TopAppBar(
        modifier = modifier,
        colors = TopAppBarDefaults.topAppBarColors(
            containerColor = MaterialTheme.colorScheme.surface,
        ),
        title = { ModelCard(model = model, generating = generating, onClick = onModelClick) },
        actions = {
            if (model?.supports_lora == true) {
                IconButton(onClick = onLora) {
                    Icon(
                        imageVector = RACIcons.Outline.Adjustments,
                        contentDescription = "LoRA adapters",
                        tint = if (loraActive) MaterialTheme.colorScheme.primary else LocalContentColor.current,
                    )
                }
            }
            IconButton(onClick = onHistory) {
                Icon(RACIcons.Outline.History, contentDescription = "History")
            }
            IconButton(onClick = onNewChat) {
                Icon(RACIcons.Outline.Plus, contentDescription = "New chat")
            }
        },
    )
}

@Composable
private fun ModelCard(model: RAModelInfo?, generating: Boolean, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    val brand = model?.brand()
    val statusText = when {
        generating -> "Generating…"
        model != null -> "Ready"
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
                    text = model?.name ?: "Select Model",
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
