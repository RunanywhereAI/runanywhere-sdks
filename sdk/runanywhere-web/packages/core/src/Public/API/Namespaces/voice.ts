/**
 * `RunAnywhere.voice` — live speech-to-speech conversation sessions.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  PipelineState,
  type VoiceEvent as ProtoVoiceEvent,
} from '@runanywhere/proto-ts/voice_events';
import { VADStreamEventKind } from '@runanywhere/proto-ts/vad_options';
import { SDKException } from '../../../Foundation/SDKException.js';
import { SDKLogger } from '../../../Foundation/SDKLogger.js';
import { AsyncQueue } from '../../../Foundation/AsyncQueue.js';
import {
  VoiceAgentMicDriver,
  type VoiceAgentMicPhase,
} from '../../../Infrastructure/VoiceAgentMicDriver.js';
import {
  cleanupVoiceAgent,
  ensureDefaultVAD,
  initializeVoiceAgentWithLoadedModels,
  streamVoiceAgent,
} from '../../Extensions/RunAnywhere+VoiceAgent.js';
import { tts as ttsNamespace } from './tts.js';
import type { ModelRef } from '../Inputs.js';
import type { LlmOptions, TurnHandlingOptions, VadOptions } from '../Options.js';
import type { AgentState, VoiceEvent } from '../Events.js';
import type { SpeechHandle } from '../Results.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

const logger = new SDKLogger('voice');

/** Everything needed to start and steer one live conversation. */
export interface VoiceSessionOptions {
  stt: ModelRef;
  llm: ModelRef;
  /** `voice` selects a speaker within a multi-voice synthesis model. */
  tts: ModelRef;
  /** Unset ensures the catalogued default Silero VAD. */
  vad?: VadOptions;
  turnHandling?: TurnHandlingOptions;
  generation?: LlmOptions;
  /** Download any of the three models that are missing. Defaults to `true`. */
  downloadIfNeeded?: boolean;
}

/** A live conversation that owns the microphone while it is running. */
export interface VoiceSession {
  /** Conversation events. Subscribing never opens the microphone. */
  readonly events: AsyncIterable<VoiceEvent>;
  /** Open the microphone and begin the turn loop. */
  start(): Promise<void>;
  /** Speak text immediately, outside the turn loop. */
  say(text: string): Promise<SpeechHandle>;
  /**
   * Stop the agent mid-utterance. Awaitable: resolves once the interrupted
   * `say()`/turn-loop response, its tools, and its playout have all settled.
   */
  interrupt(): Promise<void>;
  /** Close the session and release the microphone. */
  close(): Promise<void>;
}

const DRIVER_PHASE_STATES: Record<VoiceAgentMicPhase, AgentState> = {
  listening: 'listening',
  processing: 'thinking',
  speaking: 'speaking',
};

const AGENT_STATES: Partial<Record<PipelineState, AgentState>> = {
  [PipelineState.PIPELINE_STATE_LISTENING]: 'listening',
  [PipelineState.PIPELINE_STATE_THINKING]: 'thinking',
  [PipelineState.PIPELINE_STATE_PROCESSING_SPEECH]: 'thinking',
  [PipelineState.PIPELINE_STATE_GENERATING_RESPONSE]: 'thinking',
  [PipelineState.PIPELINE_STATE_SPEAKING]: 'speaking',
  [PipelineState.PIPELINE_STATE_PLAYING_TTS]: 'speaking',
};

/** Translate one native voice-pipeline event into the public grammar. */
function toVoiceEvents(event: ProtoVoiceEvent): VoiceEvent[] {
  const out: VoiceEvent[] = [];
  if (event.userSaid) {
    out.push({ type: 'userTranscribed', text: event.userSaid.text, isFinal: event.userSaid.isFinal });
  }
  if (event.assistantToken?.isFinal && event.assistantToken.text) {
    out.push({ type: 'agentResponse', text: event.assistantToken.text });
  }
  const state = event.state ? AGENT_STATES[event.state.current] : undefined;
  if (state) out.push({ type: 'agentStateChanged', state });
  if (event.vad) {
    if (event.vad.type === VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY) {
      out.push(event.vad.isSpeech ? { type: 'speechStarted' } : { type: 'speechEnded' });
    }
  }
  if (event.sessionError) {
    out.push({
      type: 'error',
      message: event.sessionError.message,
      recoverable: event.sessionError.recoverable,
    });
  }
  return out;
}

