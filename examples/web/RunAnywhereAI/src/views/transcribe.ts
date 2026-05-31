/**
 * Transcribe Tab — V2 canonical proto-byte STT.
 *
 * Once `ONNX.register()` resolves, the public surface in `@runanywhere/web`
 * (`RunAnywhere.stt.*`) flows through the proto-byte
 * STT adapter into the WASM module. This view supports two input paths:
 *  1. Microphone capture via `AudioCapture` (push-to-talk style).
 *  2. File picker via `AudioFileLoader`.
 *
 * Both paths require a loaded STT model. When the WASM module isn't built
 * with `RAC_WASM_ONNX=ON` the STT adapter throws `BackendNotAvailable`; the
 * view surfaces the error inline rather than rendering a blank placeholder
 * once the ONNX backend has been registered.
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  isSDKException,
  type STTOutput,
} from '@runanywhere/web';
import {
  AudioCapture,
  AudioFileLoader,
} from '@runanywhere/web/browser';
import { ONNX } from '@runanywhere/web-onnx';
import {
  ensureCatalogRegistered,
  findLoadedModelForCategory,
  onModelStateChange,
  openSheet,
} from '../components/model-selection';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const STT_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
];

let container: HTMLElement;
let unmounted = false;
let audioCapture: AudioCapture | null = null;
let isCapturing = false;
let isProcessing = false;
let lastResult: STTOutput | null = null;
let unsubscribeState: (() => void) | null = null;

export function initTranscribeTab(el: HTMLElement): TabLifecycle {
  container = el;
  unmounted = false;
  ensureCatalogRegistered();
  renderTranscribe();
  unsubscribeState = onModelStateChange(() => {
    if (!unmounted) renderTranscribe();
  });
  return {
    // app.ts fires onDeactivate on every tab switch (not only on panel
    // teardown). Treat the flag as a "currently inactive" guard for
    // in-flight async renders and reset it on re-activation so a returning
    // user doesn't see stale microphone / processing state or skipped
    // post-ONNX-register re-renders.
    onActivate: () => {
      unmounted = false;
      ensureCatalogRegistered();
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

interface TranscribeStatus {
  registered: boolean;
  supportsProto: boolean;
}

function inspectStatus(): TranscribeStatus {
  const registered = ONNX.isRegistered;
  const supportsProto = RunAnywhere.stt.supportsProtoSTT();
  return { registered, supportsProto };
}

function renderTranscribe(): void {
  const status = inspectStatus();
  const transcript = lastResult?.text ?? '';
  const showLive = status.registered && status.supportsProto;
  const loadedModel = findLoadedModelForCategory(
    ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  );
  const modelLabel = loadedModel?.name ?? 'Select STT Model';
  const canRunInference = showLive && Boolean(loadedModel);

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Transcribe</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="transcribe-model-btn">${escapeHtml(modelLabel)}</button>
        <button class="btn btn-secondary" id="onnx-register-btn">${
          status.registered ? 'Re-register ONNX' : 'Register ONNX backend'
        }</button>
      </div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Backend status</h3>
        <ul class="feature-unavailable__list">
          <li><code>ONNX.isRegistered</code>: <strong>${
            status.registered ? 'yes' : 'no'
          }</strong></li>
          <li><code>RunAnywhere.stt.supportsProtoSTT()</code>: <strong>${
            status.supportsProto ? 'yes' : 'no'
          }</strong></li>
          <li><code>STT model loaded</code>: <strong>${loadedModel ? escapeHtml(loadedModel.id) : 'no'}</strong></li>
        </ul>
        <div id="onnx-register-status" class="docs-status"></div>
      </div>

      ${showLive
        ? `
          <div class="docs-section">
            <h3>Microphone</h3>
            <p class="text-secondary">Capture audio from your microphone, then transcribe it through <code>RunAnywhere.transcribe(...)</code>.</p>
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
              Once the ONNX backend is registered against a WASM build that
              includes <code>RAC_WASM_ONNX=ON</code>, this view dispatches
              transcription through <code>RunAnywhere.transcribe(audio, options)</code>.
            </p>
            <ul class="feature-unavailable__list">
              <li><code>RunAnywhere.loadModel(...)</code></li>
              <li><code>RunAnywhere.transcribe(audio, { modelPath })</code></li>
            </ul>
          </div>`}
    </div>
  `;

  container
    .querySelector('#onnx-register-btn')!
    .addEventListener('click', () => void registerOnnx());

  container.querySelector('#transcribe-model-btn')?.addEventListener('click', () => {
    openSheet({
      title: 'Select Transcription Model',
      filterCategories: STT_PICKER_FILTER,
    });
  });

  if (showLive) {
    container.querySelector('#mic-toggle-btn')?.addEventListener('click', () => {
      void toggleMic();
    });
    container.querySelector('#clear-btn')?.addEventListener('click', () => {
      lastResult = null;
      renderTranscribe();
    });
    const fileInput = container.querySelector<HTMLInputElement>('#file-input');
    fileInput?.addEventListener('change', () => {
      const file = fileInput.files?.[0];
      if (file) void transcribeFile(file);
    });
  }
}

async function registerOnnx(): Promise<void> {
  const banner = container.querySelector<HTMLDivElement>('#onnx-register-status');
  if (!banner) return;
  banner.textContent = 'Registering ONNX backend...';
  try {
    await ONNX.register();
    if (unmounted) return;
    banner.textContent = 'ONNX backend registered.';
    renderTranscribe();
  } catch (err) {
    banner.textContent = `Failed to register ONNX backend: ${formatErr(err)}`;
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
    renderTranscribe();
  } catch (err) {
    setStatus(`Microphone error: ${formatErr(err)}`);
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
  await runTranscribe(samples);
}

async function transcribeFile(file: File): Promise<void> {
  isProcessing = true;
  renderTranscribe();
  try {
    const decoded = await AudioFileLoader.toFloat32Array(file, 16000);
    await runTranscribe(decoded.samples);
  } catch (err) {
    setStatus(`Failed to decode file: ${formatErr(err)}`);
  } finally {
    isProcessing = false;
    renderTranscribe();
  }
}

async function runTranscribe(samples: Float32Array): Promise<void> {
  isProcessing = true;
  renderTranscribe();
  setStatus(`Transcribing ${(samples.length / 16000).toFixed(2)}s of audio...`);
  try {
    lastResult = await RunAnywhere.transcribe(samples);
    setStatus('Done.');
  } catch (err) {
    setStatus(`Transcribe failed: ${formatErr(err)}`);
  } finally {
    isProcessing = false;
    renderTranscribe();
  }
}

function setStatus(text: string): void {
  const banner = container.querySelector<HTMLDivElement>('#transcribe-status');
  if (banner) banner.textContent = text;
}

function formatErr(err: unknown): string {
  if (isSDKException(err)) return err.message;
  return formatError(err);
}
