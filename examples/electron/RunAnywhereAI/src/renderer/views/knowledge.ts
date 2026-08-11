/**
 * Knowledge — standalone RAG hub.
 *
 * One session at a time: `rag.open` is memoized so concurrent first-use shares
 * a single native handle. The session survives view dispose so leaving and
 * returning does not throw away the index (legacy Electron behaviour).
 */
import type { Match, RagSession } from '@runanywhere/electron';

import type { ViewFactory, ViewInstance } from '../shell/app';
import { showError, showToast } from '../components/toast';
import { escapeHtml } from '../services/format';
import { logger } from '../services/logger';
import { modelLabel } from '../services/modality-models';
import {
  generationOptions,
  loadAppSettings,
  selectedModel,
} from '../services/settings';

const log = logger('knowledge');

/** App-wide singleton — one RAG corpus for the whole process. */
let session: RagSession | null = null;
let opening: Promise<RagSession> | null = null;

async function ensureSession(): Promise<RagSession> {
  if (session !== null) return session;
  if (opening !== null) return opening;
  opening = (async () => {
    await loadAppSettings();
    session = await window.runanywhere.rag.open(
      { id: selectedModel('embedder') },
      { id: selectedModel('llm') },
      { topK: 3, chunkSize: 512, chunkOverlap: 64 },
    );
    return session;
  })().catch((error: unknown) => {
    opening = null;
    throw error;
  });
  return opening;
}

function statsText(documentCount: number, chunkCount: number): string {
  if (documentCount === 0) return 'No documents yet';
  const docs = `${documentCount} document${documentCount === 1 ? '' : 's'}`;
  const chunks = `${chunkCount} chunk${chunkCount === 1 ? '' : 's'} indexed`;
  return `${docs} · ${chunks}`;
}

function renderSources(host: HTMLElement, chunks: readonly Match[]): void {
  if (chunks.length === 0) {
    host.replaceChildren();
    return;
  }
  host.innerHTML =
    `<div class="ra-label" style="margin-top:var(--ra-space-md)">Sources</div>` +
    chunks
      .map((chunk) => {
        const src =
          'sourceDocument' in chunk.metadata && chunk.metadata.sourceDocument.trim() !== ''
            ? chunk.metadata.sourceDocument
            : 'document';
        const score = typeof chunk.score === 'number' ? chunk.score.toFixed(3) : '';
        return (
          `<div class="ra-rag-chunk">` +
          `<div class="ra-rag-chunk-meta"><span>${escapeHtml(src)}</span>` +
          `<span class="ra-rag-score">${escapeHtml(score)}</span></div>` +
          `<div class="ra-rag-chunk-text">${escapeHtml(chunk.text)}</div>` +
          `</div>`
        );
      })
      .join('');
}

