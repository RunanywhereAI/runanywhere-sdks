package com.runanywhere.runanywhereai.presentation.stt

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.ui.graphics.Brush
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.presentation.chat.components.ModelLoadedToast
import com.runanywhere.runanywhereai.presentation.chat.components.ModelRequiredOverlay
import com.runanywhere.runanywhereai.presentation.components.ConfigureTopBar
import com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.util.getModelLogoResIdForName
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import kotlinx.coroutines.launch

/**
 * Speech to Text Screen
 *
 * Features:
 * - Batch mode: Record full audio then transcribe
 * - Live mode: Real-time streaming transcription
 * - Recording button with RED color when recording
 * - Audio level visualization with GREEN bars
 * - Model status banner
 * - Transcription display
 */
@Composable
fun SpeechToTextScreen(
    onBack: () -> Unit = {},
    viewModel: SpeechToTextViewModel = viewModel(),
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var showModelPicker by remember { mutableStateOf(false) }
    var showModelLoadedToast by remember { mutableStateOf(false) }
    var loadedModelToastName by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    // Initialize ViewModel with context
    LaunchedEffect(Unit) {
        viewModel.initialize(context)
    }

    // Permission launcher - start recording after permission granted
    val permissionLauncher =
        rememberLauncherForActivityResult(
            contract = ActivityResultContracts.RequestPermission(),
        ) { isGranted ->
            if (isGranted) {
                viewModel.initialize(context)
                viewModel.toggleRecording()
            }
        }

    ConfigureTopBar(
        title = "Speech to Text",
        showBack = true,
        onBack = onBack,
        actions = {
            if (uiState.isModelLoaded) {
                Surface(
                    onClick = { showModelPicker = true },
                    shape = RoundedCornerShape(50),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                ) {
                    STTModelChip(
                        modelName = uiState.selectedModelName,
                        mode = uiState.mode,
                        modifier = Modifier.padding(
                            start = 6.dp,
                            end = 12.dp,
                            top = 6.dp,
                            bottom = 6.dp,
                        ),
                    )
                }
            }
        },
    )

    Box(
        modifier =
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            if (uiState.isModelLoaded) {
                STTModeSelector(
                    selectedMode = uiState.mode,
                    supportsLiveMode = uiState.supportsLiveMode,
                    onModeChange = { viewModel.setMode(it) },
                )

                TranscriptionArea(
                    transcription = uiState.transcription,
                    isRecording = uiState.recordingState == RecordingState.RECORDING,
                    isTranscribing = uiState.isTranscribing || uiState.recordingState == RecordingState.PROCESSING,
                    metrics = uiState.metrics,
                    mode = uiState.mode,
                    modifier = Modifier.weight(1f),
                )

                uiState.errorMessage?.let { error ->
                    Text(
                        text = error,
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.statusRed,
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .padding(horizontal = 16.dp),
                        textAlign = TextAlign.Center,
                    )
                }

                // Audio level indicator - green bars
                if (uiState.recordingState == RecordingState.RECORDING) {
                    AudioLevelIndicator(
                        audioLevel = uiState.audioLevel,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    )
                }

                // Controls section
                ControlsSection(
                    recordingState = uiState.recordingState,
                    audioLevel = uiState.audioLevel,
                    isModelLoaded = uiState.isModelLoaded,
                    onToggleRecording = {
                        // Check if permission is already granted
                        val hasPermission =
                            ContextCompat.checkSelfPermission(
                                context,
                                Manifest.permission.RECORD_AUDIO,
                            ) == PackageManager.PERMISSION_GRANTED

                        if (hasPermission) {
                            // Permission already granted, toggle recording directly
                            viewModel.toggleRecording()
                        } else {
                            // Request permission, toggleRecording will be called in callback
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    },
                )
            }
        }

        if (!uiState.isModelLoaded && uiState.recordingState != RecordingState.PROCESSING) {
            ModelRequiredOverlay(
                modality = ModelSelectionContext.STT,
                onSelectModel = { showModelPicker = true },
                modifier = Modifier.matchParentSize(),
            )
        }

        // Model loaded toast overlay
        ModelLoadedToast(
            modelName = loadedModelToastName,
            isVisible = showModelLoadedToast,
            onDismiss = { showModelLoadedToast = false },
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }

    if (showModelPicker) {
        ModelSelectionBottomSheet(
            context = ModelSelectionContext.STT,
            onDismiss = { showModelPicker = false },
            onModelSelected = { model ->
                scope.launch {
                    // Update ViewModel with model info AND mark as loaded
                    // The model was already loaded by ModelSelectionViewModel.selectModel()
                    viewModel.onModelLoaded(
                        modelName = model.name,
                        modelId = model.id,
                        framework = model.framework,
                    )
                    // Show model loaded toast
                    loadedModelToastName = model.name
                    showModelLoadedToast = true
                }
            },
        )
    }
}

/**
 * Mode Description text
 * iOS Reference: Mode description under segmented control
 */
@Composable
private fun ModeDescription(
    mode: STTMode,
    supportsLiveMode: Boolean,
) {
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector =
                when (mode) {
                    STTMode.BATCH -> Icons.Filled.GraphicEq
                    STTMode.LIVE -> Icons.Filled.Waves
                },
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(16.dp),
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text =
                when (mode) {
                    STTMode.BATCH -> "Record audio, then transcribe all at once"
                    STTMode.LIVE -> "Real-time transcription as you speak"
                },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        // Show warning if live mode not supported
        if (!supportsLiveMode && mode == STTMode.LIVE) {
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "(will use batch)",
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.primaryOrange,
            )
        }
    }
}

