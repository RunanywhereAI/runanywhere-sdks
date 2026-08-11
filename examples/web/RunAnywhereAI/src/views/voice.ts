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
import {
  recommendVoicePipeline,
  type VoicePipelineSelection,
} from '../services/model-recommendation';
import { canRunByModelID } from '../services/model-compatibility-lookup';
import {
  ensureModelReady,
  isModelLoaded,
  onModelStateChange,
  openSheet,
  runEngineRetry,
} from '../components/model-selection';
import { renderModelSlot, type ModelSlotView } from '../components/model-slot';
import { icon } from '../components/icons';
import {
  canRetryEngines,
  describeFailures,
  failuresForEntries,
  isRetryingForEntries,
  onEngineStateChange,
  type EngineFailure,
} from '../services/engine-availability';

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
/**
 * Whether `userTranscript` is a settled result or a live hypothesis.
 *
 * A partial hypothesis is a guess that will be revised — words visibly change
 * under the reader as more audio arrives. Rendering it identically to the final
 * transcript makes the panel look like it is malfunctioning. Every other app
 * distinguishes the two, so this does too.
 */
let isTranscriptFinal = false;
let assistantResponse = '';
let lastError: string | null = null;
/** True from the moment interrupt() is called until the agent leaves `speaking`. */
let interrupting = false;

// Pre-selected best-for-device voice trio (+ VAD), computed once on first
// activation. `null` until the async capability probe resolves.
let voicePipeline: VoicePipelineSelection | null = null;
let pipelineProbePending = false;
let settingUpPipeline = false;
let unsubscribeModelState: (() => void) | null = null;
let unsubscribeEngineState: (() => void) | null = null;

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

/** Adapt a pipeline slot to the shared setup-card row. */
function slotView(slot: PipelineSlot): ModelSlotView {
  return { ...slot, changeable: true };
}

/** Required (non-VAD) slots that have a resolved model entry. */
function requiredSlots(): PipelineSlot[] {
  return pipelineSlots().filter((slot) => !slot.optional && slot.entry);
}

/**
 * Engine failures that actually block *this* pipeline.
 *
 * Scoped to the models the card names, so a llama.cpp failure is reported here
 * only because the chat slot needs it — not because some other tab does.
 */
function pipelineFailures(): readonly EngineFailure[] {
  return failuresForEntries(pipelineEntries());
}

function pipelineEntries(): CatalogEntry[] {
  return pipelineSlots()
    .map((slot) => slot.entry)
    .filter((entry): entry is CatalogEntry => entry !== null);
}

/** True while a retry is re-checking an engine this pipeline needs. */
function pipelineRechecking(): boolean {
  return isRetryingForEntries(pipelineEntries());
}

/** Blocked, or mid-recheck after being blocked — either way, not startable. */
function pipelineBlocked(): boolean {
  return pipelineFailures().length > 0 || pipelineRechecking();
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
      if (!unsubscribeEngineState) {
        // A retry that succeeds has to unblock this card without a tab switch.
        unsubscribeEngineState = onEngineStateChange(() => scheduleRender());
      }
      renderView();
    },
    onDeactivate: () => {
      unmounted = true;
      unsubscribeModelState?.();
      unsubscribeModelState = null;
      unsubscribeEngineState?.();
      unsubscribeEngineState = null;
      void stopSession({ silent: true });
    },
  };
}

/**
 * Probe commons can_run once and derive the voice trio (+ VAD). Cached for
 * the session; re-renders when it resolves so the setup card fills in.
 * No local tier/budget — unknown fit treats engine-compatible catalog entries
 * as eligible.
 */
