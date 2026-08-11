/**
 * Segmentation — split an image into labelled regions.
 *
 * SDK: `models.load` + `segmentation.segment(image.rawRgb(...))`. Decode and
 * mask painting stay in the app (see `services/segmentation-mask.ts`).
 */
import { escapeHtml } from '../services/format';
import { selectedModel } from '../services/settings';
import {
  classRgb,
  decodeRawRgb,
  paintClassMask,
} from '../services/segmentation-mask';
import { showError } from '../components/toast';
import type { ViewFactory } from '../shell/app';

export const createSegmentationView: ViewFactory = ({ root }) => {
  let disposed = false;
  let busy = false;
  let file: File | null = null;

  const scroll = document.createElement('div');
  scroll.className = 'ra-view-scroll ra-stack';
  scroll.innerHTML =
    `<section class="ra-card ra-stack">` +
    `<h2 class="ra-section-title">Image</h2>` +
    `<p class="ra-muted">Pick a photo. Pixels stay on this device; the model labels every region.</p>` +
    `<div class="ra-row">` +
    `<input type="file" id="seg-file" accept="image/*" hidden />` +
    `<button type="button" class="ra-btn-secondary" id="seg-pick">Choose image</button>` +
    `<span id="seg-fname" class="ra-muted">No image selected</span>` +
    `</div>` +
    `<button type="button" class="ra-btn-primary" id="seg-go" disabled>Run segmentation</button>` +
    `<div id="seg-status" class="ra-muted"></div>` +
    `</section>` +
    `<section class="ra-stack">` +
    `<canvas id="seg-canvas" class="ra-seg-canvas" style="display:none"></canvas>` +
    `<div id="seg-out"></div>` +
    `</section>`;
  root.append(scroll);

  const fileInput = scroll.querySelector<HTMLInputElement>('#seg-file');
  const pickBtn = scroll.querySelector<HTMLButtonElement>('#seg-pick');
  const goBtn = scroll.querySelector<HTMLButtonElement>('#seg-go');
  const fname = scroll.querySelector<HTMLElement>('#seg-fname');
  const status = scroll.querySelector<HTMLElement>('#seg-status');
  const canvas = scroll.querySelector<HTMLCanvasElement>('#seg-canvas');
  const out = scroll.querySelector<HTMLElement>('#seg-out');
  if (
    fileInput === null ||
    pickBtn === null ||
    goBtn === null ||
    fname === null ||
    status === null ||
    canvas === null ||
    out === null
  ) {
    return {};
  }

  pickBtn.addEventListener('click', () => fileInput.click());
  fileInput.addEventListener('change', () => {
    file = fileInput.files?.[0] ?? null;
    fname.textContent = file?.name ?? 'No image selected';
    goBtn.disabled = file === null || busy;
    out.replaceChildren();
    canvas.style.display = 'none';
  });

  const isDisposed = (): boolean => disposed;

  goBtn.addEventListener('click', () => {
    const image = file;
    if (image === null || busy) return;
    void (async () => {
      busy = true;
      goBtn.disabled = true;
      status.textContent = 'Preparing…';
      out.replaceChildren();
      try {
        const modelId = selectedModel('segmentation');
        await window.runanywhere.models.load(modelId);
        if (isDisposed()) return;
        status.textContent = 'Segmenting…';
        const { rgb, width, height } = await decodeRawRgb(image);
        const result = await window.runanywhere.segmentation.segment(
          window.runanywhere.image.rawRgb(rgb, width, height),
        );
        if (isDisposed()) return;
        paintClassMask(canvas, result);
        const classes = [...result.classes]
          .sort((a, b) => b.fraction - a.fraction)
          .slice(0, 12);
        if (classes.length === 0) {
          out.innerHTML = `<p class="ra-muted">No classes detected.</p>`;
        } else {
          out.innerHTML =
            `<div class="ra-dense-list">` +
            classes
              .map((entry) => {
                const [r, g, b] = classRgb(entry.classId);
                const label = entry.label || `class ${entry.classId}`;
                return (
                  `<div class="ra-dense-row">` +
                  `<span class="ra-swatch" style="background:rgb(${r},${g},${b})"></span>` +
                  `<div class="ra-dense-copy"><strong>${escapeHtml(label)}</strong></div>` +
                  `<span class="ra-badge">${(entry.fraction * 100).toFixed(1)}%</span>` +
                  `</div>`
                );
              })
              .join('') +
            `</div>`;
        }
        status.textContent = 'Done';
      } catch (error) {
        canvas.style.display = 'none';
        showError(error, 'Segmentation failed');
        status.textContent = error instanceof Error ? error.message : 'Failed';
      } finally {
        busy = false;
        if (!isDisposed()) goBtn.disabled = file === null;
      }
    })();
  });

  return {
    dispose() {
      disposed = true;
    },
  };
};
