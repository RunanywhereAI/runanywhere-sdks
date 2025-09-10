package com.runanywhere.runanywhereai.presentation.voice

import android.Manifest
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
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
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import com.runanywhere.runanywhereai.domain.models.SessionState
import kotlinx.coroutines.launch

/**
 * Voice Assistant screen matching iOS VoiceAssistantView
 * Complete voice pipeline UI with VAD, STT, LLM, and TTS
 */
@OptIn(ExperimentalPermissionsApi::class, ExperimentalMaterial3Api::class)
@Composable
fun VoiceAssistantScreen(
    viewModel: VoiceAssistantViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    val scrollState = rememberScrollState()
    val scope = rememberCoroutineScope()

    // Permission handling
    val microphonePermissionState = rememberPermissionState(
        Manifest.permission.RECORD_AUDIO
    )

    // Model info visibility
    var showModelInfo by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        // Top Bar with model info toggle
        TopAppBar(
            title = {
                Text(
                    "Voice Assistant",
                    style = MaterialTheme.typography.titleLarge
                )
            },
            actions = {
                // Status indicator
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(end = 8.dp)
                ) {
                    StatusIndicator(sessionState = uiState.sessionState)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = getStatusText(uiState.sessionState),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }

                // Model info toggle
                IconButton(onClick = { showModelInfo = !showModelInfo }) {
                    Icon(
                        imageVector = if (showModelInfo) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                        contentDescription = if (showModelInfo) "Hide Models" else "Show Models"
                    )
                }
            }
        )

        // Model badges (matching iOS)
        AnimatedVisibility(
            visible = showModelInfo,
            enter = slideInVertically() + fadeIn(),
            exit = slideOutVertically() + fadeOut()
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                ModelBadge(
                    icon = Icons.Default.Psychology,
                    label = "LLM",
                    value = uiState.currentLLMModel,
                    color = MaterialTheme.colorScheme.primary
                )
                ModelBadge(
                    icon = Icons.Default.Mic,
                    label = "STT",
                    value = uiState.whisperModel,
                    color = MaterialTheme.colorScheme.secondary
                )
                ModelBadge(
                    icon = Icons.Default.VolumeUp,
                    label = "TTS",
                    value = uiState.ttsVoice,
                    color = MaterialTheme.colorScheme.tertiary
                )
            }
        }

        Divider()

        // Main conversation area
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth()
        ) {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(scrollState)
                    .padding(16.dp)
            ) {
                // User transcript
                AnimatedVisibility(
                    visible = uiState.currentTranscript.isNotEmpty(),
                    enter = fadeIn() + expandVertically(),
                    exit = fadeOut() + shrinkVertically()
                ) {
                    ConversationBubble(
                        speaker = "You",
                        message = uiState.currentTranscript,
                        isUser = true,
                        modifier = Modifier.padding(bottom = 16.dp)
                    )
                }

                // Assistant response
                AnimatedVisibility(
                    visible = uiState.assistantResponse.isNotEmpty(),
                    enter = fadeIn() + expandVertically(),
                    exit = fadeOut() + shrinkVertically()
                ) {
                    ConversationBubble(
                        speaker = "Assistant",
                        message = uiState.assistantResponse,
                        isUser = false,
                        modifier = Modifier.padding(bottom = 16.dp)
                    )
                }

                // Empty state
                if (uiState.currentTranscript.isEmpty() && uiState.assistantResponse.isEmpty()) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 100.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Icon(
                                imageVector = Icons.Default.Mic,
                                contentDescription = "Microphone",
                                modifier = Modifier.size(64.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                            )
                            Spacer(modifier = Modifier.height(16.dp))
                            Text(
                                "Tap the microphone to start",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }

            // Auto-scroll when new messages appear
            LaunchedEffect(uiState.assistantResponse) {
                if (uiState.assistantResponse.isNotEmpty()) {
                    scrollState.animateScrollTo(scrollState.maxValue)
                }
            }
        }

        // Bottom control area
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(MaterialTheme.colorScheme.surface)
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Error message
            uiState.errorMessage?.let { error ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Text(
                        text = error,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.padding(12.dp)
                    )
                }
            }

            // Audio waveform visualization
            AnimatedVisibility(
                visible = uiState.isListening,
                enter = fadeIn(),
                exit = fadeOut()
            ) {
                AudioWaveform(
                    audioLevel = uiState.audioLevel,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(60.dp)
                        .padding(bottom = 16.dp)
                )
            }

            // Main microphone button
            MicrophoneButton(
                isListening = uiState.isListening,
                sessionState = uiState.sessionState,
                hasPermission = microphonePermissionState.status.isGranted,
                onToggle = {
                    if (!microphonePermissionState.status.isGranted) {
                        microphonePermissionState.launchPermissionRequest()
                    } else {
                        if (uiState.sessionState == SessionState.DISCONNECTED) {
                            viewModel.startSession()
                        } else if (uiState.isListening) {
                            viewModel.stopSession()
                        } else {
                            viewModel.startSession()
                        }
                    }
                }
            )

            // Action buttons
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 16.dp),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                // Clear conversation
                TextButton(
                    onClick = { viewModel.clearConversation() },
                    enabled = uiState.currentTranscript.isNotEmpty() ||
                             uiState.assistantResponse.isNotEmpty()
                ) {
                    Icon(Icons.Default.Clear, contentDescription = "Clear")
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Clear")
                }

                // Push-to-talk mode toggle (future feature)
                TextButton(
                    onClick = { /* TODO: Implement push-to-talk mode */ }
                ) {
                    Icon(Icons.Default.TouchApp, contentDescription = "Push to Talk")
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Push to Talk")
                }
            }
        }
    }
}

