package com.runanywhere.runanywhereai.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.models.RecordingState
import com.runanywhere.runanywhereai.models.STTMode
import com.runanywhere.runanywhereai.models.STTUiState
import com.runanywhere.runanywhereai.models.TranscriptionMetrics
import com.runanywhere.runanywhereai.ui.components.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.components.RAButton
import com.runanywhere.runanywhereai.ui.components.RAButtonStyle
import com.runanywhere.runanywhereai.ui.components.RACard
import com.runanywhere.runanywhereai.ui.icons.RAIcons
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.viewmodels.ModelSelectionViewModel
import com.runanywhere.runanywhereai.viewmodels.STTViewModel
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import com.runanywhere.sdk.public.extensions.loadSTTModel
import kotlinx.coroutines.launch

@Composable
fun SpeechToTextScreen(
    onBack: () -> Unit,
    viewModel: STTViewModel = viewModel(),
    modelSelectionViewModel: ModelSelectionViewModel = viewModel(),
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val modelState by modelSelectionViewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var showModelSheet by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { viewModel.initialize(context) }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { isGranted ->
        if (isGranted) {
            viewModel.initialize(context)
            viewModel.toggleRecording()
        }
    }

    when (val state = uiState) {
        is STTUiState.Loading -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        is STTUiState.Ready -> {
            STTReadyContent(
                state = state,
                viewModel = viewModel,
                onToggleRecording = {
                    val hasPermission = ContextCompat.checkSelfPermission(
                        context, Manifest.permission.RECORD_AUDIO,
                    ) == PackageManager.PERMISSION_GRANTED
                    if (hasPermission) viewModel.toggleRecording()
                    else permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                },
                onSelectModel = {
                    modelSelectionViewModel.loadModels(ModelSelectionContext.STT)
                    showModelSheet = true
                },
            )
        }
        is STTUiState.Error -> {
            Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Text(text = state.message, color = MaterialTheme.colorScheme.error)
            }
        }
    }

    // Model selection bottom sheet
    if (showModelSheet) {
        ModelSelectionSheet(
            state = modelState,
            onDismiss = { showModelSheet = false },
            onSelectModel = { modelId ->
                modelSelectionViewModel.selectModel(modelId) { name, _ ->
                    scope.launch {
                        try {
                            RunAnywhere.loadSTTModel(modelId)
                            viewModel.onModelLoaded(modelName = name, modelId = modelId, framework = null)
                        } catch (_: Exception) { }
                    }
                }
            },
            onDownloadModel = { modelSelectionViewModel.downloadModel(it) },
            onCancelModelDownload = { modelSelectionViewModel.cancelModelDownload() },
            onLoadLora = { },
            onUnloadLora = { },
            onDownloadLora = { },
            onCancelLoraDownload = { },
            isLoraDownloaded = { false },
            isLoraLoaded = { false },
        )
    }
}

