import { readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * A table the core's unit tests and the web app's both run: an XData block of JSON in a test class under
 * tests/unit/Shutter/Test, read from the class's source, so the two suites agree row for row or one of them fails.
 */
export function coreTable<T>(testClass: string, name: string): T[] {
  const source = readFileSync(join(__dirname, `../../../tests/unit/Shutter/Test/${testClass}.cls`), 'utf8');
  const table = new RegExp(
    `XData ${name} \\[ MimeType = application/json \\]\\n\\{\\n(\\[[\\s\\S]*?\\n\\])\\n\\}`,
  ).exec(source);
  if (!table) throw new Error(`${testClass}.cls has no XData ${name}`);
  return JSON.parse(table[1]) as T[];
}
