package com.runanywhere.runanywhereai.ui.screens.npu

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.screens.npu.theme.RaSuccess
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing

/**
 * Compact "model bar" shown at the top of each inference screen. Displays the
 * model currently resident in NPU memory for [modality] and opens
 * [NpuModelSheet] (download + load) on tap — mirroring the main app's
 * model-selection pattern, but scoped to arch-matching NPU bundles.
 */
@Composable
fun NpuModelBar(
    modality: NpuModality,
    vm: NpuModelsViewModel,
    modifier: Modifier = Modifier,
) {
    var showSheet by remember { mutableStateOf(false) }
    val loadedId = vm.loadedId(modality)
    val loaded = vm.catalogFor(modality).firstOrNull { it.id == loadedId }

    SectionCard(modifier = modifier.clickable { showSheet = true }, title = "Model") {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    loaded?.name ?: "Select a model",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    loaded?.detail ?: "Tap to download or load a ${modality.label} model",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            StatusPill(
                label = if (loaded != null) "Loaded" else "Choose",
                color = if (loaded != null) RaSuccess else MaterialTheme.colorScheme.primary,
            )
        }
    }

    if (showSheet) {
        NpuModelSheet(modality = modality, vm = vm, onDismiss = { showSheet = false })
    }
}

/**
 * Bottom sheet listing the arch-matching models for one [modality] with
 * Download / Load / "In memory" states and live download progress.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NpuModelSheet(
    modality: NpuModality,
    vm: NpuModelsViewModel,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val s = vm.state
    val models = vm.catalogFor(modality)

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = Spacing.md, vertical = Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            Text(
                "${modality.label} models",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
            )
            Text(
                "Device NPU: ${s.deviceArch ?: "detecting…"}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            when {
                s.deviceArch == null -> EmptyNote("Detecting the device NPU…")
                models.isEmpty() -> EmptyNote(
                    "No ${modality.label} model available for Hexagon ${s.deviceArch} yet.",
                )
                else -> models.forEach { model -> NpuModelRow(model = model, vm = vm) }
            }

            s.error?.let {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
            // Bottom inset breathing room above the nav bar.
            Column(Modifier.padding(bottom = Spacing.lg)) {}
        }
    }
}

/** One catalog row with status-aware trailing control. Reused by the Models screen. */
@Composable
fun NpuModelRow(model: NpuModel, vm: NpuModelsViewModel) {
    val status = vm.statusFor(model)
    val showProgress = status == NpuModelStatus.Downloading
    val progress = vm.state.progress?.takeIf { showProgress }

    SectionCard {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Text(model.name, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(
                    model.detail,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            when (status) {
                NpuModelStatus.Loaded ->
                    Text("In memory", style = MaterialTheme.typography.labelLarge, color = RaSuccess)
                NpuModelStatus.Loading ->
                    CircularProgressIndicator(modifier = Modifier.size(20.dp))
                NpuModelStatus.Downloading ->
                    Text(
                        "${((progress ?: 0f) * 100).toInt()}%",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                    )
                NpuModelStatus.Downloaded ->
                    Button(onClick = { vm.load(model) }, enabled = vm.state.busyId == null) { Text("Load") }
                NpuModelStatus.NotDownloaded ->
                    Button(
                        onClick = { vm.download(model) },
                        enabled = model.hasSource && vm.state.busyId == null,
                    ) { Text(if (model.hasSource) "Download" else "Pending") }
            }
        }
        if (showProgress) {
            LinearProgressIndicator(
                progress = { (progress ?: 0f).coerceIn(0f, 1f) },
                modifier = Modifier.fillMaxWidth().padding(top = Spacing.sm),
            )
        }
    }
}

@Composable
private fun EmptyNote(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(vertical = Spacing.sm),
    )
}
