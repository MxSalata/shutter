import { asArray, asObject } from '@/lib/json';

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

const DAYS = 7;

/**
 * The character finding as lines (Shutter.Util.CharacterFinding): the count of recent failures holding the same character,
 * then one line per field and character with every place it stands and that field's count, the questions, and the stored
 * MSH-18 beside the operation's setting. Read from the finding's structure, so a finding stored before 1.4.1 (whose
 * sentence repeated a field for every place) reads the same way; with no fields it is the finding's own sentence.
 */
export function characterLines(character: Record<string, unknown>): string[] {
  const fields = asArray(character.fields)
    .map((f) => asObject(f) ?? {})
    .filter((f) => str(f.field));
  if (!fields.length) return str(character.sentence) ? [str(character.sentence)] : [];
  const lines: string[] = [];
  const shared = asObject(character.shared);
  if (shared && str(shared.characters))
    lines.push(
      str(shared.failures)
        ? `${str(shared.failures)} of the last ${str(shared.of_failures)} failures to this receiver in ${DAYS} days hold ${str(shared.characters)}, in any field.`
        : `Its failures could not be compared for ${str(shared.characters)}.`,
    );
  const groups: { key: string; field: string; character: string; wire: string; places: string[] }[] = [];
  for (const f of fields) {
    const key = `${str(f.field)}\u0000${str(f.character)}\u0000${str(f.wire)}`;
    const place = str(f.position)
      ? `position ${str(f.position)}${Number(f.component) > 1 ? ` of component ${str(f.component)}` : ''}`
      : '';
    const g = groups.find((x) => x.key === key);
    if (g) {
      if (place) g.places.push(place);
    } else
      groups.push({
        key,
        field: str(f.field),
        character: str(f.character),
        wire: str(f.wire),
        places: place ? [place] : [],
      });
  }
  const count = asObject(character.count) ?? {};
  const counted = new Set<string>();
  for (const g of groups) {
    const where = g.places.length
      ? ` at ${g.places.length === 1 ? g.places[0] : `${g.places.slice(0, -1).join(', ')} and ${g.places.at(-1)}`}`
      : '';
    let line = `${g.field} holds ${g.character}${where}; the operation sends ${g.wire}.`;
    const c = asObject(count[g.field]);
    if (c && !counted.has(g.field)) {
      counted.add(g.field);
      line += ` ${str(c.failures) ? `${str(c.failures)} of the last ${str(c.of_failures)} failures to this receiver in ${DAYS} days carry a character above ASCII in ${g.field}` : 'Its failures could not be compared'}; ${str(c.delivered) ? `${str(c.delivered)} of the last ${str(c.of_delivered)} delivered do.` : 'not compared with what got through.'}`;
    }
    lines.push(line);
  }
  for (const q of asArray(character.questions)) {
    const words = str(asObject(q)?.words);
    if (words) lines.push(words);
  }
  if ('msh18' in character || 'setting' in character)
    lines.push(
      `Stored MSH-18: ${str(character.msh18) || 'empty'}; the operation's DefCharEncoding: ${str(character.setting) || 'unknown'}.`,
    );
  return lines;
}
