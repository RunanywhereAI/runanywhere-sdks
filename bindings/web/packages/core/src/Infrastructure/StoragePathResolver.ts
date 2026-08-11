// AES-GCM key for encrypting localStorage metadata (device-ID-equivalent
// parity with iOS Keychain / Android Keystore-backed storage). The key is
// non-exportable and lives in IndexedDB so it is origin-scoped and survives
// page reloads without ever appearing in application-layer JS memory as raw
// bytes.
const META_KEY_DB_NAME = 'runanywhere-meta-keys';
const META_KEY_DB_VERSION = 1;
const META_KEY_STORE = 'keys';
const META_CRYPTO_KEY_ID = 'storage-meta-aes-gcm-v1';

const STORED_DIRECTORY_NAME_KEY = 'runanywhere_storage_dir_name';

// ---------------------------------------------------------------------------
// Internal crypto helpers
// ---------------------------------------------------------------------------

function openMetaKeyDB(): Promise<IDBDatabase> {
  return new Promise<IDBDatabase>((resolve, reject) => {
    const req = indexedDB.open(META_KEY_DB_NAME, META_KEY_DB_VERSION);
    req.onupgradeneeded = () => {
      if (!req.result.objectStoreNames.contains(META_KEY_STORE)) {
        req.result.createObjectStore(META_KEY_STORE);
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function getOrCreateMetaKey(): Promise<CryptoKey> {
  let db: IDBDatabase | null = null;
  try {
    db = await openMetaKeyDB();
    const existing = await new Promise<CryptoKey | null>((resolve, reject) => {
      const tx = db!.transaction(META_KEY_STORE, 'readonly');
      const req = tx.objectStore(META_KEY_STORE).get(META_CRYPTO_KEY_ID);
      req.onsuccess = () => resolve((req.result as CryptoKey | undefined) ?? null);
      req.onerror = () => reject(req.error);
    });
    if (existing) return existing;

    // Generate a fresh non-exportable AES-GCM key and persist it.
    const key = await crypto.subtle.generateKey(
      { name: 'AES-GCM', length: 256 },
      false, // non-exportable — mirrors iOS Keychain kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      ['encrypt', 'decrypt'],
    );
    await new Promise<void>((resolve, reject) => {
      const tx = db!.transaction(META_KEY_STORE, 'readwrite');
      tx.objectStore(META_KEY_STORE).put(key, META_CRYPTO_KEY_ID);
      tx.oncomplete = () => resolve();
      tx.onerror = () => reject(tx.error);
    });
    return key;
  } finally {
    db?.close();
  }
}

async function encryptMeta(plaintext: string): Promise<string> {
  const key = await getOrCreateMetaKey();
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(plaintext);
  const cipher = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, encoded);
  // Pack iv + ciphertext as a single base64 blob for localStorage.
  const combined = new Uint8Array(iv.byteLength + cipher.byteLength);
  combined.set(iv, 0);
  combined.set(new Uint8Array(cipher), iv.byteLength);
  return btoa(String.fromCharCode(...combined));
}

async function decryptMeta(blob: string): Promise<string | null> {
  try {
    const raw = Uint8Array.from(atob(blob), (c) => c.charCodeAt(0));
    if (raw.byteLength <= 12) return null;
    const iv = raw.slice(0, 12);
    const cipher = raw.slice(12);
    const key = await getOrCreateMetaKey();
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv }, key, cipher);
    return new TextDecoder().decode(plain);
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Return the stored directory name. This sync form is kept for backwards
 * compatibility with synchronous callers (e.g. LocalFileStorage static getter).
 * It returns the raw localStorage value which may be an opaque ciphertext blob
 * after `rememberDirectoryName` has been called at least once. Prefer
 * `getStoredDirectoryNameAsync` for display purposes.
 */
export function getStoredDirectoryName(): string | null {
  try {
    return localStorage.getItem(STORED_DIRECTORY_NAME_KEY);
  } catch {
    return null;
  }
}

/**
 * Return the stored directory name, decrypting the AES-GCM ciphertext stored
 * by `rememberDirectoryName`. Falls back to the raw value for entries written
 * by older SDK versions (plaintext, not valid base64 ciphertext).
 */
export async function getStoredDirectoryNameAsync(): Promise<string | null> {
  const raw = getStoredDirectoryName();
  if (!raw) return null;
  // Attempt decryption; if it fails the value is a legacy plaintext entry.
  const decrypted = await decryptMeta(raw);
  return decrypted ?? raw;
}

/**
 * Persist the selected directory name encrypted with AES-GCM so the stored
 * metadata is opaque at rest — parity with iOS Keychain storage used by the
 * Swift SDK. The encryption key is non-exportable and origin-scoped in
 * IndexedDB (mirrors `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
 *
 * The function is fire-and-forget async; localStorage writes are non-critical
 * (IndexedDB handle persistence is the source of truth for the directory handle).
 */
export function rememberDirectoryName(name: string): void {
  void (async () => {
    try {
      const blob = await encryptMeta(name);
      localStorage.setItem(STORED_DIRECTORY_NAME_KEY, blob);
    } catch {
      // Non-critical; IndexedDB handle persistence is the source of truth.
    }
  })();
}

/**
 * Sanitize a storage key for use as a local filesystem filename.
 */
export function sanitizeStorageFilename(key: string): string {
  // Intentional: strip C0 control characters from filenames.
  // eslint-disable-next-line no-control-regex
  return key.replace(/[<>:"/\\|?*\x00-\x1F]/g, '_');
}
