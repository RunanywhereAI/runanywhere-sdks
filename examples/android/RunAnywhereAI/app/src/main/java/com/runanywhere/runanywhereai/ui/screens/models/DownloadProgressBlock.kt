package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.download.DownloadProgressInfo
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.types.RAModelInfo

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
 * Why a half-finished download is sitting there, from the reader's point of view.
 *
 * The two cases look identical in the data — bytes on disk, no transfer running — but they are
 * opposite events: one is a fault, one is the user's own decision. Colouring a deliberate cancel in
 * error red, or offering "Retry" for something that never failed, reads as the app having lost track
 * of what happened.
 */
enum class DownloadInterruption { FAILED, PAUSED }

/**
 * The note under an interrupted row.
 *
 * Both variants say the bytes are kept, because the reasonable fear with a half-finished
 * multi-gigabyte download is that starting again means starting from zero. It does not: the SDK
 * cancels with `delete_partial_bytes = false`.
 */
@Composable
internal fun DownloadInterruptionNote(
    kind: DownloadInterruption,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    val failed = kind == DownloadInterruption.FAILED
    val tint = if (failed) {
        MaterialTheme.colorScheme.error
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    Row(
        modifier = modifier.padding(top = dimens.spacingXs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
    ) {
        Icon(
            imageVector = if (failed) RACIcons.Outline.AlertTriangle else RACIcons.Outline.Clock,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(dimens.iconSm),
        )
        Text(
            text = if (failed) {
                "Download failed — retry resumes where it stopped"
            } else {
                "Paused — resume picks up where it stopped"
            },
            style = MaterialTheme.typography.bodySmall,
            color = tint,
        )
    }
}

/**
 * The one control at the end of a model row, in every list that has model rows.
 *
 * The flat picker list and the per-organization list each grew their own copy of this, and they had
 * already drifted: only one of them knew about a failed download, so the same model could show a red
 * "download failed" note next to a chip that still said "Get". One definition means the verb and the
 * note can never disagree again.
 */
@Composable
internal fun DownloadRowAction(
    model: RAModelInfo,
    isCurrent: Boolean,
    isReady: Boolean,
    isBusy: Boolean,
    interruption: DownloadInterruption?,
    onDownload: () -> Unit,
    onCancel: (() -> Unit)?,
) {
    when {
        isCurrent -> ModelPill("Loaded", ModelPillColors.Availability)
        isBusy -> CancelDownloadControl(onCancel)
        isReady -> ModelPill("Use", ModelPillColors.Availability)
        // "Resume" and "Retry" both come before the plain download verb: an interrupted row's
        // primary action is to continue, and the word should say so rather than reading like a
        // fresh start that would re-spend the bytes already fetched.
        interruption == DownloadInterruption.PAUSED ->
            VerbChip("Resume", RACIcons.Outline.Download, onDownload)
        interruption == DownloadInterruption.FAILED ->
            VerbChip("Retry", RACIcons.Outline.Refresh, onDownload)
        else -> {
            val needsToken = model.requiresHfAuth() && SettingsRepository.settings.hfToken.isBlank()
            // The row already shows the size; the chip stays a simple verb.
            VerbChip(if (needsToken) "Set token" else "Get", RACIcons.Outline.Download, onDownload)
        }
    }
}

@Composable
private fun VerbChip(label: String, icon: ImageVector, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    AssistChip(
        onClick = onClick,
        label = {
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
            )
        },
        leadingIcon = {
            Icon(imageVector = icon, contentDescription = null, modifier = Modifier.size(dimens.iconSm))
        },
    )
}

/**
 * Busy-state control. With [onCancel] the spinner sits inside a tap target that stops the download;
 * without it, it stays a plain progress indicator.
 */
@Composable
private fun CancelDownloadControl(onCancel: (() -> Unit)?) {
    if (onCancel == null) {
        CircularProgressIndicator(
            modifier = Modifier.size(SPINNER_SIZE),
            strokeWidth = SPINNER_STROKE,
            color = MaterialTheme.colorScheme.primary,
        )
        return
    }
    IconButton(onClick = onCancel, modifier = Modifier.size(ROW_TAP_TARGET)) {
        Box(contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
                modifier = Modifier.size(SPINNER_SIZE),
                strokeWidth = SPINNER_STROKE,
                color = MaterialTheme.colorScheme.primary,
            )
            Icon(
                imageVector = RACIcons.Outline.Close,
                contentDescription = "Cancel download",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(CANCEL_GLYPH),
            )
        }
    }
}

/** Thick enough to read as a bar at a glance, thin enough not to dominate a list row. */
private val PROGRESS_BAR_HEIGHT = 4.dp

/**
 * Icon-only controls inside a model row. 44 dp is the floor for a touch pointer; the earlier 32 dp
 * left the cancel and delete targets smaller than a fingertip on a row that is already dense.
 */
internal val ROW_TAP_TARGET = 44.dp

private val SPINNER_SIZE = 22.dp
private val SPINNER_STROKE = 2.dp

/** Small enough to read as a badge over the spinner rather than competing with it. */
private val CANCEL_GLYPH = 12.dp
