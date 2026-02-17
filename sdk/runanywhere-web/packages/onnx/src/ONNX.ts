/**
 * ONNX - Module facade for @runanywhere/web-onnx
 *
 * Provides a high-level API matching the React Native SDK's module pattern.
 *
 * Usage:
 *   import { ONNX } from '@runanywhere/web-onnx';
 *
 *   await ONNX.register();
 */

import { ONNXProvider } from './ONNXProvider';

const MODULE_ID = 'onnx';

export const ONNX = {
  get moduleId(): string {
    return MODULE_ID;
  },

  get isRegistered(): boolean {
    return ONNXProvider.isRegistered;
  },

  async register(): Promise<void> {
    return ONNXProvider.register();
  },

  unregister(): void {
    ONNXProvider.unregister();
  },
};

export function autoRegister(): void {
  ONNXProvider.register().catch(() => {
    // Silently handle registration failure during auto-registration
  });
}
