// download.ts — model download + resolution (Node-side; Node owns desktop I/O).
// Streams HTTP(S) downloads with progress + timeouts + completeness checks,
// extracts .tar.bz2 via the system tar (bsdtar ships with Windows 10+), and
// resolves a catalog id, a direct URL, a HuggingFace repo id, or a local path to
// concrete on-disk file paths, downloading if missing.
import { spawnSync } from 'child_process';
import * as crypto from 'crypto';
import * as fs from 'fs';
import * as http from 'http';
import * as https from 'https';
import * as os from 'os';
import * as path from 'path';

import { CATALOG, isCatalogId, ModelType } from './catalog';

export interface DownloadProgress {
  file: string;
  received: number;
  total: number;
  percent: number;
}

export interface ResolvedModel {
  id: string;
  type: ModelType | 'path';
  dir: string;
  primary: string;
  mmproj?: string;
}

// Idle timeouts: reset on socket activity, so they only fire on a genuinely
// stalled connection (a mid-stream reset or a half-open socket), never during a
// slow-but-steady download.
const DOWNLOAD_IDLE_MS = 60_000;
const JSON_IDLE_MS = 30_000;

export function modelsRoot(): string {
  return path.join(os.homedir(), '.runanywhere', 'models');
}

/** Does a path exist on disk? (Used to check a custom model's downloaded state.) */
export function pathExists(p: string): boolean {
  try {
    return fs.existsSync(p);
  } catch {
    return false;
  }
}

// Recursively sum file sizes under a directory (best-effort, bounded depth).
function dirSize(dir: string, depth = 0): number {
  if (depth > 4) return 0;
  let total = 0;
  try {
    for (const name of fs.readdirSync(dir)) {
      const p = path.join(dir, name);
      try {
        const st = fs.statSync(p);
        total += st.isDirectory() ? dirSize(p, depth + 1) : st.size;
      } catch {
        /* ignore unreadable entries */
      }
    }
  } catch {
    /* ignore missing dir */
  }
  return total;
}

/**
 * Downloaded state + on-disk size for every catalog model. Runs in the utility
 * host (Node), so the recursive fs walk stays off the renderer thread.
 */
export function modelStatus(): Record<string, { downloaded: boolean; sizeBytes: number }> {
  const root = modelsRoot();
  const out: Record<string, { downloaded: boolean; sizeBytes: number }> = {};
  for (const [id, entry] of Object.entries(CATALOG)) {
    const dir = path.join(root, id);
    out[id] = { downloaded: pathExists(path.join(dir, entry.primary)), sizeBytes: dirSize(dir) };
  }
  return out;
}

/**
 * Stream a URL to `dest` (following redirects), reporting byte progress. Downloads
 * to `dest + '.part'` and renames on success. If a `.part` from an interrupted
 * attempt survives, resumes it with a Range request (falls back to a full restart
 * if the server ignores Range, and finalizes on 416 when the part is already
 * complete). A failed attempt LEAVES the `.part` so the next call can resume — a
 * `.part` is only ever renamed after a completeness check, never loaded directly.
 */