export const createKnowledgeView: ViewFactory = ({ root, refreshChrome }): ViewInstance => {
  let queryInFlight = false;

  const scroll = document.createElement('div');
  scroll.className = 'ra-view-scroll';
  scroll.innerHTML = `
    <div class="ra-stack">
      <p class="ra-hint">Add documents, then ask questions answered only from what you added.</p>
      <div class="ra-card ra-stack">
        <label class="ra-field">
          <span class="ra-label">Paste text</span>
          <textarea class="ra-textarea" data-role="doc" rows="4" placeholder="Paste any text — notes, an article, docs…"></textarea>
        </label>
        <div class="ra-row">
          <button type="button" class="ra-btn-primary" data-action="add-text">Add text</button>
          <button type="button" class="ra-btn-secondary" data-action="add-files">Add files…</button>
          <button type="button" class="ra-btn-quiet" data-action="clear">Clear all</button>
          <span class="ra-muted" data-role="stats">No documents yet</span>
        </div>
      </div>
      <div class="ra-card ra-stack">
        <label class="ra-field">
          <span class="ra-label">Ask a question</span>
          <textarea class="ra-textarea" data-role="question" rows="2" placeholder="What does the document say about…?"></textarea>
        </label>
        <button type="button" class="ra-btn-primary" data-action="ask">Ask</button>
        <div>
          <div class="ra-label">Answer</div>
          <div class="ra-out" data-role="out" data-empty="Ask a question and the answer appears here, grounded in your documents."></div>
          <div data-role="sources"></div>
        </div>
      </div>
    </div>
  `;
  root.append(scroll);

  const docEl = scroll.querySelector<HTMLTextAreaElement>('[data-role="doc"]');
  const questionEl = scroll.querySelector<HTMLTextAreaElement>('[data-role="question"]');
  const statsEl = scroll.querySelector<HTMLElement>('[data-role="stats"]');
  const out = scroll.querySelector<HTMLElement>('[data-role="out"]');
  const sources = scroll.querySelector<HTMLElement>('[data-role="sources"]');
  const askBtn = scroll.querySelector<HTMLButtonElement>('[data-action="ask"]');

  const setOut = (text: string): void => {
    if (out === null) return;
    out.textContent = text;
    out.toggleAttribute('data-has-content', text.length > 0);
  };

  const refreshStats = async (): Promise<void> => {
    if (statsEl === null) return;
    if (session === null) {
      statsEl.textContent = 'No documents yet';
      return;
    }
    try {
      const stats = await session.stats();
      statsEl.textContent = statsText(stats.documentCount, stats.chunkCount);
    } catch {
      /* session may still be opening */
    }
  };

  const ingestPaths = async (paths: readonly string[]): Promise<void> => {
    if (paths.length === 0) return;
    const rag = await ensureSession();
    for (const path of paths) {
      await rag.ingest(window.runanywhere.ragDocument.file(path));
    }
    await refreshStats();
    showToast(`Added ${paths.length} document${paths.length === 1 ? '' : 's'}`, 'success');
  };

  const addText = async (): Promise<void> => {
    const text = docEl?.value.trim() ?? '';
    if (text === '') {
      showToast('Paste some text to index first.');
      return;
    }
    try {
      const rag = await ensureSession();
      await rag.ingest(window.runanywhere.ragDocument.text(text));
      if (docEl !== null) docEl.value = '';
      await refreshStats();
      showToast('Document indexed.', 'success');
    } catch (error) {
      log.error('ingest failed', error);
      showError(error, 'Could not add document');
    }
  };

  const addFiles = async (): Promise<void> => {
    try {
      const paths = await window.appStore.pickFiles({
        title: 'Add documents',
        filters: [{ name: 'Text', extensions: ['txt', 'md', 'json', 'csv'] }],
        multiple: true,
      });
      await ingestPaths(paths);
    } catch (error) {
      log.error('ingest files failed', error);
      showError(error, 'Could not add documents');
    }
  };

  const clear = async (): Promise<void> => {
    try {
      if (session === null) {
        if (statsEl !== null) statsEl.textContent = 'No documents yet';
        setOut('');
        if (sources !== null) sources.replaceChildren();
        return;
      }
      await session.clear();
      await refreshStats();
      setOut('');
      if (sources !== null) sources.replaceChildren();
      showToast('Knowledge base cleared.');
    } catch (error) {
      log.error('clear failed', error);
      showError(error, 'Could not clear knowledge base');
    }
  };

  const ask = async (): Promise<void> => {
    const question = questionEl?.value.trim() ?? '';
    if (question === '' || queryInFlight) return;
    queryInFlight = true;
    if (askBtn !== null) askBtn.disabled = true;
    refreshChrome();
    setOut('');
    if (sources !== null) sources.replaceChildren();
    try {
      await loadAppSettings();
      const rag = await ensureSession();
      let answer = '';
      let matches: Match[] = [];
      for await (const event of rag.queryStream(question, generationOptions())) {
        switch (event.type) {
          case 'retrieved':
            matches = [...event.matches];
            break;
          case 'token':
            answer += event.text;
            setOut(answer);
            break;
          case 'completed':
            answer = event.result.answer;
            matches = [...event.result.sources];
            setOut(answer.trim());
            break;
          default: {
            const _exhaustive: never = event;
            void _exhaustive;
          }
        }
      }
      if (sources !== null) renderSources(sources, matches);
    } catch (error) {
      log.error('query failed', error);
      showError(error, 'Knowledge query failed');
    } finally {
      queryInFlight = false;
      if (askBtn !== null) askBtn.disabled = false;
      refreshChrome();
    }
  };

  scroll.addEventListener('click', (event) => {
    const target = (event.target as HTMLElement | null)?.closest<HTMLElement>('[data-action]');
    if (target === null || target === undefined) return;
    const action = target.dataset.action;
    if (action === 'add-text') void addText();
    else if (action === 'add-files') void addFiles();
    else if (action === 'clear') void clear();
    else if (action === 'ask') void ask();
  });

  void loadAppSettings().then(() => {
    if (session !== null) void refreshStats();
  });

  return {
    model() {
      return { name: modelLabel(selectedModel('llm')), meta: 'Knowledge' };
    },
    capabilities() {
      return {
        canStopGeneration: queryInFlight,
        canShowChatDetails: false,
        canPasteAttachment: false,
      };
    },
  };
};
