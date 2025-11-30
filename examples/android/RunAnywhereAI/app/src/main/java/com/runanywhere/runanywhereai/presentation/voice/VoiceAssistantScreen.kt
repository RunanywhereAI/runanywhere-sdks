package com.runanywhere.runanywhereai.presentation.voice

import android.Manifest
import androidx.compose.animation.*
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
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import com.runanywhere.runanywhereai.domain.models.SessionState
import com.runanywhere.runanywhereai.ui.theme.AppColors

/**
 * Voice Assistant screen matching iOS VoiceAssistantView
 *
 * iOS Reference: VoiceAssistantView.swift
 *
 * This screen shows:
 * - VoicePipelineSetupView when not all models are loaded
 * - Main voice UI with conversation bubbles when ready
 *
 * Complete voice pipeline UI with VAD, STT, LLM, and TTS
 */
@OptIn(ExperimentalPermissionsApi::class, ExperimentalMaterial3Api::class)
@Composable
fun VoiceAssistantScreen(
    viewModel: VoiceAssistantViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsState()
    var showModelInfo by remember { mutableStateOf(false) }

    // Model selection dialog states
    var showSTTModelSelection by remember { mutableStateOf(false) }
    var showLLMModelSelection by remember { mutableStateOf(false) }
    var showTTSModelSelection by remember { mutableStateOf(false) }

    // Permission handling
    val microphonePermissionState = rememberPermissionState(
        Manifest.permission.RECORD_AUDIO
    )

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        // Show setup view when not all models are loaded
        // iOS Reference: if !viewModel.allModelsLoaded { VoicePipelineSetupView(...) }
        if (!uiState.allModelsLoaded) {
            VoicePipelineSetupView(
                sttModel = uiState.sttModel,
                llmModel = uiState.llmModel,
                ttsModel = uiState.ttsModel,
                sttLoadState = uiState.sttLoadState,
                llmLoadState = uiState.llmLoadState,
                ttsLoadState = uiState.ttsLoadState,
                onSelectSTT = { showSTTModelSelection = true },
                onSelectLLM = { showLLMModelSelection = true },
                onSelectTTS = { showTTSModelSelection = true },
                onStartVoice = {
                    // All models loaded, nothing to do here
                    // The view will automatically switch to main voice UI
                }
            )
        } else {
            // Main voice assistant UI (only shown when all models are ready)
            MainVoiceAssistantUI(
                uiState = uiState,
                showModelInfo = showModelInfo,
                onToggleModelInfo = { showModelInfo = !showModelInfo },
                hasPermission = microphonePermissionState.status.isGranted,
                onRequestPermission = { microphonePermissionState.launchPermissionRequest() },
                onStartSession = { viewModel.startSession() },
                onStopSession = { viewModel.stopSession() },
                onClearConversation = { viewModel.clearConversation() }
            )
        }
    }

    // Model selection dialogs
    // TODO: Replace with actual model selection sheets matching iOS ModelSelectionSheet
    if (showSTTModelSelection) {
        MockModelSelectionDialog(
            title = "Select Speech Recognition Model",
            modelType = "STT",
            onDismiss = { showSTTModelSelection = false },
            onSelectModel = { framework, name, modelId ->
                viewModel.setSTTModel(framework, name, modelId)
                showSTTModelSelection = false
            }
        )
    }

    if (showLLMModelSelection) {
        MockModelSelectionDialog(
            title = "Select Language Model",
            modelType = "LLM",
            onDismiss = { showLLMModelSelection = false },
            onSelectModel = { framework, name, modelId ->
                viewModel.setLLMModel(framework, name, modelId)
                showLLMModelSelection = false
            }
        )
    }

    if (showTTSModelSelection) {
        MockModelSelectionDialog(
            title = "Select Text to Speech Model",
            modelType = "TTS",
            onDismiss = { showTTSModelSelection = false },
            onSelectModel = { framework, name, modelId ->
                viewModel.setTTSModel(framework, name, modelId)
                showTTSModelSelection = false
            }
        )
    }
}

/**
 * Voice Pipeline Setup View
 *
 * iOS Reference: VoicePipelineSetupView in ModelStatusComponents.swift
 *
 * A setup view specifically for Voice Assistant which requires 3 models:
 * - STT (Speech Recognition)
 * - LLM (Language Model)
 * - TTS (Text to Speech)
 */
