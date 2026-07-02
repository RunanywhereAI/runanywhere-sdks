import { WasmWorkerHost, registerHost, unregisterHost, type Capability } from '@runanywhere/web/internal';

const CAPABILITIES: Capability[] = ['llm', 'vlm', 'llamacpp'];

let host: WasmWorkerHost | null = null;

export interface LlamaCppRegisterOptions {
  wasmUrl?: string;
}

export const LlamaCPP = {
  async register(options: LlamaCppRegisterOptions = {}): Promise<void> {
    if (host) return;
    const wasmJsUrl = options.wasmUrl ?? new URL('../wasm/racommons-llamacpp.js', import.meta.url).href;
    host = new WasmWorkerHost(
      () => new Worker(new URL('./worker.js', import.meta.url), { type: 'module' }),
      { moduleId: 'llamacpp', wasmJsUrl, registerFns: ['rac_backend_llamacpp_register'] },
    );
    await host.ensureReady();
    registerHost(CAPABILITIES, host);
  },

  unregister(): void {
    if (!host) return;
    unregisterHost(host);
    host.shutdown();
    host = null;
  },
};
