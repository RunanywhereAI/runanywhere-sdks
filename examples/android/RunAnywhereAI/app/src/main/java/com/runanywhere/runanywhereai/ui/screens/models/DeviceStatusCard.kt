package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

@Composable
fun DeviceStatusCard(info: DeviceInfo, modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(dimens.radiusLg),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(modifier = Modifier.padding(horizontal = dimens.spacingLg)) {
            DeviceRow(RACIcons.Outline.DeviceMobile, "Model", info.model)
            Line()
            DeviceRow(RACIcons.Outline.Cpu, "Chip", info.chip)
            Line()
            DeviceRow(RACIcons.Outline.Database, "Memory", if (info.memoryMb > 0) "${info.memoryMb} MB" else "—")
        }
    }
}

@Composable
private fun DeviceRow(icon: ImageVector, label: String, value: String) {
    val dimens = LocalDimens.current
    val accent = MaterialTheme.colorScheme.primary
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = dimens.spacingMd),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(30.dp)
                .clip(RoundedCornerShape(dimens.radiusSm))
                .background(accent.copy(alpha = 0.12f)),
        ) {
            Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(dimens.iconSm))
        }
        Spacer(Modifier.width(dimens.spacingMd))
        Text(label, style = MaterialTheme.typography.bodyLarge)
        Spacer(Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Line() {
    val dimens = LocalDimens.current
    HorizontalDivider(
        modifier = Modifier.padding(start = 42.dp),
        thickness = 0.5.dp,
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
    )
}
