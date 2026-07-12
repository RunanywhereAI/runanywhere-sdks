/**
 * IndexedDB-backed conversation history for the browser example.
 *
 * Conversations are individual database records and the active conversation
 * is metadata. IndexedDB is required; the UI reports when it is unavailable.
 */

import { appLogger } from './app-logger';

export interface StoredConversation {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messages: unknown[];
}

interface PersistedConversationState {
  currentId: string | null;
  conversations: StoredConversation[];
}

export interface ConversationsStoreOptions {
  now?: () => number;
  createId?: () => string;
}

type Listener = () => void;

const DEFAULT_TITLE = 'New chat';
const MAX_TITLE_LENGTH = 56;

export class ConversationsStoreImpl {
  private readonly persistence = new IndexedDBConversationPersistence();
  private readonly now: () => number;
  private readonly createId: () => string;
  private readonly listeners = new Set<Listener>();
  private conversations: StoredConversation[] = [];
  private currentId: string | null = null;
  private initialization: Promise<void> | null = null;
  private mutationQueue: Promise<void> = Promise.resolve();

  constructor(options: ConversationsStoreOptions = {}) {
    this.now = options.now ?? Date.now;
    this.createId = options.createId ?? createConversationId;
  }

  onChange(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  async getConversations(): Promise<StoredConversation[]> {
    await this.waitForReads();
    return this.conversations
      .slice()
      .sort((left, right) => right.updatedAt - left.updatedAt)
      .map(cloneConversation);
  }

  async getCurrent(): Promise<StoredConversation | null> {
    await this.waitForReads();
    if (!this.currentId) return null;
    const conversation = this.conversations.find(({ id }) => id === this.currentId);
    return conversation ? cloneConversation(conversation) : null;
  }

  /** Keep existing conversations and move the composer to a fresh chat. */
  startNew(): Promise<void> {
    return this.mutate(async () => {
      await this.persistence.setCurrentId(null);
      this.currentId = null;
      this.notify();
    });
  }

  setCurrent(id: string): Promise<StoredConversation | null> {
    return this.mutate(async () => {
      const conversation = this.conversations.find((candidate) => candidate.id === id);
      if (!conversation) return null;
      await this.persistence.setCurrentId(id);
      this.currentId = id;
      this.notify();
      return cloneConversation(conversation);
    });
  }

  /** Save a complete snapshot, creating a conversation on the first message. */
  saveCurrent(messages: readonly unknown[]): Promise<StoredConversation | null> {
    const snapshot = cloneMessages(messages);
    return this.mutate(async () => {
      if (snapshot.length === 0) return this.currentConversationClone();

      const timestamp = this.now();
      const currentIndex = this.currentId
        ? this.conversations.findIndex(({ id }) => id === this.currentId)
        : -1;
      const current = currentIndex >= 0 ? this.conversations[currentIndex] : null;
      const next: StoredConversation = {
        id: current?.id ?? this.createId(),
        title: titleFromMessages(snapshot),
        createdAt: current?.createdAt ?? timestamp,
        updatedAt: timestamp,
        messages: snapshot,
      };

      await this.persistence.saveAndSelect(next);
      if (currentIndex >= 0) {
        this.conversations[currentIndex] = next;
      } else {
        this.conversations.push(next);
      }
      this.currentId = next.id;
      this.notify();
      return cloneConversation(next);
    });
  }

  delete(id: string): Promise<boolean> {
    return this.mutate(async () => {
      const index = this.conversations.findIndex((conversation) => conversation.id === id);
      if (index < 0) return false;
      const nextCurrentId = this.currentId === id ? null : this.currentId;
      await this.persistence.delete(id, nextCurrentId);
      this.conversations.splice(index, 1);
      this.currentId = nextCurrentId;
      this.notify();
      return true;
    });
  }

  private async initialize(): Promise<void> {
    const loaded = await this.persistence.load();
    this.conversations = loaded.conversations;
    this.currentId = validCurrentId(loaded.currentId, this.conversations);
  }

  private ensureInitialized(): Promise<void> {
    this.initialization ??= this.initialize();
    return this.initialization;
  }

  private async waitForReads(): Promise<void> {
    await this.ensureInitialized();
    await this.mutationQueue;
  }

  private mutate<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.mutationQueue.then(async () => {
      await this.ensureInitialized();
      return operation();
    });
    this.mutationQueue = result.then(() => undefined, () => undefined);
    return result;
  }

  private currentConversationClone(): StoredConversation | null {
    if (!this.currentId) return null;
    const current = this.conversations.find(({ id }) => id === this.currentId);
    return current ? cloneConversation(current) : null;
  }

  private notify(): void {
    for (const listener of this.listeners) {
      try {
        listener();
      } catch (error) {
        appLogger.warning('[Conversations] Listener failed:', error);
      }
    }
  }
}

const DB_NAME = 'runanywhere-ai-example';
const DB_VERSION = 1;
const CONVERSATIONS_STORE = 'conversations';
const METADATA_STORE = 'metadata';
const CURRENT_ID_KEY = 'currentConversationId';

