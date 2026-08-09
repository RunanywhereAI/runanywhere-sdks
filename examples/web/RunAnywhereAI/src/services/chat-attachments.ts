/**
 * Answering a question about a file the user attached to the chat composer.
 *
 * Two shapes, one contract: an image goes to the vision model as a picture, a
 * text document is indexed and answered with citations. Both stream, both are
 * cancellable, and both refuse before they start when the models they need are
 * not on the device — iOS parity, where the chat image path checks
 * `models.state().loaded[.multimodal]` first (LLMViewModel+Vision.swift:94-98)
 * and the document path is only reachable once both models have been picked
 * (ChatInterfaceView.swift:855-869). Neither platform downloads gigabytes
 * behind a "Send" press.
 */

import {
  ModelCategory,
  RunAnywhere,
  type LlmOptions,
  type Match,
  type ModelInfo,
  type RagSession,
} from '@runanywhere/web';
import { findLoadedModelForCategory } from '../components/model-selection';
import {
  decodeImageFileToRgbFrame,
  rgbFrameToThumbnailDataUrl,
  validateImageFile,
} from './image-frame';

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
  /**
   * The reader pressed Stop; `content` is whatever had arrived by then.
   *
   * A cancelled turn is not a failed one — it must not be painted in the danger
   * colour, and the partial text must not be thrown away, because the reader can
   * see it on screen and stopping is how they said "that's enough".
   */
  cancelled?: boolean;
}

export interface ChatAttachmentProgress {
  content: string;
}

const CAPTURE_DIMENSION = 384;
const THUMBNAIL_DIMENSION = 96;
const DOCUMENT_TOP_K = 3;
const MAX_DOCUMENT_ATTACHMENT_BYTES = 4 * 1024 * 1024;
/**
 * Ceiling on an attachment answer, above the Settings tab's Max tokens.
 *
 * The image path used to hard-code 256 and ignore the setting entirely, so the
 * Max tokens control in Settings silently did nothing for an image question
 * while governing every other kind. The cap stays because an attachment answer
 * is a description, not an essay.
 */
const MAX_ATTACHMENT_OUTPUT_TOKENS = 1024;

let activeDocumentCancellation: AbortController | null = null;
let activeImageStream: AsyncIterator<unknown> | null = null;
let activeDocumentStream: AsyncIterator<unknown> | null = null;
let activeDocumentSession: RagSession | null = null;
/**
 * Whether the reader stopped the image answer.
 *
 * The VLM stream signals cancellation by simply ending, with no error and no
 * terminal event, so "was this stopped or did the model finish?" can only be
 * answered by the canceller leaving a note.
 */
let imageAnswerCancelled = false;

/**
 * Document types the RAG ingest path can actually read.
 *
 * Kept as extensions as well as MIME types because a dropped or pasted file
 * often arrives with an empty or wrong `type` — Finder and several editors hand
 * over `.md` as `application/octet-stream`, and a strict MIME check would reject
 * a file the ingest path reads perfectly well.
 */
const DOCUMENT_EXTENSIONS = ['.txt', '.md', '.markdown', '.json'];
const DOCUMENT_MIME_TYPES = ['text/plain', 'text/markdown', 'application/json'];

/**
 * Which attachment mode a file belongs to, or `null` if neither can take it.
 *
 * Needed because a drop or a paste does not come from a file input, so there is
 * no `accept` attribute doing the filtering and nothing has decided the mode yet
 * — the file itself has to.
 */
export function kindForFile(file: File): ChatAttachmentKind | null {
  if (file.type.startsWith('image/')) return 'image';
  const name = file.name.toLowerCase();
  if (DOCUMENT_MIME_TYPES.includes(file.type)) return 'document';
  if (DOCUMENT_EXTENSIONS.some((ext) => name.endsWith(ext))) return 'document';
  return null;
}

/**
 * Reject a file the attachment path cannot handle, with a sentence saying why.
 *
 * Type is checked as well as size. The `accept` attribute on the hidden inputs
 * only filters the *picker* — it is a convenience, not a guarantee: a user can
 * switch the picker to "All Files", and a drop or a paste never consults it at
 * all. Without this, a `.pdf` dropped on the composer would be sent to a text
 * ingest path that cannot read it and would fail later with a decode error
 * blamed on the model rather than on the file.
 */
export function validateChatAttachmentFile(kind: ChatAttachmentKind, file: File): string | null {
  if (kind === 'image') return validateImageFile(file);

  if (file.size === 0) return 'That file is empty.';
  if (kindForFile(file) !== 'document') {
    return 'That file type is not supported. Attach a .txt, .md, or .json file.';
  }
  if (file.size > MAX_DOCUMENT_ATTACHMENT_BYTES) {
    return `Documents must be ${formatBytes(MAX_DOCUMENT_ATTACHMENT_BYTES)} or smaller.`;
  }
  return null;
}

export function canAnswerImageAttachment(): boolean {
  return findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_MULTIMODAL) !== null
    || findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_VISION) !== null;
}

