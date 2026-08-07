package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.download.DownloadProgressInfo
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

/**
 * The live state of a transfer: a determinate bar plus one line of plain numbers.
 *
 * A percentage on its own cannot distinguish a slow download from a dead one, and these models run
 * to several gigabytes, so the rate and the projected finish are the part a waiting user actually
 * reads. Everything shown comes from the SDK event; nothing is measured here.
 *
 * Shared by every surface that can start a download — the model picker rows, the per-organization
 * list, and the Voice AI setup card — so the same transfer never looks different in two places.
 */
@Composable
internal fun DownloadProgressBlock(progress: DownloadProgressInfo?, modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    val fraction = progress?.fraction

    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = dimens.spacingXs),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
    ) {
        if (fraction == null) {
            // Size unknown: an indeterminate bar is honest about that, where a determinate bar at 0
            // would look like a transfer that has stalled before starting.
            LinearProgressIndicator(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(PROGRESS_BAR_HEIGHT)
                    .clip(RoundedCornerShape(dimens.radiusFull)),
            )
        } else {
            // Retargeting toward the newest fraction rather than snapping to it. Progress arrives in
            // uneven jumps, and the eased motion is what conveys "still moving" between them — it
            // carries information, so it stays on the STANDARD tier and is skipped outright under
            // Reduce Motion, where a snapped bar is the correct presentation.
            val animated by animateFloatAsState(
                targetValue = fraction,
                animationSpec = AppMotion.standard(),
                label = "downloadProgress",
            )
            LinearProgressIndicator(
                progress = { animated },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(PROGRESS_BAR_HEIGHT)
                    .clip(RoundedCornerShape(dimens.radiusFull)),
                drawStopIndicator = {},
            )
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = progress?.detailLine?.takeIf { it.isNotBlank() } ?: "Starting…",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            progress?.percent?.let {
                Text(
                    text = "$it%",
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

/**
 * Why the row is offering Retry.
 *
 * Says the bytes are kept, because the reasonable fear with a half-finished multi-gigabyte download
 * is that retrying starts from zero. It does not: the SDK cancels without deleting partial bytes.
 */
@Composable
internal fun DownloadFailureNote(modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    Row(
        modifier = modifier.padding(top = dimens.spacingXs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
    ) {
        Icon(
            imageVector = RACIcons.Outline.AlertTriangle,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.error,
            modifier = Modifier.size(dimens.iconSm),
        )
        Text(
            text = "Download failed — retry resumes where it stopped",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.error,
        )
    }
}

/** Thick enough to read as a bar at a glance, thin enough not to dominate a list row. */
private val PROGRESS_BAR_HEIGHT = 4.dp
