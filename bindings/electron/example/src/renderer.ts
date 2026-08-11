/**
 * Renderer. One prompt box, one button, one streamed answer.
 *
 * Everything reaches the SDK through `window.runanywhere`, which the SDK's own
 * preload publishes. The page never loads the native addon and never sequences a
 * download or a load: naming the model is enough.
 */
import type { GenerationEvent, RunAnywhereApi } from '@runanywhere/electron';

/**
 * What the SDK's preload publishes, narrowed to what this app uses.
 *
 * The core members are FUNCTIONS rather than the facade's getters because
 * contextBridge clones what it exposes — a getter would be read once, before
 * `initialize()` had anything to report.
 */
interface RunAnywhereBridge {
  /** Brings up the native runtime and seeds the staged catalog into commons. */
  initialize(secureDir?: string, baseDir?: string): Promise<void>;
  /** This app's staged table, read back for its ids. */
  catalog(): Readonly<Record<string, unknown>>;
  llm: RunAnywhereApi['llm'];
}

declare global {
  interface Window {
    readonly runanywhere: RunAnywhereBridge;
  }
}

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

/** The single row `src/catalog.ts` stages; the SDK fetches it on first use. */
function modelId(): string {
  const [id] = Object.keys(window.runanywhere.catalog());
  if (!id) throw new Error('the preload staged no catalog rows');
  return id;
}

function render(event: GenerationEvent): void {
  // Only the three arms this UI has something to say about; `started`, `usage`
  // and the tool arms are streamed too and simply need no rendering here.
  if (event.type === 'textDelta') {
    outputEl.textContent += event.text;
  } else if (event.type === 'completed') {
    setStatus(
      `Done — ${event.result.outputTokens} tokens at ${event.result.tokensPerSecond.toFixed(1)} tok/s.`
    );
  } else if (event.type === 'failed') {
    setStatus(`Generation failed: ${event.error.message}`);
  }
}

/** Stream one answer. The first run also downloads and loads the model. */
async function generate(): Promise<void> {
  const prompt = promptEl.value.trim();
  if (!prompt) return;

  generateEl.disabled = true;
  outputEl.textContent = '';
  setStatus('Generating (the first run downloads the model)…');

  try {
    const stream = window.runanywhere.llm.generateStream(prompt, {
      model: modelId(),
      maxOutputTokens: 128,
    });
    // contextBridge's structured clone drops symbol keys, so `for await` cannot
    // iterate a bridged stream. Drive `next()` by hand instead.
    for (;;) {
      const step = await stream.next();
      if (step.done) break;
      render(step.value);
    }
  } catch (error) {
    setStatus(`Generation failed: ${describe(error)}`);
  } finally {
    generateEl.disabled = false;
  }
}

generateEl.addEventListener('click', () => {
  void generate();
});

// `initialize()` waits for the MessagePort the main process brokers in, so there
// is nothing to sequence ahead of it.
window.runanywhere.initialize().then(
  () => {
    generateEl.disabled = false;
    setStatus('Ready.');
  },
  (error: unknown) => setStatus(`Startup failed: ${describe(error)}`)
);
