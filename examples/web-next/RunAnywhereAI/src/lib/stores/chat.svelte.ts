import { LLMGenerateRequest } from '@runanywhere/proto-ts/llm_service';
import { TokenKind } from '@runanywhere/proto-ts/voice_events';
import { catalog } from '../catalog';
import { models } from './models.svelte';

export interface ChatMessage {
  role: 'user' | 'assistant';
  text: string;
  thinking?: string;
  tools?: string[];
  pending?: boolean;
}

class ChatStore {
  messages = $state<ChatMessage[]>([]);
  generating = $state(false);
  thinkingEnabled = $state(true);
  toolsEnabled = $state(false);

  get ready(): boolean {
    return models.loadedLlmId != null;
  }

  get supportsThinking(): boolean {
    return catalog.llm.find((m) => m.id === models.loadedLlmId)?.supportsThinking ?? false;
  }

  clear(): void {
    if (this.generating) return;
    this.messages = [];
  }

  private update(index: number, patch: Partial<ChatMessage>): void {
    this.messages[index] = { ...this.messages[index], ...patch };
  }

  async send(prompt: string): Promise<void> {
    const text = prompt.trim();
    if (!text || this.generating || !this.ready) return;

    const think = this.thinkingEnabled && this.supportsThinking;
    this.messages.push({ role: 'user', text });
    this.messages.push({ role: 'assistant', text: '', thinking: '', tools: [], pending: true });
    const index = this.messages.length - 1;
    this.generating = true;

    try {
      const { RunAnywhere } = await import('@runanywhere/web');

      if (this.toolsEnabled) {
        const { tools } = await import('../tools');
        await RunAnywhere.generateWithTools(text, tools, {
          onToken: (t) => this.update(index, { text: this.messages[index].text + t }),
          onThinking: (t) => this.update(index, { thinking: (this.messages[index].thinking ?? '') + t }),
          onToolCall: (name) =>
            this.update(index, {
              text: '',
              tools: [...(this.messages[index].tools ?? []), name],
            }),
        });
        this.update(index, { pending: false });
        return;
      }

      const request = LLMGenerateRequest.fromPartial({
        prompt: text,
        modelId: models.loadedLlmId ?? '',
        streamingEnabled: true,
        emitThoughts: think,
        options: {
          streamingEnabled: true,
          disableThinking: !think,
          maxTokens: 1024,
          temperature: 0.7,
          topP: 0.95,
          topK: 40,
        },
      });
      for await (const event of RunAnywhere.generateStream(request)) {
        if (event.kind === TokenKind.TOKEN_KIND_THOUGHT) {
          if (event.token) this.update(index, { thinking: (this.messages[index].thinking ?? '') + event.token });
        } else if (event.token) {
          this.update(index, { text: this.messages[index].text + event.token });
        }
        if (event.isFinal) break;
      }
      this.update(index, { pending: false });
    } catch (err) {
      this.update(index, {
        text: this.messages[index].text || `Error: ${err instanceof Error ? err.message : String(err)}`,
        pending: false,
      });
    } finally {
      this.generating = false;
    }
  }

  cancel(): void {
    if (!this.generating) return;
    void import('@runanywhere/web').then(({ RunAnywhere }) => RunAnywhere.cancelGeneration());
  }
}

export const chat = new ChatStore();
