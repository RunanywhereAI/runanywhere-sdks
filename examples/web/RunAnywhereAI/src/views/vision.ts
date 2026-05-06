/**
 * Vision Tab — V2 canonical VLM camera description.
 *
 * Re-landed against the existing `VLMWorkerBridge` (off-main-thread WASM
 * runtime) and the core `VideoCapture` helper. Flow is:
 *
 *   1. User downloads + loads a VLM (e.g. SmolVLM 500M) via the shared
 *      model selection sheet (download + `modelLifecycle.load`).
 *   2. User starts the camera — `VideoCapture` attaches its `<video>` to
 *      the preview container.
 *   3. User clicks "Capture & analyze" — the latest frame is extracted as
 *      RGB pixels, wrapped in a `VLMImage` proto message, and dispatched
 *      through `VLMWorkerBridge.shared.process(image, options)`. The
 *      worker decodes on its side, calls `_rac_vlm_process_proto`, and
 *      returns the encoded `VLMResult`.
 *
 * The worker-side `loadModel` wiring (raw GGUF + mmproj bytes transferred
 * zero-copy into the worker's MEMFS) is still TBD — until the backend
 * package installs it, `VLMWorkerBridge.shared.isModelLoaded` stays false
 * and the view surfaces the situation inline rather than rendering a blank
 * placeholder.
 */

import type { TabLifecycle } from '../app';
import {
  RunAnywhere,
  VideoCapture,
  VLMImageFormat,
  isSDKException,
  type VLMGenerationOptions,
  type VLMImage,
  type VLMResult,
} from '@runanywhere/web';
import { VLMWorkerBridge } from '@runanywhere/web-llamacpp';
import {
  ensureCatalogRegistered,
  onModelStateChange,
  openSheet,
} from '../components/model-selection';

const VLM_MODEL_ID = 'smolvlm-500m-instruct-q8_0';
const DEFAULT_PROMPT = 'Describe what you see in this image.';
const CAPTURE_DIMENSION = 384;

let container: HTMLElement;
let camera: VideoCapture | null = null;
let latestFrame: { rgbPixels: Uint8Array; width: number; height: number } | null = null;
let lastResult: string | null = null;
let status = '';
let isBusy = false;
let unsubscribeState: (() => void) | null = null;

