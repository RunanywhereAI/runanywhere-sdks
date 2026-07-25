/**
 * Browser helper entrypoint.
 *
 * These utilities are Web-native platform affordances. They are intentionally
 * kept out of the root facade so `@runanywhere/web` can mirror Swift.
 */

export { AudioCapture } from './Infrastructure/AudioCapture.js';
export type {
  AudioCaptureConfig,
  AudioChunkCallback,
  AudioLevelCallback,
} from './Infrastructure/AudioCapture.js';

export { VoiceAgentMicDriver } from './Infrastructure/VoiceAgentMicDriver.js';
export type {
  VoiceAgentMicCallbacks,
  VoiceAgentMicPhase,
  VoiceAgentMicTurn,
} from './Infrastructure/VoiceAgentMicDriver.js';

export { AudioPlayback } from './Infrastructure/AudioPlayback.js';
export type {
  PlaybackCompleteCallback,
  PlaybackConfig,
} from './Infrastructure/AudioPlayback.js';

export { AudioFileLoader } from './Infrastructure/AudioFileLoader.js';
export type { AudioFileLoaderResult } from './Infrastructure/AudioFileLoader.js';

export { VideoCapture } from './Infrastructure/VideoCapture.js';
export type { CapturedFrame, VideoCaptureConfig } from './Infrastructure/VideoCapture.js';

export { detectCapabilities, getDeviceInfo } from './Infrastructure/DeviceCapabilities.js';
export type { WebCapabilities } from './Infrastructure/DeviceCapabilities.js';

export {
  ensureDownloadStorageReady,
  LARGE_DOWNLOAD_BYTES,
  readBrowserStorageEstimate,
  requestPersistentStorage,
} from './Infrastructure/BrowserStorage.js';
export type {
  BrowserStorageEstimate,
  BrowserStorageReadiness,
} from './Infrastructure/BrowserStorage.js';