@Composable
private fun VoicePipelineSetupView(
    sttModel: SelectedModel?,
    llmModel: SelectedModel?,
    ttsModel: SelectedModel?,
    sttLoadState: ModelLoadState,
    llmLoadState: ModelLoadState,
    ttsLoadState: ModelLoadState,
    onSelectSTT: () -> Unit,
    onSelectLLM: () -> Unit,
    onSelectTTS: () -> Unit,
    onStartVoice: () -> Unit
) {
    val allModelsReady = sttModel != null && llmModel != null && ttsModel != null
    val allModelsLoaded = sttLoadState.isLoaded && llmLoadState.isLoaded && ttsLoadState.isLoaded

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        // Header
        // iOS Reference: VoicePipelineSetupView header
        Spacer(modifier = Modifier.height(20.dp))

        Icon(
            imageVector = Icons.Default.Mic,
            contentDescription = "Voice Assistant",
            modifier = Modifier.size(48.dp),
            tint = AppColors.primaryBlue
        )

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = "Voice Assistant Setup",
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold
        )

        Spacer(modifier = Modifier.height(8.dp))

        Text(
            text = "Voice requires 3 models to work together",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Model cards with load state
        // iOS Reference: VStack with ModelSetupCard components

        // STT Model
        ModelSetupCard(
            step = 1,
            title = "Speech Recognition",
            subtitle = "Converts your voice to text",
            icon = Icons.Default.GraphicEq,
            color = Color(0xFF4CAF50), // Green
            selectedFramework = sttModel?.framework,
            selectedModel = sttModel?.name,
            loadState = sttLoadState,
            onSelect = onSelectSTT
        )

        Spacer(modifier = Modifier.height(16.dp))

        // LLM Model
        ModelSetupCard(
            step = 2,
            title = "Language Model",
            subtitle = "Processes and responds to your input",
            icon = Icons.Default.Psychology,
            color = AppColors.primaryBlue,
            selectedFramework = llmModel?.framework,
            selectedModel = llmModel?.name,
            loadState = llmLoadState,
            onSelect = onSelectLLM
        )

        Spacer(modifier = Modifier.height(16.dp))

        // TTS Model
        ModelSetupCard(
            step = 3,
            title = "Text to Speech",
            subtitle = "Converts responses to audio",
            icon = Icons.Default.VolumeUp,
            color = Color(0xFF9C27B0), // Purple
            selectedFramework = ttsModel?.framework,
            selectedModel = ttsModel?.name,
            loadState = ttsLoadState,
            onSelect = onSelectTTS
        )

        Spacer(modifier = Modifier.weight(1f))

        // Start button - enabled only when all models are loaded
        Button(
            onClick = onStartVoice,
            enabled = allModelsLoaded,
            modifier = Modifier
                .fillMaxWidth()
                .height(56.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = AppColors.primaryBlue
            )
        ) {
            Icon(
                imageVector = Icons.Default.Mic,
                contentDescription = null,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "Start Voice Assistant",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
        }

        Spacer(modifier = Modifier.height(12.dp))

        // Status message
        Text(
            text = when {
                !allModelsReady -> "Select all 3 models to continue"
                !allModelsLoaded -> "Waiting for models to load..."
                else -> "All models loaded and ready!"
            },
            style = MaterialTheme.typography.bodySmall,
            color = when {
                !allModelsReady -> MaterialTheme.colorScheme.onSurfaceVariant
                !allModelsLoaded -> Color(0xFFFFA000) // Orange
                else -> Color(0xFF4CAF50) // Green
            }
        )

        Spacer(modifier = Modifier.height(20.dp))
    }
}

/**
 * Model Setup Card
 *
 * iOS Reference: ModelSetupCard in ModelStatusComponents.swift
 *
 * A card showing model selection and loading state
 */
