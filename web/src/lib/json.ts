/**
 * Fields the store keeps as JSON text may come through the API as text or as parsed JSON. This reads either, and
 * gives back the value unchanged when it isn't JSON text.
 */
export function parseJson<T = unknown>(value: unknown): T | undefined {
  if (value === null || value === undefined || value === '') return undefined;
  if (typeof value !== 'string') return value as T;
  const text = value.trim();
  if (!text.startsWith('{') && !text.startsWith('[')) return value as T;
  try {
    return JSON.parse(text) as T;
  } catch {
    return value as T;
  }
}

/** A JSON value as indented text, for the raw views. */
export function pretty(value: unknown): string {
  const parsed = parseJson(value);
  if (parsed === undefined) return '';
  if (typeof parsed === 'string') return parsed;
  return JSON.stringify(parsed, null, 2);
}

/** The value as an array when it is one (or JSON text of one), otherwise empty. */
export function asArray<T = unknown>(value: unknown): T[] {
  const parsed = parseJson(value);
  return Array.isArray(parsed) ? (parsed as T[]) : [];
}

/** The value as a plain object when it is one (or JSON text of one), otherwise undefined. */
export function asObject(value: unknown): Record<string, unknown> | undefined {
  const parsed = parseJson(value);
  return parsed && typeof parsed === 'object' && !Array.isArray(parsed)
    ? (parsed as Record<string, unknown>)
    : undefined;
}
