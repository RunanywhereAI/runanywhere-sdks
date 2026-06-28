package com.runanywhere.runanywhereai.ui.screens.npu.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModality
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelRow
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelsViewModel
import com.runanywhere.runanywhereai.ui.screens.npu.label
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing

/**
 * NPU model overview, grouped by modality (Chat / Vision / STT / TTS). Only
 * bundles matching the device's Hexagon arch are shown; download + load is
 * driven by the shared [NpuModelsViewModel], so progress and resident state
 * stay in sync with the per-screen model bars.
 */
@Composable
fun ModelsScreen(vm: NpuModelsViewModel) {
    LaunchedEffect(Unit) { vm.refresh() }
    val s = vm.state

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Text(
            "Device NPU: ${s.deviceArch ?: "detecting…"}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        s.error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        }

        NpuModality.entries.forEach { modality ->
            val models = vm.catalogFor(modality)
            if (models.isNotEmpty()) {
                Text(
                    modality.label,
                    style = MaterialTheme.typography.titleMedium,
                )
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    models.forEach { model -> NpuModelRow(model = model, vm = vm) }
                }
            }
        }

        if (!vm.hasAnyForDevice()) {
            Text(
                "No NPU models available for ${s.deviceArch ?: "this device"} yet.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
