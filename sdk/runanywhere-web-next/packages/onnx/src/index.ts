import { WasmWorkerHost, registerHost, unregisterHost, type Capability } from '@runanywhere/web/internal';

const CAPABILITIES: Capability[] = ['stt', 'tts', 'vad', 'embedding', 'onnx', 'sherpa', 'rag'];

let host: WasmWorkerHost | null = null;

export interface OnnxRegisterOptions {
  wasmUrl?: string;
}

export const ONNX = {
  async register(options: OnnxRegisterOptions = {}): Promise<void> {
    if (host) return;
    const wasmJsUrl = options.wasmUrl ?? new URL('../wasm/racommons-onnx-sherpa.js', import.meta.url).href;
    host = new WasmWorkerHost(
      () => new Worker(new URL('./worker.js', import.meta.url), { type: 'module' }),
      {
        moduleId: 'onnx',
        wasmJsUrl,
        // llamacpp is registered so RAG can create its in-session LLM service in
        // this worker (retrieval + generation together). 'llm'/'vlm' stay off
        // CAPABILITIES so app-level LLM/VLM routing still targets the dedicated
        // llamacpp worker; the LLM here is used only inside the RAG pipeline.
        registerFns: ['rac_backend_onnx_register', 'rac_backend_sherpa_register', 'rac_backend_llamacpp_register'],
      },
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
