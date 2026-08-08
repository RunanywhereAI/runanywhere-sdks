package com.runanywhere.runanywhereai.ui.screens.vad

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.components.AudioWaveform
import com.runanywhere.runanywhereai.ui.screens.models.ModelPickerCard
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.permissions.PermissionRecoveryCard
import com.runanywhere.runanywhereai.ui.permissions.openRunAnywhereAppSettings
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.ambientPeriod
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import com.runanywhere.runanywhereai.util.readableWidth
import java.text.DateFormat
import java.util.Date

@Composable
fun VadScreen() {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val vadVm: VadViewModel = viewModel()
    val modelVm: ModelSelectionViewModel =
        viewModel(factory = ModelSelectionViewModel.Factory(ModelSelectionContext.VAD))
    var showSheet by remember { mutableStateOf(false) }
    var permissionDenied by remember { mutableStateOf(false) }

    DisposableEffect(vadVm) {
        onDispose { vadVm.stop() }
    }

    // onDispose fires on nav-away but NOT when the Activity is backgrounded
    // (Home/lock) mid-listen. Release the mic on ON_STOP too so it doesn't stay
    // hot behind the lock screen.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, vadVm) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) vadVm.stop()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val model = modelVm.state.models.firstOrNull { it.id == modelVm.state.currentModelId }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        permissionDenied = !granted
        if (granted) vadVm.toggle()
    }

    fun onListen() {
        if (model == null) return
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) vadVm.toggle() else permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .readableWidth()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Header()

        ModelPickerCard(
            label = "Detector",
            model = model,
            // The detector's job is to find speech in a signal, so the row wears the same
            // burst-on-a-baseline mark as this screen's own header.
            icon = RACIcons.Outline.Pulse,
            // Swapping the detector out from under a live capture would pull native state
            // away mid-stream, so the row locks while listening rather than failing later.
            enabled = !vadVm.isListening,
            onClick = { showSheet = true },
        )

        SpeechIndicator(
            isListening = vadVm.isListening,
            isSpeechDetected = vadVm.isSpeechDetected,
            audioLevel = vadVm.audioLevel,
        )

        ListenButton(
            listening = vadVm.isListening,
            enabled = model != null,
            onClick = ::onListen,
        )

        Text(
            text = when {
                vadVm.isListening -> "Listening for speech…"
                model != null -> "Tap to start detection"
                else -> "Select a model to begin"
            },
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (vadVm.activityLog.isNotEmpty()) {
            ActivityLogCard(entries = vadVm.activityLog, onClear = vadVm::clearLog)
        }

        vadVm.error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
        if (permissionDenied) {
            PermissionRecoveryCard(
                message = "Microphone access was denied. Enable it in Android settings to detect speech.",
                onOpenSettings = context::openRunAnywhereAppSettings,
            )
        }
    }

    if (showSheet) {
        ModelSelectionSheet(viewModel = modelVm, onDismiss = { showSheet = false })
    }
}

@Composable
private fun Header() {
    val dimens = LocalDimens.current
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
        Box(
            modifier = Modifier
                .size(64.dp)
                .clip(CircleShape)
                .background(MaterialTheme.colorScheme.primaryContainer),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = RACIcons.Outline.Pulse,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
                modifier = Modifier.size(dimens.iconLg),
            )
        }
        Text("Turn-taking Detection", style = MaterialTheme.typography.titleLarge)
        Text(
            text = "Detect when speech starts and ends, all on-device.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
    }
}

@Composable
private fun SpeechIndicator(isListening: Boolean, isSpeechDetected: Boolean, audioLevel: Float) {
    val dimens = LocalDimens.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        Box(contentAlignment = Alignment.Center, modifier = Modifier.size(140.dp)) {
            if (isSpeechDetected) PulseRing()

            Box(
                modifier = Modifier
                    .size(100.dp)
                    .clip(CircleShape)
                    .background(
                        if (isSpeechDetected) {
                            primaryGreen.copy(alpha = 0.2f)
                        } else {
                            MaterialTheme.colorScheme.surfaceContainerHigh
                        },
                    ),
            )
            Box(
                modifier = Modifier
                    .size(60.dp)
                    .clip(CircleShape)
                    .background(
                        if (isSpeechDetected) primaryGreen else MaterialTheme.colorScheme.surfaceContainerHighest,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (isSpeechDetected) RACIcons.Outline.Microphone else RACIcons.Outline.MicrophoneOff,
                    contentDescription = null,
                    tint = if (isSpeechDetected) Color.White else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(dimens.iconMd),
                )
            }
        }

        Text(
            text = if (isSpeechDetected) "Speech Detected" else "Silence",
            style = MaterialTheme.typography.titleMedium,
            color = if (isSpeechDetected) primaryGreen else MaterialTheme.colorScheme.onSurfaceVariant,
        )

        // The waveform's own history is the record of what the mic heard; `active` tints it
        // green only while the detector agrees it is speech, so "hearing you" and "hearing
        // the room" are visibly different states rather than the same lit bars.
        if (isListening) {
            AudioWaveform(level = audioLevel, active = isSpeechDetected)
        }
    }
}

