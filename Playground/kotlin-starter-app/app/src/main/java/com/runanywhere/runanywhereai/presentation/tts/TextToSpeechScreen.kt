package com.runanywhere.runanywhereai.presentation.tts

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import kotlinx.coroutines.launch

/**
 * Text to Speech Screen - Matching iOS TextToSpeechView.swift exactly
 *
 * iOS Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Voice/TextToSpeechView.swift
 *
 * Features:
 * - Text input area with character count
 * - Voice settings (speed, pitch sliders)
 * - Generate/Speak button
 * - Play/Stop button for playback
 * - Audio info display
 * - Model status banner
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TextToSpeechScreen(viewModel: TextToSpeechViewModel = viewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var showModelPicker by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

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
                    text = "Text to Speech",
                    style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold,
                )
            }

            // Model Status Banner - Always visible
            // iOS Reference: ModelStatusBanner component
            ModelStatusBannerTTS(
                framework = uiState.selectedFramework?.displayName,
                modelName = uiState.selectedModelName,
                isLoading = uiState.isGenerating && uiState.selectedModelName == null,
                onSelectModel = { showModelPicker = true },
            )

            HorizontalDivider()

            // Main content - only enabled when model is selected
            if (uiState.isModelLoaded) {
                // Scrollable content area
                Column(
                    modifier =
                        Modifier
                            .fillMaxSize()
                            .weight(1f)
                            .verticalScroll(rememberScrollState())
                            .padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                ) {
                    // Text input section
                    // iOS Reference: TextEditor in TextToSpeechView
                    TextInputSection(
                        text = uiState.inputText,
                        onTextChange = { viewModel.updateInputText(it) },
                        characterCount = uiState.characterCount,
                        maxCharacters = uiState.maxCharacters,
                        onShuffle = { viewModel.shuffleSampleText() },
                    )

                    // Voice settings section
                    // iOS Reference: Voice Settings section with sliders
                    VoiceSettingsSection(
                        speed = uiState.speed,
                        pitch = uiState.pitch,
                        onSpeedChange = { viewModel.updateSpeed(it) },
                        onPitchChange = { viewModel.updatePitch(it) },
                    )

                    // Audio info section (shown after generation)
                    // iOS Reference: Audio Info section with metadata
                    if (uiState.audioDuration != null) {
                        AudioInfoSection(
                            duration = uiState.audioDuration!!,
                            audioSize = uiState.audioSize,
                            sampleRate = uiState.sampleRate,
                        )
                    }
                }

                HorizontalDivider()

                // Controls section
                // iOS Reference: Controls VStack at bottom
                ControlsSection(
                    isGenerating = uiState.isGenerating,
                    isPlaying = uiState.isPlaying,
                    isSpeaking = uiState.isSpeaking,
                    hasGeneratedAudio = uiState.hasGeneratedAudio,
                    isSystemTTS = uiState.isSystemTTS,
                    isTextEmpty = uiState.inputText.isEmpty(),
                    isModelSelected = uiState.selectedModelName != null,
                    playbackProgress = uiState.playbackProgress,
                    currentTime = uiState.currentTime,
                    duration = uiState.audioDuration ?: 0.0,
                    errorMessage = uiState.errorMessage,
                    onGenerate = { viewModel.generateSpeech() },
                    onStopSpeaking = { viewModel.stopSynthesis() },
                    onTogglePlayback = { viewModel.togglePlayback() },
                )
            } else {
                // No model selected - show spacer
                Spacer(modifier = Modifier.weight(1f))
            }
        }

        // Overlay when no model is selected
        // iOS Reference: ModelRequiredOverlay component
        if (!uiState.isModelLoaded && !uiState.isGenerating) {
            ModelRequiredOverlayTTS(
                onSelectModel = { showModelPicker = true },
            )
        }

        // Model picker bottom sheet - Full-screen with framework/model hierarchy
        // iOS Reference: ModelSelectionSheet(context: .tts)
        if (showModelPicker) {
            ModelSelectionBottomSheet(
                context = ModelSelectionContext.TTS,
                onDismiss = { showModelPicker = false },
                onModelSelected = { model ->
                    scope.launch {
                        android.util.Log.d("TextToSpeechScreen", "TTS model selected: ${model.name}")
                        // Notify ViewModel that model is loaded
                        viewModel.onModelLoaded(
                            modelName = model.name,
                            modelId = model.id,
                            framework = model.framework,
                        )
                        showModelPicker = false
                    }
                },
            )
        }
    }
}

/**
 * Model Status Banner for TTS
 * iOS Reference: ModelStatusBanner in ModelStatusComponents.swift
 */
