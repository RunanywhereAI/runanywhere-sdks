/**
 * Transcribe Tab — V2 canonical proto-byte STT.
 *
 * Mirrors iOS `STTViewModel` with a Batch / Live mode toggle (iOS parity:
 * STTViewModel.swift:43-61 `selectedMode`):
 *
 *  - Batch (STTViewModel.swift:241-261): record, then one-shot
 *    `RunAnywhere.stt.transcribe(audio)`.
 *  - Live (STTViewModel.swift:365-408): the SDK streaming session emits
 *    partial hypotheses (`isFinal=false`) that preview the utterance and a
 *    final result (`isFinal=true`) that replaces them.
 *
 * A file-upload affordance is kept as a justified web addition (browsers
 * have first-class file pickers; decoding goes through `AudioFileLoader`).
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  type AudioInput,
} from '@runanywhere/web';
import {
  AudioCapture,
  AudioFileLoader,
} from '@runanywhere/web/browser';
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
import { renderFileDrop, wireFileDrop } from '../components/file-drop';
import { icon } from '../components/icons';
import { onEngineStateChange } from '../services/engine-availability';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const STT_PICKER_FILTER: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
];

/** UI mode — mirrors iOS `STTMode` (STTViewModel.swift:442-462; hybrid is
 * cloud-router-only and not exposed on web). */
type STTMode = 'batch' | 'live';

let container: HTMLElement;
let unmounted = false;
let audioCapture: AudioCapture | null = null;
let isCapturing = false;
let isProcessing = false;
let selectedMode: STTMode = 'batch';
let transcript = '';
/** True while the on-screen transcript is a revisable hypothesis, not a result. */
let isTranscriptPartial = false;
/**
 * The status line, held in view state rather than only written into the DOM.
 *
 * Every flow ends by re-rendering, and a render rebuilds the status element
 * from scratch — so an outcome poked straight into the node ("Done.", "No
 * speech detected.", "Transcribe failed: …") was erased microseconds after it
 * was set, and a finished recording explained itself to nobody. Rendering the
 * message from state is what makes it survive the render that follows it.
 */
let statusText = '';
let unsubscribeState: (() => void) | null = null;
let unsubscribeEngine: (() => void) | null = null;

/**
 * Push-queue bridging mic chunk callbacks into the SDK's audio iterable, the
 * same shape `views/vad.ts` uses.
 *
 * Live mode used to record the whole utterance and then hand the finished
 * buffer to `transcribeStream` as a single chunk, so a mode advertising "shows
 * words as they are recognised" produced exactly one update, after the
 * microphone had already closed. Feeding the session while capture is running
 * is what makes the label true — and matches iOS/Android, where the mic pump
 * and the streaming session run concurrently.
 */
let chunkQueue: Float32Array[] = [];
let notifyChunk: (() => void) | null = null;
let streamDone = false;
let liveStreamTask: Promise<void> | null = null;

