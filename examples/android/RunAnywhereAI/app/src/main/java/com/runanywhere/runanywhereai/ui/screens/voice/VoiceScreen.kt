package com.runanywhere.runanywhereai.ui.screens.voice

import ai.runanywhere.proto.v1.InferenceFramework
import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.components.ScreenLede
import com.runanywhere.runanywhereai.ui.components.StreamingCaret
import com.runanywhere.runanywhereai.ui.components.rememberBreath
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.screens.models.DeviceInfo
import com.runanywhere.runanywhereai.ui.screens.models.HardwareTier
import com.runanywhere.runanywhereai.ui.screens.models.ModelRecommendation
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.permissions.PermissionRecoveryCard
import com.runanywhere.runanywhereai.ui.permissions.openRunAnywhereAppSettings
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.ui.theme.BrandGradient
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.Neutral100
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.motionSpec
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import com.runanywhere.runanywhereai.util.readableWidth
import kotlinx.coroutines.delay
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
        // One slot vocabulary across all three apps — the same four labels the web view
        // (src/views/voice.ts) and the iOS setup card (VoiceAISetupView) use, and each slot's
        // canonical glyph from this app's own icon set. The labels name the *role* rather than
        // the verb ("Speech-to-text", not "Listen") because a reader who learned the pipeline
        // on one platform has to recognise it on another.
        //
        // Was Brain / MessageCircle / Robot / Pulse. Brain meant speech recognition here and
        // the language model on iOS — opposite ends of the same pipeline — and it is also the
        // chat composer's thinking-mode toggle, so one glyph carried two meanings inside this
        // app. Brain now belongs to reasoning only. Waveform and Volume are the roles RACIcons
        // already documents for "the sound" and "audio leaving the device"; neither was used
        // here, so the card contradicted its own icon set.
        VoiceComponent("Speech-to-text", RACIcons.Outline.Waveform, sttVm, sttModel),
        VoiceComponent("Chat model", RACIcons.Outline.MessageCircle, llmVm, llmModel),
        VoiceComponent("Text-to-speech", RACIcons.Outline.Volume, ttsVm, ttsModel),
        VoiceComponent("Voice detection", RACIcons.Outline.Pulse, vadVm, vadModel, optional = true),
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
                // Phase 1: fetch every missing model first. Each download unloads
                // resident models for RAM headroom, so loading a component between
                // downloads would be undone by the next component's fetch.
                var staged = true
                for (component in components) {
                    val model = component.model ?: continue
                    if (!component.viewModel.ensureDownloaded(model) && !component.optional) {
                        staged = false
                        break
                    }
                }
                // Phase 2: load sequentially so per-component progress reads
                // cleanly and memory stays bounded.
                if (staged) {
                    for (component in components) {
                        val model = component.model ?: continue
                        val ok = component.viewModel.prepare(model)
                        if (!ok && !component.optional) break
                    }
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
        when {
            // While STARTING (composing the agent) ignore taps so an impatient second tap can't
            // cancel the session before it begins listening.
            voiceVm.state == VoiceState.STARTING -> Unit
            // Barge-in beats stopping. Someone who taps while the assistant is mid-sentence wants
            // the floor back, not the conversation ended — and ending it is still one tap away in
            // the row below, so neither intent is lost.
            voiceVm.state == VoiceState.SPEAKING -> voiceVm.interrupt()
            voiceVm.state !in START_STATES -> voiceVm.toggle()
            !ready -> Unit
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED -> voiceVm.toggle()
            else -> permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    // A listening agent that has heard nothing is indistinguishable from a hung one: the utterance
    // segmenter closes a turn on measured energy, so speech that is perfectly intelligible but
    // quiet — a distant mic, a low input gain — simply never crosses the threshold, and the panel
    // sits on "Listening…" forever with no transcript and no error. After a stretch of that, say
    // so. Reset by any state change, any new turn, and by the detector actually firing, so the
    // hint only ever describes the silence in front of it.
    var quietMic by remember { mutableStateOf(false) }
    LaunchedEffect(
        voiceVm.state,
        voiceVm.turns.size,
        voiceVm.isSpeechDetected,
        voiceVm.partialTranscript,
        // Suppressed while the pipeline has its own notice up. The core reports a mic delivering
        // dead air in exact terms ("digital silence … for 8s"); printing "try speaking up" under
        // that gives the reader two explanations for one silence, and the generic one is the
        // wrong advice — nothing said louder reaches a mic that is handing over zeros.
        voiceVm.error,
    ) {
        quietMic = false
        if (voiceVm.state == VoiceState.LISTENING && !voiceVm.isSpeechDetected &&
            voiceVm.partialTranscript == null && !isNpuSwap && voiceVm.error == null
        ) {
            delay(QUIET_MIC_HINT_DELAY_MS)
            quietMic = true
        }
    }

    // The live hypothesis is a list row of its own, so the follow target is the partial when one is
    // showing — otherwise the words being recognised right now scroll off the bottom.
    val transcriptRows = voiceVm.turns.size + if (voiceVm.partialTranscript != null) 1 else 0
    LaunchedEffect(transcriptRows, voiceVm.partialTranscript) {
        if (transcriptRows > 0) listState.animateScrollToItem(transcriptRows - 1)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .readableWidth()
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        ScreenLede(
            // The turn loop is what this promises, and all of it is true: nothing is tapped
            // between turns. The mic now also stays open through the reply, but whether a voice
            // arriving over the loudspeaker is recognised as an interruption depends on the
            // device's speaker-to-mic coupling (VoiceAgentMicDriver's barge-in note), so no
            // label here promises it — iOS `VoiceAgentViewModel.instructionText` settled on the
            // same rule, and the two apps have to make the same promise.
            "Hands-free: speak, pause, and it answers — no tapping between turns. We picked the " +
                "best voice models for your device; tap once to set them up.",
        )

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
            if (transcriptRows == 0) {
                Text(
                    // The empty pane is still a claim about the system, so it has to agree with the
                    // status line below it rather than repeating one fixed sentence while the agent
                    // is already listening or thinking.
                    text = emptyTranscriptText(voiceVm.state, ready),
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
                    voiceVm.partialTranscript?.let { hypothesis ->
                        item(key = PARTIAL_TURN_KEY) { PartialTurnBubble(hypothesis) }
                    }
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
            StatusLine(
                text = statusText(voiceVm.state, ready, isNpuSwap),
                hearing = voiceVm.isSpeechDetected,
            )
            QuietMicHint(visible = quietMic)
            MicButton(
                state = voiceVm.state,
                // Disabled while an interrupt is settling. The SDK's interrupt resolves only once
                // the abandoned response and its playout have both finished, and leaving the
                // button live through that window invites a second press that does nothing.
                enabled = voiceVm.state != VoiceState.STARTING &&
                    !voiceVm.isInterrupting &&
                    (ready || voiceVm.state !in START_STATES),
                pushToTalk = isNpuSwap,
                isInterrupting = voiceVm.isInterrupting,
                onClick = ::onMic,
            )
            // Ending and interrupting are different intents, so they get different controls: the
            // big button hands the turn back mid-reply, this one closes the microphone. Without a
            // separate End, barge-in would have swallowed the only way out of a live session.
            Row(
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (voiceVm.state !in START_STATES) {
                    TextButton(onClick = voiceVm::stop) {
                        Text(if (isNpuSwap) "Cancel turn" else "End conversation")
                    }
                }
                if (voiceVm.turns.isNotEmpty()) {
                    TextButton(onClick = voiceVm::clear) {
                        Icon(
                            RACIcons.Outline.Trash,
                            contentDescription = null,
                            modifier = Modifier.size(dimens.iconSm),
                        )
                        Spacer(Modifier.size(dimens.spacingXs))
                        Text("Clear")
                    }
                }
            }
        }
    }

    sheet?.let { active ->
        ModelSelectionSheet(viewModel = active, onDismiss = { sheet = null })
    }
}

/**
 * What the pipeline is doing, in the user's terms.
 *
 * Push-to-talk and the always-listening agent are different contracts, so LISTENING cannot share
 * one sentence: on the NPU per-turn-swap path the tap ends the recording and sends it, on the agent
 * path the pause does. Telling a push-to-talk user to "speak, then pause" leaves them waiting for
 * something that never happens.
 */
private fun statusText(state: VoiceState, ready: Boolean, pushToTalk: Boolean): String = when (state) {
    // Short state labels, not instructions: the empty transcript above already carries the sentence
    // telling the user what to do, and printing it twice on one screen reads as a rendering bug.
    // The wording matches the web app's session pill so the two describe the same states.
    VoiceState.IDLE -> if (ready) "Ready to talk" else "Needs setup"
    VoiceState.STARTING -> "Starting…"
    VoiceState.LISTENING ->
        if (pushToTalk) "Recording — tap when you're done" else "Listening… speak, then pause"
    VoiceState.TRANSCRIBING -> "Transcribing…"
    VoiceState.THINKING -> "Thinking…"
    // Was "mic paused", which stopped being true when the driver started feeding through
    // playout. What replaces it names only the control, not the barge-in: the core decides
    // whether a voice over the reply is an interruption or the mic hearing the loudspeaker, and
    // that needs the user to arrive meaningfully louder than the speaker — a property of the
    // device, not something a label can promise. "Take the turn back" is the phrase all four
    // apps use for this moment; each names its own control.
    VoiceState.SPEAKING -> "Speaking — tap to take the turn back"
    // The session is gone and the microphone with it, so this cannot read "Ready to talk" — the
    // reader has to know the conversation ended on its own before the error line beneath explains
    // why. "Tap to start again" is the recovery, and it really is one tap.
    VoiceState.FAILED -> "Conversation stopped — mic released, tap to start again"
}

/** The empty transcript, phrased for whatever the agent is doing at that moment. */
private fun emptyTranscriptText(state: VoiceState, ready: Boolean): String = when (state) {
    // Deliberately does not quote the card's button label: that button says "Set up Voice AI" when
    // something still has to be fetched and "Load Voice AI" when everything is already on disk, and
    // naming one of the two here left the pane pointing at a control that reads differently.
    VoiceState.IDLE -> if (ready) "Tap the mic and start talking" else "Get Voice AI ready above to begin"
    VoiceState.STARTING -> "Getting ready…"
    VoiceState.LISTENING -> "Go ahead — say something."
    VoiceState.TRANSCRIBING -> "Working out what you said…"
    VoiceState.THINKING -> "Working out a reply…"
    // States the state and nothing else — the status line directly below it already names the
    // control, and printing the instruction twice on one screen reads as a rendering bug.
    // Mirrors iOS `transcriptPlaceholder`, which settled here for the same reason.
    VoiceState.SPEAKING -> "Speaking."
    VoiceState.FAILED -> "That didn't work out. Tap the mic to try again."
}

/**
 * The status sentence, with the speech-detected marker beside it rather than folded into it.
 *
 * Two separate facts — what the pipeline is doing and whether the detector currently hears a voice
 * — so they are two separate marks. Announced as one polite live region so a screen reader gets the
 * change once instead of twice.
 */
@Composable
private fun StatusLine(text: String, hearing: Boolean) {
    val dimens = LocalDimens.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        modifier = Modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        AnimatedVisibility(
            visible = hearing,
            enter = fadeIn(AppMotion.micro()),
            exit = fadeOut(AppMotion.exit()),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                modifier = Modifier
                    .clip(RoundedCornerShape(dimens.radiusFull))
                    .background(primaryGreen.copy(alpha = 0.16f))
                    .padding(horizontal = dimens.spacingSm, vertical = dimens.spacingXs),
            ) {
                StreamingCaret(color = primaryGreen, size = 8.dp)
                Text(
                    text = "Hearing you",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
            }
        }
    }
}

/**
 * The "we are listening but hearing nothing" line.
 *
 * Advice, not an error: the session is healthy and the microphone is open, so this is styled as
 * the secondary note it is rather than in the error colour. Its own polite live region, because it
 * appears long after the status line above it last changed and would otherwise never be announced.
 */
@Composable
private fun QuietMicHint(visible: Boolean) {
    AnimatedVisibility(
        visible = visible,
        enter = fadeIn(motionSpec { AppMotion.standard() }),
        exit = fadeOut(motionSpec { AppMotion.exit() }),
    ) {
        Text(
            text = "Not hearing anything yet — try speaking up, or move closer to the mic.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .semantics { liveRegion = LiveRegionMode.Polite },
        )
    }
}

@Composable
private fun TurnBubble(turn: VoiceTurn) {
    val dimens = LocalDimens.current
    // The reader's own words carry the logo gradient, the same as chat and RAG — see
    // [BrandGradient]. White reads on the gradient; a solid `primary` fill would need
    // `onPrimary`'s ink instead, which would make the transcript's two voices look alike.
    val fill = if (turn.isUser) {
        Modifier.background(BrandGradient)
    } else {
        Modifier.background(MaterialTheme.colorScheme.surfaceContainerHigh)
    }
    val textColor = if (turn.isUser) Neutral100 else MaterialTheme.colorScheme.onSurface
    Box(
        modifier = Modifier.fillMaxWidth(),
        contentAlignment = if (turn.isUser) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Box(
            modifier = Modifier
                .widthIn(max = dimens.bubbleMaxWidth)
                .clip(RoundedCornerShape(dimens.radiusLg))
                .then(fill)
                .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
        ) {
            Text(text = turn.text.ifBlank { "…" }, style = MaterialTheme.typography.bodyLarge, color = textColor)
        }
    }
}

/**
 * The words being recognised right now, marked as provisional.
 *
 * Outlined instead of filled and trailing a caret, so it never reads as a settled turn: the text
 * inside it will be revised, sometimes several times, before it becomes one. A hypothesis rendered
 * identically to a result makes the transcript look like it is rewriting its own history.
 */
@Composable
private fun PartialTurnBubble(text: String) {
    val dimens = LocalDimens.current
    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
        Row(
            modifier = Modifier
                .widthIn(max = dimens.bubbleMaxWidth)
                .clip(RoundedCornerShape(dimens.radiusLg))
                .border(
                    width = 1.dp,
                    color = MaterialTheme.colorScheme.primary.copy(alpha = 0.45f),
                    shape = RoundedCornerShape(dimens.radiusLg),
                )
                .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd)
                .semantics { contentDescription = "Still hearing: $text" },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Text(
                text = text,
                style = MaterialTheme.typography.bodyLarge,
                fontStyle = FontStyle.Italic,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f, fill = false),
            )
            StreamingCaret(color = MaterialTheme.colorScheme.primary)
        }
    }
}

