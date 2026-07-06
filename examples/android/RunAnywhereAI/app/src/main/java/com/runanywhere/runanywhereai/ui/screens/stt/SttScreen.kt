package com.runanywhere.runanywhereai.ui.screens.stt

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.sdk.hybrid.HybridRoutedMetadata
import com.runanywhere.runanywhereai.data.cloud.CloudProviderRepository
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import com.runanywhere.runanywhereai.util.readableWidth
import java.util.Locale

@Composable
fun SttScreen() {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val sttVm: SttViewModel = viewModel()
    val modelVm: ModelSelectionViewModel =
        viewModel(factory = ModelSelectionViewModel.Factory(ModelSelectionContext.STT))
    var showSheet by remember { mutableStateOf(false) }
    var showProviderPicker by remember { mutableStateOf(false) }

    val model = modelVm.state.models.firstOrNull { it.id == modelVm.state.currentModelId }
    val busy = sttVm.isRecording || sttVm.isTranscribing
    val onlineLabel = CloudProviderRepository.labelFor(sttVm.onlineProviderId) ?: "Add a cloud provider"

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> if (granted) sttVm.toggle(modelVm.state.currentModelId) }

    fun onRecord() {
        if (model == null) return
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) sttVm.toggle(modelVm.state.currentModelId) else permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .readableWidth()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Header(mode = sttVm.mode)

        ModeSelector(mode = sttVm.mode, enabled = !busy, onSelect = sttVm::selectMode)

        if (sttVm.mode == SttMode.HYBRID) {
            ModelCard("On-device model", model?.name, RACIcons.Outline.Brain) { showSheet = true }
            ModelCard("Cloud model", onlineLabel, RACIcons.Outline.Cloud) { showProviderPicker = true }
            PolicyCard(sttVm)
        } else {
            ModelCard("Model", model?.name, RACIcons.Outline.Brain) { showSheet = true }
        }

        RecordButton(
            recording = sttVm.isRecording,
            enabled = model != null && !sttVm.isTranscribing,
            onClick = ::onRecord,
        )

        StatusLine(sttVm = sttVm, hasModel = model != null)

        when {
            sttVm.transcript.isNotBlank() -> LabeledCard("Transcript") {
                Text(text = sttVm.transcript, style = MaterialTheme.typography.bodyLarge)
            }
            sttVm.metrics != null && !sttVm.isRecording && !sttVm.isTranscribing -> LabeledCard("Transcript") {
                Text(
                    text = "No speech recognized.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        sttVm.routing?.let { routing ->
            LabeledCard("Routing") { RoutingRows(routing) }
        }

        sttVm.metrics?.let { metrics ->
            LabeledCard("Audio stats") { StatRows(metrics) }
        }

        sttVm.error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
    }

    if (showSheet) {
        ModelSelectionSheet(viewModel = modelVm, onDismiss = { showSheet = false })
    }

    if (showProviderPicker) {
        CloudProviderPicker(
            selectedId = sttVm.onlineProviderId,
            onSelect = {
                sttVm.selectOnlineProvider(it)
                showProviderPicker = false
            },
            onDismiss = { showProviderPicker = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CloudProviderPicker(
    selectedId: String?,
    onSelect: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val dimens = LocalDimens.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val options = CloudProviderRepository.providers.map { it.id to "${it.label} · ${it.preset.label}" }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = dimens.radiusLg, topEnd = dimens.radiusLg),
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        contentWindowInsets = { WindowInsets.systemBars },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = dimens.spacingLg)
                .padding(bottom = dimens.spacingXl),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Text(
                "Cloud backend",
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(vertical = dimens.spacingMd),
            )
            if (options.isEmpty()) {
                Text(
                    "Add a provider from Advanced > Cloud providers before using hybrid transcription.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = dimens.spacingSm),
                )
            }
            options.forEach { (id, label) ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(dimens.radiusMd))
                        .clickable { onSelect(id) }
                        .padding(dimens.spacingMd),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
                ) {
                    Icon(
                        RACIcons.Outline.Cloud,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(dimens.iconMd),
                    )
                    Text(label, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                    if (id == selectedId) {
                        Icon(
                            RACIcons.Outline.Check,
                            contentDescription = "Selected",
                            tint = primaryGreen,
                            modifier = Modifier.size(dimens.iconSm),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun Header(mode: SttMode) {
    val dimens = LocalDimens.current
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
        Box(
            modifier = Modifier
                .size(64.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primaryContainer),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = RACIcons.Outline.Microphone,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
                modifier = Modifier.size(dimens.iconLg),
            )
        }
        Text("Speech to Text", style = MaterialTheme.typography.titleLarge)
        Text(
            text = when (mode) {
                SttMode.BATCH -> "Tap record, speak, then tap again to transcribe — all on-device."
                SttMode.LIVE -> "Live mode transcribes each phrase as you pause. Tap to start."
                SttMode.HYBRID -> "Hybrid runs on-device first and falls back to the cloud when unsure."
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun ModeSelector(mode: SttMode, enabled: Boolean, onSelect: (SttMode) -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusFull),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(modifier = Modifier.padding(dimens.spacingXs)) {
            SttMode.entries.forEach { option ->
                val selected = option == mode
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(dimens.radiusFull))
                        .background(if (selected) MaterialTheme.colorScheme.primary else androidx.compose.ui.graphics.Color.Transparent)
                        .clickable(enabled = enabled && !selected) { onSelect(option) }
                        .padding(vertical = dimens.spacingSm),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = when (option) {
                            SttMode.BATCH -> "Batch"
                            SttMode.LIVE -> "Live"
                            SttMode.HYBRID -> "Hybrid"
                        },
                        style = MaterialTheme.typography.labelLarge,
                        color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun RoutingRows(routing: HybridRoutedMetadata) {
    val dimens = LocalDimens.current
    val onCloud = routing.was_fallback
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
            Box(
                modifier = Modifier
                    .clip(RoundedCornerShape(dimens.radiusFull))
                    .background((if (onCloud) MaterialTheme.colorScheme.tertiary else primaryGreen).copy(alpha = 0.15f))
                    .padding(horizontal = dimens.spacingMd, vertical = dimens.spacingXs),
            ) {
                Text(
                    text = if (onCloud) "Cloud fallback" else "On-device",
                    style = MaterialTheme.typography.labelMedium,
                    color = if (onCloud) MaterialTheme.colorScheme.tertiary else primaryGreen,
                )
            }
            Text(routing.chosen_model_id, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        if (!routing.confidence.isNaN()) {
            RoutingStat("Confidence", String.format(Locale.US, "%.0f%%", routing.confidence * 100))
        }
        if (onCloud && !routing.primary_confidence.isNaN()) {
            RoutingStat("On-device score", String.format(Locale.US, "%.0f%%", routing.primary_confidence * 100))
        }
        if (routing.attempt_count > 1) RoutingStat("Attempts", routing.attempt_count.toString())
    }
}

@Composable
private fun RoutingStat(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = RACTextStyles.Metric)
    }
}

@Composable
private fun ModelCard(label: String, modelName: String?, icon: ImageVector, onClick: (() -> Unit)?) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
                .padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(modelName ?: "Select a model", style = MaterialTheme.typography.bodyLarge)
            }
            if (onClick != null) {
                Icon(
                    imageVector = RACIcons.Outline.ChevronRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(dimens.iconSm),
                )
            }
        }
    }
}

@Composable
private fun PolicyCard(vm: SttViewModel) {
    val dimens = LocalDimens.current
    LabeledCard("Routing policy") {
        Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
            Text("Priority", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            RankToggle(localFirst = vm.preferLocalFirst, onSelect = vm::onRankChange)

            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Require network for cloud", style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
                Switch(checked = vm.requireNetwork, onCheckedChange = vm::onNetworkChange)
            }

            PolicySlider(
                label = "Min battery for cloud",
                valueText = "${vm.minBattery.toInt()}%",
                value = vm.minBattery,
                valueRange = 0f..100f,
                onValueChange = vm::onBatteryChange,
            )
            PolicySlider(
                label = "Cloud fallback below",
                valueText = "${(vm.confidenceThreshold * 100).toInt()}% confidence",
                value = vm.confidenceThreshold,
                valueRange = 0f..1f,
                onValueChange = vm::onConfidenceChange,
            )
        }
    }
}

@Composable
private fun RankToggle(localFirst: Boolean, onSelect: (Boolean) -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHighest,
        shape = RoundedCornerShape(dimens.radiusFull),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(modifier = Modifier.padding(dimens.spacingXs)) {
            listOf(true to "Local first", false to "Online first").forEach { (value, label) ->
                val selected = value == localFirst
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .clip(RoundedCornerShape(dimens.radiusFull))
                        .background(if (selected) MaterialTheme.colorScheme.primary else androidx.compose.ui.graphics.Color.Transparent)
                        .clickable(enabled = !selected) { onSelect(value) }
                        .padding(vertical = dimens.spacingSm),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        label,
                        style = MaterialTheme.typography.labelLarge,
                        color = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun PolicySlider(
    label: String,
    valueText: String,
    value: Float,
    valueRange: ClosedFloatingPointRange<Float>,
    onValueChange: (Float) -> Unit,
) {
    Column {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, style = MaterialTheme.typography.bodyMedium)
            Text(valueText, style = RACTextStyles.Metric, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Slider(value = value, onValueChange = onValueChange, valueRange = valueRange)
    }
}

@Composable
private fun RecordButton(recording: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val color = when {
        !enabled -> MaterialTheme.colorScheme.surfaceContainerHighest
        recording -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.primary
    }
    Box(
        modifier = Modifier
            .padding(top = 8.dp)
            .size(96.dp)
            .clip(CircleShape)
            .background(color)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = if (recording) RACIcons.Outline.PlayerStop else RACIcons.Outline.Microphone,
            contentDescription = if (recording) "Stop" else "Record",
            tint = MaterialTheme.colorScheme.onPrimary,
            modifier = Modifier.size(40.dp),
        )
    }
}

@Composable
private fun StatusLine(sttVm: SttViewModel, hasModel: Boolean) {
    val dimens = LocalDimens.current
    when {
        sttVm.isRecording -> Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            LevelBars(level = sttVm.audioLevel)
            Text(
                text = if (sttVm.mode == SttMode.LIVE) "Listening — pause to transcribe" else "Recording…",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        sttVm.isTranscribing -> Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            CircularProgressIndicator(modifier = Modifier.size(dimens.iconSm), strokeWidth = 2.dp)
            Text("Transcribing…", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        else -> Text(
            text = if (hasModel) "Tap to record" else "Select a model to begin",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun LevelBars(level: Float) {
    val dimens = LocalDimens.current
    val active = (level * BAR_COUNT).toInt()
    Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs), verticalAlignment = Alignment.CenterVertically) {
        repeat(BAR_COUNT) { index ->
            Box(
                modifier = Modifier
                    .size(width = 5.dp, height = (8 + index * 2).dp)
                    .clip(RoundedCornerShape(dimens.radiusFull))
                    .background(if (index < active) primaryGreen else MaterialTheme.colorScheme.surfaceContainerHighest),
            )
        }
    }
}

@Composable
private fun LabeledCard(title: String, content: @Composable () -> Unit) {
    val dimens = LocalDimens.current
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) {
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shape = RoundedCornerShape(dimens.radiusLg),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(modifier = Modifier.padding(dimens.spacingLg)) { content() }
        }
    }
}

@Composable
private fun StatRows(metrics: SttMetrics) {
    val dimens = LocalDimens.current
    val rows = buildList {
        add("Words" to metrics.words.toString())
        add("Audio length" to String.format(Locale.US, "%.1fs", metrics.audioSec))
        add("Processing" to "${metrics.processingMs}ms")
        metrics.realTimeFactor?.let { add("Real-time factor" to String.format(Locale.US, "%.2f×", it)) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
        rows.forEach { (label, value) ->
            Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(value, style = RACTextStyles.Metric)
            }
        }
    }
}

private const val BAR_COUNT = 12