export function initTranscribeTab(el: HTMLElement): TabLifecycle {
  container = el;
  unmounted = false;
  renderTranscribe();
  unsubscribeState = onModelStateChange(() => {
    if (!unmounted) renderTranscribe();
  });
  // A successful engine retry must restore the recording controls without the
  // user having to leave the tab and come back.
  unsubscribeEngine = onEngineStateChange(() => {
    if (!unmounted) renderTranscribe();
  });
  return {
    // app.ts fires onDeactivate on every tab switch (not only on panel
    // teardown). Treat the flag as a "currently inactive" guard for
    // in-flight async renders and reset it on re-activation so a returning
    // user doesn't see stale microphone / processing state.
    onActivate: () => {
      unmounted = false;
      renderTranscribe();
    },
    onDeactivate: () => {
      unmounted = true;
      audioCapture?.stop();
      audioCapture = null;
      isCapturing = false;
      // Release the live session's chunk source too, or `micChunks` parks on a
      // promise no capture will ever resolve and the session never closes.
      streamDone = true;
      notifyChunk?.();
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
 * What each mode means, in the user's terms rather than the SDK verb's.
 *
 * The live wording is deliberately specific about *when* words appear. The mode
 * used to claim "Shows words as they are recognised" while showing nothing at
 * all until the microphone closed; now the SDK re-reads the audio captured so
 * far while capture is open, so a first guess lands about a second in and is
 * rewritten as more of the sentence arrives. Saying "guess" and naming the
 * settle point is what keeps the sentence true of a whole-window model like
 * Whisper, which revises words it has already shown.
 */
const MODE_COPY: Record<STTMode, { label: string; detail: string }> = {
  batch: {
    label: 'Record, then transcribe',
    detail: 'Records everything first, then transcribes it in one pass. Most accurate.',
  },
  live: {
    label: 'Transcribe as I speak',
    detail: 'Shows a running guess about a second in and rewrites it as you keep talking. '
      + 'The transcript settles when you stop.',
  },
};

/**
 * Why this doesn't consult `RunAnywhere.runtime.modalities.stt`.
 *
 * That property answers *where* STT would run (worker vs main thread), not
 * *whether* a speech engine registered — with no engine at all it still reports
 * `'main'`. Gating on it meant this view rendered an enabled "Start recording"
 * and the message "Load an STT model first" on a session where the ONNX/Sherpa
 * WASM artifact had failed to load, so no STT model could ever appear in the
 * picker. The registration outcome in `engine-availability` is the real signal.
 */
function renderTranscribe(): void {
  const notice = engineNoticeForCategories(STT_PICKER_FILTER);
  const blocked = isEngineBlocked(notice);
  const loadedModel = findLoadedModelForCategory(
    ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
  );
  const modelLabel = loadedModel?.name ?? 'Choose a model';
  const canRunInference = !blocked && Boolean(loadedModel);
  const busy = isCapturing || isProcessing;

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Transcribe</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="transcribe-model-btn" ${blocked ? 'disabled' : ''}>${escapeHtml(modelLabel)}</button>
      </div>
    </div>
    <div class="scroll-area">
      ${renderEngineNotice(notice)}
      <div class="docs-section">
        <h3>How to listen</h3>
        <div class="segmented" role="radiogroup" aria-label="Transcription mode">
          ${(['batch', 'live'] as const).map((mode) => `
            <button type="button" class="segmented__option" id="mode-${mode}-btn"
              role="radio" aria-checked="${selectedMode === mode}"
              ${busy || blocked ? 'disabled' : ''}>${MODE_COPY[mode].label}</button>
          `).join('')}
        </div>
        <p class="text-secondary">${MODE_COPY[selectedMode].detail}</p>
      </div>
      <div class="docs-section">
        <h3>Record</h3>
        <div class="toolbar-actions">
          <button class="btn ${isCapturing ? 'btn-secondary' : 'btn-primary'}" id="mic-toggle-btn" ${isProcessing || !canRunInference ? 'disabled' : ''}>
            ${isCapturing ? 'Stop and transcribe' : 'Start recording'}
          </button>
          <button class="btn btn-secondary" id="clear-btn" ${isProcessing || !transcript ? 'disabled' : ''}>Clear</button>
        </div>
        ${!blocked && !loadedModel
          ? '<div class="docs-status">Choose a model to start transcribing.</div>'
          : ''}
      </div>
      <div class="docs-section">
        <h3>Or use a recording</h3>
        ${renderFileDrop({
          id: 'transcribe-drop',
          accept: 'audio/*',
          title: 'Drop an audio file here, or click to choose',
          hint: 'WAV, MP3, M4A, OGG, FLAC and other formats your browser can decode',
          disabled: isProcessing || !canRunInference,
        })}
      </div>
      <div class="docs-section">
        <h3>Transcript</h3>
        <div id="transcribe-status" class="docs-status" role="status" aria-live="polite">${escapeHtml(statusText)}</div>
        ${transcript
          ? `<pre id="transcribe-output" class="docs-pre${isTranscriptPartial ? ' docs-pre--partial' : ''}">${escapeHtml(transcript)}</pre>`
          : `<div class="surface-empty" id="transcribe-output">
               ${icon('waveform', { size: 24 })}
               <p>Your transcript will appear here.</p>
             </div>`}
      </div>
    </div>
  `;

  wireEngineNotice(container, notice);

  container.querySelector('#transcribe-model-btn')?.addEventListener('click', () => {
    openSheet({
      title: 'Choose a transcription model',
      filterCategories: STT_PICKER_FILTER,
    });
  });

  for (const mode of ['batch', 'live'] as const) {
    container.querySelector(`#mode-${mode}-btn`)?.addEventListener('click', () => {
      // Clear the previous mode's result: leaving it on screen under the new
      // mode's description attributes one mode's output to another.
      if (selectedMode !== mode) {
        transcript = '';
        isTranscriptPartial = false;
        statusText = '';
      }
      selectedMode = mode;
      renderTranscribe();
    });
  }
  container.querySelector('#mic-toggle-btn')?.addEventListener('click', () => {
    void toggleMic();
  });
  container.querySelector('#clear-btn')?.addEventListener('click', () => {
    transcript = '';
    isTranscriptPartial = false;
    statusText = '';
    renderTranscribe();
  });
  wireFileDrop(container, 'transcribe-drop', (files) => {
    const file = files[0];
    if (file) void transcribeFile(file);
  });
}

