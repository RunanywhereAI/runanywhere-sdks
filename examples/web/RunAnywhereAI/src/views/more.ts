/**
 * More Tab - Transcribe (STT), Speak (TTS), Storage management
 * Matches iOS MoreHubView with NavigationLink list.
 *
 * Transcribe sub-view mirrors iOS SpeechToTextView with Batch/Live toggle.
 */

import { AudioCapture } from '../../../../../sdk/runanywhere-web/packages/core/src/index';
import { ModelManager, ModelCategory } from '../services/model-manager';
import { showModelSelectionSheet } from '../components/model-selection';

let container: HTMLElement;

/** Shared AudioCapture instance for this view (replaces app-level MicCapture singleton). */
const micCapture = new AudioCapture();

// Funny texts for TTS "Surprise me" (matching iOS)
const SURPRISE_TEXTS = [
  "Why don't scientists trust atoms? Because they make up everything!",
  "I told my wife she was drawing her eyebrows too high. She looked surprised.",
  "Parallel lines have so much in common. It's a shame they'll never meet.",
  "I'm reading a book on anti-gravity. It's impossible to put down!",
  "Did you hear about the mathematician who's afraid of negative numbers? He'll stop at nothing to avoid them.",
  "What do you call a fake noodle? An impasta!",
  "I would tell you a construction joke, but I'm still working on it.",
];

// ---------------------------------------------------------------------------
// STT State (matching iOS STTViewModel)
// ---------------------------------------------------------------------------

type STTMode = 'batch' | 'live';
type STTState = 'idle' | 'recording' | 'transcribing';

let sttMode: STTMode = 'batch';
let sttState: STTState = 'idle';
let sttTranscription = '';
let sttError = '';
let sttModelLoaded = false;
let liveVadTimer: ReturnType<typeof setInterval> | null = null;

// VAD thresholds (matching iOS defaults)
const SPEECH_THRESHOLD = 0.02;
const SILENCE_DURATION_MS = 1500;
const MIN_BUFFER_BYTES = 16000; // ~0.5s at 16kHz float32

