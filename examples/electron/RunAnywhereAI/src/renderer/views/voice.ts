/**
 * Voice (Talk) — STT + LLM + TTS pipeline via `voice.createSession`.
 *
 * Mirrors the legacy Electron orb + Swift `VoiceAgentViewModel`: one entry point
 * owns download/load/VAD; `start()` opens the mic; leaving the route closes it.
 */
import type { AgentState, VoiceEvent, VoiceSession } from '@runanywhere/electron';

import { icon } from '../components/icons';
import { logger } from '../services/logger';
import { errorMessage, modelLabel, selectedModelId } from '../services/modality-models';
import type { ViewFactory, ViewInstance } from '../shell/app';
import { badge, el, section, statusLine } from './dom';

const log = logger('voice');

/** UI states for the orb — maps from SDK {@link AgentState} plus idle/connecting. */
const VoiceUiState = {
  Idle: 'idle',
  Connecting: 'connecting',
  Listening: 'listening',
  Thinking: 'thinking',
  Speaking: 'speaking',
} as const;
type VoiceUiState = (typeof VoiceUiState)[keyof typeof VoiceUiState];

const COPY: Readonly<Record<VoiceUiState, readonly [string, string]>> = {
  [VoiceUiState.Idle]: ['Tap to talk', 'Speech, reasoning and speech-synthesis all run on this device.'],
  [VoiceUiState.Connecting]: ['Preparing…', 'Loading the on-device voice pipeline.'],
  [VoiceUiState.Listening]: ['Listening…', 'Just speak — the turn ends on its own after a short silence.'],
  [VoiceUiState.Thinking]: ['Thinking…', 'Transcribing and composing a reply on-device.'],
  [VoiceUiState.Speaking]: ['Speaking…', 'Tap to interrupt.'],
};

function mapAgentState(state: AgentState): VoiceUiState {
  switch (state) {
    case 'LISTENING':
      return VoiceUiState.Listening;
    case 'THINKING':
      return VoiceUiState.Thinking;
    case 'SPEAKING':
      return VoiceUiState.Speaking;
    default: {
      const _exhaustive: never = state;
      void _exhaustive;
      return VoiceUiState.Listening;
    }
  }
}

