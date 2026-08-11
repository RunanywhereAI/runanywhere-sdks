/**
 * Bare-minimum RunAnywhere Web SDK harness.
 *
 * Boot the SDK, register the llama.cpp backend, then stream one completion into
 * the page. Naming a catalog model in `options.model` is all it takes: the SDK
 * downloads and loads it on first use — this app never sequences that by hand.
 */
import {
  InferenceFramework,
  ModelCategory,
  ModelFormat,
  RunAnywhere,
} from '@runanywhere/web';
import { LlamaCPP } from '@runanywhere/web-llamacpp';
import { publishReadiness, publishSDK } from './readiness';

const MODEL_ID = 'smollm2-360m-q8_0';

function element<T extends HTMLElement>(id: string): T {
  const found = document.getElementById(id);
  if (!found) throw new Error(`Missing #${id} in index.html`);
  return found as T;
}

const promptEl = element<HTMLTextAreaElement>('prompt');
const generateEl = element<HTMLButtonElement>('generate');
const statusEl = element<HTMLParagraphElement>('status');
const outputEl = element<HTMLPreElement>('output');

function setStatus(message: string): void {
  statusEl.textContent = message;
}

function describe(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** Boot order: SDK core WASM → backend WASM → background services. */
async function boot(): Promise<void> {
  publishReadiness({
    state: 'initializing-sdk',
    step: 'initializing-sdk',
    reason: 'Loading the commons WASM.',
  });
  await RunAnywhere.initialize({ environment: 'development' });
  publishSDK(RunAnywhere);

  publishReadiness({
    step: 'registering-llamacpp',
    reason: 'Loading the llama.cpp backend WASM.',
  });
  await LlamaCPP.register({ acceleration: 'auto' });
  publishReadiness({
    backend: 'registered',
    step: 'registering-catalog',
    reason: 'Backend registered; registering the app-owned catalog.',
  });

  // Deprecated no-op forwarder retained for the documented two-phase boot;
  // `initialize()` already folds both phases.
  await RunAnywhere.completeServicesInitialization();
  // The catalog is app-owned: the SDK downloads and loads a model on demand,
  // but it can only resolve ids it already knows about.
  RunAnywhere.models.register({
    id: MODEL_ID,
    name: 'SmolLM2 360M Q8_0',
    category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
    format: ModelFormat.MODEL_FORMAT_GGUF,
    url: 'https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct-GGUF/resolve/main/smollm2-360m-instruct-q8_0.gguf',
    sizeBytes: 386_404_992,
    memoryRequiredBytes: 500_000_000,
    contextLength: 2048,
  });
}

/** Stream one answer. The first run also downloads and loads the model. */
async function generate(): Promise<void> {
  const prompt = promptEl.value.trim();
  if (!prompt) return;

  generateEl.disabled = true;
  outputEl.textContent = '';
  setStatus(`Generating with ${MODEL_ID} (first run downloads the model)…`);

  let text = '';
  try {
    const events = RunAnywhere.llm.generateStream(prompt, {
      model: MODEL_ID,
      maxOutputTokens: 256,
    });
    for await (const event of events) {
      if (event.type === 'textDelta' || event.type === 'reasoningDelta') {
        text += event.text;
        outputEl.textContent = text;
      } else if (event.type === 'completed') {
        outputEl.textContent = event.result.text || text;
        setStatus(`Done — ${event.result.outputTokens} tokens at ${event.result.tokensPerSecond.toFixed(1)} tok/s.`);
      } else if (event.type === 'failed') {
        setStatus(`Generation failed: ${event.error.message}`);
      } else if (event.type === 'cancelled') {
        setStatus('Generation cancelled.');
      }
    }
  } catch (error) {
    setStatus(`Generation failed: ${describe(error)}`);
  } finally {
    generateEl.disabled = false;
  }
}

generateEl.addEventListener('click', () => { void generate(); });

boot().then(
  () => {
    generateEl.disabled = false;
    setStatus(`Ready — SDK ${RunAnywhere.version}, backend llama.cpp (${RunAnywhere.runtime.active ?? 'cpu'}).`);
    publishReadiness({
      ready: true,
      state: 'interactive',
      step: 'interactive',
      shellReady: true,
      reason: 'Prompt accepted; the model downloads and loads on first generate.',
    });
  },
  (error: unknown) => {
    const message = describe(error);
    setStatus(`Startup failed: ${message}`);
    publishReadiness({
      state: 'error',
      step: 'error',
      backend: 'unavailable',
      reason: 'SDK boot failed.',
      error: message,
    });
  },
);
