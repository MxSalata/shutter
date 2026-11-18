import type { SiteEntryItem, SiteProfile } from '@/api/types';
import { categoryOf } from '@/lib/categories';

/**
 * What a save of the site profile does to one of the site's own active entries that reads a receiver's kind (CONTRACTS
 * 6.8, R19): the receiver leaves the entry's pattern or comes into it, the recheck after the save widens the entry (a
 * matching fixture of the receiver reads the kind otherwise than when it was frozen), or the entry cannot be read and may
 * read the kind. The shape of an item of the 409 kind_change_unread answer's kindChanges.
 */
export interface KindChange {
  entry: string;
  title: string;
  receiver: string;
  from: string;
  to: string;
  change: 'leaves' | 'enters' | 'widens' | 'unread';
  /** For widens: the matching fixture's case, of that receiver, whose kind the recheck reads again. */
  case?: string;
}

/** A pattern's or a scope's value (a list, or one value) holds this one, compared as the matcher compares. */
const among = (allowed: unknown, value: string) =>
  Array.isArray(allowed)
    ? allowed.some((v) => String(v) === value)
    : allowed !== null && typeof allowed !== 'object' && allowed !== undefined && String(allowed) === value;

/** A receiver's kind in a profile as the matcher reads it: the first entry of that name, else current_state. */
const kindIn = (p: SiteProfile | undefined, name: string) =>
  categoryOf((p?.receivers ?? []).find((r) => r?.name === name));

/**
 * The port of SiteEntry.KindChanges: for each receiver whose kind differs between `before` (the profile in force) and
 * `after` (the draft), each active entry of `items` (GET /site-entries) whose pattern in force names receiver_category,
 * and whose scope in force admits the receiver when it lists receivers, where the kind moves the receiver out of the
 * pattern's values or into them. An entry with a matching fixture of a changed receiver whose frozen kind is not the one
 * the draft gives it is listed as widens instead (R14: the recheck drops receiver_category), unless the entry's review
 * says that fixture's case is no longer stored or cannot be read (its frozen copy then answers, and drops nothing). The
 * core reads the stored cases themselves; this listing knows them only from the review's notes. An active entry that
 * cannot be read is listed once as unread while any kind changes.
 */
export function kindChanges(
  before: SiteProfile | undefined,
  after: SiteProfile | undefined,
  items: readonly SiteEntryItem[] | undefined,
): KindChange[] {
  const names: string[] = [];
  for (const p of [after, before])
    for (const r of p?.receivers ?? [])
      if (r && typeof r.name === 'string' && r.name && !names.includes(r.name)) names.push(r.name);
  const changed = names
    .map((name) => ({ name, from: kindIn(before, name), to: kindIn(after, name) }))
    .filter((c) => c.from !== c.to);
  if (!changed.length) return [];
  const out: KindChange[] = [];
  const active = (items ?? [])
    .filter((e) => e.state === 'active')
    .sort((a, b) => Number(a.id.slice(1)) - Number(b.id.slice(1)));
  for (const e of active) {
    const pattern = e.effectivePattern ?? e.content?.pattern;
    if (e.unreadable || !pattern || typeof pattern !== 'object' || Array.isArray(pattern)) {
      out.push({ entry: e.id, title: '', receiver: '', from: '', to: '', change: 'unread' });
      continue;
    }
    if (!('receiver_category' in pattern)) continue;
    const title = e.content?.title || e.title;
    const notes = e.review?.notes ?? [];
    const wide = new Map<string, string>();
    for (const f of e.content?.fixtures ?? []) {
      if (!f || f.expect !== 'match' || !f.conditions || typeof f.conditions !== 'object') continue;
      const name = f.scope?.receiver;
      const c = changed.find((x) => x.name === name);
      if (!c || wide.has(c.name)) continue;
      if (
        notes.some(
          (n) =>
            n.startsWith(`Case ${f.case} is no longer stored`) ||
            n.startsWith(`Case ${f.case} is stored, but`),
        )
      )
        continue;
      if (String(f.conditions.receiver_category ?? '') !== c.to) wide.set(c.name, f.case);
    }
    if (wide.size) {
      for (const c of changed)
        if (wide.has(c.name))
          out.push({
            entry: e.id,
            title,
            receiver: c.name,
            from: c.from,
            to: c.to,
            change: 'widens',
            case: wide.get(c.name),
          });
      continue;
    }
    const allowed: unknown = (pattern as Record<string, unknown>).receiver_category;
    const scope = (e.effectiveScope ?? e.content?.scope) as Record<string, unknown> | undefined;
    const scoped = !!scope && typeof scope === 'object' && 'receiver' in scope;
    for (const c of changed) {
      if (scoped && !among(scope?.receiver, c.name)) continue;
      const was = among(allowed, c.from);
      if (was === among(allowed, c.to)) continue;
      out.push({
        entry: e.id,
        title,
        receiver: c.name,
        from: c.from,
        to: c.to,
        change: was ? 'leaves' : 'enters',
      });
    }
  }
  return out;
}

/** An item in words, as SiteEntry.KindChangeWords gives it. */
export function kindChangeWords(c: KindChange): string {
  const who = !c.entry ? 'an active site entry' : c.title ? `${c.entry} (${c.title})` : c.entry;
  if (c.change === 'unread') return `${who} cannot be read, so it may read the kind`;
  const kinds = `${c.receiver} (${c.from} to ${c.to})`;
  if (c.change === 'widens')
    return `${kinds} is the receiver of case ${c.case ?? ''}, a matching fixture of ${who}: the recheck after the save drops receiver_category from that entry, which then stops its cases whatever the receiver's kind and is flagged for review`;
  return c.change === 'leaves'
    ? `${kinds} leaves the pattern of ${who}, which then no longer stops its cases`
    : `${kinds} comes into the pattern of ${who}, which then stops its cases too`;
}

/** The entries a person reads the changes of: what the save sends as kindChangesRead once they have ticked. */
export const kindChangesRead = (changes: readonly KindChange[]) => [
  ...new Set(changes.map((c) => c.entry).filter(Boolean)),
];

/**
 * The port of SiteEntry.KindChangeRefusal, for the trial's mock of PUT /site-profile: "" or why a save is refused, an
 * entry `changes` lists that `read` does not name.
 */
export function kindChangeRefusal(changes: readonly KindChange[], read: readonly unknown[]): string {
  const words = changes
    .filter((c) => !c.entry || !read.some((r) => String(r) === c.entry))
    .map(kindChangeWords)
    .join('; ');
  return words
    ? `This save changes a receiver's kind that one of the site's own active entries reads (receiver_category): ${words}. Send kindChangesRead with the id of each entry once a person has read what the save does to it (CONTRACTS 6.8, R19)`
    : '';
}