/**
 * Whether a document question can be answered right now.
 *
 * The pipeline needs an indexing model *on disk* and a chat model to write the
 * answer with. `rag.open` does not fetch either — it fails with
 * "model is not downloaded — download it first or set validate_availability",
 * an internal sentence that reached the chat bubble verbatim and left the reader
 * with nothing to act on. Asking first is what lets the composer open the model
 * picker instead, the same way the image path already did.
 */
export function canAnswerDocumentAttachment(): boolean {
  const models = resolveRAGModels();
  return models.embedding !== null && models.llm !== null;
}

/** A downloaded thumbnail-sized preview of an image attachment, or `null`. */
export async function imageAttachmentThumbnail(file: File): Promise<string | null> {
  try {
    const frame = await decodeImageFileToRgbFrame(file, CAPTURE_DIMENSION);
    return rgbFrameToThumbnailDataUrl(frame, THUMBNAIL_DIMENSION);
  } catch {
    // A thumbnail is decoration. A file that cannot be decoded here will fail
    // loudly on send, which is where that belongs.
    return null;
  }
}

export function cancelActiveImageAttachmentAnswer(): void {
  // Recorded before the stream check, not after it. Stop is offered from the
  // moment the turn starts, but the stream only exists once the image has
  // finished decoding — a press inside that window used to set nothing and
  // abandon nothing, so the answer ran to completion and was presented as
  // finished rather than stopped.
  imageAnswerCancelled = true;
  if (!activeImageStream) return;
  // Abandoning the iterator is the cancellation contract for every v3 stream.
  void activeImageStream.return?.();
  activeImageStream = null;
}

export function cancelActiveDocumentAttachmentAnswer(): void {
  activeDocumentCancellation?.abort();
  void activeDocumentStream?.return?.();
  activeDocumentStream = null;
}

export async function answerImageAttachment(
  file: File,
  prompt: string,
  settings: ChatAttachmentGenerationSettings,
  onProgress: (progress: ChatAttachmentProgress) => void,
): Promise<ChatAttachmentAnswer> {
  assertChatAttachmentFile('image', file);
  imageAnswerCancelled = false;
  onProgress({ content: 'Reading the image…' });

  const frame = await decodeImageFileToRgbFrame(file, CAPTURE_DIMENSION);
  // The decode is the only suspension before the stream exists, so honouring the
  // flag here closes the window in which Stop had nothing to act on. Thrown as
  // an AbortError because that is what `chat.ts` reads as "Stopped." — mirroring
  // the document path's `throwIfDocumentCancelled`.
  if (imageAnswerCancelled) {
    imageAnswerCancelled = false;
    throw new DOMException('Image answer cancelled', 'AbortError');
  }
  const image = RunAnywhere.ImageInput.rawRgb(frame.rgbPixels, frame.width, frame.height);

  let content = '';
  onProgress({ content });
  const events = RunAnywhere.vlm.generateStream(image, prompt, {
    maxOutputTokens: Math.min(settings.maxTokens, MAX_ATTACHMENT_OUTPUT_TOKENS),
    temperature: settings.temperature,
    topP: 0.9,
    topK: 40,
    ...reasoningFor(visionModelSupportsThinking(), settings),
  });
  const iterator = events[Symbol.asyncIterator]();
  activeImageStream = iterator;
  try {
    for (let step = await iterator.next(); !step.done; step = await iterator.next()) {
      const event = step.value;
      if (event.type === 'textDelta') {
        content += event.text;
        onProgress({ content });
      } else if (event.type === 'failed') {
        // A mid-stream failure arrives as an event, not a throw. Swallowing it
        // — which this loop used to do — reported a broken vision pipeline as an
        // empty answer, which is the one thing an error must never look like.
        throw new Error(event.error.message || 'The vision model failed mid-answer.');
      }
    }
  } finally {
    if (activeImageStream === iterator) activeImageStream = null;
  }

  const cancelled = imageAnswerCancelled;
  imageAnswerCancelled = false;

  // A vision model with a thinking phase emits its reasoning as literal
  // `<think>` tags in the same channel as the answer; without splitting them the
  // markup landed in the bubble as prose.
  const split = splitThinking(content);
  return {
    content: split.content || (cancelled ? '' : content),
    thinking: split.thinking || undefined,
    cancelled,
  };
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
  let session: RagSession | null = null;
  try {
    assertChatAttachmentFile('document', file);
    const models = resolveRAGModels();
    if (!models.embedding || !models.llm) {
      throw new Error(documentModelsMissingMessage());
    }

    onProgress({ content: 'Reading the document…' });
    const text = await file.text();
    throwIfDocumentCancelled(cancellation.signal);
    if (!text.trim()) {
      throw new Error('The selected document does not contain readable text.');
    }

    await closeActiveDocumentSession();
    session = await RunAnywhere.rag.open(
      { id: models.embedding.id },
      { id: models.llm.id },
      { topK: DOCUMENT_TOP_K },
    );
    activeDocumentSession = session;
    throwIfDocumentCancelled(cancellation.signal);
    onProgress({ content: 'Indexing the document…' });
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

    onProgress({ content: 'Finding the relevant passages…' });

    const generation: LlmOptions = {
      maxOutputTokens: Math.min(settings.maxTokens, MAX_ATTACHMENT_OUTPUT_TOKENS),
      temperature: settings.temperature,
      ...reasoningFor(models.llm.supportsThinking, settings),
    };
    // Streamed, not one-shot: iOS moved to `queryStream` because the v4 pipeline
    // resolves the one-shot `query` with an empty answer
    // (LLMViewModel+Documents.swift:72-77), and streaming is also what makes the
    // wait legible — retrieval lands first, then the answer writes itself.
    const events = session.queryStream(question, { generation });
    const iterator = events[Symbol.asyncIterator]();
    activeDocumentStream = iterator;
    let answer = '';
    let sources: ChatAttachmentSource[] = [];
    try {
      for (let step = await iterator.next(); !step.done; step = await iterator.next()) {
        const event = step.value;
        if (event.type === 'retrieved') {
          sources = event.matches.map(sourceFromMatch);
        } else if (event.type === 'textDelta') {
          answer += event.text;
          onProgress({ content: splitThinking(answer).content || answer });
        } else if (event.type === 'completed') {
          answer = event.result.answer || answer;
          if (event.result.sources.length > 0) sources = event.result.sources.map(sourceFromMatch);
        } else if (event.type === 'failed') {
          throw new Error(event.error.message || 'The document answer failed.');
        }
      }
    } finally {
      if (activeDocumentStream === iterator) activeDocumentStream = null;
    }

    const cancelled = cancellation.signal.aborted;
    const split = splitThinking(answer);
    return {
      content: split.content || (cancelled ? '' : answer),
      thinking: split.thinking || undefined,
      sources: sources.length > 0 ? sources : undefined,
      cancelled,
    };
  } catch (error) {
    if (cancellation.signal.aborted) {
      throw new DOMException('Document answer cancelled', 'AbortError');
    }
    throw error;
  } finally {
    if (activeDocumentCancellation === cancellation) activeDocumentCancellation = null;
    // Only close the session this call opened. Closing `activeDocumentSession`
    // unconditionally meant a second question — which aborts the first — tore
    // down the session the *second* call had just opened.
    if (session && activeDocumentSession === session) await closeActiveDocumentSession();
  }
}

