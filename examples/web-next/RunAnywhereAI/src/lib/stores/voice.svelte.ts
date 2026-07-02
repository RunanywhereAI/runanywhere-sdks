import { LLMGenerateRequest } from '@runanywhere/proto-ts/llm_service';
import { TokenKind } from '@runanywhere/proto-ts/voice_events';
import { models } from './models.svelte';
import { stt } from './stt.svelte';
import { tts } from './tts.svelte';

export interface VoiceTurn {
  role: 'user' | 'assistant';
  text: string;
  pending?: boolean;
}

export type VoicePhase = 'idle' | 'listening' | 'thinking' | 'speaking';

// Keep the last N turns as LLM context so replies stay coherent without
// blowing the small models' context window.
const HISTORY_TURNS = 6;

class VoiceStore {
  turns = $state<VoiceTurn[]>([]);
  phase = $state<VoicePhase>('idle');
  error = $state<string | null>(null);

  private cancelled = false;

  get listening(): boolean {
    return this.phase === 'listening';
  }

  get busy(): boolean {
    return this.phase === 'thinking' || this.phase === 'speaking';
  }

  get ready(): boolean {
    // Gate on the actual component handles (the STT/TTS stores' own $state),
    // which is what transcribe/synthesize need — the `models.loadedXId` mirror
    // is set separately and can diverge. LLM has no component handle, so use
    // its loaded id.
    return stt.ready && models.loadedLlmId != null && tts.ready;
  }

  clear(): void {
    if (this.phase !== 'idle') return;
    this.turns = [];
    this.error = null;
  }

  // Push-to-talk: begin capturing mic audio.
  async startListening(): Promise<void> {
    if (this.phase !== 'idle' || !this.ready) return;
    this.error = null;
    this.cancelled = false;
    try {
      await stt.startCapture();
      this.phase = 'listening';
    } catch (err) {
      this.phase = 'idle';
      this.error = this.describe(err, 'Microphone unavailable');
    }
  }

  // Stop capturing and run the full transcribe -> generate -> speak loop.
  async stopAndRespond(): Promise<void> {
    if (this.phase !== 'listening') return;
    const samples = stt.finishCapture();

    this.phase = 'thinking';
    let userText = '';
    try {
      userText = await stt.transcribeSamples(samples);
    } catch (err) {
      this.phase = 'idle';
      this.error = this.describe(err, 'Transcription failed');
      return;
    }

    if (this.cancelled) {
      this.phase = 'idle';
      return;
    }
    if (!userText) {
      this.phase = 'idle';
      this.error = 'No speech detected';
      return;
    }

    // History is everything before this new user turn.
    const history = this.turns.slice();
    this.turns.push({ role: 'user', text: userText });
    this.turns.push({ role: 'assistant', text: '', pending: true });
    const index = this.turns.length - 1;

    let reply = '';
    try {
      reply = await this.generate(userText, history, index);
    } catch (err) {
      this.turns[index] = {
        role: 'assistant',
        text: this.turns[index].text || 'Sorry, something went wrong.',
        pending: false,
      };
      this.phase = 'idle';
      this.error = this.describe(err, 'Generation failed');
      return;
    }

    this.turns[index] = { role: 'assistant', text: reply, pending: false };

    if (this.cancelled || !reply) {
      this.phase = 'idle';
      return;
    }

    this.phase = 'speaking';
    try {
      await tts.speak(reply);
    } catch (err) {
      this.error = this.describe(err, 'Playback failed');
    } finally {
      if (this.phase === 'speaking') this.phase = 'idle';
    }
  }

  // Cancel whatever is in flight: abandon capture, generation, or playback.
  stop(): void {
    this.cancelled = true;
    if (this.phase === 'listening') {
      stt.finishCapture();
    } else if (this.phase === 'thinking') {
      void import('@runanywhere/web').then(({ RunAnywhere }) => RunAnywhere.cancelGeneration());
    } else if (this.phase === 'speaking') {
      tts.stop();
    }
    this.phase = 'idle';
  }

  private async generate(prompt: string, history: VoiceTurn[], index: number): Promise<string> {
    const { RunAnywhere } = await import('@runanywhere/web');
    const request = LLMGenerateRequest.fromPartial({
      prompt: this.buildPrompt(prompt, history),
      modelId: models.loadedLlmId ?? '',
      streamingEnabled: true,
      emitThoughts: false,
      options: {
        streamingEnabled: true,
        disableThinking: true,
        maxTokens: 512,
        temperature: 0.7,
        topP: 0.95,
        topK: 40,
      },
    });

    let reply = '';
    for await (const event of RunAnywhere.generateStream(request)) {
      if (this.cancelled) break;
      if (event.kind === TokenKind.TOKEN_KIND_THOUGHT) continue;
      if (event.token) {
        reply += event.token;
        this.turns[index] = { role: 'assistant', text: reply, pending: true };
      }
      if (event.isFinal) break;
    }
    return reply.trim();
  }

  // A compact multi-turn transcript so the assistant remembers recent context.
  private buildPrompt(latest: string, prior: VoiceTurn[]): string {
    const history = prior
      .filter((t) => t.text.trim().length > 0)
      .slice(-HISTORY_TURNS)
      .map((t) => `${t.role === 'user' ? 'User' : 'Assistant'}: ${t.text.trim()}`);
    const lines = [
      'You are a helpful voice assistant. Reply in a brief, natural, conversational way suited to being read aloud. Do not use markdown, lists, or emoji.',
      ...history,
      `User: ${latest}`,
      'Assistant:',
    ];
    return lines.join('\n');
  }

  private describe(err: unknown, fallback: string): string {
    if (err instanceof Error) {
      if (err.name === 'NotAllowedError' || /permission/i.test(err.message)) {
        return 'Microphone permission denied';
      }
      return err.message || fallback;
    }
    return fallback;
  }
}

export const voice = new VoiceStore();
