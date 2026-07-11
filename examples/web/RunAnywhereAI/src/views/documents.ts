/**
 * Documents Tab — RAG workflow through the public core facade.
 *
 * Mirrors iOS `RAGViewModel` (RAGViewModel.swift:80-115): the user picks an
 * embedding model and an LLM model from the registry, the pipeline is
 * created via `RunAnywhere.ragCreatePipeline(embeddingModelId, llmModelId)`,
 * and documents are ingested through `ragIngest`. The view owns browser
 * file selection/reading and rendering only.
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
  ragQueryOptionsWithQuestion,
  type ModelInfo,
  type RAGDocumentSummary,
  type RAGSearchResult,
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
/** Model-id pair the current native pipeline was created with. */
let createdPipelineKey: string | null = null;

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
        A native RAG provider or WASM RAG session is required.</p>
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

  return {};
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
    const model = modelId ? RunAnywhere.getModel(modelId) : null;
    const downloaded = !!(model?.isDownloaded || model?.localPath);
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
  const model = RunAnywhere.getModel(modelId);
  if (!model) {
    setModelStatus(`${label} model '${modelId}' is not registered.`);
    return;
  }
  isBusy = true;
  refreshModelButtons();
  setModelStatus(`Downloading ${label} model ${model.name || modelId}…`);
  try {
    await RunAnywhere.downloadModel({
      modelId,
      model,
      allowMeteredNetwork: true,
      resumeExisting: true,
      verifyChecksums: false,
      validateExistingBytes: false,
      updateRegistryOnCompletion: true,
      storageNamespace: '',
      availableStorageBytes: 0,
      requiredFreeBytesAfterDownload: 0,
      pollIntervalMs: 500,
      onProgress: (next) => {
        const pct = next.totalBytes > 0
          ? Math.round((Number(next.bytesDownloaded) / Number(next.totalBytes)) * 100)
          : 0;
        setModelStatus(`Downloading ${label} model… ${pct}%`);
      },
    });
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
  try {
    const list = RunAnywhere.listModels();
    return (list?.models ?? []).filter((model) => model.category === category);
  } catch {
    return [];
  }
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
  if (!(await ensureRAGReady())) {
    target.value = '';
    return;
  }

  isBusy = true;
  try {
    for (const file of Array.from(target.files)) {
      await ingestFile(file);
    }
    await renderDocList();
  } catch (err) {
    setStatus(`Indexing failed: ${formatError(err)}`);
  } finally {
    isBusy = false;
    target.value = '';
  }
}

async function ingestFile(file: File): Promise<void> {
  setStatus(`Reading ${file.name}...`);
  // .txt/.md/.json are all read as plain text and ingested as-is — same as
  // iOS, where JSON documents flow through text extraction before ragIngest
  // (DocumentRAGView.swift:50 allows [.pdf, .json]).
  const text = await file.text();
  const docId = createDocumentId();

  setStatus(`Indexing ${file.name}...`);
  await RunAnywhere.ragIngest(text, JSON.stringify({
    docId,
    docName: file.name,
    sourceUri: `web-file:${file.name}`,
    mediaType: file.type || 'text/plain',
    sizeBytes: String(file.size),
  }));

  const stats = await RunAnywhere.ragGetStatistics();
  setStatus(`Indexed ${file.name}. ${stats.indexedChunks} chunks total.`);
}

async function clearAllDocs(): Promise<void> {
  if (isBusy) return;
  if (!(await ensureRAGReady())) return;
  isBusy = true;
  try {
    await RunAnywhere.ragClearDocuments();
    await renderDocList();
    setStatus('All documents cleared.');
  } catch (err) {
    setStatus(`Clear failed: ${formatError(err)}`);
  } finally {
    isBusy = false;
  }
}

