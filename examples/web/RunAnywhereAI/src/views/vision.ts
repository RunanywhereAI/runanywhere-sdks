/**
 * Vision Tab — VLM camera description over the canonical streaming facade.
 *
 * Mirrors iOS VLMViewModel (Features/Vision/VLMViewModel.swift):
 *
 *   1. User downloads + loads any multimodal model via the shared model
 *      selection sheet (`RunAnywhere.downloadModel` + `loadModel`). Loading a
 *      multimodal model syncs the Web vision-language provider inside the
 *      SDK — no app-side bridging.
 *   2. User starts the camera — `VideoCapture` attaches its `<video>` to
 *      the preview container.
 *   3. User clicks "Capture & analyze" — the latest frame streams through
 *      `RunAnywhere.processImageStream(image, options)`, rendering TOKEN
 *      events as they arrive (iOS parity: VLMViewModel.swift:148-194
 *      consumeVLMStream/describeCurrentFrame), with cancel support.
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  VLMModelFamily,
  VLMStreamEventKind,
  vlmImageFromRawRGB,
  type VLMGenerationOptions,
} from '@runanywhere/web';
import { VideoCapture } from '@runanywhere/web/browser';
import {
  onModelStateChange,
  openSheet,
} from '../components/model-selection';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const VLM_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_MULTIMODAL,
  ModelCategory.MODEL_CATEGORY_VISION,
];

const DEFAULT_PROMPT = 'Describe what you see in this image.';
const CAPTURE_DIMENSION = 384;

let container: HTMLElement;
let camera: VideoCapture | null = null;
let latestFrame: { rgbPixels: Uint8Array; width: number; height: number } | null = null;
let lastResult: string | null = null;
let status = '';
let isBusy = false;
let cancelAnalyze: (() => void) | null = null;
let unsubscribeState: (() => void) | null = null;

export function initVisionTab(el: HTMLElement): TabLifecycle {
  container = el;

  renderView();

  // Re-render when the shared model state changes so the "Load model"
  // button reflects real state without manual refresh.
  unsubscribeState = onModelStateChange(() => renderView());

  // Tear down the model-state subscription if the panel element ever
  // detaches (e.g. a full app-shell re-render).
  const rootParent = container.parentElement;
  if (typeof MutationObserver !== 'undefined' && rootParent) {
    const disposeObserver = new MutationObserver(() => {
      if (!container.isConnected) {
        disposeObserver.disconnect();
        unsubscribeState?.();
        unsubscribeState = null;
      }
    });
    disposeObserver.observe(rootParent, { childList: true });
  }

  return {
    onActivate: () => {
      renderView();
    },
    onDeactivate: () => {
      cancelAnalyze?.();
      stopCamera();
    },
  };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderView(): void {
  const modelLoaded = isVLMModelLoaded();
  const captureReady = camera?.isCapturing ?? false;
  const canAnalyze = modelLoaded && captureReady && !isBusy;

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Vision</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="vision-model-btn">
          ${modelLoaded ? 'Change Model' : 'Load Vision Model'}
        </button>
      </div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Status</h3>
        <ul class="feature-unavailable__list">
          <li><code>VLM model loaded</code>: <strong>${modelLoaded ? 'yes' : 'no'}</strong></li>
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
          Streams <code>RunAnywhere.processImageStream(image, options)</code>
          on the last captured frame, rendering tokens as they arrive.
        </p>
        <label class="form-label" for="vision-prompt">Prompt</label>
        <textarea id="vision-prompt" class="chat-input" rows="2"
          ${isBusy ? 'disabled' : ''}
          placeholder="What's in this image?">${escapeHtml(DEFAULT_PROMPT)}</textarea>
        <div class="toolbar-actions">
          <button class="btn btn-primary" id="vision-analyze-btn" ${canAnalyze ? '' : 'disabled'}>
            ${isBusy ? 'Analyzing…' : 'Capture & analyze'}
          </button>
          <button class="btn btn-secondary" id="vision-cancel-btn" ${isBusy ? '' : 'disabled'}>
            Cancel
          </button>
        </div>
        <div id="vision-status" class="docs-status">${escapeHtml(status)}</div>
        <pre id="vision-output" class="docs-pre">${escapeHtml(lastResult ?? '(no response yet)')}</pre>
      </div>
    </div>
  `;

  reattachCameraPreview();

  container
    .querySelector('#vision-model-btn')!
    .addEventListener('click', () =>
      openSheet({
        title: 'Select Vision Model',
        filterCategories: VLM_PICKER_FILTER,
      }),
    );
  container
    .querySelector('#vision-camera-btn')!
    .addEventListener('click', () => void toggleCamera());
  container
    .querySelector('#vision-capture-btn')!
    .addEventListener('click', () => captureFrame());
  container
    .querySelector('#vision-analyze-btn')!
    .addEventListener('click', () => void onAnalyze());
  container
    .querySelector('#vision-cancel-btn')!
    .addEventListener('click', () => cancelAnalyze?.());
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
    setStatus(`Camera error: ${formatError(err)}`);
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

  // Gate on the lifecycle's loaded multimodal model — iOS parity:
  // VLMViewModel.swift:58-62 checkModelStatus() (currentModel(.multimodal)).
  if (!isVLMModelLoaded()) {
    setStatus(
      'No VLM model is loaded. Load a vision model from the model picker, then re-run Analyze.',
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

  const image = vlmImageFromRawRGB(frame.rgbPixels, frame.width, frame.height);

  const options: VLMGenerationOptions = {
    prompt,
    maxTokens: 200,
    temperature: 0.7,
    topP: 0.9,
    topK: 40,
    stopSequences: [],
    streamingEnabled: true,
    systemPrompt: undefined,
    maxImageSize: CAPTURE_DIMENSION,
    nThreads: 0,
    useGpu: false,
    modelFamily: VLMModelFamily.VLM_MODEL_FAMILY_UNSPECIFIED,
    customChatTemplate: undefined,
    imageMarkerOverride: undefined,
    seed: 0,
    repetitionPenalty: 1.1,
    minP: 0.05,
    emitImageEmbeddings: false,
  };

  // Cancel maps to the SDK's native cancel verb — iOS parity:
  // VLMViewModel.swift:244-246 (`RunAnywhere.cancelVLMGeneration()`).
  cancelAnalyze = () => {
    void RunAnywhere.visionLanguage.cancelVLMGeneration();
  };

  isBusy = true;
  setStatus('Running VLM inference…');
  lastResult = '';
  renderView();

  try {
    // Typed stream: STARTED → TOKEN* → terminal COMPLETED/ERROR — iOS parity:
    // VLMViewModel.swift:148-169 consumeVLMStream.
    const stream = await RunAnywhere.visionLanguage.processImageStream(image, options);
    for await (const event of stream) {
      switch (event.kind) {
        case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN:
          if (event.token) {
            lastResult = (lastResult ?? '') + event.token;
            updateOutput(lastResult);
          }
          break;
        case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED: {
          const result = event.result;
          const tokLine = result && result.tokensPerSecond > 0
            ? ` — ${result.completionTokens} tokens in ${Math.round(result.processingTimeMs)}ms (${result.tokensPerSecond.toFixed(1)} tok/s)`
            : '';
          setStatus(`Done${tokLine}.`);
          break;
        }
        case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_ERROR:
          throw new Error(event.errorMessage || 'VLM stream failed');
        default:
          break;
      }
    }
    if (!lastResult) lastResult = '(empty response)';
  } catch (err) {
    setStatus(`VLM inference failed: ${formatError(err)}`);
  } finally {
    cancelAnalyze = null;
    isBusy = false;
    renderView();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * True when the C++ lifecycle reports a loaded MULTIMODAL (or VISION) model —
 * iOS parity: VLMViewModel.swift:58-62 (currentModel with category filter).
 * No model-id allowlist: any loaded vision-capable model enables Analyze.
 */
function isVLMModelLoaded(): boolean {
  try {
    for (const category of VLM_PICKER_FILTER) {
      const current = RunAnywhere.currentModel({
        category,
        includeModelMetadata: false,
      });
      if (current?.found || current?.modelId) return true;
    }
    return false;
  } catch {
    return false;
  }
}

function setStatus(text: string): void {
  status = text;
  const banner = container.querySelector<HTMLDivElement>('#vision-status');
  if (banner) banner.textContent = text;
}

function updateOutput(text: string): void {
  const output = container.querySelector<HTMLPreElement>('#vision-output');
  if (output) output.textContent = text;
}

