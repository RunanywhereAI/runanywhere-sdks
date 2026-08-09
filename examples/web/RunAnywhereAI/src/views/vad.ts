/**
 * VAD Tab — voice activity detection through the public SDK surface.
 *
 * Mirrors iOS `VADViewModel`: mic chunks are fed straight into the SDK's
 * `RunAnywhere.vad.detectStream` session — the SDK owns model framing, no app-side
 * buffer math (iOS parity: VADViewModel.swift:30-33, :175-203). Speech
 * state transitions are logged into an activity list capped at 50 entries
 * (iOS parity: VADViewModel.swift:212-220).
 *
 * `AudioCapture` already delivers Float32 PCM, so no app-side conversion is
 * needed (iOS feeds `RunAnywhere.pcm16ToFloat32(audioData)` because its mic
 * pump emits Int16 bytes — VADViewModel.swift:150).
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  type AudioInput,
  type VadEvent,
} from '@runanywhere/web';
import { AudioCapture } from '@runanywhere/web/browser';
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

const VAD_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
];

interface ActivityLogEntry {
  label: 'Speech Started' | 'Speech Ended';
  timestamp: Date;
}

let container: HTMLElement;
let unmounted = false;
let audioCapture: AudioCapture | null = null;
let isListening = false;
let isSpeechDetected = false;
let lastResult: Extract<VadEvent, { type: 'activity' }> | null = null;
let lastError: string | null = null;
let activityLog: ActivityLogEntry[] = [];
let unsubscribeState: (() => void) | null = null;
let unsubscribeEngine: (() => void) | null = null;
/**
 * Wall clock of the first frame of this listening session.
 *
 * `VADResult.timestampMs` is commons' `rac_get_current_time_ms()` — a Unix
 * epoch, which this view was printing verbatim under a heading that reads
 * "Position". "1786231282799 ms" is not a position in anything the reader can
 * see. Anchoring on the first frame turns it into what the label promises:
 * how far into the session this reading is.
 */
let sessionOriginMs: number | null = null;

/** Push-queue bridging mic chunk callbacks into the SDK's audio iterable. */
let chunkQueue: Float32Array[] = [];
let notifyChunk: (() => void) | null = null;
let streamDone = false;

export function initVadTab(el: HTMLElement): TabLifecycle {
  container = el;
  unmounted = false;
  renderVad();
  unsubscribeState = onModelStateChange(() => {
    if (!unmounted) renderVad();
  });
  // A successful engine retry must restore the listening control without the
  // user having to leave the tab and come back.
  unsubscribeEngine = onEngineStateChange(() => {
    if (!unmounted) renderVad();
  });
  return {
    onActivate: () => {
      unmounted = false;
      renderVad();
    },
    onDeactivate: () => {
      unmounted = true;
      stopListening();
      if (!container.isConnected) {
        unsubscribeState?.();
        unsubscribeState = null;
        unsubscribeEngine?.();
        unsubscribeEngine = null;
      }
    },
  };
}

/**
 * Why this asks `engine-availability` rather than trusting a loaded model.
 *
 * The only gate here used to be `Boolean(loadedModel)`, so on a session where
 * the ONNX/Sherpa WASM artifact failed to load this view showed an enabled
 * "Start listening" and the message "Load a VAD model (e.g. Silero VAD) first" —
 * pointing the user at a picker that could not offer one. Neither did it consult
 * `runtime.modalities.vad`, which would not have helped: that property reports
 * *where* VAD would run, and answers `'main'` even with no engine registered.
 *
 * The live readings render as a `<dl>` rather than reusing
 * `.feature-unavailable__list`, which they previously borrowed — live telemetry
 * had inherited the styling of a "this feature is missing" bullet list.
 */