export function initMoreTab(el: HTMLElement): void {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">More</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area" id="more-content">
      <div class="feature-list">
        <div class="feature-row" id="more-transcribe-btn">
          <div class="feature-icon" style="background:var(--color-blue);">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22"><path d="M2 13a2 2 0 0 0 2-2V7a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V4a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V7a2 2 0 0 1 2-2"/></svg>
          </div>
          <div class="feature-text">
            <h3>Transcribe</h3>
            <p>Convert speech to text</p>
          </div>
        </div>
        <div class="feature-row" id="more-speak-btn">
          <div class="feature-icon" style="background:var(--color-green);">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/></svg>
          </div>
          <div class="feature-text">
            <h3>Speak</h3>
            <p>Convert text to speech</p>
          </div>
        </div>
        <div class="feature-row" id="more-storage-btn">
          <div class="feature-icon" style="background:var(--color-primary);">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="22" height="22"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
          </div>
          <div class="feature-text">
            <h3>Storage</h3>
            <p>Manage models and files</p>
          </div>
        </div>
      </div>
    </div>

    <!-- ================================================================= -->
    <!-- Transcribe Sub-view (matches iOS SpeechToTextView)                -->
    <!-- ================================================================= -->
    <div class="sub-view" id="more-transcribe-view">
      <div class="toolbar">
        <button class="back-btn" id="transcribe-back">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><polyline points="15 18 9 12 15 6"/></svg>
          More
        </button>
        <div class="toolbar-title">Speech to Text</div>
        <div class="toolbar-actions">
          <button class="btn btn-icon" id="stt-model-btn" title="Select Model" style="border:none;background:none;">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><path d="M9.75 3.104v5.714a2.25 2.25 0 0 1-.659 1.591L5 14.5M9.75 3.104c-.251.023-.501.05-.75.082m.75-.082a24.301 24.301 0 0 1 4.5 0m0 0v5.714c0 .597.237 1.17.659 1.591L19.8 15.3M14.25 3.104c.251.023.501.05.75.082M19.8 15.3l-1.57.393A9.065 9.065 0 0 1 12 15a9.065 9.065 0 0 0-6.23.693L5 14.5m14.8.8l1.402 1.402c1.232 1.232.65 3.318-1.067 3.611A48.309 48.309 0 0 1 12 21c-2.773 0-5.491-.235-8.135-.687-1.718-.293-2.3-2.379-1.067-3.61L5 14.5"/></svg>
          </button>
        </div>
      </div>

      <!-- Mode Toggle (Batch / Live) -->
      <div style="display:flex;gap:var(--space-sm);padding:var(--space-md) var(--space-lg);background:var(--bg-secondary);border-bottom:1px solid var(--border-light);">
        <button class="stt-mode-btn active" id="stt-mode-batch" style="flex:1;">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14"><rect x="2" y="7" width="20" height="14" rx="2" ry="2"/><path d="M16 3h-8l-2 4h12z"/></svg>
          Batch
        </button>
        <button class="stt-mode-btn" id="stt-mode-live" style="flex:1;">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="14" height="14"><path d="M2 13a2 2 0 0 0 2-2V7a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V4a2 2 0 0 1 4 0v13a2 2 0 0 0 4 0V7a2 2 0 0 1 2-2"/></svg>
          Live
        </button>
      </div>

      <!-- Main content area -->
      <div class="scroll-area" id="stt-content" style="flex:1;display:flex;flex-direction:column;">

        <!-- Ready state (no transcription yet) -->
        <div id="stt-ready" style="flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:var(--space-lg);padding:var(--space-3xl);">
          <!-- Animated waveform (breathing) -->
          <div class="stt-waveform-anim" id="stt-waveform-anim">
            <div class="stt-wave-bar"></div>
            <div class="stt-wave-bar"></div>
            <div class="stt-wave-bar"></div>
            <div class="stt-wave-bar"></div>
            <div class="stt-wave-bar"></div>
          </div>
          <h3 style="font-weight:var(--font-weight-semibold);">Ready to transcribe</h3>
          <p id="stt-mode-desc" style="color:var(--text-secondary);font-size:var(--font-size-sm);text-align:center;">Record first, then transcribe</p>
        </div>

        <!-- Transcription result area (hidden until there's text) -->
        <div id="stt-result-area" style="display:none;flex:1;padding:var(--space-lg);">
          <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:var(--space-md);">
            <span style="font-weight:var(--font-weight-semibold);font-size:var(--font-size-md);">Transcription</span>
            <span id="stt-status-badge" style="display:none;"></span>
          </div>
          <div id="stt-result-text" style="padding:var(--space-lg);background:var(--bg-secondary);border-radius:var(--radius-lg);min-height:100px;line-height:var(--line-height-relaxed);color:var(--text-primary);white-space:pre-wrap;"></div>
        </div>
      </div>

      <!-- Bottom controls (always visible) -->
      <div style="padding:var(--space-md) var(--space-lg) var(--space-xl);display:flex;flex-direction:column;align-items:center;gap:var(--space-md);border-top:1px solid var(--border-light);background:var(--bg-secondary);">
        <div id="stt-error" style="display:none;color:var(--color-red);font-size:var(--font-size-sm);text-align:center;"></div>

        <!-- Audio level bars -->
        <div id="stt-level-bars" style="display:none;width:100%;max-width:300px;">
          <div style="display:flex;align-items:center;gap:2px;height:24px;justify-content:center;">
            ${Array.from({ length: 20 }, () => '<div class="stt-level-bar" style="width:4px;height:3px;background:var(--color-green);border-radius:1px;transition:height 0.08s ease;"></div>').join('')}
          </div>
        </div>

        <!-- Mic button -->
        <button class="mic-btn" id="stt-mic-btn" style="width:72px;height:72px;">
          <svg id="stt-mic-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="28" height="28">
            <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
            <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
            <line x1="12" y1="19" x2="12" y2="23"/>
            <line x1="8" y1="23" x2="16" y2="23"/>
          </svg>
        </button>
        <p id="stt-status-text" style="color:var(--text-secondary);font-size:var(--font-size-sm);">Tap to start recording</p>
      </div>
    </div>

    <!-- ================================================================= -->
    <!-- Speak Sub-view                                                     -->
    <!-- ================================================================= -->
    <div class="sub-view" id="more-speak-view">
      <div class="toolbar">
        <button class="back-btn" id="speak-back">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><polyline points="15 18 9 12 15 6"/></svg>
          More
        </button>
        <div class="toolbar-title">Speak</div>
        <div class="toolbar-actions">
          <button class="btn btn-icon" id="tts-model-btn" title="Select TTS Model" style="border:none;background:none;">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><path d="M9.75 3.104v5.714a2.25 2.25 0 0 1-.659 1.591L5 14.5M9.75 3.104c-.251.023-.501.05-.75.082m.75-.082a24.301 24.301 0 0 1 4.5 0m0 0v5.714c0 .597.237 1.17.659 1.591L19.8 15.3M14.25 3.104c.251.023.501.05.75.082M19.8 15.3l-1.57.393A9.065 9.065 0 0 1 12 15a9.065 9.065 0 0 0-6.23.693L5 14.5m14.8.8l1.402 1.402c1.232 1.232.65 3.318-1.067 3.611A48.309 48.309 0 0 1 12 21c-2.773 0-5.491-.235-8.135-.687-1.718-.293-2.3-2.379-1.067-3.61L5 14.5"/></svg>
          </button>
        </div>
      </div>
      <div class="scroll-area" style="display:flex;flex-direction:column;align-items:center;gap:var(--space-xl);padding:var(--space-3xl);">
        <textarea class="chat-input" id="speak-text" placeholder="Enter text to speak..." rows="5" style="max-width:400px;width:100%;min-height:120px;"></textarea>
        <button class="btn btn-sm" id="speak-surprise-btn" style="color:var(--color-purple);">Surprise me</button>
        <div style="display:flex;align-items:center;gap:var(--space-lg);width:100%;max-width:400px;">
          <label style="font-size:var(--font-size-sm);color:var(--text-secondary);min-width:50px;">Speed</label>
          <input type="range" id="speak-speed" min="0.5" max="2" step="0.1" value="1" style="flex:1;">
          <span id="speak-speed-val" style="font-size:var(--font-size-sm);min-width:30px;text-align:right;">1.0x</span>
        </div>
        <div id="tts-error" style="display:none;color:var(--color-red);font-size:var(--font-size-sm);text-align:center;width:100%;max-width:400px;"></div>
        <div id="tts-status" style="display:none;color:var(--text-secondary);font-size:var(--font-size-sm);text-align:center;width:100%;max-width:400px;"></div>
        <button class="btn btn-primary btn-lg" id="speak-btn" style="width:100%;max-width:400px;background:var(--color-purple);border-color:var(--color-purple);">
          Speak
        </button>
      </div>
    </div>

    <!-- ================================================================= -->
    <!-- Storage Sub-view                                                   -->
    <!-- ================================================================= -->
    <div class="sub-view" id="more-storage-view">
      <div class="toolbar">
        <button class="back-btn" id="storage-back">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" width="18" height="18"><polyline points="15 18 9 12 15 6"/></svg>
          More
        </button>
        <div class="toolbar-title">Storage</div>
        <div class="toolbar-actions"></div>
      </div>
      <div class="scroll-area">
        <div class="storage-overview" id="storage-overview">
          <div class="storage-stat"><div class="value" id="storage-count">0</div><div class="label">Models</div></div>
          <div class="storage-stat"><div class="value" id="storage-size">0 MB</div><div class="label">Total Size</div></div>
          <div class="storage-stat"><div class="value" id="storage-available">-- GB</div><div class="label">Available</div></div>
        </div>
        <div id="storage-models" style="padding:var(--space-lg);"></div>
        <div style="padding:0 var(--space-lg) var(--space-lg);">
          <button class="btn" id="storage-clear-btn" style="width:100%;color:var(--color-red);">Clear All Models</button>
        </div>
      </div>
    </div>
  `;

  // Navigation
  setupNav('more-transcribe-btn', 'more-transcribe-view', 'transcribe-back');
  setupNav('more-speak-btn', 'more-speak-view', 'speak-back');
  setupNav('more-storage-btn', 'more-storage-view', 'storage-back');

  // --- Transcribe (STT) setup ---
  initTranscribeView();

  // --- Speak (TTS) setup ---
  initSpeakView();

  // --- Storage setup ---
  container.querySelector('#storage-back')!.addEventListener('click', refreshStorage);
  refreshStorage();
}

// ---------------------------------------------------------------------------
// Transcribe View Logic (matches iOS SpeechToTextView + STTViewModel)
// ---------------------------------------------------------------------------

function initTranscribeView(): void {
  const batchBtn = container.querySelector('#stt-mode-batch')!;
  const liveBtn = container.querySelector('#stt-mode-live')!;
  const micBtn = container.querySelector('#stt-mic-btn')!;
  const modelBtn = container.querySelector('#stt-model-btn')!;

  // Mode toggle
  batchBtn.addEventListener('click', () => switchSTTMode('batch'));
  liveBtn.addEventListener('click', () => switchSTTMode('live'));

  // Mic button
  micBtn.addEventListener('click', handleMicToggle);

  // Model selection
  modelBtn.addEventListener('click', () => showModelSelectionSheet(ModelCategory.SpeechRecognition));

  // Reset on back
  container.querySelector('#transcribe-back')!.addEventListener('click', () => {
    if (micCapture.isCapturing) {
      micCapture.stop();
    }
    stopLiveVAD();
    sttState = 'idle';
    renderSTTUI();
  });
}

function switchSTTMode(mode: STTMode): void {
  if (sttState === 'recording' || sttState === 'transcribing') return; // Don't switch while active
  sttMode = mode;

  const batchBtn = container.querySelector('#stt-mode-batch')!;
  const liveBtn = container.querySelector('#stt-mode-live')!;
  batchBtn.classList.toggle('active', mode === 'batch');
  liveBtn.classList.toggle('active', mode === 'live');

  const descEl = container.querySelector('#stt-mode-desc')!;
  descEl.textContent = mode === 'batch'
    ? 'Record first, then transcribe'
    : 'Auto-transcribe on silence';
}

async function handleMicToggle(): Promise<void> {
  if (sttState === 'transcribing') return; // Button disabled during transcription

  if (sttState === 'recording') {
    // Stop recording
    stopLiveVAD();

    if (sttMode === 'batch') {
      // Batch: transcribe all collected audio
      sttState = 'transcribing';
      renderSTTUI();
      await performBatchTranscription();
    } else {
      // Live: transcribe any remaining audio, then stop
      sttState = 'transcribing';
      renderSTTUI();
      await performBatchTranscription(); // transcribe remainder
    }

    micCapture.stop();
    sttState = 'idle';
    renderSTTUI();
  } else {
    // Start recording
    sttError = '';
    try {
      await micCapture.start(undefined, (level) => {
        updateLevelBars(level);
      });
      sttState = 'recording';
      renderSTTUI();

      if (sttMode === 'live') {
        startLiveVAD();
      }
    } catch (err) {
      sttError = 'Microphone access denied. Please allow microphone access.';
      renderSTTUI();
    }
  }
}

/** Batch transcription: send full audio buffer to STT. */
async function performBatchTranscription(): Promise<void> {
  const audioBuffer = micCapture.getAudioBuffer();
  if (audioBuffer.length < MIN_BUFFER_BYTES) {
    sttError = 'Recording too short. Please speak longer.';
    return;
  }

  try {
    const text = await transcribeAudio(audioBuffer);
    if (text && text.trim().length > 0) {
      if (sttTranscription.length > 0) {
        sttTranscription += '\n' + text.trim();
      } else {
        sttTranscription = text.trim();
      }
    }
  } catch (err) {
    sttError = err instanceof Error ? err.message : String(err);
  }
  renderSTTUI();
}

/** Live VAD: poll audio level and auto-transcribe on silence after speech. */
function startLiveVAD(): void {
  let speechDetected = false;
  let silenceStart = 0;

  liveVadTimer = setInterval(async () => {
    if (sttState !== 'recording' || !micCapture.isCapturing) {
      stopLiveVAD();
      return;
    }

    const level = micCapture.currentLevel;

    if (level >= SPEECH_THRESHOLD) {
      speechDetected = true;
      silenceStart = 0;
    } else if (speechDetected) {
      if (silenceStart === 0) {
        silenceStart = Date.now();
      } else if (Date.now() - silenceStart >= SILENCE_DURATION_MS) {
        // Silence detected after speech -> transcribe segment
        speechDetected = false;
        silenceStart = 0;

        const segment = micCapture.drainBuffer();
        if (segment.length >= MIN_BUFFER_BYTES) {
          try {
            const text = await transcribeAudio(segment);
            if (text && text.trim().length > 0) {
              sttTranscription += (sttTranscription.length > 0 ? '\n' : '') + text.trim();
              renderSTTUI();
            }
          } catch (err) {
            sttError = err instanceof Error ? err.message : String(err);
            renderSTTUI();
          }
        }
      }
    }
  }, 50);
}

function stopLiveVAD(): void {
  if (liveVadTimer) {
    clearInterval(liveVadTimer);
    liveVadTimer = null;
  }
}

/**
 * Call the SDK STT API via sherpa-onnx WASM.
 *
 * Requires:
 *  1. An STT model to be downloaded and loaded (via model selection)
 *  2. sherpa-onnx WASM module to be loaded
 *
 * The model is loaded by ModelManager.loadModel() which calls STT.loadModel().
 */
async function transcribeAudio(pcmFloat32: Float32Array): Promise<string> {
  // Ensure an STT model is loaded (auto-loads a downloaded one if available)
  const model = await ModelManager.ensureLoaded(ModelCategory.SpeechRecognition);
  if (!model) {
    throw new Error(
      'No STT model available. Tap the model button (top right) to download a Speech Recognition model.'
    );
  }

  // Now call STT.transcribe
  const { STT } = await import(
    '../../../../../sdk/runanywhere-web/packages/core/src/index'
  );

  if (!STT.isModelLoaded) {
    throw new Error(
      'STT model not loaded. Tap the model button (top right) to select and load a model.'
    );
  }

  const result = await STT.transcribe(pcmFloat32);
  return result.text;
}

/** Update the audio level indicator bars. */
function updateLevelBars(level: number): void {
  const bars = container.querySelectorAll('.stt-level-bar') as NodeListOf<HTMLElement>;
  bars.forEach((bar) => {
    const h = 3 + Math.random() * level * 21;
    bar.style.height = h + 'px';
    bar.style.background = level > SPEECH_THRESHOLD ? 'var(--color-green)' : 'var(--bg-gray5)';
  });
}

/** Render the STT UI based on current state. */
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
  if (sttError) {
    errorEl.style.display = '';
    errorEl.textContent = sttError;
  } else {
    errorEl.style.display = 'none';
  }

  // Show/hide result area
  if (sttTranscription.length > 0 || sttState === 'transcribing') {
    readyArea.style.display = 'none';
    resultArea.style.display = '';
    resultText.textContent = sttTranscription || 'Transcribing...';
  } else {
    readyArea.style.display = '';
    resultArea.style.display = 'none';
  }

  // Level bars
  levelBars.style.display = sttState === 'recording' ? '' : 'none';

  // Status badge
  if (sttState === 'recording') {
    statusBadge.style.display = '';
    statusBadge.innerHTML = `<span style="display:inline-flex;align-items:center;gap:4px;padding:2px 8px;border-radius:4px;background:rgba(239,68,68,0.1);color:var(--color-red);font-size:11px;font-weight:600;">
      <span style="width:6px;height:6px;border-radius:50%;background:var(--color-red);animation:stt-pulse 1s infinite;"></span> RECORDING
    </span>`;
  } else if (sttState === 'transcribing') {
    statusBadge.style.display = '';
    statusBadge.innerHTML = `<span style="display:inline-flex;align-items:center;gap:4px;padding:2px 8px;border-radius:4px;background:rgba(249,115,22,0.1);color:var(--color-primary);font-size:11px;font-weight:600;">
      <span style="width:12px;height:12px;border:2px solid var(--color-primary);border-top-color:transparent;border-radius:50%;animation:spin 0.8s linear infinite;display:inline-block;"></span> TRANSCRIBING
    </span>`;
  } else {
    statusBadge.style.display = 'none';
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

// ---------------------------------------------------------------------------
// Speak (TTS) View Logic
// ---------------------------------------------------------------------------

let ttsIsSpeaking = false;
let ttsPlayback: InstanceType<typeof import('../../../../../sdk/runanywhere-web/packages/core/src/Infrastructure/AudioPlayback').AudioPlayback> | null = null;

function initSpeakView(): void {
  const speedSlider = container.querySelector('#speak-speed') as HTMLInputElement;
  const speedVal = container.querySelector('#speak-speed-val')!;
  const modelBtn = container.querySelector('#tts-model-btn')!;
  const speakBtn = container.querySelector('#speak-btn')!;

  speedSlider.addEventListener('input', () => {
    speedVal.textContent = parseFloat(speedSlider.value).toFixed(1) + 'x';
  });

  container.querySelector('#speak-surprise-btn')!.addEventListener('click', () => {
    const textArea = container.querySelector('#speak-text') as HTMLTextAreaElement;
    textArea.value = SURPRISE_TEXTS[Math.floor(Math.random() * SURPRISE_TEXTS.length)];
  });

  // Model selection
  modelBtn.addEventListener('click', () => showModelSelectionSheet(ModelCategory.SpeechSynthesis));

  // Speak button
  speakBtn.addEventListener('click', handleSpeak);

  // Stop on back
  container.querySelector('#speak-back')!.addEventListener('click', () => {
    if (ttsPlayback) {
      ttsPlayback.stop();
      ttsIsSpeaking = false;
      renderSpeakUI();
    }
  });
}

async function handleSpeak(): Promise<void> {
  const textArea = container.querySelector('#speak-text') as HTMLTextAreaElement;
  const speedSlider = container.querySelector('#speak-speed') as HTMLInputElement;
  const errorEl = container.querySelector('#tts-error') as HTMLElement;
  const statusEl = container.querySelector('#tts-status') as HTMLElement;

  const text = textArea.value.trim();
  if (!text) {
    errorEl.style.display = '';
    errorEl.textContent = 'Please enter some text to speak.';
    return;
  }

  // If currently speaking, stop
  if (ttsIsSpeaking && ttsPlayback) {
    ttsPlayback.stop();
    ttsIsSpeaking = false;
    renderSpeakUI();
    return;
  }

  errorEl.style.display = 'none';
  statusEl.style.display = '';
  statusEl.textContent = 'Loading TTS model...';

  try {
    // Ensure a TTS model is loaded (auto-loads a downloaded one if available)
    const ttsModel = await ModelManager.ensureLoaded(ModelCategory.SpeechSynthesis);
    if (!ttsModel) {
      throw new Error(
        'No TTS model available. Tap the model button (top right) to download a Speech Synthesis model.'
      );
    }

    // Synthesize
    statusEl.textContent = 'Synthesizing speech...';
    const speed = parseFloat(speedSlider.value);

    const { TTS, AudioPlayback } = await import(
      '../../../../../sdk/runanywhere-web/packages/core/src/index'
    );

    if (!TTS.isVoiceLoaded) {
      throw new Error('TTS voice not loaded. Select and load a model first.');
    }

    const result = await TTS.synthesize(text, { speed });

    // Play audio
    statusEl.textContent = `Playing (${(result.durationMs / 1000).toFixed(1)}s)...`;
    ttsIsSpeaking = true;
    renderSpeakUI();

    if (!ttsPlayback) {
      ttsPlayback = new AudioPlayback();
    }

    await ttsPlayback.play(result.audioData, result.sampleRate);

    // Done
    ttsIsSpeaking = false;
    statusEl.textContent = `Done — ${(result.durationMs / 1000).toFixed(1)}s audio in ${(result.processingTimeMs / 1000).toFixed(1)}s`;
    renderSpeakUI();
  } catch (err) {
    ttsIsSpeaking = false;
    errorEl.style.display = '';
    errorEl.textContent = err instanceof Error ? err.message : String(err);
    statusEl.style.display = 'none';
    renderSpeakUI();
  }
}

function renderSpeakUI(): void {
  const speakBtn = container.querySelector('#speak-btn') as HTMLButtonElement;
  if (ttsIsSpeaking) {
    speakBtn.textContent = 'Stop';
    speakBtn.style.background = 'var(--color-red)';
    speakBtn.style.borderColor = 'var(--color-red)';
  } else {
    speakBtn.textContent = 'Speak';
    speakBtn.style.background = 'var(--color-purple)';
    speakBtn.style.borderColor = 'var(--color-purple)';
  }
}

function setupNav(triggerBtnId: string, subViewId: string, backBtnId: string): void {
  container.querySelector(`#${triggerBtnId}`)!.addEventListener('click', () => {
    container.querySelector(`#${subViewId}`)!.classList.add('active');
  });
  container.querySelector(`#${backBtnId}`)!.addEventListener('click', () => {
    container.querySelector(`#${subViewId}`)!.classList.remove('active');
  });
}

