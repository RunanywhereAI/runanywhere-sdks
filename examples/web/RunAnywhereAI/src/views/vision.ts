/**
 * Vision Tab — V2 canonical VLM camera description.
 *
 * Re-landed against the Swift-shaped `RunAnywhere.processImage(...)` facade
 * and the core `VideoCapture` helper. Flow is:
 *
 *   1. User downloads + loads a VLM (e.g. SmolVLM2 256M) via the shared
 *      model selection sheet (download + `modelLifecycle.load`).
 *   2. User starts the camera — `VideoCapture` attaches its `<video>` to
 *      the preview container.
 *   3. User clicks "Capture & analyze" — the latest frame is extracted as
 *      RGB pixels, wrapped in a `VLMImage` proto message, and dispatched
 *      through `RunAnywhere.processImage(image, options)`.
 *
 * The Web provider reads C++ lifecycle-resolved primary GGUF and mmproj
 * artifacts from the active WASM filesystem.
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  SDKErrorCode,
  VLMImageFormat,
  VLMModelFamily,
  isSDKException,
  type VLMGenerationOptions,
  type VLMImage,
  type VLMResult,
} from '@runanywhere/web';
import { VideoCapture } from '@runanywhere/web/browser';
import {
  ensureCatalogRegistered,
  onModelStateChange,
  openSheet,
} from '../components/model-selection';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const VLM_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_MULTIMODAL,
  ModelCategory.MODEL_CATEGORY_VISION,
];

const VLM_MODEL_ID = 'smolvlm2-256m-video-instruct-q8_0';
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
  void syncVisionLanguageProvider();
  renderView();

  // Re-render when the shared model state changes so the "Load model"
  // button reflects real state without manual refresh. Also bridge the
  // C++ lifecycle current-model into the Web VLM provider; without this
  // call, RunAnywhere.processImage throws "No VLM model has been loaded
  // through RunAnywhere.loadModel()." even after a successful load.
  unsubscribeState = onModelStateChange(() => {
    void syncVisionLanguageProvider();
    renderView();
  });

  return {
    onActivate: () => {
      ensureCatalogRegistered();
      void syncVisionLanguageProvider();
      renderView();
    },
    onDeactivate: () => {
      stopCamera();
    },
  };
}

/**
 * Mirror the C++ lifecycle's current VLM into the Web vision-language
 * provider's private _modelLoaded flag. The shared model picker only loads
 * the model into the C++ lifecycle; without this bridge call, the Web
 * provider stays in its own unloaded state and rejects processImage even
 * though the lifecycle reports a loaded multimodal model. Symmetric
 * unloadModel keeps the provider state in sync when the active VLM is
 * unloaded or replaced through the picker.
 */
async function syncVisionLanguageProvider(): Promise<void> {
  try {
    if (isVLMModelLoaded()) {
      if (!RunAnywhere.visionLanguage.isModelLoaded) {
        await RunAnywhere.visionLanguage.loadCurrentModel();
        renderView();
      }
    } else if (RunAnywhere.visionLanguage.isModelLoaded) {
      await RunAnywhere.visionLanguage.unloadModel();
      renderView();
    }
  } catch (err) {
    // Provider not registered yet (LlamaCPP backend missing or still
    // initializing) is expected; surface real failures via status panel
    // so the user can see why Analyze keeps rejecting.
    if (isSDKException(err) && err.code === SDKErrorCode.BackendNotAvailable) return;
    setStatus(`VLM provider sync failed: ${formatErr(err)}`);
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderView(): void {
  const modelLoaded = isVLMModelLoaded();
  const providerLoaded = RunAnywhere.visionLanguage.isModelLoaded;
  const captureReady = camera?.isCapturing ?? false;
  const canAnalyze = modelLoaded && captureReady && !isBusy;

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
          <li><code>RunAnywhere.visionLanguage.isInitialized</code>: <strong>${RunAnywhere.visionLanguage.isInitialized ? 'yes' : 'no'}</strong></li>
          <li><code>RunAnywhere.visionLanguage.isModelLoaded</code>: <strong>${providerLoaded ? 'yes' : 'no'}</strong></li>
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
          Runs <code>RunAnywhere.processImage(image, options)</code> on the last
          captured frame.
        </p>
        <label class="form-label" for="vision-prompt">Prompt</label>
        <textarea id="vision-prompt" class="chat-input" rows="2"
          ${isBusy ? 'disabled' : ''}
          placeholder="What's in this image?">${escapeHtml(DEFAULT_PROMPT)}</textarea>
        <div class="toolbar-actions">
          <button class="btn btn-primary" id="vision-analyze-btn" ${canAnalyze ? '' : 'disabled'}>
            ${isBusy ? 'Analyzing…' : 'Capture & analyze'}
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

  if (!isVLMModelLoaded()) {
    setStatus(
      'No VLM model is loaded. Load SmolVLM from the model picker, then re-run Analyze.',
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
    modelFamily: VLMModelFamily.VLM_MODEL_FAMILY_SMOLVLM,
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
    const result: VLMResult = await RunAnywhere.processImage(image, options);
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
    const current = RunAnywhere.currentModel();
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
  return formatError(err);
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