@Composable
private fun ModelStatusBannerTTS(
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
                    text = "Loading voice...",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            } else if (framework != null && modelName != null) {
                Icon(
                    imageVector = Icons.Filled.VolumeUp,
                    contentDescription = null,
                    tint = AppColors.primaryAccent,
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
                Icon(
                    imageVector = Icons.Filled.Warning,
                    contentDescription = null,
                    tint = AppColors.primaryOrange,
                )
                Text(
                    text = "No voice selected",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                Button(
                    onClick = onSelectModel,
                    colors =
                        ButtonDefaults.buttonColors(
                            containerColor = AppColors.primaryAccent,
                            contentColor = Color.White,
                        ),
                ) {
                    Icon(
                        Icons.Filled.Apps,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                        tint = Color.White,
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        "Select Voice",
                        color = Color.White,
                    )
                }
            }
        }
    }
}

/**
 * Text Input Section
 * iOS Reference: TextEditor section in TextToSpeechView
 */
@Composable
private fun TextInputSection(
    text: String,
    onTextChange: (String) -> Unit,
    characterCount: Int,
    @Suppress("UNUSED_PARAMETER") maxCharacters: Int,
    onShuffle: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = "Enter Text",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )

        OutlinedTextField(
            value = text,
            onValueChange = onTextChange,
            modifier =
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 120.dp),
            placeholder = {
                Text("Type or paste text to convert to speech...")
            },
            shape = RoundedCornerShape(12.dp),
        )

        // Character count and Surprise me! button row
        // iOS Reference: HStack with character count and dice button
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "$characterCount characters",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            TextButton(
                onClick = onShuffle,
                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp),
            ) {
                Icon(
                    imageVector = Icons.Filled.Casino,
                    contentDescription = "Shuffle",
                    modifier = Modifier.size(16.dp),
                    tint = AppColors.primaryAccent,
                )
                Spacer(modifier = Modifier.width(4.dp))
                Text(
                    text = "Surprise me!",
                    style = MaterialTheme.typography.labelSmall,
                    color = AppColors.primaryAccent,
                )
            }
        }
    }
}

/**
 * Voice Settings Section with Speed and Pitch sliders
 * iOS Reference: Voice Settings section in TextToSpeechView
 */
@Composable
private fun VoiceSettingsSection(
    speed: Float,
    pitch: Float,
    onSpeedChange: (Float) -> Unit,
    onPitchChange: (Float) -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(
                text = "Voice Settings",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )

            // Speed slider
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = "Speed",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Text(
                        text = String.format("%.1fx", speed),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                // 0.1 increments
                Slider(
                    value = speed,
                    onValueChange = onSpeedChange,
                    valueRange = 0.5f..2.0f,
                    steps = 14,
                    colors =
                        SliderDefaults.colors(
                            thumbColor = AppColors.primaryAccent,
                            activeTrackColor = AppColors.primaryAccent,
                        ),
                )
            }

            // Pitch slider
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = "Pitch",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Text(
                        text = String.format("%.1fx", pitch),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Slider(
                    value = pitch,
                    onValueChange = onPitchChange,
                    valueRange = 0.5f..2.0f,
                    steps = 14,
                    colors =
                        SliderDefaults.colors(
                            thumbColor = AppColors.primaryAccent,
                            activeTrackColor = AppColors.primaryAccent,
                        ),
                )
            }
        }
    }
}

/**
 * Audio Info Section
 * iOS Reference: Audio Info section in TextToSpeechView
 */
@Composable
private fun AudioInfoSection(
    duration: Double,
    audioSize: Int?,
    sampleRate: Int?,
) {
    Surface(
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = "Audio Info",
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
            )

            AudioInfoRow(
                icon = Icons.Outlined.GraphicEq,
                label = "Duration",
                value = String.format("%.2fs", duration),
            )

            audioSize?.let {
                AudioInfoRow(
                    icon = Icons.Outlined.Description,
                    label = "Size",
                    value = formatBytes(it),
                )
            }

            sampleRate?.let {
                AudioInfoRow(
                    icon = Icons.Outlined.VolumeUp,
                    label = "Sample Rate",
                    value = "$it Hz",
                )
            }
        }
    }
}

@Composable
private fun AudioInfoRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(16.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.width(8.dp))
        Text(
            text = "$label:",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(modifier = Modifier.weight(1f))
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.Medium,
        )
    }
}

/**
 * Controls Section with Generate and Play buttons
 * iOS Reference: Controls VStack in TextToSpeechView
 */
