/**
 * Speak Tab — V2 canonical proto-byte TTS.
 *
 * Mirrors iOS `TTSViewModel`: the view hands text to `RunAnywhere.speak()`
 * and the SDK handles synthesis AND playback internally (iOS parity:
 * TTSViewModel.swift:69-90). Stopping in-flight speech goes through
 * `RunAnywhere.stopSpeaking()` (iOS parity: TTSViewModel.swift:88-92).
 * The app never decodes PCM or owns an audio-playback pipeline.
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
} from '@runanywhere/web';
import {
  findLoadedModelForCategory,
  onModelStateChange,
  openSheet,
} from '../components/model-selection';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const TTS_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
];

let container: HTMLElement;
let unmounted = false;
let isSynthesizing = false;
let lastError: string | null = null;
let lastDurationMs: number | null = null;
/** Speech rate 0.5 – 2.0 (iOS parity: TextToSpeechView.swift:244 slider). */
let speechRate = 1.0;
let unsubscribeState: (() => void) | null = null;

const DEFAULT_TEXT =
  'Hello — this synthesis was generated entirely on-device through the ' +
  'RunAnywhere Web SDK and the proto-byte TTS adapter.';

export function initSpeakTab(el: HTMLElement): TabLifecycle {
  container = el;
  unmounted = false;
  renderSpeak();
  unsubscribeState = onModelStateChange(() => {
    if (!unmounted) renderSpeak();
  });
  return {
    // app.ts fires onDeactivate on every tab switch (not only on panel
    // teardown). Treat the flag as a "currently inactive" guard for
    // in-flight async renders and reset it on re-activation so a returning
    // user doesn't see stuck Speak / Synthesizing controls.
    onActivate: () => {
      unmounted = false;
      renderSpeak();
    },
    onDeactivate: () => {
      unmounted = true;
      // Stop any in-flight SDK playback when leaving the tab.
      RunAnywhere.stopSpeaking();
      if (!container.isConnected && unsubscribeState) {
        unsubscribeState();
        unsubscribeState = null;
      }
    },
  };
}

function renderSpeak(): void {
  const supportsProto = RunAnywhere.tts.supportsProtoTTS();
  const loadedModel = findLoadedModelForCategory(
    ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
  );
  const modelLabel = loadedModel?.name ?? 'Select TTS Model';
  const canRunInference = supportsProto && Boolean(loadedModel);

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Speak</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="speak-model-btn">${escapeHtml(modelLabel)}</button>
      </div>
    </div>
    <div class="scroll-area">
      ${supportsProto
        ? `
          <div class="docs-section">
            <h3>Synthesize</h3>
            <p class="text-secondary">Type some text and let on-device TTS render it. The SDK synthesizes and plays the audio through <code>RunAnywhere.speak()</code>.</p>
            <textarea class="chat-input" id="speak-text" rows="3" ${
              isSynthesizing ? 'disabled' : ''
            }>${escapeHtml(DEFAULT_TEXT)}</textarea>
            <div class="docs-status" style="display:flex;align-items:center;gap:8px">
              <strong>Rate:</strong>
              <input
                type="range"
                id="speak-rate"
                min="0.5"
                max="2"
                step="0.1"
                value="${speechRate}"
                style="flex:1;max-width:240px"
                ${isSynthesizing ? 'disabled' : ''}
              />
              <span id="speak-rate-label">${speechRate.toFixed(1)}x</span>
            </div>
            <div class="toolbar-actions">
              <button class="btn btn-primary" id="speak-btn" ${
                isSynthesizing || !canRunInference ? 'disabled' : ''
              }>${isSynthesizing ? 'Speaking...' : 'Speak'}</button>
              <button class="btn btn-secondary" id="stop-btn" ${
                isSynthesizing ? '' : 'disabled'
              }>Stop</button>
            </div>
            <div id="speak-status" class="docs-status">${
              !canRunInference ? 'Load a TTS model first.' : ''
            }${
              lastError ? `Error: ${escapeHtml(lastError)}` : ''
            }${
              lastDurationMs != null && !lastError && canRunInference
                ? `Last synthesis: ${(lastDurationMs / 1000).toFixed(2)}s of audio.`
                : ''
            }</div>
          </div>`
        : `
          <div class="docs-section">
            <h3>Synthesis</h3>
            <p class="text-secondary">
              Real TTS calls dispatch through <code>RunAnywhere.speak(text, options)</code>
              once a speech-capable backend is registered against a WASM build
              that includes <code>RAC_WASM_ONNX=ON</code>.
            </p>
            <ul class="feature-unavailable__list">
              <li><code>RunAnywhere.loadModel(...)</code></li>
              <li><code>RunAnywhere.speak(text, { speakingRate })</code></li>
              <li><code>RunAnywhere.stopSpeaking()</code></li>
            </ul>
          </div>`}
    </div>
  `;

  container.querySelector('#speak-model-btn')?.addEventListener('click', () => {
    openSheet({
      title: 'Select TTS Model',
      filterCategories: TTS_PICKER_FILTER,
    });
  });

  if (supportsProto) {
    const rateInput = container.querySelector<HTMLInputElement>('#speak-rate');
    rateInput?.addEventListener('input', () => {
      speechRate = Number(rateInput.value);
      const label = container.querySelector('#speak-rate-label');
      if (label) label.textContent = `${speechRate.toFixed(1)}x`;
    });
    container.querySelector('#speak-btn')?.addEventListener('click', () => {
      void runSpeak();
    });
    container.querySelector('#stop-btn')?.addEventListener('click', () => {
      RunAnywhere.stopSpeaking();
    });
  }
}

async function runSpeak(): Promise<void> {
  const textarea = container.querySelector<HTMLTextAreaElement>('#speak-text');
  const text = (textarea?.value ?? '').trim();
  if (!text) return;

  isSynthesizing = true;
  lastError = null;
  lastDurationMs = null;
  renderSpeak();

  try {
    // SDK handles everything — synthesis AND playback (iOS parity:
    // TTSViewModel.swift:69-78 builds options with speakingRate, then
    // `RunAnywhere.speak(text, options:)`).
    const result = await RunAnywhere.speak(text, { speakingRate: speechRate });
    lastDurationMs = result.durationMs ?? 0;
  } catch (err) {
    lastError = formatError(err);
  } finally {
    isSynthesizing = false;
    if (!unmounted) renderSpeak();
  }
}
