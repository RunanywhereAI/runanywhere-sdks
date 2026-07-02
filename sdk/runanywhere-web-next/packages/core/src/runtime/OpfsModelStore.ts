export const OPFS_ROOT = 'rac-models';
const DOWNLOADED_DIR = '.downloaded';

export interface DownloadedFile {
  path: string;
  bytes: number;
}

interface OpfsWritable {
  write(data: string | ArrayBufferView): Promise<void>;
  close(): Promise<void>;
}
interface OpfsFile {
  size: number;
  text(): Promise<string>;
}
interface OpfsFileHandle {
  getFile(): Promise<OpfsFile>;
  createWritable?(): Promise<OpfsWritable>;
}
interface OpfsDir {
  getDirectoryHandle(name: string, options?: { create?: boolean }): Promise<OpfsDir>;
  getFileHandle(name: string, options?: { create?: boolean }): Promise<OpfsFileHandle>;
  removeEntry(name: string, options?: { recursive?: boolean }): Promise<void>;
  keys?(): AsyncIterableIterator<string>;
}

function encodeId(modelId: string): string {
  return encodeURIComponent(modelId);
}

function decodeId(name: string): string {
  try {
    return decodeURIComponent(name);
  } catch {
    return name;
  }
}

async function opfsRoot(): Promise<OpfsDir | null> {
  const storage = (globalThis as { navigator?: { storage?: { getDirectory?: () => Promise<OpfsDir> } } }).navigator?.storage;
  if (!storage?.getDirectory) return null;
  try {
    return await storage.getDirectory();
  } catch {
    return null;
  }
}

async function rootDir(create: boolean): Promise<OpfsDir | null> {
  const root = await opfsRoot();
  if (!root) return null;
  try {
    return await root.getDirectoryHandle(OPFS_ROOT, { create });
  } catch {
    return null;
  }
}

async function downloadedDir(create: boolean): Promise<OpfsDir | null> {
  const root = await rootDir(create);
  if (!root) return null;
  try {
    return await root.getDirectoryHandle(DOWNLOADED_DIR, { create });
  } catch {
    return null;
  }
}

async function modelFileSize(path: string): Promise<number> {
  const root = await rootDir(false);
  if (!root) return 0;
  const parts = path.replace(/^\/+/, '').split('/').filter(Boolean);
  const fileName = parts.pop();
  if (!fileName) return 0;
  let dir = root;
  for (const part of parts) {
    try {
      dir = await dir.getDirectoryHandle(part, { create: false });
    } catch {
      return 0;
    }
  }
  try {
    const handle = await dir.getFileHandle(fileName, { create: false });
    return (await handle.getFile()).size;
  } catch {
    return 0;
  }
}

async function readManifest(dir: OpfsDir, modelId: string): Promise<DownloadedFile[] | null> {
  try {
    const handle = await dir.getFileHandle(encodeId(modelId), { create: false });
    const text = await (await handle.getFile()).text();
    if (!text) return [];
    const parsed = JSON.parse(text) as DownloadedFile[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return null;
  }
}

async function bytesPresent(files: DownloadedFile[]): Promise<boolean> {
  if (files.length === 0) return false;
  for (const file of files) {
    if ((await modelFileSize(file.path)) <= 0) return false;
  }
  return true;
}

export const DownloadedModelStore = {
  fileSize(path: string): Promise<number> {
    return modelFileSize(path);
  },

  async mark(modelId: string, files: DownloadedFile[]): Promise<void> {
    const dir = await downloadedDir(true);
    if (!dir) return;
    try {
      const handle = await dir.getFileHandle(encodeId(modelId), { create: true });
      if (!handle.createWritable) return;
      const writable = await handle.createWritable();
      await writable.write(JSON.stringify(files));
      await writable.close();
    } catch {
      /* best effort */
    }
  },

  async unmark(modelId: string): Promise<void> {
    const dir = await downloadedDir(false);
    if (!dir) return;
    try {
      await dir.removeEntry(encodeId(modelId));
    } catch {
      /* best effort */
    }
  },

  async verify(modelId: string): Promise<boolean> {
    const dir = await downloadedDir(false);
    if (!dir) return false;
    const files = await readManifest(dir, modelId);
    if (!files) return false;
    return bytesPresent(files);
  },

  async listVerified(): Promise<string[]> {
    const dir = await downloadedDir(false);
    if (!dir?.keys) return [];
    const present: string[] = [];
    const stale: string[] = [];
    try {
      for await (const name of dir.keys()) {
        const modelId = decodeId(name);
        const files = await readManifest(dir, modelId);
        if (files && (await bytesPresent(files))) present.push(modelId);
        else stale.push(modelId);
      }
    } catch {
      /* best effort */
    }
    for (const modelId of stale) await this.unmark(modelId);
    return present;
  },
};
