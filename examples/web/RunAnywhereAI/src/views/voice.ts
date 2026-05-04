/**
 * Voice Tab — Voice Assistant driven by VoiceEvent cases off a
 * `VoiceAgentStreamAdapter.stream()` async iterable.
 *
 * Cross-SDK parity: the iOS, Android, Flutter, and React Native samples
 * all consume the same `AsyncIterable<VoiceEvent>` shape coming off
 * their platform's `VoiceAgentStreamAdapter`. On Web, the adapter can
 * be backed by either:
 *
 *   1. A WASM voice-agent handle (`new VoiceAgentStreamAdapter(handle)`)
 *      — the fully native path, parity with mobile.
 *   2. A custom `VoiceAgentStreamTransport` — the pluggable path used
 *      here, because until the Web WASM voice-agent bindings land the
 *      sample composes STT → LLM (streaming) → TTS directly on the TS
 *      side through the provider registry.
 *
 * Either way, the UI code that consumes the events is identical, which
 * is the whole point of GAP 09 Phase 19 and the v0.20 close-out.
 *
 * Pipeline: Mic -> VAD -> STT -> LLM (streaming) -> TTS -> Speaker.
 */

import type { TabLifecycle } from '../app';
import { showModelSelectionSheet } from '../components/model-selection';
import { ModelManager, ModelCategory, ensureVADLoaded } from '../services/model-manager';
import {
  VoiceAgentStreamAdapter,
  AudioCapture,
  AudioPlayback,
  SpeechActivity,
  ExtensionPoint,
  type VoiceAgentStreamTransport,
  type VoiceEvent,
  VADEventType,
} from '@runanywhere/web';
import { VAD } from '@runanywhere/web-onnx';

/** Shared AudioCapture instance for this view (replaces app-level MicCapture singleton). */
const micCapture = new AudioCapture();

// ---------------------------------------------------------------------------
// Inline STT → LLM → TTS transport.
// ---------------------------------------------------------------------------
// Composes the three provider capabilities registered by backend packages
// (@runanywhere/web-llamacpp, @runanywhere/web-onnx) and emits proto
// `VoiceEvent`s through the canonical `VoiceAgentStreamTransport` contract.
// Replaces the deleted TS-side `VoicePipeline` orchestrator; the public
// event surface (UserSaid, AssistantToken, Audio, State, Error) is
// identical to what `VoiceAgentStreamAdapter(handle)` produces on mobile.
//
// When the Web WASM voice-agent bindings land, this factory is swapped for
// `new VoiceAgentStreamAdapter(handle)` and the state machine / UI below
// stays unchanged.

// Proto PipelineState values (see idl/voice_events.proto) used in the
// StateChangeEvent arm. Inlined so this file doesn't have to import the
// proto enum just for switch labels.
const PROTO_STATE_IDLE = 1;
const PROTO_STATE_THINKING = 3;
const PROTO_STATE_SPEAKING = 4;

interface ComposedTransportOptions {
  readonly maxTokens: number;
  readonly temperature: number;
  readonly systemPrompt: string;
}

/**
 * Create a transport that runs one STT→LLM→TTS turn per `feedTurn(audio)`
 * call and emits proto `VoiceEvent`s through the generated stream surface.
 * `cancel()` aborts the current in-flight generation.
 */
