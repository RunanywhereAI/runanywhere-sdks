/**
 * Voice Tab — V2 canonical voice agent.
 *
 * Mirrors the iOS `VoiceAgentViewModel` pattern (Swift source-of-truth):
 *
 *   1. The user loads three models from the other tabs (Chat for LLM,
 *      Transcribe for STT, Speak for TTS — backed by the same model registry
 *      and `RunAnywhere.loadModel(...)` lifecycle).
 *   2. We probe `RunAnywhere.componentLifecycleSnapshot(SDK_COMPONENT_*)` for
 *      LLM / STT / TTS readiness. When all three are READY, the Start
 *      button enables.
 *   3. Start: capture mic at 16 kHz mono Float32 through `AudioCapture`,
 *      register backend models via
 *      `RunAnywhere.initializeVoiceAgentWithLoadedModels()`, and consume
 *      `RunAnywhere.streamVoiceAgent()` as `AsyncIterable<VoiceEvent>`.
 *   4. Each VoiceEvent oneof arm drives a UI region:
 *        - `state`              → pipeline status pill (idle / listening / ...)
 *        - `vad`                → speech-detected indicator
 *        - `userSaid`           → live transcript area
 *        - `assistantToken`     → streamed assistant response
 *        - `audio`              → push PCM bytes to `AudioPlayback`
 *        - `error`              → inline error banner
 *   5. Stop: cancel the event-consumer task, stop capture, dispose playback,
 *      and call `RunAnywhere.cleanupVoiceAgent()`.
 *
 * The voice agent itself owns audio pacing (the energy-VAD inside the C++
 * agent runs against the mic samples once registered). Until the ONNX/Sherpa
 * WASM is rebuilt with the matched-set bump, `ONNX.register()` may resolve
 * but `initializeVoiceAgentWithLoadedModels()` will raise
 * `BackendNotAvailable` — the view surfaces that as an inline error.
 */