export function downloadFile(
  url: string,
  dest: string,
  onProgress?: (p: DownloadProgress) => void
): Promise<void> {
  const tmp = dest + '.part';
  let startAt = 0;
  try { startAt = fs.statSync(tmp).size; } catch { startAt = 0; }
  const finalize = (resolve: () => void, reject: (e: Error) => void): void => {
    // renameSync runs outside the Promise executor's synchronous scope, so a throw
    // (Windows EPERM/EBUSY from AV/indexer, or EXDEV across volumes) would not be
    // caught — settle explicitly instead of hanging/crashing.
    try { fs.renameSync(tmp, dest); resolve(); }
    catch (e) { try { fs.rmSync(tmp, { force: true }); } catch { /* ignore */ } reject(e as Error); }
  };
  return new Promise((resolve, reject) => {
    const get = (u: string, redirects = 0): void => {
      if (redirects > 6) {
        reject(new Error('too many redirects: ' + u));
        return;
      }
      const lib = new URL(u).protocol === 'http:' ? http : https;
      const headers: Record<string, string> = { 'User-Agent': 'runanywhere-electron' };
      if (startAt > 0) headers.Range = `bytes=${startAt}-`;
      const req = lib.get(u, { headers }, (res) => {
        const code = res.statusCode ?? 0;
        if (code >= 300 && code < 400 && res.headers.location) {
          res.resume();
          get(new URL(res.headers.location, u).toString(), redirects + 1);
          return;
        }
        // 416: our `.part` already covers the whole file — just finalize it.
        if (code === 416 && startAt > 0) {
          res.resume();
          finalize(resolve, reject);
          return;
        }
        if (code !== 200 && code !== 206) {
          res.resume();
          reject(new Error(`HTTP ${code} for ${u}`));
          return;
        }
        // 206 => resuming (its content-length is the REMAINING bytes); 200 => the
        // server ignored Range, so restart from scratch (truncate the `.part`).
        const resuming = code === 206 && startAt > 0;
        const len = parseInt((res.headers['content-length'] as string) || '0', 10);
        const total = resuming ? startAt + len : len;
        let received = resuming ? startAt : 0;
        const out = fs.createWriteStream(tmp, { flags: resuming ? 'a' : 'w' });
        // res.pipe(out) does NOT forward source errors to the destination, so a
        // mid-stream TCP reset / TLS error would otherwise settle nothing and the
        // awaiting load would hang forever. Fail explicitly on either stream, and
        // KEEP the `.part` so the next attempt resumes instead of refetching.
        const fail = (e: Error): void => {
          out.destroy();
          res.destroy();
          reject(e);
        };
        res.on('error', fail);
        // A server/proxy that drops the socket mid-response may emit only 'aborted'
        // (not 'error'); catch it so the download rejects instead of hanging.
        res.on('aborted', () => fail(new Error(`connection aborted for ${u}`)));
        out.on('error', fail);
        res.on('data', (chunk: Buffer) => {
          received += chunk.length;
          onProgress?.({
            file: path.basename(dest),
            received,
            total,
            percent: total ? Math.round((100 * received) / total) : 0,
          });
        });
        res.pipe(out);
        out.on('finish', () => {
          // A clean-but-early EOF (proxy cutoff, disk-full) still fires 'finish';
          // reject on a byte-count mismatch so a truncated file is never renamed.
          if (total > 0 && received !== total) {
            fail(new Error(`incomplete download for ${u}: got ${received} of ${total} bytes`));
            return;
          }
          out.close(() => finalize(resolve, reject));
        });
      });
      req.on('error', reject);
      req.setTimeout(DOWNLOAD_IDLE_MS, () => req.destroy(new Error('download timed out: ' + u)));
    };
    get(url);
  });
}

function extractTarBz2(archive: string, destDir: string): void {
  const r = spawnSync('tar', ['-xjf', archive, '-C', destDir], { stdio: 'ignore' });
  if (r.status !== 0) throw new Error('tar extraction failed for ' + archive + ' (need bsdtar/tar on PATH)');
}

// Dedup concurrent downloads to the SAME destination. Two resolveModel calls for
// one source (e.g. a UI double-click, or an auto-load racing an explicit
// download) would otherwise open two write streams on the same `.part` file and
// corrupt it / race the rename. Callers share the first in-flight promise.
const inFlight = new Map<string, Promise<void>>();
function downloadOnce(url: string, dest: string, onProgress?: (p: DownloadProgress) => void): Promise<void> {
  const existing = inFlight.get(dest);
  if (existing) return existing;
  const p = downloadFile(url, dest, onProgress).finally(() => inFlight.delete(dest));
  inFlight.set(dest, p);
  return p;
}

const RE_URL = /^https?:\/\//i;
const RE_HF = /^[A-Za-z0-9][\w.-]*\/[A-Za-z0-9][\w.-]*(:[^\s]+)?$/;
const RE_MODEL_EXT = /\.(gguf|onnx|bin|safetensors)$/i;

/** True for a remote model source (a URL or a HuggingFace repo) vs a local path. */
export function isRemoteSource(s: string): boolean {
  if (RE_URL.test(s)) return true;
  if (!RE_HF.test(s)) return false;
  if (s.includes('\\') || /^[A-Za-z]:/.test(s)) return false; // Windows path
  // `owner/file.gguf` is a local relative path, not a HuggingFace repo id (repo
  // ids never end in a model extension). Guard the pre-`:file` part.
  if (RE_MODEL_EXT.test(s.split(':')[0])) return false;
  return !fs.existsSync(s);
}

// Model kinds whose on-disk shape is a directory (sherpa STT/TTS) or an
// ONNX+vocab pair (embedder). The remote resolver is GGUF/single-file-only, so a
// URL/HF source can't produce the right shape — reject it up front with one
// message, uniformly across every load surface (facade + RPC host).
const REMOTE_UNSUPPORTED_KINDS: Record<string, string> = {
  stt: 'speech-to-text',
  tts: 'text-to-speech',
  embedder: 'embedding',
};
export type ModelKind = 'llm' | 'vlm' | 'embedder' | 'stt' | 'tts';
export function assertRemoteSupported(idOrPath: string, kind: ModelKind): void {
  if (REMOTE_UNSUPPORTED_KINDS[kind] && isRemoteSource(idOrPath)) {
    throw new Error(
      `loading a ${REMOTE_UNSUPPORTED_KINDS[kind]} model from a URL or HuggingFace repo is not supported yet — ` +
        'use a built-in catalog id or a local path'
    );
  }
}

