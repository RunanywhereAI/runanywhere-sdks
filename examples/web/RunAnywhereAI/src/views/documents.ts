/**
 * Documents Tab — RAG workflow through the public core facade.
 *
 * Mirrors iOS `RAGViewModel` (RAGViewModel.swift:80-115): the user picks an
 * embedding model and an LLM model from the registry, `RunAnywhere.rag.open`
 * returns a session that owns the corpus, and documents are ingested through
 * `session.ingest`. The view owns browser file selection/reading and rendering.
 *
 * Per-document removal is not part of the v3 RAG session surface, so the list
 * reports indexed counts and offers Clear All instead.
 *
 * PDF ingestion is iOS-only for now: iOS extracts text via PDFKit
 * (DocumentService.extractText), a platform framework with no dependency-free
 * web equivalent — .txt/.md/.json are supported here instead.
 *
 * The citations/retrievedChunks display is a deliberate web-ahead addition.
 */

import type { TabLifecycle } from '../app';
import {
  ModelCategory,
  RunAnywhere,
  type Match,
  type ModelInfo,
  type RagSession,
} from '@runanywhere/web';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import { formatFramework } from '../services/model-display';
import { getGenerationSettings } from './settings';

const TOP_K = 3;

let container: HTMLElement;
let isBusy = false;

/** User-selected pipeline models (iOS parity: DocumentRAGView.swift:79-91
 * embedding + LLM model picker rows). */
let selectedEmbeddingModelId = '';
let selectedLlmModelId = '';
/** Live corpus session, and the model pair it was opened with. */
let ragSession: RagSession | null = null;
let openedPipelineKey: string | null = null;
/** Documents ingested in this session, for the list the SDK does not enumerate. */
const ingestedDocuments: Array<{ name: string; chunkCount: number }> = [];

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export function initDocumentsTab(el: HTMLElement): TabLifecycle {
  container = el;
  // Register the model catalog so the SDK's model registry has entries for
  // the embedding and LLM models used by RAG. Other tabs trigger this
  // implicitly via their toolbar pickers; Docs has its own UI.
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Documents</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Pipeline models</h3>
        <p class="text-secondary">Choose an embedding model and an LLM model from the registry; the RAG pipeline is created with this pair.</p>
        <div class="docs-actions" style="display:flex; gap:12px; flex-wrap:wrap; align-items:flex-end;">
          <label style="display:flex; flex-direction:column; gap:4px; font-size:0.8rem;">
            Embedding model
            <select id="docs-embedding-model" class="chat-input" style="min-width:220px"></select>
          </label>
          <button class="btn btn-secondary" id="docs-embedding-download-btn">Download</button>
          <label style="display:flex; flex-direction:column; gap:4px; font-size:0.8rem;">
            LLM model
            <select id="docs-llm-model" class="chat-input" style="min-width:220px"></select>
          </label>
          <button class="btn btn-secondary" id="docs-llm-download-btn">Download</button>
        </div>
        <div id="docs-model-status" class="docs-status"></div>
      </div>
      <div class="docs-section">
        <h3>Indexed documents</h3>
        <p class="text-secondary">Upload <code>.txt</code>, <code>.md</code>, or <code>.json</code> files to index through the core RAG facade.
        A native RAG provider or WASM RAG session is required. The current Web
        RAG index is session-only and is not restored after a page reload.</p>
        <div class="docs-actions">
          <input type="file" id="docs-file" accept=".txt,.md,.json" multiple style="display:none" />
          <button class="btn btn-primary" id="docs-upload-btn">Upload</button>
          <button class="btn btn-secondary" id="docs-clear-btn">Clear all</button>
        </div>
        <ul class="docs-list" id="docs-list"></ul>
        <div id="docs-status" class="docs-status"></div>
      </div>
      <div class="docs-section">
        <h3>Ask a question</h3>
        <p class="text-secondary">Queries the core RAG facade for retrieval and grounded answer generation.</p>
        <textarea id="docs-query" class="docs-query" placeholder="Ask something about your uploaded docs..." rows="3"></textarea>
        <button class="btn btn-primary" id="docs-ask-btn">Ask</button>
        <div id="docs-answer" class="docs-answer"></div>
      </div>
    </div>
  `;

  populateModelPickers();
  void renderDocList();

  container.querySelector('#docs-upload-btn')!.addEventListener('click', () => {
    (container.querySelector('#docs-file') as HTMLInputElement).click();
  });
  container.querySelector('#docs-file')!.addEventListener('change', (event) => {
    void onFilePicked(event);
  });
  container.querySelector('#docs-clear-btn')!.addEventListener('click', () => {
    void clearAllDocs();
  });
  container.querySelector('#docs-ask-btn')!.addEventListener('click', () => {
    void askQuestion();
  });
  container.querySelector('#docs-embedding-download-btn')!.addEventListener('click', () => {
    void downloadSelectedModel(selectedEmbeddingModelId, 'embedding');
  });
  container.querySelector('#docs-llm-download-btn')!.addEventListener('click', () => {
    void downloadSelectedModel(selectedLlmModelId, 'LLM');
  });
  refreshModelButtons();

  return {
    onActivate: () => {
      refreshModelButtons();
      void renderDocList();
    },
    // Settings can reinitialize every backend while this view stays mounted;
    // the session holds the process-wide RAG index, so release it on exit.
    onDeactivate: () => {
      void closeRAGSession();
    },
  };
}

// ---------------------------------------------------------------------------
// Model download
// ---------------------------------------------------------------------------

function setModelStatus(msg: string): void {
  const el = container.querySelector<HTMLElement>('#docs-model-status');
  if (el) el.textContent = msg;
}

/** Reflect downloaded state on the two download buttons. */
function refreshModelButtons(): void {
  const pairs: Array<['embedding' | 'llm', string]> = [
    ['embedding', selectedEmbeddingModelId],
    ['llm', selectedLlmModelId],
  ];
  for (const [kind, modelId] of pairs) {
    const btn = container.querySelector<HTMLButtonElement>(`#docs-${kind}-download-btn`);
    if (!btn) continue;
    const downloaded = modelId
      ? RunAnywhere.models.list({ downloadedOnly: true }).some((model) => model.id === modelId)
      : false;
    btn.disabled = isBusy || !modelId || downloaded;
    btn.textContent = downloaded ? 'Downloaded' : 'Download';
  }
}