async function toggleMic(): Promise<void> {
  if (isCapturing) {
    await stopMicAndTranscribe();
    return;
  }
  await startMic();
}

async function startMic(): Promise<void> {
  audioCapture = audioCapture ?? new AudioCapture({ sampleRate: 16000 });
  const live = selectedMode === 'live';
  chunkQueue = [];
  streamDone = false;
  try {
    // Live mode opens the streaming session alongside capture and pushes every
    // mic chunk into it as it arrives; batch mode only accumulates and runs one
    // pass on stop.
    await audioCapture.start(live
      ? (chunk) => {
        chunkQueue.push(chunk);
        notifyChunk?.();
      }
      : undefined);
    isCapturing = true;
    transcript = '';
    isTranscriptPartial = false;
    // Set before the render so the previous run's outcome ("Done.", "No speech
    // detected.") cannot sit over a recording that has just started.
    statusText = live
      ? 'Listening — the first guess appears about a second in.'
      : 'Recording — press stop when you have finished speaking.';
    renderTranscribe();
    if (live) liveStreamTask = runTranscribeStream();
  } catch (err) {
    streamDone = true;
    setStatus(`Microphone error: ${formatError(err)}`);
  }
}

async function stopMicAndTranscribe(): Promise<void> {
  if (!audioCapture) return;
  const samples = audioCapture.getAudioBuffer();
  audioCapture.stop();
  isCapturing = false;

  if (selectedMode === 'live') {
    // Close the chunk source and let the session drain to its final result.
    // `isProcessing` covers that window so the controls stay busy until the
    // final has replaced the last partial, rather than re-enabling over a
    // transcript that is still a hypothesis.
    streamDone = true;
    notifyChunk?.();
    isProcessing = true;
    setStatus('Settling the transcript…');
    renderTranscribe();
    await liveStreamTask;
    liveStreamTask = null;
    return;
  }

  if (samples.length === 0) {
    setStatus('No audio captured.');
    renderTranscribe();
    return;
  }
  await runTranscribe(samples);
}

/**
 * A recording is always transcribed in one pass, whichever mode is selected:
 * there is no live capture to follow, so streaming a finished buffer would be
 * batch transcription wearing a streaming label.
 */
async function transcribeFile(file: File): Promise<void> {
  isProcessing = true;
  renderTranscribe();
  try {
    const decoded = await AudioFileLoader.toFloat32Array(file, 16000);
    await runTranscribe(decoded.samples);
  } catch (err) {
    setStatus(`Failed to decode file: ${formatError(err)}`);
  } finally {
    isProcessing = false;
    renderTranscribe();
  }
}

