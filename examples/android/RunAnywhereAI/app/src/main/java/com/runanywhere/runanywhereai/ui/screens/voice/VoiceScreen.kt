package com.runanywhere.runanywhereai.ui.screens.voice

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import com.runanywhere.runanywhereai.util.readableWidth

@Composable
fun VoiceScreen() {
    val dimens = LocalDimens.current
    val context = LocalContext.current
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
    val listState = rememberLazyListState()

    val llmName = GlobalState.model.loaded?.name
    val sttName = sttVm.state.models.firstOrNull { it.id == sttVm.state.currentModelId }?.name
    val ttsVoice = ttsVm.state.models.firstOrNull { it.id == ttsVm.state.currentModelId }
    val vadName = vadVm.state.models.firstOrNull { it.id == vadVm.state.currentModelId }?.name
    val ready = llmName != null && sttName != null && ttsVoice != null

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> if (granted) voiceVm.toggle() }

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
        if (granted) voiceVm.toggle() else permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
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
        Surface(
            color = MaterialTheme.colorScheme.surfaceContainerHigh,
            shape = RoundedCornerShape(dimens.radiusLg),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column {
                SetupRow(RACIcons.Outline.MessageCircle, "Language model", llmName, onClick = { sheet = llmVm })
                Divider()
                SetupRow(RACIcons.Outline.Brain, "Speech to text", sttName, onClick = { sheet = sttVm })
                Divider()
                SetupRow(RACIcons.Outline.Robot, "Voice", ttsVoice?.name, onClick = { sheet = ttsVm })
                Divider()
                SetupRow(RACIcons.Outline.Activity, "Voice activity (VAD)", vadName, onClick = { sheet = vadVm })
            }
        }

        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
            if (voiceVm.turns.isEmpty()) {
                Text(
                    text = if (ready) "Tap the mic and start talking" else "Pick the required models to begin",
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
private fun Divider() {
    HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.4f))
}

@Composable
private fun SetupRow(icon: ImageVector, label: String, value: String?, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    val ready = value != null
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = dimens.spacingLg, vertical = dimens.spacingMd),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (ready) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconMd),
        )
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                text = value ?: "Tap to select",
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (ready) {
            Box(
                modifier = Modifier
                    .size(dimens.spacingSm)
                    .clip(CircleShape)
                    .background(primaryGreen),
            )
        }
        Icon(
            imageVector = RACIcons.Outline.ChevronRight,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.size(dimens.iconSm),
        )
    }
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