async function refreshStorage(): Promise<void> {
  const info = await ModelManager.getStorageInfo();
  const countEl = container.querySelector('#storage-count')!;
  const sizeEl = container.querySelector('#storage-size')!;
  const availEl = container.querySelector('#storage-available')!;

  countEl.textContent = String(info.modelCount);
  sizeEl.textContent = formatBytes(info.totalSize);
  availEl.textContent = formatBytes(info.available);

  // List downloaded models
  const modelsEl = container.querySelector('#storage-models')!;
  const downloaded = ModelManager.getModels().filter((m) => m.status === 'downloaded' || m.status === 'loaded');
  if (downloaded.length === 0) {
    modelsEl.innerHTML = '<p style="text-align:center;color:var(--text-tertiary);padding:var(--space-xl);">No downloaded models</p>';
  } else {
    modelsEl.innerHTML = downloaded
      .map(
        (m) => `
        <div class="model-row">
          <div class="model-logo">&#129302;</div>
          <div class="model-info">
            <div class="model-name">${m.name}</div>
            <div class="model-meta">
              <span class="model-framework-badge">${m.framework}</span>
              ${m.sizeBytes ? `<span class="model-size">${formatBytes(m.sizeBytes)}</span>` : ''}
            </div>
          </div>
          <button class="btn btn-sm" style="color:var(--color-red);" data-delete="${m.id}">Delete</button>
        </div>
      `
      )
      .join('');

    modelsEl.querySelectorAll('[data-delete]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        await ModelManager.deleteModel((btn as HTMLElement).dataset.delete!);
        refreshStorage();
      });
    });
  }
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(1) + ' ' + units[i];
}
