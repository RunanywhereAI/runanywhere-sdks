/**
 * VAD Tab — voice activity detection through the public SDK surface.
 *
 * Mirrors iOS `VADViewModel`: mic chunks are fed straight into the SDK's
 * `RunAnywhere.streamVAD` session — the SDK owns model framing, no app-side
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
  type VADResult,
} from '@runanywhere/web';
import { AudioCapture } from '@runanywhere/web/browser';
import {
  findLoadedModelForCategory,
  onModelStateChange,
  openSheet,
} from '../components/model-selection';
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
let lastResult: VADResult | null = null;
let lastError: string | null = null;
let activityLog: ActivityLogEntry[] = [];
let unsubscribeState: (() => void) | null = null;

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
  return {
    onActivate: () => {
      unmounted = false;
      renderVad();
    },
    onDeactivate: () => {
      unmounted = true;
      stopListening();
      if (!container.isConnected && unsubscribeState) {
        unsubscribeState();
        unsubscribeState = null;
      }
    },
  };
}

function renderVad(): void {
  const loadedModel = findLoadedModelForCategory(
    ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
  );
  const modelLabel = loadedModel?.name ?? 'Select VAD Model';
  const canListen = Boolean(loadedModel);

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">VAD</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="vad-model-btn">${escapeHtml(modelLabel)}</button>
      </div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Voice activity detection</h3>
        <p class="text-secondary">Mic chunks are fed into
        <code>RunAnywhere.streamVAD(...)</code>; the SDK owns model framing
        and emits one result per chunk.</p>
        <div class="toolbar-actions">
          <button class="btn btn-primary" id="vad-toggle-btn" ${canListen ? '' : 'disabled'}>
            ${isListening ? 'Stop listening' : 'Start listening'}
          </button>
          <button class="btn btn-secondary" id="vad-clear-btn">Clear log</button>
        </div>
        ${canListen ? '' : '<div class="docs-status">Load a VAD model (e.g. Silero VAD) first.</div>'}
        ${lastError ? `<div class="docs-status error">Error: ${escapeHtml(lastError)}</div>` : ''}
      </div>

      <div class="docs-section">
        <h3>Status</h3>
        <div class="docs-status">
          <span id="vad-speech-pill" class="badge ${isSpeechDetected ? 'badge-green' : 'badge-grey'}">
            ${isSpeechDetected ? 'Speech detected' : isListening ? 'No speech' : 'Idle'}
          </span>
        </div>
        <ul class="feature-unavailable__list" id="vad-stats">
          <li><strong>Confidence:</strong> <code id="vad-confidence">${lastResult ? lastResult.confidence.toFixed(3) : '-'}</code></li>
          <li><strong>Energy (RMS):</strong> <code id="vad-energy">${lastResult ? lastResult.energy.toFixed(4) : '-'}</code></li>
          <li><strong>Frame:</strong> <code id="vad-frame">${lastResult ? `${lastResult.durationMs} ms` : '-'}</code></li>
        </ul>
      </div>

      <div class="docs-section">
        <h3>Activity log</h3>
        <ul class="docs-list" id="vad-log">
          ${activityLog.length === 0
            ? '<li class="docs-empty">No speech activity yet</li>'
            : activityLog.map((entry) => `
                <li class="docs-item">
                  <div>
                    <div class="docs-item-title">${entry.label}</div>
                    <div class="docs-item-meta">${entry.timestamp.toLocaleTimeString()}</div>
                  </div>
                </li>`).join('')}
        </ul>
      </div>
    </div>
  `;

  container.querySelector('#vad-model-btn')?.addEventListener('click', () => {
    openSheet({
      title: 'Select VAD Model',
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
    lastError = 'No VAD model loaded';
    renderVad();
    return;
  }

  chunkQueue = [];
  streamDone = false;

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
async function* micChunks(): AsyncIterable<Float32Array> {
  while (!streamDone) {
    const next = chunkQueue.shift();
    if (next) {
      yield next;
      continue;
    }
    await new Promise<void>((resolve) => {
      notifyChunk = resolve;
    });
    notifyChunk = null;
  }
}

/**
 * Consume the SDK's streaming VAD session: one `VADResult` per mic chunk,
 * with speech-state transitions logged for the activity list (iOS parity:
 * VADViewModel.swift:175-203 `startDetectionStream`).
 */
async function consumeDetectionStream(): Promise<void> {
  let wasSpeechActive = false;
  try {
    for await (const result of RunAnywhere.streamVAD(micChunks())) {
      if (unmounted || !isListening) break;

      if (result.errorMessage) {
        lastError = result.errorMessage;
        continue;
      }

      lastResult = result;
      isSpeechDetected = result.isSpeech;
      updateStatusRegions();

      // Log state transitions (iOS parity: VADViewModel.swift:193-200).
      if (result.isSpeech && !wasSpeechActive) {
        addLogEntry('Speech Started');
        wasSpeechActive = true;
      } else if (!result.isSpeech && wasSpeechActive) {
        addLogEntry('Speech Ended');
        wasSpeechActive = false;
      }
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
    pill.textContent = isSpeechDetected ? 'Speech detected' : isListening ? 'No speech' : 'Idle';
  }
  if (lastResult) {
    const conf = container.querySelector('#vad-confidence');
    if (conf) conf.textContent = lastResult.confidence.toFixed(3);
    const energy = container.querySelector('#vad-energy');
    if (energy) energy.textContent = lastResult.energy.toFixed(4);
    const frame = container.querySelector('#vad-frame');
    if (frame) frame.textContent = `${lastResult.durationMs} ms`;
  }
}
