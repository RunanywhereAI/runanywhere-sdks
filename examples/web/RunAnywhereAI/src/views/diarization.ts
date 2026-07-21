/**
 * Diarization Tab — standalone speaker diarization over the canonical
 * `RunAnywhere.diarize` facade (NVIDIA Streaming Sortformer). Offline only:
 * the Web SDK exposes no `diarizeStream` verb yet.
 *
 * The Sortformer weights are released under the NVIDIA Open Model License. Like
 * the segmentation view, this view:
 *
 *   1. Renders the license text + an acceptance toggle. Accepting registers the
 *      ONNX Web backend for this browser session through the documented facade
 *      `ONNX.register(...)` — no app-side bridging into backend internals.
 *   2. Reports the SDK-owned lifecycle state for a loaded
 *      `.speakerDiarization` model. The Sortformer weights are user-supplied and
 *      uncataloged, so model supply/load is delegated to the SDK's model
 *      management (the shared model sheet) rather than reimplemented here.
 *   3. Accepts a user-picked or recorded audio clip, decodes it to 16 kHz mono
 *      PCM float samples, and runs `RunAnywhere.diarize(request)`.
 *   4. Renders the returned speaker segments (start / end / speaker) as a list.
 *
 * All inference, model routing, and license enforcement live in the SDK / C++
 * commons. This view is DOM state + thin facade calls only.
 */

import type { TabLifecycle } from '../app';
import { ModelCategory, RunAnywhere } from '@runanywhere/web';
import { AudioCapture, AudioFileLoader } from '@runanywhere/web/browser';
import { onModelStateChange, openSheet } from '../components/model-selection';
import {
  DiarizationAudioEncoding,
  type DiarizationResult,
  type DiarizationSegment,
} from '@runanywhere/proto-ts/diarization';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const DIAR_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
];

const SAMPLE_RATE = 16000;

const LICENSE_URL =
  'https://huggingface.co/nvidia/diar_streaming_sortformer_4spk-v2.1';

interface LoadedAudio {
  /** 16 kHz mono PCM float samples. */
  samples: Float32Array;
  label: string;
}

let container: HTMLElement;
let licenseAccepted = false;
let licenseBusy = false;
let audio: LoadedAudio | null = null;
let lastResult: DiarizationResult | null = null;
let status = '';
let isBusy = false;
let isCapturing = false;
let audioCapture: AudioCapture | null = null;
let unsubscribeState: (() => void) | null = null;