@Composable
private fun STTReadyContent(
    state: STTUiState.Ready,
    viewModel: STTViewModel,
    onToggleRecording: () -> Unit,
    onSelectModel: () -> Unit,
) {
    val isRecording by remember(state.recordingState) {
        derivedStateOf { state.recordingState == RecordingState.RECORDING }
    }
    val isProcessing by remember(state.recordingState) {
        derivedStateOf { state.recordingState == RecordingState.PROCESSING }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // Model status
        if (!state.isModelLoaded) {
            RACard(modifier = Modifier.padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = RAIcons.AlertCircle,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.error,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text("No STT model loaded", style = MaterialTheme.typography.bodyLarge)
                        Text(
                            "Select a speech recognition model to get started",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Spacer(Modifier.width(8.dp))
                    RAButton(
                        text = "Select Model",
                        onClick = onSelectModel,
                        icon = RAIcons.Download,
                        style = RAButtonStyle.Tonal,
                    )
                }
            }
        } else {
            // Model loaded status with change button
            RACard(
                modifier = Modifier.padding(16.dp),
                containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = RAIcons.Mic,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(20.dp),
                    )
                    Spacer(Modifier.width(12.dp))
                    Column(Modifier.weight(1f)) {
                        Text(
                            state.selectedModelName ?: "STT Model",
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.Medium,
                        )
                        Text(
                            "On-device",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    RAButton(
                        text = "Change",
                        onClick = onSelectModel,
                        icon = RAIcons.Settings,
                        style = RAButtonStyle.Tonal,
                    )
                }
            }
        }

        // Mode selector
        if (state.isModelLoaded) {
            STTModeSelector(
                selectedMode = state.mode,
                onModeChange = { viewModel.setMode(it) },
            )
        }

        // Transcription area
        Box(
            modifier = Modifier.weight(1f).fillMaxWidth().padding(16.dp),
            contentAlignment = Alignment.Center,
        ) {
            when {
                state.transcription.isEmpty() && !isRecording && !state.isTranscribing -> {
                    ReadyStateContent(mode = state.mode)
                }
                state.isTranscribing && state.transcription.isEmpty() -> {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(48.dp), strokeWidth = 4.dp)
                        Text("Transcribing...", style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                else -> {
                    TranscriptionDisplay(
                        transcription = state.transcription,
                        isRecording = isRecording,
                        isTranscribing = state.isTranscribing,
                        metrics = state.metrics,
                    )
                }
            }
        }

        // Error message
        state.error?.let { error ->
            Text(
                text = error,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                textAlign = TextAlign.Center,
            )
        }

        // Audio level indicator
        if (isRecording) {
            AudioLevelIndicator(
                audioLevel = state.audioLevel,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }

        // Controls
        Column(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            RecordingButton(
                recordingState = state.recordingState,
                onToggle = onToggleRecording,
                enabled = state.isModelLoaded && !isProcessing,
            )

            Text(
                text = when (state.recordingState) {
                    RecordingState.IDLE -> "Tap to start recording"
                    RecordingState.RECORDING -> "Tap to stop recording"
                    RecordingState.PROCESSING -> "Processing transcription..."
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// -- Mode Selector ------------------------------------------------------------

@Composable
private fun STTModeSelector(
    selectedMode: STTMode,
    onModeChange: (STTMode) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        STTMode.entries.forEach { mode ->
            val isSelected = mode == selectedMode
            Surface(
                modifier = Modifier.weight(1f).clickable { onModeChange(mode) },
                shape = RoundedCornerShape(12.dp),
                color = if (isSelected) MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.5f) else Color.Transparent,
                border = BorderStroke(
                    1.dp,
                    if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)
                    else MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f),
                ),
            ) {
                Column(
                    modifier = Modifier.padding(vertical = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = when (mode) {
                            STTMode.BATCH -> "Batch"
                            STTMode.LIVE -> "Live"
                        },
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.Medium,
                        color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = when (mode) {
                            STTMode.BATCH -> "Record then transcribe"
                            STTMode.LIVE -> "Real-time transcription"
                        },
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                    )
                }
            }
        }
    }
}

// -- Ready state (breathing waveform) -----------------------------------------

@Composable
private fun ReadyStateContent(mode: STTMode) {
    val infiniteTransition = rememberInfiniteTransition(label = "stt_breathing")
    val breathing by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(800),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "breathing",
    )
    val baseHeights = listOf(16, 24, 20, 28, 18)
    val breathingHeights = listOf(24, 40, 32, 48, 28)

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(48.dp),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            verticalAlignment = Alignment.Bottom,
        ) {
            baseHeights.forEachIndexed { index, base ->
                val h = base + (breathingHeights[index] - base) * breathing
                Box(
                    modifier = Modifier
                        .width(6.dp)
                        .height(h.toInt().dp)
                        .clip(RoundedCornerShape(8.dp))
                        .background(
                            Brush.verticalGradient(
                                listOf(
                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.8f),
                                    MaterialTheme.colorScheme.primary.copy(alpha = 0.4f),
                                ),
                            ),
                        ),
                )
            }
        }

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                "Ready to transcribe",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                if (mode == STTMode.BATCH) "Record first, then transcribe" else "Real-time transcription",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// -- Transcription display ----------------------------------------------------

@Composable
private fun TranscriptionDisplay(
    transcription: String,
    isRecording: Boolean,
    isTranscribing: Boolean,
    metrics: TranscriptionMetrics?,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Transcription", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (isRecording) RecordingBadge()
            else if (isTranscribing) TranscribingBadge()
        }

        Spacer(Modifier.height(12.dp))

        RACard(modifier = Modifier.weight(1f)) {
            Text(
                text = transcription.ifEmpty { "Listening..." },
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.verticalScroll(rememberScrollState()),
                color = if (transcription.isEmpty()) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
            )
        }

        // Metrics
        if (metrics != null && transcription.isNotEmpty() && !isRecording && !isTranscribing) {
            Spacer(Modifier.height(12.dp))
            TranscriptionMetricsBar(metrics = metrics)
        }
    }
}

@Composable
private fun RecordingBadge() {
    val infiniteTransition = rememberInfiniteTransition(label = "rec_pulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 1f, targetValue = 0.5f,
        animationSpec = infiniteRepeatable(animation = tween(500), repeatMode = RepeatMode.Reverse),
        label = "badge_pulse",
    )
    Surface(
        shape = RoundedCornerShape(4.dp),
        color = MaterialTheme.colorScheme.error.copy(alpha = 0.1f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(8.dp).clip(CircleShape)
                    .background(MaterialTheme.colorScheme.error.copy(alpha = alpha)),
            )
            Text("RECORDING", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.error)
        }
    }
}

@Composable
private fun TranscribingBadge() {
    Surface(
        shape = RoundedCornerShape(4.dp),
        color = MaterialTheme.colorScheme.tertiary.copy(alpha = 0.1f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CircularProgressIndicator(modifier = Modifier.size(10.dp), strokeWidth = 1.5.dp, color = MaterialTheme.colorScheme.tertiary)
            Text("TRANSCRIBING", style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.tertiary)
        }
    }
}