/** Batch mode — one-shot transcription (iOS parity: STTViewModel.swift:252). */
async function runTranscribe(samples: Float32Array): Promise<void> {
  isProcessing = true;
  setStatus(`Transcribing ${(samples.length / 16000).toFixed(2)}s of audio...`);
  renderTranscribe();
  try {
    const output = await RunAnywhere.stt.transcribe(RunAnywhere.AudioInput.float32(samples));
    transcript = output.text;
    // "Recorded, nothing recognised" is a different fact from "nothing recorded
    // yet", and the empty pane alone cannot tell them apart. Same distinction
    // iOS and Android draw.
    setStatus(transcript ? 'Done.' : 'No speech detected in that recording.');
  } catch (err) {
    setStatus(`Transcribe failed: ${formatError(err)}`);
  } finally {
    isProcessing = false;
    renderTranscribe();
  }
}

/** Bridge the push-style mic callback into the SDK's pull-style iterable. */
async function* micChunks(): AsyncGenerator<AudioInput> {
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
  // Drain whatever the microphone delivered between the stop and this point, so
  // the tail of the utterance still reaches the session.
  let tail = chunkQueue.shift();
  while (tail) {
    yield RunAnywhere.AudioInput.float32(tail);
    tail = chunkQueue.shift();
  }
}

/**
 * Live mode — runs for the whole of capture, emitting `partial` hypotheses as
 * words are recognised and a `transcriptFinal` that replaces them. Failures
 * throw into this loop rather than arriving as a terminal partial.
 *
 * Partials are rendered in the revisable style so a guess on screen is never
 * mistaken for a settled result; the final clears that marking.
 */
async function runTranscribeStream(): Promise<void> {
  try {
    transcript = '';
    isTranscriptPartial = false;
    for await (const event of RunAnywhere.stt.transcribeStream(micChunks())) {
      if (event.type === 'partial') {
        const text = event.alternatives[0]?.text.trim();
        if (text) {
          transcript = text;
          isTranscriptPartial = true;
          updateOutput();
        }
      } else if (event.type === 'transcriptFinal') {
        transcript = event.segment.text.trim();
        isTranscriptPartial = false;
        updateOutput();
      }
    }
    setStatus(transcript ? 'Done.' : 'No speech detected.');
  } catch (err) {
    setStatus(`Transcribe failed: ${formatError(err)}`);
  } finally {
    isProcessing = false;
    isTranscriptPartial = false;
    renderTranscribe();
  }
}

/**
 * Push a streaming partial into the transcript element.
 *
 * The empty state is a different element from the transcript, so the first
 * partial has to swap them — writing `textContent` into the empty-state block
 * would erase its icon and leave a bare line of text. The swap is done in place
 * rather than by re-rendering the panel: a full render mid-utterance rebuilds
 * the toolbar and the drop zone and resets the status line, so the "listening"
 * message vanished at exactly the moment the first words arrived. Later
 * partials just mutate the `<pre>`.
 */
function updateOutput(): void {
  const existing = container.querySelector<HTMLElement>('#transcribe-output');
  if (!existing) {
    renderTranscribe();
    return;
  }
  const pre = existing instanceof HTMLPreElement
    ? existing
    : swapEmptyStateForTranscript(existing);
  pre.textContent = transcript;
  // Same treatment the Talk panel gives a revisable hypothesis, so a partial
  // reads as one on both screens instead of only on one of them.
  pre.classList.toggle('docs-pre--partial', isTranscriptPartial);
}

/** Swap the waveform empty state for the transcript block that supersedes it. */
function swapEmptyStateForTranscript(emptyState: HTMLElement): HTMLPreElement {
  const pre = document.createElement('pre');
  pre.id = 'transcribe-output';
  pre.className = 'docs-pre';
  emptyState.replaceWith(pre);
  return pre;
}

/** Record the status in view state and patch it in without a full render. */
function setStatus(text: string): void {
  statusText = text;
  const banner = container.querySelector<HTMLDivElement>('#transcribe-status');
  if (banner) banner.textContent = text;
}
