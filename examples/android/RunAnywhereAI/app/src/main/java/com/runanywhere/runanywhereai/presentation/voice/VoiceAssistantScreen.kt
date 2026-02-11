package com.runanywhere.runanywhereai.presentation.voice

import android.Manifest
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.animation.core.EaseInOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlin.math.abs
import kotlin.math.sin
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.ui.text.style.TextOverflow
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import com.runanywhere.runanywhereai.domain.models.SessionState
import com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppTypography
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import kotlin.math.min

/**
 * Voice Assistant screen
 *
 * This screen shows:
 * - VoicePipelineSetupView when not all models are loaded
 * - Main voice UI with conversation bubbles when ready
 *
 * Complete voice pipeline UI with VAD, STT, LLM, and TTS
 */
@OptIn(ExperimentalPermissionsApi::class, ExperimentalMaterial3Api::class)
@Composable
fun VoiceAssistantScreen(viewModel: VoiceAssistantViewModel = viewModel()) {
    val uiState by viewModel.uiState.collectAsState()
    val context = LocalContext.current
    var showModelInfo by remember { mutableStateOf(false) }

    // Model selection dialog states
    var showSTTModelSelection by remember { mutableStateOf(false) }
    var showLLMModelSelection by remember { mutableStateOf(false) }
    var showTTSModelSelection by remember { mutableStateOf(false) }
    var showVoiceSetupSheet by remember { mutableStateOf(false) }

    // Permission handling
    val microphonePermissionState =
        rememberPermissionState(
            Manifest.permission.RECORD_AUDIO,
        )

    // Initialize audio capture service and refresh model states when the screen appears
    // This ensures that:
    // 1. Audio capture is ready when user starts the session
    // 2. Models loaded from other screens (e.g., Chat) are reflected here
    LaunchedEffect(Unit) {
        viewModel.initialize(context)
        viewModel.refreshComponentStatesFromSDK()
    }

    // Re-initialize when permission is granted
    LaunchedEffect(microphonePermissionState.status.isGranted) {
        if (microphonePermissionState.status.isGranted) {
            viewModel.initialize(context)
        }
    }

    // When !allModelsLoaded show VoicePipelineSetupView as main content; when loaded show mainVoiceUI with Scaffold
    Scaffold(
        topBar = {
            if (uiState.allModelsLoaded) {
                // Header - cube 18pt, info 18pt, padding horizontal 20, top 20, bottom 10, no title
                TopAppBar(
                    title = { Text("Voice", style = MaterialTheme.typography.headlineMedium) },
                    actions = {
                        IconButton(
                            onClick = { showVoiceSetupSheet = true },
                            modifier = Modifier.size(38.dp),
                        ) {
                            Icon(
                                imageVector = Icons.Default.ViewInAr,
                                contentDescription = "Models",
                                modifier = Modifier.size(18.dp),
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        IconButton(
                            onClick = { showModelInfo = !showModelInfo },
                            modifier = Modifier.size(38.dp),
                        ) {
                            Icon(
                                imageVector = if (showModelInfo) Icons.Filled.Info else Icons.Outlined.Info,
                                contentDescription = if (showModelInfo) "Hide Info" else "Show Info",
                                modifier = Modifier.size(18.dp),
                                tint = if (showModelInfo) AppColors.primaryAccent else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    },
                    colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
                )
            }
        },
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .background(MaterialTheme.colorScheme.background),
        ) {
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
                    onStartVoice = {},
                )
            } else {
                MainVoiceAssistantUI(
                    uiState = uiState,
                    showModelInfo = showModelInfo,
                    onToggleModelInfo = { showModelInfo = !showModelInfo },
                    hasPermission = microphonePermissionState.status.isGranted,
                    onRequestPermission = { microphonePermissionState.launchPermissionRequest() },
                    onStartSession = { viewModel.startSession() },
                    onStopSession = { viewModel.stopSession() },
                    onClearConversation = { viewModel.clearConversation() },
                )
            }
        }
    }

    if (showVoiceSetupSheet) {
        ModalBottomSheet(onDismissRequest = { showVoiceSetupSheet = false }) {
            VoicePipelineSetupView(
                sttModel = uiState.sttModel,
                llmModel = uiState.llmModel,
                ttsModel = uiState.ttsModel,
                sttLoadState = uiState.sttLoadState,
                llmLoadState = uiState.llmLoadState,
                ttsLoadState = uiState.ttsLoadState,
                onSelectSTT = { showVoiceSetupSheet = false; showSTTModelSelection = true },
                onSelectLLM = { showVoiceSetupSheet = false; showLLMModelSelection = true },
                onSelectTTS = { showVoiceSetupSheet = false; showTTSModelSelection = true },
                onStartVoice = { showVoiceSetupSheet = false },
            )
        }
    }

    // Model selection bottom sheets - uses real SDK models
    // ModelSelectionSheet(context: .stt/.llm/.tts)
    if (showSTTModelSelection) {
        ModelSelectionBottomSheet(
            context = ModelSelectionContext.STT,
            onDismiss = { showSTTModelSelection = false },
            onModelSelected = { model ->
                val framework = model.framework.displayName
                viewModel.setSTTModel(framework, model.name, model.id)
                showSTTModelSelection = false
            },
        )
    }

    if (showLLMModelSelection) {
        ModelSelectionBottomSheet(
            context = ModelSelectionContext.LLM,
            onDismiss = { showLLMModelSelection = false },
            onModelSelected = { model ->
                val framework = model.framework.displayName
                viewModel.setLLMModel(framework, model.name, model.id)
                showLLMModelSelection = false
            },
        )
    }

    if (showTTSModelSelection) {
        ModelSelectionBottomSheet(
            context = ModelSelectionContext.TTS,
            onDismiss = { showTTSModelSelection = false },
            onModelSelected = { model ->
                val framework = model.framework.displayName
                viewModel.setTTSModel(framework, model.name, model.id)
                showTTSModelSelection = false
            },
        )
    }
}

/**
 * Voice Pipeline Setup View
 *
 * VoicePipelineSetupView
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
    onStartVoice: () -> Unit,
) {
    val allModelsReady = sttModel != null && llmModel != null && ttsModel != null
    val allModelsLoaded = sttLoadState.isLoaded && llmLoadState.isLoaded && ttsLoadState.isLoaded

    // VStack(spacing: 24), .padding(.top, 20), icon 48pt, .title2 .bold, .subheadline .secondary
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = Dimensions.padding16),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(24.dp),
    ) {
        Spacer(modifier = Modifier.height(20.dp))

        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(
                imageVector = Icons.Default.Mic,
                contentDescription = "Voice Assistant",
                modifier = Modifier.size(48.dp),
                tint = AppColors.primaryAccent,
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

        // VStack(spacing: 16), .padding(.horizontal)
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            ModelSetupCard(
                step = 1,
                title = "Speech Recognition",
                subtitle = "Converts your voice to text",
                icon = Icons.Default.GraphicEq,
                color = AppColors.primaryGreen,
            selectedFramework = sttModel?.framework,
            selectedModel = sttModel?.name,
            loadState = sttLoadState,
                onSelect = onSelectSTT,
            )
            ModelSetupCard(
            step = 2,
            title = "Language Model",
            subtitle = "Processes and responds to your input",
            icon = Icons.Default.Psychology,
            color = AppColors.primaryAccent,
            selectedFramework = llmModel?.framework,
            selectedModel = llmModel?.name,
            loadState = llmLoadState,
                onSelect = onSelectLLM,
            )
            ModelSetupCard(
                step = 3,
                title = "Text to Speech",
                subtitle = "Converts responses to audio",
                icon = Icons.Default.VolumeUp,
                color = AppColors.primaryPurple,
                selectedFramework = ttsModel?.framework,
                selectedModel = ttsModel?.name,
                loadState = ttsLoadState,
                onSelect = onSelectTTS,
            )
        }

        // Button .headline, .padding(.vertical, 16), .padding(.bottom, 20)
        Button(
            onClick = onStartVoice,
            enabled = allModelsLoaded,
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 16.dp),
            colors = ButtonDefaults.buttonColors(containerColor = AppColors.primaryAccent),
        ) {
            Icon(Icons.Default.Mic, contentDescription = null, modifier = Modifier.size(20.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = "Start Voice Assistant",
                style = MaterialTheme.typography.headlineMedium,
            )
        }

        // .font(.caption), .padding(.bottom, 10)
        Text(
            text = when {
                !allModelsReady -> "Select all 3 models to continue"
                !allModelsLoaded -> "Waiting for models to load..."
                else -> "All models loaded and ready!"
            },
            style = MaterialTheme.typography.labelMedium,
            color = when {
                !allModelsReady -> MaterialTheme.colorScheme.onSurfaceVariant
                !allModelsLoaded -> AppColors.statusOrange
                else -> AppColors.primaryGreen
            },
        )
        Spacer(modifier = Modifier.height(10.dp))
    }
}

/**
 * Model Setup Card
 *
 * ModelSetupCard
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
    onSelect: () -> Unit,
) {
    val isConfigured = selectedFramework != null && selectedModel != null
    val isLoaded = loadState.isLoaded
    val isLoading = loadState.isLoading

    Card(
        modifier =
            Modifier
                .fillMaxWidth()
                .clickable(onClick = onSelect)
                .then(
                    if (isLoaded) {
                        Modifier.border(2.dp, AppColors.primaryGreen.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                    } else if (isLoading) {
                        Modifier.border(2.dp, AppColors.statusOrange.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                    } else if (isConfigured) {
                        Modifier.border(2.dp, color.copy(alpha = 0.5f), RoundedCornerShape(12.dp))
                    } else {
                        Modifier
                    },
                ),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Step indicator with loading/loaded state
            Box(
                modifier =
                    Modifier
                        .size(36.dp)
                        .clip(CircleShape)
                        .background(
                            when {
                                isLoading -> AppColors.statusOrange
                                isLoaded -> AppColors.primaryGreen
                                isConfigured -> color
                                else -> AppColors.statusGray.copy(alpha = 0.2f)
                            },
                        ),
                contentAlignment = Alignment.Center,
            ) {
                when {
                    isLoading -> {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            color = Color.White,
                            strokeWidth = 2.dp,
                        )
                    }
                    isLoaded -> {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = "Loaded",
                            modifier = Modifier.size(18.dp),
                            tint = Color.White,
                        )
                    }
                    isConfigured -> {
                        Icon(
                            imageVector = Icons.Default.Check,
                            contentDescription = "Configured",
                            modifier = Modifier.size(18.dp),
                            tint = Color.White,
                        )
                    }
                    else -> {
                        Text(
                            text = "$step",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            color = AppColors.statusGray,
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
                        modifier = Modifier.size(16.dp),
                        tint = color,
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = title,
                        style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                    )
                }

                Spacer(modifier = Modifier.height(4.dp))

                if (isConfigured) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(
                            text = "$selectedFramework • $selectedModel",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f),
                        )
                        if (isLoading) {
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(
                                text = "Loading...",
                                style = AppTypography.caption2,
                                color = AppColors.statusOrange,
                            )
                        }
                    }
                } else {
                    Text(
                        text = subtitle,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            // Action / Status
            when {
                isLoading -> {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        strokeWidth = 2.dp,
                    )
                }
                isLoaded -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = "Loaded",
                            modifier = Modifier.size(16.dp),
                            tint = AppColors.primaryGreen,
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = "Loaded",
                            style = MaterialTheme.typography.labelMedium,
                            color = AppColors.primaryGreen,
                        )
                    }
                }
                isConfigured -> {
                    Text(
                        text = "Change",
                        style = MaterialTheme.typography.labelMedium,
                        color = AppColors.primaryAccent,
                    )
                }
                else -> {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            text = "Select",
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Medium,
                            color = AppColors.primaryAccent,
                        )
                        Spacer(modifier = Modifier.width(2.dp))
                        Icon(
                            imageVector = Icons.Default.ChevronRight,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = AppColors.primaryAccent,
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
 * Main voice UI (shown when allModelsLoaded)
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
    @Suppress("UNUSED_PARAMETER") onClearConversation: () -> Unit,
) {
    val density = LocalDensity.current

    // Particle animation state
    var amplitude by remember { mutableStateOf(0f) }
    var morphProgress by remember { mutableStateOf(0f) }
    var scatterAmount by remember { mutableStateOf(0f) }
    var touchPoint by remember { mutableStateOf(Offset.Zero) }
    val isDarkMode = isSystemInDarkTheme()

    // Determine if animation should be active to save battery/CPU
    // Only run when: listening, speaking, scatter recovering, or morph transitioning
    val isListening = uiState.sessionState == SessionState.LISTENING
    val isSpeaking = uiState.sessionState == SessionState.SPEAKING
    val isAnimationNeeded = isListening || isSpeaking || scatterAmount > 0.001f ||
        (morphProgress > 0.001f && morphProgress < 0.999f)

    // Animation timer (60 FPS = ~16ms) - only runs when animation is needed
    LaunchedEffect(isAnimationNeeded) {
        if (isAnimationNeeded) {
            while (true) {
                delay(16) // ~60 FPS
                updateAnimation(
                    uiState = uiState,
                    amplitudeState = { amplitude },
                    morphProgressState = { morphProgress },
                    scatterAmountState = { scatterAmount },
                    onAmplitudeChange = { amplitude = it },
                    onMorphProgressChange = { morphProgress = it },
                    onScatterAmountChange = { scatterAmount = it },
                )
                // Re-check if animation is still needed
                val stillNeeded = uiState.sessionState == SessionState.LISTENING ||
                    uiState.sessionState == SessionState.SPEAKING ||
                    scatterAmount > 0.001f ||
                    (morphProgress > 0.001f && morphProgress < 0.999f)
                if (!stillNeeded) break
            }
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        // Background particle animation - centered
        // Particle animation setup
        BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
            val size = min(constraints.maxWidth, constraints.maxHeight) * 0.9f
            val centerX = size / 2f
            val centerY = size / 2f

            VoiceAssistantParticleView(
                amplitude = amplitude,
                morphProgress = morphProgress,
                scatterAmount = scatterAmount,
                touchPoint = touchPoint,
                isDarkMode = isDarkMode,
                modifier = Modifier
                    .size(with(density) { size.toDp() })
                    .align(Alignment.Center)
                    .offset(y = with(density) { (-50).dp })
                    .pointerInput(Unit) {
                        detectTapGestures { offset ->
                            // Convert touch to normalized coordinates (-1 to 1)
                            // Coordinate system
                            val normalizedX = ((offset.x - centerX) / (size / 2f)) * 0.85f
                            val normalizedY = ((offset.y - centerY) / (size / 2f)) * -0.85f // Flip Y

                            touchPoint = Offset(normalizedX, normalizedY)
                            scatterAmount = 1.0f
                        }
                    },
            )
        }

        // Main UI overlay
        Column(
            modifier = Modifier.fillMaxSize(),
        ) {
        // Model info section - VStack spacing 8, HStack spacing 15, padding horizontal 20, padding bottom 15
        AnimatedVisibility(
            visible = showModelInfo,
            enter = slideInVertically() + fadeIn(),
            exit = slideOutVertically() + fadeOut(),
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .padding(bottom = 15.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(15.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    ModelBadge(
                        icon = Icons.Default.Psychology,
                        label = "LLM",
                        value = uiState.llmModel?.name ?: "Not set",
                        color = AppColors.primaryAccent,
                    )
                    ModelBadge(
                        icon = Icons.Default.GraphicEq,
                        label = "STT",
                        value = uiState.sttModel?.name ?: "Not set",
                        color = AppColors.primaryGreen,
                    )
                    ModelBadge(
                        icon = Icons.Default.VolumeUp,
                        label = "TTS",
                        value = uiState.ttsModel?.name ?: "Not set",
                        color = AppColors.primaryPurple,
                    )
                }
            }
        }

        // Conversation area is now hidden - messages shown as toast at bottom
        Spacer(modifier = Modifier.weight(1f))

        // Control area - VStack spacing 20, error .caption, response maxHeight 150 padding H 30, mic, instruction .caption2, padding bottom 30
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Error message
            uiState.errorMessage?.let { error ->
                Text(
                    text = error,
                    style = MaterialTheme.typography.labelMedium, // .caption
                    color = AppColors.statusRed,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )
            }

            // Main mic button section
            // Mic button section
            micButtonSection(
                uiState = uiState,
                hasPermission = hasPermission,
                onRequestPermission = onRequestPermission,
                onStartSession = onStartSession,
                onStopSession = onStopSession,
            )

            // Instruction text
            // .caption2, .secondary.opacity(0.7)
            Text(
                text = getInstructionText(uiState.sessionState),
                style = AppTypography.caption2,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                textAlign = TextAlign.Center,
            )
        }
        }
    }
}

/**
 * Update animation state
 */
private fun updateAnimation(
    uiState: VoiceUiState,
    amplitudeState: () -> Float,
    morphProgressState: () -> Float,
    scatterAmountState: () -> Float,
    onAmplitudeChange: (Float) -> Unit,
    onMorphProgressChange: (Float) -> Unit,
    onScatterAmountChange: (Float) -> Unit,
) {
    // Target morph: 0 = sphere (idle/thinking), 1 = ring (listening/speaking)
    val isListening = uiState.sessionState == SessionState.LISTENING
    val isSpeaking = uiState.sessionState == SessionState.SPEAKING
    val isActive = isListening || isSpeaking
    val targetMorph = if (isActive) 1.0f else 0.0f

    // Smooth morph transition
    val currentMorph = morphProgressState()
    val morphDiff = targetMorph - currentMorph
    onMorphProgressChange((currentMorph + morphDiff * 0.04f).coerceIn(0f, 1f))

    // Scatter decay
    val currentScatter = scatterAmountState()
    if (currentScatter > 0.001f) {
        onScatterAmountChange(currentScatter * 0.92f)
    } else {
        onScatterAmountChange(0f)
    }

    // Audio amplitude - reactive to both input (listening) and output (speaking)
    val currentAmplitude = amplitudeState()
    val newAmplitude = when {
        isListening -> {
            // Use real audio level from microphone
            val realAudioLevel = uiState.audioLevel
            // Smooth interpolation for natural movement
            (currentAmplitude * 0.7f + realAudioLevel * 0.3f).coerceIn(0f, 1f)
        }
        isSpeaking -> {
            // TTS output - realistic speech-like pulse simulation
            val time = System.currentTimeMillis() / 1000f

            // Multiple frequency components for natural speech rhythm
            val basePulse = 0.35f
            val primaryWave = sin(time * 3.5f) * 0.2f // Main speech rhythm
            val secondaryWave = sin(time * 7.0f) * 0.1f // Phoneme-like variation
            val randomNoise = kotlin.random.Random.nextFloat() * 0.2f - 0.05f // Natural variation

            val targetAmplitude = basePulse + abs(primaryWave) + abs(secondaryWave) * 0.5f + randomNoise

            // Smooth interpolation to avoid jarring changes
            (currentAmplitude * 0.75f + targetAmplitude * 0.25f).coerceIn(0f, 1f)
        }
        else -> {
            // Gentle decay when not active
            currentAmplitude * 0.95f
        }
    }
    onAmplitudeChange(newAmplitude)
}

/**
 * Mic button section
 */
@Composable
private fun micButtonSection(
    uiState: VoiceUiState,
    hasPermission: Boolean,
    onRequestPermission: () -> Unit,
    onStartSession: () -> Unit,
    onStopSession: () -> Unit,
) {
    val isLoading = uiState.sessionState == SessionState.CONNECTING ||
        (uiState.sessionState == SessionState.PROCESSING && !uiState.isListening)

    Row(modifier = Modifier.fillMaxWidth()) {
        Spacer(modifier = Modifier.weight(1f))

        MicrophoneButton(
            isListening = uiState.isListening,
            sessionState = uiState.sessionState,
            isSpeechDetected = uiState.isSpeechDetected,
            hasPermission = hasPermission,
            isLoading = isLoading,
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
            },
        )

        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
private fun StatusIndicator(sessionState: SessionState) {
    val color =
        when (sessionState) {
            SessionState.CONNECTED -> AppColors.statusGreen
            SessionState.LISTENING -> AppColors.statusRed
            SessionState.PROCESSING -> AppColors.primaryAccent
            SessionState.SPEAKING -> AppColors.statusGreen
            SessionState.ERROR -> AppColors.statusRed
            SessionState.DISCONNECTED -> AppColors.statusGray
            SessionState.CONNECTING -> AppColors.statusOrange
        }

    val animatedScale by animateFloatAsState(
        targetValue = if (sessionState == SessionState.LISTENING) 1.2f else 1f,
        animationSpec =
            infiniteRepeatable(
                animation = tween(1000),
                repeatMode = RepeatMode.Reverse,
            ),
        label = "statusScale",
    )

    Box(
        modifier =
            Modifier
                .size(8.dp)
                .scale(if (sessionState == SessionState.LISTENING) animatedScale else 1f)
                .clip(CircleShape)
                .background(color),
    )
}

@Composable
private fun ModelBadge(
    icon: ImageVector,
    label: String,
    value: String,
    color: Color,
) {
    // Badge font size 9, label badgeFontSize-1 (8), value badgeFontSize (9) medium, padding H 8 V 4, cornerRadius 6, spacing 4
    Row(
        modifier = Modifier
            .background(color.copy(alpha = 0.1f), RoundedCornerShape(6.dp))
            .padding(horizontal = 8.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = label,
            modifier = Modifier.size(12.dp),
            tint = color,
        )
        Column {
            Text(
                text = label,
                style = AppTypography.system9,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = value,
                style = AppTypography.system9.copy(fontWeight = FontWeight.Medium),
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun ConversationBubble(
    speaker: String,
    message: String,
    isUser: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.Start,
    ) {
        Text(
            text = speaker,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(6.dp))

        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            modifier =
                Modifier
                    .background(
                        if (isUser) {
                            MaterialTheme.colorScheme.surfaceVariant
                        } else {
                            AppColors.primaryAccent.copy(alpha = 0.08f)
                        },
                        RoundedCornerShape(16.dp),
                    )
                    .padding(12.dp)
                    .fillMaxWidth(),
        )
    }
}

/**
 * Audio Level Indicator with RECORDING badge and animated bars
 *
 * Recording indicator
 * Shows 10 animated audio level bars during recording
 */
@Composable
private fun AudioLevelIndicator(
    audioLevel: Float,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Recording status badge
        // HStack with red circle + "RECORDING" text
        Row(
            modifier =
                Modifier
                    .background(
                        AppColors.statusRed.copy(alpha = 0.1f),
                        RoundedCornerShape(4.dp),
                    )
                    .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            // Pulsing red dot
            val infiniteTransition = rememberInfiniteTransition(label = "recording_pulse")
            val pulseAlpha by infiniteTransition.animateFloat(
                initialValue = 1f,
                targetValue = 0.5f,
                animationSpec =
                    infiniteRepeatable(
                        animation = tween(500),
                        repeatMode = RepeatMode.Reverse,
                    ),
                label = "recordingDotPulse",
            )
            Box(
                modifier =
                    Modifier
                        .size(8.dp)
                        .clip(CircleShape)
                        .background(AppColors.statusRed.copy(alpha = pulseAlpha)),
            )
            Text(
                text = "RECORDING",
                style = AppTypography.caption2Bold,
                color = AppColors.statusRed,
            )
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Audio level bars (10 bars)
        Row(
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            repeat(10) { index ->
                val isActive = index < (audioLevel * 10).toInt()
                Box(
                    modifier =
                        Modifier
                            .width(25.dp)
                            .height(8.dp)
                            .clip(RoundedCornerShape(2.dp))
                            .background(
                                if (isActive) AppColors.primaryGreen
                                else AppColors.statusGray.copy(alpha = 0.3f),
                            )
                            .animateContentSize(
                                animationSpec = tween(200, easing = EaseInOut),
                            ),
                )
            }
        }
    }
}

@Composable
private fun MicrophoneButton(
    isListening: Boolean,
    sessionState: SessionState,
    isSpeechDetected: Boolean,
    hasPermission: Boolean,
    isLoading: Boolean = false,
    onToggle: () -> Unit,
) {
    val backgroundColor =
        when {
            !hasPermission -> AppColors.statusRed
            sessionState == SessionState.CONNECTING -> AppColors.statusOrange
            sessionState == SessionState.LISTENING -> AppColors.statusRed
            sessionState == SessionState.PROCESSING -> AppColors.primaryAccent
            sessionState == SessionState.SPEAKING -> AppColors.statusGreen
            else -> AppColors.primaryAccent
        }

    val animatedScale by animateFloatAsState(
        targetValue = if (isSpeechDetected) 1.1f else 1f,
        animationSpec =
            spring(
                dampingRatio = Spring.DampingRatioMediumBouncy,
                stiffness = Spring.StiffnessLow,
            ),
        label = "micScale",
    )

    Box(contentAlignment = Alignment.Center) {
        // Pulsing effect when speech detected
        if (isSpeechDetected) {
            val infiniteTransition = rememberInfiniteTransition(label = "pulse_transition")
            val pulseScale by infiniteTransition.animateFloat(
                initialValue = 1f,
                targetValue = 1.3f,
                animationSpec =
                    infiniteRepeatable(
                        animation = tween(1000),
                        repeatMode = RepeatMode.Reverse,
                    ),
                label = "pulse",
            )
            Box(
                modifier =
                    Modifier
                        .size(72.dp)
                        .scale(pulseScale)
                        .clip(CircleShape)
                        .border(2.dp, Color.White.copy(alpha = 0.4f), CircleShape),
            )
        }

        FloatingActionButton(
            onClick = onToggle,
            modifier =
                Modifier
                    .size(72.dp)
                    .scale(animatedScale),
            containerColor = backgroundColor,
        ) {
            when {
                isLoading -> {
                    CircularProgressIndicator(
                        modifier = Modifier.size(28.dp),
                        color = Color.White,
                        strokeWidth = 2.dp,
                    )
                }
                else -> {
                    Icon(
                        imageVector =
                            when {
                                !hasPermission -> Icons.Default.MicOff
                                sessionState == SessionState.LISTENING -> Icons.Default.Mic
                                sessionState == SessionState.SPEAKING -> Icons.Default.VolumeUp
                                else -> Icons.Default.Mic
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

/**
 * Get instruction text
 */
private fun getInstructionText(sessionState: SessionState): String {
    return when (sessionState) {
        SessionState.LISTENING -> "Listening... Pause to send"
        SessionState.PROCESSING -> "Processing your message..."
        SessionState.SPEAKING -> "Speaking..."
        SessionState.CONNECTING -> "Connecting..."
        else -> "Tap to start conversation"
    }
}
