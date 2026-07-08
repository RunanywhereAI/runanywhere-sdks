/**
 * Shared display helpers for model catalog rendering.
 *
 * Previously these label tables were inlined in both `components/model-selection.ts`
 * and `views/storage.ts`, and a third byte formatter lived in `components/dialogs.ts`.
 * Keeping a single canonical site avoids the picker, the storage tab, and the
 * eviction dialog drifting from each other when proto enums add new values.
 */

import { ModelCategory } from '@runanywhere/web';
export { formatFramework } from '@runanywhere/web';

/**
 * Returns the HTML entity for the emoji shown next to a model row. The
 * return value is an HTML-safe entity ("&#129302;") so it can be inlined
 * inside an innerHTML template without further escaping.
 */
export function modalityEmoji(category: ModelCategory): string {
  switch (category) {
    case ModelCategory.MODEL_CATEGORY_LANGUAGE:
      return '&#129302;';
    case ModelCategory.MODEL_CATEGORY_MULTIMODAL:
      return '&#128065;';
    case ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION:
      return '&#127908;';
    case ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS:
      return '&#128266;';
    case ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION:
      return '&#128483;';
    case ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION:
      return '&#127912;';
    case ModelCategory.MODEL_CATEGORY_EMBEDDING:
      return '&#128279;';
    default:
      return '&#9881;&#65039;';
  }
}

/**
 * Decimal byte formatter ("GB" / "MB" / "KB"). Aligns with how model
 * catalogs advertise file sizes (1 GB = 10^9 bytes) and with the eviction
 * dialog's storage gauge, both of which run against model catalog byte inputs.
 */
export function formatBytes(bytes: number): string {
  if (bytes >= 1_000_000_000) return `${(bytes / 1_000_000_000).toFixed(1)} GB`;
  if (bytes >= 1_000_000) return `${Math.round(bytes / 1_000_000)} MB`;
  return `${Math.round(bytes / 1_000)} KB`;
}

export function modelDisplaySizeBytes(model: {
  downloadSizeBytes?: number;
  memoryRequiredBytes?: number;
}): number {
  return model.downloadSizeBytes && model.downloadSizeBytes > 0
    ? model.downloadSizeBytes
    : model.memoryRequiredBytes ?? 0;
}
