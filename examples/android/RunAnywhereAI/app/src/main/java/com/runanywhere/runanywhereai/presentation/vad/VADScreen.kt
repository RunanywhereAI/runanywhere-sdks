package com.runanywhere.runanywhereai.presentation.vad

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
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.ViewInAr
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.models.ModelSelectionContext
import com.runanywhere.runanywhereai.presentation.chat.components.ModelLoadedToast
import com.runanywhere.runanywhereai.presentation.chat.components.ModelRequiredOverlay
import com.runanywhere.runanywhereai.presentation.components.ConfigureTopBar
import com.runanywhere.runanywhereai.presentation.models.ModelSelectionBottomSheet
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.util.getModelLogoResIdForName
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Cyan accent used by the VAD screen to match the iOS [VoiceActivityDetectionView]
 * reference design (iOS uses `.cyan` for the ready/inactive states and a green
 * pulse when speech is detected).
 */
private val VadCyan = Color(0xFF00BCD4)

/**
 * Voice Activity Detection Screen
 *
 * iOS Reference: VoiceActivityDetectionView.swift
 *
 * Features:
 * - Speech detected/silence indicator with pulse animation
 * - Audio level meter (green bars)
 * - Activity log of speech start/end events
 * - Model selector chip in app bar
 * - 30ms detection loop processing 1024-byte (32ms @ 16kHz) frames via
 *   `RunAnywhere.detectVoiceActivity()`
 */