function ensureVoicePipeline(): void {
  if (voicePipeline || pipelineProbePending) return;
  pipelineProbePending = true;
  const catalog = getCatalog();
  void canRunByModelID(catalog.map((entry) => entry.id))
    .then((canRun) => {
      voicePipeline = recommendVoicePipeline(catalog, canRun);
    })
    .catch((err) => {
      appLogger.warning('[voice] pipeline recommendation failed', err);
      voicePipeline = recommendVoicePipeline(catalog, {});
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
  // "Needs setup" would be a lie while the engine is missing: no amount of
  // setting up helps, and the sentence sends the user back to a button that
  // cannot finish.
  const blocked = pipelineBlocked();

  container.innerHTML = `
    <div class="toolbar">
      <!-- "Talk", matching this panel's nav row and Android's drawer row. Every other
           panel's title is its nav label; this one said "Voice AI", so the reader
           arrived somewhere apparently different from what they clicked. The setup card
           below still carries "Voice AI" as the feature's own name, which is what the
           iOS and Android setup cards call it too. -->
      <div class="toolbar-title">Talk</div>
      <div class="toolbar-actions">
        <button class="btn btn-secondary" id="voice-refresh-btn">Refresh</button>
      </div>
    </div>
    <div class="scroll-area">
      ${renderSetupCard(allReady)}

      <div class="docs-section">
        <h3>Conversation</h3>
        <p class="text-secondary">Speak naturally. Your microphone opens only
        while a conversation is running, and both speech recognition and the
        reply are computed in this browser — no audio leaves the device.</p>
        <div class="toolbar-actions">
          <button
            class="btn btn-primary"
            id="voice-start-btn"
            ${allReady && !isActive && !blocked ? '' : 'disabled'}
          >${isActive ? 'Conversation active' : 'Start conversation'}</button>
          ${
            /*
             * The deterministic half of taking the turn back. `session.interrupt()`
             * cuts the agent off mid-utterance and keeps the session open, which
             * is what a person who has heard enough actually wants — not ending
             * the call. The SDK has always exposed it and this view never called
             * it, so the only way to stop a long-winded reply was Stop, which
             * closes the session and releases the microphone. It replaces Stop
             * while the agent is speaking because those are the same intent at
             * that moment, and two adjacent stop-shaped buttons would be a coin
             * toss.
             *
             * The other half is acoustic: the mic driver's barge-in gate cuts the
             * same reply when the user simply speaks over it. The button is not a
             * substitute for a missing capability — it is the version that works
             * without having to out-shout the speaker, so it stays.
             */
            sessionState === 'speaking'
              ? `<button class="btn btn-secondary" id="voice-interrupt-btn" ${interrupting ? 'disabled' : ''}>
                   ${icon('stop', { size: 16 })}
                   <span>${interrupting ? 'Stopping…' : 'Stop talking'}</span>
                 </button>`
              : `<button
                  class="btn btn-secondary"
                  id="voice-stop-btn"
                  ${isActive ? '' : 'disabled'}
                >End conversation</button>`
          }
        </div>
        <div class="docs-status" role="status" aria-live="polite">
          <span id="voice-state-pill" class="badge ${blocked ? 'badge-yellow' : stateBadgeClass(sessionState, allReady)}">${blocked ? (pipelineRechecking() ? 'Re-checking engine' : 'Engine unavailable') : prettyState(sessionState, allReady)}</span>
          ${isSpeechDetected ? '<span class="badge badge-green">Hearing you</span>' : ''}
        </div>
        ${lastError
          ? `<div class="docs-status error">${escapeHtml(lastError)}</div>`
          : ''}
      </div>

      ${userTranscript || assistantResponse || isActive
        ? `<div class="docs-section">
             <h3>You said</h3>
             <pre id="voice-user-transcript" class="docs-pre${transcriptModifier()}">${escapeHtml(userTranscript || transcriptPlaceholder())}</pre>
           </div>

           <div class="docs-section">
             <h3>Reply</h3>
             <pre id="voice-assistant-response" class="docs-pre">${escapeHtml(assistantResponse || replyPlaceholder())}</pre>
           </div>`
        : ''}
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
      <div class="setup-card">
        <div class="setup-card__head">
          <div class="setup-card__title">Setting up Voice AI…</div>
          <div class="setup-card__subtitle">Finding the best models for your device.</div>
        </div>
      </div>
    `;
  }

  const slots = pipelineSlots().filter((slot) => slot.entry || !slot.optional);
  const rows = slots.map((slot) => renderModelSlot(slotView(slot))).join('');

  // A "Set up Voice AI" button that downloads models whose engine never loaded
  // spends the user's bandwidth to arrive back at the same dead card. Offer the
  // only action that can change the outcome instead.
  const failures = pipelineFailures();
  const rechecking = pipelineRechecking();
  const primary = failures.length > 0 || rechecking
    ? `<div class="setup-card__note">${escapeHtml(
        rechecking
          ? 'Re-checking the on-device AI engine…'
          : describeFailures(failures),
      )}</div>
       ${canRetryEngines()
         ? `<button class="btn btn-secondary btn-lg" id="voice-engine-retry" ${rechecking ? 'disabled' : ''}>
              ${rechecking ? 'Re-checking…' : 'Retry setup'}
            </button>`
         : ''}`
    : allReady
      ? `<div class="setup-card__ready"><span class="badge badge-green">Ready</span> Your voice assistant is set up.</div>`
      : `<button class="btn btn-primary btn-lg" id="voice-setup-btn" ${settingUpPipeline ? 'disabled' : ''}>
           ${settingUpPipeline ? 'Setting up…' : 'Set up Voice AI'}
         </button>
         <div class="setup-card__note">Downloads &amp; loads all components. Voice inference runs offline afterward.</div>`;

  return `
    <div class="setup-card">
      <div class="setup-card__head">
        <div class="setup-card__glyph">
          ${icon('mic', { size: 24 })}
        </div>
        <div>
          <div class="setup-card__title">Voice AI</div>
          <div class="setup-card__subtitle">Talk to a fully on-device assistant — pre-tuned for your hardware.</div>
        </div>
      </div>
      <div class="setup-card__slots">${rows}</div>
      <div class="setup-card__actions">${primary}</div>
    </div>
  `;
}

function attachHandlers(): void {
  container.querySelector('#voice-refresh-btn')?.addEventListener('click', () => renderView());
  container.querySelector('#voice-start-btn')?.addEventListener('click', () => void startSession());
  container.querySelector('#voice-stop-btn')?.addEventListener('click', () => void stopSession());
  container.querySelector('#voice-interrupt-btn')?.addEventListener('click', () => void interruptAgent());
  container.querySelector('#voice-setup-btn')?.addEventListener('click', () => void setupPipeline());
  container.querySelector('#voice-engine-retry')?.addEventListener('click', () => void runEngineRetry());
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
  isTranscriptFinal = false;
  assistantResponse = '';
  lastError = null;
  isSpeechDetected = false;
  interrupting = false;
  sessionState = 'connecting';
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
    renderView();
  } catch (err) {
    lastError = `Failed to start voice session: ${formatError(err)}`;
    sessionState = 'error';
    await stopSession({ silent: true });
    renderView();
  }
}

