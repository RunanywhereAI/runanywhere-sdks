/**
 * Voice Tab - Voice Assistant with pipeline setup and particle animation
 * Matches iOS VoiceAssistantView.
 *
 * Pipeline flow:  Mic → STT → LLM (streaming) → TTS → Speaker
 */

import type { TabLifecycle } from '../app';
import { showModelSelectionSheet } from '../components/model-selection';
import { ModelManager, ModelCategory, ensureVADLoaded } from '../services/model-manager';
import { AudioCapture, VAD, SpeechActivity } from '../../../../../sdk/runanywhere-web/packages/core/src/index';

// Lazy-imported SDK modules (loaded only when pipeline runs)
type SDKModules = typeof import('../../../../../sdk/runanywhere-web/packages/core/src/index');
let sdkModules: SDKModules | null = null;

async function getSDK(): Promise<SDKModules> {
  if (!sdkModules) {
    sdkModules = await import('../../../../../sdk/runanywhere-web/packages/core/src/index');
  }
  return sdkModules;
}

/** Shared AudioCapture instance for this view (replaces app-level MicCapture singleton). */
const micCapture = new AudioCapture();

// ---------------------------------------------------------------------------
// Pipeline step definitions
// ---------------------------------------------------------------------------

interface PipelineStep {
  modality: ModelCategory;
  elementId: string;
  title: string;
  defaultStatus: string;
}

const PIPELINE_STEPS: PipelineStep[] = [
  { modality: ModelCategory.SpeechRecognition, elementId: 'voice-setup-stt', title: 'Speech-to-Text', defaultStatus: 'Select STT model' },
  { modality: ModelCategory.Language, elementId: 'voice-setup-llm', title: 'Language Model', defaultStatus: 'Select LLM model' },
  { modality: ModelCategory.SpeechSynthesis, elementId: 'voice-setup-tts', title: 'Text-to-Speech', defaultStatus: 'Select TTS model' },
];

// Minimum audio segment (samples at 16kHz) to process — ~0.5s
const MIN_AUDIO_SAMPLES = 8000;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

type VoiceState = 'setup' | 'idle' | 'listening' | 'processing' | 'speaking';

let container: HTMLElement;
let state: VoiceState = 'setup';
let canvas: HTMLCanvasElement;
let animationFrame: number | null = null;
let particles: Particle[] = [];

/** Whether the continuous conversation session is active */
let sessionActive = false;
/** Cancel function for in-progress LLM generation */
let cancelGeneration: (() => void) | null = null;
/** Whether SDK VAD is actively monitoring audio. */
let vadActive = false;
/** Unsubscribe function for VAD speech activity callback. */
let unsubscribeVAD: (() => void) | null = null;

