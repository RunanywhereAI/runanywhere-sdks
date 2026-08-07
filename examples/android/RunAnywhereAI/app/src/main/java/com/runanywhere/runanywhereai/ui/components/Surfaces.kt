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
