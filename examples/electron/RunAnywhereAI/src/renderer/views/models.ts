/**
 * Models — catalog list, download progress, load / unload.
 *
 * Thin SDK calls only: `models.list` / `download` / `load` / `unload` / `state`.
 * Branch on `downloaded`, never invent residency or storage paths. Progress uses
 * the Swift-shaped DownloadEvent grammar via the C1 download-progress control.
 */
import type { DownloadEvent, ModelInfo, ModelsState } from '@runanywhere/electron';

import { createDownloadProgress, type DownloadProgressControl } from '../components/download-progress';
import { icon } from '../components/icons';
import { showError, showToast } from '../components/toast';
import { escapeHtml, formatSize } from '../services/format';
import { logger } from '../services/logger';
import { saveAppSettings } from '../services/settings';
import type { ViewContext, ViewFactory, ViewInstance } from '../shell/app';

const log = logger('models');

const BROWSE_CATEGORIES = new Set([
  'LANGUAGE',
  'VISION',
  'SPEECH_TO_TEXT',
  'TEXT_TO_SPEECH',
  'EMBEDDING',
  'DIARIZATION',
  'SEGMENTATION',
  'VOICE_ACTIVITY',
]);

type RowAction = 'download' | 'load' | 'unload' | 'busy';

export const createModelsView: ViewFactory = (context) => new ModelsView(context);

class ModelsView implements ViewInstance {
  private readonly listHost: HTMLElement;
  private readonly summaryHost: HTMLElement;
  private readonly searchInput: HTMLInputElement;

  private models: ModelInfo[] = [];
  private state: ModelsState | null = null;
  private search = '';
  private readonly progressControls = new Map<string, DownloadProgressControl>();
  private readonly inflight = new Set<string>();
  private disposed = false;

  constructor(private readonly context: ViewContext) {
    const root = context.root;
    root.classList.add('ra-models');

    const toolbar = document.createElement('div');
    toolbar.className = 'ra-models-toolbar';

    this.searchInput = document.createElement('input');
    this.searchInput.type = 'search';
    this.searchInput.className = 'ra-search-input';
    this.searchInput.placeholder = 'Search models';
    this.searchInput.setAttribute('aria-label', 'Search models');
    this.searchInput.addEventListener('input', () => {
      this.search = this.searchInput.value.trim().toLowerCase();
      this.renderList();
    });

    const refresh = document.createElement('button');
    refresh.type = 'button';
    refresh.className = 'ra-btn-quiet';
    refresh.innerHTML = `${icon('arrow.clockwise', { size: 14 })}<span>Refresh</span>`;
    refresh.addEventListener('click', () => void this.reload());

    toolbar.append(this.searchInput, refresh);

    this.summaryHost = document.createElement('div');
    this.summaryHost.className = 'ra-models-summary';

    this.listHost = document.createElement('div');
    this.listHost.className = 'ra-models-list ra-stack';

    const scroll = document.createElement('div');
    scroll.className = 'ra-view-scroll ra-scroll';
    scroll.append(this.summaryHost, this.listHost);

    root.append(toolbar, scroll);
    void this.reload();
  }

  model(): { name: string; meta: string } | undefined {
    const loaded = this.state?.loaded.LANGUAGE;
    if (loaded === undefined) return undefined;
    return {
      name: loaded.name,
      meta: loaded.parameters ?? formatSize(loaded.sizeBytes),
    };
  }

  dispose(): void {
    this.disposed = true;
  }

  private async reload(): Promise<void> {
    try {
      await window.runanywhere.models.refresh();
      const [models, state] = await Promise.all([
        window.runanywhere.models.list(),
        window.runanywhere.models.state(),
      ]);
      if (this.disposed) return;
      this.models = models.filter((m) => BROWSE_CATEGORIES.has(m.category));
      this.state = state;
      this.renderSummary();
      this.renderList();
      this.context.refreshChrome();
    } catch (error) {
      log.error('reload failed', error);
      showError(error, 'Could not list models');
    }
  }