// -- Audio level indicator ----------------------------------------------------

@Composable
private fun AudioLevelIndicator(audioLevel: Float, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val barsCount = 10
        val activeBars = (audioLevel * barsCount).toInt()
        val activeColor = MaterialTheme.colorScheme.primary
        val inactiveColor = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f)

        repeat(barsCount) { index ->
            val isActive = index < activeBars
            val barColor by animateColorAsState(
                targetValue = if (isActive) activeColor else inactiveColor,
                animationSpec = tween(100),
                label = "bar_$index",
            )
            Box(
                Modifier.padding(horizontal = 2.dp)
                    .width(25.dp).height(8.dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(barColor),
            )
        }
    }
}

// -- Recording button ---------------------------------------------------------

@Composable
private fun RecordingButton(
    recordingState: RecordingState,
    onToggle: () -> Unit,
    enabled: Boolean,
) {
    val infiniteTransition = rememberInfiniteTransition(label = "rec_anim")
    val scale by infiniteTransition.animateFloat(
        initialValue = 1f, targetValue = 1.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "pulse_scale",
    )

    val buttonColor by animateColorAsState(
        targetValue = when (recordingState) {
            RecordingState.IDLE -> MaterialTheme.colorScheme.primary
            RecordingState.RECORDING -> MaterialTheme.colorScheme.error
            RecordingState.PROCESSING -> MaterialTheme.colorScheme.tertiary
        },
        animationSpec = AppMotion.tweenMedium(),
        label = "btn_color",
    )

    val buttonIcon = when (recordingState) {
        RecordingState.IDLE -> RAIcons.Mic
        RecordingState.RECORDING -> RAIcons.Stop
        RecordingState.PROCESSING -> RAIcons.Activity
    }

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(88.dp)
            .scale(if (recordingState == RecordingState.RECORDING) scale else 1f),
    ) {
        // Pulse ring when recording
        if (recordingState == RecordingState.RECORDING) {
            Box(
                Modifier.size(84.dp)
                    .clip(CircleShape)
                    .background(Color.Transparent)
                    .scale(scale * 1.1f)
                    .clip(CircleShape)
                    .background(buttonColor.copy(alpha = 0.15f)),
            )
        }

        Surface(
            modifier = Modifier.size(72.dp).clickable(enabled = enabled, onClick = onToggle),
            shape = CircleShape,
            color = buttonColor,
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.fillMaxSize()) {
                if (recordingState == RecordingState.PROCESSING) {
                    CircularProgressIndicator(modifier = Modifier.size(32.dp), color = Color.White, strokeWidth = 3.dp)
                } else {
                    Icon(
                        imageVector = buttonIcon,
                        contentDescription = when (recordingState) {
                            RecordingState.IDLE -> "Start recording"
                            RecordingState.RECORDING -> "Stop recording"
                            RecordingState.PROCESSING -> "Processing"
                        },
                        tint = Color.White,
                        modifier = Modifier.size(32.dp),
                    )
                }
            }
        }
    }
}

// -- Metrics bar --------------------------------------------------------------

@Composable
private fun TranscriptionMetricsBar(metrics: TranscriptionMetrics) {
    RACard(contentPadding = 12.dp) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            MetricItem(icon = RAIcons.FileText, value = "${metrics.wordCount}", label = "words", color = MaterialTheme.colorScheme.primary)

            MetricDivider()

            if (metrics.audioDurationMs > 0) {
                MetricItem(icon = RAIcons.Clock, value = formatDurationMs(metrics.audioDurationMs), label = "duration", color = MaterialTheme.colorScheme.secondary)
                MetricDivider()
            }

            if (metrics.inferenceTimeMs > 0) {
                MetricItem(icon = RAIcons.Zap, value = "${metrics.inferenceTimeMs.toLong()}ms", label = "inference", color = MaterialTheme.colorScheme.tertiary)
                MetricDivider()
            }

            if (metrics.audioDurationMs > 0 && metrics.inferenceTimeMs > 0) {
                val rtf = metrics.inferenceTimeMs / metrics.audioDurationMs
                MetricItem(
                    icon = RAIcons.Activity,
                    value = String.format("%.2fx", rtf),
                    label = "RTF",
                    color = if (rtf < 1.0) MaterialTheme.colorScheme.secondary else MaterialTheme.colorScheme.tertiary,
                )
            }
        }
    }
}

@Composable
private fun MetricItem(icon: ImageVector, value: String, label: String, color: Color) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(14.dp), tint = color.copy(alpha = 0.8f))
        Column {
            Text(value, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold)
            Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f))
        }
    }
}

@Composable
private fun MetricDivider() {
    Box(
        Modifier.width(1.dp).height(24.dp)
            .background(MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)),
    )
}

private fun formatDurationMs(ms: Double): String {
    val totalSeconds = (ms / 1000).toLong()
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return if (minutes > 0) "${minutes}m ${seconds}s" else "${seconds}s"
}
