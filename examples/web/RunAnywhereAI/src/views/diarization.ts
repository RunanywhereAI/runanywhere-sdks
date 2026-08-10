/**
 * Diarization Tab — standalone speaker diarization over the canonical
 * `RunAnywhere.diarization.diarize` facade (NVIDIA Streaming Sortformer). Offline only:
 * the Web SDK exposes no `diarizeStream` verb yet.
 *
 * TWO SCREENS, ONE VIEW. No browser engine registers the diarization capability
 * in this build, so the model catalog has no `.speakerDiarization` entry and the
 * shared sheet would open empty. The view therefore renders the designed
 * unavailable state (`components/modality-unavailable.ts`) whenever the catalog
 * can offer nothing — rather than the previous arrangement, where the full
 * working screen was drawn (a "Load Diarization Model" button, a recorder, a
 * permanently disabled Run) above a paragraph explaining that the picker it just
 * showed was empty.
 *
 * When a catalog entry does exist, the working flow below is what runs:
 *
 *   1. Reports the SDK-owned lifecycle state for a loaded
 *      `.speakerDiarization` model. Model supply/load is delegated to the SDK's
 *      model management (the shared model sheet) rather than reimplemented here.
 *   2. Accepts a user-picked or recorded audio clip, decodes it to 16 kHz mono
 *      PCM float samples, and runs `RunAnywhere.diarization.diarize(audio)`.
 *   3. Renders the returned speaker segments (start / end / speaker) as a list.
 *
 * All inference and model routing live in the SDK / C++ commons. This view is
 * DOM state + thin facade calls only.
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  type DiarizationResult,
  type SpeakerSegment,
} from '@runanywhere/web';
import { AudioCapture, AudioFileLoader } from '@runanywhere/web/browser';
import {
  findLoadedModelForCategory,
  onModelStateChange,
  openSheet,
} from '../components/model-selection';
import { renderModalityUnavailable } from '../components/modality-unavailable';
import { getCatalogForCategories } from '../services/model-catalog';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const DIAR_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION,
];

const SAMPLE_RATE = 16000;

interface LoadedAudio {
  /** 16 kHz mono PCM float samples. */
  samples: Float32Array;
  label: string;
}

let container: HTMLElement;
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

  // Same reasoning as Segmentation: an empty catalog means an empty picker, and
  // a picker in front of an empty sheet is a control that promises something it
  // cannot deliver.
  if (!modelLoaded && getCatalogForCategories(DIAR_PICKER_FILTER).length === 0) {
    renderUnavailable();
    return;
  }

  renderWorkflow(modelLoaded);
}

function renderUnavailable(): void {
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Diarization</div>
      <!-- Empty, but present: the toolbar is space-between, so without a
           third child the shell's injected Back button and the title get
           pushed to opposite edges. -->
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area">
      ${renderModalityUnavailable({
        glyph: 'speakers',
        title: 'Diarization',
        summary:
          'Diarization works out who spoke when, turning a recording of a conversation '
          + 'into a timeline of speaker turns with a start and end time for each.',
        requirements: [
          'No engine in this build serves it. ONNX/Sherpa covers speech recognition, '
            + 'speech synthesis and voice activity in the browser, but it does not '
            + 'publish a diarization capability.',
          'With no engine, the model catalog has no diarization model to list, so '
            + 'there is nothing to choose and no download to start.',
        ],
        verb: 'RunAnywhere.diarization.diarize(audio)',
        elsewhere:
          'Diarization does run today in the iOS and Android RunAnywhere apps, where '
          + 'the platform SDK ships an engine for it.',
      })}
    </div>
  `;
}

function renderWorkflow(modelLoaded: boolean): void {
  const canRun = modelLoaded && audio !== null && !isBusy;

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Diarization</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="diar-model-btn">
          ${modelLoaded ? 'Change Model' : 'Load Diarization Model'}
        </button>
      </div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Status</h3>
        <ul class="feature-unavailable__list">
          <li><code>diarization model loaded</code>: <strong>${modelLoaded ? 'yes' : 'no'}</strong></li>
        </ul>
        ${modelLoaded
          ? ''
          : '<p class="text-secondary">Choose a diarization model from the button above to enable the run.</p>'}
      </div>

      <div class="docs-section">
        <h3>Audio</h3>
        <p class="text-secondary">
          Pick an audio file with two or more speakers, or record a clip. It is decoded to
          16 kHz mono PCM float samples for the SDK.
        </p>
        <div class="docs-actions">
          <button class="btn btn-secondary" id="diar-mic-btn" ${!isBusy ? '' : 'disabled'}>
            ${isCapturing ? 'Stop recording' : 'Record'}
          </button>
          <input type="file" id="diar-file-input" accept="audio/*"
            ${!isBusy && !isCapturing ? '' : 'disabled'} />
        </div>
        <div id="diar-audio-meta" class="docs-status">${escapeHtml(audioMetaLabel())}</div>
      </div>

      <div class="docs-section">
        <h3>Diarize</h3>
        <p class="text-secondary">
          Runs <code>RunAnywhere.diarization.diarize(audio)</code> on the loaded
          <code>.speakerDiarization</code> model and lists the speaker segments.
        </p>
        <div class="docs-actions">
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
    .querySelector('#diar-mic-btn')!
    .addEventListener('click', () => void toggleMic());
  const fileInput = container.querySelector<HTMLInputElement>('#diar-file-input')!;
  fileInput.addEventListener('change', () => void onAudioFileSelected(fileInput));
  container
    .querySelector('#diar-run-btn')!
    .addEventListener('click', () => void onRun());
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
    const startedAt = performance.now();
    const result = await RunAnywhere.diarization.diarize(
      RunAnywhere.AudioInput.float32(audio.samples, SAMPLE_RATE),
    );
    lastResult = result;
    setStatus(
      `Done — ${result.speakerCount} speakers, ${result.segments.length} segments in ` +
        `${Math.round(performance.now() - startedAt)}ms.`,
    );
  } catch (err) {
    setStatus(`Diarization failed: ${formatError(err)}`);
  } finally {
    isBusy = false;
    renderView();
  }
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
    (a: SpeakerSegment, b: SpeakerSegment) => a.startMs - b.startMs,
  );
  for (const segment of sorted) {
    const item = document.createElement('li');
    const speaker = segment.speakerId;
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
  return findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION) !== null;
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
