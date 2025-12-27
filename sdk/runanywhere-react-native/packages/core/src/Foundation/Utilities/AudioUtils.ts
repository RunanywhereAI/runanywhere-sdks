/**
 * AudioUtils.ts
 *
 * Audio utility functions for encoding/decoding audio data.
 * Kept minimal - prefer native-side audio processing when possible.
 */

/**
 * Convert ArrayBuffer or Uint8Array to base64 string
 * Used for passing audio data to native module
 */
export function arrayBufferToBase64(
  data: ArrayBuffer | ArrayBufferLike | Uint8Array
): string {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]!);
  }
  return btoa(binary);
}

/**
 * Convert base64 string to Uint8Array
 * Used for receiving audio data from native module
 */
export function base64ToUint8Array(base64: string): Uint8Array {
  const binaryString = atob(base64);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes;
}

/**
 * Normalize audio data to Uint8Array
 * Accepts ArrayBuffer, Buffer, or Uint8Array
 */
export function normalizeAudioData(
  audioData: ArrayBuffer | Uint8Array | Buffer
): Uint8Array {
  if (audioData instanceof ArrayBuffer) {
    return new Uint8Array(audioData);
  } else if (Buffer.isBuffer(audioData)) {
    return new Uint8Array(audioData);
  }
  return audioData;
}
