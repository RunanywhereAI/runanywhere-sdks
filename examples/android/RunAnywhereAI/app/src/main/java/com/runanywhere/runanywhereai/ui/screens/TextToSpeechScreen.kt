package com.runanywhere.runanywhereai.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.models.TTSUiState
import com.runanywhere.runanywhereai.ui.components.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.components.RAButton
import com.runanywhere.runanywhereai.ui.components.RAButtonStyle
import com.runanywhere.runanywhereai.ui.components.RACard
import com.runanywhere.runanywhereai.ui.icons.RAIcons
import com.runanywhere.runanywhereai.viewmodels.ModelSelectionViewModel
import com.runanywhere.runanywhereai.viewmodels.TTSViewModel
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import com.runanywhere.sdk.public.extensions.loadTTSVoice
import kotlinx.coroutines.launch

@Composable
fun TextToSpeechScreen(
    onBack: () -> Unit,
    viewModel: TTSViewModel = viewModel(),
    modelSelectionViewModel: ModelSelectionViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val modelState by modelSelectionViewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var showModelSheet by remember { mutableStateOf(false) }

    when (val state = uiState) {
        is TTSUiState.Loading -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        is TTSUiState.Ready -> TTSReadyContent(
            state = state,
            viewModel = viewModel,
            onSelectModel = {
                modelSelectionViewModel.loadModels(ModelSelectionContext.TTS)
                showModelSheet = true
            },
        )
        is TTSUiState.Error -> {
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
                            RunAnywhere.loadTTSVoice(modelId)
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
private fun TTSReadyContent(
    state: TTSUiState.Ready,
    viewModel: TTSViewModel,
    onSelectModel: () -> Unit,
) {
    val canGenerate by remember(state.inputText, state.isGenerating, state.isModelLoaded) {
        derivedStateOf { state.inputText.isNotEmpty() && !state.isGenerating && state.isModelLoaded }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        // Scrollable content
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            // Model status
            if (!state.isModelLoaded) {
                RACard {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = RAIcons.AlertCircle,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(20.dp),
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text("No voice model loaded", style = MaterialTheme.typography.bodyLarge)
                            Text(
                                "Select a TTS model to get started",
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
                state.selectedModelName?.let { modelName ->
                    RACard(
                        containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = RAIcons.Volume2,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(20.dp),
                            )
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(
                                    modelName,
                                    style = MaterialTheme.typography.bodyLarge,
                                    fontWeight = FontWeight.Medium,
                                )
                                Text(
                                    if (state.isSystemTTS) "System TTS" else "On-device",
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
            }

            // Text input
            TextInputSection(
                text = state.inputText,
                onTextChange = { viewModel.updateInputText(it) },
                characterCount = state.characterCount,
                onShuffle = { viewModel.shuffleSampleText() },
            )

            // Voice settings
            VoiceSettingsSection(
                speed = state.speed,
                onSpeedChange = { viewModel.updateSpeed(it) },
            )

            // Audio info
            AnimatedVisibility(
                visible = state.audioDuration != null,
                enter = fadeIn(),
                exit = fadeOut(),
            ) {
                state.audioDuration?.let { duration ->
                    AudioInfoSection(
                        duration = duration,
                        audioSize = state.audioSize,
                    )
                }
            }
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))

        // Controls pinned to bottom
        TTSControlsSection(
            state = state,
            canGenerate = canGenerate,
            onGenerate = { viewModel.generateSpeech() },
            onStopSpeaking = { viewModel.stopSynthesis() },
            onTogglePlayback = { viewModel.togglePlayback() },
        )
    }
}

@Composable
private fun TextInputSection(
    text: String,
    onTextChange: (String) -> Unit,
    characterCount: Int,
    onShuffle: () -> Unit,
) {
    RACard {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Enter Text", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)

            OutlinedTextField(
                value = text,
                onValueChange = onTextChange,
                modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp),
                placeholder = { Text("Type or paste text to convert to speech...") },
                shape = RoundedCornerShape(12.dp),
            )

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "$characterCount characters",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                Surface(
                    shape = RoundedCornerShape(8.dp),
                    color = MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.5f),
                    onClick = onShuffle,
                ) {
                    Row(
                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(
                            imageVector = RAIcons.Sparkles,
                            contentDescription = "Surprise me",
                            modifier = Modifier.size(14.dp),
                            tint = MaterialTheme.colorScheme.tertiary,
                        )
                        Text(
                            "Surprise me",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.tertiary,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun VoiceSettingsSection(
    speed: Float,
    onSpeedChange: (Float) -> Unit,
) {
    RACard {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Voice Settings", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text("Speed", style = MaterialTheme.typography.bodyMedium)
                Text(
                    String.format("%.1fx", speed),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            Slider(
                value = speed,
                onValueChange = onSpeedChange,
                valueRange = 0.5f..2.0f,
                steps = 14,
                colors = SliderDefaults.colors(
                    thumbColor = MaterialTheme.colorScheme.primary,
                    activeTrackColor = MaterialTheme.colorScheme.primary,
                ),
            )
        }
    }
}

@Composable
private fun AudioInfoSection(
    duration: Double,
    audioSize: Int?,
) {
    RACard {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Audio Info", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold)

            AudioInfoRow(
                icon = RAIcons.Activity,
                label = "Duration",
                value = String.format("%.2fs", duration),
            )

            audioSize?.let {
                AudioInfoRow(
                    icon = RAIcons.FileText,
                    label = "Size",
                    value = formatBytes(it),
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
        Spacer(Modifier.width(8.dp))
        Text("$label:", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Spacer(Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun TTSControlsSection(
    state: TTSUiState.Ready,
    canGenerate: Boolean,
    onGenerate: () -> Unit,
    onStopSpeaking: () -> Unit,
    onTogglePlayback: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Error message
        state.error?.let { error ->
            Text(
                text = error,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                textAlign = TextAlign.Center,
            )
        }

        // Playback progress
        if (state.isPlaying) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(formatTime(state.currentTime), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                LinearProgressIndicator(
                    progress = { state.playbackProgress.toFloat() },
                    modifier = Modifier.weight(1f),
                    color = MaterialTheme.colorScheme.primary,
                )
                Text(formatTime(state.audioDuration ?: 0.0), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        // Action buttons
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            // Generate / Speak / Stop button
            RAButton(
                text = when {
                    state.isGenerating -> "Generating..."
                    state.isSystemTTS && state.isSpeaking -> "Stop"
                    state.isSystemTTS -> "Speak"
                    else -> "Generate"
                },
                onClick = {
                    if (state.isSystemTTS && state.isSpeaking) onStopSpeaking() else onGenerate()
                },
                enabled = canGenerate || (state.isSystemTTS && state.isSpeaking),
                icon = when {
                    state.isSystemTTS && state.isSpeaking -> RAIcons.Stop
                    state.isSystemTTS -> RAIcons.Volume2
                    else -> RAIcons.Activity
                },
                style = RAButtonStyle.Filled,
            )

            // Play/Stop button (non-system TTS only)
            if (!state.isSystemTTS) {
                RAButton(
                    text = if (state.isPlaying) "Stop" else "Play",
                    onClick = onTogglePlayback,
                    enabled = state.hasGeneratedAudio && !state.isSpeaking,
                    icon = if (state.isPlaying) RAIcons.Stop else RAIcons.Play,
                    style = RAButtonStyle.Tonal,
                )
            }
        }

        // Status text
        Text(
            text = when {
                state.isSpeaking -> "Speaking..."
                state.isSystemTTS && state.isModelLoaded -> "System TTS plays directly"
                state.isGenerating -> "Generating speech..."
                state.isPlaying -> "Playing..."
                state.isModelLoaded -> "Ready"
                else -> "Select a model to begin"
            },
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// -- Helpers ------------------------------------------------------------------

private fun formatBytes(bytes: Int): String {
    val kb = bytes / 1024.0
    return if (kb < 1024) String.format("%.1f KB", kb) else String.format("%.1f MB", kb / 1024.0)
}

private fun formatTime(seconds: Double): String {
    val mins = (seconds / 60).toInt()
    val secs = (seconds % 60).toInt()
    return String.format("%d:%02d", mins, secs)
}
