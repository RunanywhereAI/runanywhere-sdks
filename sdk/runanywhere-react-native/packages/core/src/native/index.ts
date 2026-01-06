/**
 * Native module exports for @runanywhere/core
 */

export {
  NativeRunAnywhereCore,
  getNativeCoreModule,
  requireNativeCoreModule,
  isNativeCoreModuleAvailable,
  // Backwards compatibility
  requireNativeModule,
  isNativeModuleAvailable,
  requireDeviceInfoModule,
  requireFileSystemModule,
  hasNativeMethod,
} from './NativeRunAnywhereCore';
export type {
  NativeRunAnywhereCoreModule,
  NativeRunAnywhereModule,
  FileSystemModule,
} from './NativeRunAnywhereCore';
