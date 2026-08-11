/**
 * Chat — conversation turns, streaming generation, composer, stop.
 *
 * Mirrors macOS ChatInterfaceView / LLMViewModel at a high level. Uses C1
 * Composer / messageBubble / StreamingText / markdown. One generation at a time;
 * Stop is `iterator.return()`. Conversation chrome lives in the sidebar.
 */
import type { ChatMessage, GenerationEvent, GenerationResult, ModelInfo } from '@runanywhere/electron';
import type { ChatMessageRecord } from '@shared/conversation';
import { MenuCommand } from '@shared/ipc-contract';

import { Composer } from '../components/composer';
import { emptyStateMark } from '../components/empty-state-mark';
import { icon, type IconName } from '../components/icons';
import { renderMarkdown, wireMarkdown } from '../components/markdown';
import { messageBubble, userBubbleHtml } from '../components/message-bubble';
import { StreamingText } from '../components/streaming-text';
import { showError, showToast } from '../components/toast';
import {
  ConversationStore,
  createMessage,
  titleFromPrompt,
} from '../services/conversations';
import { escapeHtml, formatMetrics, greeting } from '../services/format';
import { logger } from '../services/logger';
import {
  generationOptions,
  loadAppSettings,
  selectedModel,
} from '../services/settings';
import type { ViewContext, ViewFactory, ViewInstance } from '../shell/app';
import { Route } from '../shell/routes';

const log = logger('chat');

/** Byte-identical to Swift StarterPrompt.all / Android / Web. */
const STARTER_PROMPTS: ReadonlyArray<{
  readonly id: string;
  readonly title: string;
  readonly subtitle: string;
  readonly text: string;
  readonly icon: IconName;
}> = [
  {
    id: 'plan',
    title: 'Plan my day',
    subtitle: 'from messy notes',
    text: 'Turn this messy list into a realistic plan with the top three priorities:',
    icon: 'doc.text',
  },
  {
    id: 'rewrite',
    title: 'Rewrite clearly',
    subtitle: 'warm and concise',
    text: 'Rewrite this so it is clear, warm, and concise:',
    icon: 'square.and.pencil',
  },
  {
    id: 'compare',
    title: 'Compare options',
    subtitle: 'weigh the tradeoffs',
    text: 'Compare these options, explain the tradeoffs, and recommend one:',
    icon: 'arrow.clockwise',
  },
  {
    id: 'summarize',
    title: 'Summarize notes',
    subtitle: 'into next steps',
    text: 'Summarize these notes into decisions, action items, and open questions:',
    icon: 'sparkles',
  },
];

type GenerationHandle = AsyncIterableIterator<GenerationEvent>;

function toSdkMessages(messages: readonly ChatMessageRecord[]): ChatMessage[] {
  return messages
    .filter((m) => !(m.role === 'assistant' && m.content.length === 0 && m.thinking === undefined))
    .filter((m) => m.error === undefined)
    .map((m) => ({
      role: m.role === 'user' ? 'user' : 'assistant',
      content: m.content,
    }));
}

function metricsFromPartial(
  partial: Partial<GenerationResult> | undefined,
): ChatMessageRecord['metrics'] | undefined {
  if (
    partial?.outputTokens === undefined ||
    partial.tokensPerSecond === undefined ||
    partial.timeToFirstTokenMs === undefined
  ) {
    return undefined;
  }
  return {
    outputTokens: partial.outputTokens,
    tokensPerSecond: partial.tokensPerSecond,
    timeToFirstTokenMs: partial.timeToFirstTokenMs,
  };
}

export const createChatView: ViewFactory = (context) => new ChatView(context);

class ChatView implements ViewInstance {
  private readonly store: ConversationStore;
  private readonly scroll: HTMLElement;
  private readonly messagesHost: HTMLElement;
  private readonly composer: Composer;

  private generating = false;
  private stream: GenerationHandle | null = null;
  private liveStream: StreamingText | null = null;
  private liveAssistantId: string | null = null;
  private loadedModelName: string | null = null;
  private loadedModelMeta = '';
  private disposed = false;