/**
 * Cut the agent off mid-utterance and hand the turn back.
 *
 * `interrupt()` resolves only once the interrupted response, its tools, and its
 * playout have all settled, so the button is disabled for that whole window
 * rather than staying live and inviting a second press that would queue behind
 * the first. The session stays open throughout — this is the difference between
 * interrupting and hanging up.
 */
async function interruptAgent(): Promise<void> {
  const active = session;
  if (!active || interrupting) return;
  interrupting = true;
  renderView();
  try {
    await active.interrupt();
  } catch (err) {
    // A failed interrupt leaves the session usable, so this is a notice, not an
    // error state — dropping to `error` would imply the conversation is over.
    lastError = `Could not interrupt: ${formatError(err)}`;
  } finally {
    interrupting = false;
    if (!unmounted) renderView();
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
  interrupting = false;

  if (wasActive && sessionState !== 'error') {
    sessionState = 'disconnected';
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
      // Leaving `speaking` is what actually ends an interrupt, whether the
      // interrupt caused it or the agent simply finished the sentence.
      if (event.state !== 'speaking') interrupting = false;
      scheduleRender();
      break;
    case 'speechStarted':
      isSpeechDetected = true;
      scheduleRender();
      break;
    case 'speechEnded':
      isSpeechDetected = false;
      scheduleRender();
      break;
    case 'userTranscribed':
      // Partial hypotheses overwrite; a final clears the previous answer.
      userTranscript = event.text;
      isTranscriptFinal = event.isFinal;
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

let renderScheduled = false;
function scheduleRender(): void {
  if (renderScheduled || unmounted) return;
  renderScheduled = true;
  requestAnimationFrame(() => {
    renderScheduled = false;
    renderView();
  });
}

/**
 * What an empty transcript pane says, given what the agent is actually doing.
 *
 * These were two fixed strings, so an empty pane read "Listening…" while the
 * agent was thinking and "Waiting for you to finish speaking…" while it was
 * already talking — the panel contradicting the status pill directly above it.
 * An empty state is still a claim about the system, and it has to be a true one.
 */
function transcriptPlaceholder(): string {
  switch (sessionState) {
    case 'connecting': return 'Getting ready…';
    case 'listening': return isSpeechDetected ? 'Listening…' : 'Go ahead — say something.';
    case 'processing': return 'Working out a reply…';
    // Both affordances are real, so both are named. `VoiceAgentMicDriver.onChunk`
    // tests `replyAudible` *before* the segmenter's `processing` gate and hands
    // the frame to `evaluateBargeIn`, which stops playout and publishes
    // `speechStarted` — talking over the reply genuinely takes the turn back.
    // This line used to deny that, because the Stop-talking button landed one
    // commit before the barge-in gate existed and the copy was never revisited;
    // a placeholder that hides a working affordance is as untrue as one that
    // promises a missing one. The button is still worth naming because the gate
    // is deliberately hard to trip — it wants 3x ordinary speech level and 2.5x
    // the reply's own measured echo, precisely so the agent can never interrupt
    // itself — whereas a press is unconditional. "Take the turn back" is the
    // phrase all four apps use for this moment.
    case 'speaking': return 'Speaking. Talk over it to take the turn back, or use “Stop talking”.';
    default: return 'Nothing heard yet.';
  }
}

function replyPlaceholder(): string {
  switch (sessionState) {
    case 'connecting': return 'Getting ready…';
    case 'listening': return 'Waiting for you to finish speaking…';
    case 'processing': return 'Thinking…';
    case 'speaking': return 'Speaking…';
    default: return 'No reply yet.';
  }
}

/** `--partial` while the transcript is a revisable hypothesis. */
function transcriptModifier(): string {
  return userTranscript && !isTranscriptFinal ? ' docs-pre--partial' : '';
}

/**
 * Patch just the two text regions.
 *
 * Per-token `renderView()` would rebuild the whole panel and reset scroll and
 * focus on every partial hypothesis, so the streaming path writes textContent
 * directly. `textContent` (never innerHTML) is what makes that safe for
 * model-authored text.
 */
function updateTextRegions(): void {
  const userPre = container.querySelector<HTMLPreElement>('#voice-user-transcript');
  if (userPre) {
    userPre.textContent = userTranscript || transcriptPlaceholder();
    // Toggled here rather than only in renderView because the settle from
    // partial to final arrives as an event, not a re-render.
    userPre.classList.toggle('docs-pre--partial', Boolean(userTranscript) && !isTranscriptFinal);
  }
  const respPre = container.querySelector<HTMLPreElement>('#voice-assistant-response');
  if (respPre) respPre.textContent = assistantResponse || replyPlaceholder();
}

/**
 * iOS parity: VoiceAgentTypes.swift:34-44 `displayName`, with one divergence.
 *
 * iOS maps `.disconnected` to "Ready", which is true there because its voice
 * screen is only reachable once models are resident. Here the same state is the
 * *pre-setup* state, so echoing "Ready" put a green "Ready" pill directly below
 * four rows reading "Not set up" — two opposite claims about the same thing, on
 * one screen. `allReady` disambiguates: idle-and-unequipped is "Needs setup",
 * idle-and-equipped is "Ready to talk".
 */
function prettyState(state: SessionState, allReady: boolean): string {
  switch (state) {
    case 'disconnected':
    case 'connected':
      return allReady ? 'Ready to talk' : 'Needs setup';
    case 'connecting': return 'Connecting';
    case 'listening': return 'Listening';
    case 'processing': return 'Thinking';
    case 'speaking': return 'Speaking';
    case 'error': return 'Something went wrong';
  }
}

function stateBadgeClass(state: SessionState, allReady: boolean): string {
  switch (state) {
    case 'listening':
      return 'badge-green';
    case 'processing':
    case 'speaking':
    case 'connecting':
      return 'badge-blue';
    case 'error':
      return 'badge-red';
    case 'disconnected':
    case 'connected':
      // Green only once the pipeline can actually start; grey while it can't.
      return allReady ? 'badge-green' : 'badge-grey';
  }
}
