package com.runanywhere.runanywhereai.ui.screens.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.components.rememberBreath
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.motionSpec

enum class ThinkingPhase {
    ACTIVE,
    COMPLETE,
}

@Composable
fun ThinkingSection(
    thinking: String,
    phase: ThinkingPhase,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    var manuallyExpanded by rememberSaveable { mutableStateOf(false) }
    val inProgress = phase == ThinkingPhase.ACTIVE
    val expanded = inProgress || manuallyExpanded
    val accent = MaterialTheme.colorScheme.primary

    LaunchedEffect(phase) {
        if (phase == ThinkingPhase.COMPLETE) {
            manuallyExpanded = false
        }
    }

    Column(modifier = modifier) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(dimens.radiusSm))
                .clickable(enabled = !inProgress) { manuallyExpanded = !manuallyExpanded }
                .padding(vertical = dimens.spacingXs, horizontal = dimens.spacingXs),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
        ) {
            // Breathes on the shared 1.6 s ambient period while the model reasons, steady
            // once it is done. `graphicsLayer` rather than `Modifier.alpha` so the per-frame
            // cost is a compositor property, not a draw invalidation on the icon.
            val brainAlpha = if (inProgress) rememberBreath(min = 0.4f, label = "thinking") else 1f
            Icon(
                imageVector = RACIcons.Outline.Brain,
                contentDescription = null,
                tint = accent,
                modifier = Modifier
                    .size(dimens.iconSm)
                    .graphicsLayer { alpha = brainAlpha },
            )
            Text(
                text = if (inProgress) "Thinking…" else "Reasoning",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Icon(
                imageVector = if (expanded) RACIcons.Outline.ChevronUp else RACIcons.Outline.ChevronDown,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(dimens.iconSm),
            )
        }

        // A disclosure is the canonical STANDARD-tier state change. Both halves go through
        // `motionSpec` so the whole expand collapses to one 150 ms crossfade under reduced
        // motion instead of still sliding the panel open.
        AnimatedVisibility(
            visible = expanded,
            enter = fadeIn(motionSpec { AppMotion.standard() }) +
                expandVertically(motionSpec { AppMotion.standard() }),
            exit = fadeOut(motionSpec { AppMotion.exit() }) +
                shrinkVertically(motionSpec { AppMotion.exit() }),
        ) {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = dimens.spacingXs),
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                shape = RoundedCornerShape(dimens.radiusSm),
            ) {
                Text(
                    text = thinking.ifEmpty { if (inProgress) "Waiting for the first reasoning token…" else "No reasoning provided." },
                    style = RACTextStyles.CodeSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .heightIn(max = 220.dp)
                        .verticalScroll(rememberScrollState())
                        .padding(dimens.spacingMd),
                )
            }
        }
    }
}
