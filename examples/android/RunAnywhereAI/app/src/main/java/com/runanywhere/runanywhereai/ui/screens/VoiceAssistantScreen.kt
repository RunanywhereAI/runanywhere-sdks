package com.runanywhere.runanywhereai.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.models.VoiceAgentState
import com.runanywhere.runanywhereai.models.VoiceModelLoadState
import com.runanywhere.runanywhereai.models.VoiceSelectedModel
import com.runanywhere.runanywhereai.models.VoiceUiState
import com.runanywhere.runanywhereai.ui.components.MarkdownText
import com.runanywhere.runanywhereai.ui.components.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.components.VoiceOrbCanvas
import com.runanywhere.runanywhereai.ui.icons.RAIcons
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.viewmodels.ModelSelectionViewModel
import com.runanywhere.runanywhereai.viewmodels.VoiceAssistantViewModel
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.min
import kotlin.math.sin

@Composable
fun VoiceAssistantScreen(
    voiceViewModel: VoiceAssistantViewModel = viewModel(),
    modelSelectionViewModel: ModelSelectionViewModel = viewModel(),
) {
    val uiState by voiceViewModel.uiState.collectAsStateWithLifecycle()
    val modelState by modelSelectionViewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current

    var showSTTModelSelection by remember { mutableStateOf(false) }
    var showLLMModelSelection by remember { mutableStateOf(false) }
    var showTTSModelSelection by remember { mutableStateOf(false) }
    var showVoiceSetupSheet by remember { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { isGranted ->
        if (isGranted) {
            voiceViewModel.initialize(context)
        }
    }

    LaunchedEffect(Unit) {
        voiceViewModel.initialize(context)
        voiceViewModel.refreshComponentStatesFromSDK()
    }

    when (val state = uiState) {
        is VoiceUiState.Loading -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }

        is VoiceUiState.Ready -> {
            if (!state.allModelsLoaded) {
                VoicePipelineSetupView(
                    sttModel = state.sttModel,
                    llmModel = state.llmModel,
                    ttsModel = state.ttsModel,
                    sttLoadState = state.sttLoadState,
                    llmLoadState = state.llmLoadState,
                    ttsLoadState = state.ttsLoadState,
                    onSelectSTT = {
                        modelSelectionViewModel.loadModels(ModelSelectionContext.STT)
                        showSTTModelSelection = true
                    },
                    onSelectLLM = {
                        modelSelectionViewModel.loadModels(ModelSelectionContext.LLM)
                        showLLMModelSelection = true
                    },
                    onSelectTTS = {
                        modelSelectionViewModel.loadModels(ModelSelectionContext.TTS)
                        showTTSModelSelection = true
                    },
                )
            } else {
                MainVoiceUI(
                    state = state,
                    hasPermission = ContextCompat.checkSelfPermission(
                        context, Manifest.permission.RECORD_AUDIO,
                    ) == PackageManager.PERMISSION_GRANTED,
                    onRequestPermission = {
                        permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                    },
                    onStartSession = { voiceViewModel.startSession() },
                    onStopSession = { voiceViewModel.stopSession() },
                    onShowModels = { showVoiceSetupSheet = true },
                )
            }
        }

        is VoiceUiState.Error -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    text = state.message,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.error,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(32.dp),
                )
            }
        }
    }

    // Voice setup bottom sheet
    if (showVoiceSetupSheet) {
        VoiceSetupBottomSheet(
            state = uiState as? VoiceUiState.Ready,
            onDismiss = { showVoiceSetupSheet = false },
            onSelectSTT = {
                showVoiceSetupSheet = false
                modelSelectionViewModel.loadModels(ModelSelectionContext.STT)
                showSTTModelSelection = true
            },
            onSelectLLM = {
                showVoiceSetupSheet = false
                modelSelectionViewModel.loadModels(ModelSelectionContext.LLM)
                showLLMModelSelection = true
            },
            onSelectTTS = {
                showVoiceSetupSheet = false
                modelSelectionViewModel.loadModels(ModelSelectionContext.TTS)
                showTTSModelSelection = true
            },
        )
    }

    // Stable model lookup used across all voice model selection sheets
    val currentModels by rememberUpdatedState(modelState.models)

    // Model selection sheets
    if (showSTTModelSelection) {
        ModelSelectionSheet(
            state = modelState,
            onDismiss = { showSTTModelSelection = false },
            onSelectModel = { modelId ->
                val model = currentModels.find { it.id == modelId }
                modelSelectionViewModel.selectModel(modelId) { _, _ ->
                    if (model != null) {
                        voiceViewModel.setSTTModel(model.framework.displayName, model.name, model.id)
                    }
                }
                showSTTModelSelection = false
            },
            onDownloadModel = { modelSelectionViewModel.downloadModel(it) },
            onCancelModelDownload = { modelSelectionViewModel.cancelModelDownload() },
            onLoadLora = {},
            onUnloadLora = {},
            onDownloadLora = {},
            onCancelLoraDownload = {},
            isLoraDownloaded = { false },
            isLoraLoaded = { false },
        )
    }

    if (showLLMModelSelection) {
        ModelSelectionSheet(
            state = modelState,
            onDismiss = { showLLMModelSelection = false },
            onSelectModel = { modelId ->
                val model = currentModels.find { it.id == modelId }
                modelSelectionViewModel.selectModel(modelId) { _, _ ->
                    if (model != null) {
                        voiceViewModel.setLLMModel(model.framework.displayName, model.name, model.id)
                    }
                }
                showLLMModelSelection = false
            },
            onDownloadModel = { modelSelectionViewModel.downloadModel(it) },
            onCancelModelDownload = { modelSelectionViewModel.cancelModelDownload() },
            onLoadLora = {},
            onUnloadLora = {},
            onDownloadLora = {},
            onCancelLoraDownload = {},
            isLoraDownloaded = { false },
            isLoraLoaded = { false },
        )
    }

    if (showTTSModelSelection) {
        ModelSelectionSheet(
            state = modelState,
            onDismiss = { showTTSModelSelection = false },
            onSelectModel = { modelId ->
                val model = currentModels.find { it.id == modelId }
                modelSelectionViewModel.selectModel(modelId) { _, _ ->
                    if (model != null) {
                        voiceViewModel.setTTSModel(model.framework.displayName, model.name, model.id)
                    }
                }
                showTTSModelSelection = false
            },
            onDownloadModel = { modelSelectionViewModel.downloadModel(it) },
            onCancelModelDownload = { modelSelectionViewModel.cancelModelDownload() },
            onLoadLora = {},
            onUnloadLora = {},
            onDownloadLora = {},
            onCancelLoraDownload = {},
            isLoraDownloaded = { false },
            isLoraLoaded = { false },
        )
    }
}

