/**
 * Solutions Tab — demo for `RunAnywhere.solutions.run({ yaml })`.
 *
 * Two buttons run the canonical voice_agent.yaml + rag.yaml solutions
 * shipped at sdk/runanywhere-commons/examples/solutions/. The YAMLs are
 * synced from the canonical commons files into a generated module via
 * `scripts/sync-solutions.mjs` (iOS parity:
 * examples/ios/RunAnywhereAI/scripts/sync-solutions-yamls.sh) so the view
 * never embeds drift-prone inline copies. Each lifecycle transition is
 * appended to a simple scrolling log.
 */
import { RunAnywhere, type RAGAvailability } from '@runanywhere/web';
import type { TabLifecycle } from '../app';
import { formatError } from '../services/format-error';
import { RAG_YAML, VOICE_AGENT_YAML } from '../services/solutions-config';

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
      <input id="solutions-feed" type="text" placeholder="Optional UTF-8 item to feed before teardown"
        style="padding: 8px; border-radius: 6px; border: 1px solid var(--color-border, #ccc);" />
      <pre id="solutions-log" style="flex: 1; margin: 0; padding: 8px; background: var(--color-surface-2, #f4f4f4); border-radius: 8px; overflow: auto; font-size: 12px; font-family: ui-monospace, Menlo, monospace; white-space: pre-wrap;"></pre>
    </div>
  `;

  const voiceBtn = host.querySelector<HTMLButtonElement>('#solutions-run-voice')!;
  const ragBtn = host.querySelector<HTMLButtonElement>('#solutions-run-rag')!;
  const feedInput = host.querySelector<HTMLInputElement>('#solutions-feed')!;
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

    if (name === 'RAG') {
      // `rag.ensureReady` owns the bootstrap: when the RAG WASM exports are
      // healthy but no provider has bootstrapped yet, the SDK creates the
      // native session; truly missing exports (RAC_BACKEND_RAG=OFF or no
      // WASM module) come back as a terminal unavailable snapshot.
      let availability: RAGAvailability;
      try {
        availability = await RunAnywhere.rag.ensureReady({
          embeddingModelId: 'all-minilm-l6-v2',
          llmModelId: 'smollm2-360m-q8_0',
        });
      } catch (err) {
        append(`N/A RAG: bootstrap failed: ${formatError(err)}`);
        return;
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
      const item = feedInput.value.trim();
      if (item) {
        handle.feed(item);
        append(`OK ${name}: fed one UTF-8 item.`);
      }
      handle.closeInput();
      append(`OK ${name}: input closed. Waiting for deterministic teardown...`);
      await handle.wait();
      append(`OK ${name}: teardown complete.`);
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

  voiceBtn.addEventListener('click', () => {
    void runSolution('Voice Agent', VOICE_AGENT_YAML);
  });
  ragBtn.addEventListener('click', () => {
    void runSolution('RAG', RAG_YAML);
  });

  return {};
}