async function closeActiveDocumentSession(): Promise<void> {
  const previous = activeDocumentSession;
  activeDocumentSession = null;
  if (previous) await previous.close().catch(() => undefined);
}

function throwIfDocumentCancelled(signal: AbortSignal): void {
  if (signal.aborted) throw new DOMException('Document answer cancelled', 'AbortError');
}

function assertChatAttachmentFile(kind: ChatAttachmentKind, file: File): void {
  const error = validateChatAttachmentFile(kind, file);
  if (error) throw new Error(error);
}

/**
 * Suppress reasoning structurally when the model has a thinking phase and the
 * reader turned it off — the same rule the text chat path applies. The app never
 * injects control tokens to do this.
 */
function reasoningFor(
  supportsThinking: boolean,
  settings: ChatAttachmentGenerationSettings,
): Pick<LlmOptions, 'reasoning'> {
  return supportsThinking && !settings.thinkingModeEnabled
    ? { reasoning: { mode: 'off' } }
    : { reasoning: { mode: 'on', includeInOutput: true } };
}

function visionModelSupportsThinking(): boolean {
  const model = findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_MULTIMODAL)
    ?? findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_VISION);
  return model?.supportsThinking ?? false;
}

/**
 * The two models a grounded answer needs, or `null` where none is ready.
 *
 * Both must already be downloaded: `rag.open` validates availability and throws
 * rather than fetching. The indexing model prefers whatever is already on disk
 * so a reader who downloaded one in Documents is not sent to fetch a second.
 */
function resolveRAGModels(): { embedding: ModelInfo | null; llm: ModelInfo | null } {
  return {
    embedding: firstDownloadedModelForCategory(ModelCategory.MODEL_CATEGORY_EMBEDDING),
    llm: findLoadedModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE)
      ?? firstDownloadedModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE),
  };
}

/** Names whichever half of the document pipeline is missing. */
function documentModelsMissingMessage(): string {
  const models = resolveRAGModels();
  if (!models.embedding && !models.llm) {
    return 'Answering questions about a file needs an indexing model and a chat model on this device. Download both from the model picker, then send the file again.';
  }
  if (!models.embedding) {
    return 'Answering questions about a file needs an indexing model on this device. Download one from the model picker, then send the file again.';
  }
  return 'Answering questions about a file needs a chat model on this device. Download one from the model picker, then send the file again.';
}

function firstDownloadedModelForCategory(category: ModelCategory): ModelInfo | null {
  return RunAnywhere.models.list({ category, downloadedOnly: true })[0] ?? null;
}

function sourceFromMatch(match: Match): ChatAttachmentSource {
  return {
    document: match.metadata.docName || match.metadata.sourceUri || 'Document',
    text: match.text,
  };
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
