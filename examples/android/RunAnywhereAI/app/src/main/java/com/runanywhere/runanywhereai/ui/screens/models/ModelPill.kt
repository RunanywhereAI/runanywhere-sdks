package com.runanywhere.runanywhereai.ui.screens.models

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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.primaryGreen

// The one badge shape used across the picker. Flat recommended rows, family cards and
// variant rows all render through it, so a tag can never look different depending on
// where it is shown.
@Composable
fun ModelPill(
    text: String,
    color: Color,
    icon: ImageVector? = null,
) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(dimens.radiusSm))
            .background(color.copy(alpha = 0.12f))
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
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

// One palette for every pill in the picker, named by meaning rather than by hue, so the
// same idea keeps the same colour everywhere.
object ModelPillColors {
    val Availability: Color = primaryGreen
    val Capability: Color @Composable get() = MaterialTheme.colorScheme.primary
    val Feel: Color @Composable get() = MaterialTheme.colorScheme.tertiary
    val Neutral: Color @Composable get() = MaterialTheme.colorScheme.onSurfaceVariant
    val Warning: Color @Composable get() = MaterialTheme.colorScheme.error
}

@Composable
fun ConsumerTagKind.pillColor(): Color = when (this) {
    ConsumerTagKind.CAPABILITY, ConsumerTagKind.MODALITY -> ModelPillColors.Capability
    ConsumerTagKind.FEEL -> ModelPillColors.Feel
}