async function downloadSelectedModel(
  modelId: string,
  label: string,
): Promise<void> {
  if (!modelId) {
    setModelStatus(`Select a ${label} model first.`);
    return;
  }
  const model = RunAnywhere.models.get(modelId);
  if (!model) {
    setModelStatus(`${label} model '${modelId}' is not registered.`);
    return;
  }
  isBusy = true;
  refreshModelButtons();
  setModelStatus(`Downloading ${label} model ${model.name || modelId}…`);
  try {
    for await (const event of RunAnywhere.models.download(modelId)) {
      if (event.type === 'progress') {
        const percent = event.bytesTotal > 0 ? (event.bytesDone / event.bytesTotal) * 100 : 0;
        setModelStatus(`Downloading ${label} model… ${Math.round(percent)}%`);
      } else if (event.type === 'extracting') {
        setModelStatus(`Extracting ${label} model…`);
      }
    }
    setModelStatus(`${label} model ready: ${model.name || modelId}.`);
  } catch (err) {
    setModelStatus(`${label} model download failed: ${formatError(err)}`);
  } finally {
    isBusy = false;
    refreshModelButtons();
  }
}

// ---------------------------------------------------------------------------
// Model pickers
// ---------------------------------------------------------------------------

function registryModelsForCategory(category: ModelCategory): ModelInfo[] {
  return RunAnywhere.models.list({ category });
}

function populateModelPickers(): void {
  const embeddingSelect = container.querySelector<HTMLSelectElement>('#docs-embedding-model')!;
  const llmSelect = container.querySelector<HTMLSelectElement>('#docs-llm-model')!;

  const embeddingModels = registryModelsForCategory(ModelCategory.MODEL_CATEGORY_EMBEDDING);
  const llmModels = registryModelsForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);

  fillSelect(embeddingSelect, embeddingModels, 'No embedding models registered');
  fillSelect(llmSelect, llmModels, 'No LLM models registered');

  selectedEmbeddingModelId = embeddingSelect.value;
  selectedLlmModelId = llmSelect.value;

  embeddingSelect.addEventListener('change', () => {
    selectedEmbeddingModelId = embeddingSelect.value;
    refreshModelButtons();
  });
  llmSelect.addEventListener('change', () => {
    selectedLlmModelId = llmSelect.value;
    refreshModelButtons();
  });
}

