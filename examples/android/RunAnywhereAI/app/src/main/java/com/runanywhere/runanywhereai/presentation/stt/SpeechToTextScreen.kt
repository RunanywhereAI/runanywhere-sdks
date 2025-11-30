package com.runanywhere.runanywhereai.presentation.stt

import androidx.compose.animation.animateContentSize
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.theme.AppColors

/**
 * Speech to Text Screen - Matching iOS SpeechToTextView.swift exactly
 *
 * iOS Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/SpeechToTextView.swift
 *
 * Features:
 * - Batch mode: Record full audio then transcribe
 * - Live mode: Real-time streaming transcription
 * - Recording button with 3 states (idle, recording, processing)
 * - Model status banner
 * - Transcription display
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SpeechToTextScreen(
    viewModel: SpeechToTextViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var showModelPicker by remember { mutableStateOf(false) }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
        ) {
            // Header with title
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Speech to Text",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold
                )
            }

            // Model Status Banner - Always visible
            // iOS Reference: ModelStatusBanner component
            ModelStatusBannerSTT(
                framework = uiState.selectedFramework,
                modelName = uiState.selectedModelName,
                isLoading = uiState.recordingState == RecordingState.PROCESSING && !uiState.isModelLoaded,
                onSelectModel = { showModelPicker = true }
            )

            HorizontalDivider()

            // Main content - only enabled when model is selected
            if (uiState.isModelLoaded) {
                Column(
                    modifier = Modifier
                        .fillMaxSize()
                        .weight(1f)
                ) {
                    // Mode selector: Batch / Live
                    // iOS Reference: ModeSelector in SpeechToTextView
                    STTModeSelector(
                        selectedMode = uiState.mode,
                        onModeChange = { viewModel.setMode(it) }
                    )

                    // Main recording area
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .weight(1f)
                            .padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.Center
                    ) {
                        // Recording button with pulsing animation
                        RecordingButton(
                            recordingState = uiState.recordingState,
                            audioLevel = uiState.audioLevel,
                            onToggleRecording = { viewModel.toggleRecording() }
                        )

                        Spacer(modifier = Modifier.height(24.dp))

                        // Status text
                        Text(
                            text = when (uiState.recordingState) {
                                RecordingState.IDLE -> "Tap to start recording"
                                RecordingState.RECORDING -> "Recording... Tap to stop"
                                RecordingState.PROCESSING -> "Processing..."
                            },
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    // Transcription display
                    if (uiState.transcription.isNotEmpty()) {
                        TranscriptionDisplay(
                            transcription = uiState.transcription,
                            language = uiState.language
                        )
                    }

                    // Error message
                    uiState.errorMessage?.let { error ->
                        Text(
                            text = error,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            textAlign = TextAlign.Center
                        )
                    }
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
                onSelectModel = { showModelPicker = true }
            )
        }

        // Model picker bottom sheet
        // TODO: Implement ModelSelectionSheet when SDK integration is ready
        // iOS Reference: ModelSelectionSheet(context: .stt)
        if (showModelPicker) {
            // Mock model selection for now
            AlertDialog(
                onDismissRequest = { showModelPicker = false },
                title = { Text("Select STT Model") },
                text = {
                    Column {
                        Text(
                            "TODO: Integrate with RunAnywhere SDK",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        Spacer(modifier = Modifier.height(16.dp))
                        // Mock model options
                        listOf(
                            "WhisperKit Tiny" to "whisperkit-tiny",
                            "WhisperKit Base" to "whisperkit-base",
                            "WhisperKit Small" to "whisperkit-small"
                        ).forEach { (name, id) ->
                            Surface(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(vertical = 4.dp)
                                    .clickable {
                                        viewModel.loadModel(name, id)
                                        showModelPicker = false
                                    },
                                shape = RoundedCornerShape(8.dp),
                                color = MaterialTheme.colorScheme.surfaceVariant
                            ) {
                                Row(
                                    modifier = Modifier.padding(12.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Icon(
                                        Icons.Outlined.GraphicEq,
                                        contentDescription = null,
                                        tint = AppColors.primaryGreen
                                    )
                                    Spacer(modifier = Modifier.width(12.dp))
                                    Text(name)
                                }
                            }
                        }
                    }
                },
                confirmButton = {
                    TextButton(onClick = { showModelPicker = false }) {
                        Text("Cancel")
                    }
                }
            )
        }
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
    onSelectModel: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            if (isLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    strokeWidth = 2.dp
                )
                Text(
                    text = "Loading model...",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            } else if (framework != null && modelName != null) {
                // Model loaded state
                Icon(
                    imageVector = Icons.Filled.GraphicEq,
                    contentDescription = null,
                    tint = AppColors.primaryGreen,
                    modifier = Modifier.size(18.dp)
                )
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = framework,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Text(
                        text = modelName,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium
                    )
                }
                OutlinedButton(
                    onClick = onSelectModel,
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)
                ) {
                    Text("Change", style = MaterialTheme.typography.labelMedium)
                }
            } else {
                // No model state
                Icon(
                    imageVector = Icons.Filled.Warning,
                    contentDescription = null,
                    tint = AppColors.primaryOrange
                )
                Text(
                    text = "No model selected",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f)
                )
                Button(
                    onClick = onSelectModel,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = AppColors.primaryBlue
                    )
                ) {
                    Icon(
                        Icons.Filled.Apps,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp)
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
    onModeChange: (STTMode) -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Row(
            modifier = Modifier.padding(4.dp)
        ) {
            STTMode.values().forEach { mode ->
                val isSelected = mode == selectedMode
                Surface(
                    modifier = Modifier
                        .weight(1f)
                        .clickable { onModeChange(mode) },
                    shape = RoundedCornerShape(8.dp),
                    color = if (isSelected) MaterialTheme.colorScheme.surface else Color.Transparent
                ) {
                    Text(
                        text = when (mode) {
                            STTMode.BATCH -> "Batch"
                            STTMode.LIVE -> "Live"
                        },
                        modifier = Modifier.padding(vertical = 8.dp),
                        textAlign = TextAlign.Center,
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                        color = if (isSelected) AppColors.primaryBlue else MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

/**
 * Recording Button with pulsing animation
 * iOS Reference: Recording button in SpeechToTextView with 3 states
 */
