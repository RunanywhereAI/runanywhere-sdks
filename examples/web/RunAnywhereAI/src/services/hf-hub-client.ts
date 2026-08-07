/**
 * Hugging Face Hub REST client — example-app helper for the "Add from Hugging
 * Face" flow. The Web SDK already resolves + downloads any HF `resolve` URL, but
 * it has no *search* API, so this thin `fetch` client calls the public
 * huggingface.co REST endpoints directly for repo search and file listing.
 *
 * Scope: discovery only. Registration + download stay in the SDK
 * (`RunAnywhere.models.register` / `models.download`). No secrets are persisted; an
 * optional token is attached to the request only for the lifetime of the call.
 *
 * Cross-app contract (see thoughts/shared/plans/add_from_huggingface_example_apps.md):
 *   - Search GGUF repos:
 *     GET /api/models?search={q}&filter=gguf&sort=downloads&direction=-1&limit=25&expand[]=gguf
 *   - List files + sizes:
 *     GET /api/models/{repoId}/tree/main?recursive=true
 */

const HF_API_BASE = 'https://huggingface.co/api';
const SEARCH_LIMIT = 25;

/** A single repo hit from the HF model search endpoint. */
export interface HfModelSummary {
  id: string;
  downloads: number;
  likes: number;
  /**
   * Parameter count read from `gguf.total`. Optional because the Hub only
   * publishes it for repos whose GGUF header it managed to parse — a missing
   * value must render as *no badge*, never as "0" or "unknown".
   */
  params?: number;
}

/**
 * One entry in the curated sub-1B suggestion list.
 *
 * Authored data, not an API response, which is why it carries no download or
 * like count: those would go stale silently on a hardcoded row. Live counts
 * belong on search results, where they come from the Hub on every request.
 */
export interface HfSuggestedModel {
  repoId: string;
  /** Vendor-style short name, e.g. `SmolLM2 135M`. */
  title: string;
  /** Measured parameter count — the number the "under 1B" claim was checked against. */
  params: number;
  /** One line of consumer language explaining when to pick this one. */
  blurb: string;
}

/**
 * Sub-1B GGUF models, ascending by measured parameter count.
 *
 * WHY A CURATED LIST AND NOT A LIVE QUERY. All of the following was established
 * against the live Hub REST API:
 *
 *   - `gguf.total` is the only readable parameter count, and reading it needs
 *     `expand[]=gguf`, which inflates the payload 4-14x because it embeds the
 *     whole Jinja `chat_template`. There is no cheap sub-field expand —
 *     `expand[]=gguf.total` is rejected outright.
 *   - "Fetch the top N by downloads, then filter under 1B" does not work: only
 *     3 of the top 100 GGUF text-generation repos are sub-1B. The head of that
 *     list is 27B-284B models, so the panel would come back nearly empty.
 *   - Size-token searches (`search=135M`, `search=0.6B`) do surface small
 *     repos but leak other modalities — `0.6B` returns parakeet/nemotron ASR
 *     repos alongside chat models.
 *
 * A curated list is instant, deterministic, needs no network on open, and
 * cannot render an empty panel. The counts below are the measured `gguf.total`
 * for each repo, so what the badge shows is exactly what was verified.
 *
 * `unsloth/Llama-3.2-1B-Instruct-GGUF` is 1,235,814,432 params — over the line,
 * deliberately excluded.
 *
 * The context window is not a field here: every blurb that has a notable
 * context already says so in words, and a second badge repeating it would be
 * noise on a four-line tile.
 */
export const HF_SUGGESTED_GGUF_MODELS: readonly HfSuggestedModel[] = [
  {
    repoId: 'unsloth/SmolLM2-135M-Instruct-GGUF',
    title: 'SmolLM2 135M',
    params: 134_515_008,
    blurb: 'The smallest useful chat model. Downloads in seconds.',
  },
  {
    repoId: 'unsloth/gemma-3-270m-it-GGUF',
    title: 'Gemma 3 270M',
    params: 268_098_176,
    blurb: "Google's smallest instruction model, with a 32K context.",
  },
  {
    repoId: 'LiquidAI/LFM2-350M-GGUF',
    title: 'LFM2 350M',
    params: 354_483_968,
    blurb: 'A 128K context in a tiny model — good for long documents.',
  },
  {
    repoId: 'HuggingFaceTB/SmolLM2-360M-Instruct-GGUF',
    title: 'SmolLM2 360M',
    params: 361_821_120,
    blurb: 'More capable than 135M, still quick on any device.',
  },
  {
    repoId: 'unsloth/Qwen3-0.6B-GGUF',
    title: 'Qwen3 0.6B',
    params: 596_049_920,
    blurb: 'A strong all-rounder for its size, with a 40K context.',
  },
  {
    repoId: 'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
    title: 'Qwen2.5 0.5B',
    params: 630_167_424,
    blurb: 'Widely used, dependable general chat.',
  },
  {
    repoId: 'LiquidAI/LFM2-700M-GGUF',
    title: 'LFM2 700M',
    params: 742_489_344,
    blurb: 'The long-context option, with more room to reason.',
  },
  {
    repoId: 'ggml-org/gemma-3-1b-it-GGUF',
    title: 'Gemma 3 1B',
    params: 999_885_952,
    blurb: 'The most capable model still under 1B.',
  },
];