@Composable
fun VADScreen(
    onBack: () -> Unit = {},
    viewModel: VADViewModel = viewModel(),
) {
    val context = LocalContext.current
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    var showModelPicker by remember { mutableStateOf(false) }
    var showModelLoadedToast by remember { mutableStateOf(false) }
    var loadedModelToastName by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        viewModel.initialize(context)
    }

    DisposableEffect(Unit) {
        onDispose {
            viewModel.cleanup()
        }
    }

    val permissionLauncher =
        rememberLauncherForActivityResult(
            contract = ActivityResultContracts.RequestPermission(),
        ) { isGranted ->
            if (isGranted) {
                viewModel.initialize(context)
                viewModel.toggleListening()
            }
        }

    ConfigureTopBar(
        title = "Voice Activity Detection",
        showBack = true,
        onBack = onBack,
        actions = {
            if (uiState.isModelLoaded) {
                Surface(
                    onClick = { showModelPicker = true },
                    shape = RoundedCornerShape(50),
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                ) {
                    VADModelChip(
                        modelName = uiState.selectedModelName,
                        modifier =
                            Modifier.padding(
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
        if (uiState.isModelLoaded) {
            Column(modifier = Modifier.fillMaxSize()) {
                MainContent(
                    state = uiState,
                    onClearLog = { viewModel.clearLog() },
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

                ControlsSection(
                    isListening = uiState.isListening,
                    isProcessing = uiState.isProcessing,
                    isSpeechDetected = uiState.isSpeechDetected,
                    onToggleListening = {
                        val hasPermission =
                            ContextCompat.checkSelfPermission(
                                context,
                                Manifest.permission.RECORD_AUDIO,
                            ) == PackageManager.PERMISSION_GRANTED
                        if (hasPermission) {
                            viewModel.toggleListening()
                        } else {
                            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                        }
                    },
                )
            }
        }

        if (!uiState.isModelLoaded && !uiState.isProcessing) {
            ModelRequiredOverlay(
                modality = ModelSelectionContext.VAD,
                onSelectModel = { showModelPicker = true },
                modifier = Modifier.matchParentSize(),
            )
        }

        ModelLoadedToast(
            modelName = loadedModelToastName,
            isVisible = showModelLoadedToast,
            onDismiss = { showModelLoadedToast = false },
            modifier = Modifier.align(Alignment.TopCenter),
        )
    }

    if (showModelPicker) {
        ModelSelectionBottomSheet(
            context = ModelSelectionContext.VAD,
            onDismiss = { showModelPicker = false },
            onModelSelected = { model ->
                scope.launch {
                    viewModel.onModelLoaded(
                        modelName = model.name,
                        modelId = model.id,
                        framework = model.framework,
                    )
                    loadedModelToastName = model.name
                    showModelLoadedToast = true
                }
            },
        )
    }
}

/**
 * Centerpiece of the screen: ready prompt when idle, otherwise speech
 * indicator + activity log (mirrors iOS mainContentView).
 */
@Composable
private fun MainContent(
    state: VADUiState,
    onClearLog: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier = modifier.fillMaxSize()) {
        if (!state.isListening && state.activityLog.isEmpty()) {
            ReadyStateVAD(modifier = Modifier.fillMaxSize())
        } else {
            Column(
                modifier =
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Spacer(modifier = Modifier.height(24.dp))
                SpeechIndicator(
                    isSpeechDetected = state.isSpeechDetected,
                    isListening = state.isListening,
                    audioLevel = state.audioLevel,
                )

                if (state.activityLog.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(24.dp))
                    ActivityLog(entries = state.activityLog, onClear = onClearLog)
                }
                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}

/**
 * iOS ready-state: large waveform icon + headline + subtitle.
 */
@Composable
private fun ReadyStateVAD(modifier: Modifier = Modifier) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.GraphicEq,
            contentDescription = null,
            tint = VadCyan,
            modifier = Modifier.size(64.dp),
        )
        Spacer(modifier = Modifier.height(28.dp))
        Text(
            text = "Ready to detect",
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "Tap the mic to start detecting speech activity",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

/**
 * Pulsing speech-detected indicator (iOS: green concentric circles with pulse
 * ring) plus the "Speech Detected" / "Silence" status text and audio level
 * meter underneath, matching the iOS `speechIndicatorView`.
 */
@Composable
private fun SpeechIndicator(
    isSpeechDetected: Boolean,
    isListening: Boolean,
    audioLevel: Float,
) {
    val infinite = rememberInfiniteTransition(label = "vad_pulse")
    val pulse by infinite.animateFloat(
        initialValue = 1f,
        targetValue = 1.3f,
        animationSpec =
            infiniteRepeatable(
                animation = tween(1000, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Restart,
            ),
        label = "pulse",
    )
    val pulseAlpha by infinite.animateFloat(
        initialValue = 0.6f,
        targetValue = 0f,
        animationSpec =
            infiniteRepeatable(
                animation = tween(1000, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Restart,
            ),
        label = "pulse_alpha",
    )

    val indicatorColor by animateColorAsState(
        targetValue = if (isSpeechDetected) AppColors.primaryGreen else Color.Gray.copy(alpha = 0.3f),
        animationSpec = tween(300),
        label = "indicator_color",
    )

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier.size(140.dp),
        ) {
            if (isSpeechDetected) {
                Box(
                    modifier =
                        Modifier
                            .size(120.dp)
                            .scale(pulse)
                            .border(
                                width = 2.dp,
                                color = AppColors.primaryGreen.copy(alpha = pulseAlpha),
                                shape = CircleShape,
                            ),
                )
            }

            Box(
                modifier =
                    Modifier
                        .size(100.dp)
                        .clip(CircleShape)
                        .background(
                            if (isSpeechDetected) {
                                AppColors.primaryGreen.copy(alpha = 0.2f)
                            } else {
                                Color.Gray.copy(alpha = 0.1f)
                            },
                        ),
            )

            Box(
                contentAlignment = Alignment.Center,
                modifier =
                    Modifier
                        .size(60.dp)
                        .clip(CircleShape)
                        .background(indicatorColor),
            ) {
                Icon(
                    imageVector = if (isSpeechDetected) Icons.Filled.Mic else Icons.Filled.MicOff,
                    contentDescription = null,
                    tint = Color.White,
                    modifier = Modifier.size(28.dp),
                )
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        Text(
            text = if (isSpeechDetected) "Speech Detected" else "Silence",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            color = if (isSpeechDetected) AppColors.primaryGreen else MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (isListening) {
            Spacer(modifier = Modifier.height(16.dp))
            AudioLevelMeter(audioLevel = audioLevel)
        }
    }
}

/**
 * Horizontal bar meter — same green active / gray inactive style as STT.
 */
@Composable
private fun AudioLevelMeter(
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
                label = "bar_$index",
            )
            Box(
                modifier =
                    Modifier
                        .padding(horizontal = 2.dp)
                        .width(20.dp)
                        .height(6.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(barColor),
            )
        }
    }
}

/**
 * Scrollable list of speech-started/ended events with timestamps, plus a
 * "Clear" affordance in the header (mirrors iOS activityLogView).
 */
@Composable
private fun ActivityLog(
    entries: List<SpeechActivityLogEntry>,
    onClear: () -> Unit,
) {
    val timeFormatter = remember { SimpleDateFormat("HH:mm:ss", Locale.getDefault()) }
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Activity Log",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )
            TextButton(
                onClick = onClear,
                contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp),
            ) {
                Text(
                    text = "Clear",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        Spacer(modifier = Modifier.height(6.dp))
        entries.forEach { entry ->
            ActivityLogRow(entry = entry, timeFormatter = timeFormatter)
        }
    }
}

@Composable
private fun ActivityLogRow(
    entry: SpeechActivityLogEntry,
    timeFormatter: SimpleDateFormat,
) {
    val isStart = entry.type == SpeechActivityLogEntry.ActivityType.SPEECH_STARTED
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = if (isStart) Icons.Filled.Mic else Icons.Filled.MicOff,
                contentDescription = null,
                tint = if (isStart) AppColors.primaryGreen else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(18.dp),
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = if (isStart) "Speech Started" else "Speech Ended",
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = if (isStart) FontWeight.Medium else FontWeight.Normal,
                color = if (isStart) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            Text(
                text = timeFormatter.format(Date(entry.timestampMs)),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Listen toggle button + status label. Color states: cyan idle → green
 * listening (with green pulse when speech is detected) → orange processing.
 */
@Composable
private fun ControlsSection(
    isListening: Boolean,
    isProcessing: Boolean,
    isSpeechDetected: Boolean,
    onToggleListening: () -> Unit,
) {
    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(16.dp)
                .background(MaterialTheme.colorScheme.background),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        ListenButton(
            isListening = isListening,
            isProcessing = isProcessing,
            isSpeechDetected = isSpeechDetected,
            onToggle = onToggleListening,
        )

        Text(
            text =
                when {
                    isProcessing -> "Loading model..."
                    isListening -> "Listening for speech..."
                    else -> "Tap to start detection"
                },
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ListenButton(
    isListening: Boolean,
    isProcessing: Boolean,
    isSpeechDetected: Boolean,
    onToggle: () -> Unit,
) {
    val infinite = rememberInfiniteTransition(label = "listen_pulse")
    val pulseScale by infinite.animateFloat(
        initialValue = 1f,
        targetValue = 1.12f,
        animationSpec =
            infiniteRepeatable(
                animation = tween(600, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
        label = "pulse",
    )

    val buttonColor by animateColorAsState(
        targetValue =
            when {
                isProcessing -> AppColors.primaryOrange
                isListening -> AppColors.primaryGreen
                else -> VadCyan
            },
        animationSpec = tween(300),
        label = "button_color",
    )

    val buttonIcon =
        when {
            isProcessing -> Icons.Filled.Sync
            isListening -> Icons.Filled.Stop
            else -> Icons.Filled.Mic
        }

    Box(
        contentAlignment = Alignment.Center,
        modifier =
            Modifier
                .size(88.dp)
                .scale(if (isListening && isSpeechDetected) pulseScale else 1f),
    ) {
        if (isListening && isSpeechDetected) {
            Box(
                modifier =
                    Modifier
                        .size(84.dp)
                        .border(
                            width = 2.dp,
                            color = AppColors.primaryGreen.copy(alpha = 0.3f),
                            shape = CircleShape,
                        ).scale(pulseScale * 1.1f),
            )
        }

        Surface(
            modifier =
                Modifier
                    .size(72.dp)
                    .clickable(enabled = !isProcessing, onClick = onToggle),
            shape = CircleShape,
            color = buttonColor,
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier.fillMaxSize(),
            ) {
                if (isProcessing) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(32.dp),
                        color = Color.White,
                        strokeWidth = 3.dp,
                    )
                } else {
                    Icon(
                        imageVector = buttonIcon,
                        contentDescription =
                            when {
                                isListening -> "Stop listening"
                                else -> "Start listening"
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
 * App-bar model chip — mirrors STTModelChip but tagged "VAD".
 */
@Composable
private fun VADModelChip(
    modelName: String?,
    modifier: Modifier = Modifier,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier,
    ) {
        if (modelName != null) {
            Box(
                modifier =
                    Modifier
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
                    text = shortModelNameVAD(modelName, maxLength = 12),
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
                        imageVector = Icons.Filled.GraphicEq,
                        contentDescription = null,
                        modifier = Modifier.size(10.dp),
                        tint = VadCyan,
                    )
                    Text(
                        text = "VAD",
                        style =
                            MaterialTheme.typography.labelSmall.copy(
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                        color = VadCyan,
                    )
                }
            }
        } else {
            Icon(
                imageVector = Icons.Filled.ViewInAr,
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

private fun shortModelNameVAD(
    name: String,
    maxLength: Int = 15,
): String {
    val cleaned = name.replace(Regex("\\s*\\([^)]*\\)"), "").trim()
    return if (cleaned.length > maxLength) cleaned.take(maxLength - 1) + "…" else cleaned
}
