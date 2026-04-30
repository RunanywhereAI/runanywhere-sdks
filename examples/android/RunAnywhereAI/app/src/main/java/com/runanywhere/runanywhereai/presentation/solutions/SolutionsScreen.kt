package com.runanywhere.runanywhereai.presentation.solutions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.presentation.components.ConfigureTopBar
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.solutions
import kotlinx.coroutines.launch

/**
 * Wave 3 Step 3.3 (G-E6): demo for `RunAnywhere.solutions.run(yaml = ...)`.
 *
 * Embeds the canonical voice_agent.yaml + rag.yaml from
 * sdk/runanywhere-commons/examples/solutions/ as inline string constants
 * — no asset-bundling churn — and exposes one button per solution.
 *
 * On click, creates the solution, starts the scheduler, and immediately
 * destroys the handle. Each lifecycle transition is appended to a simple
 * scrolling log so the demo stays readable without wiring up streaming
 * output yet.
 */
private val VOICE_AGENT_YAML = """
voice_agent:
  llm_model_id: "qwen3-4b-q4_k_m"
  stt_model_id: "whisper-base"
  tts_model_id: "kokoro"
  vad_model_id: "silero-v5"

  sample_rate_hz: 16000
  chunk_ms: 20
  audio_source: "microphone"

  enable_barge_in: true
  barge_in_threshold_ms: 200

  system_prompt: "You are a helpful voice assistant. Keep answers concise."
  max_context_tokens: 4096
  temperature: 0.7

  emit_partials: true
  emit_thoughts: false
""".trimIndent()

private val RAG_YAML = """
rag:
  embed_model_id: "bge-small-en-v1.5"
  rerank_model_id: "bge-reranker-v2-m3"
  llm_model_id: "qwen3-4b-q4_k_m"

  vector_store: "usearch"
  vector_store_path: "/tmp/ra-rag.usearch"

  retrieve_k: 24
  rerank_top: 6

  bm25_k1: 1.2
  bm25_b: 0.75
  rrf_k: 60

  prompt_template: "Use the context below to answer.\nContext:\n{{context}}\n\nQuestion: {{query}}"
""".trimIndent()

@Composable
fun SolutionsScreen() {
    ConfigureTopBar(title = "Solutions")

    val log = remember { mutableStateListOf<String>() }
    var isRunning by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun append(line: String) {
        log.add(line)
    }

    fun runSolution(name: String, yaml: String) {
        if (isRunning) return
        isRunning = true
        append("→ $name: creating solution from YAML…")
        scope.launch {
            try {
                val handle = RunAnywhere.solutions.run(yaml = yaml)
                append("✓ $name: handle created. Calling start()…")
                handle.start()
                append("✓ $name: started. Tearing down (demo).")
                handle.destroy()
                append("✓ $name: destroyed.")
            } catch (t: Throwable) {
                append("✗ $name: ${t.message ?: t.toString()}")
            } finally {
                isRunning = false
            }
        }
    }

    Column(
        modifier =
            Modifier
                .fillMaxSize()
                .padding(16.dp),
    ) {
        Text(
            "Run a prepackaged pipeline (voice agent or RAG) by handing a YAML config to RunAnywhere.solutions.run.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Button(
                onClick = { runSolution("Voice Agent", VOICE_AGENT_YAML) },
                enabled = !isRunning,
                modifier = Modifier.weight(1f),
            ) {
                Text("Voice Agent")
            }
            Button(
                onClick = { runSolution("RAG", RAG_YAML) },
                enabled = !isRunning,
                modifier = Modifier.weight(1f),
            ) {
                Text("RAG")
            }
        }
        Spacer(Modifier.height(16.dp))
        Column(
            modifier =
                Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState()),
        ) {
            log.forEach { line ->
                Text(
                    line,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}
