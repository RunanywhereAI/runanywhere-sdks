/**
 * Vision Tab - Live Camera + VLM Description
 *
 * Mirrors iOS VLMCameraView / VLMViewModel:
 *   - Live webcam preview via getUserMedia()
 *   - Single-tap capture + describe (sparkles button)
 *   - Auto-streaming "Live" mode (describe every 2.5s)
 *   - Photo upload fallback
 *   - Description panel with streaming text
 *   - Model selection for multimodal models
 */

import { ModelManager, type ModelInfo } from '../services/model-manager';
import { showModelSelectionSheet } from '../components/model-selection';

// ---------------------------------------------------------------------------
// Constants (matching iOS VLMViewModel defaults)
// ---------------------------------------------------------------------------

const AUTO_STREAM_INTERVAL_MS = 2500;
const SINGLE_SHOT_MAX_TOKENS = 200;
const AUTO_STREAM_MAX_TOKENS = 100;
const SINGLE_SHOT_PROMPT = 'Describe what you see briefly.';
const AUTO_STREAM_PROMPT = 'Describe what you see in one sentence.';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

let container: HTMLElement;
let overlayEl: HTMLElement;
let toolbarModelEl: HTMLElement;
let videoEl: HTMLVideoElement;
let canvasEl: HTMLCanvasElement;
let descriptionEl: HTMLElement;
let captureBtn: HTMLElement;
let liveToggleBtn: HTMLElement;
let liveBadge: HTMLElement;
let processingOverlay: HTMLElement;
let metricsEl: HTMLElement;
let copyBtn: HTMLElement;

let cameraStream: MediaStream | null = null;
let isProcessing = false;
let isLiveMode = false;
let liveIntervalId: ReturnType<typeof setTimeout> | null = null;
let currentDescription = '';

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export function initVisionTab(el: HTMLElement): void {
  container = el;
  container.innerHTML = `
    <!-- Toolbar -->
    <div class="toolbar">
      <div class="toolbar-actions"></div>
      <div class="toolbar-title" id="vision-toolbar-model" style="cursor:pointer;">Select Model</div>
      <div class="toolbar-actions"></div>
    </div>

    <!-- Main Content -->
    <div class="vision-main" id="vision-main" style="display:none;">
      <!-- Camera Preview -->
      <div class="vision-camera-container">
        <video id="vision-video" autoplay playsinline muted></video>
        <canvas id="vision-canvas" style="display:none;"></canvas>
        <!-- Processing overlay -->
        <div class="vision-processing-overlay" id="vision-processing-overlay" style="display:none;">
          <div class="typing-dots" style="transform:scale(0.8);">
            <div class="typing-dot"></div>
            <div class="typing-dot"></div>
            <div class="typing-dot"></div>
          </div>
          <span style="font-size:var(--font-size-xs);color:rgba(255,255,255,0.8);">Analyzing...</span>
        </div>
      </div>

      <!-- Description Panel -->
      <div class="vision-description-panel" id="vision-description-panel">
        <div class="vision-description-header">
          <div style="display:flex;align-items:center;gap:6px;">
            <span style="font-size:var(--font-size-sm);font-weight:var(--font-weight-semibold);">Description</span>
            <span class="vision-live-badge" id="vision-live-badge" style="display:none;">LIVE</span>
          </div>
          <button class="btn btn-icon" id="vision-copy-btn" title="Copy" style="display:none;width:28px;height:28px;">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
          </button>
        </div>
        <div class="vision-description-text" id="vision-description-text">
          <span style="color:var(--text-tertiary);">Tap the capture button to describe what the camera sees.</span>
        </div>
        <div class="vision-metrics" id="vision-metrics" style="display:none;"></div>
      </div>

      <!-- Control Bar -->
      <div class="vision-control-bar">
        <input type="file" id="vision-file-input" accept="image/*" style="display:none;">
        <button class="vision-control-btn" id="vision-photos-btn" title="Photos">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><circle cx="8.5" cy="8.5" r="1.5"/><polyline points="21 15 16 10 5 21"/></svg>
          <span>Photos</span>
        </button>
        <button class="vision-capture-btn" id="vision-capture-btn" title="Capture and Describe">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 14.5v-9l6 4.5-6 4.5z" opacity="0"/><path d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 1 1 7.072 0l-.548.547A3.374 3.374 0 0 0 12 18.469V19" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>
        </button>
        <button class="vision-control-btn" id="vision-live-btn" title="Toggle Live Mode">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15"/><circle cx="12" cy="12" r="10"/></svg>
          <span>Live</span>
        </button>
        <button class="vision-control-btn" id="vision-model-btn" title="Select Model">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>
          <span>Model</span>
        </button>
      </div>
    </div>

    <!-- Camera Permission / Model Required Overlay -->
    <div class="model-overlay" id="vision-model-overlay">
      <div class="model-overlay-bg" id="vision-floating-bg"></div>
      <div class="model-overlay-content">
        <div class="sparkle-icon">&#128065;</div>
        <h2>Vision AI</h2>
        <p>See the world through AI. Point your camera at anything and get instant descriptions.</p>
        <button class="btn btn-primary btn-lg" id="vision-get-started-btn">Get Started</button>
        <div class="privacy-note">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          <span>100% Private &mdash; Runs on your device</span>
        </div>
      </div>
    </div>
  `;

  // Build floating circles for overlay
  buildFloatingCircles();

  // Cache references
  overlayEl = container.querySelector('#vision-model-overlay')!;
  toolbarModelEl = container.querySelector('#vision-toolbar-model')!;
  videoEl = container.querySelector('#vision-video')!;
  canvasEl = container.querySelector('#vision-canvas')!;
  descriptionEl = container.querySelector('#vision-description-text')!;
  captureBtn = container.querySelector('#vision-capture-btn')!;
  liveToggleBtn = container.querySelector('#vision-live-btn')!;
  liveBadge = container.querySelector('#vision-live-badge')!;
  processingOverlay = container.querySelector('#vision-processing-overlay')!;
  metricsEl = container.querySelector('#vision-metrics')!;
  copyBtn = container.querySelector('#vision-copy-btn')!;

  const fileInput = container.querySelector('#vision-file-input') as HTMLInputElement;

  // Event listeners
  captureBtn.addEventListener('click', onCaptureClick);
  liveToggleBtn.addEventListener('click', toggleLiveMode);
  container.querySelector('#vision-photos-btn')!.addEventListener('click', () => fileInput.click());
  container.querySelector('#vision-model-btn')!.addEventListener('click', openModelSheet);
  container.querySelector('#vision-get-started-btn')!.addEventListener('click', onGetStarted);
  toolbarModelEl.addEventListener('click', openModelSheet);
  copyBtn.addEventListener('click', copyDescription);

  fileInput.addEventListener('change', () => {
    const file = fileInput.files?.[0];
    if (file) handlePhotoUpload(file);
    fileInput.value = '';
  });

  // Subscribe to model changes
  ModelManager.onChange(onModelsChanged);
  onModelsChanged(ModelManager.getModels());
}

