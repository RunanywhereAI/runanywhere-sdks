/**
 * RunAnywhere+Frameworks.ts
 *
 * Framework discovery API. Mirrors Swift `RunAnywhere+Frameworks.swift`.
 * Derives the set of registered inference frameworks from the model
 * registry — frameworks aren't tracked separately; the source of truth
 * is the registered models themselves.
 */

import { ModelRegistry } from '../../services/ModelRegistry';
import { LLMFramework, ModelCategory, SDKComponent } from '../../types';
import type { ModelInfo } from '../../types';

/**
 * Get all registered frameworks derived from available models.
 * Matches Swift: `getRegisteredFrameworks() async -> [InferenceFramework]`.
 */
export async function getRegisteredFrameworks(): Promise<LLMFramework[]> {
  const allModels = await ModelRegistry.getAvailableModels();
  const set = new Set<LLMFramework>();
  for (const model of allModels) {
    if (model.preferredFramework) {
      set.add(model.preferredFramework);
    }
    for (const fw of model.compatibleFrameworks ?? []) {
      set.add(fw);
    }
  }
  return Array.from(set).sort();
}

/**
 * Get registered frameworks for a specific capability / component.
 * Matches Swift: `getFrameworks(for: SDKComponent)`.
 */
export async function getFrameworks(
  capability: SDKComponent
): Promise<LLMFramework[]> {
  const relevant = relevantCategoriesFor(capability);
  const allModels = await ModelRegistry.getAvailableModels();
  const set = new Set<LLMFramework>();
  for (const model of allModels) {
    if (!relevant.has(model.category)) continue;
    if (model.preferredFramework) set.add(model.preferredFramework);
    for (const fw of model.compatibleFrameworks ?? []) set.add(fw);
  }
  return Array.from(set).sort();
}

function relevantCategoriesFor(capability: SDKComponent): Set<ModelCategory> {
  switch (capability) {
    case SDKComponent.LLM:
      return new Set([ModelCategory.Language]);
    case SDKComponent.STT:
      return new Set([ModelCategory.SpeechRecognition]);
    case SDKComponent.TTS:
      return new Set([ModelCategory.SpeechSynthesis]);
    case SDKComponent.VAD:
      return new Set([ModelCategory.Audio]);
    case SDKComponent.VoiceAgent:
      return new Set([
        ModelCategory.Language,
        ModelCategory.SpeechRecognition,
        ModelCategory.SpeechSynthesis,
      ]);
    case SDKComponent.Embedding:
      return new Set([ModelCategory.Embedding]);
    case SDKComponent.SpeakerDiarization:
      return new Set([ModelCategory.Audio]);
  }
}

/**
 * Get all models compatible with a framework. Mirrors Kotlin / Swift
 * `getModelsForFramework(_:)`.
 */
export async function getModelsForFramework(
  framework: LLMFramework
): Promise<ModelInfo[]> {
  const allModels = await ModelRegistry.getAvailableModels();
  return allModels.filter(
    (model) =>
      model.preferredFramework === framework ||
      (model.compatibleFrameworks ?? []).includes(framework)
  );
}
