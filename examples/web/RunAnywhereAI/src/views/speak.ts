/**
 * Speak Tab — V2 canonical proto-byte TTS.
 *
 * Mirrors iOS `TTSViewModel`: the view hands text to `RunAnywhere.tts.speak()`
 * and the SDK handles synthesis AND playback internally (iOS parity:
 * TTSViewModel.swift:69-90). Stopping in-flight speech goes through
 * `RunAnywhere.tts.stop()` (iOS parity: TTSViewModel.swift:88-92).
 * The app never decodes PCM or owns an audio-playback pipeline.
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  type SpeechHandle,
} from '@runanywhere/web';
import {
  findLoadedModelForCategory,
  onModelStateChange,
  openSheet,
} from '../components/model-selection';
import {
  engineNoticeForCategories,
  isEngineBlocked,
  renderEngineNotice,
  wireEngineNotice,
} from '../components/engine-notice';
import { onEngineStateChange } from '../services/engine-availability';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const TTS_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
];

let container: HTMLElement;
let unmounted = false;
let unsubscribeEngine: (() => void) | null = null;
/**
 * True from the tap until the speaker actually falls silent.
 *
 * `tts.speak()` resolves as soon as it has handed back a `SpeechHandle` —
 * synthesis and playout both happen behind it. Treating that resolution as "done"
 * put the panel back into its idle state about a second before any sound came
 * out, and left Stop disabled for the whole utterance, so nothing on screen could
 * halt six seconds of audio. Playout, not the call, is what the user is waiting
 * on, so the flag follows the handle.
 */
let isSpeaking = false;
/** The utterance currently sounding, so Stop can interrupt that exact one. */
let activeSpeech: SpeechHandle | null = null;
let lastError: string | null = null;
/** How the previous utterance ended — a stop is a distinct outcome, not a failure. */
let lastOutcome: 'finished' | 'stopped' | null = null;
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
  // A successful retry has to restore the Speak control without a tab switch —
  // the same reason Solutions subscribes to this.
  unsubscribeEngine = onEngineStateChange(() => {
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
      void activeSpeech?.interrupt();
      if (!container.isConnected) {
        unsubscribeState?.();
        unsubscribeState = null;
        unsubscribeEngine?.();
        unsubscribeEngine = null;
      }
    },
  };
}

/**
 * Why this doesn't consult `RunAnywhere.runtime.modalities.tts`.
 *
 * That property answers *where* TTS would run (worker vs main thread), not
 * *whether* a speech engine registered — with no engine at all it still reports
 * `'main'`. Gating on it meant this view rendered an enabled Speak button and
 * the message "Load a TTS model first" on a session where the ONNX/Sherpa WASM
 * artifact had failed to load and no TTS model could ever appear in the picker.
 * The registration outcome in `engine-availability` is the real signal.
 */
function renderSpeak(): void {
  const notice = engineNoticeForCategories(TTS_PICKER_FILTER);
  const blocked = isEngineBlocked(notice);
  const loadedModel = findLoadedModelForCategory(
    ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
  );
  const modelLabel = loadedModel?.name ?? 'Choose a voice';
  const canRunInference = !blocked && Boolean(loadedModel);

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Read aloud</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="speak-model-btn" ${blocked ? 'disabled' : ''}>${escapeHtml(modelLabel)}</button>
      </div>
    </div>
    <div class="scroll-area">
      ${renderEngineNotice(notice)}
      <div class="docs-section">
        <h3>Turn text into speech</h3>
        <p class="text-secondary">Type anything and hear it spoken on this device. Nothing is sent to a server.</p>
        <textarea class="chat-input" id="speak-text" rows="3" aria-label="Text to read aloud" ${
          isSpeaking || blocked ? 'disabled' : ''
        }>${escapeHtml(DEFAULT_TEXT)}</textarea>
        <div class="speak-rate">
          <label class="speak-rate__label" for="speak-rate">Speed</label>
          <input
            type="range"
            id="speak-rate"
            class="speak-rate__slider"
            min="0.5"
            max="2"
            step="0.1"
            value="${speechRate}"
            aria-describedby="speak-rate-label"
            ${isSpeaking || blocked ? 'disabled' : ''}
          />
          <span class="speak-rate__value" id="speak-rate-label">${speechRate.toFixed(1)}×</span>
        </div>
        <div class="toolbar-actions">
          <button class="btn btn-primary" id="speak-btn" ${
            isSpeaking || !canRunInference ? 'disabled' : ''
          }>${isSpeaking ? 'Speaking…' : 'Read aloud'}</button>
          <button class="btn btn-secondary" id="stop-btn" ${
            isSpeaking ? '' : 'disabled'
          }>Stop</button>
        </div>
        <div id="speak-status" class="docs-status" role="status">${
          !blocked && !loadedModel ? 'Choose a voice to get started.' : ''
        }${
          lastError ? `Error: ${escapeHtml(lastError)}` : ''
        }${
          // The old readout claimed "Read Xs of audio" from the wall-clock time
          // of the speak() call, which returns before a single sample plays — it
          // reported 0.00s over a six-second utterance. The SDK's speech handle
          // exposes how the utterance ended but not its length, so report the
          // outcome, which is both true and the thing that differs.
          lastOutcome != null && !lastError && canRunInference
            ? lastOutcome === 'stopped' ? 'Stopped.' : 'Finished reading.'
            : ''
        }</div>
      </div>
    </div>
  `;

  wireEngineNotice(container, notice);

  container.querySelector('#speak-model-btn')?.addEventListener('click', () => {
    openSheet({
      title: 'Choose a voice',
      filterCategories: TTS_PICKER_FILTER,
    });
  });

  const rateInput = container.querySelector<HTMLInputElement>('#speak-rate');
  rateInput?.addEventListener('input', () => {
    speechRate = Number(rateInput.value);
    const label = container.querySelector('#speak-rate-label');
    if (label) label.textContent = `${speechRate.toFixed(1)}×`;
  });
  container.querySelector('#speak-btn')?.addEventListener('click', () => {
    void runSpeak();
  });
  container.querySelector('#stop-btn')?.addEventListener('click', () => {
    // Interrupt this utterance specifically, rather than the deprecated global
    // stop that guesses at the most recent handle.
    void activeSpeech?.interrupt();
  });
}

async function runSpeak(): Promise<void> {
  const textarea = container.querySelector<HTMLTextAreaElement>('#speak-text');
  const text = (textarea?.value ?? '').trim();
  if (!text) return;

  isSpeaking = true;
  lastError = null;
  lastOutcome = null;
  renderSpeak();

  try {
    // One verb synthesizes and plays through the device; the handle is what
    // tracks that playout and what Stop acts on.
    const handle = await RunAnywhere.tts.speak(text, { speed: speechRate });
    activeSpeech = handle;
    renderSpeak();
    await handle.waitForPlayout();
    // Playout failures arrive on the handle, not as a throw.
    if (handle.error) lastError = handle.error.message;
    else lastOutcome = handle.interrupted ? 'stopped' : 'finished';
  } catch (err) {
    lastError = formatError(err);
  } finally {
    activeSpeech = null;
    isSpeaking = false;
    if (!unmounted) renderSpeak();
  }
}
