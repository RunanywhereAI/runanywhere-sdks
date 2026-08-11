/**
 * `RunAnywhere.voice` — a full listen/think/speak session.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { VADConfiguration } from '@runanywhere/proto-ts/vad_options';
import {
  TurnDetection,
  VoiceAgentComposeConfig,
} from '@runanywhere/proto-ts/voice_agent_service';
import {
  PipelineState,
  type VoiceEvent as VoiceEventProto,
} from '@runanywhere/proto-ts/voice_events';

import { SDKException } from '../../Foundation/Errors/SDKException';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { VoiceAgentStreamAdapter } from '../../Adapters/VoiceAgentStreamAdapter';
import { VoiceAgentMicDriver } from '../../Features/VoiceAgent/VoiceAgentMicDriver';
import { AudioPlaybackManager } from '../../Features/VoiceSession/AudioPlaybackManager';
import {
  cleanupVoiceAgent,
  ensureDefaultVAD,
  initializeVoiceAgent,
} from '../Extensions/VoiceAgent/RunAnywhere+VoiceAgent';
import { stopSpeaking } from '../Extensions/TTS/RunAnywhere+TTS';
import { decodeOptional, preflight } from './Bridge';
import { ensureModelLoaded, models } from './Models';
import { toLlmOptions, toVadOptions } from './Options';
import { mapStream } from './Stream';
import type {
  AgentState,
  LlmOptions,
  ModelRef,
  SpeechHandle,
  TurnHandlingOptions,
  VadOptions,
  VoiceEvent,
  VoiceSession,
} from './Types';
import { TTSOutput } from '@runanywhere/proto-ts/tts_options';

const logger = new SDKLogger('RunAnywhere.voice');

/** Arguments for {@link voice.createSession}. */
export interface VoiceCreateSessionOptions {
  stt: ModelRef;
  llm: ModelRef;
  /** `voice` selects the voice inside a multi-voice speech model. */
  tts: ModelRef;
  /** Omit `vad.model` to let the session ensure the catalogued default Silero VAD. */
  vad?: VadOptions;
  turnHandling?: TurnHandlingOptions;
  generation?: LlmOptions;
  downloadIfNeeded?: boolean;
}

function agentStateFor(state: PipelineState): AgentState | undefined {
  switch (state) {
    case PipelineState.PIPELINE_STATE_LISTENING:
      return 'listening';
    case PipelineState.PIPELINE_STATE_THINKING:
    case PipelineState.PIPELINE_STATE_PROCESSING_SPEECH:
    case PipelineState.PIPELINE_STATE_GENERATING_RESPONSE:
      return 'thinking';
    case PipelineState.PIPELINE_STATE_SPEAKING:
    case PipelineState.PIPELINE_STATE_PLAYING_TTS:
      return 'speaking';
    default:
      return undefined;
  }
}

/**
 * Project one native voice event onto the public grammar.
 *
 * `VoiceEvent.error` is deleted outright — `sessionError` is the one error
 * payload in this domain, and it already carries its own `recoverable`
 * boolean.
 */
function toVoiceEvent(event: VoiceEventProto): VoiceEvent | undefined {
  if (event.userSaid) {
    return {
      type: 'userTranscribed',
      text: event.userSaid.text,
      isFinal: event.userSaid.isFinal,
    };
  }
  if (event.assistantToken?.isFinal) {
    return { type: 'agentResponse', text: event.assistantToken.text };
  }
  if (event.state) {
    const state = agentStateFor(event.state.current);
    return state ? { type: 'agentStateChanged', state } : undefined;
  }
  if (event.vad) {
    return event.vad.isSpeech
      ? { type: 'speechStarted' }
      : { type: 'speechEnded' };
  }
  if (event.sessionError) {
    return {
      type: 'error',
      message: event.sessionError.message,
      recoverable: event.sessionError.recoverable,
    };
  }
  return undefined;
}

async function resolveModel(
  ref: ModelRef,
  category: ModelCategory,
  downloadIfNeeded: boolean
): Promise<void> {
  if (downloadIfNeeded) {
    await ensureModelLoaded(ref.id, category);
    return;
  }
  await models.load(ref.id);
}

/**
 * `VoiceSessionConfig` is deleted outright — its two commons-read fields
 * (`silenceDurationMs`, and the threshold that used to be `speechThreshold`)
 * now live on `TurnDetection`, following OpenAI Realtime
 * `session.audio.input.turn_detection` naming/units.
 */
