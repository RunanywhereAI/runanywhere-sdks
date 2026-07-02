import { ModelArtifactType, ModelInfo, ModelLoadRequest } from '@runanywhere/proto-ts/model_types';
import { catalog, loadableEntries, type CatalogEntry } from '../catalog';
import type { Modality, ModelItem } from '../types';

function toItem(e: CatalogEntry): ModelItem {
  return { id: e.id, name: e.name, meta: e.meta, state: 'available', progress: 0 };
}

function buildModelInfo(e: CatalogEntry): ModelInfo {
  const base = {
    id: e.id,
    name: e.name,
    category: e.category,
    format: e.format,
    framework: e.framework,
    downloadUrl: e.downloadUrl,
    downloadSizeBytes: e.downloadSizeBytes,
    memoryRequiredBytes: e.memoryRequiredBytes,
    contextLength: e.contextLength ?? 0,
    supportsThinking: e.supportsThinking ?? false,
    ...(e.artifactType != null ? { artifactType: e.artifactType } : {}),
  };
  if (!e.files || e.files.length === 0) return ModelInfo.fromPartial(base);

  const descriptors = e.files.map((f) => ({
    url: f.url,
    filename: f.filename,
    role: f.role,
    sizeBytes: f.sizeBytes,
    isRequired: true,
  }));
  return ModelInfo.fromPartial({
    ...base,
    artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_MULTI_FILE,
    multiFile: { files: descriptors },
    expectedFiles: { files: descriptors, rootDirectory: e.id, requiredPatterns: [], optionalPatterns: [] },
  });
}

class ModelsStore {
  registered = $state(false);
  loadedLlmId = $state<string | null>(null);
  loadedVlmId = $state<string | null>(null);
  loadedEmbeddingId = $state<string | null>(null);
  loadedTtsId = $state<string | null>(null);
  loadedSttId = $state<string | null>(null);
  llm = $state<ModelItem[]>(catalog.llm.map(toItem));
  vlm = $state<ModelItem[]>(catalog.vlm.filter((e) => e.loadable).map(toItem));
  embedding = $state<ModelItem[]>(catalog.embedding.filter((e) => e.loadable).map(toItem));
  tts = $state<ModelItem[]>(catalog.tts.filter((e) => e.loadable).map(toItem));
  stt = $state<ModelItem[]>(catalog.stt.filter((e) => e.loadable).map(toItem));

  private get lists(): ModelItem[][] {
    return [this.llm, this.vlm, this.embedding, this.tts, this.stt];
  }

  private def(id: string): CatalogEntry | undefined {
    return loadableEntries.find((e) => e.id === id);
  }

  private listFor(modality: Modality): ModelItem[] {
    if (modality === 'vlm') return this.vlm;
    if (modality === 'embedding') return this.embedding;
    if (modality === 'tts') return this.tts;
    if (modality === 'stt') return this.stt;
    return this.llm;
  }

  private stateOf(id: string): ModelItem['state'] {
    for (const list of this.lists) {
      const item = list.find((m) => m.id === id);
      if (item) return item.state;
    }
    return 'available';
  }

  private patch(id: string, next: Partial<ModelItem>): void {
    for (const list of this.lists) {
      const i = list.findIndex((m) => m.id === id);
      if (i >= 0) { list[i] = { ...list[i], ...next }; return; }
    }
  }

  private setLoaded(modality: Modality, id: string): void {
    for (const m of this.listFor(modality)) {
      if (m.state === 'loaded' && m.id !== id) this.patch(m.id, { state: 'downloaded' });
    }
    this.patch(id, { state: 'loaded', progress: 1 });
    if (modality === 'vlm') this.loadedVlmId = id;
    else if (modality === 'embedding') this.loadedEmbeddingId = id;
    else if (modality === 'tts') this.loadedTtsId = id;
    else if (modality === 'stt') this.loadedSttId = id;
    else this.loadedLlmId = id;
  }

  // Reflect a component-based model (TTS/STT) as loaded in the list. These
  // load outside the LLM/embedding `load()` path (they create a component
  // handle owned by their feature store), so the store marks state here.
  markLoaded(modality: Modality, id: string): void {
    this.setLoaded(modality, id);
  }

  private async ensureEngine(): Promise<void> {
    const { sdk } = await import('./sdk.svelte');
    await sdk.boot();
    if (!sdk.ready) throw new Error(sdk.message || 'Engine failed to start');
  }

  async registerAll(): Promise<void> {
    if (this.registered) return;
    const { RunAnywhere } = await import('@runanywhere/web');
    for (const e of loadableEntries) {
      try {
        await RunAnywhere.registerModel(buildModelInfo(e));
      } catch (err) {
        console.warn('[models] register failed', e.id, err);
      }
    }
    this.registered = true;
  }

  async refreshDownloaded(): Promise<void> {
    const { RunAnywhere } = await import('@runanywhere/web');
    for (const e of loadableEntries) {
      if (this.stateOf(e.id) !== 'available') continue;
      try {
        if (await RunAnywhere.isModelDownloaded(e.id, e.framework)) this.patch(e.id, { state: 'downloaded' });
      } catch (err) {
        console.warn('[models] discovery failed', e.id, err);
      }
    }
  }

  async hydrateDownloaded(): Promise<void> {
    const { RunAnywhere } = await import('@runanywhere/web');
    for (const e of loadableEntries) {
      if (this.stateOf(e.id) !== 'downloaded') continue;
      try {
        await RunAnywhere.downloadModel(e.id, e.framework);
      } catch (err) {
        console.warn('[models] hydrate failed', e.id, err);
      }
    }
  }

  async download(id: string): Promise<void> {
    const e = this.def(id);
    if (!e) return;
    this.patch(id, { state: 'downloading', progress: 0 });
    try {
      await this.ensureEngine();
      const { RunAnywhere } = await import('@runanywhere/web');
      await RunAnywhere.downloadModel(id, e.framework, (p) => {
        if (p.overallProgress > 0) this.patch(id, { progress: p.overallProgress });
      });
      this.patch(id, { state: 'downloaded', progress: 1 });
    } catch (err) {
      this.patch(id, { state: 'available', progress: 0 });
      throw err;
    }
  }

  async load(id: string): Promise<void> {
    const e = this.def(id);
    if (!e) return;
    const prev = this.stateOf(id);
    this.patch(id, { state: 'downloading', progress: 0 });
    try {
      await this.ensureEngine();
      const { RunAnywhere } = await import('@runanywhere/web');
      const req = ModelLoadRequest.fromPartial({
        modelId: id,
        category: e.category,
        framework: e.framework,
        forceReload: false,
        validateAvailability: true,
      });
      const result = await RunAnywhere.downloadAndLoad(req, (p) => {
        if (p.overallProgress > 0) this.patch(id, { progress: p.overallProgress });
      });
      if (!result?.success) throw new Error(result?.errorMessage || 'Model load failed');
      this.setLoaded(e.modality, id);
    } catch (err) {
      console.error('[models] load failed', id, err);
      this.patch(id, { state: prev === 'available' ? 'available' : 'downloaded', progress: 0 });
      throw err;
    }
  }
}

export const models = new ModelsStore();