  private renderSummary(): void {
    const state = this.state;
    if (state === null) {
      this.summaryHost.replaceChildren();
      return;
    }

    const card = document.createElement('div');
    card.className = 'ra-card ra-models-device';
    const used = formatSize(state.storageUsedBytes);
    const free = formatSize(state.storageFreeBytes);
    const loadedCount = Object.keys(state.loaded).length;
    card.innerHTML =
      `<div class="ra-type-section-title">On this device</div>` +
      `<p class="ra-type-secondary">` +
      `${escapeHtml(used)} used · ${escapeHtml(free)} free` +
      (loadedCount > 0 ? ` · ${loadedCount} loaded` : '') +
      `</p>`;
    this.summaryHost.replaceChildren(card);
  }

  private filtered(): ModelInfo[] {
    if (this.search.length === 0) return this.models;
    return this.models.filter(
      (m) =>
        m.name.toLowerCase().includes(this.search) ||
        m.id.toLowerCase().includes(this.search) ||
        m.category.toLowerCase().includes(this.search),
    );
  }

  private renderList(): void {
    const models = this.filtered();
    if (models.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'ra-type-secondary';
      empty.textContent =
        this.search.length > 0 ? 'No models match that search.' : 'No models in the catalog yet.';
      this.listHost.replaceChildren(empty);
      return;
    }

    const groups = new Map<string, ModelInfo[]>();
    for (const model of models) {
      const list = groups.get(model.category) ?? [];
      list.push(model);
      groups.set(model.category, list);
    }

    const fragment = document.createDocumentFragment();
    for (const [category, rows] of groups) {
      const section = document.createElement('section');
      section.className = 'ra-models-section';
      const heading = document.createElement('h3');
      heading.className = 'ra-type-section-title';
      heading.textContent = categoryLabel(category);
      section.append(heading);

      for (const model of rows) {
        section.append(this.buildRow(model));
      }
      fragment.append(section);
    }
    this.listHost.replaceChildren(fragment);
  }

  private buildRow(model: ModelInfo): HTMLElement {
    const row = document.createElement('article');
    row.className = 'ra-model-row';
    row.dataset.id = model.id;

    const loadedId = this.state?.loaded[model.category as keyof ModelsState['loaded']]?.id;
    const isLoaded = loadedId === model.id;
    const busy = this.inflight.has(model.id);
    const progress = this.progressControls.get(model.id);

    const main = document.createElement('div');
    main.className = 'ra-model-row-main';

    const title = document.createElement('div');
    title.className = 'ra-model-row-title';
    title.innerHTML =
      `<strong class="ra-type-card-title ra-selectable">${escapeHtml(model.name)}</strong>` +
      `<span class="ra-type-caption ra-selectable">${escapeHtml(model.id)}</span>`;

    const meta = document.createElement('div');
    meta.className = 'ra-model-row-meta';
    const badges: string[] = [];
    if (model.parameters !== undefined) {
      badges.push(`<span class="ra-badge">${escapeHtml(model.parameters)}</span>`);
    }
    if (model.sizeBytes > 0) {
      badges.push(`<span class="ra-badge">${escapeHtml(formatSize(model.sizeBytes))}</span>`);
    }
    if (isLoaded) badges.push('<span class="ra-badge" data-tone="success">Loaded</span>');
    else if (model.downloaded) badges.push('<span class="ra-badge" data-tone="success">Downloaded</span>');
    meta.innerHTML = badges.join('');

    main.append(title, meta);
    if (progress !== undefined) main.append(progress.element);

    const actions = document.createElement('div');
    actions.className = 'ra-model-row-actions';

    const action = this.primaryAction(model, isLoaded, busy || progress !== undefined);
    const button = document.createElement('button');
    button.type = 'button';
    button.className = action === 'unload' ? 'ra-btn-secondary' : 'ra-btn-primary';
    button.disabled = action === 'busy';
    button.textContent = actionLabel(action);
    button.addEventListener('click', () => void this.runAction(model, action));
    actions.append(button);

    row.append(main, actions);
    return row;
  }

  private primaryAction(model: ModelInfo, isLoaded: boolean, busy: boolean): RowAction {
    if (busy) return 'busy';
    if (isLoaded) return 'unload';
    if (model.downloaded) return 'load';
    return 'download';
  }

  private async runAction(model: ModelInfo, action: RowAction): Promise<void> {
    if (action === 'busy') return;
    switch (action) {
      case 'download':
        await this.download(model.id);
        return;
      case 'load':
        await this.load(model);
        return;
      case 'unload':
        await this.unload(model.id);
        return;
      default: {
        const _exhaustive: never = action;
        void _exhaustive;
      }
    }
  }

