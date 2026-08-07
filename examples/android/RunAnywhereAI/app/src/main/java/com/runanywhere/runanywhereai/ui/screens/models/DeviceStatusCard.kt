package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen

/**
 * What this phone can run, as one line that opens into the specs behind it.
 *
 * Collapsed by default. The four facts — model, chip, memory, NPU — explain a
 * recommendation but do not make one, and a reader who came to the picker to
 * choose a model does not need a spec sheet to do it. The summary line carries
 * the only part that changes their decision ("High-performance • NPU
 * accelerated"); the table stays one tap away for anyone who wants to know why.
 */
@Composable
fun DeviceStatusCard(info: DeviceInfo, modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    var expanded by remember { mutableStateOf(false) }
    Surface(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(dimens.radiusLg),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column {
            TierHeader(
                info = info,
                expanded = expanded,
                onToggle = { expanded = !expanded },
            )
            AnimatedVisibility(visible = expanded) {
                Column(modifier = Modifier.padding(horizontal = dimens.spacingLg)) {
                    Line()
                    DeviceRow(RACIcons.Outline.DeviceMobile, "Model", info.model)
                    Line()
                    DeviceRow(RACIcons.Outline.Cpu, "Chip", info.chip)
                    Line()
                    DeviceRow(RACIcons.Outline.Memory, "Memory", info.memoryLabel)
                    Line()
                    DeviceRow(
                        RACIcons.Filled.Bolt,
                        "NPU",
                        info.npuName ?: "Not detected",
                        valueColor = if (info.hasNpu) primaryGreen else null,
                    )
                    Spacer(Modifier.padding(bottom = dimens.spacingXs))
                }
            }
        }
    }
}

// Memory in GB with one decimal. "11316 MB" is a number the reader has to convert
// before it means anything; "11.1 GB" is the figure printed on the box.
private val DeviceInfo.memoryLabel: String
    get() = if (memoryMb > 0) "%.1f GB".format(memoryMb / 1024.0) else "—"

@Composable
private fun TierHeader(info: DeviceInfo, expanded: Boolean, onToggle: () -> Unit) {
    val dimens = LocalDimens.current
    val accent = if (info.hasNpu) primaryGreen else MaterialTheme.colorScheme.primary
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(
                role = Role.Button,
                onClickLabel = if (expanded) "Hide device details" else "Show device details",
                onClick = onToggle,
            )
            .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(36.dp)
                .clip(RoundedCornerShape(dimens.radiusMd))
                .background(accent.copy(alpha = 0.14f)),
        ) {
            Icon(RACIcons.Outline.Cpu, contentDescription = null, tint = accent, modifier = Modifier.size(dimens.iconMd))
        }
        Spacer(Modifier.width(dimens.spacingMd))
        Column(modifier = Modifier.weight(1f)) {
            Text(
                info.tierSummary,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                "Recommendations tuned to this device",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Icon(
            imageVector = if (expanded) RACIcons.Outline.ChevronUp else RACIcons.Outline.ChevronDown,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconMd),
        )
    }
}

@Composable
private fun DeviceRow(icon: ImageVector, label: String, value: String, valueColor: Color? = null) {
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
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            color = valueColor ?: MaterialTheme.colorScheme.onSurfaceVariant,
            fontWeight = if (valueColor != null) FontWeight.SemiBold else FontWeight.Normal,
        )
    }
}

@Composable
private fun Line() {
    val dimens = LocalDimens.current
    HorizontalDivider(
        thickness = 0.5.dp,
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
    )
    Spacer(Modifier.padding(top = dimens.spacingXs))
}