// -- Main Voice UI --

@Composable
private fun MainVoiceUI(
    state: VoiceUiState.Ready,
    hasPermission: Boolean,
    onRequestPermission: () -> Unit,
    onStartSession: () -> Unit,
    onStopSession: () -> Unit,
    onShowModels: () -> Unit,
) {
    val density = LocalDensity.current
    val isDarkMode = isSystemInDarkTheme()

    var amplitude by remember { mutableFloatStateOf(0f) }
    var morphProgress by remember { mutableFloatStateOf(0f) }
    var scatterAmount by remember { mutableFloatStateOf(0f) }
    var touchPoint by remember { mutableStateOf(Offset.Zero) }

    val currentState by rememberUpdatedState(state)

    val isActive by remember {
        derivedStateOf {
            currentState.agentState == VoiceAgentState.LISTENING ||
                currentState.agentState == VoiceAgentState.SPEAKING ||
                amplitude > 0.001f ||
                morphProgress > 0.001f
        }
    }

    LaunchedEffect(isActive, state.agentState) {
        if (isActive) {
            while (true) {
                delay(16L)
                updateOrbAnimation(
                    state = currentState,
                    currentAmplitude = amplitude,
                    onAmplitudeChange = { amplitude = it },
                )

                val targetMorph = if (
                    currentState.agentState == VoiceAgentState.LISTENING ||
                    currentState.agentState == VoiceAgentState.SPEAKING
                ) 1f else 0f
                morphProgress += (targetMorph - morphProgress) * 0.04f
                morphProgress = morphProgress.coerceIn(0f, 1f)

                if (scatterAmount > 0.001f) {
                    scatterAmount *= 0.92f
                } else {
                    scatterAmount = 0f
                }

                val stillNeeded = currentState.agentState == VoiceAgentState.LISTENING ||
                    currentState.agentState == VoiceAgentState.SPEAKING ||
                    amplitude > 0.001f ||
                    morphProgress > 0.001f
                if (!stillNeeded) break
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // Background particle orb — centered, same size always
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
            val orbSize = min(constraints.maxWidth, constraints.maxHeight) * 0.9f

            VoiceOrbCanvas(
                amplitude = amplitude,
                morphProgress = morphProgress,
                scatterAmount = scatterAmount,
                touchPoint = touchPoint,
                isDarkMode = isDarkMode,
                modifier = Modifier
                    .size(with(density) { orbSize.toDp() })
                    .align(Alignment.Center)
                    .offset(y = (-50).dp)
                    .pointerInput(Unit) {
                        detectDragGestures(
                            onDrag = { change, _ ->
                                change.consume()
                                val pos = change.position
                                val w = this.size.width.toFloat()
                                val h = this.size.height.toFloat()
                                val normX = ((pos.x - w / 2f) / (w / 2f)) * 0.85f
                                val normY = -((pos.y - h / 2f) / (h / 2f)) * 0.85f
                                touchPoint = Offset(normX, normY)
                                scatterAmount = 1f
                            },
                        )
                    },
            )
        }

        // Main UI overlay
        Column(modifier = Modifier.fillMaxSize()) {
            // Model badges — only when idle
            AnimatedVisibility(
                visible = state.agentState == VoiceAgentState.IDLE,
                enter = slideInVertically() + fadeIn(),
                exit = slideOutVertically() + fadeOut(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                ) {
                    ModelBadge(RAIcons.Activity, "STT", state.sttModel?.name ?: "Not set", onShowModels)
                    ModelBadge(RAIcons.Sparkles, "LLM", state.llmModel?.name ?: "Not set", onShowModels)
                    ModelBadge(RAIcons.Volume2, "TTS", state.ttsModel?.name ?: "Not set", onShowModels)
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // -- User transcript (what they said) --
            AnimatedVisibility(
                visible = state.currentTranscript.isNotEmpty(),
                enter = fadeIn(AppMotion.tweenMedium()),
                exit = fadeOut(AppMotion.tweenShort()),
            ) {
                Text(
                    text = "\"${state.currentTranscript}\"",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.7f),
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 32.dp, vertical = 4.dp),
                )
            }

            // -- AI response (streaming markdown) --
            val displayText = state.streamingResponse.ifEmpty { state.assistantResponse }

            if (displayText.isNotEmpty()) {
                val scrollState = rememberScrollState()

                LaunchedEffect(displayText.length) {
                    scrollState.scrollTo(scrollState.maxValue)
                }

                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(max = 200.dp)
                        .verticalScroll(scrollState)
                        .padding(horizontal = 24.dp, vertical = 8.dp),
                ) {
                    MarkdownText(
                        text = displayText,
                        style = MaterialTheme.typography.bodyLarge,
                    )
                }
            }

            // -- Controls --
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 30.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                state.error?.let { error ->
                    Text(
                        text = error,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.error,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(horizontal = 20.dp),
                    )
                }

                val stateText by remember(state.agentState) {
                    derivedStateOf { getStateText(state.agentState) }
                }
                AnimatedVisibility(
                    visible = state.agentState != VoiceAgentState.IDLE,
                    enter = fadeIn(AppMotion.tweenMedium()),
                    exit = fadeOut(AppMotion.tweenShort()),
                ) {
                    Text(
                        text = stateText,
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        fontWeight = FontWeight.Medium,
                    )
                }

                MicrophoneButton(
                    agentState = state.agentState,
                    isSpeechDetected = state.isSpeechDetected,
                    hasPermission = hasPermission,
                    onClick = {
                        if (!hasPermission) {
                            onRequestPermission()
                        } else {
                            when (state.agentState) {
                                VoiceAgentState.LISTENING,
                                VoiceAgentState.SPEAKING,
                                VoiceAgentState.THINKING -> onStopSession()
                                VoiceAgentState.IDLE -> onStartSession()
                            }
                        }
                    },
                )

                Text(
                    text = getInstructionText(state.agentState),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

// -- Orb Animation Logic --

private fun updateOrbAnimation(
    state: VoiceUiState.Ready,
    currentAmplitude: Float,
    onAmplitudeChange: (Float) -> Unit,
) {
    val newAmplitude = when (state.agentState) {
        VoiceAgentState.LISTENING -> {
            val realAudioLevel = state.audioLevel
            (currentAmplitude * 0.7f + realAudioLevel * 0.3f).coerceIn(0f, 1f)
        }
        VoiceAgentState.SPEAKING -> {
            val time = System.currentTimeMillis() / 1000f
            val basePulse = 0.35f
            val primaryWave = sin(time * 3.5f) * 0.2f
            val secondaryWave = sin(time * 7.0f) * 0.1f
            val randomNoise = kotlin.random.Random.nextFloat() * 0.2f - 0.05f
            val targetAmplitude = basePulse + abs(primaryWave) + abs(secondaryWave) * 0.5f + randomNoise
            (currentAmplitude * 0.75f + targetAmplitude * 0.25f).coerceIn(0f, 1f)
        }
        else -> {
            val decayed = currentAmplitude * 0.93f
            if (decayed < 0.001f) 0f else decayed
        }
    }
    onAmplitudeChange(newAmplitude)
}

// -- Microphone Button --

@Composable
private fun MicrophoneButton(
    agentState: VoiceAgentState,
    isSpeechDetected: Boolean,
    hasPermission: Boolean,
    onClick: () -> Unit,
) {
    val isThinking = agentState == VoiceAgentState.THINKING

    val backgroundColor by animateColorAsState(
        targetValue = when {
            !hasPermission -> MaterialTheme.colorScheme.error
            agentState == VoiceAgentState.LISTENING -> MaterialTheme.colorScheme.error
            agentState == VoiceAgentState.THINKING -> MaterialTheme.colorScheme.primary
            agentState == VoiceAgentState.SPEAKING -> MaterialTheme.colorScheme.tertiary
            else -> MaterialTheme.colorScheme.primary
        },
        animationSpec = AppMotion.tweenMedium(),
        label = "micBgColor",
    )

    val animatedScale by animateFloatAsState(
        targetValue = if (isSpeechDetected) 1.1f else 1f,
        animationSpec = spring(
            dampingRatio = Spring.DampingRatioMediumBouncy,
            stiffness = Spring.StiffnessLow,
        ),
        label = "micScale",
    )

    Box(contentAlignment = Alignment.Center) {
        if (isSpeechDetected) {
            val infiniteTransition = rememberInfiniteTransition(label = "pulse_transition")
            val pulseScale by infiniteTransition.animateFloat(
                initialValue = 1f,
                targetValue = 1.3f,
                animationSpec = infiniteRepeatable(
                    animation = tween(1000),
                    repeatMode = RepeatMode.Reverse,
                ),
                label = "pulse",
            )
            Box(
                modifier = Modifier
                    .size(72.dp)
                    .scale(pulseScale)
                    .clip(CircleShape)
                    .border(2.dp, Color.White.copy(alpha = 0.4f), CircleShape),
            )
        }

        FloatingActionButton(
            onClick = onClick,
            modifier = Modifier
                .size(72.dp)
                .scale(animatedScale),
            containerColor = backgroundColor,
        ) {
            when {
                isThinking -> {
                    CircularProgressIndicator(
                        modifier = Modifier.size(28.dp),
                        color = Color.White,
                        strokeWidth = 2.dp,
                    )
                }
                else -> {
                    Icon(
                        imageVector = when {
                            !hasPermission -> RAIcons.Mic
                            agentState == VoiceAgentState.LISTENING -> RAIcons.Mic
                            agentState == VoiceAgentState.SPEAKING -> RAIcons.Volume2
                            else -> RAIcons.Mic
                        },
                        contentDescription = "Microphone",
                        modifier = Modifier.size(28.dp),
                        tint = Color.White,
                    )
                }
            }
        }
    }
}

// -- Model Badge --

@Composable
private fun ModelBadge(
    icon: ImageVector,
    label: String,
    value: String,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.1f),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                modifier = Modifier.size(12.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Column {
                Text(
                    text = label,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    text = value,
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Medium),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

// -- Voice Pipeline Setup View --

@Composable
private fun VoicePipelineSetupView(
    sttModel: VoiceSelectedModel?,
    llmModel: VoiceSelectedModel?,
    ttsModel: VoiceSelectedModel?,
    sttLoadState: VoiceModelLoadState,
    llmLoadState: VoiceModelLoadState,
    ttsLoadState: VoiceModelLoadState,
    onSelectSTT: () -> Unit,
    onSelectLLM: () -> Unit,
    onSelectTTS: () -> Unit,
) {
    val allModelsSelected = sttModel != null && llmModel != null && ttsModel != null
    val allModelsLoaded = sttLoadState.isLoaded && llmLoadState.isLoaded && ttsLoadState.isLoaded

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Spacer(modifier = Modifier.height(20.dp))

        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = RAIcons.Mic,
                contentDescription = "Voice Assistant",
                modifier = Modifier.size(48.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
            Text(
                text = "Voice Assistant Setup",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
            )
            Text(
                text = "Voice requires 3 models to work together",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Column(
            modifier = Modifier
                .weight(1f)
                .padding(bottom = 8.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            ModelSetupCard(1, "Speech Recognition", "Converts your voice to text", RAIcons.Activity, sttModel?.framework, sttModel?.name, sttLoadState, onSelectSTT)
            ModelSetupCard(2, "Language Model", "Processes and responds to your input", RAIcons.Sparkles, llmModel?.framework, llmModel?.name, llmLoadState, onSelectLLM)
            ModelSetupCard(3, "Text to Speech", "Converts responses to audio", RAIcons.Volume2, ttsModel?.framework, ttsModel?.name, ttsLoadState, onSelectTTS)
        }

        Text(
            text = when {
                !allModelsSelected -> "Select all 3 models to continue"
                !allModelsLoaded -> "Waiting for models to load..."
                else -> "All models loaded and ready!"
            },
            style = MaterialTheme.typography.labelMedium,
            color = when {
                !allModelsSelected -> MaterialTheme.colorScheme.onSurfaceVariant
                !allModelsLoaded -> MaterialTheme.colorScheme.tertiary
                else -> MaterialTheme.colorScheme.primary
            },
        )
        Spacer(modifier = Modifier.height(10.dp))
    }
}

// -- Model Setup Card --

@Composable
private fun ModelSetupCard(
    step: Int,
    title: String,
    subtitle: String,
    icon: ImageVector,
    selectedFramework: String?,
    selectedModel: String?,
    loadState: VoiceModelLoadState,
    onSelect: () -> Unit,
) {
    val isConfigured = selectedFramework != null && selectedModel != null
    val isLoaded = loadState.isLoaded
    val isLoading = loadState.isLoading

    val borderColor = when {
        isLoaded -> MaterialTheme.colorScheme.primary
        isLoading -> MaterialTheme.colorScheme.tertiary
        isConfigured -> MaterialTheme.colorScheme.outline
        else -> Color.Transparent
    }

    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .then(
                if (borderColor != Color.Transparent) {
                    Modifier.border(2.dp, borderColor.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                } else {
                    Modifier
                },
            )
            .clickable(onClick = onSelect),
        shape = RoundedCornerShape(12.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .clip(CircleShape)
                    .background(
                        when {
                            isLoading -> MaterialTheme.colorScheme.tertiary
                            isLoaded -> MaterialTheme.colorScheme.primary
                            isConfigured -> MaterialTheme.colorScheme.outline
                            else -> MaterialTheme.colorScheme.surfaceContainerHighest
                        },
                    ),
                contentAlignment = Alignment.Center,
            ) {
                when {
                    isLoading -> CircularProgressIndicator(Modifier.size(18.dp), color = Color.White, strokeWidth = 2.dp)
                    isLoaded -> Icon(RAIcons.Check, "Loaded", Modifier.size(18.dp), tint = Color.White)
                    isConfigured -> Icon(RAIcons.Check, "Configured", Modifier.size(18.dp), tint = Color.White)
                    else -> Text("$step", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            Spacer(modifier = Modifier.width(16.dp))

            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(icon, title, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(title, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold))
                }
                Spacer(modifier = Modifier.height(4.dp))
                if (isConfigured) {
                    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                        Text(
                            "$selectedFramework \u00B7 $selectedModel",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        if (isLoading) {
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Loading...", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.tertiary)
                        }
                    }
                } else {
                    Text(subtitle, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }

            when {
                isLoading -> CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                isLoaded -> Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(RAIcons.CircleCheck, "Loaded", Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(4.dp))
                    Text("Loaded", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                }
                isConfigured -> Text("Change", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
                else -> Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Select", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.width(2.dp))
                    Icon(RAIcons.ChevronRight, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}

// -- Voice Setup Bottom Sheet --

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun VoiceSetupBottomSheet(
    state: VoiceUiState.Ready?,
    onDismiss: () -> Unit,
    onSelectSTT: () -> Unit,
    onSelectLLM: () -> Unit,
    onSelectTTS: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        if (state != null) {
            VoicePipelineSetupView(
                sttModel = state.sttModel,
                llmModel = state.llmModel,
                ttsModel = state.ttsModel,
                sttLoadState = state.sttLoadState,
                llmLoadState = state.llmLoadState,
                ttsLoadState = state.ttsLoadState,
                onSelectSTT = onSelectSTT,
                onSelectLLM = onSelectLLM,
                onSelectTTS = onSelectTTS,
            )
        }
    }
}

// -- Utility --

private fun getStateText(state: VoiceAgentState): String = when (state) {
    VoiceAgentState.IDLE -> "Ready"
    VoiceAgentState.LISTENING -> "Listening"
    VoiceAgentState.THINKING -> "Thinking"
    VoiceAgentState.SPEAKING -> "Speaking"
}

private fun getInstructionText(state: VoiceAgentState): String = when (state) {
    VoiceAgentState.LISTENING -> "Listening... Pause to send"
    VoiceAgentState.THINKING -> "Processing your message..."
    VoiceAgentState.SPEAKING -> "Speaking..."
    VoiceAgentState.IDLE -> "Tap to start conversation"
}