// ---------------------------------------------------------------------------
// Floating circles background
// ---------------------------------------------------------------------------

function buildFloatingCircles(): void {
  const bg = container.querySelector('#vision-floating-bg')!;
  const colors = ['#8B5CF6', '#3B82F6', '#EC4899', '#10B981', '#F59E0B'];
  for (let i = 0; i < 8; i++) {
    const circle = document.createElement('div');
    circle.className = 'floating-circle';
    const size = 60 + Math.random() * 120;
    circle.style.cssText = `
      width:${size}px; height:${size}px;
      background:${colors[i % colors.length]};
      left:${Math.random() * 100}%;
      top:${Math.random() * 100}%;
      animation-delay:${Math.random() * 4}s;
      animation-duration:${6 + Math.random() * 6}s;
    `;
    bg.appendChild(circle);
  }
}

// ---------------------------------------------------------------------------
// Model Sheet + Overlay
// ---------------------------------------------------------------------------

function openModelSheet(): void {
  showModelSelectionSheet('multimodal');
}

function onModelsChanged(_models: ModelInfo[]): void {
  const loaded = ModelManager.getLoadedModel('multimodal');
  if (loaded) {
    toolbarModelEl.textContent = loaded.name;
    // Model is loaded — show the main camera UI (camera may or may not be active)
    overlayEl.style.display = 'none';
    (container.querySelector('#vision-main') as HTMLElement).style.display = 'flex';
    // Auto-start camera if not already running
    if (!cameraStream) {
      startCamera();
    }
  } else {
    overlayEl.style.display = '';
    toolbarModelEl.textContent = 'Select Model';
    (container.querySelector('#vision-main') as HTMLElement).style.display = 'none';
    stopLiveMode();
    stopCamera();
  }
}

