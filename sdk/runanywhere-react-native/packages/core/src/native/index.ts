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
  hasNativeMethod,
} from './NativeRunAnywhereCore';
export type {
  NativeRunAnywhereCoreModule,
  NativeRunAnywhereModule,
} from './NativeRunAnywhereCore';