export function initDiarizationTab(el: HTMLElement): TabLifecycle {
  container = el;
  renderView();

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
    onDeactivate: () => {
      audioCapture?.stop();
      audioCapture = null;
      isCapturing = false;
    },
  };
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderView(): void {
  const modelLoaded = isDiarizationModelLoaded();
  const canRun = licenseAccepted && modelLoaded && audio !== null && !isBusy;

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Diarization</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="diar-model-btn" ${licenseAccepted ? '' : 'disabled'}>
          ${modelLoaded ? 'Change Model' : 'Load Diarization Model'}
        </button>
      </div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Model license</h3>
        <p class="text-secondary">
          Speaker-diarization weights (NVIDIA Streaming Sortformer) are released under the
          <strong>NVIDIA Open Model License</strong>:
          <a href="${LICENSE_URL}" target="_blank" rel="noopener noreferrer">Sortformer model card</a>.
          Accepting registers the ONNX diarization backend for this browser session and
          does not download any model.
        </p>
        <label class="form-check">
          <input type="checkbox" id="diar-license-toggle"
            ${licenseAccepted ? 'checked' : ''} ${licenseBusy ? 'disabled' : ''} />
          <span>I have read and accept the NVIDIA Sortformer Open Model License.</span>
        </label>
        <div id="diar-license-status" class="docs-status">${escapeHtml(licenseStatusLabel())}</div>
      </div>

      <div class="docs-section">
        <h3>Status</h3>
        <ul class="feature-unavailable__list">
          <li><code>license accepted</code>: <strong>${licenseAccepted ? 'yes' : 'no'}</strong></li>
          <li><code>diarization model loaded</code>: <strong>${modelLoaded ? 'yes' : 'no'}</strong></li>
        </ul>
        <p class="text-secondary">
          Sortformer weights are user-supplied and uncataloged. Supply and load them
          through the SDK's model management (the button above), then return here to run
          <code>RunAnywhere.diarize</code>.
        </p>
      </div>

      <div class="docs-section">
        <h3>Audio</h3>
        <p class="text-secondary">
          Pick an audio file with two or more speakers, or record a clip. It is decoded to
          16 kHz mono PCM float samples for the SDK.
        </p>
        <div class="toolbar-actions">
          <button class="btn btn-secondary" id="diar-mic-btn" ${licenseAccepted && !isBusy ? '' : 'disabled'}>
            ${isCapturing ? 'Stop recording' : 'Record'}
          </button>
          <input type="file" id="diar-file-input" accept="audio/*"
            ${licenseAccepted && !isBusy && !isCapturing ? '' : 'disabled'} />
        </div>
        <div id="diar-audio-meta" class="docs-status">${escapeHtml(audioMetaLabel())}</div>
      </div>

      <div class="docs-section">
        <h3>Diarize</h3>
        <p class="text-secondary">
          Runs <code>RunAnywhere.diarize(request)</code> on the loaded
          <code>.speakerDiarization</code> model and lists the speaker segments.
        </p>
        <div class="toolbar-actions">
          <button class="btn btn-primary" id="diar-run-btn" ${canRun ? '' : 'disabled'}>
            ${isBusy ? 'Diarizing…' : 'Run diarization'}
          </button>
        </div>
        <div id="diar-status" class="docs-status">${escapeHtml(status)}</div>
        <div id="diar-result"></div>
      </div>
    </div>
  `;

  reattachResult();

  container
    .querySelector('#diar-model-btn')!
    .addEventListener('click', () =>
      openSheet({
        title: 'Select Diarization Model',
        filterCategories: DIAR_PICKER_FILTER,
      }),
    );
  container
    .querySelector('#diar-license-toggle')!
    .addEventListener('change', (event) =>
      void onLicenseToggle(event.target as HTMLInputElement),
    );
  container
    .querySelector('#diar-mic-btn')!
    .addEventListener('click', () => void toggleMic());
  const fileInput = container.querySelector<HTMLInputElement>('#diar-file-input')!;
  fileInput.addEventListener('change', () => void onAudioFileSelected(fileInput));
  container
    .querySelector('#diar-run-btn')!
    .addEventListener('click', () => void onRun());
}

function licenseStatusLabel(): string {
  if (licenseBusy) return 'Registering the ONNX diarization backend…';
  if (licenseAccepted) return 'License accepted for this session.';
  return 'License not yet accepted — diarization is disabled.';
}

function audioMetaLabel(): string {
  if (isCapturing) return 'Recording… tap Stop to finish.';
  if (!audio) return 'No audio loaded yet.';
  const seconds = (audio.samples.length / SAMPLE_RATE).toFixed(2);
  return `Loaded ${seconds}s of audio from ${audio.label}.`;
}

function reattachResult(): void {
  const host = container.querySelector<HTMLElement>('#diar-result');
  if (!host) return;
  host.innerHTML = '';
  if (!lastResult) return;
  host.appendChild(buildSegmentSummary(lastResult));
}

// ---------------------------------------------------------------------------
// License
// ---------------------------------------------------------------------------

async function onLicenseToggle(input: HTMLInputElement): Promise<void> {
  if (!input.checked) {
    // Acceptance cannot be revoked mid-session at the backend; reflect that
    // truthfully rather than pretend the toggle disables an already-loaded backend.
    input.checked = licenseAccepted;
    return;
  }
  licenseBusy = true;
  setLicenseStatus('Registering the ONNX diarization backend…');
  renderView();
  try {
    // The app-facing way to bring up the ONNX diarization backend: register it.
    // `register` is idempotent, so this is safe if ONNX is already registered
    // (e.g. for STT). Loading the Sortformer weights enforces the NVIDIA Open
    // Model License in the SDK / C++ commons; failures surface as a load error.
    const { ONNX } = await import('@runanywhere/web-onnx');
    await ONNX.register({ preferBackendWorker: true });
    licenseAccepted = true;
    setStatus('License accepted. Load a diarization model to continue.');
  } catch (err) {
    licenseAccepted = false;
    setStatus(`Could not register the diarization backend: ${formatError(err)}`);
  } finally {
    licenseBusy = false;
    renderView();
  }
}

// ---------------------------------------------------------------------------
// Audio
// ---------------------------------------------------------------------------

async function toggleMic(): Promise<void> {
  if (isCapturing) {
    await stopMic();
    return;
  }
  await startMic();
}

async function startMic(): Promise<void> {
  audioCapture = audioCapture ?? new AudioCapture({ sampleRate: SAMPLE_RATE });
  try {
    await audioCapture.start();
    isCapturing = true;
    audio = null;
    lastResult = null;
    setStatus('Recording…');
    renderView();
  } catch (err) {
    isCapturing = false;
    setStatus(`Microphone error: ${formatError(err)}`);
    renderView();
  }
}

async function stopMic(): Promise<void> {
  if (!audioCapture) return;
  const samples = audioCapture.getAudioBuffer();
  audioCapture.stop();
  audioCapture = null;
  isCapturing = false;
  if (samples.length === 0) {
    setStatus('No audio captured.');
    renderView();
    return;
  }
  audio = { samples, label: 'microphone' };
  setStatus(`Recorded ${(samples.length / SAMPLE_RATE).toFixed(2)}s of audio.`);
  renderView();
}

async function onAudioFileSelected(input: HTMLInputElement): Promise<void> {
  const file = input.files?.[0];
  input.value = '';
  if (!file) return;

  isBusy = true;
  setStatus('Loading audio…');
  renderView();
  try {
    const decoded = await AudioFileLoader.toFloat32Array(file, SAMPLE_RATE);
    audio = { samples: decoded.samples, label: file.name };
    lastResult = null;
    setStatus(`Loaded ${(decoded.samples.length / SAMPLE_RATE).toFixed(2)}s of audio from ${file.name}.`);
  } catch (err) {
    setStatus(`Failed to load audio: ${formatError(err)}`);
  } finally {
    isBusy = false;
    renderView();
  }
}

// ---------------------------------------------------------------------------
// Diarize
// ---------------------------------------------------------------------------

async function onRun(): Promise<void> {
  if (!licenseAccepted) {
    setStatus('Accept the Sortformer license first.');
    renderView();
    return;
  }
  if (!isDiarizationModelLoaded()) {
    setStatus('No diarization model is loaded. Load one from the model picker, then re-run.');
    renderView();
    return;
  }
  if (!audio) {
    setStatus('Load or record an audio clip first.');
    renderView();
    return;
  }

  isBusy = true;
  lastResult = null;
  setStatus('Running diarization…');
  renderView();

  try {
    const result = await RunAnywhere.diarize({
      audioData: floatSamplesToBytes(audio.samples),
      options: {
        sampleRateHz: SAMPLE_RATE,
        channelCount: 1,
        encoding: DiarizationAudioEncoding.DIARIZATION_AUDIO_ENCODING_PCM_F32_LE,
        minimumDurationMs: 0,
        mergeGapMs: 0,
      },
    });
    lastResult = result;
    setStatus(
      `Done — ${result.speakerCount} speakers, ${result.segments.length} segments in ` +
        `${Math.round(result.processingTimeMs)}ms (${escapeHtml(result.modelId)}).`,
    );
  } catch (err) {
    setStatus(`Diarization failed: ${formatError(err)}`);
  } finally {
    isBusy = false;
    renderView();
  }
}

/** Pack a Float32Array of PCM samples into little-endian F32 bytes. */
function floatSamplesToBytes(samples: Float32Array): Uint8Array {
  const bytes = new Uint8Array(samples.length * 4);
  new Float32Array(bytes.buffer).set(samples);
  return bytes;
}

// ---------------------------------------------------------------------------
// Result rendering
// ---------------------------------------------------------------------------

function buildSegmentSummary(result: DiarizationResult): HTMLElement {
  const section = document.createElement('div');
  section.className = 'docs-section';

  const heading = document.createElement('h3');
  heading.textContent = `Speakers · ${result.speakerCount}`;
  section.appendChild(heading);

  if (result.segments.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'text-secondary';
    empty.textContent = 'No speaker segments were returned.';
    section.appendChild(empty);
    return section;
  }

  const list = document.createElement('ul');
  list.className = 'feature-unavailable__list';
  const sorted = [...result.segments].sort(
    (a: DiarizationSegment, b: DiarizationSegment) => a.startMs - b.startMs,
  );
  for (const segment of sorted) {
    const item = document.createElement('li');
    const speaker = segment.speakerId || `Speaker ${segment.speakerIndex + 1}`;
    const duration = ((segment.endMs - segment.startMs) / 1000).toFixed(1);
    item.innerHTML =
      `<strong>${escapeHtml(speaker)}</strong> — ${formatMs(segment.startMs)} → ` +
      `${formatMs(segment.endMs)} (${duration}s)`;
    list.appendChild(item);
  }
  section.appendChild(list);
  return section;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function isDiarizationModelLoaded(): boolean {
  try {
    const current = RunAnywhere.currentModel({
      category: ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
      includeModelMetadata: false,
    });
    return Boolean(current?.found || current?.modelId);
  } catch {
    return false;
  }
}

function formatMs(ms: number): string {
  const totalSeconds = ms / 1000;
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds - minutes * 60;
  return `${minutes}:${seconds.toFixed(2).padStart(5, '0')}`;
}

function setStatus(text: string): void {
  status = text;
  const banner = container.querySelector<HTMLDivElement>('#diar-status');
  if (banner) banner.textContent = text;
}

function setLicenseStatus(text: string): void {
  const banner = container.querySelector<HTMLDivElement>('#diar-license-status');
  if (banner) banner.textContent = text;
}