async function onGetStarted(): Promise<void> {
  // First ensure a model is selected
  const loaded = ModelManager.getLoadedModel('multimodal');
  if (!loaded) {
    openModelSheet();
    // Wait for model to load, then start camera
    const unsub = ModelManager.onChange(() => {
      const m = ModelManager.getLoadedModel('multimodal');
      if (m) {
        unsub();
        startCamera();
      }
    });
    return;
  }
  await startCamera();
}

// ---------------------------------------------------------------------------
// Camera
// ---------------------------------------------------------------------------

async function startCamera(): Promise<void> {
  try {
    cameraStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'environment', width: { ideal: 1280 }, height: { ideal: 720 } },
      audio: false,
    });
    videoEl.srcObject = cameraStream;

    overlayEl.style.display = 'none';
    (container.querySelector('#vision-main') as HTMLElement).style.display = 'flex';

    console.log('[Vision] Camera started');
  } catch (err) {
    console.error('[Vision] Camera access denied:', err);
    descriptionEl.innerHTML = `<span style="color:var(--color-red);">Camera access denied. Please allow camera access in your browser settings, or use the Photos button to upload an image.</span>`;
    // Still show the main UI so they can use photo upload
    overlayEl.style.display = 'none';
    (container.querySelector('#vision-main') as HTMLElement).style.display = 'flex';
  }
}

function stopCamera(): void {
  if (cameraStream) {
    cameraStream.getTracks().forEach((t) => t.stop());
    cameraStream = null;
    videoEl.srcObject = null;
  }
}

/** Captured frame data: raw RGB pixels + dimensions */
interface CapturedFrame {
  rgbPixels: Uint8Array;
  width: number;
  height: number;
}

/**
 * Capture the current video frame as raw RGB pixels.
 *
 * The C++ VLM backend (llama.cpp mtmd) expects RAC_VLM_IMAGE_FORMAT_RGB_PIXELS
 * with RGBRGBRGB... byte layout — matching how iOS sends CVPixelBuffer data
 * after BGRA→RGB conversion.
 */
function captureFrame(): CapturedFrame | null {
  if (!videoEl.videoWidth || !videoEl.videoHeight) return null;

  canvasEl.width = videoEl.videoWidth;
  canvasEl.height = videoEl.videoHeight;
  const ctx = canvasEl.getContext('2d');
  if (!ctx) return null;

  ctx.drawImage(videoEl, 0, 0);
  return extractRGBFromCanvas(ctx, canvasEl.width, canvasEl.height);
}

/**
 * Extract raw RGB pixels from a canvas 2D context.
 * Canvas gives RGBA; we strip the alpha channel to produce RGBRGBRGB...
 */
function extractRGBFromCanvas(ctx: CanvasRenderingContext2D, w: number, h: number): CapturedFrame {
  const imageData = ctx.getImageData(0, 0, w, h);
  const rgba = imageData.data; // Uint8ClampedArray: RGBARGBA...
  const pixelCount = w * h;
  const rgb = new Uint8Array(pixelCount * 3);

  for (let i = 0; i < pixelCount; i++) {
    rgb[i * 3] = rgba[i * 4];       // R
    rgb[i * 3 + 1] = rgba[i * 4 + 1]; // G
    rgb[i * 3 + 2] = rgba[i * 4 + 2]; // B
    // skip rgba[i * 4 + 3] (alpha)
  }

  return { rgbPixels: rgb, width: w, height: h };
}

// ---------------------------------------------------------------------------
// Capture Button
// ---------------------------------------------------------------------------

function onCaptureClick(): void {
  if (isLiveMode) {
    // Tapping capture during live mode stops it
    stopLiveMode();
    return;
  }
  describeCurrent(SINGLE_SHOT_PROMPT, SINGLE_SHOT_MAX_TOKENS);
}

// ---------------------------------------------------------------------------
// Live Mode (auto-streaming every 2.5s)
// ---------------------------------------------------------------------------

function toggleLiveMode(): void {
  if (isLiveMode) {
    stopLiveMode();
  } else {
    startLiveMode();
  }
}

function startLiveMode(): void {
  isLiveMode = true;
  liveToggleBtn.classList.add('active');
  liveBadge.style.display = 'inline-flex';
  captureBtn.classList.add('live');
  captureBtn.innerHTML = `
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>
  `;

  console.log('[Vision] Live mode started');

  // Immediately describe the first frame
  describeCurrent(AUTO_STREAM_PROMPT, AUTO_STREAM_MAX_TOKENS);

  // Then repeat every 2.5s
  liveIntervalId = setInterval(() => {
    if (!isProcessing && isLiveMode) {
      describeCurrent(AUTO_STREAM_PROMPT, AUTO_STREAM_MAX_TOKENS);
    }
  }, AUTO_STREAM_INTERVAL_MS);
}

