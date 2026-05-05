/**
 * AudioFileReader
 *
 * JS-side replacement for the legacy native `transcribeFile` JSON path.
 * Reads an audio file from disk into an `ArrayBuffer` so callers can feed
 * the bytes into the canonical `sttTranscribeProto` proto-byte surface.
 *
 * Strategy:
 *   1. `file://`-prefixed paths are normalized (strip scheme).
 *   2. Prefer `react-native-fs` (`RNFS.readFile(path, 'base64')`) which is
 *      already a declared optional peer dependency. Decode base64 →
 *      `ArrayBuffer` in JS.
 *   3. Fall back to `fetch(file://path)` where available (supported by
 *      some RN platforms for local files).
 */
import { SDKLogger } from '../Foundation/Logging/Logger/SDKLogger';

const logger = new SDKLogger('AudioFileReader');

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let cachedRNFS: any = null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function getRNFS(): any {
  if (cachedRNFS !== null) return cachedRNFS;
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports
    cachedRNFS = require('react-native-fs');
  } catch {
    cachedRNFS = false;
    logger.warning(
      'react-native-fs not available; falling back to fetch() for file reads'
    );
  }
  return cachedRNFS;
}

function base64ToArrayBuffer(base64: string): ArrayBuffer {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

function normalizePath(path: string): string {
  return path.startsWith('file://') ? path.slice(7) : path;
}

/**
 * Read an audio file at `filePath` into an `ArrayBuffer`.
 *
 * Throws if no file-reading mechanism is available.
 */
export async function readAudioFileAsBuffer(
  filePath: string
): Promise<ArrayBuffer> {
  const normalized = normalizePath(filePath);

  const fs = getRNFS();
  if (fs) {
    const base64: string = await fs.readFile(normalized, 'base64');
    return base64ToArrayBuffer(base64);
  }

  // Fallback: fetch() with file:// scheme works for local files on RN.
  const url = filePath.startsWith('file://') ? filePath : `file://${normalized}`;
  const response = await fetch(url);
  return await response.arrayBuffer();
}
