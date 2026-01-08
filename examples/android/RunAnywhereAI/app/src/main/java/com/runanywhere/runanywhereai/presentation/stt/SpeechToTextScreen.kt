package com.runanywhere.runanywhereai.presentation.stt

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.*
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import kotlinx.coroutines.launch

/**
 * Speech to Text Screen - Matching iOS SpeechToTextView.swift exactly
 *
 * iOS Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/SpeechToTextView.swift
 *
 * Features:
 * - Batch mode: Record full audio then transcribe
 * - Live mode: Real-time streaming transcription
 * - Recording button with RED color when recording (matching iOS exactly)
 * - Audio level visualization with GREEN bars
 * - Model status banner
 * - Transcription display
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SpeechToTextScreen(viewModel: SpeechToTextViewModel = viewModel()) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var showModelPicker by remember { mutableStateOf(false) }
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

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier =
                Modifier
                    .fillMaxSize()
                    .background(MaterialTheme.colorScheme.background),
        ) {
            // Header with title
            Row(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Speech to Text",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )
            }

            // Model Status Banner - Always visible
            // iOS Reference: ModelStatusBanner component
            ModelStatusBannerSTT(
                framework = uiState.selectedFramework?.displayName,
                modelName = uiState.selectedModelName,
                isLoading = uiState.recordingState == RecordingState.PROCESSING && !uiState.isModelLoaded,
                onSelectModel = { showModelPicker = true },
            )

            // Main content - only enabled when model is selected
            if (uiState.isModelLoaded) {
                Column(
                    modifier =
                        Modifier
                            .fillMaxSize()
                            .weight(1f),
                ) {
                    // Mode selector: Batch / Live
                    // iOS Reference: ModeSelector in SpeechToTextView
                    STTModeSelector(
                        selectedMode = uiState.mode,
                        supportsLiveMode = uiState.supportsLiveMode,
                        onModeChange = { viewModel.setMode(it) },
                    )

                    // Mode description
                    ModeDescription(
                        mode = uiState.mode,
                        supportsLiveMode = uiState.supportsLiveMode,
                    )

                    HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

                    // Transcription display area
                    TranscriptionArea(
                        transcription = uiState.transcription,
                        isRecording = uiState.recordingState == RecordingState.RECORDING,
                        isTranscribing = uiState.isTranscribing || uiState.recordingState == RecordingState.PROCESSING,
                        metrics = uiState.metrics,
                        modifier = Modifier.weight(1f),
                    )

                    // Error message
                    uiState.errorMessage?.let { error ->
                        Text(
                            text = error,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                            modifier =
                                Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 16.dp),
                            textAlign = TextAlign.Center,
                        )
                    }

                    // Audio level indicator - iOS style green bars
                    // iOS Reference: Audio level indicator in SpeechToTextView
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
            } else {
                // No model selected - show spacer
                Spacer(modifier = Modifier.weight(1f))
            }
        }

        // Overlay when no model is selected
        // iOS Reference: ModelRequiredOverlay component
        if (!uiState.isModelLoaded && uiState.recordingState != RecordingState.PROCESSING) {
            ModelRequiredOverlaySTT(
                onSelectModel = { showModelPicker = true },
            )
        }

        // Model picker bottom sheet - Full-screen with framework/model hierarchy
        // iOS Reference: ModelSelectionSheet(context: .stt)
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
                        android.util.Log.d("SpeechToTextScreen", "STT model selected: ${model.name}")
                    }
                },
            )
        }
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
 * Transcription display area
 * iOS Reference: Transcription ScrollView in SpeechToTextView
 */
