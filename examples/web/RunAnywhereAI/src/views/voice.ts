/**
 * Voice Tab - Voice Assistant with pipeline setup and particle animation
 * Matches iOS VoiceAssistantView.
 *
 * Pipeline flow:  Mic → STT → LLM (streaming) → TTS → Speaker
 */

import { showModelSelectionSheet } from '../components/model-selection';
import { ModelManager, ModelCategory } from '../services/model-manager';
import { AudioCapture } from '../../../../../sdk/runanywhere-web/packages/core/src/index';

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

// ---------------------------------------------------------------------------
// VAD Configuration (matches iOS VoiceSessionConfig defaults)
// ---------------------------------------------------------------------------

/** Audio level threshold (0–1) to detect speech */
const SPEECH_THRESHOLD = 0.08;
/** Seconds of silence after speech before auto-processing */
const SILENCE_DURATION = 1.5;
/** Minimum audio buffer (samples at 16kHz) to process — ~0.5s */
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
/** VAD state */
let isSpeechActive = false;
let lastSpeechTime: number | null = null;
/** VAD polling interval */
let vadInterval: ReturnType<typeof setInterval> | null = null;

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

export function initVoiceTab(el: HTMLElement): void {
  container = el;
  container.innerHTML = `
    <!-- Pipeline Setup -->
    <div id="voice-setup" class="scroll-area" style="display:flex;flex-direction:column;">
      <div class="toolbar">
        <div class="toolbar-title">Voice Assistant</div>
        <div class="toolbar-actions"></div>
      </div>
      <div style="flex:1;display:flex;align-items:center;justify-content:center;">
        <div class="pipeline-setup">
          <h3 style="text-align:center;margin-bottom:var(--space-md);">Set Up Voice Pipeline</h3>
          <p style="text-align:center;color:var(--text-secondary);font-size:var(--font-size-sm);margin-bottom:var(--space-xl);">
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

          <button class="btn btn-primary btn-lg" id="voice-start-btn" disabled style="width:100%;margin-top:var(--space-xl);">
            Start Voice Assistant
          </button>
        </div>
      </div>
    </div>

    <!-- Voice Interface -->
    <div id="voice-interface" style="display:none;flex:1;flex-direction:column;">
      <div class="toolbar">
        <div class="toolbar-title">Voice Assistant</div>
        <div class="toolbar-actions">
          <button class="btn btn-icon" id="voice-back-btn" style="border:none;background:none;cursor:pointer;color:var(--text-secondary);">
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
      <div style="padding:var(--space-lg);text-align:center;">
        <div id="voice-status" style="color:var(--text-secondary);font-size:var(--font-size-sm);">Tap to speak</div>
        <div id="voice-response" class="scroll-area" style="max-height:150px;margin-top:var(--space-md);text-align:left;"></div>
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
        statusEl.style.color = 'var(--color-green)';
      }
      if (stepNumber) {
        stepNumber.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" width="16" height="16"><polyline points="20 6 9 17 4 12"/></svg>`;
      }
      card.classList.add('loaded');
    } else {
      // Not loaded — show default state
      if (statusEl) {
        statusEl.textContent = step.defaultStatus;
        statusEl.style.color = '';
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
  if (setup) setup.style.display = 'none';
  if (iface) iface.style.display = 'flex';
}

/** Switch from voice interface → pipeline setup */
function transitionToSetup(): void {
  stopSession();
  state = 'setup';
  const setup = container.querySelector('#voice-setup') as HTMLElement;
  const iface = container.querySelector('#voice-interface') as HTMLElement;
  if (setup) setup.style.display = 'flex';
  if (iface) iface.style.display = 'none';
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
  stopVAD();
  if (micCapture.isCapturing) micCapture.stop();
  setMicActive(false);
  stopParticles();
  state = 'idle';
  setStatus('Tap to speak');
}

/** Begin capturing audio and monitoring with VAD */
async function startListening(): Promise<void> {
  if (!sessionActive) return;

  state = 'listening';
  isSpeechActive = false;
  lastSpeechTime = null;
  setStatus('Listening...');

  try {
    await micCapture.start(undefined, (level) => updateParticles(level));
    startParticles();
    startVAD();
  } catch {
    setStatus('Microphone access denied');
    stopSession();
  }
}

// ---------------------------------------------------------------------------
// VAD — energy-threshold voice activity detection (matches iOS)
// ---------------------------------------------------------------------------

function startVAD(): void {
  stopVAD();
  vadInterval = setInterval(() => checkSpeechState(micCapture.currentLevel), 50);
}

function stopVAD(): void {
  if (vadInterval) {
    clearInterval(vadInterval);
    vadInterval = null;
  }
}

function checkSpeechState(level: number): void {
  if (!sessionActive || state !== 'listening') return;

  if (level > SPEECH_THRESHOLD) {
    if (!isSpeechActive) {
      console.log('[Voice] Speech started');
      isSpeechActive = true;
    }
    lastSpeechTime = Date.now();
  } else if (isSpeechActive && lastSpeechTime) {
    const silenceMs = Date.now() - lastSpeechTime;
    if (silenceMs > SILENCE_DURATION * 1000) {
      console.log(`[Voice] Silence detected (${(silenceMs / 1000).toFixed(1)}s)`);
      isSpeechActive = false;

      // Drain audio and process if we have enough data
      const audioData = micCapture.drainBuffer();
      if (audioData.length >= MIN_AUDIO_SAMPLES) {
        // Stop mic during processing (will restart after TTS)
        stopVAD();
        micCapture.stop();
        stopParticles();
        runPipeline(audioData);
      }
    }
  }
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
    setResponse(`<div style="color:var(--text-secondary);margin-bottom:8px;"><strong>You:</strong> ${escapeHtml(userText)}</div>`);
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