/**
 * Ready state - iOS: breathing waveform (5 bars gradient) + "Ready to transcribe" + subtitle by mode
 */
@Composable
private fun ReadyStateSTT(mode: STTMode) {
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
                                colors = listOf(
                                    AppColors.primaryAccent.copy(alpha = 0.8f),
                                    AppColors.primaryAccent.copy(alpha = 0.4f),
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
                text = "Ready to transcribe",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = if (mode == STTMode.BATCH) "Record first, then transcribe" else "Real-time transcription",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Transcription display area
 * iOS Reference: Transcription ScrollView in SpeechToTextView
 */
@Composable
private fun TranscriptionArea(
    transcription: String,
    isRecording: Boolean,
    isTranscribing: Boolean,
    metrics: TranscriptionMetrics?,
    mode: STTMode,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier =
            modifier
                .fillMaxWidth()
                .padding(16.dp),
        contentAlignment = Alignment.Center,
    ) {
        when {
            transcription.isEmpty() && !isRecording && !isTranscribing -> {
                ReadyStateSTT(mode = mode)
            }

            isTranscribing && transcription.isEmpty() -> {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.scale(1.2f).size(48.dp),
                        strokeWidth = 4.dp,
                        color = MaterialTheme.colorScheme.primary,
                    )
                    Text(
                        text = "Transcribing...",
                        style = MaterialTheme.typography.bodyLarge,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            else -> {
                // Transcription display
                Column(
                    modifier = Modifier.fillMaxSize(),
                ) {
                    // Header with status badge
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "Transcription",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )

                        // Status badge: RECORDING/TRANSCRIBING
                        if (isRecording) {
                            RecordingBadge()
                        } else if (isTranscribing) {
                            TranscribingBadge()
                        }
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    // Transcription text box
                    Surface(
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .weight(1f),
                        shape = RoundedCornerShape(12.dp),
                        color = MaterialTheme.colorScheme.surfaceVariant,
                    ) {
                        Text(
                            text = transcription.ifEmpty { "Listening..." },
                            style = MaterialTheme.typography.bodyLarge,
                            modifier =
                                Modifier
                                    .padding(16.dp)
                                    .verticalScroll(rememberScrollState()),
                            color =
                                if (transcription.isEmpty()) {
                                    MaterialTheme.colorScheme.onSurfaceVariant
                                } else {
                                    MaterialTheme.colorScheme.onSurface
                                },
                        )
                    }

                    // Metrics display - only show when we have results and not recording
                    if (metrics != null && transcription.isNotEmpty() && !isRecording && !isTranscribing) {
                        Spacer(modifier = Modifier.height(12.dp))
                        TranscriptionMetricsBar(metrics = metrics)
                    }
                }
            }
        }
    }
}

/**
 * Metrics bar showing transcription statistics
 * Clean, minimal design that doesn't distract from the transcription
 */
@Composable
private fun TranscriptionMetricsBar(metrics: TranscriptionMetrics) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 1.dp,
    ) {
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 12.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceEvenly,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Words count
            MetricItem(
                icon = Icons.Outlined.TextFields,
                value = "${metrics.wordCount}",
                label = "words",
                color = AppColors.primaryAccent,
            )

            MetricDivider()

            // Audio duration
            if (metrics.audioDurationMs > 0) {
                MetricItem(
                    icon = Icons.Outlined.Timer,
                    value = formatDuration(metrics.audioDurationMs),
                    label = "duration",
                    color = AppColors.primaryGreen,
                )

                MetricDivider()
            }

            // Inference time
            if (metrics.inferenceTimeMs > 0) {
                MetricItem(
                    icon = Icons.Outlined.Speed,
                    value = "${metrics.inferenceTimeMs.toLong()}ms",
                    label = "inference",
                    color = AppColors.primaryOrange,
                )

                MetricDivider()
            }

            // Real-time factor (only for batch mode with valid duration)
            if (metrics.audioDurationMs > 0 && metrics.inferenceTimeMs > 0) {
                val rtf = metrics.inferenceTimeMs / metrics.audioDurationMs
                MetricItem(
                    icon = Icons.Outlined.Analytics,
                    value = String.format("%.2fx", rtf),
                    label = "RTF",
                    color = if (rtf < 1.0) AppColors.primaryGreen else AppColors.primaryOrange,
                )
            } else if (metrics.confidence > 0) {
                // Show confidence for live mode
                MetricItem(
                    icon = Icons.Outlined.CheckCircle,
                    value = "${(metrics.confidence * 100).toInt()}%",
                    label = "confidence",
                    color =
                        when {
                            metrics.confidence >= 0.8f -> AppColors.primaryGreen
                            metrics.confidence >= 0.5f -> AppColors.primaryOrange
                            else -> Color.Red
                        },
                )
            }
        }
    }
}

