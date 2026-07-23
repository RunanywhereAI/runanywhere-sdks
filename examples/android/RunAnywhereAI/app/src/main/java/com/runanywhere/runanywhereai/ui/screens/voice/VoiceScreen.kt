package com.runanywhere.runanywhereai.ui.screens.voice

import ai.runanywhere.proto.v1.InferenceFramework
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.screens.models.DeviceInfo
import com.runanywhere.runanywhereai.ui.screens.models.HardwareTier
import com.runanywhere.runanywhereai.ui.screens.models.ModelRecommendation
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.permissions.PermissionRecoveryCard
import com.runanywhere.runanywhereai.ui.permissions.openRunAnywhereAppSettings
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.util.readableWidth
import kotlinx.coroutines.launch

@Composable
fun VoiceScreen() {
    val dimens = LocalDimens.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val voiceVm: VoiceViewModel = viewModel()
    val llmVm: ModelSelectionViewModel =
        viewModel(key = "voice-llm", factory = ModelSelectionViewModel.Factory(ModelSelectionContext.LLM))
    val sttVm: ModelSelectionViewModel =
        viewModel(key = "voice-stt", factory = ModelSelectionViewModel.Factory(ModelSelectionContext.STT))
    val ttsVm: ModelSelectionViewModel =
        viewModel(key = "voice-tts", factory = ModelSelectionViewModel.Factory(ModelSelectionContext.TTS))
    val vadVm: ModelSelectionViewModel =
        viewModel(key = "voice-vad", factory = ModelSelectionViewModel.Factory(ModelSelectionContext.VAD))
    var sheet by remember { mutableStateOf<ModelSelectionViewModel?>(null) }
    var isPreparing by remember { mutableStateOf(false) }
    var permissionDenied by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()

    // Navigation retains this ViewModel in the saved back-stack entry, so
    // onCleared is not a screen-exit signal. Stop Talk explicitly to cancel
    // AudioRecord and its native feed loop before another speech screen runs.
    DisposableEffect(voiceVm) {
        onDispose { voiceVm.stop() }
    }

    // onDispose fires on nav-away but NOT when the Activity is backgrounded
    // (Home/lock) mid-conversation. Stop Talk on ON_STOP too so the mic doesn't
    // stay hot behind the lock screen.
    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, voiceVm) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) voiceVm.stop()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val device = remember { runCatching { DeviceInfo.current() }.getOrNull() }

    // Pure recommendation over the union of all voice modalities, so the whole trio
    // (+ VAD) is pre-selected with zero hand-picking. Prefers HNPU where it fits.
    val allVoiceModels = sttVm.state.models + llmVm.state.models + ttsVm.state.models + vadVm.state.models
    val pipeline = remember(allVoiceModels, device) {
        ModelRecommendation.recommendVoicePipeline(
            tier = device?.tier ?: HardwareTier.MID_RANGE,
            hasNpu = device?.hasNpu ?: false,
            models = allVoiceModels,
        )
    }

    // A component's shown model must follow the user's live selection (loaded model), not the static
    // recommendation — otherwise picking e.g. LFM2.5 350M in "Change" loads it but the row keeps
    // showing the recommended Qwen3.5 0.8B. Fall back to the recommendation when nothing is selected.
    fun effective(vm: ModelSelectionViewModel, fallback: com.runanywhere.sdk.public.types.RAModelInfo?) =
        vm.state.currentModelId?.let { id -> vm.state.models.firstOrNull { it.id == id } } ?: fallback

    val sttModel = effective(sttVm, pipeline.stt)
    val llmModel = effective(llmVm, pipeline.llm)
    val ttsModel = effective(ttsVm, pipeline.tts)
    val vadModel = effective(vadVm, pipeline.vad)

    // Both STT + chat model on the single-slot NPU can't co-reside, so Talk swaps them per turn (see
    // VoiceViewModel). Tell the VM the current selection so its mic branch can load each in turn.
    val isNpuSwap = sttModel?.framework == InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT &&
        llmModel?.framework == InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT
    LaunchedEffect(sttModel?.id, llmModel?.id, ttsModel?.id, isNpuSwap) {
        voiceVm.setPipeline(sttModel, llmModel, ttsModel)
    }

    val components = listOf(
        VoiceComponent("Listen", RACIcons.Outline.Brain, sttVm, sttModel),
        VoiceComponent("Assistant", RACIcons.Outline.MessageCircle, llmVm, llmModel),
        VoiceComponent("Speak", RACIcons.Outline.Robot, ttsVm, ttsModel),
        VoiceComponent("Turn-taking", RACIcons.Outline.Activity, vadVm, vadModel, optional = true),
    )

    // Readiness: the co-resident agent path needs STT+LLM+TTS all loaded; the NPU per-turn-swap path
    // loads models on demand, so the mic is ready once STT + LLM are merely DOWNLOADED.
    val coreReady = listOf(sttVm, llmVm, ttsVm).all { it.state.currentModelId != null }
    val downloaded = listOf(sttModel to sttVm, llmModel to llmVm, ttsModel to ttsVm)
        .all { (m, vm) -> m != null && vm.isReady(m) }
    val ready = if (isNpuSwap) downloaded else (coreReady && GlobalState.model.isLoaded)

    fun prepareAll() {
        if (isPreparing) return
        scope.launch {
            isPreparing = true
            try {
                // Sequential so per-component progress reads cleanly and memory stays
                // bounded. Best-effort: download (and load) EVERY component. A load
                // failure on one model — e.g. a 2nd NPU model that can't co-reside with
                // the first in the single Hexagon slot — must NOT abort downloading the
                // remaining required models (this used to `break` here, so it stopped
                // after the first and left the rest un-downloaded).
                for (component in components) {
                    val model = component.model ?: continue
                    component.viewModel.prepare(model)
                }
            } finally {
                isPreparing = false
            }
        }
    }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        permissionDenied = !granted
        if (granted) voiceVm.toggle()
    }

    fun onMic() {
        // While STARTING (composing the agent) ignore taps so an impatient
        // second tap can't cancel the session before it begins listening.
        if (voiceVm.state == VoiceState.STARTING) return
        if (voiceVm.state != VoiceState.IDLE) {
            voiceVm.toggle()
            return
        }
        if (!ready) return
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        if (granted) {
            voiceVm.toggle()
        } else {
            permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    LaunchedEffect(voiceVm.turns.size) {
        if (voiceVm.turns.isNotEmpty()) listState.animateScrollToItem(voiceVm.turns.size - 1)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .readableWidth()
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
            Text("Talk Mode", style = MaterialTheme.typography.headlineSmall)
            Text(
                "Hands-free conversation. We picked the best voice models for your device — tap once to set them up.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        VoiceSetupCard(
            components = components,
            allReady = ready,
            // NPU swap loads models on demand, so a downloaded component is "ready"; the co-resident
            // agent path needs them actually loaded.
            requireLoaded = !isNpuSwap,
            isPreparing = isPreparing,
            onPrepareAll = ::prepareAll,
            onChange = { sheet = it.viewModel },
        )

        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
            if (voiceVm.turns.isEmpty()) {
                Text(
                    text = if (ready) "Tap the mic and start talking" else "Set up Voice AI above to begin",
                    modifier = Modifier.fillMaxWidth(),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                ) {
                    items(voiceVm.turns) { turn -> TurnBubble(turn) }
                }
            }
        }

        voiceVm.error?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
            )
        }
        // Surface a silent "Set up Voice AI" failure (e.g. missing HF token or a component load error)
        // that otherwise leaves the setup card grey with a dead mic and no explanation. Skip this for the
        // NPU-swap path: there a component being "not loaded" is expected (the mic loads each per turn), so
        // those load-state errors are noise — real turn errors come through voiceVm.error instead.
        if (voiceVm.error == null && !isNpuSwap) {
            components.firstNotNullOfOrNull { it.viewModel.state.error }?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center,
                )
            }
        }
        if (permissionDenied) {
            PermissionRecoveryCard(
                message = "Microphone access was denied. Enable it in Android settings to use Talk.",
                onOpenSettings = context::openRunAnywhereAppSettings,
            )
        }
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Text(
                text = statusText(voiceVm.state, ready),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            MicButton(
                state = voiceVm.state,
                enabled = voiceVm.state != VoiceState.STARTING && (ready || voiceVm.state != VoiceState.IDLE),
                onClick = ::onMic,
            )
            if (voiceVm.turns.isNotEmpty()) {
                IconButton(onClick = voiceVm::clear) {
                    Icon(RACIcons.Outline.Trash, contentDescription = "Clear", modifier = Modifier.size(dimens.iconSm))
                }
            }
        }
    }

    sheet?.let { active ->
        ModelSelectionSheet(viewModel = active, onDismiss = { sheet = null })
    }
}

