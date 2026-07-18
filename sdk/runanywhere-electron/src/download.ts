// download.ts — model download + resolution (Node-side; Node owns desktop I/O).
// Streams HTTP(S) downloads with progress, extracts .tar.bz2 via the system tar
// (bsdtar ships with Windows 10+), and resolves a catalog id (or a local path)
// to concrete on-disk file paths, downloading if missing.
import { spawnSync } from 'child_process';
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

export function modelsRoot(): string {
  return path.join(os.homedir(), '.runanywhere', 'models');
}

/** Stream a URL to `dest` (following redirects), reporting byte progress. */
export function downloadFile(
  url: string,
  dest: string,
  onProgress?: (p: DownloadProgress) => void
): Promise<void> {
  return new Promise((resolve, reject) => {
    const get = (u: string, redirects = 0): void => {
      if (redirects > 6) {
        reject(new Error('too many redirects: ' + u));
        return;
      }
      const lib = new URL(u).protocol === 'http:' ? http : https;
      lib
        .get(u, { headers: { 'User-Agent': 'runanywhere-electron' } }, (res) => {
          const code = res.statusCode ?? 0;
          if (code >= 300 && code < 400 && res.headers.location) {
            res.resume();
            get(new URL(res.headers.location, u).toString(), redirects + 1);
            return;
          }
          if (code !== 200) {
            res.resume();
            reject(new Error(`HTTP ${code} for ${u}`));
            return;
          }
          const total = parseInt((res.headers['content-length'] as string) || '0', 10);
          let received = 0;
          const tmp = dest + '.part';
          const out = fs.createWriteStream(tmp);
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
          out.on('finish', () => out.close(() => {
            fs.renameSync(tmp, dest);
            resolve();
          }));
          out.on('error', reject);
        })
        .on('error', reject);
    };
    get(url);
  });
}

function extractTarBz2(archive: string, destDir: string): void {
  const r = spawnSync('tar', ['-xjf', archive, '-C', destDir], { stdio: 'ignore' });
  if (r.status !== 0) throw new Error('tar extraction failed for ' + archive + ' (need bsdtar/tar on PATH)');
}

const RE_URL = /^https?:\/\//i;
const RE_HF = /^[A-Za-z0-9][\w.-]*\/[A-Za-z0-9][\w.-]*(:[^\s]+)?$/;

/** True for a remote model source (a URL or a HuggingFace repo) vs a local path. */
export function isRemoteSource(s: string): boolean {
  if (RE_URL.test(s)) return true;
  return RE_HF.test(s) && !s.includes('\\') && !/^[A-Za-z]:/.test(s) && !fs.existsSync(s);
}

function sanitizeId(s: string): string {
  return s.replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 64) || 'model';
}

/** GET a JSON body (following redirects) — used for the HuggingFace file tree. */
function httpGetJson(url: string): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const get = (u: string, redirects = 0): void => {
      if (redirects > 6) return reject(new Error('too many redirects: ' + u));
      const lib = new URL(u).protocol === 'http:' ? http : https;
      lib
        .get(u, { headers: { 'User-Agent': 'runanywhere-electron', Accept: 'application/json' } }, (res) => {
          const code = res.statusCode ?? 0;
          if (code >= 300 && code < 400 && res.headers.location) {
            res.resume();
            return get(new URL(res.headers.location, u).toString(), redirects + 1);
          }
          if (code !== 200) { res.resume(); return reject(new Error(`HTTP ${code} for ${u}`)); }
          let data = '';
          res.setEncoding('utf8');
          res.on('data', (c) => (data += c));
          res.on('end', () => { try { resolve(JSON.parse(data)); } catch (e) { reject(e); } });
        })
        .on('error', reject);
    };
    get(url);
  });
}

async function hfFiles(repo: string): Promise<string[]> {
  const tree = await httpGetJson(`https://huggingface.co/api/models/${repo}/tree/main?recursive=1`);
  return Array.isArray(tree)
    ? tree.filter((e) => (e as { type?: string }).type === 'file').map((e) => (e as { path: string }).path)
    : [];
}
function pickGguf(files: string[]): string | undefined {
  const g = files.filter((f) => /\.gguf$/i.test(f) && !/mmproj/i.test(f));
  return g.find((f) => /q4_k_m/i.test(f)) || g.find((f) => /q4_0/i.test(f)) || g.find((f) => /q8_0/i.test(f)) || g[0];
}
function pickMmproj(files: string[]): string | undefined {
  const m = files.filter((f) => /mmproj/i.test(f) && /\.gguf$/i.test(f));
  return m.find((f) => /q8_0/i.test(f)) || m[0];
}

/**
 * Resolve `idOrPath` to concrete file paths, downloading if needed. Accepts a
 * catalog id, a direct http(s) URL to a model file, a HuggingFace repo id
 * (`owner/repo` or `owner/repo:file.gguf`, GGUF + any mmproj auto-resolved), or a
 * local file path.
 */
export async function resolveModel(
  idOrPath: string,
  opts: { dir?: string; onProgress?: (p: DownloadProgress) => void } = {}
): Promise<ResolvedModel> {
  if (!isCatalogId(idOrPath)) {
    // Direct URL to a model file.
    if (RE_URL.test(idOrPath)) {
      const fname = decodeURIComponent(new URL(idOrPath).pathname.split('/').pop() || 'model.bin');
      const cid = 'url-' + sanitizeId(fname.replace(/\.[^.]+$/, ''));
      const dir = path.join(opts.dir ?? modelsRoot(), cid);
      fs.mkdirSync(dir, { recursive: true });
      const dest = path.join(dir, fname);
      if (!fs.existsSync(dest)) await downloadFile(idOrPath, dest, opts.onProgress);
      return { id: cid, type: 'path', dir, primary: dest };
    }
    // HuggingFace repo — resolve a GGUF (+ mmproj for VLMs).
    if (isRemoteSource(idOrPath)) {
      const [repo, explicit] = idOrPath.split(':');
      const files = await hfFiles(repo);
      const gguf = explicit || pickGguf(files);
      if (!gguf) throw new Error(`no GGUF file found in HuggingFace repo ${repo}`);
      const mmproj = explicit ? undefined : pickMmproj(files);
      const cid = 'hf-' + sanitizeId(repo);
      const dir = path.join(opts.dir ?? modelsRoot(), cid);
      fs.mkdirSync(dir, { recursive: true });
      const dest = path.join(dir, path.basename(gguf));
      if (!fs.existsSync(dest)) {
        await downloadFile(`https://huggingface.co/${repo}/resolve/main/${gguf}`, dest, opts.onProgress);
      }
      let mmprojPath: string | undefined;
      if (mmproj) {
        mmprojPath = path.join(dir, path.basename(mmproj));
        if (!fs.existsSync(mmprojPath)) {
          await downloadFile(`https://huggingface.co/${repo}/resolve/main/${mmproj}`, mmprojPath, opts.onProgress);
        }
      }
      return { id: cid, type: 'path', dir, primary: dest, mmproj: mmprojPath };
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
      if (!fs.existsSync(dest)) await downloadFile(f.url, dest, opts.onProgress);
      extractTarBz2(dest, dir);
    } else if (!fs.existsSync(dest)) {
      await downloadFile(f.url, dest, opts.onProgress);
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
