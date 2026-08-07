import {
  ModelCategory,
  RunAnywhere,
  type LlmOptions,
  type Match,
  type ModelInfo,
  type RagSession,
} from '@runanywhere/web';
import { findLoadedModelForCategory } from '../components/model-selection';

export type ChatAttachmentKind = 'image' | 'document';

export interface ChatAttachmentGenerationSettings {
  maxTokens: number;
  temperature: number;
  thinkingModeEnabled: boolean;
}

export interface ChatAttachmentSource {
  document: string;
  text: string;
}

export interface ChatAttachmentAnswer {
  content: string;
  thinking?: string;
  sources?: ChatAttachmentSource[];
}

export interface ChatAttachmentProgress {
  content: string;
}

const CAPTURE_DIMENSION = 384;
const DOCUMENT_TOP_K = 3;
const MAX_IMAGE_ATTACHMENT_BYTES = 12 * 1024 * 1024;
const MAX_DOCUMENT_ATTACHMENT_BYTES = 4 * 1024 * 1024;
let activeDocumentCancellation: AbortController | null = null;
let activeImageStream: AsyncIterator<unknown> | null = null;
let activeDocumentSession: RagSession | null = null;

export function validateChatAttachmentFile(kind: ChatAttachmentKind, file: File): string | null {
  const limit = kind === 'image' ? MAX_IMAGE_ATTACHMENT_BYTES : MAX_DOCUMENT_ATTACHMENT_BYTES;
  if (file.size <= limit) return null;
  return `${kind === 'image' ? 'Images' : 'Documents'} must be ${formatBytes(limit)} or smaller.`;
}

export function canAnswerImageAttachment(): boolean {
  return findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_MULTIMODAL) !== null
    || findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_VISION) !== null;
}

export function cancelActiveImageAttachmentAnswer(): void {
  // Abandoning the iterator is the cancellation contract for every v3 stream.
  void activeImageStream?.return?.();
  activeImageStream = null;
}

export function cancelActiveDocumentAttachmentAnswer(): void {
  activeDocumentCancellation?.abort();
  void activeDocumentSession?.close().catch(() => undefined);
  activeDocumentSession = null;
}

export async function answerImageAttachment(
  file: File,
  prompt: string,
  settings: ChatAttachmentGenerationSettings,
  onProgress: (progress: ChatAttachmentProgress) => void,
): Promise<ChatAttachmentAnswer> {
  assertChatAttachmentFileSize('image', file);
  onProgress({ content: 'Reading image...' });

  const frame = await decodeImageToRgbFrame(file, CAPTURE_DIMENSION);
  const image = RunAnywhere.ImageInput.rawRgb(frame.rgbPixels, frame.width, frame.height);

  let content = '';
  onProgress({ content });
  const events = RunAnywhere.vlm.generateStream(image, prompt, {
    maxOutputTokens: 256,
    temperature: settings.temperature,
    topP: 0.9,
    topK: 40,
  });
  const iterator = events[Symbol.asyncIterator]();
  activeImageStream = iterator;
  try {
    for (let step = await iterator.next(); !step.done; step = await iterator.next()) {
      const event = step.value;
      if (event.type === 'textDelta') {
        content += event.text;
        onProgress({ content });
      }
    }
  } finally {
    if (activeImageStream === iterator) activeImageStream = null;
  }

  return { content: content || '(empty response)' };
}

