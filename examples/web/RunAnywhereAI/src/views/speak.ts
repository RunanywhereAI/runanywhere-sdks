/**
 * Speak Tab - Text-to-Speech synthesis
 * Mirrors iOS TTSView.
 */

import type { TabLifecycle } from '../app';
import { ModelManager, ModelCategory, type ModelInfo } from '../services/model-manager';
import { showModelSelectionSheet } from '../components/model-selection';

let container: HTMLElement;

// Funny texts for TTS "Surprise me" (matching iOS)
const SURPRISE_TEXTS = [
  "Why don't scientists trust atoms? Because they make up everything!",
  "I told my wife she was drawing her eyebrows too high. She looked surprised.",
  "Parallel lines have so much in common. It's a shame they'll never meet.",
  "I'm reading a book on anti-gravity. It's impossible to put down!",
  "Did you hear about the mathematician who's afraid of negative numbers? He'll stop at nothing to avoid them.",
  "What do you call a fake noodle? An impasta!",
  "I would tell you a construction joke, but I'm still working on it.",
];

let ttsIsSpeaking = false;
let ttsPlayback: import('../../../../../sdk/runanywhere-web/packages/core/src/Infrastructure/AudioPlayback').AudioPlayback | null = null;

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export function initSpeakTab(el: HTMLElement): TabLifecycle {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-actions"></div>
      <div class="toolbar-model-btn" id="tts-toolbar-model" title="Tap to change model">
        <svg class="model-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>
        <span id="tts-toolbar-model-text">Select TTS Model</span>
        <svg class="chevron" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>
      </div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area tts-layout">
      <textarea class="chat-input tts-textarea" id="speak-text" placeholder="Enter text to speak..." rows="5"></textarea>
      <button class="btn btn-sm text-purple" id="speak-surprise-btn">Surprise me</button>
      <div class="tts-speed-row">
        <label class="tts-speed-label">Speed</label>
        <input type="range" id="speak-speed" min="0.5" max="2" step="0.1" value="1" class="flex-1">
        <span id="speak-speed-val" class="tts-speed-value">1.0x</span>
      </div>
      <div id="tts-error" class="tts-message error-text hidden"></div>
      <div id="tts-status" class="tts-message helper-text hidden"></div>
      <button class="btn btn-primary btn-lg tts-speak-btn" id="speak-btn">
        Speak
      </button>
    </div>
  `;

  const speedSlider = container.querySelector('#speak-speed') as HTMLInputElement;
  const speedVal = container.querySelector('#speak-speed-val')!;

  speedSlider.addEventListener('input', () => {
    speedVal.textContent = parseFloat(speedSlider.value).toFixed(1) + 'x';
  });

  container.querySelector('#speak-surprise-btn')!.addEventListener('click', () => {
    (container.querySelector('#speak-text') as HTMLTextAreaElement).value =
      SURPRISE_TEXTS[Math.floor(Math.random() * SURPRISE_TEXTS.length)];
  });

  container.querySelector('#tts-toolbar-model')!.addEventListener('click', () =>
    showModelSelectionSheet(ModelCategory.SpeechSynthesis),
  );

  container.querySelector('#speak-btn')!.addEventListener('click', handleSpeak);

  // Subscribe to model changes so the pill label stays current
  ModelManager.onChange(onTTSModelsChanged);
  onTTSModelsChanged(ModelManager.getModels());

  return {
    onDeactivate(): void {
      if (ttsPlayback) {
        ttsPlayback.stop();
        ttsIsSpeaking = false;
        renderSpeakUI();
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Model Selector
// ---------------------------------------------------------------------------

function onTTSModelsChanged(_models: ModelInfo[]): void {
  const loaded = ModelManager.getLoadedModel(ModelCategory.SpeechSynthesis);
  const textSpan = container.querySelector('#tts-toolbar-model-text');
  if (textSpan) {
    textSpan.textContent = loaded ? loaded.name : 'Select TTS Model';
  }
}

// ---------------------------------------------------------------------------
// Speak Logic
// ---------------------------------------------------------------------------

async function handleSpeak(): Promise<void> {
  const textArea = container.querySelector('#speak-text') as HTMLTextAreaElement;
  const speedSlider = container.querySelector('#speak-speed') as HTMLInputElement;
  const errorEl = container.querySelector('#tts-error') as HTMLElement;
  const statusEl = container.querySelector('#tts-status') as HTMLElement;

  const text = textArea.value.trim();
  if (!text) {
    errorEl.classList.remove('hidden');
    errorEl.textContent = 'Please enter some text to speak.';
    return;
  }

  if (ttsIsSpeaking && ttsPlayback) {
    ttsPlayback.stop();
    ttsIsSpeaking = false;
    renderSpeakUI();
    return;
  }

  errorEl.classList.add('hidden');
  statusEl.classList.remove('hidden');
  statusEl.textContent = 'Loading TTS model...';

  try {
    const ttsModel = await ModelManager.ensureLoaded(ModelCategory.SpeechSynthesis);
    if (!ttsModel) {
      throw new Error('No TTS model available. Tap the model button (top right) to download one.');
    }

    statusEl.textContent = 'Synthesizing speech...';
    const speed = parseFloat(speedSlider.value);

    const { AudioPlayback } = await import(
      '../../../../../sdk/runanywhere-web/packages/core/src/index'
    );
    const { TTS } = await import(
      '../../../../../sdk/runanywhere-web/packages/onnx/src/index'
    );

    if (!TTS.isVoiceLoaded) {
      throw new Error('TTS voice not loaded. Select and load a model first.');
    }

    const result = await TTS.synthesize(text, { speed });

    statusEl.textContent = `Playing (${(result.durationMs / 1000).toFixed(1)}s)...`;
    ttsIsSpeaking = true;
    renderSpeakUI();

    if (!ttsPlayback) ttsPlayback = new AudioPlayback();

    await ttsPlayback.play(result.audioData, result.sampleRate);

    ttsIsSpeaking = false;
    statusEl.textContent = `Done — ${(result.durationMs / 1000).toFixed(1)}s audio in ${(result.processingTimeMs / 1000).toFixed(1)}s`;
    renderSpeakUI();
  } catch (err) {
    ttsIsSpeaking = false;
    errorEl.classList.remove('hidden');
    errorEl.textContent = err instanceof Error ? err.message : String(err);
    statusEl.classList.add('hidden');
    renderSpeakUI();
  }
}

function renderSpeakUI(): void {
  const speakBtn = container.querySelector('#speak-btn') as HTMLButtonElement;
  speakBtn.classList.toggle('stopping', ttsIsSpeaking);
  speakBtn.textContent = ttsIsSpeaking ? 'Stop' : 'Speak';
}
