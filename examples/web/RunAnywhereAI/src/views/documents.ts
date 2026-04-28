/**
 * Documents Tab — minimal local RAG demo.
 *
 * Pipeline:
 *   1. Upload .txt or .md (PDF stub left for future).
 *   2. Chunk text (~256 tokens).
 *   3. Embed each chunk via the SDK's Embeddings extension (the user
 *      must load an embedding GGUF first via the inline "Load model"
 *      button — these are not part of the LLM registry).
 *   4. Persist {chunk, vector} to localStorage.
 *   5. On query, embed the question, score chunks by cosine
 *      similarity, take top-K and pass them to TextGeneration as
 *      context.
 *
 * Designed as a developer-facing demo — error paths are surfaced
 * inline rather than via toasts.
 */

import type { TabLifecycle } from '../app';
import { ModelManager, ModelCategory } from '../services/model-manager';
import { showToast } from '../components/dialogs';

interface DocChunk {
  id: string;
  docId: string;
  docName: string;
  text: string;
  vector: number[];
}

const DOCS_STORAGE_KEY = 'runanywhere-rag-chunks';
const CHUNK_TOKEN_TARGET = 256;
const TOP_K = 3;

let container: HTMLElement;
let chunks: DocChunk[] = [];
let isBusy = false;

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export function initDocumentsTab(el: HTMLElement): TabLifecycle {
  container = el;
  container.innerHTML = `
    <div class="toolbar">
      <div class="toolbar-title">Documents</div>
      <div class="toolbar-actions"></div>
    </div>
    <div class="scroll-area">
      <div class="docs-section">
        <h3>Indexed documents</h3>
        <p class="text-secondary">Upload <code>.txt</code> or <code>.md</code> files to embed and query locally.
        Make sure an embedding model is loaded via <code>Embeddings.loadModel(...)</code> &mdash;
        a Language model is also required for answer generation.</p>
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
        <p class="text-secondary">Embeds the query, retrieves top-${TOP_K} chunks via cosine similarity, then generates an answer using the loaded LLM.</p>
        <textarea id="docs-query" class="docs-query" placeholder="Ask something about your uploaded docs..." rows="3"></textarea>
        <button class="btn btn-primary" id="docs-ask-btn">Ask</button>
        <div id="docs-answer" class="docs-answer"></div>
      </div>
    </div>
  `;

  loadChunks();
  renderDocList();

  container.querySelector('#docs-upload-btn')!.addEventListener('click', () => {
    (container.querySelector('#docs-file') as HTMLInputElement).click();
  });
  container.querySelector('#docs-file')!.addEventListener('change', onFilePicked);
  container.querySelector('#docs-clear-btn')!.addEventListener('click', clearAllDocs);
  container.querySelector('#docs-ask-btn')!.addEventListener('click', askQuestion);

  return {};
}

// ---------------------------------------------------------------------------
// Persistence
// ---------------------------------------------------------------------------

function loadChunks(): void {
  try {
    const raw = localStorage.getItem(DOCS_STORAGE_KEY);
    if (!raw) return;
    const parsed = JSON.parse(raw) as DocChunk[];
    if (Array.isArray(parsed)) chunks = parsed;
  } catch (e) {
    console.warn('[Docs] load failed:', e);
  }
}

function persistChunks(): void {
  try {
    localStorage.setItem(DOCS_STORAGE_KEY, JSON.stringify(chunks));
  } catch (e) {
    console.warn('[Docs] persist failed (likely quota):', e);
    showToast('Storage quota exceeded — older chunks dropped', 'warning');
  }
}

function clearAllDocs(): void {
  chunks = [];
  persistChunks();
  renderDocList();
  setStatus('All chunks cleared.');
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
    for (const file of Array.from(target.files)) {
      await ingestFile(file);
    }
    persistChunks();
    renderDocList();
  } finally {
    isBusy = false;
    target.value = '';
  }
}

async function ingestFile(file: File): Promise<void> {
  setStatus(`Reading ${file.name}…`);
  const text = await file.text();
  const docId = crypto.randomUUID();
  const pieces = chunkText(text);

  setStatus(`Embedding ${pieces.length} chunks from ${file.name}…`);

  const { Embeddings } = await import(
    '../../../../../sdk/runanywhere-web/packages/llamacpp/src/index'
  );
  if (!Embeddings.isModelLoaded) {
    setStatus('No embedding model loaded. Run Embeddings.loadModel(...) first (e.g. nomic-embed-text-v1.5.Q4_K_M).');
    return;
  }

  for (let i = 0; i < pieces.length; i++) {
    const piece = pieces[i];
    try {
      const result = await Embeddings.embed(piece);
      const vector = Array.from(result.embeddings[0]?.data ?? []);
      if (vector.length === 0) continue;
      chunks.push({
        id: crypto.randomUUID(),
        docId,
        docName: file.name,
        text: piece,
        vector,
      });
      setStatus(`Embedded ${i + 1}/${pieces.length} from ${file.name}…`);
    } catch (err) {
      console.error('[Docs] embedding failed for chunk', i, err);
    }
  }

  setStatus(`Indexed ${file.name}: ${pieces.length} chunks.`);
}

/** Split text into approximately CHUNK_TOKEN_TARGET-token pieces.
 *  Uses a 4-chars-per-token estimate (good enough for English prose). */
