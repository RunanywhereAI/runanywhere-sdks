/**
 * Transcribe Tab — V2 canonical proto-byte STT.
 *
 * Mirrors iOS `STTViewModel` with a Batch / Live mode toggle (iOS parity:
 * STTViewModel.swift:43-61 `selectedMode`):
 *
 *  - Batch (STTViewModel.swift:241-261): record, then one-shot
 *    `RunAnywhere.stt.transcribe(audio)`.
 *  - Live (STTViewModel.swift:365-408): the SDK streaming session emits
 *    partial hypotheses (`isFinal=false`) that preview the utterance and a
 *    final result (`isFinal=true`) that replaces them.
 *
 * A file-upload affordance is kept as a justified web addition (browsers
 * have first-class file pickers; decoding goes through `AudioFileLoader`).
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  type AudioInput,
} from '@runanywhere/web';
import {
  AudioCapture,
  AudioFileLoader,
} from '@runanywhere/web/browser';
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
import { renderFileDrop, wireFileDrop } from '../components/file-drop';
import { icon } from '../components/icons';
import { onEngineStateChange } from '../services/engine-availability';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const STT_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
];

/** UI mode — mirrors iOS `STTMode` (STTViewModel.swift:442-462; hybrid is
 * cloud-router-only and not exposed on web). */
type STTMode = 'batch' | 'live';

let container: HTMLElement;
let unmounted = false;
let audioCapture: AudioCapture | null = null;
let isCapturing = false;
let isProcessing = false;
let selectedMode: STTMode = 'batch';
let transcript = '';
let unsubscribeState: (() => void) | null = null;
let unsubscribeEngine: (() => void) | null = null;

export function initTranscribeTab(el: HTMLElement): TabLifecycle {
  container = el;
  unmounted = false;
  renderTranscribe();
  unsubscribeState = onModelStateChange(() => {
    if (!unmounted) renderTranscribe();
  });
  // A successful engine retry must restore the recording controls without the
  // user having to leave the tab and come back.
  unsubscribeEngine = onEngineStateChange(() => {
    if (!unmounted) renderTranscribe();
  });
  return {
    // app.ts fires onDeactivate on every tab switch (not only on panel
    // teardown). Treat the flag as a "currently inactive" guard for
    // in-flight async renders and reset it on re-activation so a returning
    // user doesn't see stale microphone / processing state.
    onActivate: () => {
      unmounted = false;
      renderTranscribe();
    },
    onDeactivate: () => {
      unmounted = true;
      audioCapture?.stop();
      audioCapture = null;
      isCapturing = false;
      if (!container.isConnected) {
        unsubscribeState?.();
        unsubscribeState = null;
        unsubscribeEngine?.();
        unsubscribeEngine = null;
      }
    },
  };
}

/** What each mode means, in the user's terms rather than the SDK verb's. */
const MODE_COPY: Record<STTMode, { label: string; detail: string }> = {
  batch: {
    label: 'Record, then transcribe',
    detail: 'Records everything first, then transcribes it in one pass. Most accurate.',
  },
  live: {
    label: 'Transcribe as I speak',
    detail: 'Shows words as they are recognised. Earlier guesses are corrected as it goes.',
  },
};

/**
 * Why this doesn't consult `RunAnywhere.runtime.modalities.stt`.
 *
 * That property answers *where* STT would run (worker vs main thread), not
 * *whether* a speech engine registered — with no engine at all it still reports
 * `'main'`. Gating on it meant this view rendered an enabled "Start recording"
 * and the message "Load an STT model first" on a session where the ONNX/Sherpa
 * WASM artifact had failed to load, so no STT model could ever appear in the
 * picker. The registration outcome in `engine-availability` is the real signal.
 */
function renderTranscribe(): void {
  const notice = engineNoticeForCategories(STT_PICKER_FILTER);
  const blocked = isEngineBlocked(notice);
  const loadedModel = findLoadedModelForCategory(
    ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  );
  const modelLabel = loadedModel?.name ?? 'Choose a model';
  const canRunInference = !blocked && Boolean(loadedModel);
  const busy = isCapturing || isProcessing;

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Transcribe</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="transcribe-model-btn" ${blocked ? 'disabled' : ''}>${escapeHtml(modelLabel)}</button>
      </div>
    </div>
    <div class="scroll-area">
      ${renderEngineNotice(notice)}
      <div class="docs-section">
        <h3>How to listen</h3>
        <div class="segmented" role="radiogroup" aria-label="Transcription mode">
          ${(['batch', 'live'] as const).map((mode) => `
            <button type="button" class="segmented__option" id="mode-${mode}-btn"
              role="radio" aria-checked="${selectedMode === mode}"
              ${busy || blocked ? 'disabled' : ''}>${MODE_COPY[mode].label}</button>
          `).join('')}
        </div>
        <p class="text-secondary">${MODE_COPY[selectedMode].detail}</p>
      </div>
      <div class="docs-section">
        <h3>Record</h3>
        <div class="toolbar-actions">
          <button class="btn ${isCapturing ? 'btn-secondary' : 'btn-primary'}" id="mic-toggle-btn" ${isProcessing || !canRunInference ? 'disabled' : ''}>
            ${isCapturing ? 'Stop and transcribe' : 'Start recording'}
          </button>
          <button class="btn btn-secondary" id="clear-btn" ${isProcessing || !transcript ? 'disabled' : ''}>Clear</button>
        </div>
        ${!blocked && !loadedModel
          ? '<div class="docs-status">Choose a model to start transcribing.</div>'
          : ''}
      </div>
      <div class="docs-section">
        <h3>Or use a recording</h3>
        ${renderFileDrop({
          id: 'transcribe-drop',
          accept: 'audio/*',
          title: 'Drop an audio file here, or click to choose',
          hint: 'WAV, MP3, M4A, OGG, FLAC and other formats your browser can decode',
          disabled: isProcessing || !canRunInference,
        })}
      </div>
      <div class="docs-section">
        <h3>Transcript</h3>
        <div id="transcribe-status" class="docs-status" role="status" aria-live="polite">${isProcessing ? 'Transcribing…' : ''}</div>
        ${transcript
          ? `<pre id="transcribe-output" class="docs-pre">${escapeHtml(transcript)}</pre>`
          : `<div class="surface-empty" id="transcribe-output">
               ${icon('waveform', { size: 24 })}
               <p>Your transcript will appear here.</p>
             </div>`}
      </div>
    </div>
  `;

  wireEngineNotice(container, notice);

  container.querySelector('#transcribe-model-btn')?.addEventListener('click', () => {
    openSheet({
      title: 'Choose a transcription model',
      filterCategories: STT_PICKER_FILTER,
    });
  });

  for (const mode of ['batch', 'live'] as const) {
    container.querySelector(`#mode-${mode}-btn`)?.addEventListener('click', () => {
      selectedMode = mode;
      renderTranscribe();
    });
  }
  container.querySelector('#mic-toggle-btn')?.addEventListener('click', () => {
    void toggleMic();
  });
  container.querySelector('#clear-btn')?.addEventListener('click', () => {
    transcript = '';
    renderTranscribe();
  });
  wireFileDrop(container, 'transcribe-drop', (files) => {
    const file = files[0];
    if (file) void transcribeFile(file);
  });
}