/**
 * The one big control. Its meaning changes with the state, so its colour, glyph, and spoken label
 * all change with it — a single "Stop" that sometimes ends the conversation and sometimes sends a
 * recording is a control the user has to guess at.
 */
@Composable
private fun MicButton(
    state: VoiceState,
    enabled: Boolean,
    pushToTalk: Boolean,
    isInterrupting: Boolean,
    onClick: () -> Unit,
) {
    val scheme = MaterialTheme.colorScheme
    // A state that starts a conversation wears the start affordance, whatever the panel says about
    // the turn before it: after a failure the control is still "begin", so dressing it as the
    // secondary stop button would make the one recovery on screen look inert.
    val starts = state in START_STATES
    val container = when {
        !enabled -> scheme.surfaceContainerHighest
        state == VoiceState.LISTENING -> scheme.error
        !starts -> scheme.secondary
        else -> scheme.primary
    }
    // Paired with the container rather than always `onPrimary`: white on the disabled grey and on
    // the secondary fill both fell under the 3:1 floor for a control glyph.
    val content = when {
        !enabled -> scheme.onSurfaceVariant
        state == VoiceState.LISTENING -> scheme.onError
        !starts -> scheme.onSecondary
        else -> scheme.onPrimary
    }
    val icon = when {
        starts || state == VoiceState.STARTING -> RACIcons.Outline.Microphone
        state == VoiceState.LISTENING && pushToTalk -> RACIcons.Outline.Check
        else -> RACIcons.Outline.PlayerStop
    }
    val label = when {
        // The only way a start state is disabled is that the pipeline is not loaded yet. Sighted
        // readers get that from the "Needs setup" line beside the button; a screen reader was told
        // "Start talking" about a control that cannot, so it says why here instead.
        starts && !enabled -> "Start talking — get Voice AI ready first"
        state == VoiceState.IDLE -> "Start talking"
        state == VoiceState.FAILED -> "Start talking again"
        state == VoiceState.STARTING -> "Starting"
        state == VoiceState.LISTENING && pushToTalk -> "Send recording"
        state == VoiceState.LISTENING -> "End conversation"
        state == VoiceState.SPEAKING ->
            if (isInterrupting) "Stopping the reply" else "Interrupt and take the turn"
        else -> "Stop"
    }
    // A steady breath while the microphone is open — the one moment the user needs to know the app
    // is live without reading anything. Deliberately not on SPEAKING or THINKING: a pulse there
    // would compete with the reply for attention, and neither state is waiting on the user.
    val listening = enabled && state == VoiceState.LISTENING
    val breath = if (listening) rememberBreath(min = MIC_HALO_FLOOR, label = "micBreath") else 0f

    Box(contentAlignment = Alignment.Center) {
        if (listening) {
            Box(
                modifier = Modifier
                    // Size and opacity move together, so the halo swells and dims as one shape
                    // instead of two effects beating against each other. Under reduced motion
                    // `rememberBreath` returns its maximum, leaving a plain static ring — which is
                    // still a legible "microphone is open" mark.
                    .size(MIC_BUTTON_SIZE + MIC_HALO_SPREAD * breath)
                    .clip(CircleShape)
                    .background(container.copy(alpha = MIC_HALO_ALPHA * breath)),
            )
        }
        Box(
            modifier = Modifier
                .size(MIC_BUTTON_SIZE)
                .clip(CircleShape)
                .background(container)
                .clickable(enabled = enabled, onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = content,
                modifier = Modifier.size(MIC_GLYPH_SIZE),
            )
        }
    }
}