private fun statusText(state: VoiceState, ready: Boolean): String = when (state) {
    VoiceState.IDLE -> if (ready) "Tap to talk" else "Setup required"
    VoiceState.STARTING -> "Starting…"
    VoiceState.LISTENING -> "Listening… speak, then pause — tap to stop"
    VoiceState.TRANSCRIBING -> "Transcribing…"
    VoiceState.THINKING -> "Thinking…"
    VoiceState.SPEAKING -> "Speaking…"
}

@Composable
private fun TurnBubble(turn: VoiceTurn) {
    val dimens = LocalDimens.current
    val color = if (turn.isUser) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceContainerHigh
    val textColor = if (turn.isUser) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface
    Box(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = if (turn.isUser) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Box(
            modifier = Modifier
                .widthIn(max = 320.dp)
                .clip(RoundedCornerShape(dimens.radiusLg))
                .background(color)
                .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
        ) {
            Text(text = turn.text.ifBlank { "…" }, style = MaterialTheme.typography.bodyLarge, color = textColor)
        }
    }
}

@Composable
private fun MicButton(state: VoiceState, enabled: Boolean, onClick: () -> Unit) {
    val color = when {
        !enabled -> MaterialTheme.colorScheme.surfaceContainerHighest
        state == VoiceState.LISTENING -> MaterialTheme.colorScheme.error
        state != VoiceState.IDLE -> MaterialTheme.colorScheme.secondary
        else -> MaterialTheme.colorScheme.primary
    }
    val icon = if (state == VoiceState.IDLE || state == VoiceState.STARTING) {
        RACIcons.Outline.Microphone
    } else {
        RACIcons.Outline.PlayerStop
    }
    Box(
        modifier = Modifier
            .size(88.dp)
            .clip(CircleShape)
            .background(color)
            .clickable(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = if (state == VoiceState.IDLE) "Start" else "Stop",
            tint = MaterialTheme.colorScheme.onPrimary,
            modifier = Modifier.size(36.dp),
        )
    }
}