async function toggleMic(): Promise<void> {
  if (isCapturing) {
    await stopMicAndTranscribe();
    return;
  }
  await startMic();
}

async function startMic(): Promise<void> {
  audioCapture = audioCapture ?? new AudioCapture({ sampleRate: 16000 });
  try {
    await audioCapture.start();
    isCapturing = true;
    transcript = '';
    renderTranscribe();
  } catch (err) {
    setStatus(`Microphone error: ${formatError(err)}`);
  }
}

async function stopMicAndTranscribe(): Promise<void> {
  if (!audioCapture) return;
  const samples = audioCapture.getAudioBuffer();
  audioCapture.stop();
  isCapturing = false;
  if (samples.length === 0) {
    setStatus('No audio captured.');
    renderTranscribe();
    return;
  }
  if (selectedMode === 'live') {
    await runTranscribeStream(samples);
  } else {
    await runTranscribe(samples);
  }
}

async function transcribeFile(file: File): Promise<void> {
  isProcessing = true;
  renderTranscribe();
  try {
    const decoded = await AudioFileLoader.toFloat32Array(file, 16000);
    if (selectedMode === 'live') {
      await runTranscribeStream(decoded.samples);
    } else {
      await runTranscribe(decoded.samples);
    }
  } catch (err) {
    setStatus(`Failed to decode file: ${formatError(err)}`);
  } finally {
    isProcessing = false;
    renderTranscribe();
  }
}

/** Batch mode — one-shot transcription (iOS parity: STTViewModel.swift:252). */
async function runTranscribe(samples: Float32Array): Promise<void> {
  isProcessing = true;
  renderTranscribe();
  setStatus(`Transcribing ${(samples.length / 16000).toFixed(2)}s of audio...`);
  try {
    const output = await RunAnywhere.stt.transcribe(RunAnywhere.AudioInput.float32(samples));
    transcript = output.text;
    setStatus('Done.');
  } catch (err) {
    setStatus(`Transcribe failed: ${formatError(err)}`);
  } finally {
    isProcessing = false;
    renderTranscribe();
  }
}

/**
 * Live mode — the streaming verb takes a chunk stream and emits `partial`
 * previews followed by the `final` transcription. Failures throw into this
 * loop rather than arriving as a terminal partial.
 */
async function runTranscribeStream(samples: Float32Array): Promise<void> {
  isProcessing = true;
  renderTranscribe();
  setStatus(`Streaming ${(samples.length / 16000).toFixed(2)}s of audio...`);

  async function* chunks(): AsyncGenerator<AudioInput> {
    yield RunAnywhere.AudioInput.float32(samples);
  }

  try {
    transcript = '';
    for await (const event of RunAnywhere.stt.transcribeStream(chunks())) {
      if (event.type === 'partial') {
        const text = event.alternatives[0]?.text.trim();
        if (text) {
          transcript = text;
          updateOutput();
        }
      } else if (event.type === 'transcriptFinal') {
        transcript = event.segment.text.trim();
        updateOutput();
      }
    }
    setStatus('Done.');
  } catch (err) {
    setStatus(`Transcribe failed: ${formatError(err)}`);
  } finally {
    isProcessing = false;
    renderTranscribe();
  }
}

/**
 * Push a streaming partial into the transcript element.
 *
 * The empty state is a different element from the transcript, so the first
 * partial has to swap them — writing `textContent` into the empty-state block
 * would erase its icon and leave a bare line of text. Once a `<pre>` is on
 * screen, later partials mutate it in place: a full re-render per token would
 * rebuild the toolbar and the drop zone mid-utterance.
 */
function updateOutput(): void {
  const pre = container.querySelector<HTMLPreElement>('pre#transcribe-output');
  if (pre) {
    pre.textContent = transcript;
    return;
  }
  renderTranscribe();
}

function setStatus(text: string): void {
  const banner = container.querySelector<HTMLDivElement>('#transcribe-status');
  if (banner) banner.textContent = text;
}
