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

/**
 * What this view can ingest.
 *
 * Named once and used for three things that must agree: the file input's
 * `accept`, the hint that tells the user what to drop, and the validation that
 * rejects a dropped file — because a drop bypasses `accept` entirely, so
 * without the check an unsupported binary would be read as text and indexed as
 * mojibake.
 */
const ACCEPTED_EXTENSIONS = ['.txt', '.md', '.json'] as const;

/**
 * Why a corpus session could not be opened.
 *
 * A plain `null` return conflated "the user has not chosen models" with
 * "`rag.open` threw", so the caller had to guess — and the guess it made was
 * printed as fact next to the real error, telling the user to select models that
 * were visibly already selected. The reason travels with the failure now.
 */
type SessionOutcome =
  | { ok: true; session: RagSession }
  | { ok: false; reason: 'models-not-selected' | 'open-failed'; message: string };

let container: HTMLElement;
let isBusy = false;
/** Numbers the pasted snippets, which arrive without a filename of their own. */
let pastedNoteCount = 0;

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
        <p class="text-secondary">Answers are grounded in the files you index here.
        The index lives in this tab only — it is cleared when you reload the page.</p>
        <!-- A real drop zone, not a hidden input behind a button. It is a
             <button> so the keyboard path is the same control as the pointer
             path, rather than a separate affordance to discover. -->
        <input type="file" id="docs-file" accept="${ACCEPTED_EXTENSIONS.join(',')}" multiple hidden />
        <button type="button" class="docs-dropzone" id="docs-dropzone"
          aria-describedby="docs-dropzone-hint">
          <svg class="docs-dropzone-glyph" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"
            fill="none" stroke="currentColor" stroke-width="1.5" aria-hidden="true">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
            <polyline points="17 8 12 3 7 8"/>
            <line x1="12" y1="3" x2="12" y2="15"/>
          </svg>
          <span class="docs-dropzone-title">Drop files here, or click to choose</span>
          <span class="docs-dropzone-hint" id="docs-dropzone-hint">
            ${ACCEPTED_EXTENSIONS.join(', ')} — or paste text straight onto this page
          </span>
        </button>
        <div class="docs-actions">
          <button class="btn btn-secondary" id="docs-clear-btn">Clear all</button>
        </div>
        <ul class="docs-list" id="docs-list"></ul>
        <div id="docs-status" class="docs-status" role="status" aria-live="polite"></div>
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

  container.querySelector('#docs-file')!.addEventListener('change', (event) => {
    void onFilePicked(event);
  });
  setupDropZone();
  setupPasteToIndex();
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
      // Re-arm: init runs once, but every deactivate detaches the paste listener.
      if (!detachPaste) setupPasteToIndex();
      refreshModelButtons();
      void renderDocList();
    },
    // Settings can reinitialize every backend while this view stays mounted;
    // the session holds the process-wide RAG index, so release it on exit.
    onDeactivate: () => {
      // The paste listener is on `document`, so leaving the tab has to detach it
      // — otherwise pasting in Chat would quietly index the clipboard here.
      detachPaste?.();
      detachPaste = null;
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
// Drop zone & paste
// ---------------------------------------------------------------------------

/**
 * Wire the drop zone.
 *
 * `dragover` must be cancelled on both the zone and the surrounding section, or
 * the browser navigates away to the dropped file — the default that makes naive
 * drop handling look broken. The highlight uses a counter because `dragleave`
 * fires when the pointer crosses onto a *child* element, which would otherwise
 * flicker the state off while the pointer is still inside the zone.
 */
function setupDropZone(): void {
  const zone = container.querySelector<HTMLElement>('#docs-dropzone');
  const input = container.querySelector<HTMLInputElement>('#docs-file');
  if (!zone || !input) return;

  zone.addEventListener('click', () => input.click());

  let depth = 0;
  const setActive = (active: boolean): void => {
    zone.classList.toggle('docs-dropzone--active', active);
  };

  zone.addEventListener('dragenter', (event) => {
    event.preventDefault();
    depth += 1;
    setActive(true);
  });
  zone.addEventListener('dragover', (event) => {
    event.preventDefault();
    if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy';
  });
  zone.addEventListener('dragleave', () => {
    depth = Math.max(0, depth - 1);
    if (depth === 0) setActive(false);
  });
  zone.addEventListener('drop', (event) => {
    event.preventDefault();
    depth = 0;
    setActive(false);
    const files = Array.from(event.dataTransfer?.files ?? []);
    void ingestFiles(files);
  });

  // Dropping just outside the zone is a miss, not a request to leave the app.
  const section = zone.closest('.docs-section');
  section?.addEventListener('dragover', (event) => event.preventDefault());
  section?.addEventListener('drop', (event) => event.preventDefault());
}

/** Removes the document-level paste listener when the tab is left. */
let detachPaste: (() => void) | null = null;

/**
 * Paste text anywhere on the page to index it.
 *
 * Scoped away from the question box and any other field: pasting a passage in
 * order to *ask about it* must not also index it, and pasting into an input is
 * unambiguously editing that input.
 */
function setupPasteToIndex(): void {
  const onPaste = (event: ClipboardEvent): void => {
    const target = event.target;
    if (target instanceof HTMLElement
      && (target.isContentEditable
        || target instanceof HTMLInputElement
        || target instanceof HTMLTextAreaElement)) {
      return;
    }
    const files = Array.from(event.clipboardData?.files ?? []);
    if (files.length > 0) {
      event.preventDefault();
      void ingestFiles(files);
      return;
    }
    const text = event.clipboardData?.getData('text/plain')?.trim();
    if (!text) return;
    event.preventDefault();
    void ingestPastedText(text);
  };
  document.addEventListener('paste', onPaste);
  detachPaste = () => document.removeEventListener('paste', onPaste);
}

// ---------------------------------------------------------------------------
// File ingestion
// ---------------------------------------------------------------------------

async function onFilePicked(e: Event): Promise<void> {
  const target = e.target as HTMLInputElement;
  if (!target.files || target.files.length === 0) return;
  try {
    await ingestFiles(Array.from(target.files));
  } finally {
    target.value = '';
  }
}

/**
 * Index a batch of files, whichever way the user supplied them.
 *
 * Shared by the file picker and the drop zone. Unsupported files are named and
 * skipped rather than silently ignored: a drop bypasses the input's `accept`
 * filter, so this is the only place the rule can be enforced, and dropping a
 * folder of mixed content should still index what it can.
 */
async function ingestFiles(files: File[]): Promise<void> {
  if (isBusy || files.length === 0) return;

  const supported = files.filter((file) => isSupportedFile(file));
  const rejected = files.filter((file) => !isSupportedFile(file));

  if (supported.length === 0) {
    setStatus(
      `${describeFileList(rejected)} can't be indexed — this demo reads ${ACCEPTED_EXTENSIONS.join(', ')}.`,
      'error',
    );
    return;
  }

  isBusy = true;
  try {
    const outcome = await ensureRAGSession();
    if (!outcome.ok) return; // ensureRAGSession already reported why
    for (const file of supported) {
      await ingestText(outcome.session, {
        text: await file.text(),
        name: file.name,
        sourceUri: `web-file:${file.name}`,
        mediaType: file.type || 'text/plain',
        sizeBytes: file.size,
      });
    }
    await renderDocList();
    if (rejected.length > 0) {
      setStatus(
        `Indexed ${supported.length} file${supported.length === 1 ? '' : 's'}. Skipped ${describeFileList(rejected)} — this demo reads ${ACCEPTED_EXTENSIONS.join(', ')}.`,
        'error',
      );
    }
  } catch (err) {
    setStatus(`Indexing failed: ${formatError(err)}`, 'error');
  } finally {
    isBusy = false;
  }
}

/** Extension check, because a dropped file never passes through `accept`. */
function isSupportedFile(file: File): boolean {
  const name = file.name.toLowerCase();
  return ACCEPTED_EXTENSIONS.some((extension) => name.endsWith(extension));
}

function describeFileList(files: File[]): string {
  const names = files.map((file) => file.name);
  if (names.length === 1) return names[0];
  if (names.length === 2) return `${names[0]} and ${names[1]}`;
  return `${names.slice(0, 2).join(', ')} and ${names.length - 2} more`;
}

interface IngestPayload {
  text: string;
  name: string;
  sourceUri: string;
  mediaType: string;
  sizeBytes: number;
}

/**
 * Ingest already-read text.
 *
 * Text rather than a `File` because pasted content has no file behind it —
 * .txt/.md/.json are all read as plain text and ingested as-is anyway, same as
 * iOS, where JSON documents flow through text extraction before ingest
 * (DocumentRAGView.swift:50 allows [.pdf, .json]).
 */
async function ingestText(session: RagSession, payload: IngestPayload): Promise<void> {
  const before = await session.stats();

  setStatus(`Indexing ${payload.name}...`);
  await session.ingest({
    text: payload.text,
    name: payload.name,
    metadata: {
      docId: createDocumentId(),
      sourceUri: payload.sourceUri,
      mediaType: payload.mediaType,
      sizeBytes: String(payload.sizeBytes),
    },
  });

  const stats = await session.stats();
  ingestedDocuments.push({
    name: payload.name,
    chunkCount: Math.max(0, stats.chunkCount - before.chunkCount),
  });
  setStatus(`Indexed ${payload.name}. ${stats.chunkCount} chunks total.`);
}

/**
 * Index pasted text as a document.
 *
 * Pasting a passage is the fastest way to try RAG — it skips picking, saving and
 * uploading a file just to ask one question about a paragraph.
 */
async function ingestPastedText(text: string): Promise<void> {
  if (isBusy) return;
  isBusy = true;
  try {
    const outcome = await ensureRAGSession();
    if (!outcome.ok) return;
    pastedNoteCount += 1;
    const name = `Pasted text ${pastedNoteCount}`;
    await ingestText(outcome.session, {
      text,
      name,
      sourceUri: 'web-paste:',
      mediaType: 'text/plain',
      sizeBytes: new Blob([text]).size,
    });
    await renderDocList();
  } catch (err) {
    setStatus(`Indexing failed: ${formatError(err)}`, 'error');
  } finally {
    isBusy = false;
  }
}

async function clearAllDocs(): Promise<void> {
  if (isBusy) return;
  isBusy = true;
  try {
    const outcome = await ensureRAGSession();
    if (!outcome.ok) return;
    await outcome.session.clear();
    ingestedDocuments.length = 0;
    pastedNoteCount = 0;
    await renderDocList();
    setStatus('All documents cleared.');
  } catch (err) {
    setStatus(`Clear failed: ${formatError(err)}`, 'error');
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
  if (!question) {
    // Was a bare `return`: clicking Ask with an empty box did nothing at all, so
    // the button read as broken rather than as waiting for input.
    setAnswerText('Type a question first.');
    queryEl.focus();
    return;
  }

  isBusy = true;
  setAnswerText('Searching...');
  try {
    const outcome = await ensureRAGSession();
    if (!outcome.ok) {
      // The failure already said what went wrong, in the ingest section's status
      // line. Point at it rather than restating it here in different words —
      // this is where the false "select models first" used to appear beside the
      // real error, with both selects visibly populated.
      setAnswerText(outcome.reason === 'models-not-selected'
        ? outcome.message
        : `${outcome.message} Fix that above, then ask again.`);
      return;
    }
    const session = outcome.session;
    if ((await session.stats()).documentCount === 0) {
      setAnswerText('Upload a document first — answers are grounded in what you index here.');
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

/**
 * Report progress or a problem in the ingest section.
 *
 * The `error` tone is what makes a failure look like one — `.docs-status.error`
 * already exists for exactly this, and without it a failure rendered in the same
 * grey as an idle hint.
 */
function setStatus(msg: string, tone: 'info' | 'error' = 'info'): void {
  const el = container.querySelector('#docs-status');
  if (!el) return;
  el.textContent = msg;
  el.classList.toggle('error', tone === 'error');
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
async function ensureRAGSession(): Promise<SessionOutcome> {
  if (!selectedEmbeddingModelId || !selectedLlmModelId) {
    const message = 'Select an embedding model and an LLM model first.';
    setStatus(message, 'error');
    return { ok: false, reason: 'models-not-selected', message };
  }
  const key = `${selectedEmbeddingModelId}|${selectedLlmModelId}`;
  if (ragSession && openedPipelineKey === key) return { ok: true, session: ragSession };

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
    return { ok: true, session: ragSession };
  } catch (err) {
    await closeRAGSession();
    // Report the actual failure. This used to be paraphrased by the caller as
    // "select models first" — advice the user had already followed.
    const message = `Couldn't start the document pipeline: ${formatError(err)}`;
    setStatus(message, 'error');
    return { ok: false, reason: 'open-failed', message };
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