@Composable
private fun ModelSetupCard(
    step: Int,
    title: String,
    subtitle: String,
    icon: ImageVector,
    color: Color,
    selectedFramework: String?,
    selectedModel: String?,
    loadState: ModelLoadState,
    onSelect: () -> Unit
) {
    val isConfigured = selectedFramework != null && selectedModel != null
    val isLoaded = loadState.isLoaded
    val isLoading = loadState.isLoading

    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .then(
                if (isLoaded) {
                    Modifier.border(2.dp, Color(0xFF4CAF50).copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                } else if (isLoading) {
                    Modifier.border(2.dp, Color(0xFFFFA000).copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                } else if (isConfigured) {
                    Modifier.border(2.dp, color.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                } else {
                    Modifier
                }
            ),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant
        ),
        shape = RoundedCornerShape(12.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Step indicator with loading/loaded state
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(
                        when {
                            isLoading -> Color(0xFFFFA000) // Orange
                            isLoaded -> Color(0xFF4CAF50) // Green
                            isConfigured -> color
                            else -> Color.Gray.copy(alpha = 0.2f)
                        }
                    ),
                contentAlignment = Alignment.Center
            ) {
                when {
                    isLoading -> {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            color = Color.White,
                            strokeWidth = 2.dp
                        )
                    }
                    isLoaded -> {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = "Loaded",
                            modifier = Modifier.size(18.dp),
                            tint = Color.White
                        )
                    }
                    isConfigured -> {
                        Icon(
                            imageVector = Icons.Default.Check,
                            contentDescription = "Configured",
                            modifier = Modifier.size(18.dp),
                            tint = Color.White
                        )
                    }
                    else -> {
                        Text(
                            text = "$step",
                            fontWeight = FontWeight.Bold,
                            color = Color.Gray
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.width(16.dp))

            // Content
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = icon,
                        contentDescription = title,
                        modifier = Modifier.size(18.dp),
                        tint = color
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = title,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.SemiBold
                    )
                }

                Spacer(modifier = Modifier.height(4.dp))

                if (isConfigured) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "$selectedFramework • $selectedModel",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                        if (isLoaded) {
                            Spacer(modifier = Modifier.width(4.dp))
                            Icon(
                                imageVector = Icons.Default.CheckCircle,
                                contentDescription = "Loaded",
                                modifier = Modifier.size(12.dp),
                                tint = Color(0xFF4CAF50)
                            )
                        } else if (isLoading) {
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(
                                text = "Loading...",
                                style = MaterialTheme.typography.labelSmall,
                                color = Color(0xFFFFA000)
                            )
                        }
                    }
                } else {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            // Action / Status
            when {
                isLoading -> {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp
                    )
                }
                isLoaded -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = "Loaded",
                            modifier = Modifier.size(16.dp),
                            tint = Color(0xFF4CAF50)
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = "Loaded",
                            style = MaterialTheme.typography.labelSmall,
                            color = Color(0xFF4CAF50)
                        )
                    }
                }
                isConfigured -> {
                    Text(
                        text = "Change",
                        style = MaterialTheme.typography.labelSmall,
                        color = AppColors.primaryBlue
                    )
                }
                else -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "Select",
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = FontWeight.Medium,
                            color = AppColors.primaryBlue
                        )
                        Spacer(modifier = Modifier.width(2.dp))
                        Icon(
                            imageVector = Icons.Default.ChevronRight,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = AppColors.primaryBlue
                        )
                    }
                }
            }
        }
    }
}

