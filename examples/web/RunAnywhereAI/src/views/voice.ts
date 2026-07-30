/**
 * Voice Tab — V2 canonical voice agent.
 *
 * Mirrors the iOS `VoiceAgentViewModel` pattern (Swift source-of-truth):
 *
 *   1. The view recommends (or the user picks) an STT / LLM / TTS trio from
 *      the shared catalog.
 *   2. `RunAnywhere.voice.createSession({ stt, llm, tts })` owns every
 *      prerequisite: it downloads and loads those three models, ensures a VAD
 *      is resident, and wires the pipeline. Nothing here pre-loads anything.
 *   3. `session.start()` is the only thing that opens the microphone;
 *      `session.events` is consumed as `AsyncIterable<VoiceEvent>`.
 *   4. Each event variant drives one UI region:
 *        - `agentStateChanged`  → session status pill
 *        - `speechStarted`/`speechEnded` → speech-detected indicator
 *        - `userTranscribed`    → live transcript area
 *        - `agentResponse`      → assistant response
 *        - `error`              → inline error banner
 *   5. Stop: `session.close()` releases the microphone and the pipeline.
 *
 * Backends (llamacpp + ONNX) are registered once at app init by `main.ts` —
 * this view assumes they exist and surfaces the SDK's typed error if a verb
 * throws `backendNotAvailable`.
 */

import type { TabLifecycle } from '../app';
import {
  RunAnywhere,
  ModelCategory,
  type VoiceEvent,
  type VoiceSession,
} from '@runanywhere/web';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import { appLogger } from '../services/app-logger';
import { getCatalog, type CatalogEntry } from '../services/model-catalog';
import { detectDeviceCapabilities } from '../services/device-capabilities';
import {
  recommendVoicePipeline,
  type VoicePipelineSelection,
} from '../services/model-recommendation';
import {
  cleanModelName,
  formatBytes,
  formatFramework,
  modalityEmoji,
  modelDisplaySizeBytes,
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

let session: VoiceSession | null = null;
let eventConsumer: AbortController | null = null;
let sessionState: SessionState = 'disconnected';
let isSpeechDetected = false;
let userTranscript = '';
let assistantResponse = '';
let lastError: string | null = null;
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
  category: ModelCategory;
  entry: CatalogEntry | null;
  /** VAD is optional — the SDK auto-loads it; we don't gate Start on it. */
  optional: boolean;
}

function pipelineSlots(): PipelineSlot[] {
  const p = voicePipeline;
  return [
    { key: 'stt', label: 'Speech-to-text', category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, entry: p?.stt ?? null, optional: false },
    { key: 'llm', label: 'Chat model', category: ModelCategory.MODEL_CATEGORY_LANGUAGE, entry: p?.llm ?? null, optional: false },
    { key: 'tts', label: 'Text-to-speech', category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS, entry: p?.tts ?? null, optional: false },
    { key: 'vad', label: 'Voice detection', category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION, entry: p?.vad ?? null, optional: true },
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
      appLogger.warning('[voice] pipeline recommendation failed', err);
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
        <p class="text-secondary">Speak naturally — after setup, voice capture
        and AI inference run in this browser.</p>
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
       <div class="voice-setup__note">Downloads &amp; loads all components. Voice inference runs offline afterward.</div>`;

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
  const stateHtml = renderSlotState(status);
  const changeBtn = `<button type="button" class="voice-slot__change" data-change="${slot.key}">Change</button>`;

  return `
    <div class="voice-slot voice-slot--${status.status}" data-slot="${slot.key}">
      <div class="voice-slot__icon">${modalityEmoji(slot.category)}</div>
      <div class="voice-slot__body">
        <div class="voice-slot__label">${escapeHtml(slot.label)}${slot.optional ? ' <span class="voice-slot__opt">optional</span>' : ''}</div>
        <div class="voice-slot__hint">
          ${escapeHtml(cleanModelName(entry.name))}
          · ${formatBytes(modelDisplaySizeBytes(entry))}
          <span class="backend-pill">${escapeHtml(formatFramework(entry.framework))}</span>
        </div>
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
      if (!slot) return;
      openSheet({
        title: `Choose ${slot.label}`,
        filterCategories: [slot.category],
        onModelReady: (entry) => updatePipelineSlot(slot.key, entry),
      });
    });
  });
}

/** Replace one recommendation after the picker confirms the model is ready. */
function updatePipelineSlot(
  key: PipelineSlot['key'],
  entry: CatalogEntry,
): void {
  if (!voicePipeline) return;
  voicePipeline = { ...voicePipeline, [key]: entry };
  lastError = null;
  if (!unmounted) renderView();
}

// ---------------------------------------------------------------------------
// Session control
// ---------------------------------------------------------------------------

async function startSession(): Promise<void> {
  if (isActiveState(sessionState)) return;
  const pipeline = voicePipeline;
  if (!pipeline?.stt || !pipeline.llm || !pipeline.tts) {
    lastError = 'Pick an STT, LLM, and TTS model before starting a session.';
    sessionState = 'error';
    renderView();
    return;
  }

  userTranscript = '';
  assistantResponse = '';
  lastError = null;
  isSpeechDetected = false;
  sessionState = 'connecting';
  setEventSummary('Connecting...');
  renderView();

  try {
    // One entry point owns download, load, VAD, and pipeline wiring.
    session = await RunAnywhere.voice.createSession({
      stt: { id: pipeline.stt.id },
      llm: { id: pipeline.llm.id },
      tts: { id: pipeline.tts.id },
    });

    // Subscribing never opens the mic; `start()` is what does.
    eventConsumer = new AbortController();
    void consumeEvents(eventConsumer.signal);
    await session.start();

    sessionState = 'listening';
    setEventSummary('Listening...');
    renderView();
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

  if (session) {
    try {
      await session.close();
    } catch {
      // Close is best-effort — the session releases the mic either way.
    }
    session = null;
  }

  isSpeechDetected = false;

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
  const active = session;
  if (!active) return;
  try {
    for await (const event of active.events) {
      if (signal.aborted || unmounted) break;
      handleVoiceEvent(event);
      // Pre-compute the affected DOM regions so a token never replaces the
      // whole panel and jitters the transcript.
      updateTextRegions();
    }
  } catch (err) {
    if (!signal.aborted) {
      lastError = `Voice agent stream error: ${formatError(err)}`;
      sessionState = 'error';
      renderView();
    }
  } finally {
    if (!signal.aborted && !unmounted && sessionState !== 'error') {
      sessionState = 'disconnected';
      renderView();
    }
  }
}

function handleVoiceEvent(event: VoiceEvent): void {
  switch (event.type) {
    case 'agentStateChanged':
      sessionState = event.state === 'thinking' ? 'processing' : event.state;
      if (event.state !== 'listening') isSpeechDetected = false;
      setEventSummary(`state: ${event.state}`);
      scheduleRender();
      break;
    case 'speechStarted':
      isSpeechDetected = true;
      setEventSummary('speech started');
      scheduleRender();
      break;
    case 'speechEnded':
      isSpeechDetected = false;
      setEventSummary('speech ended');
      scheduleRender();
      break;
    case 'userTranscribed':
      // Partial hypotheses overwrite; a final clears the previous answer.
      userTranscript = event.text;
      if (event.isFinal) assistantResponse = '';
      break;
    case 'agentResponse':
      assistantResponse = event.text;
      break;
    case 'error':
      lastError = event.message;
      if (!event.recoverable) sessionState = 'error';
      scheduleRender();
      break;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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