  private readonly onShellEvent = (event: Event): void => {
    const custom = event as CustomEvent;
    const name = event.type.replace(/^runanywhere:/, '');
    switch (name) {
      case 'conversation:new':
        void this.handleNew();
        return;
      case 'conversation:select':
        void this.handleSelect(String(custom.detail));
        return;
      case 'conversation:delete':
        void this.handleDelete(String(custom.detail));
        return;
      case 'conversation:rename': {
        const detail = custom.detail as { id: string; title: string };
        this.store.rename(detail.id, detail.title);
        this.publishConversations();
        this.context.refreshChrome();
        return;
      }
      default:
        return;
    }
  };

  constructor(private readonly context: ViewContext) {
    this.store = new ConversationStore();

    const root = context.root;
    root.classList.add('ra-chat');

    this.scroll = document.createElement('div');
    this.scroll.className = 'ra-chat-scroll ra-scroll';
    this.messagesHost = document.createElement('div');
    this.messagesHost.className = 'ra-chat-messages ra-measure-text';
    this.scroll.append(this.messagesHost);

    this.composer = new Composer({
      onSend: (text) => void this.send(text),
      onStop: () => void this.stop(),
      onVoice: () => this.context.navigate(Route.Voice),
    });

    root.append(this.scroll, this.composer.element);

    for (const name of [
      'conversation:new',
      'conversation:select',
      'conversation:delete',
      'conversation:rename',
    ] as const) {
      window.addEventListener(`runanywhere:${name}`, this.onShellEvent);
    }

    void this.boot();
  }

  title(): string | undefined {
    return this.store.current?.title;
  }

  subtitle(): string | undefined {
    const count = this.store.current?.messages.length ?? 0;
    if (count === 0) return undefined;
    return `${count} message${count === 1 ? '' : 's'}`;
  }

  model(): { name: string; meta: string } | undefined {
    if (this.loadedModelName === null) return undefined;
    return { name: this.loadedModelName, meta: this.loadedModelMeta };
  }

  capabilities(): {
    canStopGeneration: boolean;
    canShowChatDetails: boolean;
    canPasteAttachment: boolean;
  } {
    return {
      canStopGeneration: this.generating,
      canShowChatDetails: (this.store.current?.messages.length ?? 0) > 0,
      canPasteAttachment: false,
    };
  }

  onMenuCommand(command: MenuCommand): void {
    switch (command) {
      case MenuCommand.FocusComposer:
        this.composer.focus();
        return;
      case MenuCommand.StopGeneration:
        void this.stop();
        return;
      case MenuCommand.OpenModelPicker:
        this.context.navigate(Route.Models);
        return;
      case MenuCommand.ShowChatDetails:
        showToast('Chat details will open here once the details sheet is wired.');
        return;
      case MenuCommand.NewConversation:
      case MenuCommand.OpenSettings:
      case MenuCommand.ToggleSidebar:
      case MenuCommand.ShowChat:
      case MenuCommand.ShowModels:
      case MenuCommand.ShowAdvanced:
      case MenuCommand.PasteAttachment:
      case MenuCommand.ImportDocument:
        return;
    }
  }

  dispose(): void {
    this.disposed = true;
    for (const name of [
      'conversation:new',
      'conversation:select',
      'conversation:delete',
      'conversation:rename',
    ] as const) {
      window.removeEventListener(`runanywhere:${name}`, this.onShellEvent);
    }
    void this.stop();
    void this.store.flush();
  }

  private async boot(): Promise<void> {
    await this.store.load();
    const snap = this.context.conversations();
    if (snap.currentId !== null) this.store.select(snap.currentId);
    if (this.store.current === null && this.store.conversations.length === 0) {
      this.store.create();
    } else if (this.store.current === null) {
      this.store.select(this.store.conversations[0]?.id ?? null);
    }
    this.publishConversations();
    await loadAppSettings();
    await this.refreshModelChip();
    this.render();
    this.context.refreshChrome();
  }

  private publishConversations(): void {
    this.context.setConversations(this.store.conversations, this.store.currentConversationId);
  }

