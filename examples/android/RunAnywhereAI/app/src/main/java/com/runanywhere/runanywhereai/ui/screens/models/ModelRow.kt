package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.download.DownloadProgressInfo
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.sdk.public.types.RAModelInfo

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ModelRow(
    model: RAModelInfo,
    isCurrent: Boolean,
    isReady: Boolean,
    isBusy: Boolean,
    // Null while a transfer is starting (or when the row is not downloading); the bar then reads as
    // indeterminate rather than pinned at zero.
    progress: DownloadProgressInfo?,
    onSelect: () -> Unit,
    onDownload: () -> Unit,
    onDelete: (() -> Unit)? = null,
    // When non-null, the busy spinner becomes a tap-to-cancel control so an
    // in-flight download can be stopped. Null keeps the plain progress spinner.
    onCancel: (() -> Unit)? = null,
    // This model's last download failed. The trailing action becomes Retry, which resumes from the
    // bytes already on disk instead of starting the transfer over.
    hasFailed: Boolean = false,
    highlightLabel: String? = null,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    val brand = model.brand()
    val hasHfToken = SettingsRepository.settings.hfToken.isNotBlank()
    val isHighlighted = highlightLabel != null
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .then(if (isReady) Modifier.clickable(onClick = onSelect) else Modifier),
        shape = RoundedCornerShape(dimens.radiusLg),
        color = if (isHighlighted) {
            MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
        } else {
            MaterialTheme.colorScheme.surface
        },
        border = if (isHighlighted) {
            BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.5f))
        } else {
            null
        },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = brand.icon,
                contentDescription = null,
                tint = brand.color,
                modifier = Modifier.size(dimens.iconLg),
            )
            Spacer(Modifier.width(dimens.spacingMd))

            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
            ) {
                if (highlightLabel != null) {
                    ModelPill(highlightLabel, ModelPillColors.Capability, icon = RACIcons.Filled.Bolt)
                }
                Text(
                    model.displayTitle(),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                // Size is always visible; backend rides along as a subtle badge.
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                ) {
                    Text(
                        model.sizeLabel(),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    BackendBadge(framework = model.framework, compact = true)
                }
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                    verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                ) {
                    // At most two clean tags (feel + one notable capability).
                    model.consumerTags().forEach { tag ->
                        ModelPill(tag.label, tag.kind.pillColor())
                    }
                    if (model.requiresHfAuth()) {
                        ModelPill(
                            "Private",
                            if (hasHfToken) ModelPillColors.Capability else ModelPillColors.Warning,
                        )
                    }
                }
                if (isBusy) {
                    DownloadProgressBlock(progress)
                } else if (hasFailed) {
                    DownloadFailureNote()
                }
            }

            Spacer(Modifier.width(dimens.spacingSm))
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
                TrailingAction(isCurrent, isReady, isBusy, hasFailed, model, onDownload, onCancel)
                if (onDelete != null && isReady) {
                    IconButton(onClick = onDelete, modifier = Modifier.size(32.dp)) {
                        Icon(
                            imageVector = RACIcons.Outline.Trash,
                            contentDescription = "Delete ${model.name}",
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(dimens.iconSm),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun TrailingAction(
    isCurrent: Boolean,
    isReady: Boolean,
    isBusy: Boolean,
    hasFailed: Boolean,
    model: RAModelInfo,
    onDownload: () -> Unit,
    onCancel: (() -> Unit)? = null,
) {
    when {
        isCurrent -> ModelPill("Loaded", ModelPillColors.Availability)
        isBusy -> DownloadProgressAction(onCancel)
        isReady -> ModelPill("Use", ModelPillColors.Availability)
        // Retry before the plain download chip: a failed row's primary action is to resume, and the
        // verb should say so rather than reading like a fresh start.
        hasFailed -> RetryChip(onRetry = onDownload)
        else -> DownloadChip(model = model, onDownload = onDownload)
    }
}

@Composable
private fun RetryChip(onRetry: () -> Unit) {
    val dimens = LocalDimens.current
    AssistChip(
        onClick = onRetry,
        label = {
            Text(
                text = "Retry",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
            )
        },
        leadingIcon = {
            Icon(
                imageVector = RACIcons.Outline.Refresh,
                contentDescription = null,
                modifier = Modifier.size(dimens.iconSm),
            )
        },
    )
}

// Busy-state control. With [onCancel] the spinner sits inside a tap target that
// stops the download; without it, it stays a plain progress indicator.
@Composable
private fun DownloadProgressAction(onCancel: (() -> Unit)?) {
    if (onCancel == null) {
        CircularProgressIndicator(
            modifier = Modifier.size(20.dp),
            strokeWidth = 2.dp,
            color = MaterialTheme.colorScheme.primary,
        )
        return
    }
    IconButton(onClick = onCancel, modifier = Modifier.size(32.dp)) {
        Box(contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
                modifier = Modifier.size(24.dp),
                strokeWidth = 2.dp,
                color = MaterialTheme.colorScheme.primary,
            )
            Icon(
                imageVector = RACIcons.Outline.Close,
                contentDescription = "Cancel download",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(12.dp),
            )
        }
    }
}

@Composable
private fun DownloadChip(model: RAModelInfo, onDownload: () -> Unit) {
    val dimens = LocalDimens.current
    val needsHfToken = model.requiresHfAuth() && SettingsRepository.settings.hfToken.isBlank()
    AssistChip(
        onClick = onDownload,
        label = {
            // The row already shows the size; the chip stays a simple verb.
            Text(
                text = if (needsHfToken) "Set token" else "Get",
                style = MaterialTheme.typography.labelLarge,
                fontWeight = FontWeight.SemiBold,
            )
        },
        leadingIcon = {
            Icon(
                imageVector = RACIcons.Outline.Download,
                contentDescription = null,
                modifier = Modifier.size(dimens.iconSm),
            )
        },
    )
}