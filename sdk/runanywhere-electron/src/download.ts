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

/**
 * Resolve `idOrPath` to concrete file paths, downloading a catalog model if it
 * isn't present yet. A non-catalog value is treated as an already-on-disk path.
 */
export async function resolveModel(
  idOrPath: string,
  opts: { dir?: string; onProgress?: (p: DownloadProgress) => void } = {}
): Promise<ResolvedModel> {
  if (!isCatalogId(idOrPath)) {
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
