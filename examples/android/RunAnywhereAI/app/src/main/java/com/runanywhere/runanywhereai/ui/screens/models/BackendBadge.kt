package com.runanywhere.runanywhereai.ui.screens.models

import ai.runanywhere.proto.v1.InferenceFramework
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens

// Deliberately neutral (never the dominant element of a row): a small
// outline-tinted pill naming the runtime that executes the model.
@Composable
fun BackendBadge(
    framework: InferenceFramework,
    modifier: Modifier = Modifier,
    compact: Boolean = false,
) {
    val dimens = LocalDimens.current
    val color = MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        modifier = modifier
            .background(color.copy(alpha = 0.10f), RoundedCornerShape(dimens.radiusSm))
            .padding(horizontal = dimens.spacingSm, vertical = dimens.spacingXs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = framework.backendIcon(),
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(if (compact) 12.dp else dimens.iconSm),
        )
        Spacer(Modifier.width(dimens.spacingXs))
        Text(
            text = if (compact) framework.shortLabel() else framework.consumerBackendLabel(),
            style = if (compact) MaterialTheme.typography.labelSmall else MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Medium,
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
