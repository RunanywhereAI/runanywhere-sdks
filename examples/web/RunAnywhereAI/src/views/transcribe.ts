/**
 * Transcribe Tab - Speech-to-Text with Batch / Live modes
 * Mirrors iOS SpeechToTextView + STTViewModel.
 */

import type { TabLifecycle } from '../app';
import { AudioCapture, VAD, SpeechActivity } from '../../../../../sdk/runanywhere-web/packages/core/src/index';
import { ModelManager, ModelCategory, ensureVADLoaded, type ModelInfo } from '../services/model-manager';
import { showModelSelectionSheet } from '../components/model-selection';

let container: HTMLElement;

/** Shared AudioCapture instance for this view. */
const micCapture = new AudioCapture();

// ---------------------------------------------------------------------------
// STT State (matching iOS STTViewModel)
// ---------------------------------------------------------------------------

type STTMode = 'batch' | 'live';
type STTState = 'idle' | 'recording' | 'transcribing';

let sttMode: STTMode = 'batch';
let sttState: STTState = 'idle';
let sttTranscription = '';
let sttError = '';

/** Whether the SDK VAD is actively monitoring audio chunks. */
let liveVadActive = false;
/** Guard against concurrent live transcriptions. */
let isLiveTranscribing = false;
/** Unsubscribe function for VAD speech activity callback. */
let unsubscribeVAD: (() => void) | null = null;