@Composable
private fun RecordingButton(
    recordingState: RecordingState,
    audioLevel: Float,
    onToggleRecording: () -> Unit
) {
    val infiniteTransition = rememberInfiniteTransition(label = "recording_pulse")
    val scale by infiniteTransition.animateFloat(
        initialValue = 1f,
        targetValue = 1.15f,
        animationSpec = infiniteRepeatable(
            animation = tween(600, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse_scale"
    )

    val buttonColor = when (recordingState) {
        RecordingState.IDLE -> AppColors.primaryBlue
        RecordingState.RECORDING -> AppColors.primaryRed
        RecordingState.PROCESSING -> AppColors.primaryOrange
    }

    val buttonIcon = when (recordingState) {
        RecordingState.IDLE -> Icons.Filled.Mic
        RecordingState.RECORDING -> Icons.Filled.Stop
        RecordingState.PROCESSING -> Icons.Filled.Sync
    }

    Box(
        contentAlignment = Alignment.Center,
        modifier = Modifier
            .size(120.dp)
            .scale(if (recordingState == RecordingState.RECORDING) scale else 1f)
    ) {
        // Pulsing ring when recording
        if (recordingState == RecordingState.RECORDING) {
            Box(
                modifier = Modifier
                    .size(120.dp)
                    .border(
                        width = 3.dp,
                        color = buttonColor.copy(alpha = 0.3f),
                        shape = CircleShape
                    )
                    .scale(scale * 1.1f)
            )
        }

        // Main button
        Surface(
            modifier = Modifier
                .size(100.dp)
                .clickable(
                    enabled = recordingState != RecordingState.PROCESSING,
                    onClick = onToggleRecording
                ),
            shape = CircleShape,
            color = buttonColor
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxSize()
            ) {
                if (recordingState == RecordingState.PROCESSING) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(40.dp),
                        color = Color.White,
                        strokeWidth = 3.dp
                    )
                } else {
                    Icon(
                        imageVector = buttonIcon,
                        contentDescription = when (recordingState) {
                            RecordingState.IDLE -> "Start recording"
                            RecordingState.RECORDING -> "Stop recording"
                            RecordingState.PROCESSING -> "Processing"
                        },
                        tint = Color.White,
                        modifier = Modifier.size(40.dp)
                    )
                }
            }
        }
    }
}

/**
 * Transcription Display
 * iOS Reference: Transcription section in SpeechToTextView
 */
@Composable
private fun TranscriptionDisplay(
    transcription: String,
    language: String
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant
    ) {
        Column(
            modifier = Modifier.padding(16.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Transcription",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold
                )
                Surface(
                    shape = RoundedCornerShape(4.dp),
                    color = AppColors.primaryGreen.copy(alpha = 0.1f)
                ) {
                    Text(
                        text = language.uppercase(),
                        modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        style = MaterialTheme.typography.labelSmall,
                        color = AppColors.primaryGreen
                    )
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                text = transcription,
                style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 100.dp)
                    .verticalScroll(rememberScrollState())
            )
        }
    }
}

/**
 * Model Required Overlay for STT
 * iOS Reference: ModelRequiredOverlay in ModelStatusComponents.swift
 */
@Composable
private fun ModelRequiredOverlaySTT(
    onSelectModel: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background.copy(alpha = 0.95f)),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp),
            modifier = Modifier.padding(40.dp)
        ) {
            Icon(
                imageVector = Icons.Outlined.GraphicEq,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)
            )

            Text(
                text = "Speech to Text",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )

            Text(
                text = "Select a speech recognition model to transcribe audio. Choose from WhisperKit or ONNX Runtime.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center
            )

            Button(
                onClick = onSelectModel,
                modifier = Modifier
                    .fillMaxWidth(0.7f)
                    .height(50.dp),
                shape = RoundedCornerShape(25.dp),
                colors = ButtonDefaults.buttonColors(
                    containerColor = AppColors.primaryBlue
                )
            ) {
                Icon(
                    Icons.Filled.Apps,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    "Select a Model",
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}
