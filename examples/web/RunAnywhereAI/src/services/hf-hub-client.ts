/**
 * Hugging Face Hub REST client — example-app helper for the "Add from Hugging
 * Face" flow. The Web SDK already resolves + downloads any HF `resolve` URL, but
 * it has no *search* API, so this thin `fetch` client calls the public
 * huggingface.co REST endpoints directly for repo search and file listing.
 *
 * Scope: discovery only. Registration + download stay in the SDK
 * (`RunAnywhere.registerModel` / `downloadModel`). No secrets are persisted; an
 * optional token is attached to the request only for the lifetime of the call.
 *
 * Cross-app contract (see thoughts/shared/plans/add_from_huggingface_example_apps.md):
 *   - Search GGUF repos:
 *     GET /api/models?search={q}&filter=gguf&sort=downloads&direction=-1&limit=25
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

  const url =
    `${HF_API_BASE}/models?search=${encodeURIComponent(trimmed)}`
    + `&filter=gguf&sort=downloads&direction=-1&limit=${SEARCH_LIMIT}`;

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
  return {
    id,
    downloads: asNumber(item.downloads),
    likes: asNumber(item.likes),
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