@Composable
private fun StatusIndicator(sessionState: SessionState) {
    val color = when (sessionState) {
        SessionState.CONNECTED -> Color.Green
        SessionState.LISTENING -> Color.Blue
        SessionState.PROCESSING -> Color.Yellow
        SessionState.SPEAKING -> Color.Cyan
        SessionState.ERROR -> Color.Red
        else -> Color.Gray
    }

    val animatedScale by animateFloatAsState(
        targetValue = if (sessionState == SessionState.LISTENING) 1.2f else 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000),
            repeatMode = RepeatMode.Reverse
        )
    )

    Box(
        modifier = Modifier
            .size(8.dp)
            .scale(if (sessionState == SessionState.LISTENING) animatedScale else 1f)
            .clip(CircleShape)
            .background(color)
    )
}

@Composable
private fun ModelBadge(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    color: Color
) {
    Card(
        modifier = Modifier.padding(4.dp),
        colors = CardDefaults.cardColors(
            containerColor = color.copy(alpha = 0.1f)
        )
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                modifier = Modifier.size(16.dp),
                tint = color
            )
            Spacer(modifier = Modifier.width(4.dp))
            Column {
                Text(
                    text = label,
                    style = MaterialTheme.typography.labelSmall,
                    color = color
                )
                Text(
                    text = value,
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Bold
                )
            }
        }
    }
}

@Composable
private fun ConversationBubble(
    speaker: String,
    message: String,
    isUser: Boolean,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = if (isUser) Alignment.End else Alignment.Start
    ) {
        Text(
            text = speaker,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 2.dp)
        )
        Card(
            colors = CardDefaults.cardColors(
                containerColor = if (isUser)
                    MaterialTheme.colorScheme.primaryContainer
                else
                    MaterialTheme.colorScheme.secondaryContainer
            ),
            modifier = Modifier.widthIn(max = 280.dp)
        ) {
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(12.dp)
            )
        }
    }
}

@Composable
private fun AudioWaveform(
    audioLevel: Float,
    modifier: Modifier = Modifier
) {
    val animatedLevel by animateFloatAsState(
        targetValue = audioLevel,
        animationSpec = tween(100)
    )

    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(8.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .fillMaxWidth(fraction = animatedLevel.coerceIn(0.1f, 1f))
                .background(
                    MaterialTheme.colorScheme.primary.copy(alpha = 0.3f)
                )
        )
    }
}

@Composable
private fun MicrophoneButton(
    isListening: Boolean,
    sessionState: SessionState,
    hasPermission: Boolean,
    onToggle: () -> Unit
) {
    val backgroundColor = when {
        !hasPermission -> MaterialTheme.colorScheme.error
        sessionState == SessionState.LISTENING -> MaterialTheme.colorScheme.primary
        sessionState == SessionState.ERROR -> MaterialTheme.colorScheme.error
        isListening -> MaterialTheme.colorScheme.secondary
        else -> MaterialTheme.colorScheme.surfaceVariant
    }

    val animatedScale by animateFloatAsState(
        targetValue = if (sessionState == SessionState.LISTENING) 1.1f else 1f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessLow
        )
    )

    FloatingActionButton(
        onClick = onToggle,
        modifier = Modifier
            .size(80.dp)
            .scale(animatedScale),
        containerColor = backgroundColor
    ) {
        Icon(
            imageVector = when {
                !hasPermission -> Icons.Default.MicOff
                sessionState == SessionState.LISTENING -> Icons.Default.Mic
                sessionState == SessionState.PROCESSING -> Icons.Default.HourglassEmpty
                sessionState == SessionState.SPEAKING -> Icons.Default.VolumeUp
                else -> Icons.Default.MicNone
            },
            contentDescription = "Microphone",
            modifier = Modifier.size(32.dp)
        )
    }
}

private fun getStatusText(sessionState: SessionState): String {
    return when (sessionState) {
        SessionState.DISCONNECTED -> "Tap to start"
        SessionState.CONNECTING -> "Connecting..."
        SessionState.CONNECTED -> "Ready"
        SessionState.LISTENING -> "Listening..."
        SessionState.PROCESSING -> "Processing..."
        SessionState.SPEAKING -> "Speaking..."
        SessionState.ERROR -> "Error"
    }
}