/**
 * Main Voice Assistant UI
 *
 * iOS Reference: Main voice UI in VoiceAssistantView.swift (shown when allModelsLoaded)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MainVoiceAssistantUI(
    uiState: VoiceUiState,
    showModelInfo: Boolean,
    onToggleModelInfo: () -> Unit,
    hasPermission: Boolean,
    onRequestPermission: () -> Unit,
    onStartSession: () -> Unit,
    onStopSession: () -> Unit,
    onClearConversation: () -> Unit
) {
    val scrollState = rememberScrollState()

    Column(
        modifier = Modifier.fillMaxSize()
    ) {
        // Minimal header with subtle controls
        // iOS Reference: HStack with model selection button, status indicator, info toggle
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Model selection button - subtle, top left
            IconButton(
                onClick = { /* TODO: Show model selection */ },
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Icon(
                    imageVector = Icons.Default.ViewInAr,
                    contentDescription = "Models",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            // Status indicator - minimal
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                StatusIndicator(sessionState = uiState.sessionState)
                Text(
                    text = getStatusText(uiState.sessionState),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            // Model info toggle - subtle, top right
            IconButton(
                onClick = onToggleModelInfo,
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(MaterialTheme.colorScheme.surfaceVariant)
            ) {
                Icon(
                    imageVector = if (showModelInfo) Icons.Filled.Info else Icons.Outlined.Info,
                    contentDescription = if (showModelInfo) "Hide Models" else "Show Models",
                    tint = if (showModelInfo) AppColors.primaryBlue else MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        // Expandable model info (hidden by default)
        AnimatedVisibility(
            visible = showModelInfo,
            enter = slideInVertically() + fadeIn(),
            exit = slideOutVertically() + fadeOut()
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    ModelBadge(
                        icon = Icons.Default.Psychology,
                        label = "LLM",
                        value = uiState.llmModel?.name ?: "Not set",
                        color = AppColors.primaryBlue
                    )
                    ModelBadge(
                        icon = Icons.Default.GraphicEq,
                        label = "STT",
                        value = uiState.sttModel?.name ?: "Not set",
                        color = Color(0xFF4CAF50)
                    )
                    ModelBadge(
                        icon = Icons.Default.VolumeUp,
                        label = "TTS",
                        value = uiState.ttsModel?.name ?: "Not set",
                        color = Color(0xFF9C27B0)
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))

                Text(
                    text = "Experimental Feature",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color(0xFFFFA000),
                    modifier = Modifier
                        .background(
                            Color(0xFFFFA000).copy(alpha = 0.1f),
                            RoundedCornerShape(8.dp)
                        )
                        .padding(horizontal = 12.dp, vertical = 4.dp)
                )

                Spacer(modifier = Modifier.height(15.dp))
            }
        }

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
                    .padding(horizontal = 20.dp, vertical = 20.dp)
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
                        modifier = Modifier.padding(bottom = 20.dp)
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
                        modifier = Modifier.padding(bottom = 20.dp)
                    )
                }

                // Placeholder when empty
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
                                modifier = Modifier.size(48.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.3f)
                            )
                            Spacer(modifier = Modifier.height(12.dp))
                            Text(
                                text = "Tap the microphone to start",
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        }

        // Minimal control area
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 30.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Error message (if any)
            uiState.errorMessage?.let { error ->
                Text(
                    text = error,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)
                )
            }

            // Main mic button
            MicrophoneButton(
                isListening = uiState.isListening,
                sessionState = uiState.sessionState,
                isSpeechDetected = uiState.isSpeechDetected,
                hasPermission = hasPermission,
                onToggle = {
                    if (!hasPermission) {
                        onRequestPermission()
                    } else {
                        val state = uiState.sessionState
                        if (state == SessionState.LISTENING ||
                            state == SessionState.SPEAKING ||
                            state == SessionState.PROCESSING ||
                            state == SessionState.CONNECTING
                        ) {
                            onStopSession()
                        } else {
                            onStartSession()
                        }
                    }
                }
            )

            Spacer(modifier = Modifier.height(20.dp))

            // Subtle instruction text
            Text(
                text = getInstructionText(uiState.sessionState),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "This feature is under active development",
                style = MaterialTheme.typography.labelSmall,
                color = Color(0xFFFFA000),
                fontStyle = androidx.compose.ui.text.font.FontStyle.Italic,
                modifier = Modifier.padding(horizontal = 40.dp)
            )
        }
    }
}

@Composable
private fun StatusIndicator(sessionState: SessionState) {
    val color = when (sessionState) {
        SessionState.CONNECTED -> Color.Green
        SessionState.LISTENING -> Color.Red
        SessionState.PROCESSING -> Color.Blue
        SessionState.SPEAKING -> Color.Green
        SessionState.ERROR -> Color.Red
        SessionState.DISCONNECTED -> Color.Gray
        SessionState.CONNECTING -> Color(0xFFFFA000) // Orange
    }

    val animatedScale by animateFloatAsState(
        targetValue = if (sessionState == SessionState.LISTENING) 1.2f else 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1000),
            repeatMode = RepeatMode.Reverse
        ),
        label = "statusScale"
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
    icon: ImageVector,
    label: String,
    value: String,
    color: Color
) {
    Row(
        modifier = Modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            modifier = Modifier.size(12.dp),
            tint = color
        )
        Column {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                fontSize = 9.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(
                text = value,
                style = MaterialTheme.typography.labelSmall,
                fontWeight = FontWeight.Medium,
                maxLines = 1
            )
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
        horizontalAlignment = Alignment.Start
    ) {
        Text(
            text = speaker,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )

        Spacer(modifier = Modifier.height(6.dp))

        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier
                .background(
                    if (isUser) MaterialTheme.colorScheme.surfaceVariant
                    else AppColors.primaryBlue.copy(alpha = 0.08f),
                    RoundedCornerShape(16.dp)
                )
                .padding(12.dp)
                .fillMaxWidth()
        )
    }
}

