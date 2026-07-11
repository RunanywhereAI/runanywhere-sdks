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
// Data URL preview for an image loaded from disk (null when the source is the
// live camera). Lets the preview survive innerHTML re-renders without a camera.
let loadedPreviewUrl: string | null = null;
let lastResult: string | null = null;
let status = '';
let isBusy = false;
let cancelAnalyze: (() => void) | null = null;
let unsubscribeState: (() => void) | null = null;
let cameraStartGeneration = 0;
let cameraStartPending = false;

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
  const canAnalyze = modelLoaded && (captureReady || latestFrame !== null) && !isBusy;

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
          <button class="btn btn-secondary" id="vision-load-image-btn" ${isBusy ? 'disabled' : ''}>
            Load image…
          </button>
          <input type="file" id="vision-image-input" accept="image/*" hidden />
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
  const imageInput = container.querySelector<HTMLInputElement>('#vision-image-input')!;
  container
    .querySelector('#vision-load-image-btn')!
    .addEventListener('click', () => imageInput.click());
  imageInput.addEventListener('change', () => void onImageFileSelected(imageInput));
  container
    .querySelector('#vision-analyze-btn')!
    .addEventListener('click', () => void onAnalyze());
  container
    .querySelector('#vision-cancel-btn')!
    .addEventListener('click', () => cancelAnalyze?.());
}

function reattachCameraPreview(): void {
  const host = container.querySelector<HTMLElement>('#vision-preview');
  if (!host) return;
  host.innerHTML = '';
  if (camera?.isCapturing) {
    host.appendChild(camera.videoElement);
    return;
  }
  if (loadedPreviewUrl) {
    const img = document.createElement('img');
    img.src = loadedPreviewUrl;
    img.alt = 'Loaded image';
    img.style.maxWidth = '100%';
    img.style.borderRadius = '8px';
    host.appendChild(img);
  }
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
  const generation = ++cameraStartGeneration;
  const candidate = new VideoCapture({
    facingMode: 'environment',
    idealWidth: 640,
    idealHeight: 480,
  });
  cameraStartPending = true;
  isBusy = true;
  setStatus('Requesting camera access…');
  renderView();
  try {
    await candidate.start();
    if (generation !== cameraStartGeneration) {
      candidate.stop();
      return;
    }
    camera = candidate;
    setStatus('Camera ready.');
  } catch (err) {
    candidate.stop();
    if (generation !== cameraStartGeneration) return;
    setStatus(`Camera error: ${formatError(err)}`);
    camera = null;
  } finally {
    if (generation === cameraStartGeneration) {
      cameraStartPending = false;
      isBusy = false;
      renderView();
    }
  }
}

function stopCamera(): void {
  cameraStartGeneration += 1;
  camera?.stop();
  camera = null;
  latestFrame = null;
  if (cameraStartPending) {
    cameraStartPending = false;
    isBusy = false;
  }
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
  loadedPreviewUrl = null;
  setStatus(`Captured ${frame.width}×${frame.height} frame.`);
  renderView();
}

// ---------------------------------------------------------------------------
// Image from disk
// ---------------------------------------------------------------------------

async function onImageFileSelected(input: HTMLInputElement): Promise<void> {
  const file = input.files?.[0];
  // Reset so re-selecting the same file fires `change` again.
  input.value = '';
  if (!file) return;

  isBusy = true;
  setStatus('Loading image…');
  renderView();
  try {
    const decoded = await decodeImageToRgbFrame(file, CAPTURE_DIMENSION);
    // A loaded image is an alternative frame source — drop the live camera so
    // the preview and analysis operate on the picked image.
    stopCamera();
    latestFrame = {
      rgbPixels: decoded.rgbPixels,
      width: decoded.width,
      height: decoded.height,
    };
    loadedPreviewUrl = decoded.previewUrl;
    setStatus(`Loaded ${decoded.width}×${decoded.height} image from ${file.name}.`);
  } catch (err) {
    setStatus(`Failed to load image: ${formatError(err)}`);
  } finally {
    isBusy = false;
    renderView();
  }
}

/**
 * Decode an image file into the same raw-RGB frame shape the camera produces:
 * aspect-preserving downscale so the longest side is `maxDim`, alpha stripped.
 */
async function decodeImageToRgbFrame(
  file: File,
  maxDim: number,
): Promise<{ rgbPixels: Uint8Array; width: number; height: number; previewUrl: string }> {
  const objectUrl = URL.createObjectURL(file);
  try {
    const img = await loadImageElement(objectUrl);
    const longest = Math.max(img.naturalWidth, img.naturalHeight) || 1;
    const scale = Math.min(1, maxDim / longest);
    const width = Math.max(1, Math.round(img.naturalWidth * scale));
    const height = Math.max(1, Math.round(img.naturalHeight * scale));

    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    if (!ctx) throw new Error('2D canvas context unavailable');
    ctx.drawImage(img, 0, 0, width, height);

    const { data } = ctx.getImageData(0, 0, width, height); // RGBA
    const rgbPixels = new Uint8Array(width * height * 3);
    for (let src = 0, dst = 0; src < data.length; src += 4, dst += 3) {
      rgbPixels[dst] = data[src];
      rgbPixels[dst + 1] = data[src + 1];
      rgbPixels[dst + 2] = data[src + 2];
    }
    return { rgbPixels, width, height, previewUrl: canvas.toDataURL('image/png') };
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}

function loadImageElement(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('Could not decode the selected image'));
    img.src = src;
  });
}

// ---------------------------------------------------------------------------
// Analyze
// ---------------------------------------------------------------------------

async function onAnalyze(): Promise<void> {
  // Gate on the lifecycle's loaded multimodal model — iOS parity:
  // VLMViewModel.swift:58-62 checkModelStatus() (currentModel(.multimodal)).
  if (!isVLMModelLoaded()) {
    setStatus(
      'No VLM model is loaded. Load a vision model from the model picker, then re-run Analyze.',
    );
    renderView();
    return;
  }

  // Frame source: an already-captured/loaded frame, or a fresh camera grab.
  const frame =
    latestFrame ?? (camera?.isCapturing ? camera.captureFrame(CAPTURE_DIMENSION) : null);
  if (!frame) {
    setStatus('Capture a camera frame or load an image first.');
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
  let cancellationRequested = false;
  cancelAnalyze = () => {
    cancellationRequested = true;
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
    if (cancellationRequested) {
      setStatus('Cancelled.');
    } else if (!lastResult) {
      lastResult = '(empty response)';
    }
  } catch (err) {
    setStatus(cancellationRequested
      ? 'Cancelled.'
      : `VLM inference failed: ${formatError(err)}`);
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