  private async refreshModelChip(): Promise<void> {
    try {
      const settings = await loadAppSettings();
      const modelId = selectedModel('llm');
      const info = await window.runanywhere.models.get(modelId);
      const state = await window.runanywhere.models.state();
      const loaded = state.loaded.LANGUAGE ?? info;
      this.loadedModelName = loaded?.name ?? modelId;
      this.loadedModelMeta = loaded?.parameters ?? '';

      if (settings.tools) {
        const pill = document.createElement('div');
        pill.className = 'ra-composer-pill';
        pill.dataset.tone = 'brand';
        pill.innerHTML =
          `${icon('globe', { size: 14 })}` +
          `<span><strong>Web &amp; tools on</strong></span>`;
        this.composer.setPills([pill]);
      } else {
        this.composer.setPills([]);
      }
    } catch (error) {
      log.warn('model chip refresh failed', error);
    }
  }

  private async handleNew(): Promise<void> {
    if (this.generating) await this.stop();
    this.store.create();
    this.publishConversations();
    this.render();
    this.context.refreshChrome();
    this.composer.focus();
  }

  private async handleSelect(id: string): Promise<void> {
    if (this.store.currentConversationId === id) return;
    if (this.generating) await this.stop();
    this.store.select(id);
    this.publishConversations();
    this.render();
    this.context.refreshChrome();
  }

  private async handleDelete(id: string): Promise<void> {
    if (this.generating && this.store.currentConversationId === id) await this.stop();
    this.store.delete(id);
    if (this.store.current === null) this.store.create();
    this.publishConversations();
    this.render();
    this.context.refreshChrome();
  }

  private setGenerating(active: boolean): void {
    this.generating = active;
    this.composer.setGenerating(active);
    this.context.refreshChrome();
  }

  private async send(prompt: string): Promise<void> {
    if (this.generating) return;
    const trimmed = prompt.trim();
    if (trimmed.length === 0) return;

    this.composer.clear();

    let model: ModelInfo | null = null;
    try {
      const settings = await loadAppSettings();
      const modelId = selectedModel('llm');
      model = await window.runanywhere.models.get(modelId);
      if (model === null) {
        showToast('Load a language model from Models first.', 'danger');
        this.context.navigate(Route.Models);
        return;
      }
      void settings;
    } catch (error) {
      showError(error, 'Could not read settings');
      return;
    }

    const conversation = this.store.ensureCurrent();
    if (conversation.messages.length === 0 || conversation.title === 'New Chat') {
      conversation.title = titleFromPrompt(trimmed);
    }

    const userMessage = createMessage('user', trimmed);
    const assistantMessage = createMessage('assistant', '');
    this.store.update((c) => {
      c.messages.push(userMessage, assistantMessage);
      c.modelId = model.id;
    });
    this.publishConversations();
    this.render();
    this.scrollToBottom();

    const settings = await loadAppSettings();
    const options = {
      ...generationOptions({ model: model.id }),
      systemPrompt: settings.systemPrompt,
      reasoning: {
        mode: settings.reasoning ? ('ON' as const) : ('OFF' as const),
        includeInOutput: settings.reasoning,
      },
    };

    const history = toSdkMessages(
      conversation.messages.filter((m) => m.id !== assistantMessage.id),
    );

    this.setGenerating(true);
    this.liveAssistantId = assistantMessage.id;
    this.attachLiveStream(assistantMessage.id);

    try {
      const stream = window.runanywhere.llm.generateStream(history, options);
      this.stream = stream;
      await this.consumeStream(stream, assistantMessage.id);
    } catch (error) {
      log.error('generate failed', error);
      this.store.update((c) => {
        const message = c.messages.find((m) => m.id === assistantMessage.id);
        if (message !== undefined) {
          message.error = error instanceof Error ? error.message : 'Generation failed';
        }
      });
      showError(error, 'Generation failed');
      this.render();
    } finally {
      this.stream = null;
      this.liveStream = null;
      this.liveAssistantId = null;
      this.setGenerating(false);
      await this.refreshModelChip();
      this.publishConversations();
      this.context.refreshChrome();
    }
  }

