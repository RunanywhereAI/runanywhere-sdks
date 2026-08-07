package com.runanywhere.runanywhereai.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RunAnywhereAITheme
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

/**
 * The app's shared content surfaces. Before this file, six screens each carried their own
 * `private fun Card(...)` with the same body — so a padding or elevation change had to be
 * made six times and never was. One definition here; screens compose it.
 */

/**
 * The standard content card: a `surfaceContainerHigh` panel with the large radius and a
 * column that spaces its children. This is the default container for a screen's sections.
 */
@Composable
fun SectionCard(
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
                .padding(dimens.spacingLg),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            content = content,
        )
    }
}

/**
 * The one-line explanation a screen opens with, under the app bar's title.
 *
 * Deliberately title-less: the app bar already names the screen, and every one of these
 * screens used to restate that name as an in-body `headlineSmall` immediately beneath it.
 * Two identical headings 8dp apart is not emphasis, it is a bug the eye has to resolve —
 * and the in-body one scrolled away, so it was the less useful of the pair.
 */
@Composable
fun ScreenLede(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = modifier.fillMaxWidth(),
    )
}

/**
 * A card's heading row: a title, an optional trailing status word, and optional supporting
 * copy underneath. Screens were hand-rolling this `Row { Text(weight(1f)); Text(status) }`
 * pattern with slightly different styles each time.
 */
@Composable
fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    status: String? = null,
    statusEmphasis: Boolean = false,
    supporting: String? = null,
) {
    val dimens = LocalDimens.current
    Column(
        modifier = modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f),
            )
            status?.let {
                Text(
                    text = it,
                    style = MaterialTheme.typography.labelMedium,
                    color = if (statusEmphasis) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurfaceVariant
                    },
                )
            }
        }
        supporting?.let {
            Text(
                text = it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** How loud a [StatusNote] is: what happened, versus what went wrong. */
enum class StatusTone { NEUTRAL, ERROR }

/**
 * A one-line status or error under a screen's content.
 *
 * Screens were each styling these by hand, which is how an error ended up the same weight
 * as a progress note on some surfaces. A leading glyph carries the difference too, so the
 * distinction survives for a user who cannot rely on the red.
 */
@Composable
fun StatusNote(text: String, tone: StatusTone = StatusTone.NEUTRAL, modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    val color = when (tone) {
        StatusTone.NEUTRAL -> MaterialTheme.colorScheme.onSurfaceVariant
        StatusTone.ERROR -> MaterialTheme.colorScheme.error
    }
    Row(
        modifier = modifier
            .fillMaxWidth()
            // Announced politely: these lines report the outcome of something the user just
            // asked for, and a screen reader has no other way to learn it happened.
            .semantics { liveRegion = LiveRegionMode.Polite },
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        verticalAlignment = Alignment.Top,
    ) {
        if (tone == StatusTone.ERROR) {
            Icon(
                imageVector = RACIcons.Outline.AlertTriangle,
                contentDescription = null,
                tint = color,
                modifier = Modifier.size(dimens.iconSm),
            )
        }
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall,
            color = color,
            modifier = Modifier.weight(1f),
        )
    }
}

/**
 * The tinted circular plate behind an empty-state or hero glyph. A soft brand-tinted
 * gradient rather than a flat wash, so the mark reads as deliberate art instead of a
 * placeholder — and so the empty state has the same depth as the populated one.
 */
@Composable
fun GlyphPlate(
    icon: ImageVector,
    modifier: Modifier = Modifier,
    diameter: androidx.compose.ui.unit.Dp = LocalDimens.current.artCircle,
) {
    val dimens = LocalDimens.current
    val scheme = MaterialTheme.colorScheme
    Box(
        modifier = modifier
            .size(diameter)
            .clip(RoundedCornerShape(dimens.radiusFull))
            .background(
                Brush.linearGradient(
                    listOf(
                        scheme.primary.copy(alpha = 0.18f),
                        scheme.tertiary.copy(alpha = 0.10f),
                    ),
                ),
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = scheme.primary,
            modifier = Modifier.size(dimens.iconLg),
        )
    }
}

/**
 * The canonical empty state. Every empty surface in the app uses this shape: a glyph, a
 * title naming the state, one line explaining *why* it is empty, and — where one exists —
 * the single action that resolves it.
 *
 * The action is the point. An empty state that only says "nothing here" makes the user
 * guess whether the app is broken; naming the next step is what turns a dead end into a
 * step in a flow.
 */
@Composable
fun EmptyState(
    icon: ImageVector,
    title: String,
    body: String,
    modifier: Modifier = Modifier,
    primaryAction: EmptyStateAction? = null,
    secondaryAction: EmptyStateAction? = null,
) {
    val dimens = LocalDimens.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = dimens.spacingXl, vertical = dimens.spacingXl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(dimens.spacingMd, Alignment.CenterVertically),
    ) {
        GlyphPlate(icon = icon)
        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        Text(
            text = body,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = dimens.bubbleMaxWidth),
        )
        primaryAction?.let {
            Button(onClick = it.onClick, enabled = it.enabled) { Text(it.label) }
        }
        secondaryAction?.let {
            TextButton(onClick = it.onClick, enabled = it.enabled) { Text(it.label) }
        }
    }
}

/** A labelled action offered by an [EmptyState]. */
data class EmptyStateAction(
    val label: String,
    val enabled: Boolean = true,
    val onClick: () -> Unit,
)

@Preview(name = "Empty state light")
@Preview(name = "Empty state dark", uiMode = 0x20)
@Composable
private fun EmptyStatePreview() {
    RunAnywhereAITheme {
        Surface {
            EmptyState(
                icon = RACIcons.Outline.FileText,
                title = "No document yet",
                body = "Pick a photo of an invoice, receipt, or scan and the text comes back as " +
                    "selectable characters.",
                primaryAction = EmptyStateAction("Choose an image") {},
            )
        }
    }
}