@Composable
private fun TranscriptionArea(
    transcription: String,
    isRecording: Boolean,
    isTranscribing: Boolean,
    metrics: TranscriptionMetrics?,
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
                // Ready state - iOS Reference: Ready state view
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    Icon(
                        imageVector = Icons.Filled.Mic,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = AppColors.primaryGreen.copy(alpha = 0.5f),
                    )
                    Text(
                        text = "Ready to transcribe",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = "Tap the microphone button to start recording",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        textAlign = TextAlign.Center,
                    )
                }
            }

            isTranscribing && transcription.isEmpty() -> {
                // Processing state - iOS Reference: Processing state (batch mode)
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(48.dp),
                        strokeWidth = 4.dp,
                        color = AppColors.primaryGreen,
                    )
                    Text(
                        text = "Processing audio...",
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = "Transcribing your recording",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            else -> {
                // Transcription display - iOS Reference: Live transcription view
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

                        // Status badge - iOS Reference: RECORDING/TRANSCRIBING badge
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
        color = Color.Red.copy(alpha = 0.1f),
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
                        .background(Color.Red.copy(alpha = alpha)),
            )
            Text(
                text = "RECORDING",
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Bold,
                color = Color.Red,
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
                targetValue = if (isActive) AppColors.primaryGreen else Color.Gray.copy(alpha = 0.3f),
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
        // Recording button - RED when recording (matching iOS exactly)
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
 * Model Status Banner for STT
 * iOS Reference: ModelStatusBanner in ModelStatusComponents.swift
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
 * STT Mode Selector (Batch / Live)
 * iOS Reference: Mode selector segment control in SpeechToTextView
 */
@Composable
private fun STTModeSelector(
    selectedMode: STTMode,
    @Suppress("UNUSED_PARAMETER") supportsLiveMode: Boolean,
    onModeChange: (STTMode) -> Unit,
) {
    Surface(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(16.dp),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Row(
            modifier = Modifier.padding(4.dp),
        ) {
            STTMode.values().forEach { mode ->
                val isSelected = mode == selectedMode
                Surface(
                    modifier =
                        Modifier
                            .weight(1f)
                            .clickable { onModeChange(mode) },
                    shape = RoundedCornerShape(8.dp),
                    color = if (isSelected) MaterialTheme.colorScheme.surface else Color.Transparent,
                ) {
                    Text(
                        text =
                            when (mode) {
                                STTMode.BATCH -> "Batch"
                                STTMode.LIVE -> "Live"
                            },
                        modifier = Modifier.padding(vertical = 8.dp),
                        textAlign = TextAlign.Center,
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (isSelected) AppColors.primaryAccent else MaterialTheme.colorScheme.onSurfaceVariant,
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

    // iOS Reference: Blue when idle, RED when recording, Orange when transcribing
    // iOS code: viewModel.isRecording ? Color.red : (viewModel.isTranscribing ? Color.orange : Color.blue)
    val buttonColor by animateColorAsState(
        targetValue =
            when (recordingState) {
                RecordingState.IDLE -> AppColors.primaryAccent
                RecordingState.RECORDING -> AppColors.primaryRed // RED when recording - matching iOS exactly
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

    // iOS button is 72pt - use 72dp to match
    Box(
        contentAlignment = Alignment.Center,
        modifier =
            Modifier
                .size(88.dp) // Container for button + pulse ring
                .scale(if (recordingState == RecordingState.RECORDING) scale else 1f),
    ) {
        // Pulsing ring when recording - RED to match iOS
        if (recordingState == RecordingState.RECORDING) {
            Box(
                modifier =
                    Modifier
                        // Slightly larger than button for pulse effect
                        .size(84.dp)
                        .border(
                            width = 2.dp,
                            // RED ring - matching iOS
                            color = AppColors.primaryRed.copy(alpha = 0.3f),
                            shape = CircleShape,
                        )
                        .scale(scale * 1.1f),
            )
        }

        // Main button - 72dp to match iOS 72pt
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
                    // Match iOS icon size
                    CircularProgressIndicator(
                        modifier = Modifier.size(32.dp),
                        color = Color.White,
                        strokeWidth = 3.dp,
                    )
                } else {
                    // Match iOS 32pt icon
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

/**
 * Model Required Overlay for STT
 * iOS Reference: ModelRequiredOverlay in ModelStatusComponents.swift
 */
@Composable
private fun ModelRequiredOverlaySTT(onSelectModel: () -> Unit) {
    Box(
        modifier =
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background.copy(alpha = 0.95f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier.padding(40.dp),
        ) {
            Icon(
                imageVector = Icons.Outlined.GraphicEq,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )

            Text(
                text = "Speech to Text",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )

            Text(
                text = "Select a speech recognition model to transcribe audio. Choose from WhisperKit or ONNX Runtime.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )

            Button(
                onClick = onSelectModel,
                modifier =
                    Modifier
                        .fillMaxWidth(0.7f)
                        .height(50.dp),
                shape = RoundedCornerShape(25.dp),
                colors =
                    ButtonDefaults.buttonColors(
                        containerColor = AppColors.primaryAccent,
                    ),
            ) {
                Icon(
                    Icons.Filled.Apps,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    "Select a Model",
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}