function renderVad(): void {
  const notice = engineNoticeForCategories(VAD_PICKER_FILTER);
  const blocked = isEngineBlocked(notice);
  const loadedModel = findLoadedModelForCategory(
    ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
  );
  const modelLabel = loadedModel?.name ?? 'Choose a model';
  const canListen = !blocked && Boolean(loadedModel);

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Voice activity</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="vad-model-btn" ${blocked ? 'disabled' : ''}>${escapeHtml(modelLabel)}</button>
      </div>
    </div>
    <div class="scroll-area">
      ${renderEngineNotice(notice)}
      <div class="docs-section">
        <h3>Detect when someone is speaking</h3>
        <p class="text-secondary">Listens to the microphone and marks where speech starts and stops. Audio never leaves this device.</p>
        <div class="toolbar-actions">
          <button class="btn ${isListening ? 'btn-secondary' : 'btn-primary'}" id="vad-toggle-btn" ${canListen ? '' : 'disabled'}>
            ${isListening ? 'Stop listening' : 'Start listening'}
          </button>
          <button class="btn btn-secondary" id="vad-clear-btn" ${activityLog.length === 0 ? 'disabled' : ''}>Clear log</button>
        </div>
        ${!blocked && !loadedModel
          ? '<div class="docs-status">Choose a model to start listening.</div>'
          : ''}
        ${lastError ? `<div class="docs-status error" role="alert">${escapeHtml(lastError)}</div>` : ''}
      </div>

      <div class="docs-section">
        <h3>Live status</h3>
        <div class="docs-status">
          <span id="vad-speech-pill" class="badge ${isSpeechDetected ? 'badge-green' : 'badge-grey'}" role="status">
            ${isSpeechDetected ? 'Speech detected' : isListening ? 'Listening — silence' : 'Not listening'}
          </span>
        </div>
        <dl class="metric-grid" id="vad-stats">
          <div class="metric-grid__cell">
            <dt>Confidence</dt>
            <dd id="vad-confidence">${lastResult ? lastResult.probability.toFixed(3) : '—'}</dd>
          </div>
          <div class="metric-grid__cell">
            <dt>Position</dt>
            <dd id="vad-frame">${lastResult ? formatPosition(lastResult.timestampMs) : '—'}</dd>
          </div>
        </dl>
      </div>

      <div class="docs-section">
        <h3>Activity log</h3>
        ${activityLog.length === 0
          ? `<div class="surface-empty">
               ${icon('pulse', { size: 24 })}
               <p>Speech starts and stops will be listed here.</p>
             </div>`
          : `<ul class="docs-list" id="vad-log">
              ${activityLog.map((entry) => `
                <li class="docs-item">
                  <div>
                    <div class="docs-item-title">${entry.label}</div>
                    <div class="docs-item-meta">${entry.timestamp.toLocaleTimeString()}</div>
                  </div>
                </li>`).join('')}
            </ul>`}
      </div>
    </div>
  `;

  wireEngineNotice(container, notice);

  container.querySelector('#vad-model-btn')?.addEventListener('click', () => {
    openSheet({
      title: 'Choose a voice-activity model',
      filterCategories: VAD_PICKER_FILTER,
    });
  });
  container.querySelector('#vad-toggle-btn')?.addEventListener('click', () => {
    if (isListening) {
      stopListening();
      renderVad();
    } else {
      void startListening();
    }
  });
  container.querySelector('#vad-clear-btn')?.addEventListener('click', () => {
    activityLog = [];
    renderVad();
  });
}

// ---------------------------------------------------------------------------
// Listening control (iOS parity: VADViewModel.swift:134-171)
// ---------------------------------------------------------------------------

async function startListening(): Promise<void> {
  lastError = null;
  isSpeechDetected = false;
  lastResult = null;

  if (!findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION)) {
    lastError = 'Choose a voice-activity model before listening.';
    renderVad();
    return;
  }

  chunkQueue = [];
  streamDone = false;
  sessionOriginMs = null; // Each session's readings are measured from its own first frame.

  try {
    audioCapture = new AudioCapture({ sampleRate: 16000, channels: 1 });
    await audioCapture.start((chunk) => {
      // Mic chunks go straight into the SDK's streaming session; the queue
      // only bridges the callback API to the AsyncIterable the SDK expects.
      chunkQueue.push(chunk);
      notifyChunk?.();
    });
    isListening = true;
    renderVad();
    void consumeDetectionStream();
  } catch (err) {
    lastError = `Failed to start recording: ${formatError(err)}`;
    stopListening();
    renderVad();
  }
}

function stopListening(): void {
  if (audioCapture) {
    try { audioCapture.stop(); } catch { /* ignore */ }
    audioCapture = null;
  }
  streamDone = true;
  notifyChunk?.();
  isListening = false;
  isSpeechDetected = false;
}

/** Bridge the push-style mic callback into the SDK's pull-style iterable. */
async function* micChunks(): AsyncIterable<AudioInput> {
  while (!streamDone) {
    const next = chunkQueue.shift();
    if (next) {
      yield RunAnywhere.AudioInput.float32(next);
      continue;
    }
    await new Promise<void>((resolve) => {
      notifyChunk = resolve;
    });
    notifyChunk = null;
  }
}

/**
 * Consume the SDK's streaming VAD session. The SDK emits the speech-state
 * transitions directly, so the activity list no longer derives them.
 */
async function consumeDetectionStream(): Promise<void> {
  try {
    for await (const event of RunAnywhere.vad.detectStream(micChunks())) {
      if (unmounted || !isListening) break;

      if (event.type === 'speechStarted') {
        addLogEntry('Speech Started');
        continue;
      }
      if (event.type === 'speechEnded') {
        addLogEntry('Speech Ended');
        continue;
      }
      if (event.type === 'failed') {
        lastError = `VAD stream failed: ${formatError(event.error)}`;
        stopListening();
        renderVad();
        continue;
      }
      if (event.type !== 'activity') continue;
      lastResult = event;
      isSpeechDetected = event.isSpeech;
      updateStatusRegions();
    }
  } catch (err) {
    if (!unmounted) {
      lastError = `VAD stream failed: ${formatError(err)}`;
      stopListening();
      renderVad();
    }
  }
}

function addLogEntry(label: ActivityLogEntry['label']): void {
  activityLog.unshift({ label, timestamp: new Date() }); // Most recent first
  if (activityLog.length > 50) activityLog.pop(); // Keep log manageable
  renderVad();
}

/** Cheap incremental update for per-chunk results (avoids full re-render). */
function updateStatusRegions(): void {
  const pill = container.querySelector<HTMLSpanElement>('#vad-speech-pill');
  if (pill) {
    pill.className = `badge ${isSpeechDetected ? 'badge-green' : 'badge-grey'}`;
    pill.textContent = isSpeechDetected
      ? 'Speech detected'
      : isListening ? 'Listening — silence' : 'Not listening';
  }
  if (lastResult) {
    const conf = container.querySelector('#vad-confidence');
    if (conf) conf.textContent = lastResult.probability.toFixed(3);
    const frame = container.querySelector('#vad-frame');
    if (frame) frame.textContent = formatPosition(lastResult.timestampMs);
  }
}

/** How far into this listening session the reading sits, as `m:ss.d`. */
function formatPosition(timestampMs: number | undefined): string {
  if (!timestampMs) return '—';
  sessionOriginMs ??= timestampMs;
  const elapsedMs = Math.max(0, timestampMs - sessionOriginMs);
  // Round to the tenth that is actually displayed *before* splitting the minute off,
  // or 59.95–59.999 s renders as `0:60.0` — `toFixed(1)` rounds up to 60.0 while the
  // minute count still reads the unrounded value. Same defect at every minute boundary.
  const elapsedDeciseconds = Math.round(elapsedMs / 100);
  const minutes = Math.floor(elapsedDeciseconds / 600);
  const seconds = (elapsedDeciseconds % 600) / 10;
  return `${minutes}:${seconds.toFixed(1).padStart(4, '0')}`;
}
