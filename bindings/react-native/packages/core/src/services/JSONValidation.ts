/** A JSON object after an external value has been narrowed at runtime. */
export type JsonObject = Readonly<Record<string, unknown>>;

/**
 * Narrow an unknown JSON value to a plain object-shaped record.
 *
 * Arrays and `null` are objects in JavaScript, but neither is a valid keyed
 * configuration/metadata payload for the native bridge boundaries that use
 * this helper.
 */
export function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}
