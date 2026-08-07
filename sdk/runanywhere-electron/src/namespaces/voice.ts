// The voice namespace: a composed speech turn (transcribe -> answer -> speak),
// mirroring the shape of Swift's VoiceSession. The composition lives here (in the
// SDK), not in the app; the app only captures the microphone and plays the audio,
// since the Node utility host has no audio device. A session names its STT, LLM,
// and TTS models once; each is auto-loaded on first use.
import type { GenerationResult, ModelRef, AudioInput } from '../types.js';
import type { LlmNamespace } from './llm.js';
import type { SttNamespace, Transcription } from './stt.js';
import type { TtsNamespace, Audio } from './tts.js';

/** Models and generation controls for a voice session. */
export interface VoiceSessionConfig {
  stt: ModelRef;
  llm: ModelRef;
  tts: ModelRef;
  systemPrompt?: string;
  temperature?: number;
  maxOutputTokens?: number;
}

/** The result of one spoken turn. */
export interface VoiceTurn {
  transcript: Transcription;
  reply: GenerationResult;
  audio: Audio;
}

export interface VoiceSession {
  /** One turn: transcribe the captured audio, answer it, synthesize the reply. */
  respond(audio: AudioInput): Promise<VoiceTurn>;
  close(): Promise<void>;
}

export interface VoiceNamespace {
  /** Open a voice session over the named STT/LLM/TTS models. */
  createSession(config: VoiceSessionConfig): Promise<VoiceSession>;
}

export function createVoiceNamespace(
  stt: SttNamespace,
  llm: LlmNamespace,
  tts: TtsNamespace
): VoiceNamespace {
  return {
    async createSession(config) {
      return {
        async respond(audio) {
          const transcript = await stt.transcribe(audio, { model: config.stt.id });
          const reply = await llm.generate(transcript.text, {
            model: config.llm.id,
            ...(config.systemPrompt !== undefined ? { systemPrompt: config.systemPrompt } : {}),
            ...(config.temperature !== undefined ? { temperature: config.temperature } : {}),
            ...(config.maxOutputTokens !== undefined ? { maxOutputTokens: config.maxOutputTokens } : {}),
          });
          const audioOut = await tts.synthesize(reply.text, {
            model: config.tts.id,
            ...(config.tts.voice ? { voice: config.tts.voice } : {}),
          });
          return { transcript, reply, audio: audioOut };
        },
        async close() {
          /* nothing to release: models stay resident for reuse */
        },
      };
    },
  };
}
