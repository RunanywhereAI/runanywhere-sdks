/**
 * Internal React Native package plumbing.
 *
 * This subpath is for sibling backend packages and local examples that need
 * Nitro/logging access. It is intentionally kept out of the package root so
 * `@runanywhere/core` stays aligned with the Swift public SDK facade.
 *
 * @internal
 */

export {
  initializeNitroModulesGlobally,
  getNitroModulesProxySync,
  isNitroModulesInitialized,
  type NitroProxy,
} from './native/NitroModulesGlobalInit';

export { SDKLogger } from './Foundation/Logging/Logger/SDKLogger';

export {
  NativeRunAnywhereCore,
  getNativeCoreModule,
  requireNativeCoreModule,
  isNativeCoreModuleAvailable,
} from './native/NativeRunAnywhereCore';
export type {
  NativeRunAnywhereCoreModule,
} from './native/NativeRunAnywhereCore';

export {
  bytesToArrayBuffer,
  arrayBufferToBytes,
} from './services/ProtoBytes';

export {
  requestAudioPermission,
  startRecording,
  stopRecording,
  cancelRecording,
  playAudio,
  stopPlayback,
  pausePlayback,
  resumePlayback,
  createWavFromPCMFloat32,
  cleanup as cleanupAudio,
  formatDuration,
  AUDIO_SAMPLE_RATE,
  TTS_SAMPLE_RATE,
} from './Internal/Audio/AudioUtilities';
export type {
  RecordingCallbacks,
  PlaybackCallbacks,
  RecordingResult,
} from './Internal/Audio/AudioUtilities';
