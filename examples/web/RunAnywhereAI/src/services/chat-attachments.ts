import {
  ModelCategory,
  RunAnywhere,
  VLMModelFamily,
  VLMStreamEventKind,
  ragQueryOptionsWithQuestion,
  type ModelInfo,
  type RAGSearchResult,
  type VLMGenerationOptions,
  vlmImageFromRawRGB,
} from '@runanywhere/web';

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

export function validateChatAttachmentFile(kind: ChatAttachmentKind, file: File): string | null {
  const limit = kind === 'image' ? MAX_IMAGE_ATTACHMENT_BYTES : MAX_DOCUMENT_ATTACHMENT_BYTES;
  if (file.size <= limit) return null;
  return `${kind === 'image' ? 'Images' : 'Documents'} must be ${formatBytes(limit)} or smaller.`;
}

export function canAnswerImageAttachment(): boolean {
  try {
    const categories = [
      ModelCategory.MODEL_CATEGORY_MULTIMODAL,
      ModelCategory.MODEL_CATEGORY_VISION,
    ];
    return categories.some((category) => {
      const current = RunAnywhere.currentModel({
        category,
        includeModelMetadata: false,
      });
      return Boolean(current?.found || current?.modelId);
    });
  } catch {
    return false;
  }
}

export function cancelActiveImageAttachmentAnswer(): void {
  void RunAnywhere.visionLanguage.cancelVLMGeneration();
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
  const image = vlmImageFromRawRGB(frame.rgbPixels, frame.width, frame.height);
  const options: VLMGenerationOptions = {
    prompt,
    maxTokens: 256,
    temperature: settings.temperature,
    topP: 0.9,
    topK: 40,
    stopSequences: [],
    streamingEnabled: true,
    systemPrompt: undefined,
    maxImageSize: CAPTURE_DIMENSION,
    nThreads: 0,
    useGpu: false,
    modelFamily: VLMModelFamily.VLM_MODEL_FAMILY_UNSPECIFIED,
    customChatTemplate: undefined,
    imageMarkerOverride: undefined,
    seed: 0,
    repetitionPenalty: 1.1,
    minP: 0.05,
    emitImageEmbeddings: false,
  };

  let content = '';
  onProgress({ content });
  const stream = await RunAnywhere.visionLanguage.processImageStream(image, options);
  for await (const event of stream) {
    switch (event.kind) {
      case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN:
        if (event.token) {
          content += event.token;
          onProgress({ content });
        }
        break;
      case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_ERROR:
        throw new Error(event.errorMessage || 'Image analysis failed');
      default:
        break;
    }
  }

  return { content: content || '(empty response)' };
}

export async function answerDocumentAttachment(
  file: File,
  question: string,
  settings: ChatAttachmentGenerationSettings,
  onProgress: (progress: ChatAttachmentProgress) => void,
): Promise<ChatAttachmentAnswer> {
  assertChatAttachmentFileSize('document', file);
  const models = resolveRAGModels();
  if (!models.embedding || !models.llm) {
    throw new Error('Document Q&A needs an embedding model and a chat model in the catalog.');
  }

  onProgress({ content: 'Indexing document...' });
  const text = await file.text();
  if (!text.trim()) {
    throw new Error('The selected document does not contain readable text.');
  }

  await RunAnywhere.ragCreatePipeline(models.embedding.id, models.llm.id);
  await RunAnywhere.ragIngest(text, JSON.stringify({
    docId: createDocumentId(),
    docName: file.name || 'Document',
    sourceUri: `web-file:${file.name || 'document'}`,
    mediaType: file.type || 'text/plain',
    sizeBytes: String(file.size),
  }));

  onProgress({ content: 'Searching document...' });

  const result = await RunAnywhere.ragQuery({
    ...ragQueryOptionsWithQuestion(question),
    retrievalTopK: DOCUMENT_TOP_K,
    maxTokens: Math.min(settings.maxTokens, 1024),
    temperature: settings.temperature,
    disableThinking: models.llm.supportsThinking && !settings.thinkingModeEnabled,
  });

  if (result.errorCode !== 0) {
    throw new Error(result.errorMessage || 'Document query failed');
  }

  const split = splitThinking(result.answer);
  return {
    content: split.content || result.answer || '(no answer)',
    thinking: result.thinkingContent || split.thinking || undefined,
    sources: result.retrievedChunks.map(sourceFromRAGResult),
  };
}

function assertChatAttachmentFileSize(kind: ChatAttachmentKind, file: File): void {
  const error = validateChatAttachmentFile(kind, file);
  if (error) throw new Error(error);
}

function resolveRAGModels(): { embedding: ModelInfo | null; llm: ModelInfo | null } {
  const embedding = firstModelForCategory(ModelCategory.MODEL_CATEGORY_EMBEDDING);
  const currentLlmId = currentModelIdForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);
  const llm = currentLlmId
    ? (RunAnywhere.getModel(currentLlmId) ?? null)
    : firstModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);
  return { embedding, llm };
}

function firstModelForCategory(category: ModelCategory): ModelInfo | null {
  try {
    return RunAnywhere.listModels()?.models.find((model) => model.category === category) ?? null;
  } catch {
    return null;
  }
}

function currentModelIdForCategory(category: ModelCategory): string | null {
  try {
    const current = RunAnywhere.currentModel({
      category,
      includeModelMetadata: false,
    });
    return current?.modelId || null;
  } catch {
    return null;
  }
}

function sourceFromRAGResult(result: RAGSearchResult): ChatAttachmentSource {
  return {
    document: result.sourceDocument || 'Document',
    text: result.text,
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
