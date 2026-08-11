/**
 * Conversation shapes shared by main (which persists them) and the renderer
 * (which renders them). Mirrors the Swift app's ConversationStore model.
 */

export type MessageRole = 'user' | 'assistant';

/** A tool the model chose to call, and what the tool returned. */
export interface ToolCallRecord {
  readonly name: string;
  readonly arguments: Readonly<Record<string, unknown>>;
  readonly result?: unknown;
  readonly error?: string;
}

/** An image or document the user attached to a turn. */
export interface AttachmentRecord {
  readonly kind: 'image' | 'document';
  readonly name: string;
  /** On-disk path, resolved via webUtils.getPathForFile — never a File object. */
  readonly path: string;
  readonly sizeBytes: number;
}

/** What the model reported about a generation, for the analytics footer. */
export interface GenerationMetricsRecord {
  readonly outputTokens: number;
  readonly tokensPerSecond: number;
  readonly timeToFirstTokenMs: number;
}

export interface ChatMessageRecord {
  readonly id: string;
  readonly role: MessageRole;
  content: string;
  /** Reasoning the model emitted separately from its answer. */
  thinking?: string;
  toolCalls?: readonly ToolCallRecord[];
  attachments?: readonly AttachmentRecord[];
  metrics?: GenerationMetricsRecord;
  /** Set when generation failed; the turn is kept so the user can retry. */
  error?: string;
  readonly createdAtUnixMs: number;
}

export interface ConversationRecord {
  readonly id: string;
  title: string;
  messages: ChatMessageRecord[];
  readonly createdAtUnixMs: number;
  updatedAtUnixMs: number;
  /** Which model produced the most recent turn, for the history subtitle. */
  modelId?: string;
}

/** The persisted file shape. Versioned so a later migration has something to read. */
export interface ConversationsFile {
  readonly version: 1;
  conversations: ConversationRecord[];
}

export const EMPTY_CONVERSATIONS: Readonly<ConversationsFile> = Object.freeze({
  version: 1,
  conversations: [],
});

/**
 * Keep the newest `max` conversations. The store is rewritten in full on every
 * message, so an unbounded list turns into an ever-growing synchronous write.
 */
export function capConversations(
  conversations: readonly ConversationRecord[] | unknown,
  max = 200,
): ConversationRecord[] {
  if (!Array.isArray(conversations)) return [];
  const list = conversations as ConversationRecord[];
  return list.length > max ? list.slice(0, max) : list;
}

/** Group conversations the way the macOS history sheet does. */
export type HistoryBucket = 'Today' | 'Yesterday' | 'Previous 7 Days' | 'Previous 30 Days' | 'Older';

export function historyBucket(updatedAtUnixMs: number, now: number): HistoryBucket {
  const day = 86_400_000;
  const startOfToday = new Date(now).setHours(0, 0, 0, 0);
  if (updatedAtUnixMs >= startOfToday) return 'Today';
  if (updatedAtUnixMs >= startOfToday - day) return 'Yesterday';
  if (updatedAtUnixMs >= startOfToday - 7 * day) return 'Previous 7 Days';
  if (updatedAtUnixMs >= startOfToday - 30 * day) return 'Previous 30 Days';
  return 'Older';
}