async function ensureVoiceModels(options: VoiceSessionOptions): Promise<void> {
  await ensureReady();
  if (options.downloadIfNeeded === false) {
    // Residency only: a missing artifact must surface as an error, not a download.
    await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
    await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);
    await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS);
    return;
  }
  await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION, options.stt.id);
  await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE, options.llm.id);
  await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS, options.tts.id);
}

function createSession(options: VoiceSessionOptions): VoiceSession {
  const queue = new AsyncQueue<VoiceEvent>();
  const driver = new VoiceAgentMicDriver();
  let nativePump: AbortController | null = null;
  let closed = false;
  let lastSpeechHandle: SpeechHandle | null = null;

  const publish = (event: VoiceEvent): void => {
    if (!closed) queue.push(event);
  };

  const session: VoiceSession = {
    events: queue,

    async start(): Promise<void> {
      if (closed) throw SDKException.invalidState('This voice session is closed.');
      // The native pipeline is the source of truth for VAD and state events;
      // the mic driver supplies capture and whole-turn results.
      nativePump = new AbortController();
      const signal = nativePump.signal;
      void (async () => {
        try {
          for await (const event of streamVoiceAgent(undefined, signal)) {
            for (const mapped of toVoiceEvents(event)) publish(mapped);
          }
        } catch (error) {
          if (signal.aborted) return;
          logger.debug(
            `voice event stream ended: ${error instanceof Error ? error.message : String(error)}`,
          );
        }
      })();

      await driver.start({
        silenceDurationMs: options.turnHandling?.endpointing?.minDelayMs,
        maxRecordingDurationMs: options.turnHandling?.endpointing?.maxDelayMs,
        speechThreshold: options.vad?.activationThreshold,
        // The driver owns playout, so it is the only layer that can say
        // "speaking" while sound is actually leaving the speaker. Mirrors
        // Swift/Kotlin, where the same phase is merged into `session.events`.
        onPhase: (phase) => publish({
          type: 'agentStateChanged',
          state: DRIVER_PHASE_STATES[phase],
        }),
        onTurn: (turn) => {
          if (turn.userText) {
            publish({ type: 'userTranscribed', text: turn.userText, isFinal: true });
          }
          if (turn.assistantText) publish({ type: 'agentResponse', text: turn.assistantText });
        },
        onError: (error) => publish({ type: 'error', message: error.message, recoverable: true }),
      });
    },

    async say(text: string): Promise<SpeechHandle> {
      if (closed) throw SDKException.invalidState('This voice session is closed.');
      publish({ type: 'agentStateChanged', state: 'speaking' });
      const handle = await ttsNamespace.speak(text, { voice: options.tts.voice });
      lastSpeechHandle = handle;
      void handle.waitForPlayout().then(() => {
        if (!closed) publish({ type: 'agentStateChanged', state: 'listening' });
      });
      return handle;
    },

    /** Awaits the interrupted `say()` handle and the turn loop's active reply settling. */
    async interrupt(): Promise<void> {
      const settling: Promise<void>[] = [driver.interruptCurrentTurn()];
      if (lastSpeechHandle) settling.push(lastSpeechHandle.interrupt());
      else ttsNamespace.stop();
      await Promise.all(settling);
    },

    async close(): Promise<void> {
      if (closed) return;
      closed = true;
      nativePump?.abort();
      driver.stop();
      ttsNamespace.stop();
      queue.complete();
      await cleanupVoiceAgent();
    },
  };
  return session;
}

/** Live speech-to-speech conversation. */
export const voice = {
  /**
   * Create a session that owns its own prerequisites: it downloads and loads
   * the three models it was given, ensures a VAD is resident, and wires the
   * pipeline. Nothing opens the microphone until `start()`.
   *
   * @throws SDKException when a model cannot be loaded or no speech backend is registered.
   *
   * @example
   * const session = await RunAnywhere.voice.createSession({
   *   stt: { id: 'whisper-tiny' }, llm: { id: 'qwen3-0.6b' }, tts: { id: 'piper-en-us' } });
   * await session.start();
   */
  async createSession(options: VoiceSessionOptions): Promise<VoiceSession> {
    await ensureVoiceModels(options);
    await ensureDefaultVAD();
    await initializeVoiceAgentWithLoadedModels(options.tts.voice);
    return createSession(options);
  },
};
