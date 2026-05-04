/**
 * RunAnywhere+Frameworks.ts
 *
 * Framework/backend management namespace — mirrors Swift's `RunAnywhere+Frameworks.swift`.
 * Provides `RunAnywhere.frameworks.*` surface for inspecting registered backends.
 */

import { ExtensionRegistry } from '../../Infrastructure/ExtensionRegistry';
import type { SDKExtension } from '../../Infrastructure/ExtensionRegistry';

export type { SDKExtension };

export const Frameworks = {
  list(): SDKExtension[] {
    return ExtensionRegistry.getAll();
  },

  isRegistered(name: string): boolean {
    return ExtensionRegistry.has(name);
  },
};