// Minimum audio segment (samples at 16kHz) worth transcribing — ~0.5s
const MIN_BUFFER_SAMPLES = 8000;

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export function initTranscribeTab(el: HTMLElement): TabLifecycle {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-actions"></div>
      <div class="toolbar-model-btn" id="stt-toolbar-model" title="Tap to change model">
        <svg class="model-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M21 16V8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16z"/><polyline points="3.27 6.96 12 12.01 20.73 6.96"/><line x1="12" y1="22.08" x2="12" y2="12"/></svg>
        <span id="stt-toolbar-model-text">Select STT Model</span>
        <svg class="chevron" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>
      </div>
      <div class="toolbar-actions"></div>
    </div>

    <!-- Mode Toggle (Batch / Live) -->
    <div class="stt-mode-bar">
      <button class="stt-mode-btn active flex-1" id="stt-mode-batch">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14"><rect x="2" y="7" width="20" height="14" rx="2" ry="2"/><path d="M16 3h-8l-2 4h12z"/></svg>
        Batch
      </button>
      <button class="stt-mode-btn flex-1" id="stt-mode-live">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14"><path d="M2 13a2 2 0 0 0 2-2V7a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V4a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V7a2 2 0 0 1 2-2"/></svg>
        Live
      </button>
    </div>

    <!-- Main content area -->
    <div class="scroll-area stt-content" id="stt-content">
      <!-- Ready state -->
      <div id="stt-ready" class="stt-ready-state">
        <div class="stt-waveform-anim" id="stt-waveform-anim">
          <div class="stt-wave-bar"></div>
          <div class="stt-wave-bar"></div>
          <div class="stt-wave-bar"></div>
          <div class="stt-wave-bar"></div>
          <div class="stt-wave-bar"></div>
        </div>
        <h3 class="font-semibold">Ready to transcribe</h3>
        <p id="stt-mode-desc" class="helper-text text-center">Record first, then transcribe</p>
      </div>

      <!-- Transcription result area -->
      <div id="stt-result-area" class="stt-result-panel">
        <div class="stt-result-header">
          <span class="font-semibold text-md">Transcription</span>
          <span id="stt-status-badge" class="hidden"></span>
        </div>
        <div id="stt-result-text" class="content-panel"></div>
      </div>
    </div>

    <!-- Bottom controls -->
    <div class="stt-controls">
      <div id="stt-error" class="error-text hidden"></div>

      <div id="stt-level-bars" class="stt-level-container">
        <div class="stt-level-row">
          ${Array.from({ length: 20 }, () => '<div class="stt-level-bar"></div>').join('')}
        </div>
      </div>

      <button class="mic-btn mic-btn-lg" id="stt-mic-btn">
        <svg id="stt-mic-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="28" height="28">
          <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
          <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
          <line x1="12" y1="19" x2="12" y2="23"/>
          <line x1="8" y1="23" x2="16" y2="23"/>
        </svg>
      </button>
      <p id="stt-status-text" class="helper-text">Tap to start recording</p>
    </div>
  `;

  // Wire up controls
  container.querySelector('#stt-mode-batch')!.addEventListener('click', () => switchSTTMode('batch'));
  container.querySelector('#stt-mode-live')!.addEventListener('click', () => switchSTTMode('live'));
  container.querySelector('#stt-mic-btn')!.addEventListener('click', handleMicToggle);
  container.querySelector('#stt-toolbar-model')!.addEventListener('click', () =>
    showModelSelectionSheet(ModelCategory.SpeechRecognition),
  );

  // Subscribe to model changes so the pill label stays current
  ModelManager.onChange(onSTTModelsChanged);
  onSTTModelsChanged(ModelManager.getModels());

  return {
    onDeactivate(): void {
      if (micCapture.isCapturing) micCapture.stop();
      stopLiveVAD();
      sttState = 'idle';
      renderSTTUI();
    },
  };
}

// ---------------------------------------------------------------------------
// Model Selector
// ---------------------------------------------------------------------------

function onSTTModelsChanged(_models: ModelInfo[]): void {
  const loaded = ModelManager.getLoadedModel(ModelCategory.SpeechRecognition);
  const textSpan = container.querySelector('#stt-toolbar-model-text');
  if (textSpan) {
    textSpan.textContent = loaded ? loaded.name : 'Select STT Model';
  }
}

// ---------------------------------------------------------------------------
// Mode Toggle
// ---------------------------------------------------------------------------

function switchSTTMode(mode: STTMode): void {
  if (sttState === 'recording' || sttState === 'transcribing') return;
  sttMode = mode;

  container.querySelector('#stt-mode-batch')!.classList.toggle('active', mode === 'batch');
  container.querySelector('#stt-mode-live')!.classList.toggle('active', mode === 'live');

  container.querySelector('#stt-mode-desc')!.textContent =
    mode === 'batch' ? 'Record first, then transcribe' : 'Auto-transcribe on silence';
}

// ---------------------------------------------------------------------------
// Mic Toggle
// ---------------------------------------------------------------------------

async function handleMicToggle(): Promise<void> {
  if (sttState === 'transcribing') return;

  if (sttState === 'recording') {
    // ── Stop recording ──
    stopLiveVAD();

    if (sttMode === 'batch') {
      // Batch mode: stop recording, then transcribe entire buffer
      sttState = 'transcribing';
      renderSTTUI();
      await performBatchTranscription();
    } else {
      // Live mode: flush VAD to process any remaining audio
      VAD.flush();
      const finalSegment = VAD.popSpeechSegment();
      if (finalSegment && finalSegment.samples.length >= MIN_BUFFER_SAMPLES) {
        sttState = 'transcribing';
        renderSTTUI();
        try {
          const text = await transcribeAudio(finalSegment.samples, 16000);
          if (text && text.trim().length > 0) {
            sttTranscription += (sttTranscription.length > 0 ? '\n' : '') + text.trim();
          }
        } catch (err) {
          sttError = err instanceof Error ? err.message : String(err);
        }
      }
      VAD.reset();
    }

    micCapture.stop();
    isLiveTranscribing = false;
    sttState = 'idle';
    renderSTTUI();
  } else {
    // ── Start recording ──
    sttError = '';
    sttTranscription = '';
    isLiveTranscribing = false;

    // For live mode, ensure the Silero VAD model is loaded (auto-downloads, ~5MB)
    if (sttMode === 'live') {
      const statusText = container.querySelector('#stt-status-text')!;
      statusText.textContent = 'Loading VAD model...';
      const vadReady = await ensureVADLoaded();
      if (!vadReady) {
        sttError = 'Failed to load VAD model.';
        renderSTTUI();
        return;
      }
      VAD.reset();
    }

    try {
      if (sttMode === 'live') {
        // Live mode: feed audio chunks to SDK VAD
        await micCapture.start(onLiveChunk, (level) => updateLevelBars(level));
        startLiveVAD();
      } else {
        // Batch mode: just accumulate audio
        await micCapture.start(undefined, (level) => updateLevelBars(level));
      }
      sttState = 'recording';
      renderSTTUI();
    } catch {
      sttError = 'Microphone access denied. Please allow microphone access.';
      renderSTTUI();
    }
  }
}

// ---------------------------------------------------------------------------
// Transcription
// ---------------------------------------------------------------------------

async function performBatchTranscription(): Promise<void> {
  const audioBuffer = micCapture.getAudioBuffer();
  const actualRate = micCapture.actualSampleRate;
  const durationSec = audioBuffer.length / actualRate;

  console.log(`[Transcribe] Buffer: ${audioBuffer.length} samples, ${actualRate}Hz, ${durationSec.toFixed(1)}s`);

  if (audioBuffer.length < MIN_BUFFER_SAMPLES) {
    sttError = 'Recording too short. Please speak longer.';
    return;
  }

  try {
    const text = await transcribeAudio(audioBuffer, actualRate);
    if (text && text.trim().length > 0) {
      sttTranscription += (sttTranscription.length > 0 ? '\n' : '') + text.trim();
    } else {
      sttError = 'No speech detected. Try speaking louder or recording longer.';
    }
  } catch (err) {
    sttError = err instanceof Error ? err.message : String(err);
  }
  renderSTTUI();
}

async function transcribeAudio(pcmFloat32: Float32Array, sampleRate?: number): Promise<string> {
  const model = await ModelManager.ensureLoaded(ModelCategory.SpeechRecognition);
  if (!model) {
    throw new Error('No STT model available. Tap the model button (top right) to download one.');
  }

  const { STT } = await import('../../../../../sdk/runanywhere-web/packages/core/src/index');
  if (!STT.isModelLoaded) {
    throw new Error('STT model not loaded. Select and load a model first.');
  }

  const result = await STT.transcribe(pcmFloat32, { sampleRate });
  console.log(`[Transcribe] STT result: "${result.text}" (${result.processingTimeMs}ms)`);
  return result.text;
}

// ---------------------------------------------------------------------------
// Live VAD (uses SDK Silero VAD)
// ---------------------------------------------------------------------------

/** AudioCapture onChunk callback — feeds audio to the SDK VAD. */
function onLiveChunk(samples: Float32Array): void {
  if (!liveVadActive) return;

  VAD.processSamples(samples);

  // Pop completed speech segments and transcribe them
  let segment = VAD.popSpeechSegment();
  while (segment) {
    if (segment.samples.length >= MIN_BUFFER_SAMPLES) {
      const segSamples = segment.samples;
      console.log(`[LiveVAD] Speech segment: ${segSamples.length} samples (${(segSamples.length / 16000).toFixed(1)}s)`);
      transcribeLiveSegment(segSamples);
    }
    segment = VAD.popSpeechSegment();
  }
}

/** Transcribe a single live segment (async, guarded against concurrency). */
async function transcribeLiveSegment(samples: Float32Array): Promise<void> {
  if (isLiveTranscribing) {
    console.log('[LiveVAD] Skipping segment — previous transcription still in progress');
    return;
  }
  isLiveTranscribing = true;
  try {
    const text = await transcribeAudio(samples, 16000);
    if (text && text.trim().length > 0) {
      sttTranscription += (sttTranscription.length > 0 ? '\n' : '') + text.trim();
      console.log(`[LiveVAD] Transcription result: "${text.trim()}"`);
      renderSTTUI();
    }
  } catch (err) {
    sttError = err instanceof Error ? err.message : String(err);
    console.error('[LiveVAD] Transcription error:', sttError);
    renderSTTUI();
  } finally {
    isLiveTranscribing = false;
  }
}

function startLiveVAD(): void {
  liveVadActive = true;
  unsubscribeVAD = VAD.onSpeechActivity((activity) => {
    if (activity === SpeechActivity.Started) {
      console.log('[LiveVAD] Speech started (Silero)');
    } else if (activity === SpeechActivity.Ended) {
      console.log('[LiveVAD] Speech ended (Silero)');
    }
  });
  console.log('[LiveVAD] Started SDK VAD monitoring');
}

function stopLiveVAD(): void {
  liveVadActive = false;
  if (unsubscribeVAD) { unsubscribeVAD(); unsubscribeVAD = null; }
}

// ---------------------------------------------------------------------------
// UI Rendering
// ---------------------------------------------------------------------------

function updateLevelBars(level: number): void {
  // In live mode, use the SDK VAD for speech detection (much more accurate).
  // In batch mode, fall back to a simple energy threshold for visual feedback.
  const isSpeech = (sttMode === 'live' && liveVadActive)
    ? VAD.isSpeechActive
    : level > 0.02;

  const bars = container.querySelectorAll('.stt-level-bar') as NodeListOf<HTMLElement>;
  bars.forEach((bar) => {
    bar.style.height = (3 + Math.random() * level * 21) + 'px';
    bar.style.background = isSpeech ? 'var(--color-green)' : 'var(--bg-gray5)';
  });
}

function renderSTTUI(): void {
  const micBtn = container.querySelector('#stt-mic-btn') as HTMLElement;
  const micIcon = container.querySelector('#stt-mic-icon') as SVGElement;
  const statusText = container.querySelector('#stt-status-text')!;
  const readyArea = container.querySelector('#stt-ready') as HTMLElement;
  const resultArea = container.querySelector('#stt-result-area') as HTMLElement;
  const resultText = container.querySelector('#stt-result-text')!;
  const statusBadge = container.querySelector('#stt-status-badge') as HTMLElement;
  const errorEl = container.querySelector('#stt-error') as HTMLElement;
  const levelBars = container.querySelector('#stt-level-bars') as HTMLElement;

  // Error
  errorEl.classList.toggle('hidden', !sttError);
  if (sttError) errorEl.textContent = sttError;

  // Show/hide result area
  const hasResult = sttTranscription.length > 0 || sttState === 'transcribing';
  readyArea.style.display = hasResult ? 'none' : 'flex';
  resultArea.style.display = hasResult ? 'flex' : 'none';
  if (hasResult) resultText.textContent = sttTranscription || 'Transcribing...';

  // Level bars
  levelBars.style.display = sttState === 'recording' ? '' : 'none';

  // Status badge
  if (sttState === 'recording') {
    statusBadge.classList.remove('hidden');
    statusBadge.innerHTML = `<span class="status-badge recording"><span class="status-dot red pulse"></span> RECORDING</span>`;
  } else if (sttState === 'transcribing') {
    statusBadge.classList.remove('hidden');
    statusBadge.innerHTML = `<span class="status-badge processing"><span class="spinner"></span> TRANSCRIBING</span>`;
  } else {
    statusBadge.classList.add('hidden');
  }

  // Mic button appearance
  switch (sttState) {
    case 'idle':
      micBtn.classList.remove('listening');
      micBtn.style.background = 'var(--color-blue)';
      micBtn.style.opacity = '1';
      micBtn.style.pointerEvents = '';
      micIcon.innerHTML = `<path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/><path d="M19 10v2a7 7 0 0 1-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/>`;
      statusText.textContent = 'Tap to start recording';
      break;
    case 'recording':
      micBtn.classList.add('listening');
      micBtn.style.background = 'var(--color-red)';
      micIcon.innerHTML = `<rect x="6" y="6" width="12" height="12" rx="2"/>`;
      statusText.textContent = sttMode === 'batch'
        ? 'Recording... Tap to stop & transcribe'
        : 'Listening... Auto-transcribes on silence';
      break;
    case 'transcribing':
      micBtn.classList.remove('listening');
      micBtn.style.background = 'var(--color-primary)';
      micBtn.style.opacity = '0.6';
      micBtn.style.pointerEvents = 'none';
      micIcon.innerHTML = `<circle cx="12" cy="12" r="8" stroke-dasharray="40" stroke-dashoffset="10"><animateTransform attributeName="transform" type="rotate" from="0 12 12" to="360 12 12" dur="1s" repeatCount="indefinite"/></circle>`;
      statusText.textContent = 'Transcribing...';
      break;
  }
}