  private attachLiveStream(assistantId: string): void {
    const row = this.messagesHost.querySelector<HTMLElement>(`.ra-msg[data-id="${CSS.escape(assistantId)}"]`);
    if (row === null) return;
    const bubble = row.querySelector('.ra-msg-bubble');
    if (bubble === null) return;
    const stream = new StreamingText();
    stream.setStreaming(true);
    bubble.replaceWith(stream.element);
    this.liveStream = stream;
  }

  private async consumeStream(stream: GenerationHandle, assistantId: string): Promise<void> {
    let answer = '';
    let thinking = '';

    const commit = (
      nextAnswer: string | undefined,
      nextThinking: string | undefined,
      metrics?: ChatMessageRecord['metrics'],
      error?: string,
    ): void => {
      if (nextAnswer !== undefined) answer = nextAnswer;
      if (nextThinking !== undefined) thinking = nextThinking;
      this.store.update((c) => {
        const message = c.messages.find((m) => m.id === assistantId);
        if (message === undefined) return;
        message.content = answer;
        if (thinking.length > 0) message.thinking = thinking;
        if (metrics !== undefined) message.metrics = metrics;
        if (error !== undefined) message.error = error;
      });
      this.patchLive(assistantId, answer, thinking, metrics, error);
      this.scrollToBottom();
    };

    for await (const event of stream) {
      if (this.disposed) break;
      switch (event.type) {
        case 'started':
        case 'outputItemAdded':
        case 'toolCallAdded':
        case 'toolArgumentsDelta':
        case 'toolArgumentsDone':
        case 'usage':
          break;
        case 'textDelta':
          if (this.liveStream !== null) this.liveStream.append(event.text);
          commit(answer + event.text, undefined);
          break;
        case 'reasoningDelta':
          commit(undefined, thinking + event.text);
          break;
        case 'completed':
          this.liveStream?.setStreaming(false);
          this.liveStream?.setContent(event.result.text);
          this.liveStream?.flush();
          commit(event.result.text, event.result.thinkingText, {
            outputTokens: event.result.outputTokens,
            tokensPerSecond: event.result.tokensPerSecond,
            timeToFirstTokenMs: event.result.timeToFirstTokenMs,
          });
          break;
        case 'failed':
          this.liveStream?.setStreaming(false);
          this.liveStream?.setError(true);
          commit(
            event.partial?.text ?? answer,
            event.partial?.thinkingText ?? thinking,
            metricsFromPartial(event.partial),
            event.error.message || 'Generation failed',
          );
          showError(event.error.message, 'Generation failed');
          break;
        case 'cancelled':
          this.liveStream?.setStreaming(false);
          commit(
            event.partial?.text ?? answer,
            event.partial?.thinkingText ?? thinking,
            metricsFromPartial(event.partial),
          );
          break;
        default: {
          const _exhaustive: never = event;
          void _exhaustive;
        }
      }
    }
  }

  private patchLive(
    id: string,
    content: string,
    thinking: string,
    metrics?: ChatMessageRecord['metrics'],
    error?: string,
  ): void {
    const row = this.messagesHost.querySelector<HTMLElement>(`.ra-msg[data-id="${CSS.escape(id)}"]`);
    if (row === null) {
      this.render();
      return;
    }

    if (thinking.length > 0) {
      let thinkingEl = row.querySelector<HTMLDetailsElement>('.ra-thinking');
      if (thinkingEl === null) {
        thinkingEl = document.createElement('details');
        thinkingEl.className = 'ra-thinking';
        thinkingEl.open = content.length === 0;
        thinkingEl.innerHTML =
          `<summary>${icon('brain', { size: 14 })}<span>Reasoning</span></summary>` +
          `<div class="ra-thinking-body ra-selectable"></div>`;
        const who = row.querySelector('.ra-msg-who');
        if (who?.nextSibling !== null && who !== null) {
          row.insertBefore(thinkingEl, who.nextSibling);
        } else {
          row.append(thinkingEl);
        }
      }
      const body = thinkingEl.querySelector('.ra-thinking-body');
      if (body !== null) body.textContent = thinking;
    }

    if (error !== undefined) {
      row.dataset.error = 'true';
      const bubble = row.querySelector('.ra-msg-bubble');
      if (bubble !== null) bubble.textContent = error;
    }

    let meta = row.querySelector<HTMLElement>('.ra-msg-meta');
    if (metrics !== undefined && error === undefined) {
      if (meta === null) {
        meta = document.createElement('div');
        meta.className = 'ra-msg-meta';
        row.append(meta);
      }
      meta.textContent = formatMetrics(metrics);
    }
  }

