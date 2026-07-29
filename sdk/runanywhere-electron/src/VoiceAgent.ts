// VoiceAgent.ts — a voice turn pipeline that orchestrates the STT, LLM and TTS
// models into one call: audio in -> transcript -> LLM response -> audio out.
// Streaming callbacks surface the transcript and the response tokens as they are
// produced. (Segmentation / VAD — deciding *when* an utterance starts and ends —
// is a separate layer; processTurn takes an already-captured utterance.)
import type { LLMModel, STTModel, TTSVoice } from './RunAnywhere';

export interface VoiceAgentModels {
  stt: STTModel;
  llm: LLMModel;
  tts: TTSVoice;
}

export interface VoiceAgentOptions {
  /** Prepended to the transcript so the assistant stays on-task/concise. */
  systemPrompt?: string;
}

export interface VoiceTurn {
  transcript: string;
  response: string;
  audio: { sampleRate: number; samples: Float32Array };
}

export interface VoiceTurnCallbacks {
  /** Fired once the utterance is transcribed. */
  onTranscript?: (transcript: string) => void;
  /** Fired per LLM response token. */
  onToken?: (token: string) => void;
}

export class VoiceAgent {
  constructor(
    private readonly models: VoiceAgentModels,
    private readonly opts: VoiceAgentOptions = {}
  ) {}

  /** Run one voice turn over 16 kHz mono PCM16 audio bytes. */
  async processTurn(pcm16: Uint8Array, cb: VoiceTurnCallbacks = {}): Promise<VoiceTurn> {
    const transcript = this.models.stt.transcribe(pcm16).trim();
    cb.onTranscript?.(transcript);

    const prompt = this.opts.systemPrompt
      ? `${this.opts.systemPrompt}\n\n${transcript}`
      : transcript;

    let response = '';
    for await (const token of this.models.llm.generate(prompt)) {
      response += token;
      cb.onToken?.(token);
    }
    response = response.trim();

    const audio = this.models.tts.synthesize(response);
    return { transcript, response, audio };
  }
}
