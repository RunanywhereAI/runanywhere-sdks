/**
 * Transcribe Tab — V2 canonical proto-byte STT.
 *
 * Mirrors iOS `STTViewModel` with a Batch / Live mode toggle (iOS parity:
 * STTViewModel.swift:43-61 `selectedMode`):
 *
 *  - Batch (STTViewModel.swift:241-261): record, then one-shot
 *    `RunAnywhere.transcribe(samples)`.
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

export function initTranscribeTab(el: HTMLElement): TabLifecycle {
  container = el;
  unmounted = false;
  renderTranscribe();
  unsubscribeState = onModelStateChange(() => {
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
      if (!container.isConnected && unsubscribeState) {
        unsubscribeState();
        unsubscribeState = null;
      }
    },
  };
}

function renderTranscribe(): void {
  const supportsProto = RunAnywhere.stt.supportsProtoSTT();
  const loadedModel = findLoadedModelForCategory(
    ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  );
  const modelLabel = loadedModel?.name ?? 'Select STT Model';
  const canRunInference = supportsProto && Boolean(loadedModel);

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Transcribe</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="transcribe-model-btn">${escapeHtml(modelLabel)}</button>
      </div>
    </div>
    <div class="scroll-area">
      ${supportsProto
        ? `
          <div class="docs-section">
            <h3>Mode</h3>
            <div class="toolbar-actions">
              <button class="btn ${selectedMode === 'batch' ? 'btn-primary' : 'btn-secondary'}" id="mode-batch-btn" ${isCapturing || isProcessing ? 'disabled' : ''}>Batch</button>
              <button class="btn ${selectedMode === 'live' ? 'btn-primary' : 'btn-secondary'}" id="mode-live-btn" ${isCapturing || isProcessing ? 'disabled' : ''}>Live</button>
            </div>
            <p class="text-secondary">${selectedMode === 'batch'
              ? 'Record first, then transcribe.'
              : 'Stream with live partial results — partials preview the utterance, the final result replaces them.'}</p>
          </div>
          <div class="docs-section">
            <h3>Microphone</h3>
            <p class="text-secondary">Capture audio from your microphone, then transcribe it through <code>${selectedMode === 'live' ? 'RunAnywhere.transcribeStream(...)' : 'RunAnywhere.transcribe(...)'}</code>.</p>
            <div class="toolbar-actions">
              <button class="btn btn-primary" id="mic-toggle-btn" ${isProcessing || !canRunInference ? 'disabled' : ''}>
                ${isCapturing ? 'Stop & transcribe' : 'Start recording'}
              </button>
              <button class="btn btn-secondary" id="clear-btn" ${isProcessing ? 'disabled' : ''}>Clear</button>
            </div>
            ${canRunInference ? '' : '<div class="docs-status">Load an STT model first.</div>'}
          </div>
          <div class="docs-section">
            <h3>From file</h3>
            <p class="text-secondary">Upload an audio file (wav, mp3, m4a, ogg, flac, etc.) — decoded via <code>AudioFileLoader</code>.</p>
            <input type="file" id="file-input" accept="audio/*" ${isProcessing || !canRunInference ? 'disabled' : ''} />
          </div>
          <div class="docs-section">
            <h3>Result</h3>
            <div id="transcribe-status" class="docs-status">${isProcessing ? 'Transcribing...' : ''}</div>
            <pre id="transcribe-output" class="docs-pre">${escapeHtml(transcript || '(no transcript yet)')}</pre>
          </div>`
        : `
          <div class="docs-section">
            <h3>Live transcription</h3>
            <p class="text-secondary">
              Once a speech-capable backend is registered against a WASM build
              that includes <code>RAC_WASM_ONNX=ON</code>, this view dispatches
              transcription through <code>RunAnywhere.transcribe(audio, options)</code>.
            </p>
            <ul class="feature-unavailable__list">
              <li><code>RunAnywhere.loadModel(...)</code></li>
              <li><code>RunAnywhere.transcribe(audio, { modelPath })</code></li>
            </ul>
          </div>`}
    </div>
  `;

  container.querySelector('#transcribe-model-btn')?.addEventListener('click', () => {
    openSheet({
      title: 'Select Transcription Model',
      filterCategories: STT_PICKER_FILTER,
    });
  });

  if (supportsProto) {
    container.querySelector('#mode-batch-btn')?.addEventListener('click', () => {
      selectedMode = 'batch';
      renderTranscribe();
    });
    container.querySelector('#mode-live-btn')?.addEventListener('click', () => {
      selectedMode = 'live';
      renderTranscribe();
    });
    container.querySelector('#mic-toggle-btn')?.addEventListener('click', () => {
      void toggleMic();
    });
    container.querySelector('#clear-btn')?.addEventListener('click', () => {
      transcript = '';
      renderTranscribe();
    });
    const fileInput = container.querySelector<HTMLInputElement>('#file-input');
    fileInput?.addEventListener('change', () => {
      const file = fileInput.files?.[0];
      if (file) void transcribeFile(file);
    });
  }
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
    const output = await RunAnywhere.transcribe(samples);
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
 * Live mode — SDK streaming session emitting partial + final results (iOS
 * parity: STTViewModel.swift:377 `RunAnywhere.transcribeStream`; partial
 * folding mirrors STTViewModel.swift:387-408 — non-final partials preview
 * the utterance, the final replaces them).
 *
 * The Web streaming verb is handle-scoped (`RunAnywhere.stt.create()` /
 * `loadModel(handle, ...)` / `transcribeStream(handle, audio)`); the model
 * path comes from the canonical lifecycle via `RunAnywhere.currentModel`.
 */
async function runTranscribeStream(samples: Float32Array): Promise<void> {
  isProcessing = true;
  renderTranscribe();
  setStatus(`Streaming ${(samples.length / 16000).toFixed(2)}s of audio...`);

  let handle: number | null = null;
  try {
    const current = RunAnywhere.currentModel({
      category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
      includeModelMetadata: true,
    });
    const modelPath = current?.resolvedPath || current?.modelId;
    if (!modelPath) {
      setStatus('No STT model loaded.');
      return;
    }

    handle = RunAnywhere.stt.create();
    RunAnywhere.stt.loadModel(handle, modelPath, current?.modelId);

    transcript = '';
    for await (const partial of RunAnywhere.transcribeStream(handle, samples, undefined)) {
      const text = partial.text.trim();
      if (partial.isFinal) {
        // Stream errors surface as a terminal partial carrying the failure
        // text (iOS parity: STTViewModel.swift:391-396).
        if (text.startsWith('STT stream failed')) {
          setStatus(text);
          return;
        }
        transcript = text;
        updateOutput();
      } else if (text) {
        transcript = text;
        updateOutput();
      }
    }
    setStatus('Done.');
  } catch (err) {
    setStatus(`Transcribe failed: ${formatError(err)}`);
  } finally {
    if (handle != null) RunAnywhere.stt.destroy(handle);
    isProcessing = false;
    renderTranscribe();
  }
}

function updateOutput(): void {
  const pre = container.querySelector<HTMLPreElement>('#transcribe-output');
  if (pre) pre.textContent = transcript || '(no transcript yet)';
}

function setStatus(text: string): void {
  const banner = container.querySelector<HTMLDivElement>('#transcribe-status');
  if (banner) banner.textContent = text;
}