async function removeDocument(id: string): Promise<void> {
  if (isBusy) return;
  if (!(await ensureRAGReady())) return;
  isBusy = true;
  try {
    await RunAnywhere.rag.removeDocument(id);
    await renderDocList();
    setStatus('Document removed.');
  } catch (err) {
    setStatus(`Remove failed: ${formatError(err)}`);
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
  if (!(await ensureRAGReady())) return;

  let documentCount = 0;
  try {
    documentCount = await RunAnywhere.ragGetDocumentCount();
  } catch (err) {
    setAnswerText(`Failed: ${formatError(err)}`);
    return;
  }
  if (documentCount === 0) {
    setAnswerText('Upload a document first.');
    return;
  }

  isBusy = true;
  setAnswerText('Searching...');
  try {
    // Full-options overload (Swift parity: `ragQuery(_ options:)` with
    // RARAGQueryOptions.defaults(question:) — RAGViewModel.swift:137-144).
    const result = await RunAnywhere.ragQuery({
      ...ragQueryOptionsWithQuestion(question),
      retrievalTopK: TOP_K,
      maxTokens: 512,
      temperature: 0.4,
      disableThinking: selectedLlmSupportsThinking() && !getGenerationSettings().thinkingModeEnabled,
    });

    if (result.errorCode !== 0) {
      setAnswerText(`Failed: ${result.errorMessage ?? 'RAG query failed'}`);
      return;
    }

    if (result.retrievedChunks.length === 0) {
      setAnswerText('No relevant chunks found.');
      return;
    }

    setAnswerHtml(formatAnswer(result.answer, result.retrievedChunks, result.thinkingContent));
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
  const availability = RunAnywhere.rag.availability();
  if (!availability.available) {
    listEl.innerHTML = '<li class="docs-empty">No documents indexed yet</li>';
    setStatus(availability.reason);
    return;
  }

  let documents: RAGDocumentSummary[];
  try {
    if (!RunAnywhere.rag.capabilities().documentListing) {
      const stats = await RunAnywhere.ragGetStatistics();
      listEl.innerHTML = stats.indexedDocuments === 0
        ? '<li class="docs-empty">No documents indexed yet</li>'
        : `<li class="docs-empty">${stats.indexedDocuments} document${stats.indexedDocuments === 1 ? '' : 's'} indexed. Document listing is not exposed by this RAG provider.</li>`;
      if (stats.errorMessage) {
        setStatus(stats.errorMessage);
      }
      return;
    }
    documents = await RunAnywhere.rag.listDocuments();
  } catch (err) {
    listEl.innerHTML = '<li class="docs-empty">No documents indexed yet</li>';
    setStatus(`Unable to list documents: ${formatError(err)}`);
    return;
  }

  if (documents.length === 0) {
    listEl.innerHTML = '<li class="docs-empty">No documents indexed yet</li>';
    return;
  }

  const canRemoveDocuments = RunAnywhere.rag.capabilities().documentRemoval;
  listEl.innerHTML = '';
  for (const doc of documents) {
    const li = document.createElement('li');
    li.className = 'docs-item';
    li.dataset.id = doc.id;

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

    if (canRemoveDocuments) {
      const btn = document.createElement('button');
      btn.className = 'btn btn-icon docs-item-delete';
      btn.setAttribute('aria-label', 'Remove');
      btn.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" width="16" height="16"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-2 14a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2L5 6"/></svg>';
      btn.addEventListener('click', () => { void removeDocument(doc.id); });
      li.appendChild(btn);
    }

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
 * Create the RAG pipeline for the user-selected model pair (iOS parity:
 * RAGViewModel.swift:100-103 `ragCreatePipeline(embeddingModel:llmModel:)`).
 * Recreates the native session whenever the selection changes.
 */
async function ensureRAGReady(): Promise<boolean> {
  if (!selectedEmbeddingModelId || !selectedLlmModelId) {
    setStatus('Select an embedding model and an LLM model first.');
    return false;
  }
  const key = `${selectedEmbeddingModelId}|${selectedLlmModelId}`;
  if (createdPipelineKey === key) return true;
  try {
    setStatus('Creating RAG pipeline...');
    await RunAnywhere.ragCreatePipeline(selectedEmbeddingModelId, selectedLlmModelId);
    createdPipelineKey = key;
    setStatus('RAG pipeline ready.');
    return true;
  } catch (err) {
    createdPipelineKey = null;
    setStatus(`RAG init failed: ${formatError(err)}`);
    return false;
  }
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

function formatAnswer(
  text: string,
  sources: RAGSearchResult[],
  thinkingContent?: string,
): string {
  const split = splitThinking(text);
  const thinking = thinkingContent?.trim() || split.thinking;
  const thinkingHtml = thinking
    ? `<details class="docs-thinking" style="margin-bottom:8px;">
        <summary style="cursor:pointer; font-size:0.8rem; opacity:0.7;">Reasoning</summary>
        <pre style="white-space:pre-wrap; font-size:0.8rem; opacity:0.8;">${escapeHtml(thinking)}</pre>
      </details>`
    : '';
  const sourcesHtml = sources.map((source, i) => `
    <div class="docs-source">
      <strong>Source ${i + 1}: ${escapeHtml(source.sourceDocument ?? 'Document')}</strong>
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