export async function answerDocumentAttachment(
  file: File,
  question: string,
  settings: ChatAttachmentGenerationSettings,
  onProgress: (progress: ChatAttachmentProgress) => void,
): Promise<ChatAttachmentAnswer> {
  const cancellation = new AbortController();
  activeDocumentCancellation?.abort();
  activeDocumentCancellation = cancellation;
  try {
    assertChatAttachmentFileSize('document', file);
    const models = resolveRAGModels();
    if (!models.embedding || !models.llm) {
      throw new Error('Document Q&A needs an embedding model and a chat model in the catalog.');
    }

    onProgress({ content: 'Indexing document...' });
    const text = await file.text();
    throwIfDocumentCancelled(cancellation.signal);
    if (!text.trim()) {
      throw new Error('The selected document does not contain readable text.');
    }

    await activeDocumentSession?.close().catch(() => undefined);
    const session = await RunAnywhere.rag.open(
      { id: models.embedding.id },
      { id: models.llm.id },
      { topK: DOCUMENT_TOP_K },
    );
    activeDocumentSession = session;
    throwIfDocumentCancelled(cancellation.signal);
    await session.ingest({
      text,
      name: file.name || 'Document',
      metadata: {
        docId: createDocumentId(),
        sourceUri: `web-file:${file.name || 'document'}`,
        mediaType: file.type || 'text/plain',
        sizeBytes: String(file.size),
      },
    });
    throwIfDocumentCancelled(cancellation.signal);

    onProgress({ content: 'Searching document...' });

    const generation: LlmOptions = {
      maxOutputTokens: Math.min(settings.maxTokens, 1024),
      temperature: settings.temperature,
      reasoning: models.llm.supportsThinking && !settings.thinkingModeEnabled
        ? { mode: 'off' }
        : { mode: 'on', includeInOutput: true },
    };
    const result = await session.query(question, { generation });
    throwIfDocumentCancelled(cancellation.signal);

    const split = splitThinking(result.answer);
    return {
      content: split.content || result.answer || '(no answer)',
      thinking: split.thinking || undefined,
      sources: result.sources.map(sourceFromMatch),
    };
  } catch (error) {
    if (cancellation.signal.aborted) {
      throw new DOMException('Document answer cancelled', 'AbortError');
    }
    throw error;
  } finally {
    if (activeDocumentCancellation === cancellation) activeDocumentCancellation = null;
    if (activeDocumentSession) {
      await activeDocumentSession.close().catch(() => undefined);
      activeDocumentSession = null;
    }
  }
}

function throwIfDocumentCancelled(signal: AbortSignal): void {
  if (signal.aborted) throw new DOMException('Document answer cancelled', 'AbortError');
}

function assertChatAttachmentFileSize(kind: ChatAttachmentKind, file: File): void {
  const error = validateChatAttachmentFile(kind, file);
  if (error) throw new Error(error);
}

function resolveRAGModels(): { embedding: ModelInfo | null; llm: ModelInfo | null } {
  return {
    embedding: firstModelForCategory(ModelCategory.MODEL_CATEGORY_EMBEDDING),
    llm: findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE)
      ?? firstModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE),
  };
}

function firstModelForCategory(category: ModelCategory): ModelInfo | null {
  return RunAnywhere.models.list({ category })[0] ?? null;
}

function sourceFromMatch(match: Match): ChatAttachmentSource {
  return {
    document: match.metadata.docName || match.metadata.sourceUri || 'Document',
    text: match.text,
  };
}

async function decodeImageToRgbFrame(
  file: File,
  maxDim: number,
): Promise<{ rgbPixels: Uint8Array; width: number; height: number }> {
  const objectUrl = URL.createObjectURL(file);
  try {
    const img = await loadImageElement(objectUrl);
    const longest = Math.max(img.naturalWidth, img.naturalHeight) || 1;
    const scale = Math.min(1, maxDim / longest);
    const width = Math.max(1, Math.round(img.naturalWidth * scale));
    const height = Math.max(1, Math.round(img.naturalHeight * scale));

    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    if (!ctx) throw new Error('2D canvas context unavailable');
    ctx.drawImage(img, 0, 0, width, height);

    const { data } = ctx.getImageData(0, 0, width, height);
    const rgbPixels = new Uint8Array(width * height * 3);
    for (let src = 0, dst = 0; src < data.length; src += 4, dst += 3) {
      rgbPixels[dst] = data[src];
      rgbPixels[dst + 1] = data[src + 1];
      rgbPixels[dst + 2] = data[src + 2];
    }
    return { rgbPixels, width, height };
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}

function loadImageElement(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('Could not decode the selected image'));
    img.src = src;
  });
}

function createDocumentId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return Math.random().toString(36).slice(2);
}

function splitThinking(raw: string): { content: string; thinking: string } {
  const thinkingParts: string[] = [];
  const content = raw.replace(
    /<(think|thinking)>([\s\S]*?)(<\/\1>|$)/gi,
    (_match, _tag: string, inner: string) => {
      if (inner.trim().length > 0) thinkingParts.push(inner.trim());
      return '';
    },
  );
  return {
    content: content.trim(),
    thinking: thinkingParts.join('\n\n').trim(),
  };
}

function formatBytes(bytes: number): string {
  const units = ['B', 'KB', 'MB', 'GB'];
  let value = bytes;
  let unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex += 1;
  }
  return `${value % 1 === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[unitIndex]}`;
}