function sanitizeId(s: string): string {
  const cleaned = s.replace(/[^A-Za-z0-9._-]+/g, '-').slice(0, 64);
  // Trim leading/trailing '-' with a linear scan rather than /^-+|-+$/g, whose
  // per-position `-+$` backtracking is polynomial on a run of dashes (CodeQL).
  let a = 0;
  let b = cleaned.length;
  while (a < b && cleaned[a] === '-') a++;
  while (b > a && cleaned[b - 1] === '-') b--;
  return cleaned.slice(a, b) || 'model';
}
// Short digest of the full source so two distinct sources that sanitize to the
// same stem (e.g. hostA/model.gguf vs hostB/model.gguf) get distinct cache dirs
// instead of one silently serving the other's bytes.
function shortHash(s: string): string {
  return crypto.createHash('sha1').update(s).digest('hex').slice(0, 8);
}

/** GET a URL body + headers (following redirects, with an idle timeout). */
function httpText(url: string): Promise<{ headers: http.IncomingHttpHeaders; body: string }> {
  return new Promise((resolve, reject) => {
    const get = (u: string, redirects = 0): void => {
      if (redirects > 6) return reject(new Error('too many redirects: ' + u));
      const lib = new URL(u).protocol === 'http:' ? http : https;
      const req = lib.get(u, { headers: { 'User-Agent': 'runanywhere-electron', Accept: 'application/json' } }, (res) => {
        const code = res.statusCode ?? 0;
        if (code >= 300 && code < 400 && res.headers.location) {
          res.resume();
          return get(new URL(res.headers.location, u).toString(), redirects + 1);
        }
        if (code !== 200) { res.resume(); return reject(new Error(`HTTP ${code} for ${u}`)); }
        let data = '';
        res.setEncoding('utf8');
        res.on('data', (c) => (data += c));
        res.on('error', reject);
        res.on('end', () => resolve({ headers: res.headers, body: data }));
      });
      req.on('error', reject);
      req.setTimeout(JSON_IDLE_MS, () => req.destroy(new Error('request timed out: ' + u)));
    };
    get(url);
  });
}

// List every file path in a HuggingFace repo, following the tree API's
// `Link: rel="next"` pagination so a GGUF beyond the first page is still found.
async function hfFiles(repo: string): Promise<string[]> {
  const out: string[] = [];
  let url: string | undefined = `https://huggingface.co/api/models/${repo}/tree/main?recursive=1`;
  for (let page = 0; url && page < 20; page++) {
    const { headers, body } = await httpText(url);
    let tree: unknown;
    try { tree = JSON.parse(body); } catch { break; }
    if (!Array.isArray(tree)) break;
    for (const e of tree) {
      if (e && (e as { type?: string }).type === 'file' && typeof (e as { path?: unknown }).path === 'string') {
        out.push((e as { path: string }).path);
      }
    }
    const link = headers['link'];
    const m = typeof link === 'string' ? link.match(/<([^>]+)>;\s*rel="next"/) : null;
    url = m ? new URL(m[1], url).toString() : undefined;
  }
  return out;
}
function pickGguf(files: string[]): string | undefined {
  const g = files.filter((f) => /\.gguf$/i.test(f) && !/mmproj/i.test(f));
  return g.find((f) => /q4_k_m/i.test(f)) || g.find((f) => /q4_0/i.test(f)) || g.find((f) => /q8_0/i.test(f)) || g[0];
}
function pickMmproj(files: string[]): string | undefined {
  const m = files.filter((f) => /mmproj/i.test(f) && /\.gguf$/i.test(f));
  return m.find((f) => /q8_0/i.test(f)) || m[0];
}
// If `picked` is one shard of a split GGUF (…-00001-of-00003.gguf), return the
// full sorted shard set so llama.cpp gets every part (it auto-discovers the rest
// from the -00001- name); otherwise just `[picked]`.
function ggufShardSet(picked: string, files: string[]): string[] {
  const m = picked.match(/^(.*)-\d{5}-of-\d{5}\.gguf$/i);
  if (!m) return [picked];
  const stem = m[1].replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const re = new RegExp('^' + stem + '-\\d{5}-of-\\d{5}\\.gguf$', 'i');
  const set = files.filter((f) => re.test(f)).sort();
  return set.length ? set : [picked];
}

/**
 * Resolve `idOrPath` to concrete file paths, downloading if needed. Accepts a
 * catalog id, a direct http(s) URL to a model file, a HuggingFace repo id
 * (`owner/repo` or `owner/repo:file.gguf`, GGUF + any mmproj auto-resolved,
 * split GGUFs downloaded whole), or a local file path.
 */
