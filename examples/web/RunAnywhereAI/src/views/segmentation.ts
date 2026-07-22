/**
 * Segmentation Tab — semantic image segmentation over the canonical
 * `RunAnywhere.segment` facade (SegFormer / ADE20K-class models).
 *
 * The SegFormer weights are user-supplied and gated at the source (HuggingFace
 * gated repo + the existing HF token flow); there is no in-app license
 * acceptance step. This view therefore:
 *
 *   1. Reports the SDK-owned lifecycle state for a loaded
 *      `.semanticSegmentation` model. The SegFormer weights are user-supplied
 *      and uncataloged, so model supply/load is delegated to the SDK's model
 *      management (the shared model sheet) rather than reimplemented here.
 *   2. Accepts a user-picked image, decodes it to tightly-packed RGBA8 pixels,
 *      and runs `RunAnywhere.segment(request)`.
 *   3. Renders the returned diagnostic mask overlaid on the source image and a
 *      per-class pixel summary.
 *
 * All inference and model routing live in the SDK / C++ commons. This view is
 * DOM state + thin facade calls only.
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  SegmentationPixelFormat,
  type SegmentationClassSummary,
  type SegmentationResult,
} from '@runanywhere/web';
import { onModelStateChange, openSheet } from '../components/model-selection';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const SEG_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
];

// Cap the source dimension so a huge photo cannot blow past the SDK's
// 4096-px boundary or stall the browser while decoding to raw pixels.
const MAX_SOURCE_DIMENSION = 1024;

interface LoadedImage {
  /** Tightly-packed RGBA8 pixels (width * height * 4). */
  rgba: Uint8Array;
  width: number;
  height: number;
  previewUrl: string;
}

let container: HTMLElement;
let image: LoadedImage | null = null;
let lastResult: SegmentationResult | null = null;
let status = '';
let isBusy = false;
let unsubscribeState: (() => void) | null = null;

