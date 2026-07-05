package com.runanywhere.runanywhereai.ui.screens.more

import ai.runanywhere.proto.v1.NpuCapability
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Slim Hexagon-NPU capability card. NPU models themselves live in the standard
 * model pickers (registered only for the probed arch); this card is the one
 * NPU-specific surface left — it tells the user whether this device runs them.
 */
@Composable
fun HexagonNpuCard() {
    val dimens = LocalDimens.current
    val npu by produceState<NpuCapability?>(initialValue = null) {
        value = withContext(Dispatchers.IO) {
            runCatching { QHexRT.probeNpu() }.getOrNull()
        }
    }

    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = RACIcons.Outline.Cpu,
                contentDescription = null,
                tint = if (npu?.qhexrt_supported == true) primaryGreen else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text("Hexagon NPU", style = MaterialTheme.typography.bodyLarge)
                val info = npu
                Text(
                    text = when {
                        info == null -> "Detecting…"
                        info.qhexrt_supported ->
                            "${info.soc_model.ifEmpty { "Snapdragon" }} · Hexagon ${info.arch_name} — NPU models available"
                        else ->
                            "Requires Hexagon v75+ — NPU models hidden" +
                                if (info.soc_model.isNotEmpty()) " (${info.soc_model})" else ""
                    },
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (npu?.qhexrt_supported == true) {
                Text(
                    text = "Ready",
                    style = MaterialTheme.typography.labelSmall,
                    color = primaryGreen,
                )
            }
        }
    }
}
