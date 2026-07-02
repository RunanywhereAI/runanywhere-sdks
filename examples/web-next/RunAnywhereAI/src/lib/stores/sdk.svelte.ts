export type SdkStatus = 'idle' | 'initializing' | 'ready' | 'error';

export interface BackendState {
  id: string;
  label: string;
  sub: string;
  ready: boolean;
}

class SdkStore {
  status = $state<SdkStatus>('idle');
  message = $state('Bring the on-device engine online to begin.');
  backends = $state<BackendState[]>([
    { id: 'llamacpp', label: 'LlamaCpp', sub: 'LLM · VLM', ready: false },
    { id: 'onnx', label: 'ONNX · Sherpa', sub: 'STT · TTS · VAD · RAG', ready: false },
  ]);

  get busy(): boolean {
    return this.status === 'initializing';
  }

  get ready(): boolean {
    return this.status === 'ready';
  }

  private bootPromise: Promise<void> | null = null;

  boot(): Promise<void> {
    if (this.ready) return Promise.resolve();
    if (this.bootPromise) return this.bootPromise;
    this.bootPromise = this.run().finally(() => {
      this.bootPromise = null;
    });
    return this.bootPromise;
  }

  private async run(): Promise<void> {
    this.status = 'initializing';
    this.message = 'Spinning up the commons worker…';
    try {
      const { RunAnywhere } = await import('@runanywhere/web');
      const { settings } = await import('./settings.svelte');
      console.log('[sdk] init env=%s baseUrl=%s apiKey=%s', settings.environment, settings.baseUrl, settings.apiKey ? 'set' : 'empty');
      await RunAnywhere.initialize({
        environment: settings.environmentEnum,
        apiKey: settings.apiKey || undefined,
        baseUrl: settings.baseUrl || undefined,
      });

      this.message = 'Loading the LlamaCpp worker…';
      const { LlamaCPP } = await import('@runanywhere/web-llamacpp');
      await LlamaCPP.register();
      this.backends[0].ready = true;

      this.message = 'Loading the ONNX worker…';
      const { ONNX } = await import('@runanywhere/web-onnx');
      await ONNX.register();
      this.backends[1].ready = true;

      this.message = 'Registering models…';
      const { models } = await import('./models.svelte');
      await models.registerAll();
      await models.refreshDownloaded();

      this.status = 'ready';
      this.message = 'Ready — every model runs off the main thread.';

      void models.hydrateDownloaded();
    } catch (error) {
      this.status = 'error';
      this.message = error instanceof Error ? error.message : String(error);
    }
  }
}

export const sdk = new SdkStore();