import type { TabLifecycle } from '../app';
import {
  RunAnywhere,
  AudioEncoding,
  SDKComponent,
  TokenKind,
  isSDKException,
  VoiceEventPipelineState,
  type AssistantTokenEvent,
  type AudioFrameEvent,
  type ErrorEvent,
  type StateChangeEvent,
  type UserSaidEvent,
  type VADEvent,
  type VoiceEvent,
} from '@runanywhere/web';
import {
  AudioCapture,
  AudioPlayback,
} from '@runanywhere/web/browser';
import { ONNX } from '@runanywhere/web-onnx';
import { ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

// `@runanywhere/web-llamacpp` is loaded lazily so the voice tab can be code-
// split. `main.ts` already pulls the package via dynamic `import(...)` for
// initial registration, so importing it statically here would prevent vite
// from sharing the chunk. We eagerly resolve the module on first render so
// `LlamaCPP.isRegistered` is available synchronously after that.
type LlamaCPPApi = typeof import('@runanywhere/web-llamacpp')['LlamaCPP'];
let _llamaCppCache: LlamaCPPApi | null = null;
async function llamaCpp(): Promise<LlamaCPPApi> {
  if (_llamaCppCache) return _llamaCppCache;
  const mod = await import('@runanywhere/web-llamacpp');
  _llamaCppCache = mod.LlamaCPP;
  return _llamaCppCache;
}
function llamaCppSync(): LlamaCPPApi | null {
  return _llamaCppCache;
}
// Kick off the import as soon as the module loads so the cached reference
// is available synchronously by the time the user reaches the Voice tab.
void llamaCpp().catch(() => {
  /* Silently ignored — `main.ts` reports backend registration errors. */
});

// ---------------------------------------------------------------------------
// View state
// ---------------------------------------------------------------------------

type SessionState =
  | 'idle'
  | 'starting'
  | 'listening'
  | 'speech-detected'
  | 'processing'
  | 'speaking'
  | 'stopped'
  | 'error';

interface ComponentReadiness {
  llmReady: boolean;
  sttReady: boolean;
  ttsReady: boolean;
  llmModelId: string;
  sttModelId: string;
  ttsModelId: string;
}

let container: HTMLElement;
let unmounted = false;

let audioCapture: AudioCapture | null = null;
let audioPlayback: AudioPlayback | null = null;
let eventConsumer: AbortController | null = null;
let sessionState: SessionState = 'idle';
let userTranscript = '';
let assistantResponse = '';
let assistantThinking = '';
let lastError: string | null = null;
let audioLevel = 0;
let lastEventSummary = '';

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

export function initVoiceTab(el: HTMLElement): TabLifecycle {
  container = el;
  unmounted = false;
  renderView();
  return {
    onActivate: () => {
      unmounted = false;
      renderView();
    },
    onDeactivate: () => {
      unmounted = true;
      void stopSession({ silent: true });
    },
  };
}

// ---------------------------------------------------------------------------
// Readiness probing
// ---------------------------------------------------------------------------

function readReadiness(): ComponentReadiness {
  return {
    llmReady: isComponentReady(SDKComponent.SDK_COMPONENT_LLM),
    sttReady: isComponentReady(SDKComponent.SDK_COMPONENT_STT),
    ttsReady: isComponentReady(SDKComponent.SDK_COMPONENT_TTS),
    llmModelId: componentModelId(SDKComponent.SDK_COMPONENT_LLM),
    sttModelId: componentModelId(SDKComponent.SDK_COMPONENT_STT),
    ttsModelId: componentModelId(SDKComponent.SDK_COMPONENT_TTS),
  };
}

function isComponentReady(component: SDKComponent): boolean {
  try {
    const snap = RunAnywhere.componentLifecycleSnapshot(component);
    return snap?.state === ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY;
  } catch {
    return false;
  }
}

function componentModelId(component: SDKComponent): string {
  try {
    const snap = RunAnywhere.componentLifecycleSnapshot(component);
    return snap?.modelId ?? '';
  } catch {
    return '';
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderView(): void {
  if (unmounted) return;

  const readiness = readReadiness();
  const llamaApi = llamaCppSync();
  if (!llamaApi) {
    // Resolve in the background and re-render once the module is loaded so
    // `LlamaCPP.isRegistered` becomes visible without further user action.
    void llamaCpp().then(() => {
      if (!unmounted) renderView();
    }).catch(() => { /* surfaced elsewhere */ });
  }
  const llamaRegistered = llamaApi?.isRegistered ?? false;
  const onnxRegistered = ONNX.isRegistered;
  const allReady = readiness.llmReady && readiness.sttReady && readiness.ttsReady;
  const isActive = sessionState !== 'idle'
    && sessionState !== 'stopped'
    && sessionState !== 'error';

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Voice</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="voice-refresh-btn">Refresh</button>
      </div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Backend status</h3>
        <ul class="feature-unavailable__list">
          <li><code>LlamaCPP.isRegistered</code>: <strong>${llamaRegistered ? 'yes' : 'no'}</strong></li>
          <li><code>ONNX.isRegistered</code>: <strong>${onnxRegistered ? 'yes' : 'no'}</strong></li>
        </ul>
        <div class="toolbar-actions">
          ${llamaRegistered
            ? ''
            : '<button class="btn btn-secondary" id="voice-register-llama">Register LlamaCPP</button>'}
          ${onnxRegistered
            ? ''
            : '<button class="btn btn-secondary" id="voice-register-onnx">Register ONNX</button>'}
        </div>
      </div>

      <div class="docs-section">
        <h3>Pipeline models</h3>
        <p class="text-secondary">Each slot is loaded through the canonical model
        lifecycle. Open the indicated tab to download and load the model — the
        voice agent reuses whatever is currently loaded in that component.</p>
        <ul class="feature-unavailable__list">
          <li>
            <strong>LLM:</strong>
            ${readiness.llmReady
              ? `<span class="badge badge-green">Loaded</span> <code>${escapeHtml(readiness.llmModelId || '(default)')}</code>`
              : '<span class="badge badge-grey">Not loaded</span> — load any chat model from the <em>Chat</em> tab'}
          </li>
          <li>
            <strong>STT:</strong>
            ${readiness.sttReady
              ? `<span class="badge badge-green">Loaded</span> <code>${escapeHtml(readiness.sttModelId || '(default)')}</code>`
              : '<span class="badge badge-grey">Not loaded</span> — load Whisper Tiny from the <em>Transcribe</em> tab'}
          </li>
          <li>
            <strong>TTS:</strong>
            ${readiness.ttsReady
              ? `<span class="badge badge-green">Loaded</span> <code>${escapeHtml(readiness.ttsModelId || '(default)')}</code>`
              : '<span class="badge badge-grey">Not loaded</span> — load Piper US Lessac from the <em>Speak</em> tab'}
          </li>
        </ul>
      </div>

      <div class="docs-section">
        <h3>Session</h3>
        <p class="text-secondary">When all three models are loaded the agent
        captures the microphone, dispatches each turn through
        <code>RunAnywhere.streamVoiceAgent()</code>, and plays back the TTS
        chunks via <code>AudioPlayback</code>.</p>
        <div class="toolbar-actions">
          <button
            class="btn btn-primary"
            id="voice-start-btn"
            ${allReady && !isActive ? '' : 'disabled'}
          >${isActive ? 'Session active' : 'Start Voice Session'}</button>
          <button
            class="btn btn-secondary"
            id="voice-stop-btn"
            ${isActive ? '' : 'disabled'}
          >Stop</button>
        </div>
        <div class="docs-status">
          <strong>State:</strong>
          <span id="voice-state-pill" class="badge ${stateBadgeClass(sessionState)}">${prettyState(sessionState)}</span>
          <span class="text-secondary" style="margin-left:8px"><code>${escapeHtml(lastEventSummary || '(no events yet)')}</code></span>
        </div>
        <div class="docs-status" id="voice-level-row">
          <strong>Mic level:</strong>
          <div class="progress-bar" style="display:inline-block;width:200px;margin-left:8px;vertical-align:middle">
            <div class="progress-fill" style="width:${Math.round(audioLevel * 100)}%"></div>
          </div>
        </div>
        ${lastError
          ? `<div class="docs-status error">Error: ${escapeHtml(lastError)}</div>`
          : ''}
      </div>

      <div class="docs-section">
        <h3>You said</h3>
        <pre id="voice-user-transcript" class="docs-pre">${escapeHtml(userTranscript || '(waiting for speech...)')}</pre>
      </div>

      ${assistantThinking
        ? `<div class="docs-section">
            <h3>Assistant thinking</h3>
            <pre id="voice-assistant-thinking" class="docs-pre">${escapeHtml(assistantThinking)}</pre>
          </div>`
        : ''}

      <div class="docs-section">
        <h3>Assistant</h3>
        <pre id="voice-assistant-response" class="docs-pre">${escapeHtml(assistantResponse || '(no response yet)')}</pre>
      </div>
    </div>
  `;

  attachHandlers();
}

function attachHandlers(): void {
  container.querySelector('#voice-refresh-btn')?.addEventListener('click', () => renderView());
  container
    .querySelector('#voice-register-llama')
    ?.addEventListener('click', () => void registerLlamaCpp());
  container
    .querySelector('#voice-register-onnx')
    ?.addEventListener('click', () => void registerOnnx());
  container.querySelector('#voice-start-btn')?.addEventListener('click', () => void startSession());
  container.querySelector('#voice-stop-btn')?.addEventListener('click', () => void stopSession());
}

// ---------------------------------------------------------------------------
// Backend registration helpers
// ---------------------------------------------------------------------------

async function registerLlamaCpp(): Promise<void> {
  lastError = null;
  setEventSummary('Registering LlamaCPP backend...');
  try {
    const LlamaCPP = await llamaCpp();
    await LlamaCPP.register({ acceleration: 'auto' });
  } catch (err) {
    lastError = `LlamaCPP register failed: ${formatErr(err)}`;
  } finally {
    renderView();
  }
}

async function registerOnnx(): Promise<void> {
  lastError = null;
  setEventSummary('Registering ONNX backend...');
  try {
    await ONNX.register();
  } catch (err) {
    lastError = `ONNX register failed: ${formatErr(err)}`;
  } finally {
    renderView();
  }
}

// ---------------------------------------------------------------------------
// Session control
// ---------------------------------------------------------------------------

async function startSession(): Promise<void> {
  if (sessionState !== 'idle' && sessionState !== 'stopped' && sessionState !== 'error') return;

  // Reset state.
  userTranscript = '';
  assistantResponse = '';
  assistantThinking = '';
  lastError = null;
  sessionState = 'starting';
  setEventSummary('Initializing voice agent...');
  renderView();

  try {
    // Initialize against the currently-loaded LLM/STT/TTS components.
    await RunAnywhere.initializeVoiceAgentWithLoadedModels();

    // Start the microphone at the VAD-friendly 16 kHz mono Float32 rate.
    audioCapture = new AudioCapture({ sampleRate: 16000, channels: 1 });
    await audioCapture.start(undefined, (level) => {
      audioLevel = level;
      updateLevelBar();
    });

    // Prepare playback for TTS audio chunks. The actual sample rate is
    // re-derived per `AudioFrameEvent.sampleRateHz`, but we seed at 22050
    // (Piper default) so the first chunk plays without a context reset.
    audioPlayback = new AudioPlayback({ sampleRate: 22050 });

    sessionState = 'listening';
    setEventSummary('Listening...');
    renderView();

    // Start consuming the proto event stream. We track the consumer via an
    // `AbortController` so `stopSession()` can deterministically end it.
    eventConsumer = new AbortController();
    void consumeEvents(eventConsumer.signal);
  } catch (err) {
    lastError = `Failed to start voice session: ${formatErr(err)}`;
    sessionState = 'error';
    setEventSummary('Start failed.');
    await stopSession({ silent: true });
    renderView();
  }
}

async function stopSession(opts: { silent?: boolean } = {}): Promise<void> {
  const wasActive = sessionState !== 'idle' && sessionState !== 'stopped' && sessionState !== 'error';

  eventConsumer?.abort();
  eventConsumer = null;

  if (audioCapture) {
    try { audioCapture.stop(); } catch { /* ignore */ }
    audioCapture = null;
  }

  if (audioPlayback) {
    try { audioPlayback.dispose(); } catch { /* ignore */ }
    audioPlayback = null;
  }

  audioLevel = 0;

  try {
    await RunAnywhere.cleanupVoiceAgent();
  } catch {
    // Cleanup is best-effort — silently swallow.
  }

  if (wasActive && sessionState !== 'error') {
    sessionState = 'stopped';
    setEventSummary('Session stopped.');
  }

  if (!opts.silent) renderView();
}

// ---------------------------------------------------------------------------
// Event stream consumer
// ---------------------------------------------------------------------------

async function consumeEvents(signal: AbortSignal): Promise<void> {
  try {
    const stream = RunAnywhere.streamVoiceAgent();
    for await (const event of stream) {
      if (signal.aborted || unmounted) break;
      handleVoiceEvent(event);
      // Re-render incrementally; pre-compute the affected DOM regions to
      // avoid replacing the whole panel on every token (which would jitter
      // the user-input transcript while typing).
      updateTextRegions();
    }
  } catch (err) {
    if (!signal.aborted) {
      lastError = `Voice agent stream error: ${formatErr(err)}`;
      sessionState = 'error';
      renderView();
    }
  } finally {
    if (!signal.aborted && !unmounted) {
      // The stream finished on its own (e.g. session ended server-side).
      if (sessionState !== 'error') {
        sessionState = 'stopped';
        renderView();
      }
    }
  }
}

function handleVoiceEvent(event: VoiceEvent): void {
  if (event.state) {
    applyStateChange(event.state);
    setEventSummary(`state: ${pipelineStateName(event.state.current)}`);
  }
  if (event.vad) {
    applyVadEvent(event.vad);
  }
  if (event.userSaid) {
    applyUserSaid(event.userSaid);
  }
  if (event.assistantToken) {
    applyAssistantToken(event.assistantToken);
  }
  if (event.audio) {
    void applyAudioFrame(event.audio);
  }
  if (event.error) {
    applyErrorEvent(event.error);
  }
}

function applyStateChange(state: StateChangeEvent): void {
  switch (state.current) {
    case VoiceEventPipelineState.PIPELINE_STATE_IDLE:
    case VoiceEventPipelineState.PIPELINE_STATE_LISTENING:
      if (sessionState !== 'speaking' && sessionState !== 'processing') {
        sessionState = 'listening';
      }
      break;
    case VoiceEventPipelineState.PIPELINE_STATE_PROCESSING_SPEECH:
    case VoiceEventPipelineState.PIPELINE_STATE_THINKING:
    case VoiceEventPipelineState.PIPELINE_STATE_GENERATING_RESPONSE:
      sessionState = 'processing';
      break;
    case VoiceEventPipelineState.PIPELINE_STATE_SPEAKING:
    case VoiceEventPipelineState.PIPELINE_STATE_PLAYING_TTS:
      sessionState = 'speaking';
      break;
    case VoiceEventPipelineState.PIPELINE_STATE_STOPPED:
      sessionState = 'stopped';
      break;
    case VoiceEventPipelineState.PIPELINE_STATE_ERROR:
      sessionState = 'error';
      break;
    default:
      break;
  }
  // The state pill is part of the full re-render path; queue one.
  scheduleRender();
}

function applyVadEvent(vad: VADEvent): void {
  if (vad.isSpeech) {
    sessionState = 'speech-detected';
    scheduleRender();
  } else if (sessionState === 'speech-detected') {
    sessionState = 'processing';
    scheduleRender();
  }
}

function applyUserSaid(userSaid: UserSaidEvent): void {
  // Partial hypotheses overwrite; finals stay until the next turn starts.
  userTranscript = userSaid.text;
}

function applyAssistantToken(token: AssistantTokenEvent): void {
  if (token.kind === TokenKind.TOKEN_KIND_THOUGHT) {
    assistantThinking += token.text;
  } else {
    assistantResponse += token.text;
  }
}

async function applyAudioFrame(frame: AudioFrameEvent): Promise<void> {
  if (!frame.pcm || frame.pcm.byteLength === 0) return;
  try {
    const samples = decodePcm(frame);
    const rate = frame.sampleRateHz || 22050;
    audioPlayback = audioPlayback ?? new AudioPlayback({ sampleRate: rate });
    // Fire-and-forget; subsequent chunks queue via the audio context.
    void audioPlayback.play(samples, rate);
  } catch (err) {
    lastError = `Audio playback failed: ${formatErr(err)}`;
    scheduleRender();
  }
}

function applyErrorEvent(err: ErrorEvent): void {
  if (err.message) {
    lastError = err.message;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function decodePcm(frame: AudioFrameEvent): Float32Array {
  const pcm = frame.pcm;
  if (frame.encoding === AudioEncoding.AUDIO_ENCODING_PCM_S16_LE) {
    const view = new DataView(pcm.buffer, pcm.byteOffset, pcm.byteLength);
    const samples = new Float32Array(pcm.byteLength / 2);
    for (let i = 0; i < samples.length; i += 1) {
      samples[i] = view.getInt16(i * 2, true) / 0x7fff;
    }
    return samples;
  }
  // Default to PCM-F32 little-endian (encoding 0 / unspecified or explicit).
  const view = new DataView(pcm.buffer, pcm.byteOffset, pcm.byteLength);
  const samples = new Float32Array(pcm.byteLength / 4);
  for (let i = 0; i < samples.length; i += 1) {
    samples[i] = view.getFloat32(i * 4, true);
  }
  return samples;
}

function setEventSummary(text: string): void {
  lastEventSummary = text;
}

let renderScheduled = false;
function scheduleRender(): void {
  if (renderScheduled || unmounted) return;
  renderScheduled = true;
  requestAnimationFrame(() => {
    renderScheduled = false;
    renderView();
  });
}

function updateTextRegions(): void {
  const userPre = container.querySelector<HTMLPreElement>('#voice-user-transcript');
  if (userPre) userPre.textContent = userTranscript || '(waiting for speech...)';
  const respPre = container.querySelector<HTMLPreElement>('#voice-assistant-response');
  if (respPre) respPre.textContent = assistantResponse || '(no response yet)';
  const thoughtPre = container.querySelector<HTMLPreElement>('#voice-assistant-thinking');
  if (thoughtPre && assistantThinking) thoughtPre.textContent = assistantThinking;
}

function updateLevelBar(): void {
  const fill = container.querySelector<HTMLDivElement>('#voice-level-row .progress-fill');
  if (fill) fill.style.width = `${Math.round(audioLevel * 100)}%`;
}

function pipelineStateName(state: VoiceEventPipelineState): string {
  switch (state) {
    case VoiceEventPipelineState.PIPELINE_STATE_IDLE: return 'idle';
    case VoiceEventPipelineState.PIPELINE_STATE_LISTENING: return 'listening';
    case VoiceEventPipelineState.PIPELINE_STATE_THINKING: return 'thinking';
    case VoiceEventPipelineState.PIPELINE_STATE_SPEAKING: return 'speaking';
    case VoiceEventPipelineState.PIPELINE_STATE_STOPPED: return 'stopped';
    case VoiceEventPipelineState.PIPELINE_STATE_WAITING_WAKEWORD: return 'waiting-wakeword';
    case VoiceEventPipelineState.PIPELINE_STATE_PROCESSING_SPEECH: return 'processing-speech';
    case VoiceEventPipelineState.PIPELINE_STATE_GENERATING_RESPONSE: return 'generating-response';
    case VoiceEventPipelineState.PIPELINE_STATE_PLAYING_TTS: return 'playing-tts';
    case VoiceEventPipelineState.PIPELINE_STATE_COOLDOWN: return 'cooldown';
    case VoiceEventPipelineState.PIPELINE_STATE_ERROR: return 'error';
    default: return 'unspecified';
  }
}

function prettyState(state: SessionState): string {
  switch (state) {
    case 'idle': return 'Idle';
    case 'starting': return 'Starting...';
    case 'listening': return 'Listening';
    case 'speech-detected': return 'Speech detected';
    case 'processing': return 'Processing';
    case 'speaking': return 'Speaking';
    case 'stopped': return 'Stopped';
    case 'error': return 'Error';
  }
}

function stateBadgeClass(state: SessionState): string {
  switch (state) {
    case 'listening':
    case 'speech-detected':
      return 'badge-green';
    case 'processing':
    case 'speaking':
    case 'starting':
      return 'badge-blue';
    case 'error':
      // No `.badge-red` rule is shipped today; use the grey variant tinted
      // by the inline `error` docs-status class below so failures still
      // surface visibly without depending on a missing rule.
      return 'badge-grey';
    default:
      return 'badge-grey';
  }
}

function formatErr(err: unknown): string {
  if (isSDKException(err)) return err.message;
  return formatError(err);
}