export async function resolveModel(
  idOrPath: string,
  opts: { dir?: string; onProgress?: (p: DownloadProgress) => void } = {}
): Promise<ResolvedModel> {
  if (!isCatalogId(idOrPath)) {
    // Direct URL to a model file.
    if (RE_URL.test(idOrPath)) {
      let fname: string;
      try {
        // path.basename collapses any `../` in the URL so the write stays in `dir`.
        fname = path.basename(decodeURIComponent(new URL(idOrPath).pathname)) || 'model.bin';
      } catch {
        // new URL() / decodeURIComponent throw on a malformed URL or bad %-escape;
        // surface a clear message instead of a bare URIError/TypeError.
        throw new Error(`invalid model URL: ${idOrPath}`);
      }
      const cid = 'url-' + sanitizeId(fname.replace(/\.[^.]+$/, '')) + '-' + shortHash(idOrPath);
      const dir = path.join(opts.dir ?? modelsRoot(), cid);
      fs.mkdirSync(dir, { recursive: true });
      const dest = path.join(dir, fname);
      if (!fs.existsSync(dest)) await downloadOnce(idOrPath, dest, opts.onProgress);
      return { id: cid, type: 'path', dir, primary: dest };
    }
    // HuggingFace repo — resolve a GGUF (+ mmproj for VLMs, + shards for splits).
    if (isRemoteSource(idOrPath)) {
      const ci = idOrPath.indexOf(':'); // split on the FIRST colon only
      const repo = ci >= 0 ? idOrPath.slice(0, ci) : idOrPath;
      const explicit = ci >= 0 ? idOrPath.slice(ci + 1) : undefined;
      const files = await hfFiles(repo);
      const picked = explicit || pickGguf(files);
      if (!picked) throw new Error(`no GGUF file found in HuggingFace repo ${repo}`);
      const shards = ggufShardSet(picked, files);
      const mmproj = explicit ? undefined : pickMmproj(files);
      const cid = 'hf-' + sanitizeId(repo) + '-' + shortHash(idOrPath);
      const dir = path.join(opts.dir ?? modelsRoot(), cid);
      fs.mkdirSync(dir, { recursive: true });
      const shardNames = new Set(shards.map((g) => path.basename(g)));
      for (const g of shards) {
        const d = path.join(dir, path.basename(g));
        if (!fs.existsSync(d)) await downloadOnce(`https://huggingface.co/${repo}/resolve/main/${g}`, d, opts.onProgress);
      }
      let mmprojPath: string | undefined;
      if (mmproj) {
        // Files are flattened to their basename; if the mmproj basename collides
        // with a model shard (subfolders like model/x.gguf + mmproj/x.gguf), the
        // shard's existsSync would make us SKIP the mmproj and point at the model
        // bytes. Namespace the mmproj so it always lands in its own file.
        const mmName = path.basename(mmproj);
        mmprojPath = path.join(dir, shardNames.has(mmName) ? 'mmproj-' + mmName : mmName);
        if (!fs.existsSync(mmprojPath)) {
          await downloadOnce(`https://huggingface.co/${repo}/resolve/main/${mmproj}`, mmprojPath, opts.onProgress);
        }
      }
      return { id: cid, type: 'path', dir, primary: path.join(dir, path.basename(shards[0])), mmproj: mmprojPath };
    }
    // Local path (existing or to-be-created).
    return { id: idOrPath, type: 'path', dir: path.dirname(idOrPath), primary: idOrPath };
  }
  const entry = CATALOG[idOrPath];
  const dir = path.join(opts.dir ?? modelsRoot(), idOrPath);
  fs.mkdirSync(dir, { recursive: true });
  for (const f of entry.files) {
    const dest = path.join(dir, f.as);
    if (entry.archive) {
      // For archives, "done" means the EXTRACTED primary exists — gating on the
      // downloaded .tar.bz2 alone would skip forever after a failed/interrupted
      // extract. Download the archive if missing, then (re-)extract.
      if (fs.existsSync(path.join(dir, entry.primary))) continue;
      if (!fs.existsSync(dest)) await downloadOnce(f.url, dest, opts.onProgress);
      extractTarBz2(dest, dir);
      // The extracted tree is what we load; drop the archive so it isn't kept
      // (and double-counted by dirSize) forever.
      try { fs.rmSync(dest, { force: true }); } catch { /* leave it if locked */ }
    } else if (!fs.existsSync(dest)) {
      await downloadOnce(f.url, dest, opts.onProgress);
    }
  }
  return {
    id: idOrPath,
    type: entry.type,
    dir,
    primary: path.join(dir, entry.primary),
    mmproj: entry.mmproj ? path.join(dir, entry.mmproj) : undefined,
  };
}
