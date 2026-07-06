package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import com.runanywhere.sdk.public.types.RAModelInfo

@Composable
fun ModelRow(
    model: RAModelInfo,
    isCurrent: Boolean,
    isReady: Boolean,
    isBusy: Boolean,
    progressPercent: Int?,
    onSelect: () -> Unit,
    onDownload: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val dimens = LocalDimens.current
    val brand = model.brand()
    Surface(
        modifier = modifier
            .fillMaxWidth()
            .then(if (isReady) Modifier.clickable(onClick = onSelect) else Modifier),
        shape = RoundedCornerShape(dimens.radiusLg),
        color = MaterialTheme.colorScheme.surface,
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
                Text(
                    model.name,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    model.framework.consumerBackendLabel(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
                    model.capabilityLabels().take(3).forEach { label ->
                        Pill(label, MaterialTheme.colorScheme.primary)
                    }
                }
                if (isBusy && progressPercent != null) {
                    Text(
                        "Downloading… $progressPercent%",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            Spacer(Modifier.width(dimens.spacingSm))
            TrailingAction(isCurrent, isReady, isBusy, model, onDownload)
        }
    }
}

@Composable
private fun TrailingAction(
    isCurrent: Boolean,
    isReady: Boolean,
    isBusy: Boolean,
    model: RAModelInfo,
    onDownload: () -> Unit,
) {
    when {
        isCurrent -> Pill("Loaded", primaryGreen)
        isBusy -> CircularProgressIndicator(
            modifier = Modifier.size(20.dp),
            strokeWidth = 2.dp,
            color = MaterialTheme.colorScheme.primary,
        )
        isReady -> Pill("Use", primaryGreen)
        else -> Pill(
            text = formatModelSize(model.download_size_bytes),
            color = MaterialTheme.colorScheme.primary,
            icon = RACIcons.Outline.Download,
            onClick = onDownload,
        )
    }
}

@Composable
private fun Pill(
    text: String,
    color: Color,
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
    onClick: (() -> Unit)? = null,
) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(dimens.radiusSm))
            .background(color.copy(alpha = 0.12f))
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = dimens.spacingSm, vertical = dimens.spacingXs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(dimens.spacingXs))
        }
        Text(
            text,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.SemiBold,
            color = color,
        )
    }
}