function fillSelect(select: HTMLSelectElement, models: ModelInfo[], emptyLabel: string): void {
  if (models.length === 0) {
    select.innerHTML = `<option value="">${escapeHtml(emptyLabel)}</option>`;
    select.disabled = true;
    return;
  }
  select.disabled = false;
  select.innerHTML = models
    .map((model) => {
      const label = `${model.name || model.id} · ${formatFramework(model.framework)}`;
      return `<option value="${escapeHtml(model.id)}">${escapeHtml(label)}</option>`;
    })
    .join('');
}

function selectedLlmSupportsThinking(): boolean {
  return registryModelsForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE)
    .some((model) => model.id === selectedLlmModelId && model.supportsThinking);
}

// ---------------------------------------------------------------------------
// File ingestion
// ---------------------------------------------------------------------------

async function onFilePicked(e: Event): Promise<void> {
  const target = e.target as HTMLInputElement;
  if (!target.files || target.files.length === 0) return;
  if (isBusy) return;

  isBusy = true;
  try {
    const session = await ensureRAGSession();
    if (!session) return;
    for (const file of Array.from(target.files)) {
      await ingestFile(session, file);
    }
    await renderDocList();
  } catch (err) {
    setStatus(`Indexing failed: ${formatError(err)}`);
  } finally {
    isBusy = false;
    target.value = '';
  }
}

async function ingestFile(session: RagSession, file: File): Promise<void> {
  setStatus(`Reading ${file.name}...`);
  // .txt/.md/.json are all read as plain text and ingested as-is — same as
  // iOS, where JSON documents flow through text extraction before ingest
  // (DocumentRAGView.swift:50 allows [.pdf, .json]).
  const before = await session.stats();

  setStatus(`Indexing ${file.name}...`);
  await session.ingest({
    text: await file.text(),
    name: file.name,
    metadata: {
      docId: createDocumentId(),
      sourceUri: `web-file:${file.name}`,
      mediaType: file.type || 'text/plain',
      sizeBytes: String(file.size),
    },
  });

  const stats = await session.stats();
  ingestedDocuments.push({
    name: file.name,
    chunkCount: Math.max(0, stats.chunkCount - before.chunkCount),
  });
  setStatus(`Indexed ${file.name}. ${stats.chunkCount} chunks total.`);
}

async function clearAllDocs(): Promise<void> {
  if (isBusy) return;
  isBusy = true;
  try {
    const session = await ensureRAGSession();
    if (!session) return;
    await session.clear();
    ingestedDocuments.length = 0;
    await renderDocList();
    setStatus('All documents cleared.');
  } catch (err) {
    setStatus(`Clear failed: ${formatError(err)}`);
  } finally {
    isBusy = false;
  }
}

// ---------------------------------------------------------------------------
// Query
// ---------------------------------------------------------------------------

