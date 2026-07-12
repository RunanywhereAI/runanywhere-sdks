/**
 * Internal React Native package plumbing.
 *
 * Sibling backend packages (`@runanywhere/llamacpp`, `@runanywhere/mlx`,
 * `@runanywhere/onnx`) reach the NitroModules proxy and the SDK logger through
 * this subpath.
 * Nothing here is part of the stable `@runanywhere/core` surface.
 *
 * @internal
 */

export {
  requireNativeModule,
  isNativeModuleAvailable,
  type NativeRunAnywhereModule,
} from './native/NativeRunAnywhereCore';

export {
  getNitroModulesProxySync,
  type NitroProxy,
} from './native/NitroModulesGlobalInit';

export { SDKLogger } from './Foundation/Logging/Logger/SDKLogger';
