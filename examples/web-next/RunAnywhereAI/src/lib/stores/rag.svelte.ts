import { RAGConfiguration, RAGDocument, RAGQueryOptions } from '@runanywhere/proto-ts/rag';
import { models } from './models.svelte';

export interface RagSource {
  document: string;
  text: string;
  score: number;
}

export interface RagMessage {
  id: number;
  isUser: boolean;
  text: string;
  sources: RagSource[];
  elapsedMs: number;
  pending: boolean;
}

class RagStore {
  busy = $state(false);
  generating = $state(false);
  chunkCount = $state(0);
  documents = $state<string[]>([]);
  messages = $state<RagMessage[]>([]);
  error = $state<string | null>(null);

  private sessionId: number | null = null;
  private sessionEmbeddingId: string | null = null;
  private sessionLlmId: string | null = null;
  private seq = 0;

  get embeddingReady(): boolean {
    return models.loadedEmbeddingId != null;
  }

  get llmReady(): boolean {
    return models.loadedLlmId != null;
  }

  get ready(): boolean {
    return this.embeddingReady && this.llmReady;
  }

  get hasDocuments(): boolean {
    return this.documents.length > 0;
  }

  get canQuery(): boolean {
    return this.ready && this.hasDocuments && !this.generating;
  }

  private async ensureEngine(): Promise<void> {
    const { sdk } = await import('./sdk.svelte');
    await sdk.boot();
    if (!sdk.ready) throw new Error(sdk.message || 'Engine failed to start');
  }

  private async ensureSession(): Promise<number> {
    const embeddingModelId = models.loadedEmbeddingId;
    const llmModelId = models.loadedLlmId;
    if (!embeddingModelId) throw new Error('Load an embedding model first');
    if (!llmModelId) throw new Error('Load a language model first');
    // A new embedding or language model means a new pipeline — rebuild it.
    if (this.sessionId != null && (this.sessionEmbeddingId !== embeddingModelId || this.sessionLlmId !== llmModelId)) {
      await this.destroySession();
    }
    if (this.sessionId != null) return this.sessionId;

    await this.ensureEngine();
    const { RunAnywhere } = await import('@runanywhere/web');
    const config = RAGConfiguration.fromPartial({
      embeddingModelId,
      llmModelId,
      topK: 4,
      similarityThreshold: 0,
      chunkSize: 256,
      chunkOverlap: 32,
      persistIndex: false,
      rerankResults: false,
    });
    const id = await RunAnywhere.ragCreateSession(config);
    if (id == null) throw new Error('Failed to create RAG session');
    this.sessionId = id;
    this.sessionEmbeddingId = embeddingModelId;
    this.sessionLlmId = llmModelId;
    return id;
  }

  private async destroySession(): Promise<void> {
    const session = this.sessionId;
    if (session != null) {
      const { RunAnywhere } = await import('@runanywhere/web');
      await RunAnywhere.ragDestroySession(session);
    }
    this.sessionId = null;
    this.sessionEmbeddingId = null;
    this.sessionLlmId = null;
    this.documents = [];
    this.chunkCount = 0;
  }

  private uniqueName(name: string): string {
    if (!this.documents.includes(name)) return name;
    const dot = name.lastIndexOf('.');
    const stem = dot > 0 ? name.slice(0, dot) : name;
    const ext = dot > 0 ? name.slice(dot) : '';
    let n = 2;
    while (this.documents.includes(`${stem} (${n})${ext}`)) n += 1;
    return `${stem} (${n})${ext}`;
  }

  async ingest(name: string, text: string): Promise<void> {
    const content = text.trim();
    if (!content || this.busy) return;
    this.busy = true;
    this.error = null;
    try {
      const session = await this.ensureSession();
      const docId = this.uniqueName(name.trim() || `document ${this.documents.length + 1}`);
      const { RunAnywhere } = await import('@runanywhere/web');
      const stats = await RunAnywhere.ragIngest(session, RAGDocument.fromPartial({ id: docId, text: content }));
      this.documents = [...this.documents, docId];
      this.chunkCount = stats?.indexedChunks ?? this.chunkCount;
    } catch (err) {
      this.error = err instanceof Error ? err.message : String(err);
    } finally {
      this.busy = false;
    }
  }

  async ask(question: string): Promise<void> {
    const q = question.trim();
    if (!q || !this.canQuery) return;
    this.error = null;
    this.messages = [...this.messages, { id: ++this.seq, isUser: true, text: q, sources: [], elapsedMs: 0, pending: false }];
    const answer: RagMessage = { id: ++this.seq, isUser: false, text: '', sources: [], elapsedMs: 0, pending: true };
    this.messages = [...this.messages, answer];
    this.generating = true;
    const started = Date.now();

    const patch = (next: Partial<RagMessage>): void => {
      this.messages = this.messages.map((m) => (m.id === answer.id ? { ...m, ...next } : m));
    };

    try {
      const session = await this.ensureSession();
      const { RunAnywhere } = await import('@runanywhere/web');
      const result = await RunAnywhere.ragQuery(
        session,
        RAGQueryOptions.fromPartial({
          question: q,
          retrievalTopK: 4,
          similarityThreshold: 0,
          maxTokens: 512,
          temperature: 0.3,
          topP: 0.9,
          stream: false,
          disableThinking: true,
        }),
      );
      const sources: RagSource[] = (result?.retrievedChunks ?? []).map((c) => ({
        document: c.sourceDocument || 'Document',
        text: c.text,
        score: c.similarityScore,
      }));
      const answerText = result?.answer?.trim()
        ? result.answer
        : sources.length === 0
          ? 'No relevant passages found in your documents.'
          : 'No answer was generated.';
      patch({ sources, text: answerText });
    } catch (err) {
      patch({ text: `Error: ${err instanceof Error ? err.message : String(err)}` });
    } finally {
      patch({ pending: false, elapsedMs: Date.now() - started });
      this.generating = false;
    }
  }

  async clearAll(): Promise<void> {
    if (this.busy || this.generating) return;
    this.messages = [];
    this.error = null;
    await this.destroySession();
  }
}

export const rag = new RagStore();