function stopLiveMode(): void {
  isLiveMode = false;
  if (liveIntervalId) {
    clearInterval(liveIntervalId);
    liveIntervalId = null;
  }
  liveToggleBtn.classList.remove('active');
  liveBadge.style.display = 'none';
  captureBtn.classList.remove('live');
  captureBtn.innerHTML = `
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" width="28" height="28"><path d="M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 1 1 7.072 0l-.548.547A3.374 3.374 0 0 0 12 18.469V19" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>
  `;

  console.log('[Vision] Live mode stopped');
}

// ---------------------------------------------------------------------------
// Describe Current Frame
// ---------------------------------------------------------------------------

async function describeCurrent(prompt: string, maxTokens: number): Promise<void> {
  if (isProcessing) return;

  const loaded = ModelManager.getLoadedModel('multimodal');
  if (!loaded) {
    openModelSheet();
    return;
  }

  const frame = captureFrame();
  if (!frame) {
    descriptionEl.innerHTML = `<span style="color:var(--text-tertiary);">No camera frame available. Make sure the camera is active.</span>`;
    return;
  }

  await processFrame(frame, prompt, maxTokens);
}

/**
 * Process raw RGB pixel data with the VLM.
 * Mirrors the iOS flow: CVPixelBuffer → RGB pixels → rac_vlm_image_t
 */
async function processFrame(frame: CapturedFrame, prompt: string, maxTokens: number): Promise<void> {
  isProcessing = true;
  processingOverlay.style.display = 'flex';

  try {
    const { VLM, VLMImageFormat } = await import(
      '../../../../../sdk/runanywhere-web/packages/core/src/index'
    );

    if (!VLM.isModelLoaded) {
      throw new Error('VLM model not loaded in WASM backend');
    }

    const result = await VLM.process(
      {
        format: VLMImageFormat.RGBPixels,
        pixelData: frame.rgbPixels,
        width: frame.width,
        height: frame.height,
      },
      prompt,
      { maxTokens, temperature: 0.7 },
    );

    // Update description (smooth replace for live mode)
    currentDescription = result.text;
    descriptionEl.textContent = currentDescription;
    copyBtn.style.display = currentDescription ? '' : 'none';

    // Show metrics
    metricsEl.style.display = 'flex';
    metricsEl.innerHTML = `
      <span class="metric"><span class="metric-value">${result.tokensPerSecond.toFixed(1)}</span> tok/s</span>
      <span class="metric-separator">&middot;</span>
      <span class="metric"><span class="metric-value">${result.totalTokens}</span> tokens</span>
      <span class="metric-separator">&middot;</span>
      <span class="metric"><span class="metric-value">${(result.totalTimeMs / 1000).toFixed(1)}s</span></span>
    `;

    console.log(
      `[Vision] VLM: ${result.totalTokens} tokens, ${result.tokensPerSecond.toFixed(1)} tok/s`,
    );
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error('[Vision] VLM failed:', msg);
    // In live mode, suppress errors to avoid disrupting the stream
    if (!isLiveMode) {
      descriptionEl.innerHTML = `<span style="color:var(--color-red);">Error: ${escapeHtml(msg)}</span>`;
    }
  }

  isProcessing = false;
  processingOverlay.style.display = 'none';
}

// ---------------------------------------------------------------------------
// Photo Upload (fallback)
// ---------------------------------------------------------------------------

async function handlePhotoUpload(file: File): Promise<void> {
  // Load the image into an Image element, draw to canvas, extract RGB pixels
  const img = new Image();
  const objectUrl = URL.createObjectURL(file);

  img.onload = () => {
    URL.revokeObjectURL(objectUrl);

    canvasEl.width = img.naturalWidth;
    canvasEl.height = img.naturalHeight;
    const ctx = canvasEl.getContext('2d');
    if (!ctx) return;

    ctx.drawImage(img, 0, 0);
    const frame = extractRGBFromCanvas(ctx, canvasEl.width, canvasEl.height);
    processFrame(frame, SINGLE_SHOT_PROMPT, SINGLE_SHOT_MAX_TOKENS);
  };

  img.src = objectUrl;
}

// ---------------------------------------------------------------------------
// Copy Description
// ---------------------------------------------------------------------------

function copyDescription(): void {
  if (!currentDescription) return;
  navigator.clipboard.writeText(currentDescription).then(() => {
    console.log('[Vision] Description copied to clipboard');
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