  private async stop(): Promise<void> {
    const stream = this.stream;
    this.stream = null;
    if (stream?.return !== undefined) {
      try {
        await stream.return();
      } catch (error) {
        log.warn('stop failed', error);
      }
    }
    this.liveStream?.setStreaming(false);
    this.setGenerating(false);
  }

  private render(): void {
    const conversation = this.store.current;
    const messages = conversation?.messages ?? [];

    if (messages.length === 0) {
      this.messagesHost.replaceChildren(this.buildEmptyState());
      return;
    }

    const fragment = document.createDocumentFragment();
    messages.forEach((message, index) => {
      fragment.append(this.buildMessage(message, index === messages.length - 1));
    });
    this.messagesHost.replaceChildren(fragment);
  }

  private buildEmptyState(): HTMLElement {
    const wrap = document.createElement('div');
    wrap.className = 'ra-chat-empty';
    wrap.append(emptyStateMark('sparkles'));

    const title = document.createElement('h2');
    title.className = 'ra-empty-title';
    title.textContent = greeting();
    wrap.append(title);

    const subtitle = document.createElement('p');
    subtitle.className = 'ra-empty-subtitle';
    subtitle.textContent = 'Ask anything — everything runs privately on your device.';
    wrap.append(subtitle);

    const grid = document.createElement('div');
    grid.className = 'ra-suggestion-grid';
    for (const starter of STARTER_PROMPTS) {
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'ra-suggestion';
      button.innerHTML =
        `${icon(starter.icon, { size: 18 })}` +
        `<span class="ra-suggestion-copy">` +
        `<strong>${escapeHtml(starter.title)}</strong>` +
        `<small>${escapeHtml(starter.subtitle)}</small>` +
        `</span>`;
      button.addEventListener('click', () => {
        this.composer.input.value = starter.text;
        this.composer.input.dispatchEvent(new Event('input'));
        this.composer.focus();
      });
      grid.append(button);
    }
    wrap.append(grid);
    return wrap;
  }

  private buildMessage(message: ChatMessageRecord, latest: boolean): HTMLElement {
    if (message.role === 'user') {
      const bubble = messageBubble({
        role: 'user',
        bodyHtml: userBubbleHtml(message.content),
      });
      bubble.dataset.id = message.id;
      return bubble;
    }

    const streaming =
      this.generating && this.liveAssistantId === message.id && message.content.length === 0;
    const bodyHtml =
      message.error !== undefined
        ? escapeHtml(message.error)
        : message.content.length === 0 && streaming
          ? ''
          : renderMarkdown(message.content);

    const bubble = messageBubble({
      role: 'assistant',
      bodyHtml,
      thinkingHtml:
        message.thinking !== undefined && message.thinking.length > 0
          ? escapeHtml(message.thinking).replace(/\n/g, '<br>')
          : undefined,
      thinkingOpen: streaming,
      streaming,
      error: message.error !== undefined,
      latest,
      metrics: message.metrics !== undefined ? formatMetrics(message.metrics) : undefined,
      onCopy: () => {
        void navigator.clipboard.writeText(message.content);
        showToast('Copied');
      },
    });
    bubble.dataset.id = message.id;
    wireMarkdown(bubble);
    return bubble;
  }

  private scrollToBottom(): void {
    this.scroll.scrollTop = this.scroll.scrollHeight;
  }
}
