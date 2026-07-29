// Chat.ts — multi-turn conversation over an LLMModel. Keeps history (system +
// user/assistant turns), formats it into the model's prompt each turn, streams
// the reply, and appends it to the history so the next turn has context.
import type { LLMModel } from './RunAnywhere';

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export interface ChatOptions {
  /** System instruction, kept at the head of every prompt. */
  system?: string;
}

export class Chat {
  private history: ChatMessage[] = [];

  constructor(
    private readonly llm: LLMModel,
    opts: ChatOptions = {}
  ) {
    if (opts.system) this.history.push({ role: 'system', content: opts.system });
  }

  /** A copy of the conversation so far. */
  get messages(): ChatMessage[] {
    return this.history.map((m) => ({ ...m }));
  }

  /** Clear the conversation (keeps the system message). */
  reset(): void {
    this.history = this.history.filter((m) => m.role === 'system');
  }

  /** Send a user message; stream the assistant reply, then record both turns. */
  send(userText: string): AsyncIterableIterator<string> {
    const prompt = this.buildPrompt(userText);
    const src = this.llm.generate(prompt);
    const history = this.history;
    let acc = '';
    return {
      [Symbol.asyncIterator]() {
        return this;
      },
      async next(): Promise<IteratorResult<string>> {
        const r = await src.next();
        if (r.done) {
          history.push({ role: 'user', content: userText });
          history.push({ role: 'assistant', content: acc.trim() });
          return { value: undefined as unknown as string, done: true };
        }
        acc += r.value;
        return { value: r.value, done: false };
      },
    };
  }

  /** Convenience: send and collect the full reply. */
  async sendText(userText: string): Promise<string> {
    let out = '';
    for await (const t of this.send(userText)) out += t;
    return out;
  }

  private buildPrompt(userText: string): string {
    const system = this.history.find((m) => m.role === 'system');
    const turns = this.history.filter((m) => m.role !== 'system');
    let p = system ? system.content + '\n\n' : '';
    for (const m of turns) {
      p += (m.role === 'user' ? 'User: ' : 'Assistant: ') + m.content + '\n';
    }
    p += 'User: ' + userText + '\nAssistant:';
    return p;
  }
}
