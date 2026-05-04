/**
 * RunAnywhere+ModelAssignments.ts
 *
 * Model assignment API. Mirrors Swift `RunAnywhere+ModelAssignments.swift`.
 *
 * Until the native ModelAssignment bridge is wired through to RN, these
 * functions delegate to the model registry and warn that backend-driven
 * assignments are not yet available on RN. New code should call these
 * forwarders rather than re-implementing the logic at the screen level.
 */

import { ModelRegistry } from '../../services/ModelRegistry';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../Foundation/ErrorTypes/SDKException';
import { LLMFramework, ModelCategory } from '../../types';
import type { ModelInfo } from '../../types';
import { isNativeModuleAvailable, requireNativeModule } from '../../native';

const logger = new SDKLogger('RunAnywhere.ModelAssignments');

/**
 * Fetch model assignments from the backend.
 *
 * Currently delegates to `getAvailableModels()` (registry-backed). The
 * native ModelAssignment bridge (`CppBridge.ModelAssignment.fetch`) is
 * not yet exposed via Nitro on RN; once it is, this should switch to the
 * native call and return device-scoped assignments.
 *
 * Mirrors Swift: `fetchModelAssignments(forceRefresh:) async throws -> [ModelInfo]`.
 */
export async function fetchModelAssignments(
  forceRefresh: boolean = false
): Promise<ModelInfo[]> {
  if (!isNativeModuleAvailable()) {
    throw SDKException.notInitialized('SDK');
  }
  if (forceRefresh) {
    const native = requireNativeModule();
    try {
      // Best-effort: ask native to refresh the catalog if the method
      // exists on the bridge. Older bridges may not expose this.
      if (typeof (native as { refreshModelRegistry?: (...a: unknown[]) => unknown }).refreshModelRegistry === 'function') {
        await (native as { refreshModelRegistry: (
          includeRemote: boolean,
          rescanLocal: boolean,
          pruneOrphans: boolean,
        ) => Promise<boolean> }).refreshModelRegistry(true, false, false);
      }
    } catch (err) {
      logger.warning(
        `refreshModelRegistry failed (non-fatal): ${err instanceof Error ? err.message : String(err)}`
      );
    }
  }
  return ModelRegistry.getAvailableModels();
}

/**
 * Get available models for a specific framework.
 * Mirrors Swift: `getModelsForFramework(_:) async throws -> [ModelInfo]`.
 */
export async function getModelsForFramework(
  framework: LLMFramework
): Promise<ModelInfo[]> {
  const allModels = await ModelRegistry.getAvailableModels();
  return allModels.filter(
    (m) =>
      m.preferredFramework === framework ||
      (m.compatibleFrameworks ?? []).includes(framework)
  );
}

/**
 * Get available models for a specific category.
 * Mirrors Swift: `getModelsForCategory(_:) async throws -> [ModelInfo]`.
 */
export async function getModelsForCategory(
  category: ModelCategory
): Promise<ModelInfo[]> {
  const allModels = await ModelRegistry.getAvailableModels();
  return allModels.filter((m) => m.category === category);
}
