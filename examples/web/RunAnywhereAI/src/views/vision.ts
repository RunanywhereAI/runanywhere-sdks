/**
 * Vision Tab — ask a vision model about a photo or the live camera.
 *
 * Mirrors iOS VLMViewModel (Features/Vision/VLMViewModel.swift):
 *
 *   1. User downloads + loads any multimodal model via the shared model
 *      selection sheet (`RunAnywhere.models.download` + `models.load`). Loading a
 *      multimodal model syncs the Web vision-language provider inside the
 *      SDK — no app-side bridging.
 *   2. User starts the camera — `VideoCapture` attaches its `<video>` to
 *      the preview container.
 *   3. The still is streamed through `RunAnywhere.vlm.generateStream(image,
 *      prompt)`, rendering token events as they arrive (iOS parity:
 *      VLMViewModel.swift:148-194 consumeVLMStream/describeCurrentFrame), with
 *      cancel support.
 *
 * The three things this screen is doing at any moment — the camera, the frame,
 * and the run — are tracked separately on purpose. They used to share one
 * `isBusy` flag, so waiting on the camera permission prompt labelled the run
 * button "Analyzing…" and enabled a Cancel that had nothing to cancel.
 */

import type { TabLifecycle } from '../app';
import { ModelCategory, RunAnywhere } from '@runanywhere/web';
import { VideoCapture } from '@runanywhere/web/browser';
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
import { icon } from '../components/icons';
import { onEngineStateChange } from '../services/engine-availability';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import {
  decodeImageFileToRgbFrame,
  rgbFrameToDataUrl,
  validateImageFile,
  type RgbFrame,
} from '../services/image-frame';

const VLM_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_MULTIMODAL,
  ModelCategory.MODEL_CATEGORY_VISION,
];

const DEFAULT_PROMPT = 'Describe what you see in this image.';
const CAPTURE_DIMENSION = 384;

/** Where the still on screen came from — the two paths read differently. */
type FrameSource = 'camera' | 'file';

/** What the camera is doing. `starting` is the permission prompt's window. */
type CameraState = 'idle' | 'starting' | 'live';

let container: HTMLElement;
let camera: VideoCapture | null = null;
let cameraState: CameraState = 'idle';
/**
 * The prompt the user actually typed.
 *
 * Held here rather than read off the DOM at analyze time, because `renderView`
 * rebuilds the panel's whole subtree — on every capture, every model-state
 * change and every status update — and the textarea used to be re-emitted with
 * `DEFAULT_PROMPT` as its content each time. Typing a prompt and then pressing
 * "Capture frame" silently reverted it.
 */
let prompt = DEFAULT_PROMPT;
let latestFrame: RgbFrame | null = null;
let frameSource: FrameSource | null = null;
/**
 * A data URL of exactly the pixels in `latestFrame`.
 *
 * Kept for both frame sources, not just for a file. A camera still used to have
 * no image behind it, so stopping the camera blanked the preview — and
 * `stopCamera` then discarded the frame outright, leaving "Captured 384×288
 * frame." on screen above "No frame captured yet." A captured still is a
 * photograph: releasing the camera must not take it away.
 */
let framePreviewUrl: string | null = null;
let lastResult: string | null = null;
let status = '';
let cameraStatus = '';
let isAnalyzing = false;
let cancelAnalyze: (() => void) | null = null;
/**
 * Drops the previous tab instance's subscriptions.
 *
 * Per-instance rather than the pair of module-globals every observer used to
 * read: a second `initVisionTab` overwrote those globals, so the older
 * observer's teardown cancelled the *live* tab's subscriptions and left the
 * replaced ones running — engine and model changes then re-rendered a detached
 * panel and stopped reaching this one. Cleared here on re-init as well, because
 * the shell rebuild that causes it (`buildAppShell` empties `#app`) mutates
 * neither observed parent, so the old observer never fires at all.
 */
let disposeSubscriptions: (() => void) | null = null;
let cameraStartGeneration = 0;

