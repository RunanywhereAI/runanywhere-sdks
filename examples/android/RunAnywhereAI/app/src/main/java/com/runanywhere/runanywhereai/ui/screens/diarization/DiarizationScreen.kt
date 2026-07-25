package com.runanywhere.runanywhereai.ui.screens.diarization

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.permissions.PermissionRecoveryCard
import com.runanywhere.runanywhereai.ui.permissions.openRunAnywhereAppSettings
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import java.util.Locale
import kotlin.math.abs

/**
 * Standalone speaker-diarization (NVIDIA Sortformer) UI. Pure Compose:
 * user-supplied model import, microphone capture, and a speaker-segment timeline.
 * No inference or model logic lives here — everything routes through
 * [DiarizationViewModel] into the SDK facade.
 */
@Composable
fun DiarizationScreen(viewModel: DiarizationViewModel = viewModel()) {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    var permissionDenied by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { viewModel.refreshModelStatus() }

    DisposableEffect(viewModel) { onDispose { viewModel.cancel() } }

    // Release the mic when the Activity is backgrounded mid-recording.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, viewModel) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) viewModel.cancel()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val modelPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris ->
        if (uris.isNotEmpty()) viewModel.importAndLoadModel(uris)
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        permissionDenied = !granted
        if (granted) viewModel.toggleRecording()
    }

    fun onRecord() {
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) viewModel.toggleRecording() else permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
    ) {
        Text(
            text = "Diarization",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
        )

        modelCard(viewModel) { modelPicker.launch(arrayOf("*/*")) }
        audioCard(viewModel, onRecord = ::onRecord)

        if (viewModel.segments.isNotEmpty()) {
            resultCard(viewModel)
        }

        if (permissionDenied) {
            PermissionRecoveryCard(
                message = "Microphone access was denied. Enable it in Android settings to diarize audio.",
                onOpenSettings = context::openRunAnywhereAppSettings,
            )
        }
        viewModel.error?.let { message ->
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }
        if (viewModel.status.isNotEmpty()) {
            Text(
                text = viewModel.status,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun modelCard(viewModel: DiarizationViewModel, onPickModel: () -> Unit) {
    Card {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Model", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            Text(
                if (viewModel.isModelLoaded) "loaded" else "not loaded",
                style = MaterialTheme.typography.labelMedium,
                color = if (viewModel.isModelLoaded) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
            )
        }
        Text(
            "Sortformer weights are user-supplied and uncataloged. Pick the model bundle " +
                "(the ONNX weights and their config); the SDK imports and loads them under " +
                "the speaker-diarization category.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Button(
            onClick = onPickModel,
            enabled = !viewModel.isImportingModel,
        ) {
            if (viewModel.isImportingModel) {
                CircularProgressIndicator(modifier = Modifier.height(18.dp))
            } else {
                Text(if (viewModel.isModelLoaded) "Change model files…" else "Choose model files…")
            }
        }
    }
}

@Composable
private fun audioCard(viewModel: DiarizationViewModel, onRecord: () -> Unit) {
    Card {
        Text("Audio", style = MaterialTheme.typography.titleMedium)
        Text(
            "Record a clip with two or more speakers, then stop to diarize on-device.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (viewModel.isRecording) {
            LevelBars(level = viewModel.audioLevel)
        }
        Button(
            onClick = onRecord,
            enabled = viewModel.isModelLoaded && !viewModel.isDiarizing,
            modifier = Modifier.fillMaxWidth(),
        ) {
            when {
                viewModel.isDiarizing -> CircularProgressIndicator(modifier = Modifier.height(18.dp))
                viewModel.isRecording -> Text("Stop & diarize")
                else -> Text("Record")
            }
        }
    }
}

@Composable
private fun resultCard(viewModel: DiarizationViewModel) {
    val dimens = LocalDimens.current
    Card {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Speakers · ${viewModel.speakerCount}",
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f),
            )
            if (viewModel.processingTimeMs > 0) {
                Text(
                    "${viewModel.processingTimeMs} ms",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        viewModel.segments.forEach { segment ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
            ) {
                SpeakerChip(index = segment.speaker_index, id = segment.speaker_id)
                Text(
                    "${formatMs(segment.start_ms)} – ${formatMs(segment.end_ms)}",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    formatDuration(segment.end_ms - segment.start_ms),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun SpeakerChip(index: Int, id: String) {
    val dimens = LocalDimens.current
    val color = speakerColor(index)
    Box(
        modifier = Modifier
            .clip(RoundedCornerShape(dimens.radiusFull))
            .background(color.copy(alpha = 0.15f))
            .padding(horizontal = dimens.spacingMd, vertical = dimens.spacingXs),
    ) {
        Text(
            text = id.ifEmpty { "Speaker ${index + 1}" },
            style = MaterialTheme.typography.labelMedium,
            color = color,
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
                    .background(
                        if (index < active) {
                            MaterialTheme.colorScheme.primary
                        } else {
                            MaterialTheme.colorScheme.surfaceContainerHighest
                        },
                    ),
            )
        }
    }
}

@Composable
private fun Card(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(dimens.spacingLg),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
            content = content,
        )
    }
}

private val SPEAKER_COLORS = listOf(
    Color(0xFF4C8BF5),
    Color(0xFF34A853),
    Color(0xFFEA4335),
    Color(0xFFFBBC05),
    Color(0xFF9C27B0),
    Color(0xFF00ACC1),
)

private fun speakerColor(index: Int): Color = SPEAKER_COLORS[abs(index) % SPEAKER_COLORS.size]

private fun formatMs(ms: Long): String {
    val totalSeconds = ms / 1000.0
    val minutes = (totalSeconds / 60).toInt()
    val seconds = totalSeconds % 60
    return String.format(Locale.US, "%d:%05.2f", minutes, seconds)
}

private fun formatDuration(ms: Long): String = String.format(Locale.US, "%.1fs", ms / 1000.0)

private const val BAR_COUNT = 12
