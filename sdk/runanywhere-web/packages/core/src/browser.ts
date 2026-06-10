/**
 * Browser helper entrypoint.
 *
 * These utilities are Web-native platform affordances. They are intentionally
 * kept out of the root facade so `@runanywhere/web` can mirror Swift.
 */

export { AudioCapture } from './Infrastructure/AudioCapture';
export type {
  AudioCaptureConfig,
  AudioChunkCallback,
  AudioLevelCallback,
} from './Infrastructure/AudioCapture';

export { AudioPlayback } from './Infrastructure/AudioPlayback';
export type {
  PlaybackCompleteCallback,
  PlaybackConfig,
} from './Infrastructure/AudioPlayback';

export { AudioFileLoader } from './Infrastructure/AudioFileLoader';
export type { AudioFileLoaderResult } from './Infrastructure/AudioFileLoader';

export { VideoCapture } from './Infrastructure/VideoCapture';
export type { CapturedFrame, VideoCaptureConfig } from './Infrastructure/VideoCapture';

export { detectCapabilities, getDeviceInfo } from './Infrastructure/DeviceCapabilities';
export type { WebCapabilities } from './Infrastructure/DeviceCapabilities';
