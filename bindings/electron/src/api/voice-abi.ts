// voice-abi.ts — typed access to the commons voice-agent proto ABI.
//
// The one migrated feature that is a session rather than a call. Commons owns
// the composed pipeline: it frames the fed audio, decides where an utterance
// ends, runs VAD -> STT -> LLM -> TTS over it, keeps the conversation history,
// and walks the eight `rac_audio_pipeline_state_t` states while doing it. What
// stays on this side is the microphone and the speaker, which are the two parts
// a C library cannot have.
//
// Every entry point takes a `rac_voice_agent_handle_t`, so unlike stt/tts/llm
// this one is handle-bound; `NativeBackend` holds it and hands out an opaque
// session id, the same shape RAG uses.

import { ErrorCode, SDKException } from '../errors';
import { ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';
import { AudioEncoding } from '@runanywhere/proto-ts/model_types';
import {
  VoiceAgentAudioFrame,
  VoiceAgentComposeConfig,
  VoiceAgentResult,
  VoiceAgentTurnRequest,
  TurnDetection,
  TurnDetection_Type,
} from '@runanywhere/proto-ts/voice_agent_service';
import {
  PipelineState,
  TokenKind as ProtoTokenKind,
  TurnLifecycleEventKind,
  VoiceAgentComponentStates,
  VoiceEvent as ProtoVoiceEvent,
} from '@runanywhere/proto-ts/voice_events';
import { VADStreamEventKind } from '@runanywhere/proto-ts/vad_options';
import type { RaBackend } from './backend';
import { bridgeStream } from './iter';
import { TURN_DEFAULTS, optionDefaults } from './options';
import type { LlmOptions, TurnHandlingOptions, VadOptions } from './options';
import { AgentState } from './types';
import type { VoiceEvent } from './types';

/**
 * The rate the voice agent's in-core segmenter expects
 * (`voice_agent_feed_abi.cpp:48`), which is also
 * `AudioCaptureDefaults.mic_sample_rate_hz`.
 */
export const VOICE_SAMPLE_RATE = optionDefaults.micSampleRateHz;

/**
 * Build the compose config commons initializes an agent from.
 *
 * Be precise about what lands. `config_from_proto`
 * (`voice_agent_internal_helpers.cpp:408`) reads the three model selectors and
 * `vad_config`, and nothing else: `llm_generation`, `instructions`,
 * `turn_detection`, and `language` have no reader anywhere under
 * `src/features/voice_agent/`. The turn's sampling comes from
 * `make_voice_llm_options()` and its endpointing from the compile-time
 * constants at the top of `voice_agent_feed_abi.cpp`. They are still sent —
 * Swift's `VoiceNamespace` sends the same bytes, and the day commons reads them
 * every SDK gets it at once — but nothing here should be described as honouring
 * them. `vad_config.activation_threshold` is the one knob with an effect today:
 * it configures the agent's own energy detector, which is what decides whether
 * a turn contained speech when no VAD model is resident.
 */
export function toComposeConfig(args: {
  sttModelId: string;
  llmModelId: string;
  ttsVoiceId?: string;
  vad?: VadOptions;
  turnHandling?: TurnHandlingOptions;
  generation?: LlmOptions;
  instructions?: string;
  language?: string;
}): VoiceAgentComposeConfig {
  return VoiceAgentComposeConfig.fromPartial({
    sttModelId: args.sttModelId,
    llmModelId: args.llmModelId,
    // The voice id selects a voice *inside* the loaded TTS model and is not a
    // model id; leaving it unset lets a single-voice engine pick its own.
    ttsVoiceId: args.ttsVoiceId || undefined,
    vadConfig: {
      sampleRate: VOICE_SAMPLE_RATE,
      activationThreshold: args.vad?.activationThreshold ?? 0,
    },
    turnDetection: toTurnDetection(args.vad, args.turnHandling),
    llmGeneration: args.generation
      ? {
          maxTokens: args.generation.maxOutputTokens,
          temperature: args.generation.temperature,
          topP: args.generation.topP,
          topK: args.generation.topK,
          seed: args.generation.seed,
          stopSequences: args.generation.stopSequences,
        }
      : undefined,
    instructions: args.instructions ?? args.generation?.systemPrompt,
    language: args.language,
  });
}

/**
 * `TurnDetection` is where the turn-taking knobs belong on the wire, and it is
 * what Swift fills. `endpointing.maxDelayMs` and `interruption.minDurationMs`
 * have no field on it at all: the utterance cap is `kMaxUtteranceMs`
 * (`voice_agent_feed_abi.cpp:58`) and barge-in is the caller's `interrupt()`.
 */
function toTurnDetection(
  vad: VadOptions | undefined,
  turnHandling: TurnHandlingOptions | undefined
): TurnDetection {
  return TurnDetection.fromPartial({
    type: TurnDetection_Type.TURN_DETECTION_TYPE_VAD,
    threshold: vad?.activationThreshold ?? 0,
    silenceDurationMs:
      turnHandling?.endpointing?.minDelayMs ??
      vad?.minSilenceMs ??
      TURN_DEFAULTS.endpointing.minDelayMs,
    // `VADOptions.prefix_padding_ms`'s own `rac_default` (300 ms), so a turn
    // keeps the pre-roll its first phoneme lives in. Sending 0 clipped it.
    prefixPaddingMs: vad?.prefixPaddingMs ?? optionDefaults.vad().prefixPaddingMs,
    interruptResponse: turnHandling?.interruption?.enabled,
  });
}

/** One captured frame, in the only encoding the in-core segmenter accepts. */
export function toAudioFrame(pcm16: Uint8Array, isFinal = false): VoiceAgentAudioFrame {
  return VoiceAgentAudioFrame.fromPartial({
    audioData: pcm16,
    sampleRateHz: VOICE_SAMPLE_RATE,
    channels: 1,
    encoding: AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
    isFinal,
  });
}

/** A per-utterance turn, keyed by the id `cancel` matches on. */
export function toTurnRequest(pcm16: Uint8Array, requestId: string): VoiceAgentTurnRequest {
  return VoiceAgentTurnRequest.fromPartial({ requestId, audioData: pcm16 });
}

/**
 * The public event shape for one commons `VoiceEvent`, or null for the arms the
 * public union has no home for (metrics, audio frames the SDK plays from the
 * turn result instead, component-state snapshots).
 */
export function toPublicVoiceEvent(event: ProtoVoiceEvent): VoiceEvent | null {
  if (event.userSaid) {
    return { type: 'userTranscribed', text: event.userSaid.text, isFinal: event.userSaid.isFinal };
  }
  if (event.assistantToken) {
    // Commons emits the whole answer as one final token: the voice turn calls
    // the non-streaming `rac_llm_generate`, so there is no token-by-token feed
    // to forward. Thoughts are dropped rather than spoken.
    if (!event.assistantToken.isFinal) return null;
    if (event.assistantToken.kind === ProtoTokenKind.TOKEN_KIND_THOUGHT) return null;
    return { type: 'agentResponse', text: event.assistantToken.text };
  }
  if (event.vad) {
    if (event.vad.type !== VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY) return null;
    return event.vad.isSpeech ? { type: 'speechStarted' } : { type: 'speechEnded' };
  }
  if (event.sessionError) {
    // "I am listening and hearing nothing" is not a failure. Commons already
    // distinguishes it on the wire; folding it into the generic `error` arm is
    // what made a healthy session look broken and an unheard user look ignored.
    if (event.sessionError.code === ErrorCode.ERROR_CODE_INSUFFICIENT_AUDIO_DATA) {
      return { type: 'inputSilent', detail: event.sessionError.message };
    }
    return {
      type: 'error',
      message: event.sessionError.message,
      recoverable: event.sessionError.recoverable,
    };
  }
  if (event.turnLifecycle) {
    return fromTurnLifecycle(event.turnLifecycle.kind);
  }
  if (event.state) {
    const state = toAgentState(event.state.current);
    return state ? { type: 'agentStateChanged', state } : null;
  }
  return null;
}

/**
 * The turn-lifecycle arm carries the only *in-flight* speech signals commons
 * emits: the in-feed segmenter reports the moment its energy gate opens
 * (`voice_agent_feed_abi.cpp` -> USER_SPEECH_STARTED) while the user is still
 * talking. The `vad` arm above fires once, after the utterance has already
 * closed, and only when a VAD model answered — with none resident it never
 * arrives at all. Reading only that arm is what made `speechStarted` late or
 * absent. Swift and Kotlin both map these.
 */
function fromTurnLifecycle(kind: TurnLifecycleEventKind): VoiceEvent | null {
  switch (kind) {
    case TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED:
      return { type: 'speechStarted' };
    case TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED:
      return { type: 'speechEnded' };
    case TurnLifecycleEventKind.TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED:
      return { type: 'agentStateChanged', state: AgentState.SPEAKING };
    default:
      // Every other kind (started, transcription-final, response-completed,
      // completed, cancelled, failed) is either already reported through a
      // richer arm or has no home in the public union.
      return null;
  }
}

/**
 * Eight pipeline states onto the three the public `AgentState` has. COOLDOWN is
 * the 800 ms feedback-prevention window commons inserts after playback, which
 * from the caller's side is still "waiting for you to speak".
 */
function toAgentState(state: PipelineState): AgentState | null {
  switch (state) {
    case PipelineState.PIPELINE_STATE_IDLE:
    case PipelineState.PIPELINE_STATE_LISTENING:
    case PipelineState.PIPELINE_STATE_COOLDOWN:
    case PipelineState.PIPELINE_STATE_WAITING_WAKEWORD:
      return AgentState.LISTENING;
    case PipelineState.PIPELINE_STATE_PROCESSING_SPEECH:
    case PipelineState.PIPELINE_STATE_GENERATING_RESPONSE:
      return AgentState.THINKING;
    case PipelineState.PIPELINE_STATE_PLAYING_TTS:
      return AgentState.SPEAKING;
    default:
      return null;
  }
}

/** Which components commons is still missing, for a readable initialize failure. */
export function missingComponents(states: VoiceAgentComponentStates): string[] {
  const ready = (state: ComponentLifecycleState): boolean =>
    state === ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY;
  const missing: string[] = [];
  if (!ready(states.sttState)) missing.push('stt');
  if (!ready(states.llmState)) missing.push('llm');
  if (!ready(states.ttsState)) missing.push('tts');
  if (!ready(states.vadState)) missing.push('vad');
  return missing;
}

/** One voice agent in commons, bound to one backend session id. */
export class VoiceAgentAbi {
  constructor(
    private readonly backend: RaBackend,
    private readonly session: string
  ) {}

  /** Configure the agent against whatever the lifecycle loads made resident. */
  async initialize(config: VoiceAgentComposeConfig): Promise<VoiceAgentComponentStates> {
    return VoiceAgentComponentStates.decode(
      await this.backend.voiceInitialize(
        this.session,
        VoiceAgentComposeConfig.encode(config).finish()
      )
    );
  }

  async states(): Promise<VoiceAgentComponentStates> {
    return VoiceAgentComponentStates.decode(await this.backend.voiceStates(this.session));
  }

  /**
   * Push one captured frame. Commons buffers it, and when its endpointer closes
   * an utterance this call blocks for the whole turn and comes back with the
   * transcript, the reply, and the synthesized audio as WAV. An empty result
   * means no utterance closed.
   */
  async feed(frame: VoiceAgentAudioFrame): Promise<VoiceAgentResult> {
    return VoiceAgentResult.decode(
      await this.backend.voiceFeed(this.session, VoiceAgentAudioFrame.encode(frame).finish())
    );
  }

  /**
   * One complete utterance in, one finished turn out.
   *
   * The older of the two per-utterance paths, and it reports differently:
   * `rac_voice_agent_process_voice_turn_proto` is its own implementation
   * (`voice_agent_proto_abi.cpp:223`) that emits only `TurnLifecycleEvent` and
   * component-state snapshots. The `userSaid` / `assistantToken` / `audio` /
   * `state` arms, and the conversation history, belong to the d7 path that
   * `feed` and `turnStream` run.
   */
  async turn(pcm16: Uint8Array): Promise<VoiceAgentResult> {
    return VoiceAgentResult.decode(await this.backend.voiceTurn(this.session, pcm16));
  }

  /** The same turn, reported event by event instead of as one result. */
  turnStream(request: VoiceAgentTurnRequest): AsyncIterableIterator<ProtoVoiceEvent> {
    const bytes = VoiceAgentTurnRequest.encode(request).finish();
    return bridgeStream<ProtoVoiceEvent>((sink) =>
      this.backend.voiceProcessTurn(this.session, bytes, (event) => {
        sink.push(ProtoVoiceEvent.decode(event));
      })
    );
  }

  /**
   * Cancel the turn whose id is `requestId`. Cooperative: an active LLM or TTS
   * backend is interrupted immediately, a running STT call is allowed to finish
   * and the pipeline exits at the next stage boundary.
   */
  async cancel(requestId: string): Promise<void> {
    if (!requestId) {
      throw SDKException.validationFailed({
        fieldPath: 'requestId',
        message: 'cancelling a voice turn needs the turn id commons reported',
      });
    }
    await this.backend.voiceCancelTurn(
      this.session,
      VoiceAgentTurnRequest.encode(VoiceAgentTurnRequest.fromPartial({ requestId })).finish()
    );
  }

  /** Every VoiceEvent the agent emits, until the session closes. */
  events(): AsyncIterableIterator<ProtoVoiceEvent> {
    return bridgeStream<ProtoVoiceEvent>((sink) =>
      this.backend.voiceEvents(this.session, (event) => {
        sink.push(ProtoVoiceEvent.decode(event));
      })
    );
  }
}

export { VoiceAgentComponentStates, PipelineState };
export type { ProtoVoiceEvent, VoiceAgentComposeConfig, VoiceAgentResult };
