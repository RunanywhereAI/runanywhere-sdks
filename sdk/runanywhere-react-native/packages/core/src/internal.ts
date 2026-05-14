/**
 * Internal React Native package plumbing.
 *
 * Sibling backend packages (`@runanywhere/llamacpp`, `@runanywhere/onnx`) and
 * local examples reach the Nitro proxy and the SDK logger through this
 * subpath. Nothing here is part of the stable `@runanywhere/core` surface.
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
  requireNativeModule,
  isNativeModuleAvailable,
  type NativeRunAnywhereModule,
} from './native/NativeRunAnywhereCore';

export {
  bytesToArrayBuffer,
  arrayBufferToBytes,
} from './services/ProtoBytes';
