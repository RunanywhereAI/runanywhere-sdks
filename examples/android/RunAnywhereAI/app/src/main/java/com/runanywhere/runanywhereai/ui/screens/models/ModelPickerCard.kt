package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.tooling.preview.Preview
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.types.RAModelInfo

/**
 * "Which model is this screen using, and how do I change it?" — the row that opens
 * [ModelSelectionSheet].
 *
 * Six screens each carried their own private `ModelCard` with the same body and subtly
 * different behaviour: some showed a chevron when they were not tappable, some showed a
 * spinner while loading and some silently froze, and the primary/disabled states diverged.
 * One definition, so every modality answers that question identically.
 */
@Composable
fun ModelPickerCard(
    label: String,
    model: RAModelInfo?,
    icon: ImageVector,
    modifier: Modifier = Modifier,
    /** Loading or downloading — the row reports it rather than appearing stuck. */
    busy: Boolean = false,
    /** Tap withheld, e.g. while inference holds native state that a swap would pull out. */
    enabled: Boolean = true,
    placeholder: String = "Select a model",
    onClick: (() -> Unit)? = null,
) {
    val dimens = LocalDimens.current
    val tappable = onClick != null && enabled && !busy
    val title = when {
        busy -> "Preparing model…"
        model != null -> model.name
        else -> placeholder
    }
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .then(
                    if (tappable) Modifier.clickable(onClick = onClick!!) else Modifier,
                )
                .padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                // Dimmed rather than hidden while locked: the row still has to read as the
                // model slot, just not as something to press right now.
                tint = if (enabled) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
            ) {
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                // Crossfaded so "Select a model" → "Preparing model…" → the real name reads
                // as one slot changing its answer, not three different rows.
                AnimatedContent(
                    targetState = title,
                    transitionSpec = {
                        fadeIn(AppMotion.standard()) togetherWith fadeOut(AppMotion.exit())
                    },
                    label = "modelTitle",
                ) { current ->
                    Text(text = current, style = MaterialTheme.typography.bodyLarge)
                }
                model?.let { BackendBadge(framework = it.framework, compact = true) }
            }
            when {
                busy -> CircularProgressIndicator(modifier = Modifier.size(dimens.iconSm))
                // No chevron when there is nothing to open: an affordance that does nothing
                // is worse than none at all.
                tappable -> Icon(
                    imageVector = RACIcons.Outline.ChevronRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(dimens.iconSm),
                )
            }
        }
    }
}

@Preview(name = "Model picker light")
@Preview(name = "Model picker dark", uiMode = 0x20)
@Composable
private fun ModelPickerCardPreview() {
    RunAnywhereAITheme {
        Surface {
            val dimens = LocalDimens.current
            Column(
                modifier = Modifier.padding(dimens.screenPadding),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
            ) {
                ModelPickerCard(
                    label = "OCR model",
                    model = null,
                    icon = RACIcons.Outline.ScanText,
                    onClick = {},
                )
                ModelPickerCard(
                    label = "OCR model",
                    model = null,
                    icon = RACIcons.Outline.ScanText,
                    busy = true,
                    onClick = {},
                )
                ModelPickerCard(
                    label = "OCR model",
                    model = null,
                    icon = RACIcons.Outline.ScanText,
                    enabled = false,
                    placeholder = "Locked while extracting",
                    onClick = {},
                )
            }
        }
    }
}
