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
import {
  engineNoticeForCategories,
  isEngineBlocked,
  renderEngineNotice,
  wireEngineNotice,
} from '../components/engine-notice';
import { renderFileDrop, wireFileDrop } from '../components/file-drop';
import { icon } from '../components/icons';
import { onEngineStateChange } from '../services/engine-availability';
import { escapeHtml } from '../services/escape-html';
import { formatError } from '../services/format-error';
import { formatFramework } from '../services/model-display';
import { renderMarkdown } from '../services/markdown';
import { getGenerationSettings } from './settings';

const TOP_K = 3;

/**
 * The model categories this view's pipeline needs.
 *
 * Documents is the one surface whose engine attribution is genuinely mixed: its
 * embedding picker offers both llama.cpp entries (`nemotron-3-embed-1b-*`) and an
 * ONNX one (`all-minilm-l6-v2`), and answer generation always needs llama.cpp.
 * Scoping the notice to both categories is what lets it name whichever engine
 * actually failed instead of asserting one.
 */
const DOCS_CATEGORIES: readonly ModelCategory[] = [
  ModelCategory.MODEL_CATEGORY_EMBEDDING,
  ModelCategory.MODEL_CATEGORY_LANGUAGE,
];

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

/** Matches the chat composer's document limit, so one app has one answer. */
const MAX_DOCUMENT_BYTES = 4 * 1024 * 1024;

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
  | {
      ok: false;
      reason: 'engine-unavailable' | 'models-not-selected' | 'open-failed';
      message: string;
    };

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
let unsubscribeEngine: (() => void) | null = null;

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
      <div id="docs-engine-notice"></div>
      <div class="docs-section">
        <h3>Set up the pipeline</h3>
        <p class="text-secondary">Two models work together: one to index your files, one to answer questions about them.</p>
        <div class="model-pair">
          <div class="model-pair__field">
            <label class="model-pair__label" for="docs-embedding-model">Indexing model</label>
            <div class="model-pair__row">
              <select id="docs-embedding-model" class="model-pair__select"></select>
              <button class="btn btn-secondary" id="docs-embedding-download-btn">Download</button>
            </div>
          </div>
          <div class="model-pair__field">
            <label class="model-pair__label" for="docs-llm-model">Answering model</label>
            <div class="model-pair__row">
              <select id="docs-llm-model" class="model-pair__select"></select>
              <button class="btn btn-secondary" id="docs-llm-download-btn">Download</button>
            </div>
          </div>
        </div>
        <div id="docs-model-status" class="docs-status"></div>
      </div>
      <div class="docs-section">
        <h3>Indexed documents</h3>
        <p class="text-secondary">Answers are grounded in the files you index here.
        The index lives in this tab only — it is cleared when you reload the page.</p>
        ${renderFileDrop({
          id: 'docs-dropzone',
          accept: ACCEPTED_EXTENSIONS.join(','),
          title: 'Drop files here, or click to choose',
          hint: `${ACCEPTED_EXTENSIONS.join(', ')} — or paste text straight onto this page`,
          multiple: true,
        })}
        <div class="docs-actions">
          <button class="btn btn-secondary" id="docs-clear-btn">Clear all</button>
        </div>
        <ul class="docs-list" id="docs-list"></ul>
        <div id="docs-status" class="docs-status" role="status" aria-live="polite"></div>
      </div>
      <div class="docs-section">
        <h3>Ask a question</h3>
        <p class="text-secondary">Answers cite the files above, so you can check where each one came from.</p>
        <label class="sr-only" for="docs-query">Your question</label>
        <textarea id="docs-query" class="docs-query" rows="3"
          placeholder="What does the document say about…?"></textarea>
        <button class="btn btn-primary" id="docs-ask-btn">Ask</button>
        <div id="docs-answer" class="docs-answer"></div>
      </div>
    </div>
  `;

  bindModelPickers();
  populateModelPickers();
  void renderDocList();
  renderIdleAnswer();

  wireFileDrop(container, 'docs-dropzone', (files) => {
    void ingestFiles([...files]);
  });
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
  refreshEngineNotice();
  refreshModelButtons();

  // A retry that succeeds has to restore this tab in place: the pickers are
  // populated from the registry once, at init, so without this a recovered
  // engine would leave "No embedding models registered" on screen forever.
  unsubscribeEngine = onEngineStateChange(() => {
    if (!container.isConnected) return;
    populateModelPickers();
    refreshEngineNotice();
    refreshModelButtons();
  });

  return {
    onActivate: () => {
      // Re-arm: init runs once, but every deactivate detaches the paste listener.
      if (!detachPaste) setupPasteToIndex();
      refreshEngineNotice();
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
      if (!container.isConnected) {
        unsubscribeEngine?.();
        unsubscribeEngine = null;
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Engine availability
// ---------------------------------------------------------------------------

/**
 * Say so when the engine this pipeline needs never loaded.
 *
 * Without this the tab was quietly the least honest surface in the app. Both
 * `<select>`s populate from the model registry, which is empty when no engine
 * registered, so they read "No embedding models registered" / "No LLM models
 * registered" — phrasing that blames the *catalog* for an engine failure and
 * offers nothing to do about it. Meanwhile Download, the drop zone and Ask all
 * stayed enabled, so indexing a file got as far as `rag.open` before failing
 * with a stack-shaped message.
 *
 * The notice is scoped to both categories (see `DOCS_CATEGORIES`) so it names
 * whichever of the two artifacts actually failed.
 */
function refreshEngineNotice(): void {
  const host = container.querySelector<HTMLElement>('#docs-engine-notice');
  if (!host) return;
  const notice = engineNoticeForCategories(DOCS_CATEGORIES);
  host.innerHTML = renderEngineNotice(notice);
  wireEngineNotice(host, notice);
  setControlsBlocked(isEngineBlocked(notice));
  // Ask is the one control with a second reason to be disabled (an answer is in
  // flight), so its state is owned in one place rather than split across two.
  refreshAskButton();
}

/** True when an engine failure means nothing on this tab can succeed. */
function enginesBlocked(): boolean {
  return isEngineBlocked(engineNoticeForCategories(DOCS_CATEGORIES));
}

/**
 * Disable what cannot work.
 *
 * A disabled drop zone still needs `disabled` on the button rather than
 * `pointer-events: none`: the latter leaves a dashed target that accepts a drop
 * and silently discards it.
 */
function setControlsBlocked(blocked: boolean): void {
  const ids = ['#docs-dropzone', '#docs-clear-btn'] as const;
  for (const id of ids) {
    const el = container.querySelector<HTMLButtonElement>(id);
    if (el) el.disabled = blocked;
  }
  const query = container.querySelector<HTMLTextAreaElement>('#docs-query');
  if (query) query.disabled = blocked;
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

/** Bound once at init; `populateModelPickers` is called again on engine recovery. */
function bindModelPickers(): void {
  const embeddingSelect = container.querySelector<HTMLSelectElement>('#docs-embedding-model')!;
  const llmSelect = container.querySelector<HTMLSelectElement>('#docs-llm-model')!;
  embeddingSelect.addEventListener('change', () => {
    selectedEmbeddingModelId = embeddingSelect.value;
    refreshModelButtons();
  });
  llmSelect.addEventListener('change', () => {
    selectedLlmModelId = llmSelect.value;
    refreshModelButtons();
  });
}

/**
 * Fill both pickers from the registry, preserving the user's choice.
 *
 * Re-runnable, because a successful engine retry turns an empty registry into a
 * populated one and this tab builds its DOM once. Preserving the selection
 * matters for the same reason: re-filling must not silently repoint the pipeline
 * at whatever model happens to sort first.
 */
function populateModelPickers(): void {
  const embeddingSelect = container.querySelector<HTMLSelectElement>('#docs-embedding-model')!;
  const llmSelect = container.querySelector<HTMLSelectElement>('#docs-llm-model')!;

  fillSelect(
    embeddingSelect,
    registryModelsForCategory(ModelCategory.MODEL_CATEGORY_EMBEDDING),
    'No indexing models available',
    selectedEmbeddingModelId,
  );
  fillSelect(
    llmSelect,
    registryModelsForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE),
    'No answering models available',
    selectedLlmModelId,
  );

  selectedEmbeddingModelId = embeddingSelect.value;
  selectedLlmModelId = llmSelect.value;
}

function fillSelect(
  select: HTMLSelectElement,
  models: ModelInfo[],
  emptyLabel: string,
  preferredId: string,
): void {
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
  if (preferredId && models.some((model) => model.id === preferredId)) {
    select.value = preferredId;
  }
}

function selectedLlmSupportsThinking(): boolean {
  return registryModelsForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE)
    .some((model) => model.id === selectedLlmModelId && model.supportsThinking);
}

// ---------------------------------------------------------------------------
// Paste
// ---------------------------------------------------------------------------

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

  // Chunking and embedding happen on the main thread, so an accidental
  // multi-hundred-megabyte log file would freeze the tab with no way back.
  const oversized = supported.filter((file) => file.size > MAX_DOCUMENT_BYTES);
  if (oversized.length > 0) {
    setStatus(
      `${describeFileList(oversized)} is over ${formatMegabytes(MAX_DOCUMENT_BYTES)} — indexing that much text in the browser would lock up this tab.`,
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
  // Clearing nothing must not open a session. `ensureRAGSession` loads both
  // models into memory, so pressing "Clear all" on an empty index used to be the
  // most expensive button on the tab — and it reported a pipeline error when the
  // models were not downloaded, for an index that was already empty.
  if (!ragSession) {
    ingestedDocuments.length = 0;
    pastedNoteCount = 0;
    await renderDocList();
    renderIdleAnswer();
    setStatus('Nothing is indexed yet.');
    return;
  }
  isBusy = true;
  try {
    const outcome = await ensureRAGSession();
    if (!outcome.ok) return;
    await outcome.session.clear();
    ingestedDocuments.length = 0;
    pastedNoteCount = 0;
    await renderDocList();
    // The answer on screen cites passages that no longer exist. Leaving it would
    // present a stale answer as if it still had sources behind it.
    renderIdleAnswer();
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

/** Stops the in-flight answer; `null` when nothing is being answered. */
let cancelAnswer: (() => void) | null = null;

/**
 * Reflect the ask state on the one control that starts and stops it.
 *
 * A silent early `return` on a second click was indistinguishable from a dead
 * button, and there was no way at all to abandon a long answer.
 */
function refreshAskButton(): void {
  const btn = container.querySelector<HTMLButtonElement>('#docs-ask-btn');
  if (!btn) return;
  const answering = cancelAnswer !== null;
  btn.textContent = answering ? 'Stop' : 'Ask';
  btn.disabled = enginesBlocked() || (isBusy && !answering);
  btn.title = answering ? 'Stop writing this answer' : 'Answer from the indexed files';
}

async function askQuestion(): Promise<void> {
  if (cancelAnswer) {
    cancelAnswer();
    return;
  }
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
  refreshAskButton();
  setAnswerText('Looking through the indexed files…');
  try {
    const outcome = await ensureRAGSession();
    if (!outcome.ok) {
      // The failure already said what went wrong, and now says what to do about
      // it, so it is repeated verbatim rather than paraphrased — this is where
      // the false "select models first" used to appear beside the real error,
      // with both selects visibly populated.
      setAnswerText(outcome.message);
      return;
    }
    const session = outcome.session;
    if ((await session.stats()).documentCount === 0) {
      setAnswerText('Upload a document first — answers are grounded in what you index here.');
      return;
    }

    const suppressThinking = selectedLlmSupportsThinking()
      && !getGenerationSettings().thinkingModeEnabled;
    // Streamed rather than one-shot, for the reason iOS moved
    // (LLMViewModel+Documents.swift:72-77): the v4 pipeline can resolve the
    // one-shot `query` with an empty answer, and a reader watching "Searching…"
    // for thirty seconds cannot tell a working pipeline from a stuck one.
    const events = session.queryStream(question, {
      generation: {
        maxOutputTokens: 512,
        temperature: 0.4,
        reasoning: suppressThinking ? { mode: 'off' } : { mode: 'on', includeInOutput: true },
      },
    });
    const iterator = events[Symbol.asyncIterator]();
    let stopped = false;
    cancelAnswer = () => {
      stopped = true;
      void iterator.return?.();
    };
    refreshAskButton();

    let answer = '';
    let sources: Match[] = [];
    for (let step = await iterator.next(); !step.done; step = await iterator.next()) {
      const event = step.value;
      if (event.type === 'retrieved') {
        sources = event.matches;
        // Citations are known before the first token, so show them immediately:
        // the passages are the evidence, and seeing them arrive is what makes
        // the wait for the sentence legible.
        setAnswerHtml(formatAnswer(answer, sources));
      } else if (event.type === 'textDelta') {
        answer += event.text;
        setAnswerHtml(formatAnswer(answer, sources));
      } else if (event.type === 'completed') {
        answer = event.result.answer || answer;
        if (event.result.sources.length > 0) sources = event.result.sources;
        setAnswerHtml(formatAnswer(answer, sources));
      } else if (event.type === 'failed') {
        throw new Error(event.error.message || 'The answer could not be generated.');
      }
    }

    if (sources.length === 0) {
      setAnswerText('Nothing in the indexed files matched that question.');
      return;
    }
    if (!answer.trim()) {
      setAnswerText(stopped
        ? 'Stopped before the answer started.'
        : 'The passages above matched, but the model did not write an answer. Try rephrasing the question.');
      return;
    }
    setAnswerHtml(formatAnswer(answer, sources));
  } catch (err) {
    setAnswerText(`Failed: ${formatError(err)}`);
  } finally {
    cancelAnswer = null;
    isBusy = false;
    refreshAskButton();
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

/**
 * The answer area before anything has been asked.
 *
 * It used to be an empty `<div>`, so the section ended on a bare "Ask" button
 * with a void beneath it and no sign that an answer was ever going to appear
 * there. Rendered once at init and re-rendered by Clear, so the pane always says
 * what it is.
 */
function renderIdleAnswer(): void {
  const el = answerElement();
  if (!el) return;
  el.innerHTML = `
    <div class="surface-empty">
      ${icon('message', { size: 24 })}
      <p>Answers appear here, with the passages they came from.</p>
    </div>
  `;
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
 * Open (or reuse) the corpus session for the selected model pair.
 *
 * `rag.open` validates that both models are already on disk and throws when
 * either is not — it does not fetch them. That is what the two Download buttons
 * above the pickers are for, and why a not-downloaded failure is translated into
 * a sentence pointing at them rather than passed through as
 * "…set validate_availability", which names a flag no user can set.
 */
async function ensureRAGSession(): Promise<SessionOutcome> {
  // Belt and braces alongside the disabled controls: paste-to-index listens on
  // `document`, so it can reach this without passing through a button.
  if (enginesBlocked()) {
    const message = 'The on-device AI engine did not load, so documents cannot be indexed yet.';
    setStatus(message, 'error');
    return { ok: false, reason: 'engine-unavailable', message };
  }
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
    const message = describeOpenFailure(err);
    setStatus(message, 'error');
    return { ok: false, reason: 'open-failed', message };
  }
}

/**
 * The one failure worth rewriting: a model that is registered but not on disk.
 *
 * `rag.open` reports it as "Embedding model 'x': model is not downloaded —
 * download it first or set validate_availability". The second half is an
 * instruction to a caller, not to a reader, and the first half does not mention
 * the Download button sitting a few pixels above.
 */
function describeOpenFailure(err: unknown): string {
  const detail = formatError(err);
  if (/not downloaded/i.test(detail)) {
    const which = /embedding/i.test(detail) ? 'indexing' : 'answering';
    return `The ${which} model isn't on this device yet. Press Download next to it above, then try again.`;
  }
  return `Couldn't start the document pipeline: ${detail}`;
}