interface Particle {
  x: number; y: number;
  vx: number; vy: number;
  radius: number;
  color: string;
  alpha: number;
  phase: number;
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export function initVoiceTab(el: HTMLElement): TabLifecycle {
  container = el;
  container.innerHTML = `
    <!-- Pipeline Setup -->
    <div id="voice-setup" class="scroll-area flex-col">
      <div class="toolbar">
        <div class="toolbar-title">Voice Assistant</div>
        <div class="toolbar-actions"></div>
      </div>
      <div class="flex-1 flex-center">
        <div class="pipeline-setup">
          <h3 class="text-center mb-md">Set Up Voice Pipeline</h3>
          <p class="text-center helper-text mb-xl">
            Select models for each step of the voice AI pipeline.
          </p>

          <div class="setup-card" id="voice-setup-stt">
            <div class="setup-step-number">1</div>
            <div class="setup-card-info">
              <div class="setup-card-title">Speech-to-Text</div>
              <div class="setup-card-status">Select STT model</div>
            </div>
          </div>

          <div class="setup-card" id="voice-setup-llm">
            <div class="setup-step-number">2</div>
            <div class="setup-card-info">
              <div class="setup-card-title">Language Model</div>
              <div class="setup-card-status">Select LLM model</div>
            </div>
          </div>

          <div class="setup-card" id="voice-setup-tts">
            <div class="setup-step-number">3</div>
            <div class="setup-card-info">
              <div class="setup-card-title">Text-to-Speech</div>
              <div class="setup-card-status">Select TTS model</div>
            </div>
          </div>

          <button class="btn btn-primary btn-lg w-full mt-xl" id="voice-start-btn" disabled>
            Start Voice Assistant
          </button>
        </div>
      </div>
    </div>

    <!-- Voice Interface -->
    <div id="voice-interface" class="voice-interface hidden">
      <div class="toolbar">
        <div class="toolbar-title">Voice Assistant</div>
        <div class="toolbar-actions">
          <button class="btn-ghost" id="voice-back-btn">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" width="20" height="20"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>
      </div>
      <div class="voice-canvas-container">
        <canvas class="voice-canvas" id="voice-particle-canvas"></canvas>
        <button class="mic-btn" id="voice-mic-btn">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
            <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
            <line x1="12" y1="19" x2="12" y2="23"/>
            <line x1="8" y1="23" x2="16" y2="23"/>
          </svg>
        </button>
      </div>
      <div class="voice-status-panel">
        <div id="voice-status" class="helper-text">Tap to speak</div>
        <div id="voice-response" class="scroll-area voice-response-area"></div>
      </div>
    </div>
  `;

  canvas = container.querySelector('#voice-particle-canvas')!;

  // Setup card clicks — open model selection for each modality
  container.querySelector('#voice-setup-stt')!.addEventListener('click', () => {
    showModelSelectionSheet(ModelCategory.SpeechRecognition);
  });
  container.querySelector('#voice-setup-llm')!.addEventListener('click', () => {
    showModelSelectionSheet(ModelCategory.Language);
  });
  container.querySelector('#voice-setup-tts')!.addEventListener('click', () => {
    showModelSelectionSheet(ModelCategory.SpeechSynthesis);
  });

  // Start Voice Assistant button
  container.querySelector('#voice-start-btn')!.addEventListener('click', () => {
    transitionToVoiceInterface();
  });

  // Back button from voice interface → setup
  container.querySelector('#voice-back-btn')!.addEventListener('click', () => {
    transitionToSetup();
  });

  // Mic button
  container.querySelector('#voice-mic-btn')!.addEventListener('click', toggleMic);

  // Subscribe to model changes so we can update pipeline state
  ModelManager.onChange(() => refreshPipelineUI());

  // Initial pipeline UI check (in case models are already loaded)
  refreshPipelineUI();

  // Return lifecycle callbacks for tab-switching cleanup
  return {
    onDeactivate(): void {
      // Stop mic, VAD, particles, and cancel any in-flight generation
      if (sessionActive) {
        stopSession();
        console.log('[Voice] Tab deactivated — session stopped');
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Pipeline State & UI
// ---------------------------------------------------------------------------

/** Refresh setup card states and start button based on loaded models */
function refreshPipelineUI(): void {
  const startBtn = container.querySelector('#voice-start-btn') as HTMLButtonElement | null;
  if (!startBtn) return;

  let allReady = true;

  for (const step of PIPELINE_STEPS) {
    const card = container.querySelector(`#${step.elementId}`);
    if (!card) continue;

    const statusEl = card.querySelector('.setup-card-status');
    const stepNumber = card.querySelector('.setup-step-number');
    const loadedModel = ModelManager.getLoadedModel(step.modality);

    if (loadedModel) {
      // Model is loaded — show checkmark and model name
      if (statusEl) {
        statusEl.textContent = loadedModel.name;
        (statusEl as HTMLElement).classList.add('text-green');
      }
      if (stepNumber) {
        stepNumber.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" width="16" height="16"><polyline points="20 6 9 17 4 12"/></svg>`;
      }
      card.classList.add('loaded');
    } else {
      // Not loaded — show default state
      if (statusEl) {
        statusEl.textContent = step.defaultStatus;
        (statusEl as HTMLElement).classList.remove('text-green');
      }
      const stepIdx = PIPELINE_STEPS.indexOf(step);
      if (stepNumber) {
        stepNumber.textContent = String(stepIdx + 1);
      }
      card.classList.remove('loaded');
      allReady = false;
    }
  }

  startBtn.disabled = !allReady;
}

/** Switch from pipeline setup → voice interface */
function transitionToVoiceInterface(): void {
  state = 'idle';
  const setup = container.querySelector('#voice-setup') as HTMLElement;
  const iface = container.querySelector('#voice-interface') as HTMLElement;
  if (setup) setup.classList.add('hidden');
  if (iface) iface.classList.remove('hidden');
}

/** Switch from voice interface → pipeline setup */
function transitionToSetup(): void {
  stopSession();
  state = 'setup';
  const setup = container.querySelector('#voice-setup') as HTMLElement;
  const iface = container.querySelector('#voice-interface') as HTMLElement;
  if (setup) setup.classList.remove('hidden');
  if (iface) iface.classList.add('hidden');
}

// ---------------------------------------------------------------------------
// UI Helpers
// ---------------------------------------------------------------------------

function setStatus(text: string): void {
  const el = container.querySelector('#voice-status');
  if (el) el.textContent = text;
}

function setResponse(html: string): void {
  const el = container.querySelector('#voice-response');
  if (el) el.innerHTML = html;
}

function setMicActive(active: boolean): void {
  const micBtn = container.querySelector('#voice-mic-btn');
  if (micBtn) micBtn.classList.toggle('listening', active);
}

// ---------------------------------------------------------------------------
// Mic Toggle — starts / stops the continuous conversation session
// ---------------------------------------------------------------------------

async function toggleMic(): Promise<void> {
  if (sessionActive) {
    stopSession();
  } else {
    await startSession();
  }
}

// ---------------------------------------------------------------------------
// Continuous conversation session  (matches iOS VoiceSessionHandle)
//
//   ┌──────────────────────────────────────────────┐
//   │  [listening] ──(VAD silence)──► [processing]  │
//   │       ▲                              │        │
//   │       └──── [speaking] ◄─────────────┘        │
//   └──────────────────────────────────────────────┘
// ---------------------------------------------------------------------------

async function startSession(): Promise<void> {
  sessionActive = true;
  setMicActive(true);
  setResponse('');
  await startListening();
}

function stopSession(): void {
  sessionActive = false;
  if (cancelGeneration) {
    cancelGeneration();
    cancelGeneration = null;
  }
  stopVoiceVAD();
  if (micCapture.isCapturing) micCapture.stop();
  VAD.reset();
  setMicActive(false);
  stopParticles();
  state = 'idle';
  setStatus('Tap to speak');
}

/** Begin capturing audio and monitoring with SDK VAD */
async function startListening(): Promise<void> {
  if (!sessionActive) return;

  state = 'listening';
  setStatus('Listening...');

  // Ensure Silero VAD model is loaded (auto-downloads, ~5MB)
  const vadReady = await ensureVADLoaded();
  if (!vadReady) {
    setStatus('Failed to load VAD model');
    stopSession();
    return;
  }
  VAD.reset();

  try {
    await micCapture.start(onVoiceChunk, (level) => updateParticles(level));
    startParticles();
    startVoiceVAD();
  } catch {
    setStatus('Microphone access denied');
    stopSession();
  }
}

// ---------------------------------------------------------------------------
// VAD — SDK Silero VAD (replaces energy-threshold approach)
// ---------------------------------------------------------------------------

/** AudioCapture onChunk callback — feeds audio to SDK VAD. */
function onVoiceChunk(samples: Float32Array): void {
  if (!vadActive || state !== 'listening') return;
  VAD.processSamples(samples);
}

function startVoiceVAD(): void {
  stopVoiceVAD();
  vadActive = true;

  // Subscribe to speech activity events from the SDK VAD
  unsubscribeVAD = VAD.onSpeechActivity((activity) => {
    if (!sessionActive || state !== 'listening') return;

    if (activity === SpeechActivity.Started) {
      console.log('[Voice] Speech started (Silero)');
    } else if (activity === SpeechActivity.Ended) {
      console.log('[Voice] Speech ended (Silero)');

      // Pop the completed speech segment
      const segment = VAD.popSpeechSegment();
      if (segment && segment.samples.length >= MIN_AUDIO_SAMPLES) {
        console.log(`[Voice] Processing segment: ${segment.samples.length} samples (${(segment.samples.length / 16000).toFixed(1)}s)`);
        // Stop mic during processing (will restart after TTS)
        stopVoiceVAD();
        micCapture.stop();
        stopParticles();
        runPipeline(segment.samples);
      }
    }
  });

  console.log('[Voice] Started SDK VAD monitoring');
}

function stopVoiceVAD(): void {
  vadActive = false;
  if (unsubscribeVAD) { unsubscribeVAD(); unsubscribeVAD = null; }
}

// ---------------------------------------------------------------------------
// Voice Pipeline:  Audio → STT → LLM (streaming) → TTS → Speaker → Listen
// ---------------------------------------------------------------------------

async function runPipeline(audioData: Float32Array): Promise<void> {
  state = 'processing';
  const sdk = await getSDK();

  try {
    // ── Step 1: STT ──
    setStatus('Transcribing...');
    console.log(`[Voice] STT: ${(audioData.length / 16000).toFixed(1)}s of audio`);

    const sttResult = await sdk.STT.transcribe(audioData, { sampleRate: 16000 });
    const userText = sttResult.text.trim();

    if (!userText) {
      console.log('[Voice] No speech detected');
      // Resume listening in continuous mode
      if (sessionActive) {
        await startListening();
      } else {
        setStatus('Tap to speak');
        state = 'idle';
      }
      return;
    }

    console.log(`[Voice] STT result: "${userText}" (${sttResult.processingTimeMs}ms)`);
    setResponse(`<div class="text-secondary mb-sm"><strong>You:</strong> ${escapeHtml(userText)}</div>`);
    setStatus('Thinking...');

    // ── Step 2: LLM (streaming) ──
    const systemPrompt =
      'You are a helpful voice assistant. Keep responses concise — 1-3 sentences. Be conversational and friendly.';

    const { stream, result, cancel } = sdk.TextGeneration.generateStream(userText, {
      maxTokens: 150,
      temperature: 0.7,
      systemPrompt,
    });
    cancelGeneration = cancel;

    // Append a response container
    const responseEl = container.querySelector('#voice-response');
    if (responseEl) {
      responseEl.innerHTML += `<div><strong>Assistant:</strong> <span id="voice-llm-output"></span></div>`;
    }
    const outputSpan = container.querySelector('#voice-llm-output');

    let fullResponse = '';
    for await (const token of stream) {
      if (!sessionActive) return; // session was stopped
      fullResponse += token;
      if (outputSpan) outputSpan.textContent = fullResponse;
    }

    cancelGeneration = null;

    const llmResult = await result;
    fullResponse = llmResult.text || fullResponse;
    if (outputSpan) outputSpan.textContent = fullResponse;
    console.log(`[Voice] LLM: ${llmResult.tokensUsed} tokens, ${llmResult.tokensPerSecond.toFixed(1)} tok/s`);

    if (!fullResponse.trim()) {
      if (sessionActive) {
        await startListening();
      } else {
        setStatus('Tap to speak');
        state = 'idle';
      }
      return;
    }

    // ── Step 3: TTS ──
    state = 'speaking';
    setStatus('Speaking...');

    const ttsResult = await sdk.TTS.synthesize(fullResponse.trim(), { speed: 1.0 });
    console.log(`[Voice] TTS: ${ttsResult.durationMs}ms audio in ${ttsResult.processingTimeMs}ms`);

    // ── Step 4: Play audio ──
    const player = new sdk.AudioPlayback({ sampleRate: ttsResult.sampleRate });
    await player.play(ttsResult.audioData, ttsResult.sampleRate);
    player.dispose();

    // ── Step 5: Resume listening (continuous mode) ──
    if (sessionActive) {
      await startListening();
    } else {
      state = 'idle';
      setStatus('Tap to speak');
    }
  } catch (err) {
    console.error('[Voice] Pipeline error:', err);
    const msg = err instanceof Error ? err.message : String(err);
    setStatus(`Error: ${msg}`);
    // Try to resume listening even after an error
    if (sessionActive) {
      await startListening();
    } else {
      state = 'idle';
    }
  }
}

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ---------------------------------------------------------------------------
// Particle Animation (Canvas2D approximation of Metal shader)
// ---------------------------------------------------------------------------

function startParticles(): void {
  resizeCanvas();
  initParticles();
  animateParticles();
}

function stopParticles(): void {
  if (animationFrame) {
    cancelAnimationFrame(animationFrame);
    animationFrame = null;
  }
}

function resizeCanvas(): void {
  const rect = canvas.parentElement!.getBoundingClientRect();
  canvas.width = rect.width * devicePixelRatio;
  canvas.height = rect.height * devicePixelRatio;
  canvas.style.width = rect.width + 'px';
  canvas.style.height = rect.height + 'px';
}

function initParticles(): void {
  particles = [];
  const cx = canvas.width / 2;
  const cy = canvas.height / 2;
  const warmColors = [
    'rgba(255, 85, 0,',
    'rgba(255, 140, 50,',
    'rgba(230, 69, 0,',
    'rgba(255, 170, 80,',
    'rgba(200, 100, 30,',
  ];

  for (let i = 0; i < 60; i++) {
    const angle = Math.random() * Math.PI * 2;
    const dist = 40 + Math.random() * 80;
    particles.push({
      x: cx + Math.cos(angle) * dist,
      y: cy + Math.sin(angle) * dist,
      vx: (Math.random() - 0.5) * 0.5,
      vy: (Math.random() - 0.5) * 0.5,
      radius: 3 + Math.random() * 8,
      color: warmColors[i % warmColors.length],
      alpha: 0.2 + Math.random() * 0.5,
      phase: Math.random() * Math.PI * 2,
    });
  }
}

function updateParticles(level: number): void {
  const cx = canvas.width / 2;
  const cy = canvas.height / 2;
  const energy = level * 3;

  for (const p of particles) {
    p.phase += 0.02;
    const dx = cx - p.x;
    const dy = cy - p.y;
    const dist = Math.sqrt(dx * dx + dy * dy);

    // Orbit + push out with audio energy
    p.vx += (dy / dist) * 0.03 + (Math.random() - 0.5) * energy;
    p.vy += (-dx / dist) * 0.03 + (Math.random() - 0.5) * energy;

    // Pull toward center
    p.vx += dx * 0.0005;
    p.vy += dy * 0.0005;

    // Damping
    p.vx *= 0.98;
    p.vy *= 0.98;

    p.x += p.vx;
    p.y += p.vy;
    p.alpha = 0.2 + Math.sin(p.phase) * 0.15 + level * 0.3;
  }
}

function animateParticles(): void {
  const ctx = canvas.getContext('2d')!;
  ctx.clearRect(0, 0, canvas.width, canvas.height);

  for (const p of particles) {
    ctx.beginPath();
    ctx.arc(p.x, p.y, p.radius * devicePixelRatio, 0, Math.PI * 2);
    ctx.fillStyle = `${p.color} ${Math.min(p.alpha, 0.8)})`;
    ctx.fill();
  }

  animationFrame = requestAnimationFrame(animateParticles);
}