@Composable
private fun MetricItem(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    value: String,
    label: String,
    color: Color,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(14.dp),
            tint = color.copy(alpha = 0.8f),
        )
        Column {
            Text(
                text = value,
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
            )
        }
    }
}

@Composable
private fun MetricDivider() {
    Box(
        modifier =
            Modifier
                .width(1.dp)
                .height(24.dp)
                .background(MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f)),
    )
}

private fun formatDuration(ms: Double): String {
    val totalSeconds = (ms / 1000).toLong()
    val minutes = totalSeconds / 60
    val seconds = totalSeconds % 60
    return if (minutes > 0) {
        "${minutes}m ${seconds}s"
    } else {
        "${seconds}s"
    }
}

/**
 * Recording badge - iOS style red recording indicator
 */
@Composable
private fun RecordingBadge() {
    val infiniteTransition = rememberInfiniteTransition(label = "recording_pulse")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 0.5f,
        animationSpec =
            infiniteRepeatable(
                animation = tween(500),
                repeatMode = RepeatMode.Reverse,
            ),
        label = "badge_pulse",
    )

    Surface(
        shape = RoundedCornerShape(4.dp),
        color = AppColors.statusRed.copy(alpha = 0.1f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier =
                    Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(AppColors.statusRed.copy(alpha = alpha)),
            )
            Text(
                text = "RECORDING",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = AppColors.statusRed,
            )
        }
    }
}

/**
 * Transcribing badge - iOS style orange processing indicator
 */
@Composable
private fun TranscribingBadge() {
    Surface(
        shape = RoundedCornerShape(4.dp),
        color = AppColors.primaryOrange.copy(alpha = 0.1f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CircularProgressIndicator(
                modifier = Modifier.size(10.dp),
                strokeWidth = 1.5.dp,
                color = AppColors.primaryOrange,
            )
            Text(
                text = "TRANSCRIBING",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = AppColors.primaryOrange,
            )
        }
    }
}

/**
 * Audio level indicator - GREEN bars matching iOS exactly
 * iOS Reference: Audio level indicator bars in SpeechToTextView
 */