export function initVisionTab(el: HTMLElement): TabLifecycle {
  container = el;

  ensureCatalogRegistered();
  renderView();

  // Re-render when the shared model state changes so the "Load model"
  // button reflects real state without manual refresh.
  unsubscribeState = onModelStateChange(() => renderView());

  return {
    onActivate: () => {
      ensureCatalogRegistered();
      renderView();
    },
    onDeactivate: () => {
      stopCamera();
    },
  };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderView(): void {
  const bridge = VLMWorkerBridge.shared;
  const modelLoaded = isVLMModelLoaded();
  const workerLoaded = bridge.isModelLoaded;
  const captureReady = camera?.isCapturing ?? false;
  const canAnalyze = workerLoaded && captureReady && !isBusy;

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Vision</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="vision-model-btn">
          ${modelLoaded ? 'Change Model' : 'Load SmolVLM'}
        </button>
      </div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Backend status</h3>
        <ul class="feature-unavailable__list">
          <li><code>VLM model loaded</code>: <strong>${modelLoaded ? 'yes' : 'no'}</strong></li>
          <li><code>VLMWorkerBridge.isInitialized</code>: <strong>${bridge.isInitialized ? 'yes' : 'no'}</strong></li>
          <li><code>VLMWorkerBridge.isModelLoaded</code>: <strong>${workerLoaded ? 'yes' : 'no'}</strong></li>
          <li><code>camera.isCapturing</code>: <strong>${captureReady ? 'yes' : 'no'}</strong></li>
        </ul>
      </div>

      <div class="docs-section">
        <h3>Camera</h3>
        <p class="text-secondary">Attach your webcam and capture frames as RGB pixels for VLM inference.</p>
        <div class="toolbar-actions">
          <button class="btn btn-primary" id="vision-camera-btn" ${isBusy ? 'disabled' : ''}>
            ${captureReady ? 'Stop camera' : 'Start camera'}
          </button>
          <button class="btn btn-secondary" id="vision-capture-btn" ${captureReady && !isBusy ? '' : 'disabled'}>
            Capture frame
          </button>
        </div>
        <div id="vision-preview" class="vision-preview"></div>
        <div id="vision-frame-meta" class="docs-status">${frameMetaLabel()}</div>
      </div>

      <div class="docs-section">
        <h3>Analyze</h3>
        <p class="text-secondary">
          Runs <code>VLMWorkerBridge.shared.process(image, options)</code> on the last
          captured frame. The worker decodes the proto message and calls
          <code>_rac_vlm_process_proto</code> off-thread.
        </p>
        <label class="form-label" for="vision-prompt">Prompt</label>
        <textarea id="vision-prompt" class="chat-input" rows="2"
          ${isBusy ? 'disabled' : ''}
          placeholder="What's in this image?">${escape(DEFAULT_PROMPT)}</textarea>
        <div class="toolbar-actions">
          <button class="btn btn-primary" id="vision-analyze-btn" ${canAnalyze ? '' : 'disabled'}>
            ${isBusy ? 'Analyzing…' : 'Capture & analyze'}
          </button>
        </div>
        <div id="vision-status" class="docs-status">${escape(status)}</div>
        <pre id="vision-output" class="docs-pre">${escape(lastResult ?? '(no response yet)')}</pre>
      </div>
    </div>
  `;

  reattachCameraPreview();

  container
    .querySelector('#vision-model-btn')!
    .addEventListener('click', () => openSheet());
  container
    .querySelector('#vision-camera-btn')!
    .addEventListener('click', () => void toggleCamera());
  container
    .querySelector('#vision-capture-btn')!
    .addEventListener('click', () => captureFrame());
  container
    .querySelector('#vision-analyze-btn')!
    .addEventListener('click', () => void onAnalyze());
}

function reattachCameraPreview(): void {
  const host = container.querySelector<HTMLElement>('#vision-preview');
  if (!host || !camera) return;
  host.innerHTML = '';
  host.appendChild(camera.videoElement);
}

function frameMetaLabel(): string {
  if (!latestFrame) return 'No frame captured yet.';
  return `Last frame: ${latestFrame.width}×${latestFrame.height} RGB (${latestFrame.rgbPixels.byteLength.toLocaleString()} bytes)`;
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

async function toggleCamera(): Promise<void> {
  if (camera?.isCapturing) {
    stopCamera();
    renderView();
    return;
  }
  await startCamera();
}

async function startCamera(): Promise<void> {
  camera = camera ?? new VideoCapture({
    facingMode: 'environment',
    idealWidth: 640,
    idealHeight: 480,
  });
  isBusy = true;
  setStatus('Requesting camera access…');
  renderView();
  try {
    await camera.start();
    setStatus('Camera ready.');
  } catch (err) {
    setStatus(`Camera error: ${formatErr(err)}`);
    camera = null;
  } finally {
    isBusy = false;
    renderView();
  }
}

function stopCamera(): void {
  camera?.stop();
  camera = null;
  latestFrame = null;
}

function captureFrame(): void {
  if (!camera?.isCapturing) return;
  const frame = camera.captureFrame(CAPTURE_DIMENSION);
  if (!frame) {
    setStatus('Failed to capture frame.');
    renderView();
    return;
  }
  latestFrame = frame;
  setStatus(`Captured ${frame.width}×${frame.height} frame.`);
  renderView();
}

// ---------------------------------------------------------------------------
// Analyze
// ---------------------------------------------------------------------------

async function onAnalyze(): Promise<void> {
  if (!camera?.isCapturing) {
    setStatus('Start the camera first.');
    renderView();
    return;
  }

  const bridge = VLMWorkerBridge.shared;
  if (!bridge.isModelLoaded) {
    setStatus(
      'The VLM Worker has no model loaded. Load SmolVLM, then re-run Analyze — ' +
      'worker-side model plumbing lands once the backend registers a VLM loader.',
    );
    renderView();
    return;
  }

  const frame = latestFrame ?? camera.captureFrame(CAPTURE_DIMENSION);
  if (!frame) {
    setStatus('Failed to capture a frame for analysis.');
    renderView();
    return;
  }
  latestFrame = frame;

  const promptEl = container.querySelector<HTMLTextAreaElement>('#vision-prompt');
  const prompt = (promptEl?.value ?? DEFAULT_PROMPT).trim() || DEFAULT_PROMPT;

  const image: VLMImage = {
    filePath: undefined,
    encoded: undefined,
    rawRgb: frame.rgbPixels,
    base64: undefined,
    width: frame.width,
    height: frame.height,
    format: VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB,
    mediaType: 'image/rgb',
    name: 'camera-frame',
    sizeBytes: frame.rgbPixels.byteLength,
    metadata: {},
  };

  const options: VLMGenerationOptions = {
    prompt,
    maxTokens: 128,
    temperature: 0.7,
    topP: 0.9,
    topK: 40,
    stopSequences: [],
    streamingEnabled: false,
    systemPrompt: undefined,
    maxImageSize: CAPTURE_DIMENSION,
    nThreads: 0,
    useGpu: false,
    modelFamily: 0,
    customChatTemplate: undefined,
    imageMarkerOverride: undefined,
    seed: 0,
    repetitionPenalty: 1.1,
    minP: 0.05,
    emitImageEmbeddings: false,
  };

  isBusy = true;
  setStatus('Running VLM inference off-thread…');
  lastResult = null;
  renderView();

  try {
    const result: VLMResult = await bridge.process(image, options);
    lastResult = result.text || '(empty response)';
    const tokLine =
      result.tokensPerSecond > 0
        ? ` — ${result.completionTokens} tokens in ${Math.round(result.processingTimeMs)}ms (${result.tokensPerSecond.toFixed(1)} tok/s)`
        : '';
    setStatus(`Done${tokLine}.`);
  } catch (err) {
    setStatus(`VLM inference failed: ${formatErr(err)}`);
  } finally {
    isBusy = false;
    renderView();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isVLMModelLoaded(): boolean {
  try {
    const current = RunAnywhere.modelLifecycle.currentModel();
    return current?.modelId === VLM_MODEL_ID;
  } catch {
    return false;
  }
}

function setStatus(text: string): void {
  status = text;
  const banner = container.querySelector<HTMLDivElement>('#vision-status');
  if (banner) banner.textContent = text;
}

function formatErr(err: unknown): string {
  if (isSDKException(err)) return err.message;
  if (err instanceof Error) return err.message;
  return String(err);
}

function escape(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// Dispose subscription on full panel teardown (mirrors chat.ts pattern).
const disposeObserver =
  typeof MutationObserver !== 'undefined'
    ? new MutationObserver(() => {
        if (container && !container.isConnected) {
          disposeObserver?.disconnect();
          unsubscribeState?.();
          unsubscribeState = null;
        }
      })
    : null;
if (disposeObserver && typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', () => {
    if (container?.parentElement) {
      disposeObserver.observe(container.parentElement, { childList: true });
    }
  });
}