export const createVoiceView: ViewFactory = ({ root }): ViewInstance => {
  let session: VoiceSession | null = null;
  let opening: Promise<void> | null = null;
  let uiState: VoiceUiState = VoiceUiState.Idle;
  let userText = '';
  let replyText = '';
  let disposed = false;

  const wrap = el('div', 'ra-view-scroll ra-voice-wrap');
  const stage = el('div', 'ra-voice-stage');
  const orb = el('button', 'ra-voice-orb');
  orb.type = 'button';
  orb.innerHTML =
    `<span class="ra-voice-orb-ring" aria-hidden="true"></span>` +
    `<span class="ra-voice-orb-core">${icon('mic', { size: 28 })}</span>`;
  const status = el('div', 'ra-type-large-title ra-voice-title', COPY[uiState][0]);
  const hint = el('p', 'ra-type-secondary ra-voice-hint', COPY[uiState][1]);
  stage.append(orb, status, hint);

  const transcript = el('div', 'ra-voice-transcript');
  transcript.hidden = true;
  const heardCard = el('div', 'ra-card ra-voice-turn');
  heardCard.append(el('span', 'ra-type-caption ra-voice-who', 'You'), el('div', 'ra-selectable ra-voice-turn-text', ''));
  const replyCard = el('div', 'ra-card ra-voice-turn');
  replyCard.append(
    el('span', 'ra-type-caption ra-voice-who', 'RunAnywhere'),
    el('div', 'ra-selectable ra-voice-turn-text', ''),
  );
  transcript.append(heardCard, replyCard);

  const errorBanner = statusLine('', 'danger');
  errorBanner.hidden = true;

  const setupBody = el('div', 'ra-stack');
  const pipelineNote = el(
    'p',
    'ra-type-secondary',
    'Uses the STT, chat, and TTS models chosen under Models. The session loads them and opens the microphone.',
  );
  const pipelineMeta = el('div', 'ra-row ra-voice-pipeline-meta');
  setupBody.append(pipelineNote, pipelineMeta);

  wrap.append(stage, transcript, errorBanner, section('Voice AI', setupBody));
  root.append(wrap);

  function setUiState(next: VoiceUiState): void {
    uiState = next;
    wrap.dataset.state = next;
    status.textContent = COPY[next][0];
    hint.textContent = COPY[next][1];
    orb.setAttribute('aria-label', COPY[next][0]);
  }

  function showError(message: string): void {
    errorBanner.hidden = false;
    errorBanner.textContent = message;
  }

  function clearError(): void {
    errorBanner.hidden = true;
    errorBanner.textContent = '';
  }

  function paintTranscript(): void {
    const heard = heardCard.querySelector('.ra-voice-turn-text');
    const reply = replyCard.querySelector('.ra-voice-turn-text');
    if (heard instanceof HTMLElement) heard.textContent = userText;
    if (reply instanceof HTMLElement) reply.textContent = replyText;
    transcript.hidden = userText.length === 0 && replyText.length === 0;
  }

  async function refreshPipelineMeta(): Promise<void> {
    try {
      const [stt, llm, tts] = await Promise.all([
        selectedModelId('stt'),
        selectedModelId('llm'),
        selectedModelId('tts'),
      ]);
      pipelineMeta.replaceChildren(
        badge(modelLabel(stt)),
        badge(modelLabel(llm)),
        badge(modelLabel(tts)),
      );
    } catch (error) {
      log.warn('pipeline meta failed', error);
    }
  }

  function handleEvent(event: VoiceEvent): void {
    switch (event.type) {
      case 'agentStateChanged':
        setUiState(mapAgentState(event.state));
        return;
      case 'userTranscribed':
        userText = event.text;
        if (event.isFinal) replyText = '';
        paintTranscript();
        return;
      case 'agentResponse':
        replyText = event.text;
        paintTranscript();
        return;
      case 'speechStarted':
      case 'speechEnded':
        return;
      case 'inputSilent':
        hint.textContent = event.detail;
        return;
      case 'error':
        showError(event.message);
        if (!event.recoverable) void stopSession();
        return;
      default: {
        const _exhaustive: never = event;
        void _exhaustive;
      }
    }
  }

  async function consume(active: VoiceSession): Promise<void> {
    try {
      for await (const event of active.events) {
        if (disposed || session !== active) return;
        handleEvent(event);
      }
    } catch (error) {
      if (!disposed && session === active) showError(errorMessage(error));
    }
  }

  async function startSession(): Promise<void> {
    if (opening !== null || session !== null) return;
    clearError();
    userText = '';
    replyText = '';
    paintTranscript();
    setUiState(VoiceUiState.Connecting);

    opening = (async () => {
      const [stt, llm, tts] = await Promise.all([
        selectedModelId('stt'),
        selectedModelId('llm'),
        selectedModelId('tts'),
      ]);
      const active = await window.runanywhere.voice.createSession({
        stt: { id: stt },
        llm: { id: llm },
        tts: { id: tts },
      });
      if (disposed) {
        await active.close().catch(() => undefined);
        return;
      }
      session = active;
      void consume(active);
      await active.start();
      setUiState(VoiceUiState.Listening);
    })();

    try {
      await opening;
    } catch (error) {
      session = null;
      setUiState(VoiceUiState.Idle);
      showError(`Could not start the voice pipeline: ${errorMessage(error)}`);
    } finally {
      opening = null;
    }
  }

  async function stopSession(): Promise<void> {
    const active = session;
    session = null;
    setUiState(VoiceUiState.Idle);
    if (active !== null) {
      try {
        await active.close();
      } catch {
        /* already closed */
      }
    }
  }

  orb.addEventListener('click', () => {
    void (async () => {
      try {
        if (session === null) {
          await startSession();
          return;
        }
        if (uiState === VoiceUiState.Speaking) {
          await session.interrupt();
          setUiState(VoiceUiState.Listening);
          return;
        }
        await stopSession();
      } catch (error) {
        showError(errorMessage(error));
      }
    })();
  });

  void refreshPipelineMeta();
  setUiState(VoiceUiState.Idle);

  return {
    dispose(): void {
      disposed = true;
      void stopSession();
    },
  };
};