function toSessionConfig(
  turnHandling: TurnHandlingOptions | undefined,
  vad: VadOptions | undefined
): TurnDetection {
  const vadOptions = toVadOptions(vad);
  return TurnDetection.fromPartial({
    ...(turnHandling?.endpointing?.minDelayMs !== undefined
      ? { silenceDurationMs: turnHandling.endpointing.minDelayMs }
      : { silenceDurationMs: vadOptions.minSilenceDurationMs }),
  });
}

/** Live voice conversations. */
export const voice = {
  /**
   * Create a session that owns its models, microphone, and playback.
   *
   * The session downloads and loads the models it was given, ensures a VAD is
   * resident, and wires the pipeline; nothing needs pre-loading. Interruption
   * settings in `turnHandling` are not applied yet — the commons voice agent is
   * strictly turn-taking, so barge-in has no channel.
   *
   * @example
   * const session = await RunAnywhere.voice.createSession({ stt, llm, tts });
   * await session.start();
   *
   * @throws SDKException when a model cannot be loaded or the pipeline fails to
   * initialize.
   */
  async createSession(
    options: VoiceCreateSessionOptions
  ): Promise<VoiceSession> {
    await preflight();
    const downloadIfNeeded = options.downloadIfNeeded ?? true;
    await resolveModel(
      options.stt,
      ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
      downloadIfNeeded
    );
    await resolveModel(
      options.llm,
      ModelCategory.MODEL_CATEGORY_LANGUAGE,
      downloadIfNeeded
    );
    await resolveModel(
      options.tts,
      ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
      downloadIfNeeded
    );
    await ensureDefaultVAD(options.vad?.model);

    const vadOptions = toVadOptions(options.vad);
    await initializeVoiceAgent(
      VoiceAgentComposeConfig.fromPartial({
        sttModelId: options.stt.id,
        llmModelId: options.llm.id,
        ...(options.tts.voice ? { ttsVoiceId: options.tts.voice } : {}),
        llmGeneration: toLlmOptions(options.generation),
        vadConfig: VADConfiguration.fromPartial({
          activationThreshold: vadOptions.activationThreshold,
        }),
        turnDetection: toSessionConfig(options.turnHandling, options.vad),
      })
    );

    const native = await preflight();
    const handle = await native.getVoiceAgentHandle();
    const mic = new VoiceAgentMicDriver();
    const playback = new AudioPlaybackManager();
    let started = false;
    let closed = false;

    const session: VoiceSession = {
      get events(): AsyncIterable<VoiceEvent> {
        return mapStream(new VoiceAgentStreamAdapter(handle).stream(), toVoiceEvent);
      },

      async start(): Promise<void> {
        if (closed) {
          throw SDKException.invalidState('This voice session is closed');
        }
        if (started) return;
        started = true;
        await mic.start();
      },

      say(text: string): Promise<SpeechHandle> {
        if (closed) {
          throw SDKException.invalidState('This voice session is closed');
        }
        let settle!: () => void;
        const settled = new Promise<void>((resolve) => {
          settle = resolve;
        });
        const handle: SpeechHandle & { interrupted: boolean; error?: Error } = {
          id: `speech-${Date.now()}`,
          interrupted: false,
          error: undefined,
          async interrupt(): Promise<void> {
            handle.interrupted = true;
            playback.stop();
            settle();
          },
          async waitForPlayout(): Promise<void> {
            await settled;
          },
        };
        void (async () => {
          try {
            const outputBytes = await native.voiceAgentSynthesizeSpeechProto(text);
            const output = decodeOptional(outputBytes, TTSOutput);
            if (!output || output.audioData.byteLength === 0) {
              throw output?.error
                ? new SDKException(output.error)
                : SDKException.processingFailed(
                    'Voice session could not synthesize speech'
                  );
            }
            const copy = new Uint8Array(output.audioData.byteLength);
            copy.set(output.audioData);
            await playback.playWav(copy.buffer);
          } catch (error) {
            handle.error = error instanceof Error ? error : new Error(String(error));
          } finally {
            settle();
          }
        })();
        return Promise.resolve(handle);
      },

      async interrupt(): Promise<void> {
        playback.stop();
        await stopSpeaking().catch((error: unknown) => {
          logger.warning(`Voice interrupt could not stop synthesis: ${String(error)}`);
        });
      },

      async close(): Promise<void> {
        if (closed) return;
        closed = true;
        await mic.stop();
        playback.stop();
        await cleanupVoiceAgent();
      },
    };

    return session;
  },
};