function chunkText(text: string): string[] {
  const charsPerChunk = CHUNK_TOKEN_TARGET * 4;
  const pieces: string[] = [];
  const paragraphs = text.split(/\n\s*\n/).map(p => p.trim()).filter(Boolean);

  let buf = '';
  for (const para of paragraphs) {
    if ((buf.length + para.length) > charsPerChunk && buf.length > 0) {
      pieces.push(buf.trim());
      buf = '';
    }
    if (para.length > charsPerChunk) {
      // Long paragraph — slice mid-word.
      for (let i = 0; i < para.length; i += charsPerChunk) {
        pieces.push(para.slice(i, i + charsPerChunk));
      }
    } else {
      buf += (buf ? '\n\n' : '') + para;
    }
  }
  if (buf.trim()) pieces.push(buf.trim());
  return pieces;
}

// ---------------------------------------------------------------------------
// Query
// ---------------------------------------------------------------------------

async function askQuestion(): Promise<void> {
  if (isBusy) return;
  const queryEl = container.querySelector('#docs-query') as HTMLTextAreaElement;
  const question = queryEl.value.trim();
  if (!question) return;

  if (chunks.length === 0) {
    setAnswer('Upload a document first.');
    return;
  }

  const llmModel = ModelManager.getLoadedModel(ModelCategory.Language);
  if (!llmModel) {
    setAnswer('Language model required to generate answer. Load one from the Chat tab first.');
    return;
  }

  isBusy = true;
  setAnswer('Searching…');
  try {
    const top = await retrieveTopK(question);
    if (top.length === 0) {
      setAnswer('No relevant chunks found (or embedding model not loaded).');
      return;
    }

    const contextBlock = top
      .map((c, i) => `[Source ${i + 1}: ${c.docName}]\n${c.text}`)
      .join('\n\n---\n\n');

    const prompt = `Use the context below to answer the user's question. If the context doesn't contain the answer, say so.\n\nContext:\n${contextBlock}\n\nQuestion: ${question}\n\nAnswer:`;

    const { TextGeneration } = await import(
      '../../../../../sdk/runanywhere-web/packages/llamacpp/src/index'
    );
    const result = await TextGeneration.generate(prompt, {
      maxTokens: 512,
      temperature: 0.4,
    });

    setAnswer(formatAnswer(result.text, top));
  } catch (err) {
    setAnswer(`Failed: ${err instanceof Error ? err.message : String(err)}`);
  } finally {
    isBusy = false;
  }
}

async function retrieveTopK(query: string): Promise<DocChunk[]> {
  const { Embeddings } = await import(
    '../../../../../sdk/runanywhere-web/packages/llamacpp/src/index'
  );
  if (!Embeddings.isModelLoaded) return [];
  const result = await Embeddings.embed(query);
  const queryVec = Array.from(result.embeddings[0]?.data ?? []);
  if (queryVec.length === 0) return [];

  const scored = chunks
    .filter(c => c.vector.length === queryVec.length)
    .map(c => ({ chunk: c, score: cosine(queryVec, c.vector) }));

  scored.sort((a, b) => b.score - a.score);
  return scored.slice(0, TOP_K).map(s => s.chunk);
}

function cosine(a: number[], b: number[]): number {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na === 0 || nb === 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function renderDocList(): void {
  const listEl = container.querySelector('#docs-list')!;
  // Group chunks by docId so we show one row per uploaded file.
  const byDoc = new Map<string, { name: string; count: number }>();
  for (const c of chunks) {
    const existing = byDoc.get(c.docId);
    if (existing) {
      existing.count++;
    } else {
      byDoc.set(c.docId, { name: c.docName, count: 1 });
    }
  }
  if (byDoc.size === 0) {
    listEl.innerHTML = '<li class="docs-empty">No documents indexed yet</li>';
    return;
  }
  listEl.innerHTML = Array.from(byDoc.entries()).map(([docId, info]) => `
    <li class="docs-item" data-id="${docId}">
      <div>
        <div class="docs-item-title">${escapeHtml(info.name)}</div>
        <div class="docs-item-meta">${info.count} chunk${info.count === 1 ? '' : 's'}</div>
      </div>
      <button class="btn btn-icon docs-item-delete" data-id="${docId}" aria-label="Remove">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" width="16" height="16"><polyline points="3 6 5 6 21 6"/><path d="M19 6l-2 14a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2L5 6"/></svg>
      </button>
    </li>
  `).join('');

  listEl.querySelectorAll<HTMLElement>('.docs-item-delete').forEach(btn => {
    btn.addEventListener('click', () => {
      const id = btn.dataset.id!;
      chunks = chunks.filter(c => c.docId !== id);
      persistChunks();
      renderDocList();
    });
  });
}

function setStatus(msg: string): void {
  const el = container.querySelector('#docs-status');
  if (el) el.textContent = msg;
}

function setAnswer(msg: string): void {
  const el = container.querySelector('#docs-answer') as HTMLElement;
  el.innerHTML = msg;
}

function formatAnswer(text: string, sources: DocChunk[]): string {
  const sourcesHtml = sources.map((s, i) => `
    <div class="docs-source">
      <strong>Source ${i + 1}: ${escapeHtml(s.docName)}</strong>
      <pre>${escapeHtml(s.text.slice(0, 400))}${s.text.length > 400 ? '…' : ''}</pre>
    </div>
  `).join('');
  return `<div class="docs-answer-text">${escapeHtml(text)}</div><div class="docs-sources">${sourcesHtml}</div>`;
}

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}
