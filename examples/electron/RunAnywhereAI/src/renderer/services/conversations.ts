/**
 * Thin conversation store client.
 *
 * Main owns the JSON file; this module is the renderer's only write path so Chat
 * and the sidebar never diverge on what is persisted.
 */
import {
  EMPTY_CONVERSATIONS,
  capConversations,
  type ChatMessageRecord,
  type ConversationRecord,
  type ConversationsFile,
} from '@shared/conversation';

import { logger } from './logger';

const log = logger('conversations');

function newId(): string {
  return crypto.randomUUID();
}

/** Title from the first user turn — matches ConversationStore on macOS. */
export function titleFromPrompt(prompt: string): string {
  const trimmed = prompt.trim().replace(/\s+/g, ' ');
  if (trimmed.length === 0) return 'New Chat';
  return trimmed.length > 42 ? `${trimmed.slice(0, 42)}…` : trimmed;
}

export function createMessage(
  role: ChatMessageRecord['role'],
  content: string,
  extras: Partial<Omit<ChatMessageRecord, 'id' | 'role' | 'content' | 'createdAtUnixMs'>> = {},
): ChatMessageRecord {
  return {
    id: newId(),
    role,
    content,
    createdAtUnixMs: Date.now(),
    ...extras,
  };
}

export function createConversation(title = 'New Chat'): ConversationRecord {
  const now = Date.now();
  return {
    id: newId(),
    title,
    messages: [],
    createdAtUnixMs: now,
    updatedAtUnixMs: now,
  };
}

export class ConversationStore {
  private file: ConversationsFile = { version: 1, conversations: [] };
  private currentId: string | null = null;
  private saveTimer: ReturnType<typeof setTimeout> | null = null;

  get conversations(): readonly ConversationRecord[] {
    return this.file.conversations;
  }

  get currentConversationId(): string | null {
    return this.currentId;
  }

  get current(): ConversationRecord | null {
    if (this.currentId === null) return null;
    return this.file.conversations.find((c) => c.id === this.currentId) ?? null;
  }

  async load(): Promise<void> {
    try {
      const saved = await window.appStore.loadConversations();
      this.file = {
        version: 1,
        conversations: capConversations(saved.conversations),
      };
      this.currentId = this.file.conversations[0]?.id ?? null;
    } catch (error) {
      log.warn('load failed', error);
      this.file = { ...EMPTY_CONVERSATIONS, conversations: [] };
      this.currentId = null;
    }
  }

  select(id: string | null): void {
    this.currentId = id;
  }

  /** Create an empty conversation and make it current. */
  create(): ConversationRecord {
    const conversation = createConversation();
    this.file.conversations = [conversation, ...this.file.conversations];
    this.currentId = conversation.id;
    this.scheduleSave();
    return conversation;
  }

  /** Ensure there is a current conversation, creating one if needed. */
  ensureCurrent(): ConversationRecord {
    const existing = this.current;
    if (existing !== null) return existing;
    return this.create();
  }

  update(mutator: (conversation: ConversationRecord) => void): ConversationRecord {
    const conversation = this.ensureCurrent();
    mutator(conversation);
    conversation.updatedAtUnixMs = Date.now();
    // Newest-first, matching the sidebar sort.
    this.file.conversations = [
      conversation,
      ...this.file.conversations.filter((c) => c.id !== conversation.id),
    ];
    this.scheduleSave();
    return conversation;
  }

  rename(id: string, title: string): void {
    const trimmed = title.trim();
    if (trimmed.length === 0) return;
    const conversation = this.file.conversations.find((c) => c.id === id);
    if (conversation === undefined) return;
    conversation.title = trimmed;
    conversation.updatedAtUnixMs = Date.now();
    this.scheduleSave();
  }

  delete(id: string): void {
    this.file.conversations = this.file.conversations.filter((c) => c.id !== id);
    if (this.currentId === id) {
      this.currentId = this.file.conversations[0]?.id ?? null;
    }
    this.scheduleSave();
  }

  private scheduleSave(): void {
    if (this.saveTimer !== null) clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      void this.flush();
    }, 200);
  }

  async flush(): Promise<void> {
    this.file.conversations = capConversations(this.file.conversations);
    try {
      await window.appStore.saveConversations({
        version: 1,
        conversations: this.file.conversations,
      });
    } catch (error) {
      log.warn('save failed', error);
    }
  }
}