export function initSegmentationTab(el: HTMLElement): TabLifecycle {
  container = el;
  renderView();

  // Re-render when the shared model state changes so the loaded-model line
  // reflects real lifecycle state without a manual refresh.
  unsubscribeState = onModelStateChange(() => renderView());

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
    onActivate: () => renderView(),
  };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderView(): void {
  const modelLoaded = isSegmentationModelLoaded();
  const canRun = modelLoaded && image !== null && !isBusy;

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Segmentation</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="seg-model-btn">
          ${modelLoaded ? 'Change Model' : 'Load Segmentation Model'}
        </button>
      </div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Status</h3>
        <ul class="feature-unavailable__list">
          <li><code>segmentation model loaded</code>: <strong>${modelLoaded ? 'yes' : 'no'}</strong></li>
        </ul>
        <p class="text-secondary">
          SegFormer weights are user-supplied and uncataloged. Supply and load them
          through the SDK's model management (the button above), then return here to run
          <code>RunAnywhere.segment</code>.
        </p>
      </div>

      <div class="docs-section">
        <h3>Image</h3>
        <p class="text-secondary">Pick a photo to segment. It is decoded to tightly-packed RGBA8 pixels for the SDK.</p>
        <div class="toolbar-actions">
          <button class="btn btn-secondary" id="seg-load-image-btn" ${!isBusy ? '' : 'disabled'}>
            Load image…
          </button>
          <input type="file" id="seg-image-input" accept="image/*" hidden />
        </div>
        <div id="seg-preview" class="vision-preview"></div>
        <div id="seg-frame-meta" class="docs-status">${escapeHtml(frameMetaLabel())}</div>
      </div>

      <div class="docs-section">
        <h3>Segment</h3>
        <p class="text-secondary">
          Runs <code>RunAnywhere.segment(request)</code> on the loaded
          <code>.semanticSegmentation</code> model and overlays the returned class mask.
        </p>
        <div class="toolbar-actions">
          <button class="btn btn-primary" id="seg-run-btn" ${canRun ? '' : 'disabled'}>
            ${isBusy ? 'Segmenting…' : 'Run segmentation'}
          </button>
        </div>
        <div id="seg-status" class="docs-status">${escapeHtml(status)}</div>
        <div id="seg-result"></div>
      </div>
    </div>
  `;

  reattachPreview();
  reattachResult();

  container
    .querySelector('#seg-model-btn')!
    .addEventListener('click', () =>
      openSheet({
        title: 'Select Segmentation Model',
        filterCategories: SEG_PICKER_FILTER,
      }),
    );
  const imageInput = container.querySelector<HTMLInputElement>('#seg-image-input')!;
  container
    .querySelector('#seg-load-image-btn')!
    .addEventListener('click', () => imageInput.click());
  imageInput.addEventListener('change', () => void onImageFileSelected(imageInput));
  container
    .querySelector('#seg-run-btn')!
    .addEventListener('click', () => void onRun());
}

function frameMetaLabel(): string {
  if (!image) return 'No image loaded yet.';
  return `Loaded image: ${image.width}×${image.height} RGBA (${image.rgba.byteLength.toLocaleString()} bytes)`;
}

function reattachPreview(): void {
  const host = container.querySelector<HTMLElement>('#seg-preview');
  if (!host) return;
  host.innerHTML = '';
  if (!image) return;
  const img = document.createElement('img');
  img.src = image.previewUrl;
  img.alt = 'Loaded image';
  img.style.maxWidth = '100%';
  img.style.borderRadius = '8px';
  host.appendChild(img);
}

function reattachResult(): void {
  const host = container.querySelector<HTMLElement>('#seg-result');
  if (!host) return;
  host.innerHTML = '';
  if (!lastResult || !image) return;
  host.appendChild(buildOverlay(lastResult, image));
  host.appendChild(buildClassSummary(lastResult));
}

// ---------------------------------------------------------------------------
// Image
// ---------------------------------------------------------------------------

async function onImageFileSelected(input: HTMLInputElement): Promise<void> {
  const file = input.files?.[0];
  input.value = '';
  if (!file) return;

  isBusy = true;
  setStatus('Loading image…');
  renderView();
  try {
    image = await decodeImageToRgba(file, MAX_SOURCE_DIMENSION);
    lastResult = null;
    setStatus(`Loaded ${image.width}×${image.height} image from ${file.name}.`);
  } catch (err) {
    setStatus(`Failed to load image: ${formatError(err)}`);
  } finally {
    isBusy = false;
    renderView();
  }
}

/** Decode an image file into tightly-packed RGBA8 pixels (alpha preserved). */
async function decodeImageToRgba(file: File, maxDim: number): Promise<LoadedImage> {
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

    const { data } = ctx.getImageData(0, 0, width, height); // RGBA, tightly packed
    return {
      rgba: new Uint8Array(data.buffer.slice(0)),
      width,
      height,
      previewUrl: canvas.toDataURL('image/png'),
    };
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
// Segment
// ---------------------------------------------------------------------------

async function onRun(): Promise<void> {
  if (!isSegmentationModelLoaded()) {
    setStatus('No segmentation model is loaded. Load one from the model picker, then re-run.');
    renderView();
    return;
  }
  if (!image) {
    setStatus('Load an image first.');
    renderView();
    return;
  }

  isBusy = true;
  lastResult = null;
  setStatus('Running segmentation…');
  renderView();

  try {
    const result = await RunAnywhere.segment({
      image: {
        data: image.rgba,
        width: image.width,
        height: image.height,
        pixelFormat: SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGBA8,
      },
      options: { includeDiagnosticRgba: true },
    });
    lastResult = result;
    setStatus(
      `Done — ${result.classSummaries.length} classes in ${Math.round(result.processingTimeMs)}ms (${escapeHtml(result.modelId)}).`,
    );
  } catch (err) {
    setStatus(`Segmentation failed: ${formatError(err)}`);
  } finally {
    isBusy = false;
    renderView();
  }
}

// ---------------------------------------------------------------------------
// Result rendering
// ---------------------------------------------------------------------------

/** Composite the diagnostic RGBA mask semi-transparently over the source image. */
function buildOverlay(result: SegmentationResult, source: LoadedImage): HTMLElement {
  const wrap = document.createElement('div');
  wrap.className = 'vision-preview';

  const canvas = document.createElement('canvas');
  canvas.width = result.width;
  canvas.height = result.height;
  canvas.style.maxWidth = '100%';
  canvas.style.borderRadius = '8px';
  const ctx = canvas.getContext('2d');
  if (!ctx) return wrap;

  // Base image.
  const base = document.createElement('img');
  base.src = source.previewUrl;
  base.onload = () => {
    ctx.drawImage(base, 0, 0, result.width, result.height);
    const mask = result.diagnosticRgba;
    if (mask && mask.byteLength === result.width * result.height * 4) {
      // Copy into a fresh ArrayBuffer-backed clamped array: the SDK bytes may
      // be backed by a SharedArrayBuffer (WASM heap), which ImageData rejects.
      const rgba = new Uint8ClampedArray(mask.byteLength);
      rgba.set(mask);
      const maskData = new ImageData(rgba, result.width, result.height);
      const maskCanvas = document.createElement('canvas');
      maskCanvas.width = result.width;
      maskCanvas.height = result.height;
      maskCanvas.getContext('2d')?.putImageData(maskData, 0, 0);
      ctx.globalAlpha = 0.55;
      ctx.drawImage(maskCanvas, 0, 0);
      ctx.globalAlpha = 1;
    }
  };
  wrap.appendChild(canvas);
  return wrap;
}

function buildClassSummary(result: SegmentationResult): HTMLElement {
  const section = document.createElement('div');
  section.className = 'docs-section';

  const heading = document.createElement('h3');
  heading.textContent = 'Classes';
  section.appendChild(heading);

  const list = document.createElement('ul');
  list.className = 'feature-unavailable__list';
  const sorted = [...result.classSummaries].sort(
    (a: SegmentationClassSummary, b: SegmentationClassSummary) => b.pixelCount - a.pixelCount,
  );
  for (const summary of sorted) {
    const item = document.createElement('li');
    const label = summary.label || `class ${summary.classId}`;
    const pct = (summary.fraction * 100).toFixed(1);
    item.innerHTML =
      `<strong>${escapeHtml(label)}</strong> — ${summary.pixelCount.toLocaleString()} px (${pct}%)`;
    list.appendChild(item);
  }
  section.appendChild(list);
  return section;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isSegmentationModelLoaded(): boolean {
  try {
    const current = RunAnywhere.currentModel({
      category: ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION,
      includeModelMetadata: false,
    });
    return Boolean(current?.found || current?.modelId);
  } catch {
    return false;
  }
}

function setStatus(text: string): void {
  status = text;
  const banner = container.querySelector<HTMLDivElement>('#seg-status');
  if (banner) banner.textContent = text;
}
