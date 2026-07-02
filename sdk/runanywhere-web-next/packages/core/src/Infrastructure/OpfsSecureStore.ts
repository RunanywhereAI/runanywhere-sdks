import { InMemorySecureStore, type SecureStore } from '../runtime/PlatformAdapter';
import { SDKLogger } from '../Foundation/SDKLogger';

const logger = new SDKLogger('OpfsSecureStore');
const FILE = 'rac_secure_store_v1.json';

interface SyncAccessHandle {
  getSize(): number;
  read(buffer: Uint8Array, opts?: { at?: number }): number;
  write(buffer: Uint8Array, opts?: { at?: number }): number;
  truncate(size: number): void;
  flush(): void;
  close(): void;
}

function opfsRoot(): Promise<FileSystemDirectoryHandle> | null {
  const storage = (navigator as Navigator & { storage?: { getDirectory?: () => Promise<FileSystemDirectoryHandle> } }).storage;
  return storage?.getDirectory ? storage.getDirectory() : null;
}

export async function createSecureStore(): Promise<SecureStore> {
  if (!opfsRoot()) {
    logger.debug('OPFS unavailable; using in-memory secure store (non-persistent)');
    return new InMemorySecureStore();
  }
  const store = new OpfsSecureStore();
  await store.hydrate();
  return store;
}

export class OpfsSecureStore implements SecureStore {
  private readonly map = new Map<string, string>();
  private persisting = false;
  private pending = false;

  get(key: string): string | null {
    return this.map.get(key) ?? null;
  }

  set(key: string, value: string): void {
    this.map.set(key, value);
    void this.persist();
  }

  delete(key: string): void {
    this.map.delete(key);
    void this.persist();
  }

  async hydrate(): Promise<void> {
    try {
      const access = await this.accessHandle();
      try {
        const size = access.getSize();
        if (size > 0) {
          const buffer = new Uint8Array(size);
          access.read(buffer, { at: 0 });
          const obj = JSON.parse(new TextDecoder().decode(buffer)) as Record<string, string>;
          for (const [key, value] of Object.entries(obj)) this.map.set(key, value);
        }
      } finally {
        access.close();
      }
    } catch (error) {
      logger.debug(`hydrate skipped: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private async persist(): Promise<void> {
    if (this.persisting) {
      this.pending = true;
      return;
    }
    this.persisting = true;
    try {
      const access = await this.accessHandle();
      try {
        const bytes = new TextEncoder().encode(JSON.stringify(Object.fromEntries(this.map)));
        access.truncate(0);
        access.write(bytes, { at: 0 });
        access.flush();
      } finally {
        access.close();
      }
    } catch (error) {
      logger.warning(`persist failed: ${error instanceof Error ? error.message : String(error)}`);
    } finally {
      this.persisting = false;
      if (this.pending) {
        this.pending = false;
        void this.persist();
      }
    }
  }

  private async accessHandle(): Promise<SyncAccessHandle> {
    const root = await opfsRoot()!;
    const file = await root.getFileHandle(FILE, { create: true });
    const create = (file as unknown as { createSyncAccessHandle(): Promise<SyncAccessHandle> }).createSyncAccessHandle;
    return create.call(file);
  }
}
