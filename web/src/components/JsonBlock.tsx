import { Code } from '@mantine/core';
import { pretty } from '@/lib/json';

/** A JSON value (or JSON text) as indented, scrollable text. */
export function JsonBlock({ value, label }: { value: unknown; label?: string }) {
  const text = pretty(value);
  if (!text) return null;
  return (
    <Code block className="json-block" aria-label={label} tabIndex={0}>
      {text}
    </Code>
  );
}
