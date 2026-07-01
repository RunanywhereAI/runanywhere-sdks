package com.runanywhere.runanywhereai.ui.screens.npu.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.TextFieldValue
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.ui.screens.npu.MetricStrip
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModality
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelBar
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelsViewModel
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing
import com.runanywhere.sdk.foundation.bridge.extensions.toRALLMGenerateRequest
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.aggregateStream
import com.runanywhere.sdk.public.extensions.cancelGeneration
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import kotlinx.coroutines.launch

private const val NPU_MAX_REPLY_TOKENS = 64

// Qwen-family models may emit `` / `` blocks even with disable_thinking; strip
// before showing live stream text or feeding prior turns back into chat_history.
private val thinkBlockRegex =
    Regex("""<think>[\s\S]*?(?:</think>|</thinking>|$)""")
private val thinkingBlockRegex =
    Regex("""<thinking>[\s\S]*?</thinking>""")

private fun stripThinkBlocks(text: String): String =
    thinkBlockRegex.replace(thinkingBlockRegex.replace(text, ""), "").trim()

private data class ChatMessage(
    val id: Int,
    val role: String,
    val text: String,
)

/**
 * NPU/QHexRT LLM tab — multi-turn chat; templating and stop criteria live in QHexRT.
 */
@Composable
fun LlmScreen(modelsVm: NpuModelsViewModel) {
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState()
    var nextId by remember { mutableIntStateOf(0) }
    val messages = remember { mutableStateListOf<ChatMessage>() }
    var input by remember { mutableStateOf(TextFieldValue("")) }
    var running by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var tps by remember { mutableStateOf("—") }
    var ttft by remember { mutableStateOf("—") }
    val loadedModelId = modelsVm.loadedId(NpuModality.LLM)

    LaunchedEffect(messages.size, running) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.lastIndex)
        }
    }

    Column(Modifier.fillMaxSize().padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        NpuModelBar(modality = NpuModality.LLM, vm = modelsVm)

        Text(
            "System prompt is configured in Settings.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            items(messages, key = { it.id }) { msg ->
                ChatBubble(msg)
            }
        }

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            OutlinedTextField(
                value = input,
                onValueChange = { input = it },
                label = { Text("Message") },
                modifier = Modifier.weight(1f),
                enabled = !running,
                maxLines = 4,
            )
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                Button(
                    onClick = {
                        val text = input.text.trim()
                        if (text.isBlank() || running || loadedModelId == null) return@Button
                        input = TextFieldValue("")
                        error = null
                        running = true
                        val userId = nextId++
                        messages.add(ChatMessage(userId, "user", text))
                        val assistantId = nextId++
                        messages.add(ChatMessage(assistantId, "assistant", ""))
                        scope.launch {
                            try {
                                val s = SettingsRepository.settings
                                val history = buildList {
                                    for (i in 0 until messages.size - 2) {
                                        val turn = messages[i].text
                                        add(
                                            if (messages[i].role == "assistant") {
                                                stripThinkBlocks(turn)
                                            } else {
                                                turn
                                            },
                                        )
                                    }
                                }
                                val opts = RALLMGenerationOptions(
                                    max_tokens = minOf(s.maxTokens, NPU_MAX_REPLY_TOKENS),
                                    temperature = s.temperature,
                                    system_prompt = s.systemPrompt.ifBlank { null },
                                    streaming_enabled = true,
                                    disable_thinking = true,
                                )
                                val request = opts.toRALLMGenerateRequest(text, history)
                                val result = RunAnywhere.aggregateStream(
                                    text,
                                    RunAnywhere.generateStream(request),
                                ) { acc ->
                                    val idx = messages.indexOfFirst { it.id == assistantId }
                                    if (idx >= 0) {
                                        messages[idx] = messages[idx].copy(text = stripThinkBlocks(acc))
                                    }
                                }
                                val idx = messages.indexOfFirst { it.id == assistantId }
                                if (idx >= 0) {
                                    messages[idx] = messages[idx].copy(
                                        text = stripThinkBlocks(
                                            result.text.ifBlank { messages[idx].text },
                                        ),
                                    )
                                }
                                tps = "%.1f".format(result.tokens_per_second)
                                ttft = result.ttft_ms?.let { "%.0f ms".format(it) } ?: "—"
                            } catch (e: Exception) {
                                error = e.message ?: "generation failed"
                                messages.removeAll { it.id == assistantId }
                            } finally {
                                running = false
                            }
                        }
                    },
                    enabled = !running && input.text.isNotBlank() && loadedModelId != null,
                ) {
                    Text(if (running) "…" else "Send")
                }
                if (running) {
                    TextButton(onClick = { scope.launch { RunAnywhere.cancelGeneration() } }) {
                        Text("Stop")
                    }
                }
            }
        }

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(
                onClick = {
                    messages.clear()
                    error = null
                    tps = "—"
                    ttft = "—"
                },
                enabled = !running && messages.isNotEmpty(),
            ) {
                Text("New chat")
            }
        }

        MetricStrip(listOf("tokens/s" to tps, "ttft" to ttft))

        error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun ChatBubble(msg: ChatMessage) {
    val isUser = msg.role == "user"
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start,
    ) {
        Box(
            Modifier
                .fillMaxWidth(0.85f)
                .background(
                    if (isUser) MaterialTheme.colorScheme.primaryContainer
                    else MaterialTheme.colorScheme.surfaceVariant,
                    MaterialTheme.shapes.medium,
                )
                .padding(Spacing.sm),
        ) {
            Text(
                if (msg.text.isBlank() && !isUser) "…" else msg.text,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}