@Composable
private fun AudioLevelIndicator(
    audioLevel: Float,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val barsCount = 10
        val activeBars = (audioLevel * barsCount).toInt()

        repeat(barsCount) { index ->
            val isActive = index < activeBars
            val barColor by animateColorAsState(
                targetValue = if (isActive) AppColors.primaryGreen else AppColors.statusGray.copy(alpha = 0.3f),
                animationSpec = tween(100),
                label = "bar_color_$index",
            )

            Box(
                modifier =
                    Modifier
                        .padding(horizontal = 2.dp)
                        .width(25.dp)
                        .height(8.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(barColor),
            )
        }
    }
}

/**
 * Controls Section with recording button
 */
@Composable
private fun ControlsSection(
    recordingState: RecordingState,
    audioLevel: Float,
    isModelLoaded: Boolean,
    onToggleRecording: () -> Unit,
) {
    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(16.dp)
                .background(MaterialTheme.colorScheme.background),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Recording button - RED when recording
        RecordingButton(
            recordingState = recordingState,
            audioLevel = audioLevel,
            onToggleRecording = onToggleRecording,
            enabled = isModelLoaded && recordingState != RecordingState.PROCESSING,
        )

        // Status text
        Text(
            text =
                when (recordingState) {
                    RecordingState.IDLE -> "Tap to start recording"
                    RecordingState.RECORDING -> "Tap to stop recording"
                    RecordingState.PROCESSING -> "Processing transcription..."
                },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * STT app bar model chip - same style as ChatTopBar: pill Surface, model icon + name + Streaming/Batch.
 */
@Composable
private fun STTModelChip(
    modelName: String?,
    mode: STTMode,
    modifier: Modifier = Modifier,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier,
    ) {
        if (modelName != null) {
            Box(
                modifier = Modifier
                    .size(30.dp)
                    .clip(RoundedCornerShape(6.dp)),
            ) {
                Image(
                    painter = painterResource(id = getModelLogoResIdForName(modelName)),
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Fit,
                )
            }

            Spacer(modifier = Modifier.width(8.dp))

            Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(
                    text = shortModelNameSTT(modelName, maxLength = 12),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Icon(
                        imageVector = if (mode == STTMode.LIVE) Icons.Default.Bolt else Icons.Default.Stop,
                        contentDescription = null,
                        modifier = Modifier.size(10.dp),
                        tint = if (mode == STTMode.LIVE) AppColors.primaryGreen else AppColors.primaryOrange,
                    )
                    Text(
                        text = if (mode == STTMode.LIVE) "Streaming" else "Batch",
                        style = MaterialTheme.typography.labelSmall.copy(
                            fontSize = 10.sp,
                            fontWeight = FontWeight.Medium,
                        ),
                        color = if (mode == STTMode.LIVE) AppColors.primaryGreen else AppColors.primaryOrange,
                    )
                }
            }
        } else {
            Icon(
                imageVector = Icons.Default.ViewInAr,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = AppColors.primaryAccent,
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = "Select Model",
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

private fun shortModelNameSTT(name: String, maxLength: Int = 15): String {
    val cleaned = name.replace(Regex("\\s*\\([^)]*\\)"), "").trim()
    return if (cleaned.length > maxLength) cleaned.take(maxLength - 1) + "\u2026" else cleaned
}

/**
 * Model Status Banner for STT (kept for reference; not used when app bar shows model)
 */
@Composable
private fun ModelStatusBannerSTT(
    framework: String?,
    modelName: String?,
    isLoading: Boolean,
    onSelectModel: () -> Unit,
) {
    Surface(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 2.dp,
                )
                Text(
                    text = "Loading model...",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else if (framework != null && modelName != null) {
                // Model loaded state
                Icon(
                    imageVector = Icons.Filled.GraphicEq,
                    contentDescription = null,
                    tint = AppColors.primaryGreen,
                    modifier = Modifier.size(18.dp),
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = framework,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = modelName,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                    )
                }
                OutlinedButton(
                    onClick = onSelectModel,
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                ) {
                    Text("Change", style = MaterialTheme.typography.labelMedium)
                }
            } else {
                // No model state
                Icon(
                    imageVector = Icons.Filled.Warning,
                    contentDescription = null,
                    tint = AppColors.primaryOrange,
                )
                Text(
                    text = "No model selected",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                Button(
                    onClick = onSelectModel,
                    colors =
                        ButtonDefaults.buttonColors(
                            containerColor = AppColors.primaryAccent,
                        ),
                ) {
                    Icon(
                        Icons.Filled.Apps,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Select Model")
                }
            }
        }
    }
}

/**
 * STT Mode Selector (Batch / Live) - iOS pill style with subtitle
 * iOS: padding horizontal 16, top 12, bottom 8; selected = primaryAccent 0.15 bg + border 0.3
 */
@Composable
private fun STTModeSelector(
    selectedMode: STTMode,
    @Suppress("UNUSED_PARAMETER") supportsLiveMode: Boolean,
    onModeChange: (STTMode) -> Unit,
) {
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        STTMode.entries.forEach { mode ->
            val isSelected = mode == selectedMode
            Surface(
                modifier =
                    Modifier
                        .weight(1f)
                        .clickable { onModeChange(mode) },
                shape = RoundedCornerShape(12.dp),
                color = if (isSelected) AppColors.primaryAccent.copy(alpha = 0.15f) else Color.Transparent,
                border =
                    androidx.compose.foundation.BorderStroke(
                        1.dp,
                        if (isSelected) AppColors.primaryAccent.copy(alpha = 0.3f)
                        else AppColors.statusGray.copy(alpha = 0.2f),
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
                        color = if (isSelected) AppColors.primaryAccent else MaterialTheme.colorScheme.onSurfaceVariant,
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

/**
 * Recording Button - RED when recording (matching iOS exactly)
 * iOS Reference: Recording button in SpeechToTextView
 * iOS Color States: Blue (idle) → Red (recording) → Orange (transcribing)
 */
@Composable
private fun RecordingButton(
    recordingState: RecordingState,
    @Suppress("UNUSED_PARAMETER") audioLevel: Float,
    onToggleRecording: () -> Unit,
    enabled: Boolean = true,
) {
    val infiniteTransition = rememberInfiniteTransition(label = "recording_pulse")
    val scale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.15f,
        animationSpec =
            infiniteRepeatable(
                animation = tween(600, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
        label = "pulse_scale",
    )

    // Color states: Blue when idle, RED when recording, Orange when transcribing
    val buttonColor by animateColorAsState(
        targetValue =
            when (recordingState) {
                RecordingState.IDLE -> AppColors.primaryAccent
                RecordingState.RECORDING -> AppColors.primaryRed // RED when recording
                RecordingState.PROCESSING -> AppColors.primaryOrange
            },
        animationSpec = tween(300),
        label = "button_color",
    )

    val buttonIcon =
        when (recordingState) {
            RecordingState.IDLE -> Icons.Filled.Mic
            RecordingState.RECORDING -> Icons.Filled.Stop
            RecordingState.PROCESSING -> Icons.Filled.Sync
        }

    // Button size: 72dp
    Box(
        contentAlignment = Alignment.Center,
        modifier =
            Modifier
                .size(88.dp) // Container for button + pulse ring
                .scale(if (recordingState == RecordingState.RECORDING) scale else 1f),
    ) {
        // Pulsing ring when recording - RED
        if (recordingState == RecordingState.RECORDING) {
            Box(
                modifier =
                    Modifier
                        // Slightly larger than button for pulse effect
                        .size(84.dp)
                        .border(
                            width = 2.dp,
                            // RED ring
                            color = AppColors.primaryRed.copy(alpha = 0.3f),
                            shape = CircleShape,
                        )
                        .scale(scale * 1.1f),
            )
        }

        // Main button - 72dp
        Surface(
            modifier =
                Modifier
                    .size(72.dp)
                    .clickable(
                        enabled = enabled,
                        onClick = onToggleRecording,
                    ),
            shape = CircleShape,
            color = buttonColor,
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxSize(),
            ) {
                if (recordingState == RecordingState.PROCESSING) {
                    // Icon size
                    CircularProgressIndicator(
                        modifier = Modifier.size(32.dp),
                        color = Color.White,
                        strokeWidth = 3.dp,
                    )
                } else {
                    // 32dp icon
                    Icon(
                        imageVector = buttonIcon,
                        contentDescription =
                            when (recordingState) {
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
