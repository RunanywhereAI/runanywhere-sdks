const STORED_DIRECTORY_NAME_KEY = 'runanywhere_storage_dir_name';

/**
 * Return the stored directory name from localStorage for fast UI display.
 */
export function getStoredDirectoryName(): string | null {
  try {
    return localStorage.getItem(STORED_DIRECTORY_NAME_KEY);
  } catch {
    return null;
  }
}

/**
 * Persist the selected directory name outside IndexedDB so UI can render it
 * before the directory handle has been restored.
 */
export function rememberDirectoryName(name: string): void {
  try {
    localStorage.setItem(STORED_DIRECTORY_NAME_KEY, name);
  } catch {
    // Non-critical; IndexedDB handle persistence is the source of truth.
  }
}

/**
 * Sanitize a storage key for use as a local filesystem filename.
 */
export function sanitizeStorageFilename(key: string): string {
  // Intentional: strip C0 control characters from filenames.
  // eslint-disable-next-line no-control-regex
  return key.replace(/[<>:"/\\|?*\x00-\x1F]/g, '_');
}