/**
 * A ring radiating out of the mic mark while speech is being heard.
 *
 * Informational: it is on screen only while the VAD reports speech, so the ripple *is* the
 * detection. Pinned to the canonical 1.0 s ambient period and linear — an eased loop stutters
 * at the seam where it restarts. Scale and alpha ride one `graphicsLayer`, so the per-frame
 * cost is two compositor properties rather than a re-layout of a 120dp circle.
 *
 * Renders nothing at all under reduced motion; the mic mark already turns green, which is the
 * same information without the movement.
 */
@Composable
private fun PulseRing() {
    val period = ambientPeriod(AppMotion.AMBIENT_SPIN) ?: return
    val transition = rememberInfiniteTransition(label = "vadPulse")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(period, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "vadPulseProgress",
    )
    Box(
        modifier = Modifier
            .size(PULSE_RING_SIZE)
            .graphicsLayer {
                val s = 1f + progress * PULSE_RING_GROWTH
                scaleX = s
                scaleY = s
                // Fades as it grows, so the ring dissipates instead of hitting the edge.
                alpha = 1f - progress
            }
            .clip(CircleShape)
            .background(primaryGreen.copy(alpha = PULSE_RING_ALPHA)),
    )
}

@Composable
private fun ListenButton(listening: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val color = when {
        !enabled -> MaterialTheme.colorScheme.surfaceContainerHighest
        listening -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.primary
    }
    // Paired with the container rather than always `onPrimary`, the rule
    // `VoiceScreen.MicButton` already follows: the glyph has to clear 3:1 against whichever
    // of the three fills is showing, and no single foreground does that for a grey, a red
    // and an orange. `onPrimary` is ink now, so on the red fill it would all but vanish.
    val tint = when {
        !enabled -> MaterialTheme.colorScheme.onSurfaceVariant
        listening -> MaterialTheme.colorScheme.onError
        else -> MaterialTheme.colorScheme.onPrimary
    }
    Box(
        modifier = Modifier
            .padding(top = 8.dp)
            .size(96.dp)
            .clip(CircleShape)
            .background(color)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = if (listening) RACIcons.Outline.PlayerStop else RACIcons.Outline.Microphone,
            contentDescription = if (listening) "Stop" else "Listen",
            tint = tint,
            modifier = Modifier.size(40.dp),
        )
    }
}

@Composable
private fun ActivityLogCard(entries: List<VadLogEntry>, onClear: () -> Unit) {
    val dimens = LocalDimens.current
    val timeFormat = remember { DateFormat.getTimeInstance(DateFormat.MEDIUM) }
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Activity Log",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onClear) { Text("Clear") }
        }
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shape = RoundedCornerShape(dimens.radiusLg),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier.padding(dimens.spacingLg),
                verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
            ) {
                entries.forEach { entry -> ActivityLogRow(entry, timeFormat) }
            }
        }
    }
}

@Composable
private fun ActivityLogRow(entry: VadLogEntry, timeFormat: DateFormat) {
    val dimens = LocalDimens.current
    val started = entry.type == VadActivity.SPEECH_STARTED
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        Icon(
            imageVector = if (started) RACIcons.Outline.Microphone else RACIcons.Outline.MicrophoneOff,
            contentDescription = null,
            tint = if (started) primaryGreen else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconSm),
        )
        Text(
            text = if (started) "Speech Started" else "Speech Ended",
            style = MaterialTheme.typography.bodyMedium,
            color = if (started) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = timeFormat.format(Date(entry.timestampMs)),
            style = RACTextStyles.Metric,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/** The mic mark's ripple geometry. */
private val PULSE_RING_SIZE = 120.dp
private const val PULSE_RING_GROWTH = 0.3f
private const val PULSE_RING_ALPHA = 0.25f