  private async download(id: string): Promise<void> {
    if (this.inflight.has(id)) return;
    this.inflight.add(id);
    const control = createDownloadProgress({ phase: 'queued' });
    this.progressControls.set(id, control);
    this.renderList();

    try {
      for await (const event of window.runanywhere.models.download(id)) {
        if (this.disposed) break;
        this.applyDownloadEvent(id, event, control);
        if (event.type === 'completed' || event.type === 'failed' || event.type === 'cancelled') break;
      }
    } catch (error) {
      log.error('download failed', error);
      showError(error, 'Download failed');
    } finally {
      this.inflight.delete(id);
      this.progressControls.delete(id);
      await this.reload();
    }
  }

  private applyDownloadEvent(
    id: string,
    event: DownloadEvent,
    control: DownloadProgressControl,
  ): void {
    switch (event.type) {
      case 'started':
        control.update({ phase: 'queued' });
        return;
      case 'progress':
        control.update({
          phase: 'downloading',
          fraction: event.snapshot.fraction,
          bytesDone: event.snapshot.bytesDone,
          bytesTotal: event.snapshot.bytesTotal > 0 ? event.snapshot.bytesTotal : undefined,
          bytesPerSecond: event.snapshot.bytesPerSecond,
          etaSeconds: event.snapshot.etaSeconds,
          currentFileIndex:
            event.snapshot.totalFiles > 1 ? event.snapshot.currentFileIndex + 1 : undefined,
          totalFiles: event.snapshot.totalFiles > 1 ? event.snapshot.totalFiles : undefined,
          label: event.snapshot.file,
        });
        return;
      case 'verifying':
        control.update({ phase: 'verifying' });
        return;
      case 'extracting':
        control.update({ phase: 'extracting' });
        return;
      case 'completed':
        this.progressControls.delete(id);
        showToast(`${event.model.name} downloaded`, 'success');
        return;
      case 'failed':
        this.progressControls.delete(id);
        showError(event.error.message, 'Download failed');
        return;
      case 'cancelled':
        this.progressControls.delete(id);
        showToast('Download cancelled');
        return;
      default: {
        const _exhaustive: never = event;
        void _exhaustive;
      }
    }
  }

  private async load(model: ModelInfo): Promise<void> {
    if (this.inflight.has(model.id)) return;
    this.inflight.add(model.id);
    this.renderList();
    try {
      await window.runanywhere.models.load(model.id);
      showToast(`${model.name} loaded`, 'success');
      if (model.category === 'LANGUAGE') {
        await saveAppSettings({ models: { llm: model.id } });
      }
    } catch (error) {
      log.error('load failed', error);
      showError(error, 'Could not load model');
    } finally {
      this.inflight.delete(model.id);
      await this.reload();
    }
  }

  private async unload(id: string): Promise<void> {
    if (this.inflight.has(id)) return;
    this.inflight.add(id);
    this.renderList();
    try {
      await window.runanywhere.models.unload(id);
      showToast('Model unloaded');
    } catch (error) {
      log.error('unload failed', error);
      showError(error, 'Could not unload model');
    } finally {
      this.inflight.delete(id);
      await this.reload();
    }
  }
}

function categoryLabel(category: string): string {
  switch (category) {
    case 'LANGUAGE':
      return 'Language';
    case 'VISION':
      return 'Vision';
    case 'SPEECH_TO_TEXT':
      return 'Speech to text';
    case 'TEXT_TO_SPEECH':
      return 'Text to speech';
    case 'EMBEDDING':
      return 'Embeddings';
    case 'DIARIZATION':
      return 'Diarization';
    case 'SEGMENTATION':
      return 'Segmentation';
    case 'VOICE_ACTIVITY':
      return 'Voice activity';
    default:
      return category;
  }
}

function actionLabel(action: RowAction): string {
  switch (action) {
    case 'download':
      return 'Download';
    case 'load':
      return 'Load';
    case 'unload':
      return 'Unload';
    case 'busy':
      return 'Working…';
    default: {
      const _exhaustive: never = action;
      return _exhaustive;
    }
  }
}