class IndexedDBConversationPersistence {
  async load(): Promise<PersistedConversationState> {
    return this.withDatabase(async (database) => {
      const transaction = database.transaction(
        [CONVERSATIONS_STORE, METADATA_STORE],
        'readonly',
      );
      const conversationsRequest = transaction.objectStore(CONVERSATIONS_STORE).getAll();
      const currentRequest = transaction.objectStore(METADATA_STORE).get(CURRENT_ID_KEY);
      const [conversations, currentRecord] = await Promise.all([
        requestResult<unknown[]>(conversationsRequest),
        requestResult<unknown>(currentRequest),
        transactionComplete(transaction),
      ]);
      const currentId = isRecord(currentRecord) && typeof currentRecord.value === 'string'
        ? currentRecord.value
        : null;
      return {
        currentId,
        conversations: conversations
          .map(normalizeConversation)
          .filter((value): value is StoredConversation => value !== null),
      };
    });
  }

  saveAndSelect(conversation: StoredConversation): Promise<void> {
    return this.write((transaction) => {
      transaction.objectStore(CONVERSATIONS_STORE).put(conversation);
      transaction.objectStore(METADATA_STORE).put({
        key: CURRENT_ID_KEY,
        value: conversation.id,
      });
    });
  }

  setCurrentId(id: string | null): Promise<void> {
    return this.write((transaction) => {
      transaction.objectStore(METADATA_STORE).put({ key: CURRENT_ID_KEY, value: id });
    });
  }

  delete(id: string, currentId: string | null): Promise<void> {
    return this.write((transaction) => {
      transaction.objectStore(CONVERSATIONS_STORE).delete(id);
      transaction.objectStore(METADATA_STORE).put({ key: CURRENT_ID_KEY, value: currentId });
    });
  }

  private async write(action: (transaction: IDBTransaction) => void): Promise<void> {
    await this.withDatabase(async (database) => {
      const transaction = database.transaction(
        [CONVERSATIONS_STORE, METADATA_STORE],
        'readwrite',
      );
      action(transaction);
      await transactionComplete(transaction);
    });
  }

  private async withDatabase<T>(action: (database: IDBDatabase) => Promise<T>): Promise<T> {
    const database = await openConversationDatabase();
    try {
      return await action(database);
    } finally {
      database.close();
    }
  }
}

function openConversationDatabase(): Promise<IDBDatabase> {
  if (typeof indexedDB === 'undefined') {
    return Promise.reject(new Error('IndexedDB is unavailable; saved chats cannot be persisted.'));
  }
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains(CONVERSATIONS_STORE)) {
        database.createObjectStore(CONVERSATIONS_STORE, { keyPath: 'id' });
      }
      if (!database.objectStoreNames.contains(METADATA_STORE)) {
        database.createObjectStore(METADATA_STORE, { keyPath: 'key' });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error ?? new Error('Could not open conversation database'));
    request.onblocked = () => reject(new Error('Conversation database upgrade is blocked'));
  });
}

function requestResult<T>(request: IDBRequest): Promise<T> {
  return new Promise((resolve, reject) => {
    request.onsuccess = () => resolve(request.result as T);
    request.onerror = () => reject(request.error ?? new Error('Conversation database request failed'));
  });
}

function transactionComplete(transaction: IDBTransaction): Promise<void> {
  return new Promise((resolve, reject) => {
    transaction.oncomplete = () => resolve();
    transaction.onerror = () => reject(
      transaction.error ?? new Error('Conversation database transaction failed'),
    );
    transaction.onabort = () => reject(
      transaction.error ?? new Error('Conversation database transaction aborted'),
    );
  });
}

function normalizeConversation(value: unknown): StoredConversation | null {
  if (!isRecord(value)
    || typeof value.id !== 'string'
    || value.id.length === 0
    || !Array.isArray(value.messages)) {
    return null;
  }
  const createdAt = finiteTimestamp(value.createdAt) ?? Date.now();
  const updatedAt = finiteTimestamp(value.updatedAt) ?? createdAt;
  const messages = cloneMessages(value.messages);
  return {
    id: value.id,
    title: typeof value.title === 'string' && value.title.trim()
      ? value.title.trim().slice(0, MAX_TITLE_LENGTH)
      : titleFromMessages(messages),
    createdAt,
    updatedAt,
    messages,
  };
}

function validCurrentId(
  candidate: string | null,
  conversations: readonly StoredConversation[],
): string | null {
  return candidate && conversations.some(({ id }) => id === candidate) ? candidate : null;
}

function titleFromMessages(messages: readonly unknown[]): string {
  for (const message of messages) {
    if (!isRecord(message) || message.role !== 'user' || typeof message.content !== 'string') continue;
    const firstLine = message.content.trim().split(/\r?\n/, 1)[0].trim();
    if (firstLine) return firstLine.slice(0, MAX_TITLE_LENGTH);
  }
  return DEFAULT_TITLE;
}

function createConversationId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `chat-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function cloneConversation(conversation: StoredConversation): StoredConversation {
  return { ...conversation, messages: cloneMessages(conversation.messages) };
}

function cloneMessages(messages: readonly unknown[]): unknown[] {
  try {
    const value: unknown = JSON.parse(JSON.stringify(messages));
    return Array.isArray(value) ? value : [];
  } catch {
    return [];
  }
}

function finiteTimestamp(value: unknown): number | null {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

export const ConversationsStore = new ConversationsStoreImpl();
