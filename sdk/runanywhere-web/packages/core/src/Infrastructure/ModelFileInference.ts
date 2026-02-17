/**
 * Model File Inference - Infer model metadata from filenames
 *
 * When a user imports a model file via picker or drag-and-drop,
 * we need to determine the model type, framework, and a human-friendly
 * name from the filename alone.
 *
 * Usage:
 *   import { inferModelFromFilename } from './ModelFileInference';
 *   const meta = inferModelFromFilename('smollm2-360m.Q8_0.gguf');
 *   // { id: 'smollm2-360m-q8_0', name: 'smollm2-360m.Q8_0', category: Language, framework: LlamaCpp }
 */

import { ModelCategory, LLMFramework } from '../types/enums';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface InferredModelMeta {
  /** Sanitized model ID (lowercase, no special chars). */
  id: string;
  /** Human-readable display name. */
  name: string;
  /** Inferred model category. */
  category: ModelCategory;
  /** Inferred inference framework. */
  framework: LLMFramework;
}

// ---------------------------------------------------------------------------
// Inference
// ---------------------------------------------------------------------------

/**
 * Infer model metadata from a filename.
 *
 * Rules:
 * - `.gguf` -> Language model, LlamaCpp framework
 * - `.onnx` -> Depends on filename keywords (vad/tts/stt/whisper/silero)
 * - `.bin`  -> Language model, LlamaCpp framework (generic)
 * - Other   -> Language model, LlamaCpp framework (best guess)
 */
export function inferModelFromFilename(filename: string): InferredModelMeta {
  const ext = getExtension(filename);
  const baseName = stripExtension(filename);
  const lowerName = baseName.toLowerCase();

  if (ext === 'gguf') {
    return {
      id: sanitizeId(baseName),
      name: humanizeName(baseName),
      category: ModelCategory.Language,
      framework: LLMFramework.LlamaCpp,
    };
  }

  if (ext === 'onnx') {
    // Infer category from filename keywords
    if (lowerName.includes('vad') || lowerName.includes('silero_vad')) {
      return {
        id: sanitizeId(baseName),
        name: humanizeName(baseName),
        category: ModelCategory.Audio,
        framework: LLMFramework.ONNX,
      };
    }
    if (lowerName.includes('tts') || lowerName.includes('piper') || lowerName.includes('vits')) {
      return {
        id: sanitizeId(baseName),
        name: humanizeName(baseName),
        category: ModelCategory.SpeechSynthesis,
        framework: LLMFramework.ONNX,
      };
    }
    if (lowerName.includes('whisper') || lowerName.includes('stt') || lowerName.includes('paraformer') || lowerName.includes('zipformer')) {
      return {
        id: sanitizeId(baseName),
        name: humanizeName(baseName),
        category: ModelCategory.SpeechRecognition,
        framework: LLMFramework.ONNX,
      };
    }
    // Default ONNX -> generic Language (avoid misclassification)
    return {
      id: sanitizeId(baseName),
      name: humanizeName(baseName),
      category: ModelCategory.Language,
      framework: LLMFramework.ONNX,
    };
  }

  // Default: treat as LLM GGUF model
  return {
    id: sanitizeId(baseName),
    name: humanizeName(baseName),
    category: ModelCategory.Language,
    framework: LLMFramework.LlamaCpp,
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function getExtension(filename: string): string {
  const lower = filename.toLowerCase();
  if (lower.endsWith('.tar.gz')) return 'tar.gz';
  if (lower.endsWith('.tar.bz2')) return 'tar.bz2';
  const lastDot = filename.lastIndexOf('.');
  return lastDot >= 0 ? filename.slice(lastDot + 1).toLowerCase() : '';
}

function stripExtension(filename: string): string {
  const lower = filename.toLowerCase();
  if (lower.endsWith('.tar.gz')) return filename.slice(0, -7);
  if (lower.endsWith('.tar.bz2')) return filename.slice(0, -8);
  const lastDot = filename.lastIndexOf('.');
  return lastDot >= 0 ? filename.slice(0, lastDot) : filename;
}

/**
 * Sanitize a filename into a valid model ID.
 * Lowercase, replace non-alphanumeric with dashes, collapse multiples.
 */
export function sanitizeId(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
}

/**
 * Create a human-readable name from a filename.
 * Preserves case and dots (e.g. "smollm2-360m.Q8_0" stays readable).
 */
function humanizeName(baseName: string): string {
  // Replace underscores with spaces, keep dots and dashes
  return baseName.replace(/_/g, ' ');
}