export function initVisionTab(el: HTMLElement): TabLifecycle {
  disposeSubscriptions?.();
  container = el;

  renderView();

  // Re-render when the shared model state changes so the "Load model"
  // button reflects real state without manual refresh.
  const unsubscribeState = onModelStateChange(() => renderView());
  // A successful engine retry has to restore this tab in place, or the notice
  // stays up over controls that would now work.
  const unsubscribeEngine = onEngineStateChange(() => renderView());
  const dispose = (): void => {
    unsubscribeState();
    unsubscribeEngine();
  };
  disposeSubscriptions = dispose;

  // Tear down this instance's subscriptions if its panel element ever detaches
  // (e.g. a full app-shell re-render). `el`, not the shared `container`, so a
  // stale observer cannot judge a newer tab's element.
  const rootParent = el.parentElement;
  if (typeof MutationObserver !== 'undefined' && rootParent) {
    const disposeObserver = new MutationObserver(() => {
      if (el.isConnected) return;
      disposeObserver.disconnect();
      dispose();
      if (disposeSubscriptions === dispose) disposeSubscriptions = null;
    });
    disposeObserver.observe(rootParent, { childList: true });
  }

  return {
    onActivate: () => {
      renderView();
    },
    onDeactivate: () => {
      cancelAnalyze?.();
      const wasActive = cameraState !== 'idle';
      stopCamera();
      // Leaving the tab releases the camera and abandons a pending permission
      // prompt, so neither "Camera is on." nor "Waiting for you to allow camera
      // access…" may still be on screen when the reader comes back.
      if (wasActive) cameraStatus = 'Camera released when you left this tab.';
    },
  };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderView(): void {
  const notice = engineNoticeForCategories(VLM_PICKER_FILTER);
  const engineBlocked = isEngineBlocked(notice);
  const loadedModel = loadedVisionModel();
  const support = cameraSupport();
  const live = cameraState === 'live';
  const starting = cameraState === 'starting';
  const canStartCamera = support === 'ok' && !engineBlocked && !starting && !isAnalyzing;
  const canAnalyze = loadedModel !== null && !engineBlocked && !isAnalyzing
    && (live || latestFrame !== null);
  const cameraBlocked = cameraBlockedReason(support, engineBlocked);

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Vision</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="vision-model-btn">
          ${loadedModel ? 'Change model' : 'Load vision model'}
        </button>
      </div>
    </div>
    <div class="scroll-area">
      <div id="vision-engine-notice"></div>

      <div class="docs-section">
        <h3>Picture</h3>
        <p class="text-secondary">Point your camera at something, or open a picture you already have. The model looks at one still image at a time.</p>
        <div class="docs-actions">
          <button class="btn ${live ? 'btn-secondary' : 'btn-primary'}" id="vision-camera-btn"
            ${canStartCamera || live ? '' : 'disabled'}
            title="${escapeHtml(cameraBlocked ?? (live ? 'Release the camera' : 'Turn the camera on'))}">
            ${live ? 'Stop camera' : starting ? 'Starting…' : 'Start camera'}
          </button>
          <button class="btn btn-secondary" id="vision-capture-btn" ${live && !isAnalyzing ? '' : 'disabled'}
            title="${live ? 'Freeze the current view as the picture to analyze' : 'Start the camera first'}">
            Take a still
          </button>
          <button class="btn btn-secondary" id="vision-load-image-btn" ${isAnalyzing || engineBlocked ? 'disabled' : ''}>
            Open a picture…
          </button>
          <input type="file" id="vision-image-input" accept="image/*" hidden />
        </div>
        <div id="vision-preview" class="vision-preview"></div>
        <div id="vision-frame-meta" class="docs-status">${escapeHtml(frameMetaLabel())}</div>
        <div id="vision-camera-status" class="docs-status" role="status" aria-live="polite">${escapeHtml(cameraStatus)}</div>
      </div>

      <div class="docs-section">
        <h3>Ask about it</h3>
        <p class="text-secondary">${escapeHtml(readinessLine(loadedModel, engineBlocked))}</p>
        <!-- A label belongs above its field, not beside it. This used to carry
             class "form-label", which no stylesheet defined, so the label and
             the textarea both laid out inline and the prompt box read as
             unlabelled. "field" is the two-row block. -->
        <div class="field">
          <label class="field__label" for="vision-prompt">Your question</label>
          <textarea id="vision-prompt" class="chat-input" rows="2"
            ${isAnalyzing ? 'disabled' : ''}
            placeholder="What's in this image?">${escapeHtml(prompt)}</textarea>
        </div>
        <div class="docs-actions">
          <button class="btn btn-primary" id="vision-analyze-btn" ${canAnalyze ? '' : 'disabled'}
            title="${escapeHtml(analyzeButtonTitle(loadedModel !== null, engineBlocked, live))}">
            ${isAnalyzing ? 'Reading the picture…' : analyzeButtonLabel(live)}
          </button>
          <button class="btn btn-secondary" id="vision-cancel-btn" ${cancelAnalyze ? '' : 'disabled'}>
            Stop
          </button>
        </div>
        <div id="vision-status" class="docs-status" role="status" aria-live="polite">${escapeHtml(status)}</div>
        <!-- null means no run has produced text; an empty string means a run is
             streaming into the pane. An output box holding the literal
             "(no response yet)" — what this used to render — is
             indistinguishable from a model that ran and answered nothing. -->
        ${lastResult === null
          ? `<div class="surface-empty">
               ${icon('message', { size: 24 })}
               <p>The answer appears here once you take a still or open a picture and ask.</p>
             </div>`
          : `<pre id="vision-output" class="docs-pre">${escapeHtml(lastResult)}</pre>`}
      </div>
    </div>
  `;

  const noticeHost = container.querySelector<HTMLElement>('#vision-engine-notice')!;
  noticeHost.innerHTML = renderEngineNotice(notice);
  wireEngineNotice(noticeHost, notice);

  reattachPreview();

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
    .addEventListener('click', () => captureStill());
  const imageInput = container.querySelector<HTMLInputElement>('#vision-image-input')!;
  container
    .querySelector('#vision-load-image-btn')!
    .addEventListener('click', () => imageInput.click());
  imageInput.addEventListener('change', () => void onImageFileSelected(imageInput));
  // Mirror every keystroke into module state so the next re-render re-emits what
  // the user typed rather than the default.
  container
    .querySelector<HTMLTextAreaElement>('#vision-prompt')!
    .addEventListener('input', (event) => {
      prompt = (event.currentTarget as HTMLTextAreaElement).value;
    });
  container
    .querySelector('#vision-analyze-btn')!
    .addEventListener('click', () => void onAnalyze());
  container
    .querySelector('#vision-cancel-btn')!
    .addEventListener('click', () => cancelAnalyze?.());
}

/**
 * Put the live video or the captured still back in the preview slot.
 *
 * Both carry their sizing inline: `.vision-preview` has no stylesheet rules of
 * its own, so a 640-wide camera element laid out at its intrinsic size and was
 * clipped by the panel on any narrow window — the right-hand third of the frame
 * the model is about to read was simply not on screen.
 */
function reattachPreview(): void {
  const host = container.querySelector<HTMLElement>('#vision-preview');
  if (!host) return;
  host.innerHTML = '';
  if (camera && cameraState === 'live') {
    const video = camera.videoElement;
    fitPreviewElement(video);
    video.setAttribute('aria-label', 'Live camera preview');
    host.appendChild(video);
    return;
  }
  if (framePreviewUrl) {
    const img = document.createElement('img');
    img.src = framePreviewUrl;
    img.alt = frameSource === 'camera'
      ? 'The still captured from your camera'
      : 'The picture you opened';
    fitPreviewElement(img);
    host.appendChild(img);
  }
}

function fitPreviewElement(el: HTMLElement): void {
  el.style.display = 'block';
  el.style.width = 'auto';
  el.style.maxWidth = '100%';
  el.style.height = 'auto';
  el.style.borderRadius = 'var(--radius-regular)';
}

function frameMetaLabel(): string {
  if (!latestFrame) {
    return cameraState === 'live'
      ? 'Nothing captured yet — take a still, or ask and the current view is used.'
      : 'No picture yet.';
  }
  const origin = frameSource === 'camera' ? 'Still from your camera' : 'Picture you opened';
  return `${origin} · ${latestFrame.width}×${latestFrame.height}`;
}

/** One honest sentence about whether a question can be answered at all. */
function readinessLine(
  loadedModel: { name: string; id: string } | null,
  engineBlocked: boolean,
): string {
  if (engineBlocked) {
    return 'The on-device AI engine did not load, so nothing can be analyzed yet.';
  }
  if (!loadedModel) {
    return 'No vision model is loaded yet. Load one from the button above and the answer streams in as it is written.';
  }
  return `${loadedModel.name || loadedModel.id} is loaded and answers on this device. The reply streams in as it is written.`;
}

function analyzeButtonLabel(live: boolean): string {
  // The label has to match what the press actually does. With the camera
  // running this grabs a fresh frame; with a held still it re-reads that still,
  // and calling that "Capture & analyze" was a promise the button did not keep.
  return live ? 'Capture & ask' : 'Ask about this picture';
}

function analyzeButtonTitle(modelLoaded: boolean, engineBlocked: boolean, live: boolean): string {
  if (engineBlocked) return 'The on-device AI engine did not load';
  if (!modelLoaded) return 'Load a vision model first';
  if (!live && latestFrame === null) return 'Take a still or open a picture first';
  return live ? 'Capture the current view and ask about it' : 'Ask about the picture above';
}

function cameraBlockedReason(support: CameraSupport, engineBlocked: boolean): string | null {
  if (support === 'insecure') {
    return 'The camera needs a secure (https) connection';
  }
  if (support === 'unsupported') {
    return 'This browser does not offer camera access';
  }
  if (engineBlocked) return 'The on-device AI engine did not load';
  return null;
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

type CameraSupport = 'ok' | 'insecure' | 'unsupported';

/**
 * Whether this browser can be asked for a camera at all.
 *
 * `navigator.mediaDevices` is simply absent on an insecure origin, so pressing
 * Start there used to throw a `TypeError` and report it as a camera fault. The
 * two cases read differently to a user — one is fixable by loading the page over
 * https, the other is not fixable at all — so they are separated here.
 */
function cameraSupport(): CameraSupport {
  // `navigator.mediaDevices` is typed as always present but is genuinely absent
  // on an insecure origin, so the check needs a widening cast — an optional
  // chain here is narrowed away as always-truthy before it can run.
  const media = typeof navigator === 'undefined'
    ? undefined
    : (navigator.mediaDevices as MediaDevices | undefined);
  if (media && typeof media.getUserMedia === 'function') return 'ok';
  return typeof window !== 'undefined' && window.isSecureContext === false
    ? 'insecure'
    : 'unsupported';
}

async function toggleCamera(): Promise<void> {
  if (cameraState === 'live') {
    stopCamera();
    setCameraStatus('Camera stopped.');
    renderView();
    return;
  }
  await startCamera();
}

async function startCamera(): Promise<void> {
  const support = cameraSupport();
  if (support !== 'ok') {
    setCameraStatus(support === 'insecure'
      ? 'The camera is only available over a secure (https) connection. Open this page over https, then start the camera.'
      : 'This browser does not offer camera access. Open a picture instead.');
    renderView();
    return;
  }

  const generation = ++cameraStartGeneration;
  const candidate = new VideoCapture({
    facingMode: 'environment',
    idealWidth: 640,
    idealHeight: 480,
  });
  cameraState = 'starting';
  setCameraStatus('Waiting for you to allow camera access…');
  renderView();
  try {
    await candidate.start();
    if (generation !== cameraStartGeneration) {
      candidate.stop();
      return;
    }
    camera = candidate;
    cameraState = 'live';
    setCameraStatus('Camera is on.');
  } catch (err) {
    candidate.stop();
    if (generation !== cameraStartGeneration) return;
    camera = null;
    cameraState = 'idle';
    setCameraStatus(await describeCameraFailure(err));
  } finally {
    if (generation === cameraStartGeneration) renderView();
  }
}

/**
 * Say which of the camera's failures this was, and what to do about it.
 *
 * `VideoCapture.start` rewraps whatever `getUserMedia` threw as
 * `new Error('Camera access failed: …')`, so the `DOMException.name` that
 * distinguishes "you blocked it" from "there isn't one" never reaches here. The
 * browser can still be asked directly, which is more reliable than matching on
 * an error string that differs per browser: device presence comes from
 * `enumerateDevices`, and the block comes from the Permissions API. The message
 * text is only consulted last, as a hint.
 */
async function describeCameraFailure(err: unknown): Promise<string> {
  if (!(await hasVideoInput())) {
    return 'No camera was found on this device. Open a picture instead.';
  }
  if (await cameraPermissionDenied()) {
    return 'Camera access is blocked for this site. Allow the camera in your browser’s site settings, then start it again.';
  }
  const detail = formatError(err).replace(/^Camera access failed:\s*/i, '');
  if (/in use|not readable|could not start|allocat/i.test(detail)) {
    return 'Another app is using the camera. Close it and start the camera again.';
  }
  if (/not allowed|permission|denied/i.test(detail)) {
    return 'Camera access was not granted. Allow the camera when your browser asks, then start it again.';
  }
  if (/not found|no device|devicenotfound/i.test(detail)) {
    return 'No camera was found on this device. Open a picture instead.';
  }
  return `The camera could not be started: ${detail}`;
}

async function hasVideoInput(): Promise<boolean> {
  try {
    const devices = await navigator.mediaDevices.enumerateDevices();
    return devices.some((device) => device.kind === 'videoinput');
  } catch {
    // Enumeration itself can be blocked; assume a camera exists rather than
    // telling the user they have no hardware on this evidence.
    return true;
  }
}

async function cameraPermissionDenied(): Promise<boolean> {
  try {
    // `camera` is not in every browser's PermissionName union, hence the cast.
    const result = await navigator.permissions.query({
      name: 'camera' as PermissionName,
    });
    return result.state === 'denied';
  } catch {
    return false;
  }
}

/**
 * Release the camera, keeping whatever still was already taken.
 *
 * Deliberately does not clear `latestFrame`: the still is an image the user
 * captured, not a property of the open stream.
 */
function stopCamera(): void {
  cameraStartGeneration += 1;
  camera?.stop();
  camera = null;
  cameraState = 'idle';
}

function captureStill(): void {
  const frame = grabCameraFrame();
  if (!frame) {
    setCameraStatus('That frame could not be captured — the camera may still be warming up. Try again.');
    renderView();
    return;
  }
  adoptFrame(frame, 'camera');
  setCameraStatus(`Still captured at ${frame.width}×${frame.height}.`);
  renderView();
}

function grabCameraFrame(): RgbFrame | null {
  if (cameraState !== 'live' || !camera?.isCapturing) return null;
  return camera.captureFrame(CAPTURE_DIMENSION);
}

/**
 * Make `frame` the picture on screen and the one Analyze will read.
 *
 * Re-adopting the frame already held is a no-op rather than a second canvas
 * round-trip, so asking twice about the same still does not re-encode it.
 *
 * A different frame drops the previous answer and its status line. They
 * describe the picture that was just replaced, and leaving them under the new
 * still's metadata reads as an answer about the new picture — the one mistake
 * this pane must not invite. Every caller re-renders after adopting, so the
 * cleared state reaches the screen with the new preview.
 */
function adoptFrame(frame: RgbFrame, source: FrameSource, previewUrl?: string): void {
  if (frame === latestFrame && framePreviewUrl) return;
  latestFrame = frame;
  frameSource = source;
  framePreviewUrl = previewUrl ?? rgbFrameToDataUrl(frame);
  lastResult = null;
  status = '';
}

// ---------------------------------------------------------------------------
// Image from disk
// ---------------------------------------------------------------------------

async function onImageFileSelected(input: HTMLInputElement): Promise<void> {
  const file = input.files?.[0];
  // Reset so re-selecting the same file fires `change` again.
  input.value = '';
  if (!file) return;

  // `accept="image/*"` only filters the picker's default view; a user can switch
  // it to "All Files" and hand this a 40 MB TIFF or a PDF.
  const rejection = validateImageFile(file);
  if (rejection) {
    setCameraStatus(rejection);
    renderView();
    return;
  }

  setCameraStatus(`Opening ${file.name}…`);
  renderView();
  try {
    const decoded = await decodeImageFileToRgbFrame(file, CAPTURE_DIMENSION);
    // An opened picture replaces the live camera as the frame source, so release
    // the camera rather than leaving a preview that no longer feeds the answer.
    stopCamera();
    adoptFrame(
      { rgbPixels: decoded.rgbPixels, width: decoded.width, height: decoded.height },
      'file',
      decoded.previewUrl,
    );
    setCameraStatus(`Opened ${file.name} at ${decoded.width}×${decoded.height}.`);
  } catch (err) {
    setCameraStatus(`That picture could not be opened: ${formatError(err)}`);
  } finally {
    renderView();
  }
}

// ---------------------------------------------------------------------------
// Analyze
// ---------------------------------------------------------------------------

async function onAnalyze(): Promise<void> {
  // Gate on the lifecycle's loaded multimodal model — iOS parity:
  // VLMViewModel.swift:58-62 checkModelStatus() (currentModel(.multimodal)).
  if (!loadedVisionModel()) {
    setStatus('No vision model is loaded. Load one from the button above, then ask again.');
    renderView();
    return;
  }

  // With the camera running, "Capture & ask" means exactly that: take a new
  // frame. Preferring an older still here is how the button came to analyze a
  // picture that was no longer what the camera was pointing at.
  const frame = grabCameraFrame() ?? latestFrame;
  if (!frame) {
    setStatus('Take a still or open a picture first.');
    renderView();
    return;
  }
  adoptFrame(frame, cameraState === 'live' ? 'camera' : frameSource ?? 'file');

  // Read from the live field when it is on screen (it always is at this point),
  // falling back to the mirrored value; an empty box means "use the default"
  // rather than sending the model no instruction at all.
  const promptEl = container.querySelector<HTMLTextAreaElement>('#vision-prompt');
  const effectivePrompt = (promptEl?.value ?? prompt).trim() || DEFAULT_PROMPT;

  const image = RunAnywhere.ImageInput.rawRgb(frame.rgbPixels, frame.width, frame.height);

  isAnalyzing = true;
  setStatus('Looking at the picture…');
  lastResult = '';

  const events = RunAnywhere.vlm.generateStream(image, effectivePrompt, {
    maxOutputTokens: 200,
    temperature: 0.7,
    topP: 0.9,
    topK: 40,
  });
  const iterator = events[Symbol.asyncIterator]();
  // Abandoning the iterator is the cancellation contract for every v3 stream.
  let cancellationRequested = false;
  cancelAnalyze = () => {
    cancellationRequested = true;
    void iterator.return?.();
  };
  // Rendered only now that the cancel handle exists, so Stop is never offered
  // before there is a run to stop.
  renderView();

  try {
    let sawToken = false;
    for (let step = await iterator.next(); !step.done; step = await iterator.next()) {
      const event = step.value;
      if (event.type === 'textDelta') {
        if (!sawToken) {
          sawToken = true;
          // The first token is the moment the model stopped preparing. Until
          // then a vision model can spend a long time encoding the image, and
          // "Looking at the picture…" is the only thing separating that wait
          // from a hang.
          setStatus('Writing the answer…');
        }
        lastResult = (lastResult ?? '') + event.text;
        updateOutput(lastResult);
      } else if (event.type === 'completed') {
        const { result } = event;
        const tokLine = result.tokensPerSecond > 0
          ? ` — ${result.outputTokens} tokens at ${result.tokensPerSecond.toFixed(1)}/s`
          : '';
        setStatus(`Done${tokLine}.`);
      } else if (event.type === 'failed') {
        // A mid-stream failure arrives as an event, not a throw. Ignoring it —
        // which this loop used to do — turned every backend fault into the
        // "model returned nothing" ending, so a broken vision pipeline was
        // indistinguishable from a model with nothing to say.
        throw new Error(event.error.message || 'The vision model failed mid-answer.');
      }
    }
    // Nothing arrived: drop back to `null` so the pane shows its empty state
    // rather than an output box holding a parenthetical stand-in, and let the
    // status line say which of the two outcomes it was.
    if (cancellationRequested) {
      setStatus(lastResult ? 'Stopped — the answer above is partial.' : 'Stopped.');
      if (!lastResult) lastResult = null;
    } else if (!lastResult) {
      lastResult = null;
      setStatus('The model finished without describing the picture. Try a different question or another picture.');
    }
  } catch (err) {
    setStatus(cancellationRequested
      ? 'Stopped.'
      : `The picture could not be analyzed: ${formatError(err)}`);
  } finally {
    cancelAnalyze = null;
    isAnalyzing = false;
    renderView();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * The loaded MULTIMODAL (or VISION) model the C++ lifecycle reports — iOS
 * parity: VLMViewModel.swift:58-62 (currentModel with category filter).
 * No model-id allowlist: any loaded vision-capable model enables Analyze.
 */
function loadedVisionModel(): { name: string; id: string } | null {
  for (const category of VLM_PICKER_FILTER) {
    const model = findLoadedModelForCategory(category);
    if (model) return { name: model.name, id: model.id };
  }
  return null;
}

function setStatus(text: string): void {
  status = text;
  const banner = container.querySelector<HTMLDivElement>('#vision-status');
  if (banner) banner.textContent = text;
}

function setCameraStatus(text: string): void {
  cameraStatus = text;
  const banner = container.querySelector<HTMLDivElement>('#vision-camera-status');
  if (banner) banner.textContent = text;
}

function updateOutput(text: string): void {
  const output = container.querySelector<HTMLPreElement>('#vision-output');
  if (output) output.textContent = text;
}