@Composable
private fun ControlsSection(
    isGenerating: Boolean,
    isPlaying: Boolean,
    isSpeaking: Boolean,
    hasGeneratedAudio: Boolean,
    isSystemTTS: Boolean,
    isTextEmpty: Boolean,
    isModelSelected: Boolean,
    playbackProgress: Double,
    currentTime: Double,
    duration: Double,
    errorMessage: String?,
    onGenerate: () -> Unit,
    onStopSpeaking: () -> Unit,
    onTogglePlayback: () -> Unit,
) {
    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Error message
        errorMessage?.let { error ->
            Text(
                text = error,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                textAlign = TextAlign.Center,
            )
        }

        // Playback progress (when playing)
        if (isPlaying) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = formatTime(currentTime),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                LinearProgressIndicator(
                    progress = { playbackProgress.toFloat() },
                    modifier = Modifier.weight(1f),
                    color = AppColors.primaryAccent,
                )
                Text(
                    text = formatTime(duration),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        // Action buttons
        Row(
            horizontalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            // Generate/Speak button (System TTS toggles Stop while speaking)
            Button(
                onClick = {
                    if (isSystemTTS && isSpeaking) {
                        onStopSpeaking()
                    } else {
                        onGenerate()
                    }
                },
                enabled = !isTextEmpty && isModelSelected && !isGenerating,
                modifier =
                    Modifier
                        .width(140.dp)
                        .height(50.dp),
                shape = RoundedCornerShape(25.dp),
                colors =
                    ButtonDefaults.buttonColors(
                        containerColor = AppColors.primaryAccent,
                        contentColor = Color.White,
                        disabledContainerColor = Color.Gray,
                    ),
            ) {
                if (isGenerating) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        color = Color.White,
                        strokeWidth = 2.dp,
                    )
                } else {
                    Icon(
                        imageVector =
                            if (isSystemTTS && isSpeaking) {
                                Icons.Filled.Stop
                            } else if (isSystemTTS) {
                                Icons.Filled.VolumeUp
                            } else {
                                Icons.Filled.GraphicEq
                            },
                        contentDescription = null,
                        modifier = Modifier.size(20.dp),
                        tint = Color.White,
                    )
                }
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text =
                        if (isSystemTTS && isSpeaking) {
                            "Stop"
                        } else if (isSystemTTS) {
                            "Speak"
                        } else {
                            "Generate"
                        },
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White,
                )
            }

            // Play/Stop button (only for non-System TTS)
            Button(
                onClick = onTogglePlayback,
                enabled = hasGeneratedAudio && !isSystemTTS && !isSpeaking,
                modifier =
                    Modifier
                        .width(140.dp)
                        .height(50.dp),
                shape = RoundedCornerShape(25.dp),
                colors =
                    ButtonDefaults.buttonColors(
                        containerColor = if (hasGeneratedAudio) AppColors.primaryGreen else Color.Gray,
                        disabledContainerColor = Color.Gray,
                    ),
            ) {
                Icon(
                    imageVector = if (isPlaying) Icons.Filled.Stop else Icons.Filled.PlayArrow,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = if (isPlaying) "Stop" else "Play",
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }

        // Status text
        Text(
            text =
                when {
                    isSpeaking -> "Speaking..."
                    isSystemTTS -> "System TTS plays directly"
                    isGenerating -> "Generating speech..."
                    isPlaying -> "Playing..."
                    else -> "Ready"
                },
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Model Required Overlay for TTS
 * iOS Reference: ModelRequiredOverlay in ModelStatusComponents.swift
 */
@Composable
private fun ModelRequiredOverlayTTS(onSelectModel: () -> Unit) {
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
                imageVector = Icons.Outlined.VolumeUp,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
            )

            Text(
                text = "Text to Speech",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )

            Text(
                text = "Select a text-to-speech voice to generate audio. Choose from System TTS or Piper models.",
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
                        contentColor = Color.White,
                    ),
            ) {
                Icon(
                    Icons.Filled.Apps,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                    tint = Color.White,
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    "Select a Voice",
                    fontWeight = FontWeight.SemiBold,
                    color = Color.White,
                )
            }
        }
    }
}

// Helper functions

private fun formatBytes(bytes: Int): String {
    val kb = bytes / 1024.0
    return if (kb < 1024) {
        String.format("%.1f KB", kb)
    } else {
        String.format("%.1f MB", kb / 1024.0)
    }
}

private fun formatTime(seconds: Double): String {
    val mins = (seconds / 60).toInt()
    val secs = (seconds % 60).toInt()
    return String.format("%d:%02d", mins, secs)
}