function createComposedVoiceTransport(opts: ComposedTransportOptions): {
  transport: VoiceAgentStreamTransport;
  feedTurn: (audio: Float32Array) => void;
  cancel: () => void;
} {
  let emitMessage: ((evt: VoiceEvent) => void) | null = null;
  let emitError: ((err: Error) => void) | null = null;
  let cancelGeneration: (() => void) | null = null;
  let seq = 0;
  let previousProtoState = PROTO_STATE_IDLE;

  const nowUs = (): number => Math.floor(performance.now() * 1000);

  const emit = (arm: Partial<VoiceEvent>): void => {
    if (!emitMessage) return;
    emitMessage({
      seq: seq++,
      timestampUs: nowUs(),
      userSaid: undefined,
      assistantToken: undefined,
      audio: undefined,
      vad: undefined,
      interrupted: undefined,
      state: undefined,
      error: undefined,
      metrics: undefined,
      ...arm,
    });
  };

  const transition = (next: number): void => {
    emit({ state: { previous: previousProtoState, current: next } });
    previousProtoState = next;
  };

  const feedTurn = (audio: Float32Array): void => {
    emit({ vad: { type: VADEventType.VAD_EVENT_VOICE_END_OF_UTTERANCE, frameOffsetUs: 0 } });
    void runTurn(audio).catch((err: unknown) => {
      const e = err instanceof Error ? err : new Error(String(err));
      emit({
        error: { code: 0, message: e.message, component: 'pipeline', isRecoverable: false },
      });
      emitError?.(e);
    });
  };

  const runTurn = async (audio: Float32Array): Promise<void> => {
    const stt = ExtensionPoint.requireProvider('stt', '@runanywhere/web-onnx');
    const llm = ExtensionPoint.requireProvider('llm', '@runanywhere/web-llamacpp');
    const tts = ExtensionPoint.requireProvider('tts', '@runanywhere/web-onnx');

    // STT
    transition(PROTO_STATE_THINKING);
    const sttResult = await stt.transcribe(audio, { sampleRate: 16000 });
    const userText = sttResult.text.trim();
    emit({
      userSaid: {
        text: userText,
        isFinal: true,
        confidence: 1.0,
        audioStartUs: 0,
        audioEndUs: nowUs(),
      },
    });
    if (!userText) {
      transition(PROTO_STATE_IDLE);
      return;
    }

    // LLM (streaming)
    const { stream, result: llmResultPromise, cancel } = await llm.generateStream(userText, {
      maxTokens: opts.maxTokens,
      temperature: opts.temperature,
      systemPrompt: opts.systemPrompt,
    });
    cancelGeneration = cancel;

    let accumulated = '';
    try {
      for await (const token of stream) {
        accumulated += token;
        emit({ assistantToken: { text: token, isFinal: false, kind: 1 } });
      }
    } finally {
      cancelGeneration = null;
    }

    const llmResult = await llmResultPromise;
    const fullResponse = (llmResult.text || accumulated).trim();
    emit({ assistantToken: { text: '', isFinal: true, kind: 1 } });

    if (!fullResponse) {
      transition(PROTO_STATE_IDLE);
      return;
    }

    // TTS
    transition(PROTO_STATE_SPEAKING);
    const ttsResult = await tts.synthesize(fullResponse, { speed: 1.0 });
    const pcm = new Uint8Array(
      ttsResult.audioData.buffer,
      ttsResult.audioData.byteOffset,
      ttsResult.audioData.byteLength,
    );
    emit({
      audio: {
        pcm,
        sampleRateHz: ttsResult.sampleRate,
        channels: 1,
        encoding: 1,
      },
    });
  };

  const cancel = (): void => {
    cancelGeneration?.();
    cancelGeneration = null;
  };

  const transport: VoiceAgentStreamTransport = {
    subscribe(_req, onMessage, onError, _onDone) {
      emitMessage = onMessage;
      emitError = onError;
      return () => {
        emitMessage = null;
        emitError = null;
      };
    },
  };

  return { transport, feedTurn, cancel };
}

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
/** Whether SDK VAD is actively monitoring audio. */
let vadActive = false;
/** Unsubscribe function for VAD speech activity callback. */
let unsubscribeVAD: (() => void) | null = null;

/**
 * VoiceAgentStreamAdapter bound to an inline STT→LLM→TTS composed
 * transport. On mobile (iOS/Android/Flutter/RN) this would be
 * `new VoiceAgentStreamAdapter(handle)`; the consumer code below is
 * identical either way. When the Web WASM voice-agent bindings land we
 * swap the transport for a handle and delete `createComposedVoiceTransport`.
 */
const { transport: pipelineTransport, feedTurn, cancel: cancelTurn } = createComposedVoiceTransport({
  maxTokens: 150,
  temperature: 0.7,
  systemPrompt:
    'You are a helpful voice assistant. Keep responses concise — 1-3 sentences. Be conversational and friendly.',
});
const adapter = new VoiceAgentStreamAdapter(pipelineTransport);

