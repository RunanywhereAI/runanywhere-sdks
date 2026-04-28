/**
 * RunAnywhere+ModelAssignments.ts
 *
 * Model assignments namespace — mirrors Swift's `RunAnywhere+ModelAssignments.swift`.
 * Provides `RunAnywhere.modelAssignments.*` surface for mapping roles → models.
 */

export interface ModelAssignment {
  role: 'stt' | 'tts' | 'vad' | 'llm' | 'vlm' | 'diffusion' | 'embedding';
  modelId: string;
}

const _assignments = new Map<string, string>();

export const ModelAssignments = {
  set(role: ModelAssignment['role'], modelId: string): void {
    _assignments.set(role, modelId);
  },

  get(role: ModelAssignment['role']): string | undefined {
    return _assignments.get(role);
  },

  getAll(): ModelAssignment[] {
    return Array.from(_assignments.entries()).map(([role, modelId]) => ({
      role: role as ModelAssignment['role'],
      modelId,
    }));
  },

  clear(): void {
    _assignments.clear();
  },
};
