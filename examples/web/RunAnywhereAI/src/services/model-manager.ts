/**
 * Model Manager - Download, store (OPFS), and load models
 *
 * Mirrors iOS ModelManager: download from URL -> OPFS persistence ->
 * mount into Emscripten FS -> load via backend.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type ModelFramework = 'llamacpp' | 'onnx' | 'coreml';
export type ModelModality = 'text' | 'multimodal' | 'speechRecognition' | 'speechSynthesis' | 'imageGeneration';
export type ModelStatus = 'registered' | 'downloading' | 'downloaded' | 'loading' | 'loaded' | 'error';

export interface ModelInfo {
  id: string;
  name: string;
  url: string;
  framework: ModelFramework;
  modality?: ModelModality;
  memoryRequirement?: number;
  status: ModelStatus;
  downloadProgress?: number;
  error?: string;
  sizeBytes?: number;
}

type ModelChangeCallback = (models: ModelInfo[]) => void;

// ---------------------------------------------------------------------------
// Registered Models (mirroring iOS RunAnywhereAIApp.swift)
// ---------------------------------------------------------------------------

const REGISTERED_MODELS: Omit<ModelInfo, 'status'>[] = [
  // LLM models (llama.cpp)
  {
    id: 'smollm2-360m-q8_0',
    name: 'SmolLM2 360M Q8_0',
    url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
    framework: 'llamacpp',
    modality: 'text',
    memoryRequirement: 500_000_000,
  },
  {
    id: 'qwen2.5-0.5b-instruct-q6_k',
    name: 'Qwen 2.5 0.5B Q6_K',
    url: 'https://huggingface.co/Triangle104/Qwen2.5-0.5B-Instruct-Q6_K-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf',
    framework: 'llamacpp',
    modality: 'text',
    memoryRequirement: 600_000_000,
  },
  {
    id: 'lfm2-350m-q4_k_m',
    name: 'LFM2 350M Q4_K_M',
    url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf',
    framework: 'llamacpp',
    modality: 'text',
    memoryRequirement: 250_000_000,
  },
  {
    id: 'lfm2-350m-q8_0',
    name: 'LFM2 350M Q8_0',
    url: 'https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf',
    framework: 'llamacpp',
    modality: 'text',
    memoryRequirement: 400_000_000,
  },
  // STT (ONNX)
  {
    id: 'sherpa-onnx-whisper-tiny.en',
    name: 'Whisper Tiny (ONNX)',
    url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz',
    framework: 'onnx',
    modality: 'speechRecognition',
    memoryRequirement: 75_000_000,
  },
  // TTS (ONNX)
  {
    id: 'vits-piper-en_US-lessac-medium',
    name: 'Piper TTS (US English)',
    url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz',
    framework: 'onnx',
    modality: 'speechSynthesis',
    memoryRequirement: 65_000_000,
  },
  {
    id: 'vits-piper-en_GB-alba-medium',
    name: 'Piper TTS (British)',
    url: 'https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz',
    framework: 'onnx',
    modality: 'speechSynthesis',
    memoryRequirement: 65_000_000,
  },
];

// ---------------------------------------------------------------------------
// Model Manager Singleton
// ---------------------------------------------------------------------------

class ModelManagerImpl {
  private models: ModelInfo[] = [];
  private listeners: ModelChangeCallback[] = [];
  private loadedModelId: string | null = null;

  constructor() {
    this.models = REGISTERED_MODELS.map((m) => ({ ...m, status: 'registered' as ModelStatus }));
  }

  // --- Queries ---

  getModels(): ModelInfo[] {
    return [...this.models];
  }

  getModelsByModality(modality: ModelModality): ModelInfo[] {
    return this.models.filter((m) => m.modality === modality);
  }

  getModelsByFramework(framework: ModelFramework): ModelInfo[] {
    return this.models.filter((m) => m.framework === framework);
  }

  getLLMModels(): ModelInfo[] {
    return this.models.filter((m) => m.modality === 'text' || m.modality === 'multimodal');
  }

  getLoadedModel(): ModelInfo | null {
    return this.models.find((m) => m.status === 'loaded') ?? null;
  }

  getLoadedModelId(): string | null {
    return this.loadedModelId;
  }

  // --- Model lifecycle ---

  async downloadModel(modelId: string): Promise<void> {
    const model = this.findModel(modelId);
    if (!model) return;

    this.updateModel(modelId, { status: 'downloading', downloadProgress: 0 });

    try {
      const response = await fetch(model.url);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const total = Number(response.headers.get('content-length') || 0);
      const reader = response.body?.getReader();
      if (!reader) throw new Error('No response body');

      const chunks: Uint8Array[] = [];
      let received = 0;

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        chunks.push(value);
        received += value.length;
        const progress = total > 0 ? received / total : 0;
        this.updateModel(modelId, { downloadProgress: progress });
      }

      // Combine chunks
      const data = new Uint8Array(received);
      let offset = 0;
      for (const chunk of chunks) {
        data.set(chunk, offset);
        offset += chunk.length;
      }

      // Store in OPFS
      await this.storeInOPFS(modelId, data);

      this.updateModel(modelId, {
        status: 'downloaded',
        downloadProgress: 1,
        sizeBytes: received,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.updateModel(modelId, { status: 'error', error: message });
    }
  }

  async loadModel(modelId: string): Promise<boolean> {
    const model = this.findModel(modelId);
    if (!model || (model.status !== 'downloaded' && model.status !== 'registered')) return false;

    // Unload current
    if (this.loadedModelId) {
      this.updateModel(this.loadedModelId, { status: 'downloaded' });
    }

    this.updateModel(modelId, { status: 'loading' });

    try {
      // Check if model exists in OPFS
      const data = await this.loadFromOPFS(modelId);
      if (!data) {
        throw new Error('Model not downloaded');
      }

      // TODO: Mount into Emscripten FS and call rac_lifecycle_load
      // For now, simulate a successful load
      await new Promise((resolve) => setTimeout(resolve, 500));

      this.loadedModelId = modelId;
      this.updateModel(modelId, { status: 'loaded' });
      return true;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      this.updateModel(modelId, { status: 'error', error: message });
      return false;
    }
  }

  async deleteModel(modelId: string): Promise<void> {
    if (this.loadedModelId === modelId) {
      this.loadedModelId = null;
    }
    await this.deleteFromOPFS(modelId);
    this.updateModel(modelId, { status: 'registered', downloadProgress: undefined, sizeBytes: undefined });
  }

  // --- OPFS Storage ---

  private async getOPFSRoot(): Promise<FileSystemDirectoryHandle> {
    return navigator.storage.getDirectory();
  }

  private async storeInOPFS(modelId: string, data: Uint8Array): Promise<void> {
    try {
      const root = await this.getOPFSRoot();
      const modelsDir = await root.getDirectoryHandle('models', { create: true });
      const fileHandle = await modelsDir.getFileHandle(modelId, { create: true });
      const writable = await fileHandle.createWritable();
      await writable.write(data);
      await writable.close();
    } catch {
      console.warn('OPFS not available, model stored in memory only');
    }
  }

  private async loadFromOPFS(modelId: string): Promise<Uint8Array | null> {
    try {
      const root = await this.getOPFSRoot();
      const modelsDir = await root.getDirectoryHandle('models');
      const fileHandle = await modelsDir.getFileHandle(modelId);
      const file = await fileHandle.getFile();
      const buffer = await file.arrayBuffer();
      return new Uint8Array(buffer);
    } catch {
      return null;
    }
  }

  private async deleteFromOPFS(modelId: string): Promise<void> {
    try {
      const root = await this.getOPFSRoot();
      const modelsDir = await root.getDirectoryHandle('models');
      await modelsDir.removeEntry(modelId);
    } catch {
      // File may not exist
    }
  }

  async getStorageInfo(): Promise<{ modelCount: number; totalSize: number; available: number }> {
    let modelCount = 0;
    let totalSize = 0;
    try {
      const root = await this.getOPFSRoot();
      const modelsDir = await root.getDirectoryHandle('models');
      for await (const entry of (modelsDir as any).values()) {
        if (entry.kind === 'file') {
          modelCount++;
          const file = await entry.getFile();
          totalSize += file.size;
        }
      }
    } catch {
      // OPFS may not exist yet
    }

    let available = 0;
    try {
      const estimate = await navigator.storage.estimate();
      available = (estimate.quota ?? 0) - (estimate.usage ?? 0);
    } catch {
      // storage API may not be available
    }

    return { modelCount, totalSize, available };
  }

  // --- Subscriptions ---

  onChange(callback: ModelChangeCallback): () => void {
    this.listeners.push(callback);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== callback);
    };
  }

  // --- Internals ---

  private findModel(id: string): ModelInfo | undefined {
    return this.models.find((m) => m.id === id);
  }

  private updateModel(id: string, patch: Partial<ModelInfo>): void {
    this.models = this.models.map((m) => (m.id === id ? { ...m, ...patch } : m));
    this.notifyListeners();
  }

  private notifyListeners(): void {
    for (const listener of this.listeners) {
      listener(this.getModels());
    }
  }
}

export const ModelManager = new ModelManagerImpl();