@Composable
private fun MicrophoneButton(
    isListening: Boolean,
    sessionState: SessionState,
    isSpeechDetected: Boolean,
    hasPermission: Boolean,
    onToggle: () -> Unit
) {
    val backgroundColor = when {
        !hasPermission -> MaterialTheme.colorScheme.error
        sessionState == SessionState.CONNECTING -> Color(0xFFFFA000) // Orange
        sessionState == SessionState.LISTENING -> Color.Red
        sessionState == SessionState.PROCESSING -> AppColors.primaryBlue
        sessionState == SessionState.SPEAKING -> Color.Green
        else -> AppColors.primaryBlue
    }

    val animatedScale by animateFloatAsState(
        targetValue = if (isSpeechDetected) 1.1f else 1f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessLow
        ),
        label = "micScale"
    )

    Box(contentAlignment = Alignment.Center) {
        // Pulsing effect when speech detected
        if (isSpeechDetected) {
            val infiniteTransition = rememberInfiniteTransition(label = "pulse_transition")
            val pulseScale by infiniteTransition.animateFloat(
                initialValue = 1f,
                targetValue = 1.3f,
                animationSpec = infiniteRepeatable(
                    animation = tween(1000),
                    repeatMode = RepeatMode.Reverse
                ),
                label = "pulse"
            )
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .scale(pulseScale)
                    .clip(CircleShape)
                    .border(2.dp, Color.White.copy(alpha = 0.4f), CircleShape)
            )
        }

        FloatingActionButton(
            onClick = onToggle,
            modifier = Modifier
                .size(72.dp)
                .scale(animatedScale),
            containerColor = backgroundColor
        ) {
            when {
                sessionState == SessionState.CONNECTING ||
                        (sessionState == SessionState.PROCESSING && !isListening) -> {
                    CircularProgressIndicator(
                        modifier = Modifier.size(28.dp),
                        color = Color.White,
                        strokeWidth = 2.dp
                    )
                }
                else -> {
                    Icon(
                        imageVector = when {
                            !hasPermission -> Icons.Default.MicOff
                            sessionState == SessionState.LISTENING -> Icons.Default.Mic
                            sessionState == SessionState.SPEAKING -> Icons.Default.VolumeUp
                            else -> Icons.Default.Mic
                        },
                        contentDescription = "Microphone",
                        modifier = Modifier.size(28.dp),
                        tint = Color.White
                    )
                }
            }
        }
    }
}

/**
 * Mock Model Selection Dialog
 *
 * TODO: Replace with actual ModelSelectionSheet matching iOS
 * iOS equivalent: ModelSelectionSheet(context: .stt/.llm/.tts)
 */
@Composable
private fun MockModelSelectionDialog(
    title: String,
    modelType: String,
    onDismiss: () -> Unit,
    onSelectModel: (framework: String, name: String, modelId: String) -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                Text("Select a model for $modelType")
                Spacer(modifier = Modifier.height(16.dp))

                // Mock model options
                val models = when (modelType) {
                    "STT" -> listOf(
                        Triple("WhisperKit", "Whisper Base", "whisper-base"),
                        Triple("WhisperKit", "Whisper Small", "whisper-small"),
                        Triple("ONNX", "Whisper Tiny", "whisper-tiny-onnx")
                    )
                    "LLM" -> listOf(
                        Triple("LlamaCpp", "SmolLM2 135M", "smollm2-135m"),
                        Triple("LlamaCpp", "Llama 3.2 1B", "llama3.2-1b"),
                        Triple("FoundationModels", "Apple FM", "apple-fm")
                    )
                    "TTS" -> listOf(
                        Triple("System", "System Voice", "system-tts"),
                        Triple("Piper", "Jenny", "piper-jenny"),
                        Triple("Piper", "Amy", "piper-amy")
                    )
                    else -> emptyList()
                }

                models.forEach { (framework, name, modelId) ->
                    TextButton(
                        onClick = { onSelectModel(framework, name, modelId) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text(name)
                            Text(
                                framework,
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

private fun getStatusText(sessionState: SessionState): String {
    return when (sessionState) {
        SessionState.DISCONNECTED -> "Ready"
        SessionState.CONNECTING -> "Connecting"
        SessionState.CONNECTED -> "Ready"
        SessionState.LISTENING -> "Listening"
        SessionState.PROCESSING -> "Thinking"
        SessionState.SPEAKING -> "Speaking"
        SessionState.ERROR -> "Error"
    }
}

private fun getInstructionText(sessionState: SessionState): String {
    return when (sessionState) {
        SessionState.LISTENING -> "Listening... Tap to stop"
        SessionState.PROCESSING -> "Processing..."
        SessionState.SPEAKING -> "Speaking..."
        SessionState.CONNECTING -> "Connecting..."
        else -> "Tap to speak"
    }
}
