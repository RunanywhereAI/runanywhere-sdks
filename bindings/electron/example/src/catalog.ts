/**
 * THIS APP's model table — one row.
 *
 * The SDK owns the entry SHAPE (`Catalog` / `registerCatalog`); the app owns
 * WHICH models it offers, exactly as on every other platform in this repo. The
 * SDK ships no built-in table, so a generation that names an id the registry has
 * never seen fails before it reaches a backend.
 *
 * Registration is PER PROCESS and two processes here resolve models: the preload
 * (whose `initialize()` seeds the rows into the commons registry) and the forked
 * utility host (which downloads them). The host receives this module's PATH from
 * the main process and loads it with a raw `require()` — which is why nothing
 * here may import a generated proto module, and why every import below is an
 * `import type` that erases at emit.
 */
import type { Catalog } from '@runanywhere/electron';

export const CATALOG: Catalog = {
  'smollm2-360m-q8_0': {
    type: 'llm',
    files: [
      {
        url: 'https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf',
        as: 'model.gguf',
      },
    ],
    primary: 'model.gguf',
    label: 'SmolLM2 360M Q8_0',
    sizeMB: 386,
  },
};
