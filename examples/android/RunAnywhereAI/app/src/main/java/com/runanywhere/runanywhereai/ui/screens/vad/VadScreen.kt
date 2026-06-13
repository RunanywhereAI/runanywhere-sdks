package com.runanywhere.runanywhereai.ui.screens.vad

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import com.runanywhere.runanywhereai.util.readableWidth
import java.text.DateFormat
import java.util.Date

@Composable
fun VadScreen() {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val vadVm: VadViewModel = viewModel()
    val modelVm: ModelSelectionViewModel =
        viewModel(factory = ModelSelectionViewModel.Factory(ModelSelectionContext.VAD))
    var showSheet by remember { mutableStateOf(false) }

    val model = modelVm.state.models.firstOrNull { it.id == modelVm.state.currentModelId }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> if (granted) vadVm.toggle() }

    fun onListen() {
        if (model == null) return
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) vadVm.toggle() else permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
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
        Header()

        ModelCard(modelName = model?.name) { showSheet = true }

        SpeechIndicator(
            isListening = vadVm.isListening,
            isSpeechDetected = vadVm.isSpeechDetected,
            audioLevel = vadVm.audioLevel,
        )

        ListenButton(
            listening = vadVm.isListening,
            enabled = model != null,
            onClick = ::onListen,
        )

        Text(
            text = when {
                vadVm.isListening -> "Listening for speech…"
                model != null -> "Tap to start detection"
                else -> "Select a model to begin"
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (vadVm.activityLog.isNotEmpty()) {
            ActivityLogCard(entries = vadVm.activityLog, onClear = vadVm::clearLog)
        }

        vadVm.error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
    }

    if (showSheet) {
        ModelSelectionSheet(viewModel = modelVm, onDismiss = { showSheet = false })
    }
}

@Composable
private fun Header() {
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
                imageVector = RACIcons.Outline.Activity,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
                modifier = Modifier.size(dimens.iconLg),
            )
        }
        Text("Voice Activity Detection", style = MaterialTheme.typography.titleLarge)
        Text(
            text = "Detect speech activity in real-time, all on-device.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun ModelCard(modelName: String?, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .clickable(onClick = onClick)
                .padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = RACIcons.Outline.Brain,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text("Model", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(modelName ?: "Select a model", style = MaterialTheme.typography.bodyLarge)
            }
            Icon(
                imageVector = RACIcons.Outline.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(dimens.iconSm),
            )
        }
    }
}

@Composable
private fun SpeechIndicator(isListening: Boolean, isSpeechDetected: Boolean, audioLevel: Float) {
    val dimens = LocalDimens.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(140.dp)) {
            if (isSpeechDetected) PulseRing()

            Box(
                modifier = Modifier
                    .size(100.dp)
                    .clip(CircleShape)
                    .background(
                        if (isSpeechDetected) {
                            primaryGreen.copy(alpha = 0.2f)
                        } else {
                            MaterialTheme.colorScheme.surfaceContainerHigh
                        },
                    ),
            )
            Box(
                modifier = Modifier
                    .size(60.dp)
                    .clip(CircleShape)
                    .background(
                        if (isSpeechDetected) primaryGreen else MaterialTheme.colorScheme.surfaceContainerHighest,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (isSpeechDetected) RACIcons.Outline.Microphone else RACIcons.Outline.MicrophoneOff,
                    contentDescription = null,
                    tint = if (isSpeechDetected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(dimens.iconMd),
                )
            }
        }

        Text(
            text = if (isSpeechDetected) "Speech Detected" else "Silence",
            style = MaterialTheme.typography.titleMedium,
            color = if (isSpeechDetected) primaryGreen else MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (isListening) LevelBars(level = audioLevel)
    }
}

@Composable
private fun PulseRing() {
    val transition = rememberInfiniteTransition(label = "vadPulse")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(durationMillis = 1000), RepeatMode.Restart),
        label = "vadPulseProgress",
    )
    Box(
        modifier = Modifier
            .size(120.dp)
            .scale(1f + progress * 0.3f)
            .alpha(1f - progress)
            .clip(CircleShape)
            .background(primaryGreen.copy(alpha = 0.25f)),
    )
}

@Composable
private fun ListenButton(listening: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val color = when {
        !enabled -> MaterialTheme.colorScheme.surfaceContainerHighest
        listening -> MaterialTheme.colorScheme.error
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
            imageVector = if (listening) RACIcons.Outline.PlayerStop else RACIcons.Outline.Microphone,
            contentDescription = if (listening) "Stop" else "Listen",
            tint = MaterialTheme.colorScheme.onPrimary,
            modifier = Modifier.size(40.dp),
        )
    }
}

@Composable
private fun ActivityLogCard(entries: List<VadLogEntry>, onClear: () -> Unit) {
    val dimens = LocalDimens.current
    val timeFormat = remember { DateFormat.getTimeInstance(DateFormat.MEDIUM) }
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Activity Log",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onClear) { Text("Clear") }
        }
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shape = RoundedCornerShape(dimens.radiusLg),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier.padding(dimens.spacingLg),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
            ) {
                entries.forEach { entry -> ActivityLogRow(entry, timeFormat) }
            }
        }
    }
}

@Composable
private fun ActivityLogRow(entry: VadLogEntry, timeFormat: DateFormat) {
    val dimens = LocalDimens.current
    val started = entry.type == VadActivity.SPEECH_STARTED
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        Icon(
            imageVector = if (started) RACIcons.Outline.Microphone else RACIcons.Outline.MicrophoneOff,
            contentDescription = null,
            tint = if (started) primaryGreen else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconSm),
        )
        Text(
            text = if (started) "Speech Started" else "Speech Ended",
            style = MaterialTheme.typography.bodyMedium,
            color = if (started) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = timeFormat.format(Date(entry.timestampMs)),
            style = RACTextStyles.Metric,
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

private const val BAR_COUNT = 12
