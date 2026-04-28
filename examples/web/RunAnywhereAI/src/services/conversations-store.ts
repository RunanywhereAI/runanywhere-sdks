/**
 * Multi-conversation history with localStorage persistence.
 *
 * Mirrors iOS / Flutter ConversationStore:
 *   - List of conversations keyed by id
 *   - One "current" conversation pointer
 *   - Auto-titled from first user message
 *   - Persisted to localStorage under STORAGE_KEY
 *
 * Pure data layer — UI code in chat.ts owns the sidebar drawer and
 * subscribes via onChange().
 */

export interface StoredMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: number;
}

export interface Conversation {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messages: StoredMessage[];
}

const STORAGE_KEY = 'runanywhere-conversations';
const CURRENT_ID_KEY = 'runanywhere-conversation-current';

type Listener = () => void;

class ConversationsStoreImpl {
  private conversations: Conversation[] = [];
  private currentId: string | null = null;
  private listeners = new Set<Listener>();

  constructor() {
    this.load();
  }

  // ---- Subscription ----

  onChange(fn: Listener): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private notify(): void {
    for (const fn of this.listeners) {
      try { fn(); } catch (e) { console.warn('[Conversations] listener error', e); }
    }
  }

  // ---- Read ----

  getConversations(): Conversation[] {
    return [...this.conversations].sort((a, b) => b.updatedAt - a.updatedAt);
  }

  getCurrent(): Conversation | null {
    if (!this.currentId) return null;
    return this.conversations.find(c => c.id === this.currentId) ?? null;
  }

  // ---- Write ----

  /** Create a new conversation and make it current. */
  create(): Conversation {
    const conv: Conversation = {
      id: crypto.randomUUID(),
      title: 'New Chat',
      createdAt: Date.now(),
      updatedAt: Date.now(),
      messages: [],
    };
    this.conversations.unshift(conv);
    this.currentId = conv.id;
    this.persist();
    this.notify();
    return conv;
  }

  /** Switch the active conversation. Returns null if id is unknown. */
  setCurrent(id: string): Conversation | null {
    const conv = this.conversations.find(c => c.id === id);
    if (!conv) return null;
    this.currentId = id;
    this.persist();
    this.notify();
    return conv;
  }

  /** Append message to current conversation, creating one if needed. */
  appendMessage(msg: StoredMessage): void {
    let conv = this.getCurrent();
    if (!conv) {
      conv = this.create();
    }
    conv.messages.push(msg);
    conv.updatedAt = Date.now();

    // Auto-title from first user message
    if (conv.title === 'New Chat' && msg.role === 'user' && msg.content.trim().length > 0) {
      const firstLine = msg.content.trim().split('\n')[0];
      conv.title = firstLine.length > 50 ? firstLine.slice(0, 50) : firstLine;
    }

    this.persist();
    this.notify();
  }

  /** Replace the most recent assistant message's content (used during streaming). */
  updateLastAssistantContent(content: string): void {
    const conv = this.getCurrent();
    if (!conv) return;
    const last = conv.messages[conv.messages.length - 1];
    if (last && last.role === 'assistant') {
      last.content = content;
      conv.updatedAt = Date.now();
      this.persist();
    }
  }

  /** Delete a conversation. If it was current, advance to next or null. */
  delete(id: string): void {
    const idx = this.conversations.findIndex(c => c.id === id);
    if (idx === -1) return;
    this.conversations.splice(idx, 1);
    if (this.currentId === id) {
      this.currentId = this.conversations[0]?.id ?? null;
    }
    this.persist();
    this.notify();
  }

  // ---- Persistence ----

  private load(): void {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw) as Conversation[];
        if (Array.isArray(parsed)) {
          this.conversations = parsed;
        }
      }
      this.currentId = localStorage.getItem(CURRENT_ID_KEY);
      if (this.currentId && !this.conversations.find(c => c.id === this.currentId)) {
        this.currentId = this.conversations[0]?.id ?? null;
      }
    } catch (e) {
      console.warn('[Conversations] load failed:', e);
      this.conversations = [];
      this.currentId = null;
    }
  }

  private persist(): void {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.conversations));
      if (this.currentId) {
        localStorage.setItem(CURRENT_ID_KEY, this.currentId);
      } else {
        localStorage.removeItem(CURRENT_ID_KEY);
      }
    } catch (e) {
      console.warn('[Conversations] persist failed:', e);
    }
  }
}

export const ConversationsStore = new ConversationsStoreImpl();