/**
 * Render a parameter count as a badge string — the same rule in all four apps.
 *
 * The `min(999, …)` floor is load-bearing, not defensive: Gemma 3 1B's
 * 999,885,952 rounds to 1000, and a badge reading "1000M" directly under a
 * header that says "All under 1B parameters." contradicts itself on screen.
 * Capping keeps it both accurate and consistent; every other entry rounds to
 * the vendor's own number (135M, 268M, 362M, 596M, 630M, 742M).
 */
export function formatParameterCount(params: number): string {
  if (params >= 1_000_000_000) return `${(params / 1_000_000_000).toFixed(1)}B`;
  return `${Math.min(999, Math.round(params / 1_000_000))}M`;
}

/** A single downloadable GGUF file inside a repo, with a friendly quant label. */
export interface HfRepoFile {
  path: string;
  sizeBytes: number;
  quantLabel: string;
}

/** Build the canonical resolve URL for a repo file (single-file GGUF). */
export function hfResolveUrl(repoId: string, path: string): string {
  return `https://huggingface.co/${repoId}/resolve/main/${path}`;
}

/**
 * Search GGUF repos, most-downloaded first. Returns `[]` for a blank query so
 * callers can render an idle state without a network round-trip.
 */
export async function searchGgufModels(
  query: string,
  token?: string,
): Promise<HfModelSummary[]> {
  const trimmed = query.trim();
  if (!trimmed) return [];

  // `expand[]=gguf` is what makes `gguf.total` — the parameter count — readable,
  // and it is the number the user is actually shopping on. It costs a heavier
  // payload (the block embeds the repo's whole chat template) but it is paid
  // once per keystroke-debounced search, on a list of at most 25 rows.
  const url =
    `${HF_API_BASE}/models?search=${encodeURIComponent(trimmed)}`
    + `&filter=gguf&sort=downloads&direction=-1&limit=${SEARCH_LIMIT}&expand[]=gguf`;

  const payload = await fetchJson(url, token);
  if (!Array.isArray(payload)) return [];

  const results: HfModelSummary[] = [];
  for (const item of payload) {
    const summary = toModelSummary(item);
    if (summary) results.push(summary);
  }
  return results;
}

/**
 * List the `.gguf` files in a repo with their real (LFS) byte sizes and a
 * derived quantization label. Non-file and non-GGUF tree entries are dropped.
 */
export async function listGgufFiles(
  repoId: string,
  token?: string,
): Promise<HfRepoFile[]> {
  const url = `${HF_API_BASE}/models/${repoId}/tree/main?recursive=true`;
  const payload = await fetchJson(url, token);
  if (!Array.isArray(payload)) return [];

  const files: HfRepoFile[] = [];
  for (const item of payload) {
    const file = toRepoFile(item);
    if (file) files.push(file);
  }
  // Smallest first — the most WASM-friendly quant sits at the top.
  return files.sort((a, b) => a.sizeBytes - b.sizeBytes);
}

// ---------------------------------------------------------------------------
// Internal — fetch + narrowing (external JSON is `unknown` until validated)
// ---------------------------------------------------------------------------

async function fetchJson(url: string, token?: string): Promise<unknown> {
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (token && token.trim()) {
    headers.Authorization = `Bearer ${token.trim()}`;
  }
  const response = await fetch(url, { headers });
  if (!response.ok) {
    throw new Error(`Hugging Face request failed (${response.status} ${response.statusText})`);
  }
  return response.json() as Promise<unknown>;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function asNumber(value: unknown): number {
  return typeof value === 'number' && Number.isFinite(value) ? value : 0;
}

function toModelSummary(item: unknown): HfModelSummary | null {
  if (!isRecord(item)) return null;
  const id = item.id;
  if (typeof id !== 'string' || id.length === 0) return null;
  // The `gguf` block is absent whenever the Hub could not parse the repo's GGUF
  // header, and `asNumber` collapses anything non-finite to 0. Both cases land
  // on `undefined`, which the row renders as no badge — degrading to silence is
  // correct here, showing "0M" would be a lie.
  const gguf = isRecord(item.gguf) ? item.gguf : null;
  const params = gguf ? asNumber(gguf.total) : 0;
  return {
    id,
    downloads: asNumber(item.downloads),
    likes: asNumber(item.likes),
    params: params > 0 ? params : undefined,
  };
}

function toRepoFile(item: unknown): HfRepoFile | null {
  if (!isRecord(item)) return null;
  if (item.type !== 'file') return null;
  const path = item.path;
  if (typeof path !== 'string' || !path.toLowerCase().endsWith('.gguf')) return null;

  const lfs = isRecord(item.lfs) ? item.lfs : null;
  const sizeBytes = lfs ? asNumber(lfs.size) : asNumber(item.size);

  return {
    path,
    sizeBytes: sizeBytes > 0 ? sizeBytes : asNumber(item.size),
    quantLabel: deriveQuantLabel(path),
  };
}

/**
 * Derive a human quant label from a GGUF filename, e.g.
 * `Qwen3-0.6B-Q4_K_M.gguf` → `Q4_K_M`, `model.IQ4_XS.gguf` → `IQ4_XS`.
 * Falls back to `GGUF` when no known quant token is present.
 */
function deriveQuantLabel(path: string): string {
  const base = path.split('/').pop() ?? path;
  const match = base.match(/(IQ\d+_[A-Z]+|Q\d+(?:_[A-Z0-9]+)*|BF16|F16|F32)/i);
  return match ? match[1].toUpperCase() : 'GGUF';
}
