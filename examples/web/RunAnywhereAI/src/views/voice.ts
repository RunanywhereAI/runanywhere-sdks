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
 *   4. Each VoiceEvent oneof arm drives a UI region (iOS parity:
 *      VoiceAgentViewModel.swift:505-584 `handleProtoEvent`):
 *        - `state`              → session status pill
 *        - `vad`                → speech-detected indicator
 *        - `userSaid`           → live transcript area
 *        - `assistantToken`     → streamed assistant response
 *        - `audio`              → push PCM bytes to `AudioPlayback`
 *        - `error`              → inline error banner
 *   5. Stop: cancel the event-consumer task, stop capture, dispose playback,
 *      and call `RunAnywhere.cleanupVoiceAgent()`.
 *
 * Backends (llamacpp + ONNX) are registered once at app init by `main.ts` —
 * this view assumes they exist and surfaces the SDK's typed error if a verb
 * throws `backendNotAvailable`.
 */

import type { TabLifecycle } from '../app';
import {
  RunAnywhere,
  AudioEncoding,
  ModelCategory,
  TokenKind,
  pcm16ToFloat32,
  VoiceEventPipelineState,
  VADStreamEventKind,
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
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import { getCatalog, type CatalogEntry } from '../services/model-catalog';
import { detectDeviceCapabilities } from '../services/device-capabilities';
import {
  recommendVoicePipeline,
  type VoicePipelineSelection,
} from '../services/model-recommendation';
import {
  modalityEmoji,
  modelFamily,
  variantSizeFeel,
} from '../services/model-display';
import {
  ensureModelReady,
  getModelStatus,
  isModelLoaded,
  onModelStateChange,
  openSheet,
} from '../components/model-selection';

// ---------------------------------------------------------------------------
// View state
// ---------------------------------------------------------------------------

/**
 * Session state — exact mirror of iOS `VoiceSessionState`
 * (iOS parity: VoiceAgentTypes.swift:25-32).
 */
type SessionState =
  | 'disconnected' // Not connected, ready to start
  | 'connecting'   // Initializing session
  | 'connected'    // Session established, idle
  | 'listening'    // Actively listening for speech
  | 'processing'   // Processing transcribed speech
  | 'speaking'     // Playing back TTS response
  | 'error';       // Error state

let container: HTMLElement;
let unmounted = false;

let audioCapture: AudioCapture | null = null;
let audioPlayback: AudioPlayback | null = null;
let eventConsumer: AbortController | null = null;
let sessionState: SessionState = 'disconnected';
let isSpeechDetected = false;
let userTranscript = '';
let assistantResponse = '';
let lastError: string | null = null;
let audioLevel = 0;
let lastEventSummary = '';

// Pre-selected best-for-device voice trio (+ VAD), computed once on first
// activation. `null` until the async capability probe resolves.
let voicePipeline: VoicePipelineSelection | null = null;
let pipelineProbePending = false;
let settingUpPipeline = false;
let unsubscribeModelState: (() => void) | null = null;

/** The ordered pipeline slots surfaced in the setup card. */
interface PipelineSlot {
  key: 'stt' | 'llm' | 'tts' | 'vad';
  label: string;
  hint: string;
  category: ModelCategory;
  entry: CatalogEntry | null;
  /** VAD is optional — the SDK auto-loads it; we don't gate Start on it. */
  optional: boolean;
}

function pipelineSlots(): PipelineSlot[] {
  const p = voicePipeline;
  return [
    { key: 'stt', label: 'Speech-to-text', hint: 'Hears what you say', category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, entry: p?.stt ?? null, optional: false },
    { key: 'llm', label: 'Chat model', hint: 'Thinks of a reply', category: ModelCategory.MODEL_CATEGORY_LANGUAGE, entry: p?.llm ?? null, optional: false },
    { key: 'tts', label: 'Text-to-speech', hint: 'Speaks the reply', category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS, entry: p?.tts ?? null, optional: false },
    { key: 'vad', label: 'Voice detection', hint: 'Knows when you pause', category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION, entry: p?.vad ?? null, optional: true },
  ];
}

/** Required (non-VAD) slots that have a resolved model entry. */
function requiredSlots(): PipelineSlot[] {
  return pipelineSlots().filter((slot) => !slot.optional && slot.entry);
}

/** Whether every required pipeline model is downloaded + loaded. */
function pipelineReady(): boolean {
  const required = requiredSlots();
  return required.length === 3 && required.every((slot) => isModelLoaded(slot.entry!.id));
}

function isActiveState(state: SessionState): boolean {
  // iOS parity: VoiceAgentViewModel.swift:108-115 `isActive`.
  return state === 'listening'
    || state === 'processing'
    || state === 'speaking'
    || state === 'connecting';
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

export function initVoiceTab(el: HTMLElement): TabLifecycle {
  container = el;
  unmounted = false;
  ensureVoicePipeline();
  renderView();
  return {
    onActivate: () => {
      unmounted = false;
      ensureVoicePipeline();
      if (!unsubscribeModelState) {
        // Reflect download/load progress driven by the shared model registry.
        unsubscribeModelState = onModelStateChange(() => scheduleRender());
      }
      renderView();
    },
    onDeactivate: () => {
      unmounted = true;
      unsubscribeModelState?.();
      unsubscribeModelState = null;
      void stopSession({ silent: true });
    },
  };
}

/**
 * Probe hardware once and derive the best-for-device voice trio (+ VAD). Cached
 * for the session; re-renders when it resolves so the setup card fills in.
 */
function ensureVoicePipeline(): void {
  if (voicePipeline || pipelineProbePending) return;
  pipelineProbePending = true;
  void detectDeviceCapabilities()
    .then((caps) => {
      voicePipeline = recommendVoicePipeline(caps.tier, caps.memoryBudgetBytes, getCatalog());
    })
    .catch((err) => {
      console.warn('[voice] pipeline recommendation failed', err);
    })
    .finally(() => {
      pipelineProbePending = false;
      if (!unmounted) renderView();
    });
}

/** Download + load every required pipeline model in sequence, then VAD. */
async function setupPipeline(): Promise<void> {
  if (settingUpPipeline) return;
  settingUpPipeline = true;
  renderView();
  try {
    // Required trio first so Start unlocks as early as possible, then the
    // optional VAD (best-effort; the SDK also auto-loads it).
    const ordered = pipelineSlots().filter((slot) => slot.entry);
    for (const slot of ordered) {
      const ok = await ensureModelReady(slot.entry!.id);
      if (!ok && !slot.optional) {
        // Surface the failure but keep going so the user sees which slot failed.
        lastError = `Could not set up ${slot.label}. Tap it to try another model.`;
      }
    }
  } finally {
    settingUpPipeline = false;
    if (!unmounted) renderView();
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderView(): void {
  if (unmounted) return;

  const isActive = isActiveState(sessionState);
  const allReady = pipelineReady();

  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Voice AI</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="voice-refresh-btn">Refresh</button>
      </div>
    </div>
    <div class="scroll-area">
      ${renderSetupCard(allReady)}

      <div class="docs-section">
        <h3>Conversation</h3>
        <p class="text-secondary">Speak naturally — the agent listens, thinks,
        and replies out loud, entirely on your device. Nothing leaves the
        browser.</p>
        <div class="toolbar-actions">
          <button
            class="btn btn-primary"
            id="voice-start-btn"
            ${allReady && !isActive ? '' : 'disabled'}
          >${isActive ? 'Conversation active' : 'Start conversation'}</button>
          <button
            class="btn btn-secondary"
            id="voice-stop-btn"
            ${isActive ? '' : 'disabled'}
          >Stop</button>
        </div>
        <div class="docs-status">
          <strong>State:</strong>
          <span id="voice-state-pill" class="badge ${stateBadgeClass(sessionState)}">${prettyState(sessionState)}</span>
          ${isSpeechDetected ? '<span class="badge badge-green" style="margin-left:6px">Speech detected</span>' : ''}
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

      <div class="docs-section">
        <h3>Assistant</h3>
        <pre id="voice-assistant-response" class="docs-pre">${escapeHtml(assistantResponse || '(no response yet)')}</pre>
      </div>
    </div>
  `;

  attachHandlers();
}

/**
 * The single "Voice AI" setup card: the pre-selected trio (+ VAD) with
 * per-component status/progress, one primary button that downloads + loads
 * everything, and a subtle per-component "Change" affordance.
 */
function renderSetupCard(allReady: boolean): string {
  if (!voicePipeline) {
    return `
      <div class="voice-setup">
        <div class="voice-setup__head">
          <div class="voice-setup__title">Setting up Voice AI…</div>
          <div class="voice-setup__subtitle">Finding the best models for your device.</div>
        </div>
      </div>
    `;
  }

  const slots = pipelineSlots().filter((slot) => slot.entry || !slot.optional);
  const rows = slots.map(renderSlotRow).join('');

  const primary = allReady
    ? `<div class="voice-setup__ready"><span class="badge badge-green">Ready</span> Your voice assistant is set up.</div>`
    : `<button class="btn btn-primary btn-lg" id="voice-setup-btn" ${settingUpPipeline ? 'disabled' : ''}>
         ${settingUpPipeline ? 'Setting up…' : 'Set up Voice AI'}
       </button>
       <div class="voice-setup__note">Downloads &amp; loads all components. Runs fully offline afterward.</div>`;

  return `
    <div class="voice-setup">
      <div class="voice-setup__head">
        <div class="voice-setup__glyph">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">
            <path d="M12 2a3 3 0 0 1 3 3v6a3 3 0 0 1-6 0V5a3 3 0 0 1 3-3z"/>
            <path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>
          </svg>
        </div>
        <div>
          <div class="voice-setup__title">Voice AI</div>
          <div class="voice-setup__subtitle">Talk to a fully on-device assistant — pre-tuned for your hardware.</div>
        </div>
      </div>
      <div class="voice-setup__slots">${rows}</div>
      <div class="voice-setup__actions">${primary}</div>
    </div>
  `;
}

/** One pipeline component row inside the setup card. */
function renderSlotRow(slot: PipelineSlot): string {
  const entry = slot.entry;
  if (!entry) {
    return `
      <div class="voice-slot voice-slot--missing">
        <div class="voice-slot__icon">${modalityEmoji(slot.category)}</div>
        <div class="voice-slot__body">
          <div class="voice-slot__label">${escapeHtml(slot.label)}</div>
          <div class="voice-slot__hint">No model available for this device.</div>
        </div>
      </div>
    `;
  }

  const status = getModelStatus(entry.id);
  const family = modelFamily(entry).name;
  const stateHtml = renderSlotState(status);
  const changeBtn = `<button type="button" class="voice-slot__change" data-change="${slot.key}">Change</button>`;

  return `
    <div class="voice-slot voice-slot--${status.status}" data-slot="${slot.key}">
      <div class="voice-slot__icon">${modalityEmoji(slot.category)}</div>
      <div class="voice-slot__body">
        <div class="voice-slot__label">${escapeHtml(slot.label)}${slot.optional ? ' <span class="voice-slot__opt">optional</span>' : ''}</div>
        <div class="voice-slot__hint">${escapeHtml(slot.hint)} · ${escapeHtml(family)} <span class="voice-slot__feel">${escapeHtml(variantSizeFeel(entry))}</span></div>
        ${status.status === 'downloading'
          ? `<div class="progress-bar voice-slot__progress"><div class="progress-fill" style="width:${Math.round(status.progress * 100)}%"></div></div>`
          : ''}
      </div>
      <div class="voice-slot__aside">
        ${stateHtml}
        ${changeBtn}
      </div>
    </div>
  `;
}

function renderSlotState(status: ReturnType<typeof getModelStatus>): string {
  switch (status.status) {
    case 'loaded':
      return '<span class="voice-slot__state voice-slot__state--ready">&#10003; Ready</span>';
    case 'downloaded':
      return '<span class="voice-slot__state">On device</span>';
    case 'downloading':
      return `<span class="voice-slot__state">${Math.round(status.progress * 100)}%</span>`;
    case 'loading':
      return '<span class="voice-slot__state">Loading…</span>';
    case 'error':
      return '<span class="voice-slot__state voice-slot__state--error">Failed</span>';
    default:
      return '<span class="voice-slot__state voice-slot__state--pending">Not set up</span>';
  }
}

function attachHandlers(): void {
  container.querySelector('#voice-refresh-btn')?.addEventListener('click', () => renderView());
  container.querySelector('#voice-start-btn')?.addEventListener('click', () => void startSession());
  container.querySelector('#voice-stop-btn')?.addEventListener('click', () => void stopSession());
  container.querySelector('#voice-setup-btn')?.addEventListener('click', () => void setupPipeline());
  container.querySelectorAll<HTMLElement>('[data-change]').forEach((el) => {
    el.addEventListener('click', () => {
      const slot = pipelineSlots().find((s) => s.key === el.dataset.change);
      if (slot) openSheet({ title: `Choose ${slot.label}`, filterCategories: [slot.category] });
    });
  });
}

// ---------------------------------------------------------------------------
// Session control
// ---------------------------------------------------------------------------

async function startSession(): Promise<void> {
  if (isActiveState(sessionState)) return;

  // Reset state (iOS parity: VoiceAgentViewModel.swift:452-456).
  userTranscript = '';
  assistantResponse = '';
  lastError = null;
  isSpeechDetected = false;
  sessionState = 'connecting';
  setEventSummary('Connecting...');
  renderView();

  try {
    // Initialize against the currently-loaded LLM/STT/TTS components. The
    // SDK owns the multi-step bootstrap (VAD auto-load + model composition).
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
    lastError = `Failed to start voice session: ${formatError(err)}`;
    sessionState = 'error';
    setEventSummary('Start failed.');
    await stopSession({ silent: true });
    renderView();
  }
}

async function stopSession(opts: { silent?: boolean } = {}): Promise<void> {
  const wasActive = isActiveState(sessionState);

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
  isSpeechDetected = false;

  try {
    await RunAnywhere.cleanupVoiceAgent();
  } catch {
    // Cleanup is best-effort — silently swallow.
  }

  // iOS parity: VoiceAgentViewModel.swift:484-494 `stopConversation` returns
  // to .disconnected ("Ready").
  if (wasActive && sessionState !== 'error') {
    sessionState = 'disconnected';
    setEventSummary('Session stopped.');
  }

  if (!opts.silent) renderView();
}

// ---------------------------------------------------------------------------
// Event stream consumer
// ---------------------------------------------------------------------------

async function consumeEvents(signal: AbortSignal): Promise<void> {
  try {
    // Swift parity: `streamVoiceAgent()` finishes EMPTY when the agent is not
    // ready — no synthetic error events arrive on the iterator, so a stream
    // that ends right away simply returns the UI to the Ready state below.
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
      lastError = `Voice agent stream error: ${formatError(err)}`;
      sessionState = 'error';
      renderView();
    }
  } finally {
    if (!signal.aborted && !unmounted) {
      // The stream finished on its own (agent stopped or was never ready).
      if (sessionState !== 'error') {
        sessionState = 'disconnected';
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

/** iOS parity: VoiceAgentViewModel.swift:507-529 `.state` arm. */
function applyStateChange(state: StateChangeEvent): void {
  switch (state.current) {
    case VoiceEventPipelineState.PIPELINE_STATE_IDLE:
      sessionState = 'listening';
      break;
    case VoiceEventPipelineState.PIPELINE_STATE_LISTENING:
      if (sessionState !== 'listening' && sessionState !== 'speaking' && sessionState !== 'processing') {
        sessionState = 'listening';
      }
      break;
    case VoiceEventPipelineState.PIPELINE_STATE_PROCESSING_SPEECH:
    case VoiceEventPipelineState.PIPELINE_STATE_THINKING:
    case VoiceEventPipelineState.PIPELINE_STATE_GENERATING_RESPONSE:
      sessionState = 'processing';
      isSpeechDetected = false;
      break;
    case VoiceEventPipelineState.PIPELINE_STATE_SPEAKING:
    case VoiceEventPipelineState.PIPELINE_STATE_PLAYING_TTS:
      sessionState = 'speaking';
      break;
    case VoiceEventPipelineState.PIPELINE_STATE_STOPPED:
      sessionState = 'disconnected';
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

/** iOS parity: VoiceAgentViewModel.swift:531-548 `.vad` arm. */
function applyVadEvent(vad: VADEvent): void {
  switch (vad.type) {
    case VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY:
      if (vad.isSpeech) {
        isSpeechDetected = true;
      } else {
        sessionState = 'processing';
        isSpeechDetected = false;
      }
      scheduleRender();
      break;
    case VADStreamEventKind.VAD_STREAM_EVENT_KIND_STOPPED:
      sessionState = 'processing';
      isSpeechDetected = false;
      scheduleRender();
      break;
    default:
      break;
  }
}

function applyUserSaid(userSaid: UserSaidEvent): void {
  // Partial hypotheses overwrite; finals stay until the next turn starts.
  userTranscript = userSaid.text;
}

function applyAssistantToken(token: AssistantTokenEvent): void {
  // Append ALL token text — thought tokens included — exactly like iOS
  // (iOS parity: VoiceAgentViewModel.swift:553-555). Mark the token kind in
  // the event summary only.
  assistantResponse += token.text;
  if (token.kind === TokenKind.TOKEN_KIND_THOUGHT) {
    setEventSummary('assistant token (thought)');
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
    lastError = `Audio playback failed: ${formatError(err)}`;
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
  // Copy into a fresh ArrayBuffer (the proto bytes may be a view into a
  // larger heap buffer).
  const copy = new Uint8Array(frame.pcm.byteLength);
  copy.set(frame.pcm);
  if (frame.encoding === AudioEncoding.AUDIO_ENCODING_PCM_S16_LE) {
    // SDK-owned Int16→Float32 conversion (Swift parity:
    // RunAnywhere.pcm16ToFloat32 — no app-side PCM math).
    return pcm16ToFloat32(copy.buffer);
  }
  // Default to PCM-F32 little-endian (encoding 0 / unspecified or explicit).
  return new Float32Array(copy.buffer);
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

/** iOS parity: VoiceAgentTypes.swift:34-44 `displayName`. */
function prettyState(state: SessionState): string {
  switch (state) {
    case 'disconnected': return 'Ready';
    case 'connecting': return 'Connecting';
    case 'connected': return 'Ready';
    case 'listening': return 'Listening';
    case 'processing': return 'Thinking';
    case 'speaking': return 'Speaking';
    case 'error': return 'Error';
  }
}

function stateBadgeClass(state: SessionState): string {
  switch (state) {
    case 'listening':
    case 'connected':
      return 'badge-green';
    case 'processing':
    case 'speaking':
    case 'connecting':
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