async function closeRAGSession(): Promise<void> {
  const previous = ragSession;
  ragSession = null;
  openedPipelineKey = null;
  ingestedDocuments.length = 0;
  await previous?.close().catch(() => undefined);
}

/**
 * Render a RAG answer with citations. Reasoning is commons-owned
 * (RAGResult.thinking_content); the public RagResult mapping does not yet
 * expose it, so this view does not re-parse `<think>` tags from the answer.
 */
function formatAnswer(text: string, sources: Match[]): string {
  const sourcesHtml = sources.map((source, i) => `
    <div class="docs-source">
      <strong>Source ${i + 1}: ${escapeHtml(source.metadata.docName ?? 'Document')}</strong>
      <pre>${escapeHtml(source.text.slice(0, 400))}${source.text.length > 400 ? '...' : ''}</pre>
    </div>
  `).join('');
  // The answer is model output, so it is markdown — the same renderer the chat
  // bubble uses. It was `escapeHtml`'d straight into a div, which meant a RAG
  // answer with numbered steps or a heading showed its `1.` and `###` markers
  // as literal characters while the identical text rendered properly one tab
  // over in Chat. `renderMarkdown` escapes every span itself.
  return `<div class="docs-answer-text">${renderMarkdown(text)}</div>`
    + `<div class="docs-sources">${sourcesHtml}</div>`;
}

function formatMegabytes(bytes: number): string {
  return `${Math.round(bytes / (1024 * 1024))} MB`;
}

function createDocumentId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return Math.random().toString(36).slice(2);
}