async function askQuestion(): Promise<void> {
  if (isBusy) return;
  const queryEl = container.querySelector('#docs-query') as HTMLTextAreaElement;
  const question = queryEl.value.trim();
  if (!question) return;

  isBusy = true;
  setAnswerText('Searching...');
  try {
    const session = await ensureRAGSession();
    if (!session) {
      setAnswerText('Select an embedding model and an LLM model first.');
      return;
    }
    if ((await session.stats()).documentCount === 0) {
      setAnswerText('Upload a document first.');
      return;
    }

    const suppressThinking = selectedLlmSupportsThinking()
      && !getGenerationSettings().thinkingModeEnabled;
    const result = await session.query(question, {
      generation: {
        maxOutputTokens: 512,
        temperature: 0.4,
        reasoning: suppressThinking ? { mode: 'off' } : { mode: 'on', includeInOutput: true },
      },
    });

    if (result.sources.length === 0) {
      setAnswerText('No relevant chunks found.');
      return;
    }
    setAnswerHtml(formatAnswer(result.answer, result.sources));
  } catch (err) {
    setAnswerText(`Failed: ${formatError(err)}`);
  } finally {
    isBusy = false;
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

async function renderDocList(): Promise<void> {
  const listEl = container.querySelector('#docs-list')!;
  if (!ragSession) {
    listEl.innerHTML = '<li class="docs-empty">No documents indexed yet</li>';
    return;
  }

  let chunkCount = 0;
  try {
    chunkCount = (await ragSession.stats()).chunkCount;
  } catch (err) {
    listEl.innerHTML = '<li class="docs-empty">No documents indexed yet</li>';
    setStatus(`Unable to read index stats: ${formatError(err)}`);
    return;
  }

  if (ingestedDocuments.length === 0) {
    listEl.innerHTML = chunkCount === 0
      ? '<li class="docs-empty">No documents indexed yet</li>'
      : `<li class="docs-empty">${chunkCount} chunks indexed</li>`;
    return;
  }

  listEl.innerHTML = '';
  for (const doc of ingestedDocuments) {
    const li = document.createElement('li');
    li.className = 'docs-item';

    const infoDiv = document.createElement('div');
    const titleDiv = document.createElement('div');
    titleDiv.className = 'docs-item-title';
    titleDiv.textContent = doc.name;
    const metaDiv = document.createElement('div');
    metaDiv.className = 'docs-item-meta';
    metaDiv.textContent = `${doc.chunkCount} chunk${doc.chunkCount === 1 ? '' : 's'}`;
    infoDiv.appendChild(titleDiv);
    infoDiv.appendChild(metaDiv);
    li.appendChild(infoDiv);

    listEl.appendChild(li);
  }
}

function setStatus(msg: string): void {
  const el = container.querySelector('#docs-status');
  if (el) el.textContent = msg;
}

function answerElement(): HTMLElement | null {
  return container.querySelector<HTMLElement>('#docs-answer');
}

function setAnswerText(message: string): void {
  const el = answerElement();
  if (el) el.textContent = message;
}

/** Accepts only markup assembled by formatAnswer(), which escapes every value. */
function setAnswerHtml(html: string): void {
  const el = answerElement();
  if (el) el.innerHTML = html;
}

/**
 * Open (or reuse) the corpus session for the selected model pair. `rag.open`
 * loads and downloads both models itself, so nothing is pre-staged here.
 */
async function ensureRAGSession(): Promise<RagSession | null> {
  if (!selectedEmbeddingModelId || !selectedLlmModelId) {
    setStatus('Select an embedding model and an LLM model first.');
    return null;
  }
  const key = `${selectedEmbeddingModelId}|${selectedLlmModelId}`;
  if (ragSession && openedPipelineKey === key) return ragSession;

  await closeRAGSession();
  try {
    setStatus('Opening RAG session...');
    ragSession = await RunAnywhere.rag.open(
      { id: selectedEmbeddingModelId },
      { id: selectedLlmModelId },
      { topK: TOP_K },
    );
    openedPipelineKey = key;
    setStatus('RAG session ready.');
    return ragSession;
  } catch (err) {
    await closeRAGSession();
    setStatus(`RAG init failed: ${formatError(err)}`);
    return null;
  }
}

async function closeRAGSession(): Promise<void> {
  const previous = ragSession;
  ragSession = null;
  openedPipelineKey = null;
  ingestedDocuments.length = 0;
  await previous?.close().catch(() => undefined);
}

/**
 * Split built-in thinking tags out of the answer into a collapsible
 * section (iOS parity: RAGViewModel.swift:145-149 thinkingContent +
 * DocumentRAGView.swift:473-543 thinkingSection).
 */
function splitThinking(text: string): { answer: string; thinking: string | null } {
  const match = /<(think|thinking)>([\s\S]*?)<\/\1>/i.exec(text);
  if (!match) {
    // Tolerate an unterminated opening tag (model cut off mid-thought).
    const open = /<(think|thinking)>([\s\S]*)$/i.exec(text);
    if (open) {
      return { answer: text.slice(0, open.index).trim(), thinking: open[2].trim() || null };
    }
    return { answer: text, thinking: null };
  }
  const thinking = match[2].trim();
  const answer = (text.slice(0, match.index) + text.slice(match.index + match[0].length)).trim();
  return { answer, thinking: thinking || null };
}

function formatAnswer(text: string, sources: Match[]): string {
  const split = splitThinking(text);
  const thinking = split.thinking;
  const thinkingHtml = thinking
    ? `<details class="docs-thinking" style="margin-bottom:8px;">
        <summary style="cursor:pointer; font-size:0.8rem; opacity:0.7;">Reasoning</summary>
        <pre style="white-space:pre-wrap; font-size:0.8rem; opacity:0.8;">${escapeHtml(thinking)}</pre>
      </details>`
    : '';
  const sourcesHtml = sources.map((source, i) => `
    <div class="docs-source">
      <strong>Source ${i + 1}: ${escapeHtml(source.metadata.docName ?? 'Document')}</strong>
      <pre>${escapeHtml(source.text.slice(0, 400))}${source.text.length > 400 ? '...' : ''}</pre>
    </div>
  `).join('');
  return `${thinkingHtml}<div class="docs-answer-text">${escapeHtml(split.answer)}</div><div class="docs-sources">${sourcesHtml}</div>`;
}

function createDocumentId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return Math.random().toString(36).slice(2);
}
