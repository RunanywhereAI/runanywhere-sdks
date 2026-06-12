/**
 * Solutions Tab — demo for `RunAnywhere.solutions.run({ yaml })`.
 *
 * Two buttons run the canonical voice_agent.yaml + rag.yaml solutions
 * shipped at sdk/runanywhere-commons/examples/solutions/. The YAMLs are
 * embedded inline as string constants (no asset bundling). Each lifecycle
 * transition is appended to a simple scrolling log.
 */
import { RunAnywhere } from '@runanywhere/web';
import { ONNX } from '@runanywhere/web-onnx';
import type { TabLifecycle } from '../app';
import { formatError } from '../services/format-error';

// Use model IDs that are actually registered by services/model-catalog.ts;
// the placeholder IDs from sdk/runanywhere-commons/examples/solutions/*.yaml
// (whisper-base, kokoro, silero-v5, bge-small-en-v1.5, bge-reranker-v2-m3,
// qwen3-4b-q4_k_m) are not present in any example catalog, so handing them
// to RunAnywhere.solutions.run produces a "model not found in registry"
// failure as soon as the operators load. rerank_model_id is omitted because
// no example app seeds a reranker model.
const VOICE_AGENT_YAML = `voice_agent:
  llm_model_id: "smollm2-360m-q8_0"
  stt_model_id: "sherpa-onnx-whisper-tiny.en"
  tts_model_id: "vits-piper-en_US-lessac-medium"
  vad_model_id: "silero-vad"

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
`;

const RAG_YAML = `rag:
  embed_model_id: "all-minilm-l6-v2"
  llm_model_id: "smollm2-360m-q8_0"

  vector_store: "usearch"
  vector_store_path: "/tmp/ra-rag.usearch"

  retrieve_k: 24
  rerank_top: 6

  bm25_k1: 1.2
  bm25_b: 0.75
  rrf_k: 60

  prompt_template: "Use the context below to answer.\\n\\nContext:\\n{{context}}\\n\\nQuestion: {{query}}"
`;

export function initSolutionsTab(host: HTMLElement): TabLifecycle {
  host.innerHTML = `
    <div class="solutions-view" style="padding: 16px; display: flex; flex-direction: column; gap: 16px; height: 100%; box-sizing: border-box;">
      <p style="margin: 0; font-size: 14px; color: var(--color-text-secondary, #666);">
        Run a prepackaged pipeline (voice agent or RAG) by handing a YAML config
        to <code>RunAnywhere.solutions.run</code>.
      </p>
      <div style="display: flex; gap: 12px;">
        <button id="solutions-run-voice" class="primary-button" style="flex: 1; padding: 10px;">Voice Agent</button>
        <button id="solutions-run-rag" class="primary-button" style="flex: 1; padding: 10px;">RAG</button>
      </div>
      <pre id="solutions-log" style="flex: 1; margin: 0; padding: 8px; background: var(--color-surface-2, #f4f4f4); border-radius: 8px; overflow: auto; font-size: 12px; font-family: ui-monospace, Menlo, monospace; white-space: pre-wrap;"></pre>
    </div>
  `;

  const voiceBtn = host.querySelector<HTMLButtonElement>('#solutions-run-voice')!;
  const ragBtn = host.querySelector<HTMLButtonElement>('#solutions-run-rag')!;
  const logEl = host.querySelector<HTMLPreElement>('#solutions-log')!;

  let running = false;

  const append = (line: string) => {
    logEl.textContent = `${logEl.textContent ?? ''}${line}\n`;
    logEl.scrollTop = logEl.scrollHeight;
  };

  const updateRAGCapabilityState = () => {
    const availability = RunAnywhere.rag.availability();
    ragBtn.title = availability.available
      ? 'Run RAG solution'
      : availability.reason;
  };

  const runSolution = async (name: string, yaml: string) => {
    if (running) return;

    if (name === 'Voice Agent') {
      if (!ONNX.isRegistered) {
        try {
          await ONNX.register();
        } catch (err) {
          append(`N/A Voice Agent: ONNX register failed: ${formatError(err)}`);
          return;
        }
      }
    }

    if (name === 'RAG') {
      let availability = RunAnywhere.rag.availability();
      // wasm-exports means the RAG WASM is healthy but no provider has
      // bootstrapped yet; the example owns that bootstrap so the demo can
      // exercise the public API end-to-end. Only treat truly missing exports
      // (RAC_BACKEND_RAG=OFF or no WASM module) as terminal.
      if (!availability.available && availability.source === 'wasm-exports') {
        try {
          await RunAnywhere.rag.createPipeline(
            RunAnywhere.rag.defaultConfiguration({
              embeddingModelId: 'all-minilm-l6-v2',
              llmModelId: 'smollm2-360m-q8_0',
            }),
          );
          availability = RunAnywhere.rag.availability();
        } catch (err) {
          append(`N/A RAG: bootstrap failed: ${formatError(err)}`);
          return;
        }
      }
      if (!availability.available) {
        append(`N/A RAG: ${availability.reason}`);
        if (availability.missingExports.length > 0) {
          append(`N/A RAG: missing ${availability.missingExports.join(', ')}`);
        }
        return;
      }
    }

    running = true;
    voiceBtn.disabled = true;
    ragBtn.disabled = true;
    append(`-> ${name}: creating solution from YAML...`);
    try {
      const handle = RunAnywhere.solutions.run({ yaml });
      append(`OK ${name}: handle created. Calling start()...`);
      handle.start();
      append(`OK ${name}: started. Tearing down (demo).`);
      handle.destroy();
      append(`OK ${name}: destroyed.`);
    } catch (err) {
      append(`ERR ${name}: ${formatError(err)}`);
    } finally {
      running = false;
      voiceBtn.disabled = false;
      ragBtn.disabled = false;
      updateRAGCapabilityState();
    }
  };

  updateRAGCapabilityState();

  voiceBtn.addEventListener('click', () => runSolution('Voice Agent', VOICE_AGENT_YAML));
  ragBtn.addEventListener('click', () => runSolution('RAG', RAG_YAML));

  return {};
}
