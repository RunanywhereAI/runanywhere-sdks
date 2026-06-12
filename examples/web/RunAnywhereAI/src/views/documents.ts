/**
 * Documents Tab — RAG workflow through the public core facade.
 *
 * The view owns browser file selection/reading and rendering. Core RAG owns
 * session creation, ingestion, retrieval, and answer generation.
 */

import type { TabLifecycle } from '../app';
import {
  RunAnywhere,
  type RAGDocumentSummary,
  type RAGSearchResult,
} from '@runanywhere/web';
import { ensureCatalogRegistered } from '../components/model-selection';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';

const TOP_K = 3;

let container: HTMLElement;
let isBusy = false;

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export function initDocumentsTab(el: HTMLElement): TabLifecycle {
  container = el;
  // Register the model catalog so the SDK's model registry has entries for
  // the embedding and LLM models used by RAG. Other tabs trigger this
  // implicitly via their toolbar pickers; Docs has its own UI.
  ensureCatalogRegistered();
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Documents</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Indexed documents</h3>
        <p class="text-secondary">Upload <code>.txt</code> or <code>.md</code> files to index through the core RAG facade.
        A native RAG provider or WASM RAG session is required.</p>
        <div class="docs-actions">
          <input type="file" id="docs-file" accept=".txt,.md" multiple style="display:none" />
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

  return {};
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
    setAnswer(`Failed: ${formatError(err)}`);
    return;
  }
  if (documentCount === 0) {
    setAnswer('Upload a document first.');
    return;
  }

  isBusy = true;
  setAnswer('Searching...');
  try {
    const result = await RunAnywhere.ragQuery(question, {
      retrievalTopK: TOP_K,
      maxTokens: 512,
      temperature: 0.4,
    });

    if (result.errorCode !== 0) {
      setAnswer(`Failed: ${result.errorMessage ?? 'RAG query failed'}`);
      return;
    }

    if (result.retrievedChunks.length === 0) {
      setAnswer('No relevant chunks found.');
      return;
    }

    setAnswer(formatAnswer(result.answer, result.retrievedChunks));
  } catch (err) {
    setAnswer(`Failed: ${formatError(err)}`);
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

function setAnswer(msg: string): void {
  const el = container.querySelector('#docs-answer') as HTMLElement;
  el.innerHTML = msg;
}

const RAG_EMBEDDING_MODEL_ID = 'all-minilm-l6-v2';
const RAG_LLM_MODEL_ID = 'smollm2-360m-q8_0';

async function ensureRAGReady(): Promise<boolean> {
  try {
    const availability = await RunAnywhere.rag.ensureReady({
      embeddingModelId: RAG_EMBEDDING_MODEL_ID,
      llmModelId: RAG_LLM_MODEL_ID,
    });
    if (!availability.available) {
      setStatus(availability.reason);
      return false;
    }
    return true;
  } catch (err) {
    setStatus(`RAG init failed: ${formatError(err)}`);
    return false;
  }
}

function formatAnswer(text: string, sources: RAGSearchResult[]): string {
  const sourcesHtml = sources.map((source, i) => `
    <div class="docs-source">
      <strong>Source ${i + 1}: ${escapeHtml(source.sourceDocument ?? 'Document')}</strong>
      <pre>${escapeHtml(source.text.slice(0, 400))}${source.text.length > 400 ? '...' : ''}</pre>
    </div>
  `).join('');
  return `<div class="docs-answer-text">${escapeHtml(text)}</div><div class="docs-sources">${sourcesHtml}</div>`;
}

function createDocumentId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return Math.random().toString(36).slice(2);
}