/** Stable list key for the single provisional row, so it is never confused with a settled turn. */
private const val PARTIAL_TURN_KEY = "voice-partial-transcript"

/**
 * The states where the big button opens a conversation instead of acting on a live one.
 *
 * IDLE and FAILED differ in what the panel says about the *past* — nothing versus "the last session
 * died" — not in what the control does next: neither holds a session, so both start one. Keeping the
 * pair in one place is what stops the two from drifting into a button labelled "Stop" with nothing
 * to stop.
 */
private val START_STATES = setOf(VoiceState.IDLE, VoiceState.FAILED)

/**
 * How long the agent may listen in silence before the screen admits it has heard nothing.
 *
 * Long enough that an ordinary pause — thinking about the question, drawing breath — never trips
 * it, short enough that it lands well before a user concludes the app has hung.
 */
private const val QUIET_MIC_HINT_DELAY_MS = 12_000L

private val MIC_BUTTON_SIZE = 88.dp
private val MIC_GLYPH_SIZE = 36.dp

/** How far past the button edge the listening halo reaches at the top of its breath. */
private val MIC_HALO_SPREAD = 24.dp
private const val MIC_HALO_ALPHA = 0.35f

/** The halo never fully vanishes — a ring that blinks out reads as a fault, not a pulse. */
private const val MIC_HALO_FLOOR = 0.2f