/** The active `AsyncIterator<VoiceEvent>` subscription, if any. */
let eventIterator: AsyncIterator<VoiceEvent> | null = null;
/** Accumulated assistant response text for the current turn. */
let accumulatedResponse = '';

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

  // Setup card clicks — open model selection for each modality.
  // coexist: true because Voice needs STT + LLM + TTS loaded simultaneously.
  container.querySelector('#voice-setup-stt')!.addEventListener('click', () => {
    showModelSelectionSheet(ModelCategory.SpeechRecognition, { coexist: true });
  });
  container.querySelector('#voice-setup-llm')!.addEventListener('click', () => {
    showModelSelectionSheet(ModelCategory.Language, { coexist: true });
  });
  container.querySelector('#voice-setup-tts')!.addEventListener('click', () => {
    showModelSelectionSheet(ModelCategory.SpeechSynthesis, { coexist: true });
  });

  container.querySelector('#voice-start-btn')!.addEventListener('click', () => {
    transitionToVoiceInterface();
  });

  container.querySelector('#voice-back-btn')!.addEventListener('click', () => {
    transitionToSetup();
  });

  container.querySelector('#voice-mic-btn')!.addEventListener('click', toggleMic);

  ModelManager.onChange(() => refreshPipelineUI());
  refreshPipelineUI();

  return {
    onDeactivate(): void {
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
      if (statusEl) {
        statusEl.textContent = loadedModel.name;
        (statusEl as HTMLElement).classList.add('text-green');
      }
      if (stepNumber) {
        stepNumber.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" width="16" height="16"><polyline points="20 6 9 17 4 12"/></svg>`;
      }
      card.classList.add('loaded');
    } else {
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

function transitionToVoiceInterface(): void {
  state = 'idle';
  const setup = container.querySelector('#voice-setup') as HTMLElement;
  const iface = container.querySelector('#voice-interface') as HTMLElement;
  if (setup) setup.classList.add('hidden');
  if (iface) iface.classList.remove('hidden');
}

function transitionToSetup(): void {
  stopSession();
  state = 'setup';
  const setup = container.querySelector('#voice-setup') as HTMLElement;
  const iface = container.querySelector('#voice-interface') as HTMLElement;
  if (setup) setup.classList.remove('hidden');
  if (iface) iface.classList.add('hidden');
}

// ---------------------------------------------------------------------------
// UI helpers
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
// Mic toggle
// ---------------------------------------------------------------------------

async function toggleMic(): Promise<void> {
  if (sessionActive) {
    stopSession();
  } else {
    await startSession();
  }
}

// ---------------------------------------------------------------------------
// Continuous conversation session
// ---------------------------------------------------------------------------

async function startSession(): Promise<void> {
  sessionActive = true;
  setMicActive(true);
  setResponse('');
  await openEventStream();
  await startListening();
}

function stopSession(): void {
  sessionActive = false;
  cancelTurn();
  closeEventStream();
  stopVoiceVAD();
  if (micCapture.isCapturing) micCapture.stop();
  VAD.reset();
  setMicActive(false);
  stopParticles();
  state = 'idle';
  setStatus('Tap to speak');
}

async function startListening(): Promise<void> {
  if (!sessionActive) return;

  state = 'listening';
  setStatus('Listening...');

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
// VAD
// ---------------------------------------------------------------------------

function onVoiceChunk(samples: Float32Array): void {
  if (!vadActive || state !== 'listening') return;
  try {
    VAD.processSamples(samples);
  } catch (err) {
    setStatus(err instanceof Error ? err.message : String(err));
    stopVoiceVAD();
  }
}

function startVoiceVAD(): void {
  stopVoiceVAD();
  vadActive = true;

  unsubscribeVAD = VAD.onSpeechActivity((activity) => {
    if (!sessionActive || state !== 'listening') return;

    if (activity === SpeechActivity.Started) {
      console.log('[Voice] Speech started (Silero)');
    } else if (activity === SpeechActivity.Ended) {
      console.log('[Voice] Speech ended (Silero)');

      const segment = VAD.popSpeechSegment();
      if (segment && segment.samples.length >= MIN_AUDIO_SAMPLES) {
        console.log(`[Voice] Processing segment: ${segment.samples.length} samples (${(segment.samples.length / 16000).toFixed(1)}s)`);
        stopVoiceVAD();
        micCapture.stop();
        stopParticles();
        state = 'processing';
        accumulatedResponse = '';
        setResponse('');
        feedTurn(segment.samples);
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
// VoiceEvent consumption — identical shape to iOS/Android/Flutter/RN.
// ---------------------------------------------------------------------------

async function openEventStream(): Promise<void> {
  closeEventStream();
  const iterable = adapter.stream({ eventFilter: '' });
  eventIterator = iterable[Symbol.asyncIterator]();
  consumeEventStream(eventIterator).catch((err) => {
    console.error('[Voice] Event stream error:', err);
    setStatus(`Error: ${err instanceof Error ? err.message : String(err)}`);
  });
}

function closeEventStream(): void {
  if (eventIterator?.return) {
    void eventIterator.return(undefined as never);
  }
  eventIterator = null;
}

async function consumeEventStream(iterator: AsyncIterator<VoiceEvent>): Promise<void> {
  while (true) {
    const { value: event, done } = await iterator.next();
    if (done || !event) return;
    handleVoiceEvent(event);
  }
}

function handleVoiceEvent(event: VoiceEvent): void {
  if (event.userSaid) {
    const text = event.userSaid.text;
    if (!text) {
      console.log('[Voice] No speech detected');
      return;
    }
    console.log(`[Voice] User said: "${text}"`);
    setResponse(
      `<div class="text-secondary mb-sm"><strong>You:</strong> ${escapeHtml(text)}</div>` +
      `<div><strong>Assistant:</strong> <span id="voice-llm-output"></span></div>`,
    );
    setStatus('Thinking...');
    return;
  }

  if (event.assistantToken) {
    if (event.assistantToken.isFinal) return;
    accumulatedResponse += event.assistantToken.text;
    const outputSpan = container.querySelector('#voice-llm-output');
    if (outputSpan) outputSpan.textContent = accumulatedResponse;
    return;
  }

  if (event.state) {
    if (event.state.current === PROTO_STATE_THINKING) {
      setStatus('Thinking...');
    } else if (event.state.current === PROTO_STATE_SPEAKING) {
      state = 'speaking';
      setStatus('Speaking...');
    }
    return;
  }

  if (event.audio) {
    // A TTS audio chunk. Copy the bytes back to a Float32Array (PCM f32
    // little-endian, per AudioEncoding.AUDIO_ENCODING_PCM_F32_LE).
    const pcm = event.audio.pcm;
    const f32 = new Float32Array(
      pcm.buffer.slice(pcm.byteOffset, pcm.byteOffset + pcm.byteLength),
    );
    const sampleRate = event.audio.sampleRateHz;
    console.log(`[Voice] TTS: playing ${(f32.length / sampleRate).toFixed(1)}s of audio`);
    void playAudioThenResume(f32, sampleRate);
    return;
  }

  if (event.vad) {
    if (event.vad.type === VADEventType.VAD_EVENT_VOICE_END_OF_UTTERANCE) {
      setStatus('Transcribing...');
    }
    return;
  }

  if (event.error) {
    console.error('[Voice] VoiceEvent error:', event.error);
    setStatus(`Error: ${event.error.message}`);
    return;
  }
}

async function playAudioThenResume(samples: Float32Array, sampleRate: number): Promise<void> {
  const player = new AudioPlayback({ sampleRate });
  try {
    await player.play(samples, sampleRate);
  } finally {
    player.dispose();
  }

  if (sessionActive) {
    await startListening();
  } else {
    state = 'idle';
    setStatus('Tap to speak');
  }
}

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ---------------------------------------------------------------------------
// Particle animation (Canvas2D approximation of Metal shader)
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

    p.vx += (dy / dist) * 0.03 + (Math.random() - 0.5) * energy;
    p.vy += (-dx / dist) * 0.03 + (Math.random() - 0.5) * energy;

    p.vx += dx * 0.0005;
    p.vy += dy * 0.0005;

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
